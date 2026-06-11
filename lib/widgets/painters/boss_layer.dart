part of '../game_painter.dart';

// Boss sprite dimensions (game coords). Override with your PNG via GameAssets.
const _bossW = 60.0;
const _bossH = 60.0;

extension BossLayer on GamePainter {
  void _drawBoss(Canvas canvas, double now) {
    final boss = game.bossState;
    if (boss == null) return;

    // Hide boss sprite once it has taken over the gate.
    if (boss.phase == BossPhase.entering || boss.phase == BossPhase.conquering) {
      _drawBossBody(canvas, boss, now);
    }

    // Draw the conquered-gate mouth once the boss has arrived.
    if (boss.phase != BossPhase.entering) {
      final conv = game.conveyors
          .where((c) => c.id == boss.conqueredConvId)
          .firstOrNull;
      if (conv != null) {
        _drawBossGate(canvas, conv, boss, now);
        if (boss.phase == BossPhase.conquered || boss.phase == BossPhase.dying) {
          _drawBossHealthBarAboveGate(canvas, conv, boss, now);
        }
      }
    }
  }

  // ── Boss body ──────────────────────────────────────────────────────────────

  void _drawBossBody(Canvas canvas, BossState boss, double now) {
    // Gentle vertical bob while walking.
    final bobY = boss.phase == BossPhase.entering
        ? sin(now * 0.008) * 3.0
        : 0.0;

    // Opacity fades out during death animation.
    double opacity = 1.0;
    if (boss.phase == BossPhase.dying) {
      opacity =
          1.0 - ((now - boss.phaseStartTime) / 1200.0).clamp(0.0, 1.0);
    }

    final rect = Rect.fromLTWH(
      boss.x - _bossW / 2,
      boss.y - _bossH + bobY,
      _bossW,
      _bossH,
    );

    final spriteImg = GameAssets.instance.bossSpriteImage;
    if (spriteImg != null) {
      _drawSprite(canvas, spriteImg, rect, opacity: opacity);
    } else {
      _drawProceduralBossBody(canvas, boss, rect, now, opacity);
    }

  }

  void _drawProceduralBossBody(
      Canvas canvas, BossState boss, Rect rect, double now, double opacity) {
    final pulse = 0.5 + 0.5 * sin(now * 0.004);

    // Angry glow aura when dying.
    if (boss.phase == BossPhase.dying) {
      canvas.drawOval(
        rect.inflate(8),
        (_p
          ..color = const Color(0xFFFF4500)
              .withValues(alpha: (0.3 + pulse * 0.4) * opacity)),
      );
    }

    // Body.
    canvas.drawOval(
        rect, (_p..color = const Color(0xFFCC0000).withValues(alpha: opacity)));

    // Eyes.
    final eyeY = rect.top + rect.height * 0.30;
    final eyeR = rect.width * 0.13;
    for (final ex in [rect.left + rect.width * 0.30, rect.left + rect.width * 0.70]) {
      canvas.drawCircle(
          Offset(ex, eyeY), eyeR, (_p..color = Colors.white.withValues(alpha: opacity)));
      canvas.drawCircle(
          Offset(ex + eyeR * 0.15, eyeY + eyeR * 0.2),
          eyeR * 0.5,
          (_p..color = Colors.black.withValues(alpha: opacity)));
    }

    // Mouth: shows as a fanged grin.
    final mouthTop = rect.top + rect.height * 0.60;
    final mouthRect = Rect.fromLTWH(
        rect.left + rect.width * 0.15, mouthTop, rect.width * 0.70, rect.height * 0.22);
    canvas.drawRRect(
        RRect.fromRectAndRadius(mouthRect, Radius.circular(mouthRect.height * 0.3)),
        (_p..color = const Color(0xFF1A0000).withValues(alpha: opacity)));
    // Fangs.
    final fangW = mouthRect.width / 4.5;
    for (int i = 0; i < 3; i++) {
      final fx = mouthRect.left + fangW * 0.5 + i * fangW * 1.2;
      final fPath = Path()
        ..moveTo(fx, mouthTop)
        ..lineTo(fx + fangW * 0.5, mouthTop)
        ..lineTo(fx + fangW * 0.25, mouthTop + mouthRect.height * 0.65)
        ..close();
      canvas.drawPath(fPath,
          (_p..color = Colors.white.withValues(alpha: opacity)));
    }

    // Flashing hit effect: brief white overlay triggered on combo reset.
    final hitFlash = boss.phase == BossPhase.dying
        ? (0.5 + 0.5 * sin(now * 0.03)) * opacity
        : 0.0;
    if (hitFlash > 0) {
      canvas.drawOval(
          rect,
          (_p..color = Colors.white.withValues(alpha: hitFlash * 0.6)));
    }
  }

  // ── Boss health bar (drawn above the boss gate) ───────────────────────────

  void _drawBossHealthBarAboveGate(
      Canvas canvas, Conveyor conv, BossState boss, double now) {
    double opacity;
    if (boss.phase == BossPhase.dying) {
      opacity = 1.0 - ((now - boss.phaseStartTime) / 1200.0).clamp(0.0, 1.0);
    } else {
      opacity = 1.0;
    }

    // Recompute gate top so the bar sits just above it.
    final layoutCenterX = GameController.gameWidth / 2;
    final xLean = (conv.x + conv.width / 2 - layoutCenterX) *
        GameConfig.conveyorPerspectiveXFactor;
    final perspDepth = GameConfig.perspDepth;
    final gatePerspScale = (conv.width * 1.6 - perspDepth) / conv.width;
    final gateH = GameConfig.gateSpriteHeight * gatePerspScale;
    final gateCenterX = conv.x + conv.width / 2 - xLean;
    final gateTop = conv.y - GameController.gateOffset - gateH;

    const barW = 70.0;
    const barH = 7.0;
    const pad  = 1.5;
    final barX = gateCenterX - barW / 2;
    final barY = gateTop - barH - 12;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(barX, barY, barW, barH),
          const Radius.circular(3)),
      (_p..color = const Color(0xFF1E293B).withValues(alpha: opacity)),
    );
    final fill = (boss.health / boss.maxHealth).clamp(0.0, 1.0);
    if (fill > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barX + pad, barY + pad,
              (barW - pad * 2) * fill, barH - pad * 2),
          const Radius.circular(2),
        ),
        (_p..color = const Color(0xFFEF4444).withValues(alpha: opacity)),
      );
    }
    _drawText(canvas, 'BOSS HP', gateCenterX, barY - 11,
        color: const Color(0xFFFF4444).withValues(alpha: opacity),
        fontSize: 9,
        fontWeight: FontWeight.bold,
        align: TextAlign.center);
  }

  // ── Boss gate (open mouth replacing the normal gate) ──────────────────────

  void _drawBossGate(Canvas canvas, Conveyor conv, BossState boss, double now) {
    final perspDepth    = GameConfig.perspDepth;
    final layoutCenterX = GameController.gameWidth / 2;
    final xLean = (conv.x + conv.width / 2 - layoutCenterX) *
        GameConfig.conveyorPerspectiveXFactor;

    // UP belt: gate sprite at the top of the belt.
    final gatePerspScale = (conv.width * 1.6 - perspDepth) / conv.width;
    final gateW = (conv.width + 6) * gatePerspScale;
    final gateH = GameConfig.gateSpriteHeight * gatePerspScale;
    final gateX = conv.x + conv.width / 2 - xLean - gateW / 2;
    final gateY = conv.y - GameController.gateOffset - gateH;
    final gateRect = Rect.fromLTWH(gateX, gateY, gateW, gateH);

    // Fade in during conquering, fade out during dying.
    double opacity;
    if (boss.phase == BossPhase.conquering) {
      opacity = ((now - boss.phaseStartTime) / 900.0).clamp(0.0, 1.0);
    } else if (boss.phase == BossPhase.dying) {
      opacity =
          1.0 - ((now - boss.phaseStartTime) / 1200.0).clamp(0.0, 1.0);
    } else {
      opacity = 1.0;
    }

    final gateImg = GameAssets.instance.bossGateImage;
    if (gateImg != null) {
      _drawSprite(canvas, gateImg, gateRect, opacity: opacity);
    } else {
      _drawProceduralBossGate(canvas, gateRect, boss, now, opacity);
    }
  }

  void _drawProceduralBossGate(
      Canvas canvas, Rect r, BossState boss, double now, double opacity) {
    final pulse = 0.5 + 0.5 * sin(now * 0.006);
    final s     = r.height / GameConfig.gateSpriteHeight; // scale factor

    // Red face background.
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(4 * s)),
      (_p..color = const Color(0xFFCC0000).withValues(alpha: opacity)),
    );

    // Open mouth (entry for boxes — this is the hit zone).
    final mouthRect = Rect.fromLTWH(
        r.left + r.width * 0.08,
        r.top + r.height * 0.40,
        r.width * 0.84,
        r.height * 0.52);
    canvas.drawRRect(
      RRect.fromRectAndRadius(mouthRect, Radius.circular(3 * s)),
      (_p..color = const Color(0xFF1A0000).withValues(alpha: opacity)),
    );

    // Upper teeth.
    final toothW = mouthRect.width / 4;
    for (int i = 0; i < 4; i++) {
      canvas.drawRect(
        Rect.fromLTWH(mouthRect.left + i * toothW + s,
            mouthRect.top, toothW - s * 2, r.height * 0.18),
        (_p..color = Colors.white.withValues(alpha: opacity)),
      );
    }

    // Glowing eyes.
    final eyeY = r.top + r.height * 0.20;
    final eyeR = r.height * 0.12;
    final eyeGlow = const Color(0xFFFFFF00);
    for (final ex in [r.left + r.width * 0.25, r.left + r.width * 0.75]) {
      canvas.drawCircle(
        Offset(ex, eyeY),
        eyeR,
        (_p..color = eyeGlow.withValues(alpha: (0.7 + pulse * 0.3) * opacity)),
      );
      canvas.drawCircle(
        Offset(ex, eyeY),
        eyeR * 0.5,
        (_p..color = Colors.black.withValues(alpha: opacity)),
      );
    }

    // Pulsing outline.
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.inflate(2 * s), Radius.circular(5 * s)),
      (_sp
        ..color = const Color(0xFFFF3300)
            .withValues(alpha: (0.5 + pulse * 0.5) * opacity)
        ..strokeWidth = 2.5 * s),
    );
  }
}
