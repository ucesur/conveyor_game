part of '../game_painter.dart';

extension BeltLayer on GamePainter {
  void _drawGeneratorBacks(Canvas canvas, double now) {
    final img = GameAssets.instance.generatorBackImage;
    if (img == null) return;
    for (final conv in game.conveyors) {
      if (conv.direction != ConveyorDirection.up) continue;
      final h    = game.getCurrentHeight(conv, now);
      final genW = conv.width + GameConfig.generatorBackExtraW;
      final genH = genW * (img.height / img.width);
      _drawSprite(canvas, img,
          Rect.fromLTWH(conv.x + GameConfig.generatorBackOffsetX,
              conv.y + h + GameConfig.generatorBackOffsetY, genW, genH));
    }
  }

  void _drawConveyor(Canvas canvas, Conveyor conv, double now) {
    final h      = game.getCurrentHeight(conv, now);
    final offset = game.beltOffset(conv.speed, conv.direction);
    final isDown = conv.direction == ConveyorDirection.down;
    final gateY  = isDown
        ? conv.y + h + GameController.gateOffset
        : conv.y - GameController.gateOffset - GameController.gateHeight;
    final flash       = conv.maintenance ? game.maintenanceFlash() : 0.0;
    final rFlash      = conv.resizing    ? game.resizeFlash()      : 0.0;
    final frozenPulse = conv.frozen ? (0.5 + 0.5 * sin(now * 0.005)) : 0.0;
    final pendingArrow = (conv.pendingDirection ?? conv.direction) == ConveyorDirection.down ? '▼' : '▲';
    final isGrowing   = conv.resizing && conv.toHeight > conv.fromHeight;

    final allowed   = game.allowedTargets;
    final isAllowed = allowed != null && allowed.contains(conv.id);
    final isForbidden = allowed != null && !allowed.contains(conv.id);
    final hlPulse   = 0.5 + 0.5 * sin(now * 0.008);

    // Trapezoid corners
    final perspDepth    = GameConfig.perspDepth;
    final layoutCenterX = GameController.gameWidth / 2;
    final xLean = (conv.x + conv.width / 2 - layoutCenterX) * GameConfig.conveyorPerspectiveXFactor;
    final tlX = conv.x + perspDepth - xLean;
    final trX = conv.x + conv.width - perspDepth - xLean;
    final blX = conv.x;
    final brX = conv.x + conv.width;
    final topY = conv.y;
    final botY = conv.y + h;

    // Geometry cache
    final cached = _convGeomCache[conv.id];
    final _ConvGeom geom;
    if (cached != null && cached.h == h && cached.xLean == xLean) {
      geom = cached;
    } else {
      final path = Path()
        ..moveTo(tlX, topY)..lineTo(trX, topY)
        ..lineTo(brX, botY)..lineTo(blX, botY)..close();
      Float64List? matrix;
      if (xLean != 0.0) {
        final shear = xLean / h;
        final tx    = -xLean * (conv.y + h) / h;
        matrix = Float64List.fromList([1,0,0,0, shear,1,0,0, 0,0,1,0, tx,0,0,1]);
      }
      geom = _ConvGeom(h: h, xLean: xLean, bodyPath: path, shearMatrix: matrix);
      _convGeomCache[conv.id] = geom;
    }
    final bodyPath = geom.bodyPath;

    // Allowed-target glow
    if (isAllowed && !conv.maintenance) {
      const pad = 6.0;
      canvas.drawPath(
        Path()
          ..moveTo(tlX-pad, topY-pad)..lineTo(trX+pad, topY-pad)
          ..lineTo(brX+pad, botY+pad)..lineTo(blX-pad, botY+pad)..close(),
        (_sp..color = const Color(0xFF22C55E).withValues(alpha: 0.4 + hlPulse * 0.5)
            ..strokeWidth = 2),
      );
    }
    if (isForbidden) {
      const pad = 2.0;
      canvas.drawPath(
        Path()
          ..moveTo(tlX-pad, topY-pad)..lineTo(trX+pad, topY-pad)
          ..lineTo(brX+pad, botY+pad)..lineTo(blX-pad, botY+pad)..close(),
        (_p..color = const Color(0xFFEF4444).withValues(alpha: 0.08)),
      );
    }

    // Generator front
    if (isDown) {
      final genFront = GameAssets.instance.generatorFrontImage;
      if (genFront != null) {
        final genW = trX - tlX + GameConfig.generatorFrontExtraW;
        final genH = genW * (genFront.height / genFront.width);
        _drawSprite(canvas, genFront,
            Rect.fromLTWH(tlX + GameConfig.generatorFrontOffsetX, conv.y - genH, genW, genH));
      } else if (!conv.maintenance) {
        _drawText(canvas, '↓', conv.x + conv.width / 2, conv.y - 6,
            color: const Color(0xFF64748B), fontSize: 14,
            fontWeight: FontWeight.bold, align: TextAlign.center);
      }
    } else if (GameAssets.instance.generatorBackImage == null && !conv.maintenance) {
      _drawText(canvas, '↑', conv.x + conv.width / 2, conv.y + h + 6,
          color: const Color(0xFF64748B), fontSize: 14,
          fontWeight: FontWeight.bold, align: TextAlign.center);
    }

    // Belt body (fallback color when no sprite)
    final convImg = GameAssets.instance.conveyorImage(conv.color);
    if (convImg == null) canvas.drawPath(bodyPath, _beltFallbackPaint);

    // Scrolling surface
    canvas.save();
    canvas.clipPath(bodyPath);
    canvas.save();
    if (geom.shearMatrix != null) canvas.transform(geom.shearMatrix!);
    if (convImg != null) {
      final tileH = conv.width * (convImg.height / convImg.width);
      final scroll = (conv.maintenance || conv.frozen) ? 0.0 : (offset % tileH);
      final numTiles = (h / tileH).ceil() + 2;
      for (int i = 0; i < numTiles; i++) {
        _drawSprite(canvas, convImg,
            Rect.fromLTWH(conv.x, conv.y + i * tileH + scroll - tileH, conv.width, tileH));
      }
    } else if (!conv.maintenance && !conv.frozen) {
      final scroll = offset % 24;
      _p.color = const Color(0xFF64748B).withValues(alpha: 0.5);
      for (int i = 0; i < (h / 24).ceil() + 2; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(conv.x + 4, conv.y + i * 24 + scroll - 24, conv.width - 8, 12),
              const Radius.circular(2)),
          _p,
        );
      }
    }
    canvas.restore();

    // Returns visual center-X at fractional belt depth t (0=top, 1=bottom).
    double beltCenterAt(double t) => conv.x + conv.width / 2 - xLean * (1 - t);

    // Resize overlay
    if (conv.resizing) {
      canvas.drawPath(bodyPath,
          (_p..color = const Color(0xFF06B6D4).withValues(alpha: 0.15 + rFlash * 0.25)));
      final ao = 0.7 + rFlash * 0.3;
      for (final entry in [(conv.y + 18, beltCenterAt(18/h), isGrowing ? '↑':'↓'),
                           (conv.y + h - 6, beltCenterAt((h-6)/h), isGrowing ? '↓':'↑')]) {
        _drawText(canvas, entry.$3, entry.$2, entry.$1,
            color: const Color(0xFF06B6D4).withValues(alpha: ao),
            fontSize: 16, fontWeight: FontWeight.bold, align: TextAlign.center);
      }
    }

    // Maintenance overlay
    if (conv.maintenance) {
      final stripeRect = Rect.fromLTRB(min(tlX, blX), conv.y, max(trX, brX), conv.y + h);
      _drawDiagonalStripes(canvas, stripeRect, opacity: 0.35 + flash * 0.35);
      for (final yPos in [conv.y + 20, conv.y + h - 20]) {
        final bx = beltCenterAt((yPos - conv.y) / h);
        canvas.drawCircle(Offset(bx, yPos), 10,
            (_p..color = const Color(0xFF0F172A).withValues(alpha: 0.9)));
        _drawText(canvas, pendingArrow, bx, yPos,
            color: const Color(0xFFFBBF24), fontSize: 14,
            fontWeight: FontWeight.bold, align: TextAlign.center, baselineCenter: true);
      }
    }

    // Frozen overlay
    if (conv.frozen) {
      canvas.drawPath(bodyPath,
          (_p..color = const Color(0xFF00BFFF).withValues(alpha: 0.18 + frozenPulse * 0.12)));
      canvas.save();
      if (geom.shearMatrix != null) canvas.transform(geom.shearMatrix!);
      final frostRng = Random(conv.id * 31 + (now / 220).toInt());
      for (int i = 0; i < 10; i++) {
        _p.color = const Color(0xFFBAE6FD).withValues(alpha: 0.30 + frozenPulse * 0.45);
        canvas.drawCircle(
            Offset(conv.x + 3 + frostRng.nextDouble() * (conv.width - 6),
                   conv.y + 3 + frostRng.nextDouble() * (h - 6)),
            1.2 + frostRng.nextDouble() * 2.0, _p);
      }
      canvas.restore();
      for (final yPos in [conv.y + 22.0, conv.y + h - 22.0]) {
        if (yPos < conv.y + 10 || yPos > conv.y + h - 10) continue;
        final bx = beltCenterAt((yPos - conv.y) / h);
        canvas.drawCircle(Offset(bx, yPos), 10,
            (_p..color = const Color(0xFF0F172A).withValues(alpha: 0.85)));
        _drawText(canvas, '❄', bx, yPos,
            color: const Color(0xFF7DD3FC).withValues(alpha: 0.85 + frozenPulse * 0.15),
            fontSize: 13, fontWeight: FontWeight.bold,
            align: TextAlign.center, baselineCenter: true);
      }
    }

    _drawBeltExplosion(canvas, conv, now, geom);
    canvas.restore(); // bodyPath clip

    // Ghost drop target
    final slots = game.landingSlots;
    if (slots != null && slots.containsKey(conv.id)) {
      final ghostY       = slots[conv.id]!;
      const ghostSize    = GameController.boxSize;
      final beltT        = ((ghostY + ghostSize / 2 - conv.y) / h).clamp(0.0, 1.0);
      final perspScale   = (conv.width - 2 * perspDepth * (1 - beltT)) / conv.width;
      final visSize      = ghostSize * perspScale;
      final ghostDrawX   = conv.x + conv.width / 2 - visSize / 2;
      final ghostDrawY   = ghostY + ghostSize / 2 * (1 - perspScale);
      final draggedBox   = game.boxes.where((b) => b.id == game.draggedBoxId).firstOrNull;
      final fillColor    = draggedBox?.color.bg ?? Colors.white;
      final borderColor  = draggedBox?.color.light ?? Colors.white;
      final pulse        = 0.65 + 0.35 * sin(now * 0.006);
      canvas.save();
      canvas.clipPath(bodyPath);
      if (geom.shearMatrix != null) canvas.transform(geom.shearMatrix!);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(ghostDrawX, ghostDrawY, visSize, visSize),
            const Radius.circular(6)),
        (_p..color = fillColor.withValues(alpha: 0.45 * pulse)),
      );
      _drawDashedRRect(canvas,
          RRect.fromRectAndRadius(
              Rect.fromLTWH(ghostDrawX, ghostDrawY, visSize, visSize),
              const Radius.circular(6)),
          borderColor, 2.0, 0.9 * pulse);
      canvas.restore();
    }

    // Rails
    Color leftRail  = const Color(0xFF94A3B8);
    Color rightRail = const Color(0xFF1E293B);
    if (conv.frozen) {
      leftRail = rightRail = const Color(0xFF38BDF8).withValues(alpha: 0.6 + frozenPulse * 0.4);
    } else if (conv.maintenance) {
      leftRail = rightRail = const Color(0xFFFBBF24).withValues(alpha: 0.6 + flash * 0.4);
    } else if (conv.resizing) {
      leftRail = rightRail = const Color(0xFF06B6D4).withValues(alpha: 0.6 + rFlash * 0.4);
    }
    final topRailW = GameConfig.railWidthTop;
    final botRailW = GameConfig.railWidthBottom;
    canvas.drawPath(
      Path()..moveTo(tlX, topY)..lineTo(tlX+topRailW, topY)
            ..lineTo(blX+botRailW, botY)..lineTo(blX, botY)..close(),
      (_p..color = leftRail),
    );
    canvas.drawPath(
      Path()..moveTo(trX-topRailW, topY)..lineTo(trX, topY)
            ..lineTo(brX, botY)..lineTo(brX-botRailW, botY)..close(),
      (_p..color = rightRail),
    );

    // Debug slots
    if (game.debugSlots) {
      canvas.save();
      canvas.clipPath(bodyPath);
      if (geom.shearMatrix != null) canvas.transform(geom.shearMatrix!);
      final scroll   = (conv.maintenance || conv.frozen) ? 0.0 : (offset % GameController.boxSize);
      final nVisible = (h / GameController.boxSize).ceil() + 2;
      for (int s = 0; s < nVisible; s++) {
        final slotTop  = conv.y + s * GameController.boxSize + scroll - GameController.boxSize;
        final slotRect = Rect.fromLTWH(conv.x + 3, slotTop, conv.width - 6, GameController.boxSize);
        canvas.drawRect(slotRect, (_p..color = const Color(0xFF00FF00).withValues(alpha: 0.08)));
        canvas.drawRect(slotRect, (_sp..color = const Color(0xFF00FF00).withValues(alpha: 0.6)..strokeWidth = 1));
      }
      canvas.restore();
    }

    // Gate
    final gatePerspScale = isDown ? 1.0 : (conv.width - 2 * perspDepth) / conv.width;
    final gateW    = (conv.width + 6) * gatePerspScale;
    final gateH    = GameConfig.gateSpriteHeight * gatePerspScale;
    final gateX    = isDown
        ? conv.x + conv.width / 2 - gateW / 2
        : conv.x + conv.width / 2 - xLean - gateW / 2;
    final scaledGateY = isDown ? gateY : conv.y - GameController.gateOffset - gateH;
    final gateRect    = Rect.fromLTWH(gateX, scaledGateY, gateW, gateH);
    final gateImg     = GameAssets.instance.gateImage(conv.color);
    if (gateImg != null) {
      _drawSprite(canvas, gateImg, gateRect, opacity: conv.maintenance ? 0.5 : 1.0);
    } else {
      _drawProceduralGate(canvas, conv, gateRect);
    }
  }

  void _drawProceduralGate(Canvas canvas, Conveyor conv, Rect r) {
    final op = conv.maintenance ? 0.5 : 1.0;
    final s  = r.height / 40.0;
    canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(4*s)),
        (_p..color = conv.color.dark.withValues(alpha: op)));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(r.left+3*s, r.top+3*s, r.width-6*s, r.height-6*s),
          Radius.circular(3*s)),
      (_p..color = conv.color.bg.withValues(alpha: op)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(r.left+4*s, r.top+6*s, r.width-8*s, 5*s),
          Radius.circular(2*s)),
      (_p..color = conv.color.light.withValues(alpha: conv.maintenance ? 0.3 : 0.7)),
    );
  }

  void _drawDiagonalStripes(Canvas canvas, Rect rect, {double opacity = 1.0}) {
    canvas.save();
    canvas.clipRect(rect);
    canvas.translate(rect.left + rect.width / 2, rect.top + rect.height / 2);
    canvas.rotate(pi / 4);
    final len = rect.width + rect.height;
    final yellow = const Color(0xFFFBBF24).withValues(alpha: opacity);
    final dark   = const Color(0xFF1E293B).withValues(alpha: opacity);
    for (double x = -len; x < len; x += 10) {
      canvas.drawRect(Rect.fromLTWH(x,   -len, 5, len * 2), (_p..color = yellow));
      canvas.drawRect(Rect.fromLTWH(x+5, -len, 5, len * 2), (_p..color = dark));
    }
    canvas.restore();
  }

  void _drawBeltExplosion(Canvas canvas, Conveyor conv, double now, _ConvGeom geom) {
    BeltExplosion? explosion;
    for (final e in game.beltExplosions) {
      if (e.conveyorId == conv.id) { explosion = e; break; }
    }
    if (explosion == null) return;

    final rawT = ((now - explosion.startTime) / explosion.duration).clamp(0.0, 1.0);
    final t    = 1.0 - pow(1.0 - rawT, 3.0);
    final waveFrontY  = explosion.fromY + (explosion.toY - explosion.fromY) * t;
    final movingDown  = explosion.toY > explosion.fromY;
    final burnedTop   = movingDown ? explosion.fromY : waveFrontY;
    final burnedBottom = movingDown ? waveFrontY : explosion.fromY;

    canvas.save();
    if (geom.shearMatrix != null) canvas.transform(geom.shearMatrix!);

    final left  = conv.x;
    final right = conv.x + conv.width;
    final ahead = movingDown ? 1.0 : -1.0;

    if (burnedBottom - burnedTop > 0.5) {
      _p.shader = ui.Gradient.linear(
        Offset(left, explosion.fromY), Offset(left, waveFrontY),
        const [Color(0x00FF4500), Color(0x88FF3300), Color(0xCCFF6600)],
        [0.0, 0.45, 1.0],
      );
      canvas.drawRect(Rect.fromLTRB(left, burnedTop, right, burnedBottom), _p);
      _p.shader = null;
    }

    const glowH = 26.0;
    _p.shader = ui.Gradient.linear(
      Offset(left, waveFrontY), Offset(left, waveFrontY + ahead * glowH),
      const [Color(0xCCFFFFFF), Color(0x66FF9900), Color(0x00FF6600)],
      [0.0, 0.45, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTRB(left,
          movingDown ? waveFrontY - 3 : waveFrontY - glowH + 3,
          right,
          movingDown ? waveFrontY + glowH : waveFrontY + 3),
      _p,
    );
    _p.shader = null;

    final rng = Random((now / 80).toInt() * 17 + conv.id * 97);
    for (int i = 0; i < 7; i++) {
      _p.color = const Color(0xFFFFCC00).withValues(alpha: 0.55 + rng.nextDouble() * 0.45);
      canvas.drawCircle(
          Offset(left + 3 + rng.nextDouble() * (conv.width - 6),
                 waveFrontY + ahead * rng.nextDouble() * 16),
          1.0 + rng.nextDouble() * 2.5, _p);
    }
    canvas.restore();
  }
}
