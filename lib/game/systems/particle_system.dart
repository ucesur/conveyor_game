part of '../game_controller.dart';

extension ParticleSystem on GameController {
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

  void _spawnExplosion(double x, double y) {
    const boom = [
      Color(0xFFFF6600), Color(0xFFFFCC00), Color(0xFFFF3300), Color(0xFFFFFFFF),
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

  void _spawnIceEffect(double x, double y) {
    const ice = [
      Color(0xFF7DD3FC), Color(0xFFBAE6FD), Color(0xFFFFFFFF), Color(0xFF0EA5E9),
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

  void _updateBeltExplosions(double now) {
    beltExplosions.removeWhere((e) => now - e.startTime >= e.duration);
  }
}
