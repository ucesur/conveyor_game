part of '../game_controller.dart';

extension LevelSystem on GameController {
  void _checkLevelUp(double now) {
    if (gameState != GameState.playing) return;
    if (currentStage.isBoss) return; // Freeze level progression during boss fight.
    final newLevel = levelFromScore(score);
    if (newLevel <= level) return;

    _hapticMedium();
    GameAudio.instance.play(SoundEffect.levelUp);
    final oldBase = 0.28 + level * 0.035;
    final newBase = 0.28 + newLevel * 0.035;
    level = newLevel;

    for (final conv in conveyors) {
      conv.speed = conv.speed * newBase / oldBase;
    }

    final newCount = min(2 + ((level - 1) ~/ 2), 5);
    if (newCount > conveyors.length) _addBelt(newCount, newBase, now);

    _addPopup(GameController.gameWidth / 2, GameController.hudBottom + 30,
        'LEVEL $level', const Color(0xFFFBBF24), size: 28);

    // Every 5th level triggers a boss stage (skip if one is already active).
    if (newLevel % 3 == 0 && currentStage is! BossStage) {
      final boss = BossStage();
      currentStage = boss;
      boss.onActivate(this, newLevel, now);
    }
  }

  void _addBelt(int newCount, double baseSpeed, double now) {
    final idx = conveyors.length;
    conveyors.add(Conveyor(
      id: idx,
      color: _shuffledColors[idx],
      x: GameController._beltSlotX(GameController._slotFillOrder[idx]),
      y: GameController.conveyorTop,
      width: GameConfig.conveyorWidth,
      height: GameController.conveyorDefaultHeight,
      speed: baseSpeed * (0.75 + _random.nextDouble() * 0.7),
      direction: _random.nextBool() ? ConveyorDirection.down : ConveyorDirection.up,
    ));
  }
}
