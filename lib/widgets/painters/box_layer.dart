part of '../game_painter.dart';

extension BoxLayer on GamePainter {
  void _drawTrail(Canvas canvas) {
    if (game.draggedBoxId == null) return;
    Box? b;
    for (final box in game.boxes) {
      if (box.id == game.draggedBoxId) { b = box; break; }
    }
    if (b == null || b.trail == null || b.trail!.isEmpty) return;

    final trail = b.trail!;
    for (int i = 0; i < trail.length; i++) {
      final pt    = trail[i];
      final frac  = i / trail.length;
      final w     = b.size * (0.5 + frac * 0.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(pt.dx + b.size / 2 - w / 2,
                        pt.dy + b.size / 2 - w / 2, w, w),
          const Radius.circular(5)),
        Paint()..color = b.color.bg.withValues(alpha: frac * 0.35),
      );
    }
  }

  void _drawBox(Canvas canvas, Box box) {
    final isDragged = game.draggedBoxId == box.id;
    final isThrown  = box.throwAnim != null;
    Conveyor? conv;
    for (final c in game.conveyors) {
      if (c.id == box.conveyorId) { conv = c; break; }
    }
    final onMaint = conv != null && conv.maintenance && !isDragged && !isThrown;
    if (box.entering && !isDragged && !isThrown) return;

    double scaleX = 1, scaleY = 1, rotation = 0, liftY = 0;
    double opacity = onMaint ? 0.7 : 1.0;

    if (isDragged) {
      final elapsed   = (game.currentTime - (box.dragStartTime ?? game.currentTime)) / 1000;
      final pickEased = 1 - pow(1 - min(1.0, elapsed * 5), 3).toDouble();
      scaleX = scaleY = 1 + pickEased * 0.35;
      liftY  = -pickEased * 6;
      rotation = (game.currentTime * 0.35) % 360 +
                 max(-25.0, min(25.0, (box.vx ?? 0.0) * 2.5));
    } else if (isThrown) {
      final pose  = game.throwPose(box);
      scaleX      = pose.scaleX;
      scaleY      = pose.scaleY;
      rotation    = pose.rotation;
      liftY       = pose.liftY;
      opacity    *= pose.opacity;
    }

    // Perspective
    double perspScale = 1.0;
    double leanX      = 0.0;
    if (!isDragged && !isThrown && conv != null) {
      final convH  = game.getCurrentHeight(conv, game.currentTime);
      final beltT  = ((box.y + box.size / 2 - conv.y) / convH).clamp(0.0, 1.0);
      perspScale   = (conv.width - 2 * GameConfig.perspDepth * (1 - beltT)) / conv.width;
      final xl     = (conv.x + conv.width / 2 - GameController.gameWidth / 2) *
                     GameConfig.conveyorPerspectiveXFactor;
      leanX        = -xl * (1 - beltT);
    }

    final cx = box.x + leanX + box.size / 2;
    final cy = box.y + box.size / 2 + liftY;

    // Shadow
    if (isDragged || isThrown) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(box.x + box.size / 2, box.y + box.size + 4),
            width: box.size * 0.7, height: 6),
        (_p..color = Colors.black.withValues(alpha: 0.3)),
      );
    }

    // Motion streaks
    double? streakVx = isDragged ? box.vx : (isThrown ? (box.throwAnim!.endX - box.throwAnim!.startX) * 0.15 : null);
    double? streakVy = isDragged ? box.vy : (isThrown ? (box.throwAnim!.endY - box.throwAnim!.startY) * 0.15 : null);
    if (streakVx != null && (streakVx.abs() > 2 || (streakVy ?? 0).abs() > 2)) {
      final speed = sqrt(streakVx * streakVx + (streakVy ?? 0) * (streakVy ?? 0));
      final nx = speed > 0 ? streakVx / speed : 0.0;
      final ny = speed > 0 ? (streakVy ?? 0) / speed : 0.0;
      for (int i = 0; i < 3; i++) {
        final sl = 8 + i * 4;
        canvas.drawLine(
          Offset(cx - nx * (sl + i * 6), cy - ny * (sl + i * 6)),
          Offset(cx - nx * (i * 4),      cy - ny * (i * 4)),
          (_sp..color = box.color.light.withValues(alpha: 0.5 - i * 0.12)
               ..strokeWidth = 3 - i * 0.7
               ..strokeCap = StrokeCap.round),
        );
      }
    }

    if (isDragged || isThrown) {
      canvas.drawCircle(Offset(cx, cy), box.size * 0.9,
          (_p..color = box.color.bg.withValues(alpha: 0.15)));
    }

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rotation * pi / 180);
    canvas.scale(scaleX * perspScale, scaleY * perspScale);
    canvas.translate(-cx, -cy);

    final bodyRect = Rect.fromLTWH(box.x + leanX, box.y, box.size, box.size);
    final specialImg = box.specialType != null
        ? GameAssets.instance.specialImage(box.specialType!)
        : null;
    if (specialImg != null) {
      _drawSprite(canvas, specialImg, bodyRect, opacity: opacity);
    } else {
      final boxImg = GameAssets.instance.boxImage(box.color);
      if (boxImg != null) {
        _drawSprite(canvas, boxImg, bodyRect, opacity: opacity);
      } else if (box.specialType != null) {
        _drawProceduralSpecialBox(canvas, box, opacity, xOffset: leanX);
      } else {
        _drawProceduralBox(canvas, box, opacity, xOffset: leanX);
      }
    }
    canvas.restore();

    if (game.debugSlots) {
      final anim  = box.throwAnim;
      final label = anim != null && !box.onConveyor
          ? '→${anim.targetSlot}'
          : box.slotIndex == null ? 'E'
          : box.slotIndex == 9999 ? 'X'
          : '${box.slotIndex}';
      final tp = TextPainter(
        text: TextSpan(text: label,
            style: const TextStyle(color: Color(0xFFFFFF00), fontSize: 11, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(box.x + leanX + (box.size - tp.width) / 2,
                              box.y + (box.size - tp.height) / 2));
    }
  }

  void _drawProceduralBox(Canvas canvas, Box box, double opacity, {double xOffset = 0.0}) {
    final x = box.x + xOffset;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, box.y, box.size, box.size),
        const Radius.circular(6)), (_p..color = box.color.dark.withValues(alpha: opacity)));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x+2, box.y+2, box.size-4, box.size-4),
        const Radius.circular(5)), (_p..color = box.color.bg.withValues(alpha: opacity)));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x+4, box.y+4, box.size-8, 6),
        const Radius.circular(3)), (_p..color = box.color.light.withValues(alpha: opacity * 0.7)));
    canvas.drawCircle(Offset(x + box.size / 2, box.y + box.size / 2 + 2), 6,
        (_p..color = box.color.light.withValues(alpha: opacity * 0.9)));
  }

  void _drawProceduralSpecialBox(Canvas canvas, Box box, double opacity, {double xOffset = 0.0}) {
    final x = box.x + xOffset;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, box.y, box.size, box.size),
        const Radius.circular(6)), (_p..color = const Color(0xFF1A1A1A).withValues(alpha: opacity)));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, box.y, box.size, box.size),
        const Radius.circular(6)),
        (_sp..color = const Color(0xFFFF6600).withValues(alpha: opacity * 0.9)..strokeWidth = 2));
    final icon = switch (box.specialType) { SpecialType.bomb => '💣', _ => '?' };
    _drawText(canvas, icon, x + box.size / 2, box.y + box.size / 2,
        color: Colors.white.withValues(alpha: opacity),
        fontSize: 22, align: TextAlign.center, baselineCenter: true);
  }

  void _drawFallingBoxes(Canvas canvas) {
    for (final fb in game.fallingBoxes) {
      final totalDist = (fb.disappearY - fb.startY).abs();
      final progress  = totalDist > 0
          ? ((fb.y - fb.startY).abs() / totalDist).clamp(0.0, 1.0) : 1.0;
      final scale   = 1.0 - progress;
      final opacity = 1.0 - progress;
      if (scale <= 0.0) continue;

      final cx = fb.x + fb.size / 2;
      final cy = fb.y + fb.size / 2;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(scale, scale);
      canvas.translate(-cx, -cy);

      final boxImg = GameAssets.instance.boxImage(fb.color);
      if (boxImg != null) {
        _drawSprite(canvas, boxImg, Rect.fromLTWH(fb.x, fb.y, fb.size, fb.size), opacity: opacity);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(fb.x, fb.y, fb.size, fb.size),
            const Radius.circular(6)), (_p..color = fb.color.dark.withValues(alpha: opacity)));
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(fb.x+2, fb.y+2, fb.size-4, fb.size-4), const Radius.circular(5)),
            (_p..color = fb.color.bg.withValues(alpha: opacity)));
      }
      canvas.restore();
    }
  }
}
