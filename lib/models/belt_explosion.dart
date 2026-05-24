/// A fire wave that travels from the gate to the generator end of a belt
/// after a bomb scores. Purely visual — no gameplay effect.
class BeltExplosion {
  final int conveyorId;
  double startTime; // mutable: shifted on pause/resume like other timestamps
  final double duration;
  final double fromY; // gate-side belt edge (wave origin)
  final double toY;   // generator-side belt edge (wave destination)

  BeltExplosion({
    required this.conveyorId,
    required this.startTime,
    required this.duration,
    required this.fromY,
    required this.toY,
  });
}
