part of '../game_painter.dart';

extension EffectLayer on GamePainter {
  void _drawComboBalloon(Canvas canvas, double now) {
    final count = game.comboCount;
    if (count < 2) return;

    // Color tier
    final color = count >= 8 ? const Color(0xFFEF4444)
        : count >= 5       ? const Color(0xFFFF6600)
        : count >= 3       ? const Color(0xFFFBBF24)
        :                    const Color(0xFF22C55E);

    final gw = GameController.gameWidth;
    final cx = gw - GameConfig.comboBalloonWidth / 2 - 19.0;
    const cy = GameConfig.comboAreaTop + GameConfig.comboAreaHeight * 0.5;
    const rx = GameConfig.comboBalloonWidth / 2;
    const ry = GameConfig.comboBalloonHeight / 2;
    const tailH = GameConfig.comboBalloonTailH;

    // Gentle pulse
    final pulse = 1.0 + 0.05 * sin(now * 0.007);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(pulse);
    canvas.translate(-cx, -cy);

    final spriteRect = Rect.fromLTRB(cx - rx, cy - ry, cx + rx, cy + ry + tailH);
    final bubbleImg = GameAssets.instance.bubbleImage;
    if (bubbleImg != null) {
      _drawSprite(canvas, bubbleImg, spriteRect);
    } else {
      // Procedural fallback until sprite loads
      final bodyRect = Rect.fromCenter(
          center: Offset(cx, cy), width: rx * 2, height: ry * 2);
      canvas.drawOval(bodyRect, (_p..color = const Color(0xEE1E293B)));
      canvas.drawOval(bodyRect, (_sp..color = color..strokeWidth = 2.5));
      final tail = Path()
        ..moveTo(cx - 5, cy + ry - 2)
        ..lineTo(cx + 5, cy + ry - 2)
        ..lineTo(cx, cy + ry + tailH)
        ..close();
      canvas.drawPath(tail, (_p..color = const Color(0xEE1E293B)));
      canvas.drawPath(tail, (_sp..color = color..strokeWidth = 2.0));
    }

    // Count
    final fontSize = count >= 10 ? 18.0 : 24.0;
    _drawText(canvas, '×$count', cx, cy - 5,
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        align: TextAlign.center,
        baselineCenter: true);

    // Label
    _drawText(canvas, 'COMBO', cx, cy + 14,
        color: color,
        fontSize: 9,
        fontWeight: FontWeight.bold,
        align: TextAlign.center,
        letterSpacing: 1.2);

    canvas.restore();
  }

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
