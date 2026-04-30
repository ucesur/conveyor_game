/// Tracks the in-progress "LEVEL N" splash that animates between levels.
class LevelTransition {
  final int level;
  double startTime;

  LevelTransition({required this.level, required this.startTime});
}
