import 'dart:ui';

/// Short-lived visual effect (dust, sparks) spawned by gameplay events
/// like a box landing after a throw. Position/velocity are integrated by
/// GameController each frame; the painter draws each particle as a small
/// circle that fades and shrinks over [lifetime].
class Particle {
  double x;
  double y;
  double vx;
  double vy;
  double gravity;
  double drag;
  double size;
  Color color;
  double startTime;
  double lifetime;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.gravity,
    required this.drag,
    required this.size,
    required this.color,
    required this.startTime,
    required this.lifetime,
  });
}
