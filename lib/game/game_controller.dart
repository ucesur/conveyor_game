import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/box.dart';
import '../models/box_color.dart';
import '../models/conveyor.dart';
import '../models/falling_box.dart';
import '../models/particle.dart';
import '../models/belt_explosion.dart';
import '../models/combo_area.dart';
import '../models/popup.dart';
import '../models/special_type.dart';
import 'game_config.dart';

enum GameState { menu, playing, paused, gameover }

/// Holds all game state and drives the game loop.
///
/// Port of the React game logic — uses [ChangeNotifier] so the UI rebuilds
/// each frame as [Ticker] pumps new timestamps into [update].
class GameController extends ChangeNotifier {
  // ---- Constants ----
  static const double maintenanceDuration = 2200;
  static const double reverseCheckInterval = 12000;
  static const double reverseChance = 0.25;

  static const double icyFreezeDuration = 4000;

  static const double resizeCheckInterval = 6500;
  static const double resizeChance = 0.35;
  static const double resizeAnimationDuration = 900;

  static const double hudBottom = GameConfig.hudBottom;
  static const double gateHeight = GameConfig.gateHeight;
  static const double gateOffset = GameConfig.gateOffset;

  // Derived from gameHeight so belts fill the screen proportionally.
  static double get conveyorMaxHeight => gameHeight - 350;
  static double get conveyorMinHeight => max(
      GameConfig.conveyorMinSlots * boxSize, conveyorMaxHeight * 0.45);
  static double get conveyorDefaultHeight => conveyorMaxHeight * 0.8;

  static double get conveyorTop => gameHeight * GameConfig.conveyorTopFraction;

  // Game-area coordinate space — call setGameSize() from the layout builder
  // before the user starts a game so setupLevel() gets the right dimensions.
  static double gameWidth = GameConfig.baseWidth;
  static double gameHeight = GameConfig.baseHeight;

  /// Called once the device screen size is known (from LayoutBuilder).
  /// Keeps [gameWidth] at 360 and scales [gameHeight] to match the screen ratio.
  static void setGameSize(double screenW, double screenH) {
    gameWidth = GameConfig.baseWidth;
    gameHeight = screenH * GameConfig.baseWidth / screenW;
  }

  // ---- State ----
  GameState gameState = GameState.menu;
  int score = 0;
  int lives = 3;
  int level = 1;
  int highScore = 0;
  bool debugSlots = false;
  bool debugPaused = false;
  bool hapticsEnabled = true;
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

  void toggleHaptics() {
    hapticsEnabled = !hapticsEnabled;
    if (hapticsEnabled) HapticFeedback.lightImpact();
    notifyListeners();
  }

  void resetHighScore() {
    highScore = 0;
    notifyListeners();
  }

  void _hapticLight() {
    if (hapticsEnabled) HapticFeedback.lightImpact();
  }

  void _hapticMedium() {
    if (hapticsEnabled) HapticFeedback.mediumImpact();
  }

  void _hapticHeavy() {
    if (hapticsEnabled) HapticFeedback.heavyImpact();
  }

  void debugToggleMaintenance(int conveyorId) {
    final conv = _findConveyor(conveyorId);
    if (conv == null) return;
    if (conv.maintenance) {
      conv.direction = conv.pendingDirection ?? conv.direction;
      conv.maintenance = false;
      conv.pendingDirection = null;
      conv.maintenanceEnd = 0;
    } else {
      conv.pendingDirection = conv.direction == ConveyorDirection.down
          ? ConveyorDirection.up
          : ConveyorDirection.down;
      conv.maintenance = true;
      // Use maxFinite so _endMaintenance timer never fires; only toggled off manually.
      conv.maintenanceEnd = double.maxFinite;
      boxes.removeWhere((b) =>
          b.conveyorId == conv.id &&
          b.id != draggedBoxId &&
          b.specialType == null);
    }
    notifyListeners();
  }
  List<Box> boxes = [];
  List<Conveyor> conveyors = [];
  List<FallingBox> fallingBoxes = [];
  List<BeltExplosion> beltExplosions = [];
  ComboArea? comboArea;
  int? draggedBoxId;
  List<Popup> popups = [];
  List<Particle> particles = [];
  List<BoxColor> _shuffledColors = [];

  // ---- Deferred mutation queues (used inside _moveBoxes) ----
  // _moveBoxes iterates `boxes` with a for-in loop; any code that runs
  // inside that loop (gate hits, combo completion, bomb effect) must NOT
  // call boxes.add / boxes.removeWhere directly — Dart throws
  // ConcurrentModificationException.  Instead they write to these queues
  // and _moveBoxes flushes them after the loop.
  final List<Box> _pendingBoxes = [];
  final Set<int> _pendingRemovals = {};

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

  // Per-belt earliest time the next box may spawn. Randomised after each spawn
  // so belts fill at different rates. Shifted on pause/resume like other timers.
  final Map<int, double> _nextSpawnTime = {};

  final Random _random = Random();

  // ---- Easing ----
  double _easeInOut(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3).toDouble() / 2;
  double easeOut(double t) => 1 - pow(1 - t, 3).toDouble();

  // ---- Slot helpers ----
  // Sentinel slotIndex value meaning "past last slot, moving freely to gate".
  static const int _exitSlot = 9999;

  static const double boxSize = GameConfig.boxSize;

  // How many box-sized slots fit on a belt of height [convH].
  static int _numSlots(double convH) => max(1, (convH / boxSize).floor());

  // Unscrolled top of slot [s]: used as a fixed approach target for entering
  // boxes so the gap to the belt doesn't drift with the belt phase.
  double _slotY(Conveyor conv, int s) => conv.y + s * boxSize;

  // Scrolled slot position — slot label [s] rotates with the belt surface so
  // the label's physical row advances each slot-period. Matches box.y exactly
  // because both advance at the same speed (conv.speed * dt * 0.1 px/frame).
  double _slotYScrolled(Conveyor conv, int s, double convH) {
    final nSlots = _numSlots(convH);
    final absOff = beltOffset(conv.speed, conv.direction).abs();
    final k = (absOff / boxSize).floor();
    final f = absOff % boxSize;
    if (conv.direction == ConveyorDirection.down) {
      return conv.y + (s + k) % nSlots * boxSize + f;
    } else {
      return conv.y + ((s - k) % nSlots + nSlots) % nSlots * boxSize - f;
    }
  }

  // Slot label currently positioned at the belt's entry row.
  // Down belt entry = physical row 0 (top); up belt entry = row N-1 (bottom).
  int _currentEntrySlot(Conveyor conv, double convH) {
    final nSlots = _numSlots(convH);
    final k = (beltOffset(conv.speed, conv.direction).abs() / boxSize).floor();
    return conv.direction == ConveyorDirection.down
        ? (nSlots - k % nSlots) % nSlots
        : (nSlots - 1 + k) % nSlots;
  }

  // Single occupancy check used by spawn, belt movement, and drop/throw validation.
  // A slot is considered occupied when any box's authoritative slotIndex matches,
  // an in-flight box has reserved it via targetSlot, or an entering box is
  // waiting at the entry slot. Using slotIndex (not a position-derived value)
  // keeps spawn, movement, and drop logic consistent with one source of truth.
  bool _isSlotFree(Conveyor conv, int s, int excludeId,
      {bool forDrop = false}) {
    final isDown = conv.direction == ConveyorDirection.down;
    final convH = getCurrentHeight(conv, _lastFrameTime);
    final entrySlot = _currentEntrySlot(conv, convH);
    return !boxes.any((b) {
      if (b.id == excludeId) return false;
      final anim = b.throwAnim;
      if (anim != null && !b.onConveyor && anim.targetConvId == conv.id) {
        return anim.targetSlot == s;
      }
      if (b.conveyorId != conv.id) return false;
      if (!b.onConveyor) return false;
      // Entering boxes block spawns always, but block drops only once they
      // have physically crossed into the belt boundary.
      if (b.slotIndex == null) {
        if (forDrop) {
          final onBelt =
              isDown ? b.y >= conv.y : b.y + b.size <= conv.y + convH;
          return onBelt && s == entrySlot;
        }
        return s == entrySlot;
      }
      if (b.slotIndex == _exitSlot) return false;
      return b.slotIndex == s;
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
    const totalWidth = GameConfig.conveyorMaxCount * GameConfig.conveyorWidth +
        (GameConfig.conveyorMaxCount - 1) * GameConfig.conveyorGap;
    final startX = (gameWidth - totalWidth) / 2;
    return startX + i * (GameConfig.conveyorWidth + GameConfig.conveyorGap);
  }

  // Order in which slots are filled. Starts at slot 1 so the first 2 belts
  // land in the center of the 5-slot grid, then grows right, then fills slot 0.
  static const List<int> _slotFillOrder = [1, 2, 3, 4, 0];

  // Two belts are visually adjacent when their left edges are one slot apart.
  bool _areAdjacentBelts(Conveyor a, Conveyor b) =>
      (a.x - b.x).abs() < GameConfig.conveyorWidth + GameConfig.conveyorGap + 1;

  void setupLevel(int lvl) {
    final numConveyors = min(2 + ((lvl - 1) ~/ 2), 5);
    final activeColors = _shuffledColors.sublist(0, numConveyors);

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
        width: GameConfig.conveyorWidth,
        height: height,
        speed: baseSpeed * speedMultiplier,
        direction: direction,
      ));
    }

    conveyors = newConveyors;
    boxes = [];
    fallingBoxes = [];
    comboArea = _generateComboArea();
    particles = [];
    final now = _lastFrameTime;
    _lastReverseCheck = now + 3000;
    _lastResizeCheck = now + 4500;
    // Stagger initial spawns so belts don't all fill at the same moment.
    _nextSpawnTime.clear();
    for (int i = 0; i < newConveyors.length; i++) {
      _nextSpawnTime[newConveyors[i].id] =
          now + 500 + i * 800 + _random.nextDouble() * 600;
    }
  }

  void startGame() {
    score = 0;
    lives = 4;
    level = 1;
    popups = [];
    particles = [];
    fallingBoxes = [];
    beltExplosions = [];
    draggedBoxId = null;
    comboArea = null;
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
    beltExplosions = [];
    popups = [];
    particles = [];
    comboArea = null;
    draggedBoxId = null;
    notifyListeners();
  }

  void _shiftTimestamps(double delta) {
    if (delta <= 0) return;
    _lastReverseCheck += delta;
    _lastResizeCheck += delta;
    _lastFrameTime += delta;
    if (_shakeUntil > 0) _shakeUntil += delta;
    for (final key in _nextSpawnTime.keys.toList()) {
      _nextSpawnTime[key] = _nextSpawnTime[key]! + delta;
    }
    for (final conv in conveyors) {
      if (conv.maintenance) conv.maintenanceEnd += delta;
      if (conv.resizing) conv.resizeStart += delta;
      if (conv.frozen) conv.frozenUntil += delta;
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
    for (final e in beltExplosions) {
      e.startTime += delta;
    }
    final ct = comboArea?.completionTime;
    if (ct != null) comboArea!.completionTime = ct + delta;
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
      _resolveOverlaps(boxes, now);
      _updateParticles(now, dt);
      _updateFallingBoxes(dt);
      _updateBeltExplosions(now);
      notifyListeners();
      return;
    }

    _handleReversals(now);
    _handleResizes(now);
    _endMaintenance(now);
    _endResize(now);
    _endFreeze(now);
    _updateThrows(now);
    _updateParticles(now, dt);
    _updateFallingBoxes(dt);
    _spawnBoxes(now);
    _moveBoxes(now, dt);
    _checkLevelUp(now);
    _checkComboReset(now);
    _updateBeltExplosions(now);

    notifyListeners();
  }

  void _handleReversals(double now) {
    if (now - _lastReverseCheck <= reverseCheckInterval) return;
    _lastReverseCheck = now;
    if (conveyors.length <= 1 || _random.nextDouble() >= reverseChance) return;

    final candidates = conveyors
        .where((c) => !c.maintenance && !c.resizing && !c.frozen)
        .toList();

    if (candidates.isEmpty) return;

    final target = candidates[_random.nextInt(candidates.length)];

    target.pendingDirection = target.direction == ConveyorDirection.down
        ? ConveyorDirection.up
        : ConveyorDirection.down;
    target.maintenance = true;
    target.maintenanceEnd = now + maintenanceDuration;

    // Special boxes survive maintenance — they're too valuable to discard.
    boxes.removeWhere((b) =>
        b.conveyorId == target.id &&
        b.id != draggedBoxId &&
        b.specialType == null);

    _addPopup(target.x + target.width / 2, target.y + 10, '⚠',
        const Color(0xFFFBBF24),
        size: 28);
  }

  void _handleResizes(double now) {
    if (now - _lastResizeCheck <= resizeCheckInterval) return;
    _lastResizeCheck = now;
    if (conveyors.isEmpty || _random.nextDouble() >= resizeChance) return;

    final candidates =
        conveyors.where((c) => !c.maintenance && !c.resizing && !c.frozen).toList();
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

  void _endFreeze(double now) {
    for (final conv in conveyors) {
      if (conv.frozen && now >= conv.frozenUntil) {
        conv.frozen = false;
        conv.frozenUntil = 0;
      }
    }
  }

  double _spawnInterval() {
    final base = max(GameConfig.spawnIntervalMin,
        GameConfig.spawnIntervalBase - (level - 1) * 200.0);
    final jitter = GameConfig.spawnIntervalJitterMin +
        _random.nextDouble() *
            (GameConfig.spawnIntervalJitterMax -
                GameConfig.spawnIntervalJitterMin);
    return base * jitter;
  }

  void _spawnBoxes(double now) {
    if (conveyors.isEmpty) return;
    const bsize = GameController.boxSize;

    for (final conv in conveyors) {
      if (conv.maintenance || conv.frozen) continue;
      if (now < (_nextSpawnTime[conv.id] ?? 0)) continue;

      final isDown = conv.direction == ConveyorDirection.down;
      final convH = getCurrentHeight(conv, now);
      if (!_isSlotFree(conv, _currentEntrySlot(conv, convH), -1)) continue;

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
      _nextSpawnTime[conv.id] = now + _spawnInterval();
    }
  }

  void _moveBoxes(double now, double dt) {
    int wrongHits = 0;
    _pendingBoxes.clear();
    _pendingRemovals.clear();
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
      if (conv.maintenance || conv.frozen) { keep.add(box); continue; }

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

      // Physical entry row (fixed: row 0 for down, row N-1 for up).
      final entryRow = isDown ? 0 : nSlots - 1;
      // Rotating slot label currently at the entry row.
      final entryLabel = _currentEntrySlot(conv, convH);

      // Entering phase: box outside belt, moving toward the fixed belt entry.
      // Uses _slotY (unscrolled) so the approach target doesn't drift with the
      // belt phase — prevents boxes getting stranded when phase wraps.
      if (box.slotIndex == null) {
        final targetY = _slotY(conv, entryRow);
        final dist = (box.y - targetY).abs();
        if (dist <= moveAmount + 0.5) {
          if (_isSlotFree(conv, entryLabel, box.id)) {
            box.y = _slotYScrolled(conv, entryLabel, convH);
            box.slotIndex = entryLabel;
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

      // Transition to exit when the box's physical Y reaches the gate end.
      if (isDown ? box.y + box.size >= conv.y + convH : box.y <= conv.y) {
        box.slotIndex = _exitSlot;
      }

      keep.add(box);
    }

    // Apply bomb removals: some boxes may have been added to keep before
    // _triggerBomb ran (they appeared earlier in the iteration order).
    if (_pendingRemovals.isNotEmpty) {
      keep.removeWhere((b) => _pendingRemovals.contains(b.id));
    }

    _resolveOverlaps(keep, now);

    boxes = keep;

    // Flush boxes spawned during gate processing (e.g., special item from combo).
    if (_pendingBoxes.isNotEmpty) {
      boxes.addAll(_pendingBoxes);
      _pendingBoxes.clear();
    }

    if (wrongHits > 0) {
     // lives -= wrongHits;
      _shakeUntil = _lastFrameTime + 280;
      if (lives <= 0) {
        lives = 0;
        gameState = GameState.gameover;
        if (score > highScore) highScore = score;
      }
    }
  }

  // Pushes overlapping boxes apart and recalculates slotIndex from their Y position.
  // Called both from _moveBoxes and the debugPaused path so throws that land
  // while paused don't leave two boxes sharing the same slot index.
  void _resolveOverlaps(List<Box> boxList, double now) {
    for (final conv in conveyors) {
      final isDown = conv.direction == ConveyorDirection.down;
      final beltBoxes = boxList
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
        final convH = getCurrentHeight(conv, now);
        final ns = _numSlots(convH);
        if (curr.slotIndex! >= ns ||
            (isDown
                ? curr.y + curr.size >= conv.y + convH
                : curr.y <= conv.y)) {
          curr.slotIndex = _exitSlot;
        }
      }
    }
  }

  // Scores a gate hit for [box], spawns the falling animation, returns 1 on wrong hit.
  int _processGateHit(Box box, Conveyor conv, double convH, bool isDown) {
    final gateY = isDown ? conv.y + convH : conv.y;
    final popupY = isDown ? gateY - 10 : gateY + 10;

    // Special items bypass color matching and trigger their own effect.
    if (box.specialType != null) {
      _triggerSpecial(box.specialType!, conv, isDown, gateY, popupY);
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
      return 0;
    }

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
      _hapticMedium();
      _advanceCombo(box.color, _lastFrameTime);
    } else {
      wrong = 1;
      _comboCount = 0;
      _comboColorId = null;
      _addPopup(conv.x + conv.width / 2, popupY, '✗',
          const Color(0xFFEF4444));
      _hapticHeavy();
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
      _hapticMedium();
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

  // ---- Combination area ----
  ComboArea _generateComboArea() {
    final colors = conveyors.map((c) => c.color).toList();
    final recipe = List.generate(
        GameConfig.comboSlotCount, (_) => colors[_random.nextInt(colors.length)]);
    final reward = SpecialType.values[_random.nextInt(SpecialType.values.length)];
    return ComboArea(recipe: recipe, reward: reward);
  }

  // Called after every correct gate hit to try to advance the combo sequence.
  // A hit that matches recipe[progress] advances; one that doesn't resets
  // progress to 0 (only if the player had already started the sequence).
  void _advanceCombo(BoxColor scored, double now) {
    final area = comboArea;
    if (area == null || area.completionTime != null) return;
    if (area.currentTarget?.id == scored.id) {
      area.progress++;
      if (area.isComplete) _completeComboArea(area, now);
    } else if (area.progress > 0) {
      area.progress = 0;
    }
  }

  void _completeComboArea(ComboArea area, double now) {
    area.completionTime = now;
    _hapticMedium();
    _spawnSpecialBox(area.reward, now);
    final centerX = gameWidth / 2;
    const popupY = GameConfig.comboAreaTop + 26;
    final label = switch (area.reward) {
      SpecialType.bomb => '💣 BOMB INCOMING!',
      SpecialType.icy => '❄ ICY INCOMING!',
    };
    _addPopup(centerX, popupY, label, const Color(0xFFFF6600), size: 20);
  }

  // Spawns a special box at the entry end of a random non-maintenance conveyor.
  // Writes to _pendingBoxes so this can be called safely from inside the
  // _moveBoxes loop (direct boxes.add would cause ConcurrentModificationException).
  void _spawnSpecialBox(SpecialType type, double now) {
    final available = conveyors.where((c) => !c.maintenance && !c.frozen).toList();
    if (available.isEmpty) return;
    final conv = available[_random.nextInt(available.length)];
    final isDown = conv.direction == ConveyorDirection.down;
    final convH = getCurrentHeight(conv, now);
    _pendingBoxes.add(Box(
      id: _boxIdCounter++,
      x: conv.x + (conv.width - boxSize) / 2,
      y: isDown ? conv.y - boxSize : conv.y + convH,
      conveyorId: conv.id,
      color: conv.color,
      size: boxSize,
      onConveyor: true,
      entering: true,
      specialType: type,
    ));
  }

  void _triggerSpecial(
      SpecialType type, Conveyor conv, bool isDown, double gateY, double popupY) {
    switch (type) {
      case SpecialType.bomb:
        _triggerBomb(conv, isDown, gateY, popupY);
      case SpecialType.icy:
        _triggerIcy(conv, isDown, gateY, popupY);
    }
  }

  void _triggerBomb(Conveyor conv, bool isDown, double gateY, double popupY) {
    // Mark all normal boxes on this conveyor for removal via _pendingRemovals
    // so we never call boxes.removeWhere inside the _moveBoxes iteration.
    int count = 0;
    for (final b in boxes) {
      if (b.conveyorId == conv.id &&
          b.id != draggedBoxId &&
          b.specialType == null) {
        _pendingRemovals.add(b.id);
        count++;
      }
    }
    if (count > 0) score += count;

    final cx = conv.x + conv.width / 2;
    _spawnExplosion(cx, gateY);
    _shakeUntil = _lastFrameTime + 500;
    HapticFeedback.heavyImpact();

    // Fire wave: travels from the gate edge to the generator end of the belt.
    final convH = getCurrentHeight(conv, _lastFrameTime);
    final toY = isDown ? conv.y : conv.y + convH;
    final duration = (convH * 1.5).clamp(500.0, 900.0);
    beltExplosions.removeWhere((e) => e.conveyorId == conv.id);
    beltExplosions.add(BeltExplosion(
      conveyorId: conv.id,
      startTime: _lastFrameTime,
      duration: duration,
      fromY: gateY,
      toY: toY,
    ));

    final label = count > 0 ? '💥 +$count' : '💥 BOOM!';
    _addPopup(cx, popupY, label, const Color(0xFFFF6600), size: 28);
  }

  void _triggerIcy(Conveyor conv, bool isDown, double gateY, double popupY) {
    conv.frozen = true;
    conv.frozenUntil = _lastFrameTime + icyFreezeDuration;

    final cx = conv.x + conv.width / 2;
    _spawnIceEffect(cx, gateY);
    HapticFeedback.lightImpact();

    _addPopup(cx, popupY, '❄ FROZEN!', const Color(0xFF7DD3FC), size: 24);
  }

  void _spawnIceEffect(double x, double y) {
    const ice = [
      Color(0xFF7DD3FC),
      Color(0xFFBAE6FD),
      Color(0xFFFFFFFF),
      Color(0xFF0EA5E9),
    ];
    for (int i = 0; i < 18; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = 0.03 + _random.nextDouble() * 0.20;
      particles.add(Particle(
        x: x + (_random.nextDouble() - 0.5) * 8,
        y: y + (_random.nextDouble() - 0.5) * 8,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        gravity: 0.00015,
        drag: 0.94,
        size: 2.0 + _random.nextDouble() * 3.5,
        color: ice[_random.nextInt(ice.length)],
        startTime: _lastFrameTime,
        lifetime: 450 + _random.nextDouble() * 300,
      ));
    }
  }

  void _updateBeltExplosions(double now) {
    beltExplosions.removeWhere((e) => now - e.startTime >= e.duration);
  }

  void _spawnExplosion(double x, double y) {
    const boom = [
      Color(0xFFFF6600),
      Color(0xFFFFCC00),
      Color(0xFFFF3300),
      Color(0xFFFFFFFF),
    ];
    for (int i = 0; i < 20; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = 0.08 + _random.nextDouble() * 0.38;
      particles.add(Particle(
        x: x + (_random.nextDouble() - 0.5) * 10,
        y: y + (_random.nextDouble() - 0.5) * 10,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        gravity: 0.0004,
        drag: 0.92,
        size: 2.5 + _random.nextDouble() * 4.5,
        color: boom[_random.nextInt(boom.length)],
        startTime: _lastFrameTime,
        lifetime: 350 + _random.nextDouble() * 250,
      ));
    }
  }

  // After the completion flash (1 500 ms), generate a fresh recipe.
  void _checkComboReset(double now) {
    final area = comboArea;
    if (area == null || area.completionTime == null) return;
    if (now - area.completionTime! >= 1500) {
      comboArea = _generateComboArea();
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
      width: GameConfig.conveyorWidth,
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
        _hapticLight();
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
    // No notifyListeners here — the ticker fires notifyListeners each vsync,
    // so calling it again per pointer event just queues redundant repaints.
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
        final slot = _findFreeSlotIndex(box, targetConv, targetH);
        if (slot != null) {
          _startThrow(box, targetConv, slot, now);
          _hapticMedium();
          draggedBoxId = null;
          notifyListeners();
          return;
        }
      }
      // Swipe toward an invalid / blocked lane — animate back to source.
      _snapBackToSource(box, now);
      _hapticHeavy();
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
      final slot = _findFreeSlotIndex(box, targetConv, currentH);
      if (slot == null) {
        _snapBackToSource(box, now);
        _hapticHeavy();
      } else {
        _startThrow(box, targetConv, slot, now);
        _hapticMedium();
      }
    } else {
      // Released outside any conveyor → animate back to source
      _snapBackToSource(box, now);
      _hapticHeavy();
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
    final fallbackSlot = _currentEntrySlot(sourceConv, h);
    final slot = _findFreeSlotIndex(box, sourceConv, h) ?? fallbackSlot;
    _startThrow(box, sourceConv, slot, now);
  }

  Box? _findBox(int id) {
    for (final b in boxes) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Returns the index of the nearest free slot on [targetConv] to [box],
  /// or null if every slot is occupied. Pure controller logic — no pixel math.
  int? _findFreeSlotIndex(Box box, Conveyor targetConv, double currentH) {
    final nSlots = _numSlots(currentH);
    final closestSlot =
        _closestSlotIndex(targetConv, box.y, currentH, nSlots);
    for (int radius = 0; radius < nSlots; radius++) {
      final candidates =
          radius == 0 ? [closestSlot] : [closestSlot - radius, closestSlot + radius];
      for (final s in candidates) {
        if (s < 0 || s >= nSlots) continue;
        if (_isSlotFree(targetConv, s, box.id, forDrop: true)) return s;
      }
    }
    return null;
  }

  /// Primes [box] for a throw to [slot] on [targetConv].
  /// The slot index is the authoritative controller decision; pixel endpoints
  /// are derived here for the visual arc and stay separate from game logic.
  void _startThrow(Box box, Conveyor targetConv, int slot, double now) {
    final convH = getCurrentHeight(targetConv, now);
    box.throwAnim = ThrowAnim(
      startTime: now,
      startX: box.x,
      startY: box.y,
      endX: targetConv.x + (targetConv.width - box.size) / 2,
      endY: _slotYScrolled(targetConv, slot, convH),
      targetConvId: targetConv.id,
      targetSlot: slot,
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
        box.onConveyor = true;
        box.conveyorId = anim.targetConvId;
        box.entering = false;
        final tConv = _findConveyor(anim.targetConvId);
        if (tConv != null) {
          final convH = getCurrentHeight(tConv, now);
          final ns = _numSlots(convH);
          // Snap to the reserved slot's current scrolled position so the box
          // lands in sync with the belt regardless of phase drift during flight.
          if (anim.targetSlot != _exitSlot && anim.targetSlot < ns) {
            box.y = _slotYScrolled(tConv, anim.targetSlot, convH);
            box.slotIndex = anim.targetSlot;
          } else {
            box.y = anim.endY;
            box.slotIndex = _exitSlot;
          }
        } else {
          box.y = anim.endY;
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
      final slot = _findFreeSlotIndex(b, conv, h);
      if (slot != null) result[conv.id] = _slotYScrolled(conv, slot, h);
    }
    return result;
  }
}
