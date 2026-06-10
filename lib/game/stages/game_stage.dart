import '../game_controller.dart';
import '../../models/special_type.dart';

/// Implement to create a new stage type (normal wave, boss, tutorial, etc.).
/// Attach to the controller via [GameController.currentStage].
///
/// Only override the hooks relevant to your stage — defaults are no-ops that
/// preserve standard game behavior.
abstract class GameStage {
  const GameStage();

  String get name;
  bool get isBoss => false;

  /// Called by [GameController.setupLevel] before conveyors are built.
  /// Override to customise belt count, colors, or starting speed.
  void onSetup(GameController ctrl, int level) {}

  /// Override to customise spawn timing for this stage.
  /// Return null to use the default formula.
  double? spawnInterval(int level) => null;

  /// Called every frame the stage is active (after normal game logic).
  void onUpdate(GameController ctrl, double now, double dt) {}

  /// Called when a correct box reaches the gate.
  void onCorrectScore(GameController ctrl, int points) {}

  /// Called when a wrong box reaches the gate.
  void onWrongHit(GameController ctrl) {}

  /// Called when the stage ends (level-up, timeout, or defeat).
  void onEnd(GameController ctrl) {}

  /// Called when this stage becomes active (e.g. boss triggered on level-up).
  void onActivate(GameController ctrl, int level, double now) {}

  /// Return non-null to force every new combo to use this reward type.
  /// Null means the default random reward is used.
  SpecialType? overrideComboReward() => null;

  /// Called whenever a bomb special scores on [conveyorId].
  void onBombHit(GameController ctrl, int conveyorId, double now) {}
}

/// The default endless-wave stage — delegates everything to GameController's
/// built-in behaviour.  No overrides needed; this is a no-op placeholder.
class NormalStage extends GameStage {
  const NormalStage();
  @override
  String get name => 'normal';
}
