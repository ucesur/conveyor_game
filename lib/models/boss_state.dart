enum BossPhase { entering, conquering, conquered, dying }

class BossState {
  BossPhase phase;
  double x;
  final double y;
  final double targetX;
  final int conqueredConvId;
  int health;
  final int maxHealth;
  double phaseStartTime;

  BossState({
    required this.phase,
    required this.x,
    required this.y,
    required this.targetX,
    required this.conqueredConvId,
    required this.health,
    required this.maxHealth,
    required this.phaseStartTime,
  });
}
