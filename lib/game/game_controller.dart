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
import 'specials/special_effect.dart';
import 'stages/game_stage.dart';

part 'systems/belt_system.dart';
part 'systems/box_system.dart';
part 'systems/drag_system.dart';
part 'systems/particle_system.dart';
part 'systems/combo_system.dart';
part 'systems/level_system.dart';

enum GameState { menu, playing, paused, gameover }

/// Holds all game state and drives the game loop via [update].
/// Logic is split across `systems/` part files — each file is an extension
/// on this class, giving it full private access with no circular imports.
class GameController extends ChangeNotifier {
  // ---- Tunable constants ----
  static const double maintenanceDuration    = 2200;
  static const double reverseCheckInterval   = 12000;
  static const double reverseChance          = 0.25;
  static const double icyFreezeDuration      = 4000;
  static const double resizeCheckInterval    = 6500;
  static const double resizeChance           = 0.35;
  static const double resizeAnimationDuration = 900;
  static const double boxSize               = GameConfig.boxSize;
  static const double hudBottom             = GameConfig.hudBottom;
  static const double gateHeight            = GameConfig.gateHeight;
  static const double gateOffset            = GameConfig.gateOffset;
  // Sentinel slotIndex: box has passed the last slot, coasting to the gate.
  static const int _exitSlot = 9999;

  static double get conveyorMaxHeight     => gameHeight - 350;
  static double get conveyorMinHeight     =>
      max(GameConfig.conveyorMinSlots * boxSize, conveyorMaxHeight * 0.45);
  static double get conveyorDefaultHeight => conveyorMaxHeight * 0.8;
  static double get conveyorTop           =>
      gameHeight * GameConfig.conveyorTopFraction;

  // ---- Canvas size — set once from LayoutBuilder ----
  static double gameWidth  = GameConfig.baseWidth;
  static double gameHeight = GameConfig.baseHeight;

  static void setGameSize(double screenW, double screenH) {
    gameWidth  = GameConfig.baseWidth;
    gameHeight = screenH * GameConfig.baseWidth / screenW;
  }

  // ---- Public game state ----
  GameState gameState = GameState.menu;
  int score     = 0;
  int lives     = 3;
  int level     = 1;
  int highScore = 0;

  // ---- Debug ----
  bool debugSlots  = false;
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

  void resetHighScore() { highScore = 0; notifyListeners(); }

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
          ? ConveyorDirection.up : ConveyorDirection.down;
      conv.maintenance = true;
      conv.maintenanceEnd = double.maxFinite;
      boxes.removeWhere((b) =>
          b.conveyorId == conv.id &&
          b.id != draggedBoxId &&
          b.specialType == null);
    }
    notifyListeners();
  }

  // ---- Object lists ----
  List<Box>           boxes          = [];
  List<Conveyor>      conveyors      = [];
  List<FallingBox>    fallingBoxes   = [];
  List<BeltExplosion> beltExplosions = [];
  List<Popup>         popups         = [];
  List<Particle>      particles      = [];
  ComboArea?          comboArea;
  int?                draggedBoxId;

  // ---- Stage ----
  GameStage currentStage = const NormalStage();

  // ---- Deferred mutation queues (safe inside _moveBoxes loop) ----
  final List<Box> _pendingBoxes     = [];
  final Set<int>  _pendingRemovals  = {};

  // ---- Internal timers / counters ----
  int    _boxIdCounter     = 0;
  int    _popupIdCounter   = 0;
  double _lastReverseCheck = 0;
  double _lastResizeCheck  = 0;
  double _lastFrameTime    = 0;
  double _shakeUntil       = 0;
  int    _comboCount       = 0;
  String? _comboColorId;
  double _pauseStart       = 0;
  final Map<int, double> _nextSpawnTime = {};
  List<BoxColor> _shuffledColors = [];

  final Random _random = Random();

  // ---- Easing ----
  double _easeInOut(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3).toDouble() / 2;
  double easeOut(double t) => 1 - pow(1 - t, 3).toDouble();

  // ---- Belt-slot layout helpers (static, used by setupLevel + BoxSystem) ----
  static const List<int> _slotFillOrder = [1, 2, 3, 4, 0];

  static double _beltSlotX(int i) {
    const total = GameConfig.conveyorMaxCount * GameConfig.conveyorWidth +
        (GameConfig.conveyorMaxCount - 1) * GameConfig.conveyorGap;
    final startX = (gameWidth - total) / 2;
    return startX + i * (GameConfig.conveyorWidth + GameConfig.conveyorGap);
  }

  bool _areAdjacentBelts(Conveyor a, Conveyor b) =>
      (a.x - b.x).abs() < GameConfig.conveyorWidth + GameConfig.conveyorGap + 1;

  // ---- Level setup ----
  void setupLevel(int lvl) {
    final numConveyors = min(2 + ((lvl - 1) ~/ 2), 5);
    final activeColors = _shuffledColors.sublist(0, numConveyors);
    final baseSpeed = 0.28 + lvl * 0.035;

    conveyors = List.generate(activeColors.length, (i) {
      final heightRoll = _random.nextDouble();
      double h;
      if (heightRoll < 0.25) {
        h = conveyorMinHeight + _random.nextDouble() * 60;
      } else if (heightRoll < 0.75) {
        h = conveyorDefaultHeight + (_random.nextDouble() - 0.5) * 40;
      } else {
        h = conveyorMaxHeight - _random.nextDouble() * 30;
      }
      return Conveyor(
        id: i,
        color: activeColors[i],
        x: _beltSlotX(_slotFillOrder[i]),
        y: conveyorTop,
        width: GameConfig.conveyorWidth,
        height: h,
        speed: baseSpeed * (0.75 + _random.nextDouble() * 0.7),
        direction: _random.nextBool() ? ConveyorDirection.down : ConveyorDirection.up,
      );
    });

    boxes          = [];
    fallingBoxes   = [];
    comboArea      = _generateComboArea();
    particles      = [];
    final now = _lastFrameTime;
    _lastReverseCheck = now + 3000;
    _lastResizeCheck  = now + 4500;
    _nextSpawnTime.clear();
    for (int i = 0; i < conveyors.length; i++) {
      _nextSpawnTime[conveyors[i].id] =
          now + 500 + i * 800 + _random.nextDouble() * 600;
    }
    currentStage.onSetup(this, lvl);
  }

  // ---- State transitions ----
  void startGame() {
    score          = 0;
    lives          = 4;
    level          = 1;
    popups         = [];
    particles      = [];
    fallingBoxes   = [];
    beltExplosions = [];
    draggedBoxId   = null;
    comboArea      = null;
    _pauseStart    = 0;
    _shakeUntil    = 0;
    _comboCount    = 0;
    _comboColorId  = null;
    _shuffledColors = List.of(BoxColor.all)..shuffle(_random);
    setupLevel(1);
    gameState = GameState.playing;
    notifyListeners();
  }

  void pauseGame() {
    if (gameState != GameState.playing) return;
    if (draggedBoxId != null) handleEnd();
    _pauseStart = _lastFrameTime;
    gameState = GameState.paused;
    notifyListeners();
  }

  void resumeGame() {
    if (gameState != GameState.paused) return;
    gameState = GameState.playing;
    notifyListeners();
  }

  void exitToMenu() {
    gameState      = GameState.menu;
    _pauseStart    = 0;
    boxes          = [];
    fallingBoxes   = [];
    beltExplosions = [];
    popups         = [];
    particles      = [];
    comboArea      = null;
    draggedBoxId   = null;
    notifyListeners();
  }

  // ---- Frame update ----
  void update(double now) {
    if (gameState == GameState.paused) return;

    if (_pauseStart != 0) {
      _shiftTimestamps(now - _pauseStart);
      _pauseStart = 0;
    }

    final dt = _lastFrameTime == 0 ? 16.0 : min(now - _lastFrameTime, 50.0);
    _lastFrameTime = now;

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
    currentStage.onUpdate(this, now, dt);

    notifyListeners();
  }

  // ---- Shared utilities used by multiple systems ----
  void _shiftTimestamps(double delta) {
    if (delta <= 0) return;
    _lastReverseCheck += delta;
    _lastResizeCheck  += delta;
    _lastFrameTime    += delta;
    if (_shakeUntil > 0) _shakeUntil += delta;
    for (final key in _nextSpawnTime.keys.toList()) {
      _nextSpawnTime[key] = _nextSpawnTime[key]! + delta;
    }
    for (final conv in conveyors) {
      if (conv.maintenance) conv.maintenanceEnd += delta;
      if (conv.resizing)    conv.resizeStart    += delta;
      if (conv.frozen)      conv.frozenUntil    += delta;
    }
    for (final box in boxes) {
      if (box.dragStartTime != null) box.dragStartTime = box.dragStartTime! + delta;
      if (box.throwAnim != null)     box.throwAnim!.startTime += delta;
    }
    for (final popup in popups)         { popup.createdAt     += delta; }
    for (final p in particles)          { p.startTime         += delta; }
    for (final e in beltExplosions)     { e.startTime         += delta; }
    final ct = comboArea?.completionTime;
    if (ct != null) comboArea!.completionTime = ct + delta;
  }

  void _addPopup(double x, double y, String text, Color color, {double size = 22}) {
    popups.add(Popup(
      id: _popupIdCounter++,
      x: x, y: y,
      text: text, color: color, size: size,
      createdAt: _lastFrameTime,
    ));
  }

  Conveyor? _findConveyor(int id) {
    for (final c in conveyors) { if (c.id == id) return c; }
    return null;
  }

  Box? _findBox(int id) {
    for (final b in boxes) { if (b.id == id) return b; }
    return null;
  }

  // ---- Height (handles resize animation) ----
  double getCurrentHeight(Conveyor conv, double now) {
    if (!conv.resizing) return conv.height;
    final t = min(1.0, (now - conv.resizeStart) / resizeAnimationDuration);
    return conv.fromHeight + (conv.toHeight - conv.fromHeight) * _easeInOut(t);
  }

  // ---- Level scoring ----
  int pointsForLevel(int lvl) {
    int total = 0;
    for (int i = 1; i < lvl; i++) total += 6 + i * 4;
    return total;
  }

  int levelFromScore(int s) {
    int lvl = 1;
    while (pointsForLevel(lvl + 1) <= s) lvl++;
    return lvl;
  }

  // ---- Helpers exposed to the painter ----
  double beltOffset(double speed, ConveyorDirection direction) {
    final t = debugPaused ? _debugFreezeTime : _lastFrameTime;
    final raw = t * speed * 0.1;
    return direction == ConveyorDirection.down ? raw : -raw;
  }

  double maintenanceFlash() => 0.5 + 0.5 * sin(_lastFrameTime * 0.01);
  double resizeFlash()      => 0.5 + 0.5 * sin(_lastFrameTime * 0.015);
  double get currentTime    => _lastFrameTime;

  Offset get shakeOffset {
    if (_lastFrameTime >= _shakeUntil) return Offset.zero;
    final t = (_shakeUntil - _lastFrameTime) / 280.0;
    final amp = 7.0 * t;
    return Offset(sin(_lastFrameTime * 0.09) * amp, sin(_lastFrameTime * 0.06 + 1.0) * amp);
  }

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

  Map<int, double>? get landingSlots {
    if (draggedBoxId == null) return null;
    final b = _findBox(draggedBoxId!);
    if (b == null || b.sourceConveyorId == null) return null;
    final targets = allowedTargets!;
    final result = <int, double>{};
    for (final conv in conveyors) {
      if (!targets.contains(conv.id) || conv.maintenance) continue;
      final h    = getCurrentHeight(conv, _lastFrameTime);
      final slot = _findFreeSlotIndex(b, conv, h);
      if (slot != null) result[conv.id] = _slotYScrolled(conv, slot, h);
    }
    return result;
  }

  // ---- Haptic helpers ----
  void _hapticLight()  { if (hapticsEnabled) HapticFeedback.lightImpact(); }
  void _hapticMedium() { if (hapticsEnabled) HapticFeedback.mediumImpact(); }
  void _hapticHeavy()  { if (hapticsEnabled) HapticFeedback.heavyImpact(); }

  // ---- Library-level helpers for part-file extensions ----
  // notifyListeners is @protected — extensions can't call it directly.
  void _notify() => notifyListeners();

  // Slot count is used by multiple systems; top of class so extensions can call it.
  static int _numSlots(double convH) => max(1, (convH / boxSize).floor());
}
