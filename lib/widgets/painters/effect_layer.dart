part of '../game_painter.dart';

extension EffectLayer on GamePainter {
  void _drawParticles(Canvas canvas, double now) {
    if (game.particles.isEmpty) return;
    for (final p in game.particles) {
      final t = ((now - p.startTime) / p.lifetime).clamp(0.0, 1.0);
      _particlePaint.color = p.color.withValues(alpha: 1 - t);
      canvas.drawCircle(Offset(p.x, p.y), p.size * (1 - t * 0.3), _particlePaint);
    }
  }

  void _drawPopups(Canvas canvas, double now) {
    for (final p in game.popups) {
      final t = ((now - p.createdAt) / 800).clamp(0.0, 1.0);
      _drawText(canvas, p.text, p.x, p.y - 30 * t,
          color: p.color.withValues(alpha: 1 - t),
          fontSize: p.size,
          fontWeight: FontWeight.bold,
          align: TextAlign.center);
    }
  }
}
