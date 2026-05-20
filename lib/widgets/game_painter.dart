import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui show Image;
import 'package:flutter/material.dart';
import '../game/game_config.dart';
import '../game/game_controller.dart';
import '../models/box.dart';
import '../models/conveyor.dart';
import '../models/special_type.dart';
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
    if (game.comboArea != null) _drawComboArea(canvas, now);

    for (final conv in game.conveyors) {
      _drawConveyor(canvas, conv, now);
    }

    _drawTrail(canvas);
    for (final box in game.boxes) {
      _drawBox(canvas, box);
    }
    _drawParticles(canvas, now);
    _drawGeneratorBacks(canvas, now);
    _drawFallingBoxes(canvas);
    _drawPopups(canvas, now);
  }

  // ---- Combination area ----
  // Draws the recipe sequence and the reward gift. Progress is shown by
  // lighting up completed slots and pulsing the current target slot.
  // When the sequence is complete the panel border flashes and all slots
  // show a check mark until the next recipe generates (1 500 ms).
  void _drawComboArea(Canvas canvas, double now) {
    final area = game.comboArea!;
    final gw = GameController.gameWidth;
    final panelY = GameConfig.comboAreaTop;
    final panelH = GameConfig.comboAreaHeight;
    final boxSz = GameConfig.comboRecipeBoxSize;
    final spacer = GameConfig.comboRecipeSpacer;
    final startX = GameConfig.comboRecipeStartX;

    final isComplete = area.completionTime != null;
    final completePulse = isComplete
        ? (0.5 + 0.5 * sin((now - area.completionTime!) * 0.015)).clamp(0.0, 1.0)
        : 0.0;

    // Vertical center for recipe boxes inside the panel.
    final boxY = panelY + (panelH - boxSz) / 2;
    // Right edge of the last recipe box → used to place the separator.
    final recipeRight = startX +
        GameConfig.comboSlotCount * boxSz +
        (GameConfig.comboSlotCount - 1) * spacer;
    final sepX = recipeRight + 12.0;
    final rewardCenterX = (sepX + gw - 4) / 2;
    final rewardCenterY = panelY + panelH / 2;

    // Panel background
    final panelRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(4, panelY, gw - 8, panelH),
      const Radius.circular(8),
    );
    canvas.drawRRect(panelRRect, Paint()..color = const Color(0xFF0F172A));

    // Panel border — pulses gold on completion
    canvas.drawRRect(
      panelRRect,
      Paint()
        ..color = isComplete
            ? const Color(0xFFFBBF24).withValues(alpha: 0.6 + completePulse * 0.4)
            : const Color(0xFF1E3A5F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isComplete ? 2.0 : 1.0,
    );

    // Separator
    canvas.drawLine(
      Offset(sepX, panelY + 8),
      Offset(sepX, panelY + panelH - 8),
      Paint()
        ..color = const Color(0xFF1E3A5F)
        ..strokeWidth = 1,
    );

    // === Recipe boxes ===
    for (int i = 0; i < area.recipe.length; i++) {
      final color = area.recipe[i];
      final boxX = startX + i * (boxSz + spacer);
      final rect = Rect.fromLTWH(boxX, boxY, boxSz, boxSz);
      final isDone = i < area.progress || isComplete;
      final isCurrent = !isComplete && i == area.progress;
      final alpha = isDone || isCurrent ? 1.0 : 0.35;
      final pulse = isCurrent ? (0.5 + 0.5 * sin(now * 0.008)) : 0.0;

      // Box body — sprite if loaded, procedural fallback otherwise
      final boxImg = GameAssets.instance.boxImage(color);
      if (boxImg != null) {
        _drawSprite(canvas, boxImg, rect, opacity: alpha);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()..color = color.dark.withValues(alpha: alpha),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(boxX + 2, boxY + 2, boxSz - 4, boxSz - 4),
            const Radius.circular(5),
          ),
          Paint()..color = color.bg.withValues(alpha: alpha),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(boxX + 4, boxY + 4, boxSz - 8, 5),
            const Radius.circular(3),
          ),
          Paint()..color = color.light.withValues(alpha: alpha * 0.6),
        );
      }

      // Pulsing outline on the current target slot
      if (isCurrent) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(9)),
          Paint()
            ..color = color.light.withValues(alpha: 0.4 + pulse * 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }

      // Check mark on completed slots
      if (isDone) {
        _drawText(canvas, '✓',
            boxX + boxSz / 2, boxY + boxSz / 2,
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            align: TextAlign.center,
            baselineCenter: true);
      }
    }

    // === Reward section — shows the special item that will be spawned ===
    final rewardAlpha = isComplete ? (0.7 + completePulse * 0.3) : 1.0;
    const rewardColor = Color(0xFFFF6600);
    final specialImg = GameAssets.instance.specialImage(area.reward);
    final rewardLabel = switch (area.reward) {
      SpecialType.bomb => 'BOMB!',
    };
    final spriteSize = 32.0;
    final spriteRect = Rect.fromCenter(
      center: Offset(rewardCenterX, rewardCenterY - 6),
      width: spriteSize,
      height: spriteSize,
    );
    if (specialImg != null) {
      _drawSprite(canvas, specialImg, spriteRect, opacity: rewardAlpha);
    } else {
      // Procedural fallback: dark rounded square with bomb emoji
      canvas.drawRRect(
        RRect.fromRectAndRadius(spriteRect, const Radius.circular(6)),
        Paint()
          ..color = const Color(0xFF1A1A1A).withValues(alpha: rewardAlpha),
      );
      _drawText(canvas, '💣', rewardCenterX, rewardCenterY - 6,
          color: Colors.white.withValues(alpha: rewardAlpha),
          fontSize: 20,
          align: TextAlign.center,
          baselineCenter: true);
    }
    _drawText(canvas, rewardLabel,
        rewardCenterX, rewardCenterY + spriteSize / 2 + 2,
        color: rewardColor.withValues(alpha: rewardAlpha),
        fontSize: 10,
        fontWeight: FontWeight.bold,
        align: TextAlign.center,
        baselineCenter: true);
  }

  // ---- Background ----
  static Paint? _bgPaint;
  static double _bgCachedWidth = 0;
  static double _bgCachedHeight = 0;

  void _drawBackground(Canvas canvas) {
    final w = GameController.gameWidth;
    final h = GameController.gameHeight;
    final dst = Rect.fromLTWH(0, 0, w, h);
    final bgImg = GameAssets.instance.backgroundImage;
    if (bgImg != null) {
      final src = Rect.fromLTWH(
          0, 0, bgImg.width.toDouble(), bgImg.height.toDouble());
      canvas.drawImageRect(bgImg, src, dst, Paint()..filterQuality = FilterQuality.medium);
      return;
    }
    if (_bgPaint == null || _bgCachedWidth != w || _bgCachedHeight != h) {
      _bgCachedWidth = w;
      _bgCachedHeight = h;
      _bgPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E293B), Color(0xFF334155)],
        ).createShader(dst);
    }
    canvas.drawRect(dst, _bgPaint!);
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

  // ---- Generator backs (z-level 2 — drawn after all conveyor belts) ----
  void _drawGeneratorBacks(Canvas canvas, double now) {
    final genBackImg = GameAssets.instance.generatorBackImage;
    if (genBackImg == null) return;
    for (final conv in game.conveyors) {
      if (conv.direction != ConveyorDirection.up) continue;
      final h = game.getCurrentHeight(conv, now);
      final genW = conv.width + GameConfig.generatorBackExtraW;
      final genH = genW * (genBackImg.height / genBackImg.width);
      _drawSprite(canvas, genBackImg,
          Rect.fromLTWH(conv.x + GameConfig.generatorBackOffsetX,
              conv.y + h + GameConfig.generatorBackOffsetY, genW, genH));
    }
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

    // 3D perspective: top (far) narrows, bottom (close) is full width.
    // Outer belts also lean their tops toward the layout centre (X-axis depth).
    final perspDepth = GameConfig.perspDepth;
    final topRailW = GameConfig.railWidthTop;
    final botRailW = GameConfig.railWidthBottom;
    final layoutCenterX = GameController.gameWidth / 2;
    final beltCenterX = conv.x + conv.width / 2;
    final xLean = (beltCenterX - layoutCenterX) *
        GameConfig.conveyorPerspectiveXFactor;
    final tlX = conv.x + perspDepth - xLean;
    final trX = conv.x + conv.width - perspDepth - xLean;
    final blX = conv.x;
    final brX = conv.x + conv.width;
    final topY = conv.y;
    final botY = conv.y + h;
    final bodyPath = Path()
      ..moveTo(tlX, topY)
      ..lineTo(trX, topY)
      ..lineTo(brX, botY)
      ..lineTo(blX, botY)
      ..close();

    // Allowed-target dashed glow (trapezoidal outline)
    if (isAllowedTarget && !conv.maintenance) {
      const pad = 6.0;
      canvas.drawPath(
        Path()
          ..moveTo(tlX - pad, topY - pad)
          ..lineTo(trX + pad, topY - pad)
          ..lineTo(brX + pad, botY + pad)
          ..lineTo(blX - pad, botY + pad)
          ..close(),
        Paint()
          ..color = const Color(0xFF22C55E).withValues(alpha: 0.4 + highlightPulse * 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Forbidden target tint
    if (isForbiddenTarget) {
      const pad = 2.0;
      canvas.drawPath(
        Path()
          ..moveTo(tlX - pad, topY - pad)
          ..lineTo(trX + pad, topY - pad)
          ..lineTo(brX + pad, botY + pad)
          ..lineTo(blX - pad, botY + pad)
          ..close(),
        Paint()..color = const Color(0xFFEF4444).withValues(alpha: 0.08),
      );
    }

    // generator_front draws here at z-level 1 (with the belt).
    // generator_back is drawn after all belts in _drawGeneratorBacks (z-level 2).
    if (isDown) {
      final genFrontImg = GameAssets.instance.generatorFrontImage;
      if (genFrontImg != null) {
        final genW = trX - tlX + GameConfig.generatorFrontExtraW;
        final genH = genW * (genFrontImg.height / genFrontImg.width);
        _drawSprite(canvas, genFrontImg,
            Rect.fromLTWH(tlX + GameConfig.generatorFrontOffsetX,
                conv.y - genH, genW, genH));
      } else if (!conv.maintenance) {
        _drawText(canvas, '↓', conv.x + conv.width / 2, spawnLabelY,
            color: const Color(0xFF64748B), fontSize: 14,
            fontWeight: FontWeight.bold, align: TextAlign.center);
      }
    } else if (GameAssets.instance.generatorBackImage == null &&
        !conv.maintenance) {
      // Fallback arrow only when no generator_back image asset exists
      _drawText(canvas, '↑', conv.x + conv.width / 2, spawnLabelY,
          color: const Color(0xFF64748B), fontSize: 14,
          fontWeight: FontWeight.bold, align: TextAlign.center);
    }

    // Belt body
    final convImg = GameAssets.instance.conveyorImage(conv.color);
    if (convImg == null) {
      canvas.drawPath(bodyPath, Paint()..color = const Color(0xFF475569));
    }

    // Scrolling belt surface — clip to belt body. Sprite tiles vertically
    // with the same scroll offset as boxes; procedural fallback paints the
    // 24px-period stripes.
    canvas.save();
    canvas.clipPath(bodyPath);
    // Perspective shear: at topY the texture shifts left by xLean; at botY
    // no shift. This makes the surface pattern follow the belt lean instead
    // of being a flat rectangle that leaves uncovered corners on outer belts.
    canvas.save();
    if (xLean != 0.0) {
      final shear = xLean / h;
      final tx = -xLean * (conv.y + h) / h;
      canvas.transform(Float64List.fromList([
        1, 0, 0, 0,
        shear, 1, 0, 0,
        0, 0, 1, 0,
        tx, 0, 0, 1,
      ]));
    }
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
    canvas.restore();

    // Returns the visual center-X of the belt at fractional height [t] (0=top).
    // The trapezoid top shifts by xLean, so the center drifts linearly with depth.
    double beltCenterAt(double t) =>
        conv.x + conv.width / 2 - xLean * (1 - t);

    // Resize flash overlay
    if (conv.resizing) {
      final fillPaint = Paint()
        ..color =
            const Color(0xFF06B6D4).withValues(alpha: 0.15 + rFlash * 0.25);
      canvas.drawPath(bodyPath, fillPaint);
      final arrowOpacity = 0.7 + rFlash * 0.3;
      _drawText(
        canvas,
        isGrowing ? '↑' : '↓',
        beltCenterAt(18 / h),
        conv.y + 18,
        color: const Color(0xFF06B6D4).withValues(alpha: arrowOpacity),
        fontSize: 16,
        fontWeight: FontWeight.bold,
        align: TextAlign.center,
      );
      _drawText(
        canvas,
        isGrowing ? '↓' : '↑',
        beltCenterAt((h - 6) / h),
        conv.y + h - 6,
        color: const Color(0xFF06B6D4).withValues(alpha: arrowOpacity),
        fontSize: 16,
        fontWeight: FontWeight.bold,
        align: TextAlign.center,
      );
    }

    // Maintenance (reversing) overlay
    if (conv.maintenance) {
      // Stripes must cover the full trapezoid bounding box, not just conv.x..conv.x+width.
      // With large xLean the top corners extend outside that rectangle, so using it
      // as the clip rect inside _drawDiagonalStripes would cut off those corners.
      final stripeRect = Rect.fromLTRB(
          min(tlX, blX), conv.y, max(trX, brX), conv.y + h);
      _drawDiagonalStripes(canvas, stripeRect, opacity: 0.35 + flash * 0.35);

      // Pending-direction badges: position at the perspective-correct center
      // for each badge's Y so they follow the belt lean at both ends.
      for (final yPos in [conv.y + 20, conv.y + h - 20]) {
        final badgeX = beltCenterAt((yPos - conv.y) / h);
        canvas.drawCircle(
            Offset(badgeX, yPos),
            10,
            Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.9));
        _drawText(canvas, pendingArrow, badgeX, yPos,
            color: const Color(0xFFFBBF24),
            fontSize: 14,
            fontWeight: FontWeight.bold,
            align: TextAlign.center,
            baselineCenter: true);
      }
    }

    canvas.restore();

    // Ghost drop target — drawn on top of the belt surface, clipped to belt body.
    // Applies the same perspective scale + xLean as real boxes so the ghost
    // shrinks toward the far end of the belt instead of staying full-size.
    final slots = game.landingSlots;
    if (slots != null && slots.containsKey(conv.id)) {
      final ghostY = slots[conv.id]!;
      const ghostSize = GameController.boxSize;
      final ghostBeltT =
          ((ghostY + ghostSize / 2 - conv.y) / h).clamp(0.0, 1.0);
      final ghostPerspScale =
          (conv.width - 2 * perspDepth * (1 - ghostBeltT)) / conv.width;
      final ghostLeanX = -xLean * (1 - ghostBeltT);
      final ghostVisualSize = ghostSize * ghostPerspScale;
      // Centre X follows the belt lean; Y anchors to the same visual centre as
      // a real box sitting in this slot (scale inward from the centre).
      final ghostDrawX =
          conv.x + conv.width / 2 + ghostLeanX - ghostVisualSize / 2;
      final ghostDrawY = ghostY + ghostSize / 2 * (1 - ghostPerspScale);
      final draggedBox =
          game.boxes.where((b) => b.id == game.draggedBoxId).firstOrNull;
      final fillColor = draggedBox?.color.bg ?? Colors.white;
      final borderColor = draggedBox?.color.light ?? Colors.white;
      final pulse = 0.65 + 0.35 * sin(now * 0.006);

      canvas.save();
      canvas.clipPath(bodyPath);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(ghostDrawX, ghostDrawY, ghostVisualSize, ghostVisualSize),
            const Radius.circular(6)),
        Paint()..color = fillColor.withValues(alpha: 0.45 * pulse),
      );
      canvas.restore();

      _drawDashedRRect(
        canvas,
        RRect.fromRectAndRadius(
            Rect.fromLTWH(ghostDrawX, ghostDrawY, ghostVisualSize, ghostVisualSize),
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
    // Tapered rails: thin at top (far), thick at bottom (close)
    canvas.drawPath(
      Path()
        ..moveTo(tlX, topY)
        ..lineTo(tlX + topRailW, topY)
        ..lineTo(blX + botRailW, botY)
        ..lineTo(blX, botY)
        ..close(),
      Paint()..color = leftRailColor,
    );
    canvas.drawPath(
      Path()
        ..moveTo(trX - topRailW, topY)
        ..lineTo(trX, topY)
        ..lineTo(brX, botY)
        ..lineTo(brX - botRailW, botY)
        ..close(),
      Paint()..color = rightRailColor,
    );

    // Debug: slot boundaries scrolling with the belt surface
    if (game.debugSlots) {
      canvas.save();
      canvas.clipPath(bodyPath);
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

    // Gate perspective: close end (isDown → bottom) is full size;
    // far end (!isDown → top) scales down to match the belt's trapezoidal narrowing.
    final gatePerspScale =
        isDown ? 1.0 : (conv.width - 2 * perspDepth) / conv.width;
    final gateW = (conv.width + 6) * gatePerspScale;
    final gateH = GameConfig.gateSpriteHeight * gatePerspScale;
    // For upward conveyors the gate sits at the top (far) end of the belt, which
    // is horizontally shifted by xLean — centre on (tlX+trX)/2 not conv.x+w/2.
    final gateX = isDown
        ? conv.x + conv.width / 2 - gateW / 2
        : conv.x + conv.width / 2 - xLean - gateW / 2;
    final scaledGateY =
        isDown ? gateY : conv.y - GameController.gateOffset - gateH;
    final gateRect = Rect.fromLTWH(gateX, scaledGateY, gateW, gateH);
    final gateImg = GameAssets.instance.gateImage(conv.color);
    final gateOpacity = conv.maintenance ? 0.5 : 1.0;
    if (gateImg != null) {
      _drawSprite(canvas, gateImg, gateRect, opacity: gateOpacity);
    } else {
      _drawProceduralGate(canvas, conv, gateRect);
    }
  }

  // ---- Procedural gate fallback (used when no PNG is present) ----
  void _drawProceduralGate(Canvas canvas, Conveyor conv, Rect r) {
    final gateOpacity = conv.maintenance ? 0.5 : 1.0;
    final s = r.height / 40.0; // scale factor relative to original 40px design
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(4 * s)),
      Paint()..color = conv.color.dark.withValues(alpha: gateOpacity),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(r.left + 3 * s, r.top + 3 * s,
              r.width - 6 * s, r.height - 6 * s),
          Radius.circular(3 * s)),
      Paint()..color = conv.color.bg.withValues(alpha: gateOpacity),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(r.left + 4 * s, r.top + 6 * s, r.width - 8 * s, 5 * s),
          Radius.circular(2 * s)),
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

  // ---- Solid rounded-rect stroke (for allowed-target highlight) ----
  // Previously dashed via computeMetrics(), which was expensive every frame.
  // A solid pulsing outline is visually equivalent and O(1) to paint.
  void _drawDashedRRect(
      Canvas canvas, RRect rrect, Color color, double strokeWidth, double opacity) {
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
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

    if (box.entering && !isDragged && !isThrown) return;

    double scaleX = 1, scaleY = 1, rotation = 0, liftY = 0;
    double opacity = onMaint ? 0.7 : 1.0;

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

    // Perspective scale + lean: boxes near the top (far) appear smaller and
    // are shifted horizontally to match the belt shear applied to the texture.
    double perspScale = 1.0;
    double leanX = 0.0;
    if (!isDragged && !isThrown && conv != null) {
      final convH = game.getCurrentHeight(conv, game.currentTime);
      final boxCenterY = box.y + box.size / 2;
      final beltT = ((boxCenterY - conv.y) / convH).clamp(0.0, 1.0);
      perspScale = (conv.width - 2 * GameConfig.perspDepth * (1 - beltT)) / conv.width;
      final xLean = (conv.x + conv.width / 2 - GameController.gameWidth / 2) *
          GameConfig.conveyorPerspectiveXFactor;
      leanX = -xLean * (1 - beltT); // 0 at bottom rail, -xLean at top rail
    }

    final cx = box.x + leanX + box.size / 2;
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

    // Body — special sprite > color sprite > procedural, transformed around
    // the lifted center.
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
        // Procedural fallback for unknown special types: dark box + emoji
        _drawProceduralSpecialBox(canvas, box, opacity, xOffset: leanX);
      } else {
        _drawProceduralBox(canvas, box, opacity, xOffset: leanX);
      }
    }
    canvas.restore();

    if (game.debugSlots) {
      final anim = box.throwAnim;
      final String label;
      if (anim != null && !box.onConveyor) {
        label = '→${anim.targetSlot}';
      } else if (box.slotIndex == null) {
        label = 'E';
      } else if (conv != null) {
        label = box.slotIndex == 9999 ? 'X' : '${box.slotIndex}';
      } else {
        label = '${box.slotIndex}';
      }
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFFFFFF00),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(box.x + leanX + (box.size - tp.width) / 2, box.y + (box.size - tp.height) / 2),
      );
    }
  }

  void _drawProceduralBox(Canvas canvas, Box box, double opacity,
      {double xOffset = 0.0}) {
    final x = box.x + xOffset;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x, box.y, box.size, box.size),
          const Radius.circular(6)),
      Paint()..color = box.color.dark.withValues(alpha: opacity),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 2, box.y + 2, box.size - 4, box.size - 4),
          const Radius.circular(5)),
      Paint()..color = box.color.bg.withValues(alpha: opacity),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 4, box.y + 4, box.size - 8, 6),
          const Radius.circular(3)),
      Paint()..color = box.color.light.withValues(alpha: opacity * 0.7),
    );
    canvas.drawCircle(
      Offset(x + box.size / 2, box.y + box.size / 2 + 2),
      6,
      Paint()..color = box.color.light.withValues(alpha: opacity * 0.9),
    );
  }

  void _drawProceduralSpecialBox(Canvas canvas, Box box, double opacity,
      {double xOffset = 0.0}) {
    final x = box.x + xOffset;
    // Dark body with orange glow border
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x, box.y, box.size, box.size),
          const Radius.circular(6)),
      Paint()..color = const Color(0xFF1A1A1A).withValues(alpha: opacity),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x, box.y, box.size, box.size),
          const Radius.circular(6)),
      Paint()
        ..color = const Color(0xFFFF6600).withValues(alpha: opacity * 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final icon = switch (box.specialType) {
      SpecialType.bomb => '💣',
      _ => '?',
    };
    _drawText(canvas, icon, x + box.size / 2, box.y + box.size / 2,
        color: Colors.white.withValues(alpha: opacity),
        fontSize: 22,
        align: TextAlign.center,
        baselineCenter: true);
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
  // Reuse a single Paint across all particles — avoids allocating one object
  // per particle per frame (which at 20+ particles × 60 fps causes GC pressure).
  final Paint _particlePaint = Paint();

  void _drawParticles(Canvas canvas, double now) {
    if (game.particles.isEmpty) return;
    for (final p in game.particles) {
      final t = ((now - p.startTime) / p.lifetime).clamp(0.0, 1.0);
      _particlePaint.color = p.color.withValues(alpha: 1 - t);
      canvas.drawCircle(Offset(p.x, p.y), p.size * (1 - t * 0.3), _particlePaint);
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
