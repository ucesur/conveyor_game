import 'dart:math';
import 'dart:ui' as ui show Image;
import 'package:flutter/material.dart';
import '../game/game_controller.dart';
import '../models/box.dart';
import '../models/conveyor.dart';
import '../models/falling_box.dart';
import '../models/game_assets.dart';

/// Paints the entire game scene onto a fixed 360x600 canvas —
/// the surrounding [FittedBox] scales it to fit the device viewport.
class GamePainter extends CustomPainter {
  final GameController game;

  GamePainter(this.game) : super(repaint: game);

  @override
  void paint(Canvas canvas, Size size) {
    // Scale from the game's fixed 360-wide coordinate space up to the widget's
    // actual pixel size. GameController.setGameSize keeps gameHeight at the
    // same aspect ratio as the widget, so a single uniform scale is correct.
    // _toGameCoords in GameScreen divides pointer positions by this same
    // scale — without it, taps wouldn't line up with painted boxes.
    final scale = size.width / GameController.gameWidth;
    canvas.scale(scale);

    final now = game.currentTime;

    _drawBackground(canvas);
    _drawHUD(canvas);

    for (final conv in game.conveyors) {
      _drawConveyor(canvas, conv, now);
    }
    _drawTrail(canvas);
    for (final box in game.boxes) {
      _drawBox(canvas, box);
    }
    _drawParticles(canvas, now);
    _drawFallingBoxes(canvas);
    _drawPopups(canvas, now);
  }

  // ---- Background ----
  void _drawBackground(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, GameController.gameWidth,
        GameController.gameHeight);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1E293B), Color(0xFF334155)],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  // ---- Top HUD: score / level / lives / progress bar ----
  void _drawHUD(Canvas canvas) {
    final bgPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, GameController.gameWidth, 60), bgPaint);

    _drawText(canvas, 'SCORE', 15, 28,
        color: const Color(0xFFFBBF24),
        fontSize: 14,
        fontWeight: FontWeight.bold);
    _drawText(canvas, '${game.score}', 15, 48,
        color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold);

    _drawText(canvas, 'LEVEL', GameController.gameWidth / 2, 28,
        color: const Color(0xFFFBBF24),
        fontSize: 14,
        fontWeight: FontWeight.bold,
        align: TextAlign.center);
    _drawText(canvas, '${game.level}', GameController.gameWidth / 2, 48,
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.bold,
        align: TextAlign.center);

    _drawText(canvas, 'LIVES', 345, 28,
        color: const Color(0xFFFBBF24),
        fontSize: 14,
        fontWeight: FontWeight.bold,
        align: TextAlign.right);

    for (int i = 0; i < 4; i++) {
      final alive = i < game.lives;
      final paint = Paint()
        ..color = alive ? const Color(0xFFEF4444) : const Color(0xFF475569);
      canvas.drawCircle(Offset(305 + i * 15, 44), 6, paint);
      if (alive) {
        final stroke = Paint()
          ..color = const Color(0xFFFCA5A5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawCircle(Offset(305 + i * 15, 44), 6, stroke);
      }
    }

    // Progress bar
    final currentLvlPts = game.pointsForLevel(game.level);
    final nextLvlPts = game.pointsForLevel(game.level + 1);
    final progressInLvl = game.score - currentLvlPts;
    final ptsNeeded = nextLvlPts - currentLvlPts;
    final pct = ptsNeeded == 0
        ? 0.0
        : min(100.0, (progressInLvl / ptsNeeded) * 100);

    canvas.drawRect(Rect.fromLTWH(0, 60, GameController.gameWidth, 4),
        Paint()..color = const Color(0xFF1E293B));
    canvas.drawRect(
        Rect.fromLTWH(0, 60, GameController.gameWidth * pct / 100, 4),
        Paint()..color = const Color(0xFFFBBF24));
  }

  // ---- Sprite blit with optional opacity (preserves source aspect ratio
  // expectations: caller picks the dst rect). ----
  void _drawSprite(Canvas canvas, ui.Image image, Rect dst,
      {double opacity = 1.0}) {
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (opacity < 1.0) {
      paint.colorFilter = ColorFilter.mode(
          Colors.white.withValues(alpha: opacity), BlendMode.modulate);
    }
    final src = Rect.fromLTWH(
        0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, dst, paint);
  }

  // ---- Conveyor belt ----
  void _drawConveyor(Canvas canvas, Conveyor conv, double now) {
    final h = game.getCurrentHeight(conv, now);
    final offset = game.beltOffset(conv.speed, conv.direction);
    final isDown = conv.direction == ConveyorDirection.down;
    final gateY = isDown
        ? conv.y + h + GameController.gateOffset
        : conv.y - GameController.gateOffset - GameController.gateHeight;
    final spawnLabelY = isDown ? conv.y - 6 : conv.y + h + 6;
    final flash = conv.maintenance ? game.maintenanceFlash() : 0.0;
    final rFlash = conv.resizing ? game.resizeFlash() : 0.0;
    final pendingArrow =
        (conv.pendingDirection ?? conv.direction) == ConveyorDirection.down
            ? '▼'
            : '▲';
    final isGrowing = conv.resizing && conv.toHeight > conv.fromHeight;

    final allowedTargets = game.allowedTargets;
    final isAllowedTarget =
        allowedTargets != null && allowedTargets.contains(conv.id);
    final isForbiddenTarget =
        allowedTargets != null && !allowedTargets.contains(conv.id);
    final highlightPulse = 0.5 + 0.5 * sin(now * 0.008);

    // Allowed-target dashed glow
    if (isAllowedTarget && !conv.maintenance) {
      _drawDashedRRect(
        canvas,
        RRect.fromRectAndRadius(
            Rect.fromLTWH(conv.x - 6, conv.y - 6, conv.width + 12, h + 12),
            const Radius.circular(6)),
        const Color(0xFF22C55E),
        2,
        0.4 + highlightPulse * 0.5,
      );
    }

    // Forbidden target tint
    if (isForbiddenTarget) {
      final paint = Paint()
        ..color = const Color(0xFFEF4444).withValues(alpha: 0.08);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(conv.x - 2, conv.y - 2, conv.width + 4, h + 4),
            const Radius.circular(5)),
        paint,
      );
    }

    // Spawn direction indicator above/below the belt
    if (!conv.maintenance) {
      _drawText(
        canvas,
        conv.direction == ConveyorDirection.down ? '↓' : '↑',
        conv.x + conv.width / 2,
        spawnLabelY,
        color: const Color(0xFF64748B),
        fontSize: 14,
        fontWeight: FontWeight.bold,
        align: TextAlign.center,
      );
    }

    // Belt body
    final bodyRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(conv.x, conv.y, conv.width, h),
        const Radius.circular(4));
    final convImg = GameAssets.instance.conveyorImage(conv.color);
    if (convImg == null) {
      canvas.drawRRect(bodyRRect, Paint()..color = const Color(0xFF475569));
    }

    // Scrolling belt surface — clip to belt body. Sprite tiles vertically
    // with the same scroll offset as boxes; procedural fallback paints the
    // 24px-period stripes.
    canvas.save();
    canvas.clipRRect(bodyRRect);
    if (convImg != null) {
      final tileH = conv.width * (convImg.height / convImg.width);
      final scroll = conv.maintenance ? 0.0 : (offset % tileH);
      final numTiles = (h / tileH).ceil() + 2;
      for (int i = 0; i < numTiles; i++) {
        final y = conv.y + (i * tileH + scroll) - tileH;
        _drawSprite(canvas, convImg,
            Rect.fromLTWH(conv.x, y, conv.width, tileH));
      }
    } else if (!conv.maintenance) {
      final scroll = offset % 24;
      final numStripes = (h / 24).ceil() + 2;
      final stripePaint = Paint()
        ..color = const Color(0xFF64748B).withValues(alpha: 0.5);
      for (int i = 0; i < numStripes; i++) {
        final stripeRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(conv.x + 4, conv.y + (i * 24 + scroll) - 24,
              conv.width - 8, 12),
          const Radius.circular(2),
        );
        canvas.drawRRect(stripeRect, stripePaint);
      }
    }

    // Resize flash overlay
    if (conv.resizing) {
      final fillPaint = Paint()
        ..color =
            const Color(0xFF06B6D4).withValues(alpha: 0.15 + rFlash * 0.25);
      canvas.drawRRect(bodyRRect, fillPaint);
      final arrowOpacity = 0.7 + rFlash * 0.3;
      _drawText(
        canvas,
        isGrowing ? '↑' : '↓',
        conv.x + conv.width / 2,
        conv.y + 18,
        color: const Color(0xFF06B6D4).withValues(alpha: arrowOpacity),
        fontSize: 16,
        fontWeight: FontWeight.bold,
        align: TextAlign.center,
      );
      _drawText(
        canvas,
        isGrowing ? '↓' : '↑',
        conv.x + conv.width / 2,
        conv.y + h - 6,
        color: const Color(0xFF06B6D4).withValues(alpha: arrowOpacity),
        fontSize: 16,
        fontWeight: FontWeight.bold,
        align: TextAlign.center,
      );
    }

    // Maintenance (reversing) overlay
    if (conv.maintenance) {
      _drawDiagonalStripes(canvas, Rect.fromLTWH(conv.x, conv.y, conv.width, h),
          opacity: 0.35 + flash * 0.35);

      // Center label
      final labelHeight = min(160.0, h - 20);
      final labelTop = conv.y + h / 2 - min(80.0, h / 2 - 10);
      final labelRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(conv.x + conv.width / 2 - 20, labelTop, 40, labelHeight),
        const Radius.circular(4),
      );
      canvas.drawRRect(
          labelRect, Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.85));

      if (h > 120) {
        // "MAINTENANCE" text, rotated 90° counterclockwise
        canvas.save();
        canvas.translate(conv.x + conv.width / 2, conv.y + h / 2);
        canvas.rotate(-pi / 2);
        _drawText(canvas, 'MAINTENANCE', 0, 0,
            color: const Color(0xFFFBBF24),
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            align: TextAlign.center,
            baselineCenter: true);
        canvas.restore();
      }

      // Pending-direction badges at both ends
      for (final yPos in [conv.y + 20, conv.y + h - 20]) {
        canvas.drawCircle(
            Offset(conv.x + conv.width / 2, yPos),
            10,
            Paint()
              ..color = const Color(0xFF0F172A).withValues(alpha: 0.9));
        _drawText(canvas, pendingArrow, conv.x + conv.width / 2, yPos,
            color: const Color(0xFFFBBF24),
            fontSize: 14,
            fontWeight: FontWeight.bold,
            align: TextAlign.center,
            baselineCenter: true);
      }
    }

    canvas.restore();

    // Ghost drop target — drawn on top of the belt surface, clipped to belt body
    final slots = game.landingSlots;
    if (slots != null && slots.containsKey(conv.id)) {
      final ghostY = slots[conv.id]!;
      const ghostSize = GameController.boxSize;
      final ghostX = conv.x + (conv.width - ghostSize) / 2;
      final draggedBox =
          game.boxes.where((b) => b.id == game.draggedBoxId).firstOrNull;
      final fillColor = draggedBox?.color.bg ?? Colors.white;
      final borderColor = draggedBox?.color.light ?? Colors.white;
      final pulse = 0.65 + 0.35 * sin(now * 0.006);

      canvas.save();
      canvas.clipRRect(bodyRRect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(ghostX, ghostY, ghostSize, ghostSize),
            const Radius.circular(6)),
        Paint()..color = fillColor.withValues(alpha: 0.45 * pulse),
      );
      canvas.restore();

      _drawDashedRRect(
        canvas,
        RRect.fromRectAndRadius(
            Rect.fromLTWH(ghostX, ghostY, ghostSize, ghostSize),
            const Radius.circular(6)),
        borderColor,
        2.0,
        0.9 * pulse,
      );
    }

    // Left + right rails with state-dependent color
    Color leftRailColor = const Color(0xFF94A3B8);
    Color rightRailColor = const Color(0xFF1E293B);
    if (conv.maintenance) {
      leftRailColor = const Color(0xFFFBBF24).withValues(alpha: 0.6 + flash * 0.4);
      rightRailColor = leftRailColor;
    } else if (conv.resizing) {
      leftRailColor = const Color(0xFF06B6D4).withValues(alpha: 0.6 + rFlash * 0.4);
      rightRailColor = leftRailColor;
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(conv.x, conv.y, 3, h), const Radius.circular(1)),
        Paint()..color = leftRailColor);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(conv.x + conv.width - 3, conv.y, 3, h),
            const Radius.circular(1)),
        Paint()..color = rightRailColor);

    // Drive-roller end caps
    final endCapFill = Paint()..color = const Color(0xFF1E293B);
    final endCapStroke = Paint()
      ..color = const Color(0xFF64748B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(conv.x + conv.width / 2, conv.y + 6), 5, endCapFill);
    canvas.drawCircle(Offset(conv.x + conv.width / 2, conv.y + 6), 5, endCapStroke);
    canvas.drawCircle(
        Offset(conv.x + conv.width / 2, conv.y + h - 6), 5, endCapFill);
    canvas.drawCircle(
        Offset(conv.x + conv.width / 2, conv.y + h - 6), 5, endCapStroke);

    // Speed pips in the middle of the belt
    if (!conv.maintenance && !conv.resizing && h > 80) {
      for (int i = 0; i < 3; i++) {
        final filled = conv.speed > (0.3 + i * 0.15);
        final paint = Paint()
          ..color = (filled
                  ? const Color(0xFFFBBF24)
                  : const Color(0xFF334155))
              .withValues(alpha: filled ? 0.9 : 0.6);
        canvas.drawCircle(
            Offset(conv.x + conv.width / 2, conv.y + h / 2 - 12 + i * 12),
            2,
            paint);
      }
    }

    // Debug: slot boundaries scrolling with the belt surface
    if (game.debugSlots) {
      canvas.save();
      canvas.clipRRect(bodyRRect);
      final scroll = conv.maintenance ? 0.0 : (offset % GameController.boxSize);
      final nVisible = (h / GameController.boxSize).ceil() + 2;
      final slotBorder = Paint()
        ..color = const Color(0xFF00FF00).withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      final slotFill = Paint()
        ..color = const Color(0xFF00FF00).withValues(alpha: 0.08);
      for (int s = 0; s < nVisible; s++) {
        final slotTop =
            conv.y + s * GameController.boxSize + scroll - GameController.boxSize;
        final slotRect = Rect.fromLTWH(
            conv.x + 3, slotTop, conv.width - 6, GameController.boxSize);
        canvas.drawRect(slotRect, slotFill);
        canvas.drawRect(slotRect, slotBorder);
      }
      canvas.restore();
    }

    // Colored gate at the end of the belt — sprite if available, otherwise
    // the layered procedural draw. Direction arrow is rendered on top of
    // both so the indicator stays legible regardless of art style.
    final gateRect =
        Rect.fromLTWH(conv.x - 3, gateY, conv.width + 6, 40);
    final gateImg = GameAssets.instance.gateImage(conv.color);
    final gateOpacity = conv.maintenance ? 0.5 : 1.0;
    if (gateImg != null) {
      _drawSprite(canvas, gateImg, gateRect, opacity: gateOpacity);
    } else {
      _drawProceduralGate(canvas, conv, gateY);
    }
  }

  // ---- Procedural gate fallback (used when no PNG is present) ----
  void _drawProceduralGate(Canvas canvas, Conveyor conv, double gateY) {
    final gateOpacity = conv.maintenance ? 0.5 : 1.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(conv.x - 3, gateY, conv.width + 6, 40),
          const Radius.circular(4)),
      Paint()..color = conv.color.dark.withValues(alpha: gateOpacity),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(conv.x, gateY + 3, conv.width, 34),
          const Radius.circular(3)),
      Paint()..color = conv.color.bg.withValues(alpha: gateOpacity),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(conv.x + 4, gateY + 6, conv.width - 8, 5),
          const Radius.circular(2)),
      Paint()
        ..color = conv.color.light.withValues(alpha: conv.maintenance ? 0.3 : 0.7),
    );
  }

  // ---- Diagonal maintenance stripes pattern ----
  void _drawDiagonalStripes(Canvas canvas, Rect rect, {double opacity = 1.0}) {
    canvas.save();
    canvas.clipRect(rect);
    // Use a rotated transform so stripes run diagonally
    canvas.translate(rect.left + rect.width / 2, rect.top + rect.height / 2);
    canvas.rotate(pi / 4);
    final len = rect.width + rect.height;
    final yellow = Paint()..color = const Color(0xFFFBBF24).withValues(alpha: opacity);
    final dark = Paint()..color = const Color(0xFF1E293B).withValues(alpha: opacity);
    for (double x = -len; x < len; x += 10) {
      canvas.drawRect(Rect.fromLTWH(x, -len, 5, len * 2), yellow);
      canvas.drawRect(Rect.fromLTWH(x + 5, -len, 5, len * 2), dark);
    }
    canvas.restore();
  }

  // ---- Dashed rounded-rect stroke (for allowed-target highlight) ----
  void _drawDashedRRect(
      Canvas canvas, RRect rrect, Color color, double strokeWidth, double opacity) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    const dashLen = 4.0;
    const gapLen = 3.0;
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final next = min(distance + dashLen, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLen;
      }
    }
  }

  // ---- Motion trail of the dragged box ----
  void _drawTrail(Canvas canvas) {
    if (game.draggedBoxId == null) return;
    Box? b;
    for (final box in game.boxes) {
      if (box.id == game.draggedBoxId) {
        b = box;
        break;
      }
    }
    if (b == null || b.trail == null || b.trail!.isEmpty) return;

    final trail = b.trail!;
    for (int i = 0; i < trail.length; i++) {
      final pt = trail[i];
      final alpha = (i / trail.length) * 0.35;
      final scale = 0.5 + (i / trail.length) * 0.5;
      final paint = Paint()..color = b.color.bg.withValues(alpha: alpha);
      final w = b.size * scale;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(pt.dx + b.size / 2 - w / 2,
              pt.dy + b.size / 2 - w / 2, w, w),
          const Radius.circular(5),
        ),
        paint,
      );
    }
  }

  // ---- Boxes ----
  // Three modes: normal (default pose), dragged (pickup scale + spin), and
  // throwing (pose comes from GameController.throwPose). Body uses the
  // PNG sprite when GameAssets has one for the color, else the procedural
  // 3-layer draw so the game runs without art assets.
  void _drawBox(Canvas canvas, Box box) {
    final isDragged = game.draggedBoxId == box.id;
    final isThrown = box.throwAnim != null;
    Conveyor? conv;
    for (final c in game.conveyors) {
      if (c.id == box.conveyorId) {
        conv = c;
        break;
      }
    }
    final onMaint = conv != null && conv.maintenance && !isDragged && !isThrown;

    double scaleX = 1, scaleY = 1, rotation = 0, liftY = 0;
    double opacity = (box.entering && !isDragged) || onMaint ? 0.7 : 1.0;

    if (isDragged) {
      final elapsed =
          (game.currentTime - (box.dragStartTime ?? game.currentTime)) / 1000;
      final pickT = min(1.0, elapsed * 5);
      final pickEased = 1 - pow(1 - pickT, 3).toDouble();
      scaleX = scaleY = 1 + pickEased * 0.35;
      liftY = -pickEased * 6;
      final spin = (game.currentTime * 0.35) % 360;
      final vx = box.vx ?? 0.0;
      final tilt = max(-25.0, min(25.0, vx * 2.5));
      rotation = spin + tilt;
    } else if (isThrown) {
      final pose = game.throwPose(box);
      scaleX = pose.scaleX;
      scaleY = pose.scaleY;
      rotation = pose.rotation;
      liftY = pose.liftY;
      opacity *= pose.opacity;
    }

    final cx = box.x + box.size / 2;
    final cy = box.y + box.size / 2 + liftY;

    // Floor shadow — stays at unlifted Y so the lift reads as height.
    if (isDragged || isThrown) {
      final shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.3);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(box.x + box.size / 2, box.y + box.size + 4),
          width: box.size * 0.7,
          height: 6,
        ),
        shadowPaint,
      );
    }

    // Motion streaks — for a thrown box, synthesize the velocity from the
    // throw vector so streaks trail from the source side.
    double? streakVx;
    double? streakVy;
    if (isDragged && box.vx != null) {
      streakVx = box.vx;
      streakVy = box.vy ?? 0.0;
    } else if (isThrown) {
      final anim = box.throwAnim!;
      final dx = anim.endX - anim.startX;
      final dy = anim.endY - anim.startY;
      streakVx = dx * 0.15;
      streakVy = dy * 0.15;
    }
    if (streakVx != null &&
        (streakVx.abs() > 2 || (streakVy ?? 0).abs() > 2)) {
      final double vx = streakVx;
      final double vy = streakVy ?? 0.0;
      final speed = sqrt(vx * vx + vy * vy);
      final double normX = speed > 0 ? vx / speed : 0.0;
      final double normY = speed > 0 ? vy / speed : 0.0;
      for (int i = 0; i < 3; i++) {
        final streakLen = 8 + i * 4;
        final paint = Paint()
          ..color = box.color.light.withValues(alpha: 0.5 - i * 0.12)
          ..strokeWidth = 3 - i * 0.7
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(cx - normX * (streakLen + i * 6),
              cy - normY * (streakLen + i * 6)),
          Offset(cx - normX * (i * 4), cy - normY * (i * 4)),
          paint,
        );
      }
    }

    // Outer aura during drag / throw
    if (isDragged || isThrown) {
      canvas.drawCircle(
        Offset(cx, cy),
        box.size * 0.9,
        Paint()..color = box.color.bg.withValues(alpha: 0.15),
      );
    }

    // Body — sprite or procedural, transformed around the lifted center.
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rotation * pi / 180);
    canvas.scale(scaleX, scaleY);
    canvas.translate(-cx, -cy);

    final boxImg = GameAssets.instance.boxImage(box.color);
    if (boxImg != null) {
      _drawSprite(
          canvas,
          boxImg,
          Rect.fromLTWH(box.x, box.y, box.size, box.size),
          opacity: opacity);
    } else {
      _drawProceduralBox(canvas, box, opacity);
    }
    canvas.restore();
  }

  void _drawProceduralBox(Canvas canvas, Box box, double opacity) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(box.x, box.y, box.size, box.size),
          const Radius.circular(6)),
      Paint()..color = box.color.dark.withValues(alpha: opacity),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(box.x + 2, box.y + 2, box.size - 4, box.size - 4),
          const Radius.circular(5)),
      Paint()..color = box.color.bg.withValues(alpha: opacity),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(box.x + 4, box.y + 4, box.size - 8, 6),
          const Radius.circular(3)),
      Paint()..color = box.color.light.withValues(alpha: opacity * 0.7),
    );
    canvas.drawCircle(
      Offset(box.x + box.size / 2, box.y + box.size / 2 + 2),
      6,
      Paint()..color = box.color.light.withValues(alpha: opacity * 0.9),
    );
  }

  // ---- Falling boxes (drop into gate after scoring) ----
  void _drawFallingBoxes(Canvas canvas) {
    for (final fb in game.fallingBoxes) {
      // Linear 0→1 over the full drop distance so the box shrinks and fades
      // continuously from the moment it leaves the belt until it vanishes.
      final totalDist = (fb.disappearY - fb.startY).abs();
      final progress = totalDist > 0
          ? ((fb.y - fb.startY).abs() / totalDist).clamp(0.0, 1.0)
          : 1.0;

      final scale = 1.0 - progress;
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
        _drawSprite(canvas, boxImg,
            Rect.fromLTWH(fb.x, fb.y, fb.size, fb.size),
            opacity: opacity);
      } else {
        _drawProceduralFallingBox(canvas, fb, opacity);
      }
      canvas.restore();
    }
  }

  void _drawProceduralFallingBox(Canvas canvas, FallingBox fb, double opacity) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(fb.x, fb.y, fb.size, fb.size),
          const Radius.circular(6)),
      Paint()..color = fb.color.dark.withValues(alpha: opacity),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(fb.x + 2, fb.y + 2, fb.size - 4, fb.size - 4),
          const Radius.circular(5)),
      Paint()..color = fb.color.bg.withValues(alpha: opacity),
    );
  }

  // ---- Particles (dust on landing, etc.) ----
  void _drawParticles(Canvas canvas, double now) {
    for (final p in game.particles) {
      final t = ((now - p.startTime) / p.lifetime).clamp(0.0, 1.0);
      final opacity = 1 - t;
      final size = p.size * (1 - t * 0.3);
      canvas.drawCircle(
        Offset(p.x, p.y),
        size,
        Paint()..color = p.color.withValues(alpha: opacity),
      );
    }
  }

  // ---- Popups (float up and fade) ----
  void _drawPopups(Canvas canvas, double now) {
    for (final p in game.popups) {
      final elapsed = now - p.createdAt;
      final t = (elapsed / 800).clamp(0.0, 1.0);
      final dy = -30 * t;
      final opacity = 1 - t;
      _drawText(canvas, p.text, p.x, p.y + dy,
          color: p.color.withValues(alpha: opacity),
          fontSize: p.size,
          fontWeight: FontWeight.bold,
          align: TextAlign.center);
    }
  }

  // ---- Text helper ----
  void _drawText(
    Canvas canvas,
    String text,
    double x,
    double y, {
    required Color color,
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.normal,
    double letterSpacing = 0,
    TextAlign align = TextAlign.left,
    bool baselineCenter = false,
    Color? strokeColor,
    double strokeWidth = 0,
  }) {
    final textStyle = TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
    );

    final textSpan = TextSpan(text: text, style: textStyle);
    final tp = TextPainter(
      text: textSpan,
      textAlign: align,
      textDirection: TextDirection.ltr,
    );
    tp.layout();

    double offsetX = x;
    double offsetY = y;
    if (align == TextAlign.center) {
      offsetX -= tp.width / 2;
    } else if (align == TextAlign.right) {
      offsetX -= tp.width;
    }
    if (baselineCenter) {
      offsetY -= tp.height / 2;
    } else {
      // Approximate SVG-style baseline positioning (y is the baseline, roughly)
      offsetY -= tp.height * 0.75;
    }

    // Optional stroke (for the big LEVEL number)
    if (strokeColor != null && strokeWidth > 0) {
      final strokePainter = TextPainter(
        text: TextSpan(
          text: text,
          style: textStyle.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..color = strokeColor,
          ),
        ),
        textAlign: align,
        textDirection: TextDirection.ltr,
      );
      strokePainter.layout();
      strokePainter.paint(canvas, Offset(offsetX, offsetY));
    }

    tp.paint(canvas, Offset(offsetX, offsetY));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
