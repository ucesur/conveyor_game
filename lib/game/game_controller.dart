import 'dart:math';
import 'package:flutter/material.dart';
import '../models/box.dart';
import '../models/box_color.dart';
import '../models/conveyor.dart';
import '../models/falling_box.dart';
import '../models/particle.dart';
import '../models/popup.dart';

enum GameState { menu, playing, paused, gameover }

/// Holds all game state and drives the game loop.
///
/// Port of the React game logic — uses [ChangeNotifier] so the UI rebuilds
/// each frame as [Ticker] pumps new timestamps into [update].
class GameController extends ChangeNotifier {
  // ---- Constants ----
  static const double maintenanceDuration = 2200;
  static const double reverseCheckInterval = 5000;
  static const double reverseChance = 0.4;

  static const double resizeCheckInterval = 6500;
  static const double resizeChance = 0.35;
  static const double resizeAnimationDuration = 900;

  // HUD (score/level/lives + progress bar) occupies y=0..64.
  static const double hudBottom = 64;
  // Colored gate block at each end of a belt is 40px tall.
  static const double gateHeight = 40;
  // Gap between belt bottom and gate top so they read as separate elements.
  static const double gateOffset = 1.0;

  // Derived from gameHeight so belts fill the screen proportionally.
  static double get conveyorMaxHeight => gameHeight - 200;
  static double get conveyorMinHeight => conveyorMaxHeight * 0.45;
  static double get conveyorDefaultHeight => conveyorMaxHeight * 0.8;

  // Position the belt so there is 50px above it for box spawn entry and
  // gateHeight below it for the gate; centers the whole block vertically.
  static double get conveyorTop {
    final available = gameHeight - hudBottom;
    final needed = conveyorMaxHeight + gateHeight + 50;
    final padding = max(0.0, (available - needed) / 2);
    return hudBottom + padding + 50;
  }

  // Game-area coordinate space — call setGameSize() from the layout builder
  // before the user starts a game so setupLevel() gets the right dimensions.
  static double gameWidth = 360;
  static double gameHeight = 600;

  /// Called once the device screen size is known (from LayoutBuilder).
  /// Keeps [gameWidth] at 360 and scales [gameHeight] to match the screen ratio.
  static void setGameSize(double screenW, double screenH) {
    gameWidth = 360;
    gameHeight = screenH * 360 / screenW;
  }

  // ---- State ----
  GameState gameState = GameState.menu;
  int score = 0;
  int lives = 3;
  int level = 1;
  int highScore = 0;
  bool debugSlots = false;
  bool debugPaused = false;
  double _debugFreezeTime = 0;

  void toggleDebugSlots() {
    debugSlots = !debugSlots;
    if (!debugSlots) debugPaused = false;
    notifyListeners();
  }

  void toggleDebugPaused() {
    debugPaused = !debugPaused;
    if (debugPaused) _debugFreezeTime = _lastFrameTime;
    notifyListeners();
  }
  List<Box> boxes = [];
  List<Conveyor> conveyors = [];
  List<FallingBox> fallingBoxes = [];
  int? draggedBoxId;
  List<Popup> popups = [];
  List<Particle> particles = [];
  List<BoxColor> _shuffledColors = [];

  // ---- Internal ----
  int _boxIdCounter = 0;
  int _popupIdCounter = 0;
  double _lastReverseCheck = 0;
  double _lastResizeCheck = 0;
  double _lastFrameTime = 0;
  double _shakeUntil = 0;
  int _comboCount = 0;
  String? _comboColorId;
  // Set when pause begins (to _lastFrameTime) and consumed on the first
  // post-resume update to shift stored timestamps forward by the pause
  // duration — keeps "age since event" continuous across the pause.
  double _pauseStart = 0;

  final Random _random = Random();

  // ---- Easing ----
  double _easeInOut(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3).toDouble() / 2;
  double easeOut(double t) => 1 - pow(1 - t, 3).toDouble();

  // ---- Slot helpers ----
  // Sentinel slotIndex value meaning "past last slot, moving freely to gate".
  static const int _exitSlot = 9999;

  // Side length of every box and slot pitch — one constant governs both so
  // changing it scales box count per belt automatically.
  static const double boxSize = 40.0;

  // How many box-sized slots fit on a belt of height [convH].
  static int _numSlots(double convH) => max(1, (convH / boxSize).floor());

  // Y coordinate of the top-left corner of slot [s] on [conv].
  // Slots are always top-anchored (conv.y + s*boxSize) for both directions so
  // that resize animations — which change convH but not conv.y — don't shift
  // existing slots and cause boxes to drift the wrong way.
  //
  // Direction semantics:
  //   down → slot 0 = top (entry), slot N-1 = bottom (exit toward gate)
  //   up   → slot 0 = top (exit toward gate), slot N-1 = bottom (entry)
  //
  // convH is accepted but unused — kept so call sites that already pass it
  // don't need to be updated.
  // ignore: avoid_unused_parameters
  double _slotY(Conveyor conv, int s, double convH) => conv.y + s * boxSize;

  // Scrolled slot position — matches the visual belt surface scroll so ghosts,
  // debug markers, and landed boxes all use the same coordinate.
  double _slotYScrolled(Conveyor conv, int s, double convH) {
    final phase = beltOffset(conv.speed, conv.direction) % boxSize;
    return conv.y + s * boxSize + phase;
  }

  // Phase-adjusted slot index from a box's Y. Subtracting the current belt
  // phase before dividing gives the correct slot even as the belt scrolls.
  int _rawSlot(Conveyor conv, double y) {
    final phase = beltOffset(conv.speed, conv.direction) % boxSize;
    return ((y - conv.y - phase) / boxSize).floor();
  }

  // Logical occupancy check — used by _moveBoxes for belt advancement.
  // A box owns exactly the slot it is heading toward (slotIndex), so queued
  // boxes can start moving the instant the slot ahead is logically vacated,
  // giving continuous belt flow with no artificial stall.
  bool _isSlotFree(Conveyor conv, int s, int excludeId) {
    final isDown = conv.direction == ConveyorDirection.down;
    final convH = getCurrentHeight(conv, _lastFrameTime);
    final entrySlot = isDown ? 0 : _numSlots(convH) - 1;
    return !boxes.any((b) {
      if (b.id == excludeId) return false;
      if (b.conveyorId != conv.id) return false;
      if (!b.onConveyor) return false;
      if (b.slotIndex == null) return s == entrySlot;
      if (b.slotIndex == _exitSlot) return false;
      return b.slotIndex == s;
    });
  }

  // Physical occupancy check — used only when validating a throw or snap-back
  // target. Slot [s] is considered occupied whenever any on-belt box's bounding
  // rect [b.y, b.y+50] overlaps the slot's rect [slotTop, slotTop+50].
  // This is exact: a box that has fully left a slot (b.y >= slotTop+50) no
  // longer blocks it, so the earliest possible landing for the thrown box is
  // flush-touching (0 px gap) — never overlapping.
  bool _isSlotFreeStrict(Conveyor conv, int s, int excludeId) {
    return !boxes.any((b) {
      if (b.id == excludeId) return false;
      if (b.conveyorId != conv.id) return false;
      if (!b.onConveyor) return false;
      return _rawSlot(conv, b.y) == s;
    });
  }

  // Index of the slot whose Y is closest to [y] on [conv].
  int _closestSlotIndex(Conveyor conv, double y, double convH, int nSlots) {
    int best = 0;
    double bestDist = double.infinity;
    for (int s = 0; s < nSlots; s++) {
      final dist = (y - _slotYScrolled(conv, s, convH)).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = s;
      }
    }
    return best.clamp(0, nSlots - 1);
  }

  /// Returns the current animated height of a conveyor given the time [now].
  double getCurrentHeight(Conveyor conv, double now) {
    if (!conv.resizing) return conv.height;
    final elapsed = now - conv.resizeStart;
    final t = min(1.0, elapsed / resizeAnimationDuration);
    final eased = _easeInOut(t);
    return conv.fromHeight + (conv.toHeight - conv.fromHeight) * eased;
  }

  // ---- Level progression ----
  int pointsForLevel(int lvl) {
    int total = 0;
    for (int i = 1; i < lvl; i++) {
      total += 6 + i * 4;
    }
    return total;
  }

  int levelFromScore(int s) {
    int lvl = 1;
    while (pointsForLevel(lvl + 1) <= s) {
      lvl++;
    }
    return lvl;
  }

  // ---- Setup ----
  // X position of slot [i] in the fixed max-5 layout.
  static double _beltSlotX(int i) {
    const conveyorWidth = 52.0;
    const gap = 14.0;
    const maxCount = 5;
    const totalWidth = maxCount * conveyorWidth + (maxCount - 1) * gap;
    final startX = (gameWidth - totalWidth) / 2;
    return startX + i * (conveyorWidth + gap);
  }

  // Order in which slots are filled. Starts at slot 1 so the first 2 belts
  // land in the center of the 5-slot grid, then grows right, then fills slot 0.
  static const List<int> _slotFillOrder = [1, 2, 3, 4, 0];

  // Two belts are visually adjacent when their left edges are one slot apart.
  bool _areAdjacentBelts(Conveyor a, Conveyor b) =>
      (a.x - b.x).abs() < 52.0 + 14.0 + 1;

  void setupLevel(int lvl) {
    final numConveyors = min(2 + ((lvl - 1) ~/ 2), 5);
    final activeColors = _shuffledColors.sublist(0, numConveyors);

    const conveyorWidth = 52.0;
    final baseSpeed = 0.28 + lvl * 0.035;
    final List<Conveyor> newConveyors = [];
    for (int i = 0; i < activeColors.length; i++) {
      final color = activeColors[i];
      final direction = _random.nextBool()
          ? ConveyorDirection.down
          : ConveyorDirection.up;
      final speedMultiplier = 0.75 + _random.nextDouble() * 0.7;
      final heightRoll = _random.nextDouble();
      double height;
      if (heightRoll < 0.25) {
        height = conveyorMinHeight + _random.nextDouble() * 60;
      } else if (heightRoll < 0.75) {
        height = conveyorDefaultHeight + (_random.nextDouble() - 0.5) * 40;
      } else {
        height = conveyorMaxHeight - _random.nextDouble() * 30;
      }

      newConveyors.add(Conveyor(
        id: i,
        color: color,
        x: _beltSlotX(_slotFillOrder[i]),
        y: conveyorTop,
        width: conveyorWidth,
        height: height,
        speed: baseSpeed * speedMultiplier,
        direction: direction,
      ));
    }

    conveyors = newConveyors;
    boxes = [];
    fallingBoxes = [];
    particles = [];
    final now = _lastFrameTime;
    _lastReverseCheck = now + 3000;
    _lastResizeCheck = now + 4500;
  }

  void startGame() {
    score = 0;
    lives = 4;
    level = 1;
    popups = [];
    particles = [];
    fallingBoxes = [];
    draggedBoxId = null;
    _pauseStart = 0;
    _shakeUntil = 0;
    _comboCount = 0;
    _comboColorId = null;
    _shuffledColors = List.of(BoxColor.all)..shuffle(_random);
    setupLevel(1);
    gameState = GameState.playing;
    notifyListeners();
  }

  void pauseGame() {
    if (gameState != GameState.playing) return;
    // Cancel any in-flight drag so the user isn't left holding a box when
    // the overlay appears — handleEnd snaps the box back to its source.
    if (draggedBoxId != null) handleEnd();
    _pauseStart = _lastFrameTime;
    gameState = GameState.paused;
    notifyListeners();
  }

  void resumeGame() {
    if (gameState != GameState.paused) return;
    gameState = GameState.playing;
    // _pauseStart is consumed by the next update(now) to shift timestamps.
    notifyListeners();
  }

  void exitToMenu() {
    gameState = GameState.menu;
    _pauseStart = 0;
    boxes = [];
    fallingBoxes = [];
    popups = [];
    particles = [];
    draggedBoxId = null;
    notifyListeners();
  }

  void _shiftTimestamps(double delta) {
    if (delta <= 0) return;
    _lastReverseCheck += delta;
    _lastResizeCheck += delta;
    _lastFrameTime += delta;
    if (_shakeUntil > 0) _shakeUntil += delta;
    for (final conv in conveyors) {
      if (conv.maintenance) conv.maintenanceEnd += delta;
      if (conv.resizing) conv.resizeStart += delta;
    }
    for (final box in boxes) {
      if (box.dragStartTime != null) {
        box.dragStartTime = box.dragStartTime! + delta;
      }
      if (box.throwAnim != null) {
        box.throwAnim!.startTime += delta;
      }
    }
    for (final popup in popups) {
      popup.createdAt += delta;
    }
    for (final particle in particles) {
      particle.startTime += delta;
    }
  }

  void _addPopup(double x, double y, String text, Color color,
      {double size = 22}) {
    final id = _popupIdCounter++;
    popups.add(Popup(
      id: id,
      x: x,
      y: y,
      text: text,
      color: color,
      size: size,
      createdAt: _lastFrameTime,
    ));
  }

  // ---- Frame update ----
  void update(double now) {
    // While paused, freeze everything: don't advance _lastFrameTime (so
    // painter animations driven by currentTime also freeze) and don't
    // notify — the overlay was already posted when gameState flipped.
    if (gameState == GameState.paused) return;

    // First frame after resume: shift every stored timestamp forward by
    // the pause duration so elapsed-time comparisons stay consistent.
    if (_pauseStart != 0) {
      _shiftTimestamps(now - _pauseStart);
      _pauseStart = 0;
    }

    final dt = _lastFrameTime == 0 ? 16.0 : min(now - _lastFrameTime, 50.0);
    _lastFrameTime = now;

    // Drop expired popups (800ms lifetime)
    popups.removeWhere((p) => now - p.createdAt > 800);

    if (gameState != GameState.playing) {
      _updateParticles(now, dt);
      notifyListeners();
      return;
    }

    if (debugPaused) {
      _updateThrows(now);
      _updateParticles(now, dt);
      _updateFallingBoxes(dt);
      notifyListeners();
      return;
    }

    _handleReversals(now);
    _handleResizes(now);
    _endMaintenance(now);
    _endResize(now);
    _updateThrows(now);
    _updateParticles(now, dt);
    _updateFallingBoxes(dt);
    _spawnBoxes(now);
    _moveBoxes(now, dt);
    _checkLevelUp(now);

    notifyListeners();
  }

  void _handleReversals(double now) {
    if (now - _lastReverseCheck <= reverseCheckInterval) return;
    _lastReverseCheck = now;
    if (conveyors.length <= 1 || _random.nextDouble() >= reverseChance) return;

    // Only reverse belts that have no box currently on/approaching them,
    // which avoids sending an in-flight box through the wrong gate.
    final candidates = conveyors.where((c) {
      if (c.maintenance || c.resizing) return false;
      final hasBox = boxes.any(
          (b) => b.conveyorId == c.id && (b.onConveyor || b.entering));
      return !hasBox;
    }).toList();

    if (candidates.isEmpty) return;

    final target = candidates[_random.nextInt(candidates.length)];

    target.pendingDirection = target.direction == ConveyorDirection.down
        ? ConveyorDirection.up
        : ConveyorDirection.down;
    target.maintenance = true;
    target.maintenanceEnd = now + maintenanceDuration;

    _addPopup(target.x + target.width / 2, target.y + 10, '⚠',
        const Color(0xFFFBBF24),
        size: 28);
  }

  void _handleResizes(double now) {
    if (now - _lastResizeCheck <= resizeCheckInterval) return;
    _lastResizeCheck = now;
    if (conveyors.isEmpty || _random.nextDouble() >= resizeChance) return;

    final candidates =
        conveyors.where((c) => !c.maintenance && !c.resizing).toList();
    if (candidates.isEmpty) return;

    final target = candidates[_random.nextInt(candidates.length)];
    final currentH = target.height;
    double newH;
    if (currentH < conveyorMaxHeight * 0.55) {
      newH = conveyorDefaultHeight +
          _random.nextDouble() * (conveyorMaxHeight - conveyorDefaultHeight);
    } else if (currentH > conveyorMaxHeight * 0.9) {
      newH = conveyorMinHeight +
          _random.nextDouble() * (conveyorDefaultHeight - conveyorMinHeight);
    } else {
      newH = _random.nextDouble() < 0.5
          ? conveyorMinHeight + _random.nextDouble() * 50
          : conveyorMaxHeight - _random.nextDouble() * 40;
    }
    newH = max(conveyorMinHeight, min(conveyorMaxHeight, newH));

    target.resizing = true;
    target.resizeStart = now;
    target.fromHeight = target.height;
    target.toHeight = newH;

    final resizeIcon = newH > currentH ? '↕+' : '↕−';
    _addPopup(target.x + target.width / 2, target.y + 10, resizeIcon,
        const Color(0xFF06B6D4),
        size: 22);
  }

  void _endMaintenance(double now) {
    for (final conv in conveyors) {
      if (conv.maintenance && now >= conv.maintenanceEnd) {
        conv.direction = conv.pendingDirection ?? conv.direction;
        conv.maintenance = false;
        conv.pendingDirection = null;
        conv.maintenanceEnd = 0;
      }
    }
  }

  void _endResize(double now) {
    for (final conv in conveyors) {
      if (conv.resizing && now - conv.resizeStart >= resizeAnimationDuration) {
        conv.height = conv.toHeight;
        conv.resizing = false;
        conv.fromHeight = conv.toHeight;
      }
    }
  }

  void _spawnBoxes(double now) {
    if (conveyors.isEmpty) return;
    const bsize = GameController.boxSize;

    for (final conv in conveyors) {
      if (conv.maintenance) continue;
      final isDown = conv.direction == ConveyorDirection.down;
      final convH = getCurrentHeight(conv, now);
      final entrySlot = isDown ? 0 : _numSlots(convH) - 1;
      if (!_isSlotFree(conv, entrySlot, -1)) continue;

      final colorIdx = _random.nextInt(conveyors.length);
      boxes.add(Box(
        id: _boxIdCounter++,
        x: conv.x + (conv.width - bsize) / 2,
        y: isDown ? conv.y - bsize : conv.y + convH,
        conveyorId: conv.id,
        color: conveyors[colorIdx].color,
        size: bsize,
        onConveyor: true,
        entering: true,
      ));
    }
  }

  void _moveBoxes(double now, double dt) {
    int wrongHits = 0;
    final List<Box> keep = [];

    for (final box in boxes) {
      if (box.id == draggedBoxId) { keep.add(box); continue; }
      // During flight onConveyor==false, so the !onConveyor guard below
      // already skips the box. During squash/settle onConveyor==true and
      // _updateThrows no longer writes box.y — let the slot logic run so
      // the box starts moving the moment it lands, not 180ms later.
      if (!box.onConveyor) { keep.add(box); continue; }

      final conv = _findConveyor(box.conveyorId);
      if (conv == null) { keep.add(box); continue; }
      if (conv.maintenance) { keep.add(box); continue; }

      final convH = getCurrentHeight(conv, now);
      final nSlots = _numSlots(convH);
      final moveAmount = conv.speed * dt * 0.1;
      final isDown = conv.direction == ConveyorDirection.down;

      // Exit phase: past last slot, sliding freely into the gate.
      if (box.slotIndex == _exitSlot) {
        final newY = box.y + (isDown ? moveAmount : -moveAmount);
        final gateY = isDown ? conv.y + convH : conv.y;
        if (isDown ? newY + box.size >= gateY : newY <= gateY) {
          wrongHits += _processGateHit(box, conv, convH, isDown);
          continue;
        }
        box.y = newY;
        keep.add(box);
        continue;
      }

      // Entry slot: slot 0 for direction=down (top), slot N-1 for direction=up (bottom).
      final entrySlot = isDown ? 0 : nSlots - 1;

      // Entering phase: box outside belt, moving toward the entry slot.
      if (box.slotIndex == null) {
        final targetY = _slotY(conv, entrySlot, convH);
        final dist = (box.y - targetY).abs();
        if (dist <= moveAmount + 0.5) {
          if (_isSlotFree(conv, entrySlot, box.id)) {
            box.y = _slotYScrolled(conv, entrySlot, convH);
            box.slotIndex = entrySlot;
            box.entering = false;
          }
          // else wait just outside for the entry slot to clear
        } else {
          box.y += (isDown ? 1.0 : -1.0) * moveAmount;
        }
        keep.add(box);
        continue;
      }

      // On belt: move continuously at belt speed, same rate as the belt surface.
      box.y += (isDown ? 1.0 : -1.0) * moveAmount;

      // Derive slot index from phase-adjusted Y so it tracks scrolled slots.
      final rawSlot = _rawSlot(conv, box.y);
      if (rawSlot >= nSlots || rawSlot < 0) {
        box.slotIndex = _exitSlot;
      } else {
        box.slotIndex = rawSlot.clamp(0, nSlots - 1);
      }

      keep.add(box);
    }

    // Collision safety: boxes move at the same speed so they stay separated
    // under normal conditions, but a freshly thrown box may land too close.
    // Process exit-first so the leading box takes priority.
    for (final conv in conveyors) {
      final isDown = conv.direction == ConveyorDirection.down;
      final beltBoxes = keep
          .where((b) =>
              b.conveyorId == conv.id &&
              b.onConveyor &&
              b.slotIndex != null &&
              b.slotIndex != _exitSlot &&
              b.id != draggedBoxId)
          .toList();
      beltBoxes.sort(
          (a, b) => isDown ? b.y.compareTo(a.y) : a.y.compareTo(b.y));
      for (int i = 1; i < beltBoxes.length; i++) {
        final ahead = beltBoxes[i - 1];
        final curr = beltBoxes[i];
        if (isDown) {
          if (curr.y + curr.size > ahead.y) curr.y = ahead.y - curr.size;
        } else {
          if (curr.y < ahead.y + ahead.size) curr.y = ahead.y + ahead.size;
        }
        final rs = _rawSlot(conv, curr.y);
        final ns = _numSlots(getCurrentHeight(conv, now));
        curr.slotIndex =
            (rs >= ns || rs < 0) ? _exitSlot : rs.clamp(0, ns - 1);
      }
    }

    boxes = keep;

    if (wrongHits > 0) {
      lives -= wrongHits;
      _shakeUntil = _lastFrameTime + 280;
      if (lives <= 0) {
        lives = 0;
        gameState = GameState.gameover;
        if (score > highScore) highScore = score;
      }
    }
  }

  // Scores a gate hit for [box], spawns the falling animation, returns 1 on wrong hit.
  int _processGateHit(Box box, Conveyor conv, double convH, bool isDown) {
    final gateY = isDown ? conv.y + convH : conv.y;
    final popupY = isDown ? gateY - 10 : gateY + 10;
    int wrong = 0;
    if (box.color.id == conv.color.id) {
      if (_comboColorId == box.color.id) {
        _comboCount++;
      } else {
        _comboCount = 1;
        _comboColorId = box.color.id;
      }
      final mult = min(_comboCount, 4);
      score += mult;
      final label = _comboCount >= 2 ? '+$mult  x$_comboCount' : '+1';
      _addPopup(conv.x + conv.width / 2, popupY, label,
          const Color(0xFF22C55E),
          size: _comboCount >= 2 ? 26 : 22);
    } else {
      wrong = 1;
      _comboCount = 0;
      _comboColorId = null;
      _addPopup(conv.x + conv.width / 2, popupY, '✗',
          const Color(0xFFEF4444));
    }
    final fbStartY = isDown ? gateY - box.size : gateY;
    final fbDisappearY = isDown
        ? gateY + gateOffset + gateHeight
        : gateY - gateOffset - gateHeight;
    fallingBoxes.add(FallingBox(
      x: box.x,
      y: fbStartY,
      vy: isDown ? 0.4 : -0.4,
      size: box.size,
      color: box.color,
      startY: fbStartY,
      disappearY: fbDisappearY,
    ));
    return wrong;
  }

  void _updateFallingBoxes(double dt) {
    fallingBoxes.removeWhere((fb) => fb.disappearY >= fb.startY
        ? fb.y >= fb.disappearY
        : fb.y <= fb.disappearY);
    for (final fb in fallingBoxes) {
      fb.vy += 0.001 * dt;
      fb.y += fb.vy * dt;
    }
  }

  void _checkLevelUp(double now) {
    if (gameState != GameState.playing) return;
    final newLevel = levelFromScore(score);
    if (newLevel > level) {
      final oldBase = 0.28 + level * 0.035;
      final newBase = 0.28 + newLevel * 0.035;
      level = newLevel;

      for (final conv in conveyors) {
        conv.speed = conv.speed * newBase / oldBase;
      }

      final newCount = min(2 + ((level - 1) ~/ 2), 5);
      if (newCount > conveyors.length) {
        _addBelt(newCount, newBase, now);
      }

      _addPopup(gameWidth / 2, hudBottom + 30, 'LEVEL $level',
          const Color(0xFFFBBF24), size: 28);
    }
  }

  void _addBelt(int newCount, double baseSpeed, double now) {
    final oldCount = conveyors.length;
    final newColor = _shuffledColors[oldCount];
    final direction =
        _random.nextBool() ? ConveyorDirection.down : ConveyorDirection.up;
    final speedMultiplier = 0.75 + _random.nextDouble() * 0.7;
    conveyors.add(Conveyor(
      id: oldCount,
      color: newColor,
      x: _beltSlotX(_slotFillOrder[oldCount]),
      y: conveyorTop,
      width: 52.0,
      height: conveyorDefaultHeight,
      speed: baseSpeed * speedMultiplier,
      direction: direction,
    ));
  }

  Conveyor? _findConveyor(int id) {
    for (final c in conveyors) {
      if (c.id == id) return c;
    }
    return null;
  }

  // ---- Drag handling (called from gesture recognizer) ----
  void handleStart(Offset pos) {
    if (gameState != GameState.playing) return;
    // Iterate from top-most drawn box downward so the user picks up
    // the visually-front-most box when stacks overlap.
    for (int i = boxes.length - 1; i >= 0; i--) {
      final b = boxes[i];
      if (b.throwAnim != null) continue;
      if (pos.dx >= b.x - 12 &&
          pos.dx <= b.x + b.size + 12 &&
          pos.dy >= b.y - 12 &&
          pos.dy <= b.y + b.size + 12) {
        draggedBoxId = b.id;
        b.onConveyor = false;
        b.slotIndex = null;
        b.sourceConveyorId = b.conveyorId;
        b.dragStartTime = _lastFrameTime;
        b.x = pos.dx - b.size / 2;
        b.y = pos.dy - b.size / 2;
        b.trail = [];
        notifyListeners();
        return;
      }
    }
  }

  void handleMove(Offset pos) {
    if (draggedBoxId == null) return;
    final box = _findBox(draggedBoxId!);
    if (box == null) return;

    final newX = pos.dx - box.size / 2;
    final newY = pos.dy - box.size / 2;
    final prevX = box.x;
    final prevY = box.y;
    final vx = newX - prevX;
    final vy = newY - prevY;

    // Record a position trail (up to 6 points) for the motion streak effect
    final trail = box.trail ?? [];
    final bool shouldAdd = trail.isEmpty ||
        (trail.last.dx - prevX).abs() > 3 ||
        (trail.last.dy - prevY).abs() > 3;
    if (shouldAdd) {
      trail.add(Offset(prevX, prevY));
      if (trail.length > 6) trail.removeAt(0);
    }

    box.x = newX;
    box.y = newY;
    box.vx = vx;
    box.vy = vy;
    box.trail = trail;
    notifyListeners();
  }

  void handleEnd() {
    if (draggedBoxId == null) return;
    final boxId = draggedBoxId!;
    final box = _findBox(boxId);
    if (box == null) {
      draggedBoxId = null;
      notifyListeners();
      return;
    }

    final now = _lastFrameTime;

    // Swipe (fling) detection: quick horizontal flick at release.
    // Using the last pointer-move delta alone misses natural flicks where
    // the finger decelerates in the final ~16ms before lift, so average
    // over the tail of the trail (up to 3 samples) to recover the user's
    // sustained direction. Long-press / slow-drag keeps the avg small and
    // falls through to the normal drop logic below.
    double swipeVx = box.vx ?? 0.0;
    double swipeVy = box.vy ?? 0.0;
    final trail = box.trail;
    if (trail != null && trail.isNotEmpty) {
      final n = min(3, trail.length);
      final oldest = trail[trail.length - n];
      swipeVx = (box.x - oldest.dx) / n;
      swipeVy = (box.y - oldest.dy) / n;
    }
    const swipeThreshold = 3.0;
    final horizontallyDominant = swipeVx.abs() > swipeVy.abs();
    if (swipeVx.abs() >= swipeThreshold &&
        horizontallyDominant &&
        box.sourceConveyorId != null) {
      final sourceConv = _findConveyor(box.sourceConveyorId!);
      final goRight = swipeVx > 0;
      final targetConv = sourceConv == null
          ? null
          : conveyors.where((c) {
              if (!_areAdjacentBelts(sourceConv, c)) return false;
              return goRight ? c.x > sourceConv.x : c.x < sourceConv.x;
            }).firstOrNull;
      if (targetConv != null && !targetConv.maintenance) {
        final targetH = getCurrentHeight(targetConv, now);
        final landingY = _findFreeSlot(box, targetConv, targetH);
        if (landingY != null) {
          _startThrow(box, targetConv, landingY, now);
          draggedBoxId = null;
          notifyListeners();
          return;
        }
      }
      // Swipe toward an invalid / blocked lane — animate back to source.
      _snapBackToSource(box, now);
      _addPopup(box.x + box.size / 2, box.y - 10, '✗',
          const Color(0xFFEF4444),
          size: 16);
      draggedBoxId = null;
      notifyListeners();
      return;
    }

    final boxCenterX = box.x + box.size / 2;
    final boxCenterY = box.y + box.size / 2;

    Conveyor? targetConv;
    for (final conv in conveyors) {
      final currentH = getCurrentHeight(conv, now);
      if (boxCenterX >= conv.x - 10 &&
          boxCenterX <= conv.x + conv.width + 10 &&
          boxCenterY >= conv.y &&
          boxCenterY <= conv.y + currentH) {
        targetConv = conv;
        break;
      }
    }

    // Rule 1: can't drop on a belt that's under maintenance
    if (targetConv != null && targetConv.maintenance) {
      _snapBackToSource(box, now);
      draggedBoxId = null;
      notifyListeners();
      return;
    }

    // Rule 2: box can only hop to the immediately adjacent conveyor (or the same)
    if (targetConv != null && box.sourceConveyorId != null) {
      final sameConv = targetConv.id == box.sourceConveyorId;
      final src = _findConveyor(box.sourceConveyorId!);
      final isNeighbor = src != null && _areAdjacentBelts(src, targetConv);
      if (!sameConv && !isNeighbor) {
        _snapBackToSource(box, now);
        _addPopup(boxCenterX, boxCenterY - 20, 'TOO FAR',
            const Color(0xFFEF4444),
            size: 14);
        draggedBoxId = null;
        notifyListeners();
        return;
      }
    }

    if (targetConv != null) {
      final currentH = getCurrentHeight(targetConv, now);
      final landingY = _findFreeSlot(box, targetConv, currentH);
      if (landingY == null) {
        _snapBackToSource(box, now);
      } else {
        _startThrow(box, targetConv, landingY, now);
      }
    } else {
      // Released outside any conveyor → animate back to source
      _snapBackToSource(box, now);
    }

    draggedBoxId = null;
    notifyListeners();
  }

  /// Kicks off a throw animation back to the box's source belt. Falls
  /// back to removing the box if the source belt no longer exists (which
  /// shouldn't happen mid-game but keeps the controller resilient).
  void _snapBackToSource(Box box, double now) {
    if (box.sourceConveyorId == null) {
      boxes.removeWhere((b) => b.id == box.id);
      return;
    }
    final sourceConv = _findConveyor(box.sourceConveyorId!);
    if (sourceConv == null) {
      boxes.removeWhere((b) => b.id == box.id);
      return;
    }
    final h = getCurrentHeight(sourceConv, now);
    final nSlots = _numSlots(h);
    final entrySlot = sourceConv.direction == ConveyorDirection.down ? 0 : nSlots - 1;
    final landingY =
        _findFreeSlot(box, sourceConv, h) ?? _slotYScrolled(sourceConv, entrySlot, h);
    _startThrow(box, sourceConv, landingY, now);
  }

  Box? _findBox(int id) {
    for (final b in boxes) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Looks for a vacant Y position on [targetConv] near the box's current y.
  /// Returns null if 20 nudges against the belt's travel direction don't find
  /// a slot. Mirrors the same policy as the drop path in [handleEnd].
  double? _findFreeSlot(Box box, Conveyor targetConv, double currentH) {
    final nSlots = _numSlots(currentH);
    final closestSlot =
        _closestSlotIndex(targetConv, box.y, currentH, nSlots);
    for (int radius = 0; radius < nSlots; radius++) {
      final candidates =
          radius == 0 ? [closestSlot] : [closestSlot - radius, closestSlot + radius];
      for (final s in candidates) {
        if (s < 0 || s >= nSlots) continue;
        if (_isSlotFreeStrict(targetConv, s, box.id)) {
          return _slotYScrolled(targetConv, s, currentH);
        }
      }
    }
    return null;
  }

  /// Primes [box] for a throw to [landingY] on [targetConv]. The actual
  /// per-frame interpolation runs in [_updateThrows]; clearing drag fields
  /// here keeps the painter from rendering pickup state during flight.
  void _startThrow(
      Box box, Conveyor targetConv, double landingY, double now) {
    box.throwAnim = ThrowAnim(
      startTime: now,
      startX: box.x,
      startY: box.y,
      endX: targetConv.x + (targetConv.width - box.size) / 2,
      endY: landingY,
      targetConvId: targetConv.id,
    );
    box.onConveyor = false;
    box.sourceConveyorId = null;
    box.dragStartTime = null;
  }

  /// Advances throw animations: interpolates box position during flight,
  /// commits the box to its target belt at landing (spawning dust once),
  /// then clears the anim after squash + settle so the box rejoins normal
  /// belt movement on the same frame.
  void _updateThrows(double now) {
    for (final box in boxes) {
      final anim = box.throwAnim;
      if (anim == null) continue;
      final elapsed = now - anim.startTime;

      if (elapsed < anim.flightDuration) {
        final t = elapsed / anim.flightDuration;
        final eased = easeOut(t);
        box.x = anim.startX + (anim.endX - anim.startX) * eased;
        box.y = anim.startY + (anim.endY - anim.startY) * eased;
        continue;
      }

      // Flight finished — lock to landing spot. The first frame we cross
      // this boundary commits the box to its target belt and spawns dust;
      // subsequent frames during squash/settle just hold position.
      if (!box.onConveyor || box.conveyorId != anim.targetConvId) {
        box.x = anim.endX;
        box.y = anim.endY;
        box.onConveyor = true;
        box.conveyorId = anim.targetConvId;
        box.entering = false;
        final tConv = _findConveyor(anim.targetConvId);
        if (tConv != null) {
          final convH = getCurrentHeight(tConv, now);
          final ns = _numSlots(convH);
          final rs = _rawSlot(tConv, box.y);
          box.slotIndex = (rs < 0 || rs >= ns) ? _exitSlot : rs.clamp(0, ns - 1);
        }
        _spawnDust(box.x + box.size / 2, box.y + box.size, box.color);
      }

      if (elapsed >= anim.totalDuration) {
        box.throwAnim = null;
        box.trail = null;
        box.vx = null;
        box.vy = null;
      }
    }
  }

  /// Visual transform for [box]'s body during a throw. Returns identity
  /// when no animation is active, so the painter can call this unconditionally.
  ThrowPose throwPose(Box box) {
    final anim = box.throwAnim;
    if (anim == null) return const ThrowPose();
    final elapsed = currentTime - anim.startTime;

    if (elapsed < anim.flightDuration) {
      final t = elapsed / anim.flightDuration;
      final spin = (currentTime * 0.6) % 360;
      final dx = anim.endX - anim.startX;
      final tilt = max(-30.0, min(30.0, dx * 0.25));
      final scale = 1.35 - 0.35 * t;
      final lift = -8 * (1 - t);
      return ThrowPose(
        scaleX: scale,
        scaleY: scale,
        rotation: spin + tilt,
        liftY: lift,
      );
    }

    final squashEnd = anim.flightDuration + anim.squashDuration;
    if (elapsed < squashEnd) {
      // Strong impact stretch easing back toward 1.0
      final t = (elapsed - anim.flightDuration) / anim.squashDuration;
      final intensity = 1 - t;
      return ThrowPose(
        scaleX: 1.0 + intensity * 0.25,
        scaleY: 1.0 - intensity * 0.20,
      );
    }

    // Settle: half-sine bounce back to rest
    final t = (elapsed - squashEnd) / anim.settleDuration;
    final bounce = sin(t * pi) * 0.06;
    return ThrowPose(scaleX: 1.0 + bounce, scaleY: 1.0 + bounce);
  }

  /// Sprays a small upward burst of light-colored particles to sell the
  /// box-landing impact. Uses the box's [BoxColor.light] so each color's
  /// dust reads as related to its box.
  void _spawnDust(double x, double y, BoxColor color) {
    for (int i = 0; i < 6; i++) {
      final angle = -pi / 2 + (_random.nextDouble() - 0.5) * pi * 0.7;
      final speed = 0.05 + _random.nextDouble() * 0.08;
      particles.add(Particle(
        x: x + (_random.nextDouble() - 0.5) * 6,
        y: y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        gravity: 0.0003,
        drag: 0.96,
        size: 2.5 + _random.nextDouble() * 1.5,
        color: color.light,
        startTime: _lastFrameTime,
        lifetime: 400 + _random.nextDouble() * 200,
      ));
    }
  }

  void _updateParticles(double now, double dt) {
    if (particles.isEmpty) return;
    particles.removeWhere((p) => now - p.startTime >= p.lifetime);
    for (final p in particles) {
      p.vy += p.gravity * dt;
      p.vx *= p.drag;
      p.vy *= p.drag;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
    }
  }

  // ---- Helpers exposed to the UI painter ----
  double beltOffset(double speed, ConveyorDirection direction) {
    // Signed, unmodulated scroll distance. Caller mods by the appropriate
    // period (tile height for sprite belts, 24 for the procedural stripe
    // pattern) — modding here would force every belt skin onto the same
    // period and snap tile-based belts backward each time the scroll crosses
    // that period. Factor must match the 0.1 used in _moveBoxes so stripes
    // scroll at the same px/ms rate boxes travel along the belt.
    final t = debugPaused ? _debugFreezeTime : _lastFrameTime;
    final raw = t * speed * 0.1;
    return direction == ConveyorDirection.down ? raw : -raw;
  }

  double maintenanceFlash() => 0.5 + 0.5 * sin(_lastFrameTime * 0.01);
  double resizeFlash() => 0.5 + 0.5 * sin(_lastFrameTime * 0.015);
  double get currentTime => _lastFrameTime;

  Offset get shakeOffset {
    if (_lastFrameTime >= _shakeUntil) return Offset.zero;
    final t = (_shakeUntil - _lastFrameTime) / 280.0;
    final amplitude = 7.0 * t;
    return Offset(
      sin(_lastFrameTime * 0.09) * amplitude,
      sin(_lastFrameTime * 0.06 + 1.0) * amplitude,
    );
  }

  /// Belts reachable from the currently-dragged box: source + visual neighbors.
  Set<int>? get allowedTargets {
    if (draggedBoxId == null) return null;
    final b = _findBox(draggedBoxId!);
    if (b == null || b.sourceConveyorId == null) return null;
    final source = _findConveyor(b.sourceConveyorId!);
    if (source == null) return null;
    return {
      source.id,
      for (final c in conveyors)
        if (_areAdjacentBelts(source, c)) c.id,
    };
  }

  /// Landing Y for the dragged box on each valid, non-maintenance belt.
  /// Returns null when nothing is being dragged.
  Map<int, double>? get landingSlots {
    if (draggedBoxId == null) return null;
    final b = _findBox(draggedBoxId!);
    if (b == null || b.sourceConveyorId == null) return null;
    final targets = allowedTargets!;
    final result = <int, double>{};
    for (final conv in conveyors) {
      if (!targets.contains(conv.id)) continue;
      if (conv.maintenance) continue;
      final h = getCurrentHeight(conv, _lastFrameTime);
      final slot = _findFreeSlot(b, conv, h);
      if (slot != null) result[conv.id] = slot;
    }
    return result;
  }
}
