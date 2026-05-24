import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../game/game_config.dart';
import '../game/game_controller.dart';
import '../models/box.dart';
import '../models/conveyor.dart';
import '../models/belt_explosion.dart';
import '../models/special_type.dart';
import '../models/falling_box.dart';
import '../models/game_assets.dart';

// Cached per-conveyor geometry — body path and shear matrix.
// Stored outside GamePainter because the painter is rebuilt every frame.
class _ConvGeom {
  final double h;
  final double xLean;
  final Path bodyPath;
  final Float64List? shearMatrix; // null when xLean == 0
  _ConvGeom({required this.h, required this.xLean, required this.bodyPath, this.shearMatrix});
}

/// Paints the entire game scene onto a fixed 360x600 canvas —
/// the surrounding [FittedBox] scales it to fit the device viewport.
class GamePainter extends CustomPainter {
  final GameController game;

  GamePainter(this.game) : super(repaint: game);

  // ---- Static resources: survive GamePainter rebuilds each frame ----
  // GamePainter is recreated every frame (AnimatedBuilder + CustomPaint),
  // so anything that must persist across frames must be static.

  // General-purpose reusable paints — set properties before each use.
  // Safe because Canvas.draw* calls are synchronous within paint().
  static final _p = Paint();
  static final _sp = Paint()..style = PaintingStyle.stroke;

  // Fixed-color paints that never change between frames.
  static final _hudBgPaint = Paint()..color = const Color(0xFF0F172A);
  static final _progressBgPaint = Paint()..color = const Color(0xFF1E293B);
  static final _progressYellowPaint = Paint()..color = const Color(0xFFFBBF24);
  static final _liveRedPaint = Paint()..color = const Color(0xFFEF4444);
  static final _liveDeadPaint = Paint()..color = const Color(0xFF475569);
  static final _liveStrokePaint = Paint()
    ..color = const Color(0xFFFCA5A5)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  static final _beltFallbackPaint = Paint()..color = const Color(0xFF475569);
  static final _spritePaint = Paint()..filterQuality = FilterQuality.medium;

  // TextPainter cache — layout() is expensive; skip it when nothing changed.
  // Key encodes all style parameters; capped to avoid unbounded growth.
  static final _textCache = <String, TextPainter>{};
  static const _textCacheMax = 128;

  static TextPainter _cachedText({
    required String text,
    required Color color,
    required double fontSize,
    required FontWeight fontWeight,
    required TextAlign align,
    double letterSpacing = 0,
  }) {
    final key =
        '$text\x00${color.a}_${color.r}_${color.g}_${color.b}\x00$fontSize\x00${fontWeight.index}\x00${align.index}\x00$letterSpacing';
    var tp = _textCache[key];
    if (tp == null) {
      if (_textCache.length >= _textCacheMax) _textCache.remove(_textCache.keys.first);
      tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: fontWeight,
              letterSpacing: letterSpacing),
        ),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout();
      _textCache[key] = tp;
    }
    return tp;
  }

  // Per-conveyor geometry cache — body path + shear matrix.
  // Rebuilt only when height or xLean changes (i.e. during resize).
  static final _convGeomCache = <int, _ConvGeom>{};

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
  // ---- Combination area ----
  // Layout driven by container.svg (viewBox 800×290).
  // slot_1 (SVG 78,75,160,165)  → recipe box 0
  // slot_2 (SVG 282,75,160,165) → recipe box 1
  // slot_3 (SVG 486,75,235,165) → reward
  void _drawComboArea(Canvas canvas, double now) {
    final area = game.comboArea!;
    final panelX = (GameController.gameWidth - GameConfig.comboAreaWidth) / 2;
    final panelY = GameConfig.comboAreaTop;
    final panelW = GameConfig.comboAreaWidth - 8.0;
    // Height derived from SVG aspect ratio so the container image is undistorted.
    final panelH = panelW * GameConfig.containerSvgH / GameConfig.containerSvgW;
    final panelRect = Rect.fromLTWH(panelX, panelY, panelW, panelH);
    final panelRRect = RRect.fromRectAndRadius(panelRect, const Radius.circular(8));

    final isComplete = area.completionTime != null;
    final completePulse = isComplete
        ? (0.5 + 0.5 * sin((now - area.completionTime!) * 0.015)).clamp(0.0, 1.0)
        : 0.0;

    // SVG → panel coordinate mapping
    final sx = panelW / GameConfig.containerSvgW;
    final sy = panelH / GameConfig.containerSvgH;
    Rect svgSlot(double x, double y, double w, double h) =>
        Rect.fromLTWH(panelX + x * sx, panelY + y * sy, w * sx, h * sy);

    final slot1 = svgSlot(GameConfig.containerSlot1X, GameConfig.containerSlot1Y,
        GameConfig.containerSlot1W, GameConfig.containerSlot1H);
    final slot2 = svgSlot(GameConfig.containerSlot2X, GameConfig.containerSlot2Y,
        GameConfig.containerSlot2W, GameConfig.containerSlot2H);
    final slot3 = svgSlot(GameConfig.containerSlot3X, GameConfig.containerSlot3Y,
        GameConfig.containerSlot3W, GameConfig.containerSlot3H);

    // Container background (image or procedural fallback)
    final containerImg = GameAssets.instance.containerImage;
    if (containerImg != null) {
      _drawSprite(canvas, containerImg, panelRect);
    } else {
      canvas.drawRRect(panelRRect, _hudBgPaint);
      canvas.drawRRect(panelRRect,
          (_sp..color = const Color(0xFF1E3A5F)..strokeWidth = 1));
    }

    // Gold pulse border on combo completion (always on top of image)
    if (isComplete) {
      canvas.drawRRect(panelRRect,
          (_sp
            ..color = const Color(0xFFFBBF24)
                .withValues(alpha: 0.6 + completePulse * 0.4)
            ..strokeWidth = 2.0));
    }

    // === Recipe boxes in slot_1 and slot_2 ===
    final slots = [slot1, slot2];
    for (int i = 0; i < area.recipe.length; i++) {
      final slot   = slots[i];
      final color  = area.recipe[i];
      final isDone = i < area.progress || isComplete;
      final isCurrent = !isComplete && i == area.progress;
      final alpha  = isDone || isCurrent ? 1.0 : 0.35;
      final pulse  = isCurrent ? (0.5 + 0.5 * sin(now * 0.008)) : 0.0;
      const pad    = 3.0;
      final boxRect = Rect.fromLTWH(
          slot.left + pad, slot.top + pad,
          slot.width - pad * 2, slot.height - pad * 2);

      final boxImg = GameAssets.instance.boxImage(color);
      if (boxImg != null) {
        _drawSprite(canvas, boxImg, boxRect, opacity: alpha);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(boxRect, const Radius.circular(6)),
            (_p..color = color.dark.withValues(alpha: alpha)));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(boxRect.left + 2, boxRect.top + 2,
                  boxRect.width - 4, boxRect.height - 4),
              const Radius.circular(5)),
          (_p..color = color.bg.withValues(alpha: alpha)),
        );
      }

      // Pulsing outline on the current target slot
      if (isCurrent) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(boxRect.inflate(3), const Radius.circular(9)),
          (_sp..color = color.light.withValues(alpha: 0.4 + pulse * 0.6)..strokeWidth = 2),
        );
      }

      // Check mark on completed slots
      if (isDone) {
        _drawText(canvas, '✓',
            slot.center.dx, slot.center.dy,
            color: Colors.white,
            fontSize: slot.height * 0.45,
            fontWeight: FontWeight.bold,
            align: TextAlign.center,
            baselineCenter: true);
      }
    }

    // === Reward in slot_3 ===
    final rewardAlpha = isComplete ? (0.7 + completePulse * 0.3) : 1.0;
    final rewardFallbackEmoji = switch (area.reward) {
      SpecialType.bomb => '💣',
      SpecialType.icy  => '❄',
    };

    const pad    = 3.0;
    final spriteRect = Rect.fromLTWH(
        slot3.left + pad, slot3.top + pad,
        slot3.width - pad * 2, slot3.height - pad * 2);

    final specialImg = GameAssets.instance.specialImage(area.reward);
    if (specialImg != null) {
      _drawSprite(canvas, specialImg, spriteRect, opacity: rewardAlpha);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(spriteRect, const Radius.circular(6)),
        (_p..color = const Color(0xFF1A1A1A).withValues(alpha: rewardAlpha)),
      );
      _drawText(canvas, rewardFallbackEmoji,
          slot3.center.dx, slot3.top + slot3.height * 0.45,
          color: Colors.white.withValues(alpha: rewardAlpha),
          fontSize: slot3.height * 0.38,
          align: TextAlign.center,
          baselineCenter: true);
    }

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
      _spritePaint.colorFilter = null;
      canvas.drawImageRect(bgImg, src, dst, _spritePaint);
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
  // Layout driven by HUD.svg (viewBox 800×195). Scale factors:
  //   sx = gameWidth / 800,  sy = hudH / 195   (both = 0.5 at baseWidth=400)
  void _drawHUD(Canvas canvas) {
    final gw = GameController.gameWidth;
    final hudH = GameConfig.hudImageHeight; // 97.5 at gameWidth=400
    final sx = gw / GameConfig.hudSvgW;
    final sy = hudH / GameConfig.hudSvgH;

    // Background image (or fallback solid rect)
    final hudImg = GameAssets.instance.hudImage;
    if (hudImg != null) {
      _drawSprite(canvas, hudImg, Rect.fromLTWH(0, 0, gw, hudH));
    } else {
      canvas.drawRect(Rect.fromLTWH(0, 0, gw, hudH), _hudBgPaint);
    }

    // Helper: center X/Y of an SVG-defined named slot.
    double slotCX(double svgX, double svgW) => (svgX + svgW / 2) * sx;
    double slotCY(double svgY, double svgH) => (svgY + svgH / 2) * sy;

    // ── score slot ──────────────────────────────────────────────────────────
    final sCX = slotCX(GameConfig.hudScoreX, GameConfig.hudScoreW);
    final sCY = slotCY(GameConfig.hudScoreY, GameConfig.hudScoreH);
    _drawText(canvas, '${game.score}', sCX, sCY,
        color: Colors.white,
        fontSize: GameConfig.hudScoreH * sy * 0.72,
        fontWeight: FontWeight.bold,
        align: TextAlign.center,
        baselineCenter: true);

    // ── level slot ──────────────────────────────────────────────────────────
    final lCX = slotCX(GameConfig.hudLevelX, GameConfig.hudLevelW);
    final lCY = slotCY(GameConfig.hudLevelY, GameConfig.hudLevelH);
    _drawText(canvas, '${game.level}', lCX, lCY,
        color: Colors.white,
        fontSize: GameConfig.hudLevelH * sy * 0.72,
        fontWeight: FontWeight.bold,
        align: TextAlign.center,
        baselineCenter: true);

    // ── lives slot — 4 dots centered in the slot rect ───────────────────────
    final liSlotX = GameConfig.hudLivesX * sx;
    final liSlotW = GameConfig.hudLivesW * sx;
    final liCY    = slotCY(GameConfig.hudLivesY, GameConfig.hudLivesH);
    const dotCount = 4;
    final dotR    = (GameConfig.hudLivesH * sy * 0.5 * 0.42).clamp(3.0, 7.0);
    final dotStep = dotR * 2.8;
    final dotsStartX = liSlotX + liSlotW / 2 - (dotCount - 1) * dotStep / 2;
    for (int i = 0; i < dotCount; i++) {
      final dx = dotsStartX + i * dotStep;
      final alive = i < game.lives;
      canvas.drawCircle(Offset(dx, liCY), dotR,
          alive ? _liveRedPaint : _liveDeadPaint);
      if (alive) canvas.drawCircle(Offset(dx, liCY), dotR, _liveStrokePaint);
    }

    // ── Progress bar immediately below HUD image ─────────────────────────────
    final currentLvlPts = game.pointsForLevel(game.level);
    final nextLvlPts    = game.pointsForLevel(game.level + 1);
    final ptsNeeded     = nextLvlPts - currentLvlPts;
    final pct = ptsNeeded == 0
        ? 0.0
        : min(100.0, ((game.score - currentLvlPts) / ptsNeeded) * 100);
    canvas.drawRect(Rect.fromLTWH(0, hudH, gw, 4), _progressBgPaint);
    canvas.drawRect(Rect.fromLTWH(0, hudH, gw * pct / 100, 4), _progressYellowPaint);
  }

  // ---- Sprite blit with optional opacity (preserves source aspect ratio
  // expectations: caller picks the dst rect). ----
  void _drawSprite(Canvas canvas, ui.Image image, Rect dst,
      {double opacity = 1.0}) {
    if (opacity < 1.0) {
      _spritePaint.colorFilter = ColorFilter.mode(
          Colors.white.withValues(alpha: opacity), BlendMode.modulate);
    } else {
      _spritePaint.colorFilter = null;
    }
    final src = Rect.fromLTWH(
        0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, dst, _spritePaint);
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
    final frozenPulse = conv.frozen ? (0.5 + 0.5 * sin(now * 0.005)) : 0.0;
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

    // Retrieve or build per-conveyor geometry (body path + shear matrix).
    // Rebuilds only when h or xLean changes (during resize); otherwise reuses.
    final cachedGeom = _convGeomCache[conv.id];
    final _ConvGeom geom;
    if (cachedGeom != null && cachedGeom.h == h && cachedGeom.xLean == xLean) {
      geom = cachedGeom;
    } else {
      final path = Path()
        ..moveTo(tlX, topY)
        ..lineTo(trX, topY)
        ..lineTo(brX, botY)
        ..lineTo(blX, botY)
        ..close();
      Float64List? matrix;
      if (xLean != 0.0) {
        final shear = xLean / h;
        final tx = -xLean * (conv.y + h) / h;
        matrix = Float64List.fromList([
          1, 0, 0, 0,
          shear, 1, 0, 0,
          0, 0, 1, 0,
          tx, 0, 0, 1,
        ]);
      }
      geom = _ConvGeom(h: h, xLean: xLean, bodyPath: path, shearMatrix: matrix);
      _convGeomCache[conv.id] = geom;
    }
    final bodyPath = geom.bodyPath;

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
        (_sp
          ..color = const Color(0xFF22C55E).withValues(alpha: 0.4 + highlightPulse * 0.5)
          ..strokeWidth = 2),
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
        (_p..color = const Color(0xFFEF4444).withValues(alpha: 0.08)),
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
      canvas.drawPath(bodyPath, _beltFallbackPaint);
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
    if (geom.shearMatrix != null) canvas.transform(geom.shearMatrix!);
    if (convImg != null) {
      final tileH = conv.width * (convImg.height / convImg.width);
      final scroll = (conv.maintenance || conv.frozen) ? 0.0 : (offset % tileH);
      final numTiles = (h / tileH).ceil() + 2;
      for (int i = 0; i < numTiles; i++) {
        final y = conv.y + (i * tileH + scroll) - tileH;
        _drawSprite(canvas, convImg,
            Rect.fromLTWH(conv.x, y, conv.width, tileH));
      }
    } else if (!conv.maintenance && !conv.frozen) {
      final scroll = offset % 24;
      final numStripes = (h / 24).ceil() + 2;
      _p.color = const Color(0xFF64748B).withValues(alpha: 0.5);
      for (int i = 0; i < numStripes; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(conv.x + 4, conv.y + (i * 24 + scroll) - 24,
                conv.width - 8, 12),
            const Radius.circular(2),
          ),
          _p,
        );
      }
    }
    canvas.restore();

    // Returns the visual center-X of the belt at fractional height [t] (0=top).
    // The trapezoid top shifts by xLean, so the center drifts linearly with depth.
    double beltCenterAt(double t) =>
        conv.x + conv.width / 2 - xLean * (1 - t);

    // Resize flash overlay
    if (conv.resizing) {
      canvas.drawPath(bodyPath,
          (_p..color = const Color(0xFF06B6D4).withValues(alpha: 0.15 + rFlash * 0.25)));
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
        canvas.drawCircle(Offset(badgeX, yPos), 10,
            (_p..color = const Color(0xFF0F172A).withValues(alpha: 0.9)));
        _drawText(canvas, pendingArrow, badgeX, yPos,
            color: const Color(0xFFFBBF24),
            fontSize: 14,
            fontWeight: FontWeight.bold,
            align: TextAlign.center,
            baselineCenter: true);
      }
    }

    // Frozen (icy) overlay — ice-blue tint with frost crystals and snowflake badges.
    if (conv.frozen) {
      canvas.drawPath(bodyPath,
          (_p..color = const Color(0xFF00BFFF).withValues(alpha: 0.18 + frozenPulse * 0.12)));

      // Frost crystal dots (sheared with the belt lean).
      canvas.save();
      if (geom.shearMatrix != null) canvas.transform(geom.shearMatrix!);
      final frostRng = Random(conv.id * 31 + (now / 220).toInt());
      for (int i = 0; i < 10; i++) {
        final fx = conv.x + 3 + frostRng.nextDouble() * (conv.width - 6);
        final fy = conv.y + 3 + frostRng.nextDouble() * (h - 6);
        final fr = 1.2 + frostRng.nextDouble() * 2.0;
        _p.color = const Color(0xFFBAE6FD).withValues(alpha: 0.30 + frozenPulse * 0.45);
        canvas.drawCircle(Offset(fx, fy), fr, _p);
      }
      canvas.restore();

      // Snowflake badges at top and bottom of the belt.
      for (final yPos in [conv.y + 22.0, conv.y + h - 22.0]) {
        if (yPos < conv.y + 10 || yPos > conv.y + h - 10) continue;
        final badgeX = beltCenterAt((yPos - conv.y) / h);
        canvas.drawCircle(Offset(badgeX, yPos), 10,
            (_p..color = const Color(0xFF0F172A).withValues(alpha: 0.85)));
        _drawText(canvas, '❄', badgeX, yPos,
            color: const Color(0xFF7DD3FC).withValues(alpha: 0.85 + frozenPulse * 0.15),
            fontSize: 13,
            fontWeight: FontWeight.bold,
            align: TextAlign.center,
            baselineCenter: true);
      }
    }

    // Belt explosion wave: fire rushes from gate to generator after a bomb.
    // Drawn inside the outer bodyPath clip so it's naturally masked to the belt.
    _drawBeltExplosion(canvas, conv, now, geom);

    canvas.restore();

    // Ghost drop target — drawn on top of the belt surface, clipped to belt body.
    // Uses the same shear transform as the belt texture so the ghost leans with
    // non-centre belts instead of remaining a vertical rectangle.
    final slots = game.landingSlots;
    if (slots != null && slots.containsKey(conv.id)) {
      final ghostY = slots[conv.id]!;
      const ghostSize = GameController.boxSize;
      final ghostBeltT =
          ((ghostY + ghostSize / 2 - conv.y) / h).clamp(0.0, 1.0);
      final ghostPerspScale =
          (conv.width - 2 * perspDepth * (1 - ghostBeltT)) / conv.width;
      final ghostVisualSize = ghostSize * ghostPerspScale;
      // Centre X: place the ghost at the belt's horizontal centre; the belt
      // shear transform (applied below) moves it to follow the lean so top and
      // bottom edges track the belt edges instead of staying vertical.
      final ghostDrawX = conv.x + conv.width / 2 - ghostVisualSize / 2;
      final ghostDrawY = ghostY + ghostSize / 2 * (1 - ghostPerspScale);
      final draggedBox =
          game.boxes.where((b) => b.id == game.draggedBoxId).firstOrNull;
      final fillColor = draggedBox?.color.bg ?? Colors.white;
      final borderColor = draggedBox?.color.light ?? Colors.white;
      final pulse = 0.65 + 0.35 * sin(now * 0.006);

      // Draw fill + outline inside one save/restore so both receive the same
      // shear and clip.  The shear is identical to the belt-texture shear:
      // at topY the ghost shifts left by xLean; at botY no shift.
      canvas.save();
      canvas.clipPath(bodyPath);
      if (geom.shearMatrix != null) canvas.transform(geom.shearMatrix!);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(ghostDrawX, ghostDrawY, ghostVisualSize, ghostVisualSize),
            const Radius.circular(6)),
        (_p..color = fillColor.withValues(alpha: 0.45 * pulse)),
      );
      _drawDashedRRect(
        canvas,
        RRect.fromRectAndRadius(
            Rect.fromLTWH(ghostDrawX, ghostDrawY, ghostVisualSize, ghostVisualSize),
            const Radius.circular(6)),
        borderColor,
        2.0,
        0.9 * pulse,
      );
      canvas.restore();
    }

    // Left + right rails with state-dependent color
    Color leftRailColor = const Color(0xFF94A3B8);
    Color rightRailColor = const Color(0xFF1E293B);
    if (conv.frozen) {
      leftRailColor = const Color(0xFF38BDF8).withValues(alpha: 0.6 + frozenPulse * 0.4);
      rightRailColor = leftRailColor;
    } else if (conv.maintenance) {
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
      (_p..color = leftRailColor),
    );
    canvas.drawPath(
      Path()
        ..moveTo(trX - topRailW, topY)
        ..lineTo(trX, topY)
        ..lineTo(brX, botY)
        ..lineTo(brX - botRailW, botY)
        ..close(),
      (_p..color = rightRailColor),
    );

    // Debug: slot boundaries scrolling with the belt surface
    if (game.debugSlots) {
      canvas.save();
      canvas.clipPath(bodyPath);
      if (geom.shearMatrix != null) canvas.transform(geom.shearMatrix!);
      final scroll = (conv.maintenance || conv.frozen) ? 0.0 : (offset % GameController.boxSize);
      final nVisible = (h / GameController.boxSize).ceil() + 2;
      for (int s = 0; s < nVisible; s++) {
        final slotTop =
            conv.y + s * GameController.boxSize + scroll - GameController.boxSize;
        final slotRect = Rect.fromLTWH(
            conv.x + 3, slotTop, conv.width - 6, GameController.boxSize);
        canvas.drawRect(slotRect,
            (_p..color = const Color(0xFF00FF00).withValues(alpha: 0.08)));
        canvas.drawRect(slotRect,
            (_sp..color = const Color(0xFF00FF00).withValues(alpha: 0.6)..strokeWidth = 1));
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
    final s = r.height / 40.0;
    canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(4 * s)),
        (_p..color = conv.color.dark.withValues(alpha: gateOpacity)));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(r.left + 3 * s, r.top + 3 * s, r.width - 6 * s, r.height - 6 * s),
          Radius.circular(3 * s)),
      (_p..color = conv.color.bg.withValues(alpha: gateOpacity)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(r.left + 4 * s, r.top + 6 * s, r.width - 8 * s, 5 * s),
          Radius.circular(2 * s)),
      (_p..color = conv.color.light.withValues(alpha: conv.maintenance ? 0.3 : 0.7)),
    );
  }

  // ---- Diagonal maintenance stripes pattern ----
  void _drawDiagonalStripes(Canvas canvas, Rect rect, {double opacity = 1.0}) {
    canvas.save();
    canvas.clipRect(rect);
    canvas.translate(rect.left + rect.width / 2, rect.top + rect.height / 2);
    canvas.rotate(pi / 4);
    final len = rect.width + rect.height;
    final yellowColor = const Color(0xFFFBBF24).withValues(alpha: opacity);
    final darkColor = const Color(0xFF1E293B).withValues(alpha: opacity);
    for (double x = -len; x < len; x += 10) {
      canvas.drawRect(Rect.fromLTWH(x, -len, 5, len * 2), (_p..color = yellowColor));
      canvas.drawRect(Rect.fromLTWH(x + 5, -len, 5, len * 2), (_p..color = darkColor));
    }
    canvas.restore();
  }

  // ---- Belt explosion wave (bomb effect) ----
  void _drawBeltExplosion(
      Canvas canvas, Conveyor conv, double now, _ConvGeom geom) {
    BeltExplosion? explosion;
    for (final e in game.beltExplosions) {
      if (e.conveyorId == conv.id) {
        explosion = e;
        break;
      }
    }
    if (explosion == null) return;

    final elapsed = now - explosion.startTime;
    final rawT = (elapsed / explosion.duration).clamp(0.0, 1.0);
    // Ease-out cubic: fast initial rush that slows as it reaches the generator.
    final t = 1.0 - pow(1.0 - rawT, 3.0);

    final waveFrontY =
        explosion.fromY + (explosion.toY - explosion.fromY) * t;
    final movingDown = explosion.toY > explosion.fromY;

    // Burned region spans from origin (gate edge) to current wave front.
    final burnedTop    = movingDown ? explosion.fromY : waveFrontY;
    final burnedBottom = movingDown ? waveFrontY       : explosion.fromY;

    // Apply the same shear as the belt texture so the wave follows the lean.
    canvas.save();
    if (geom.shearMatrix != null) canvas.transform(geom.shearMatrix!);

    final left  = conv.x;
    final right = conv.x + conv.width;

    // ── Fire body gradient: transparent at tail → bright orange at front ──
    if (burnedBottom - burnedTop > 0.5) {
      _p.shader = ui.Gradient.linear(
        Offset(left, explosion.fromY), // tail (transparent)
        Offset(left, waveFrontY),      // front (bright)
        const [
          Color(0x00FF4500),
          Color(0x88FF3300),
          Color(0xCCFF6600),
        ],
        [0.0, 0.45, 1.0],
      );
      canvas.drawRect(
          Rect.fromLTRB(left, burnedTop, right, burnedBottom), _p);
      _p.shader = null;
    }

    // ── Wave-front glow: bright band extending ahead of the front ──
    const glowH = 26.0;
    final ahead = movingDown ? 1.0 : -1.0; // direction of travel
    _p.shader = ui.Gradient.linear(
      Offset(left, waveFrontY),                   // at front: white-hot
      Offset(left, waveFrontY + ahead * glowH),   // ahead: transparent
      const [
        Color(0xCCFFFFFF),
        Color(0x66FF9900),
        Color(0x00FF6600),
      ],
      [0.0, 0.45, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTRB(
        left,
        movingDown ? waveFrontY - 3 : waveFrontY - glowH + 3,
        right,
        movingDown ? waveFrontY + glowH : waveFrontY + 3,
      ),
      _p,
    );
    _p.shader = null;

    // ── Sparks: pseudo-random dots that flicker near the wave front ──
    // Seed changes every ~80 ms for a natural flicker rate.
    final sparkSeed = (now / 80).toInt() * 17 + conv.id * 97;
    final rng = Random(sparkSeed);
    for (int i = 0; i < 7; i++) {
      final sx = left + 3 + rng.nextDouble() * (conv.width - 6);
      final sy = waveFrontY + ahead * rng.nextDouble() * 16;
      final sr = 1.0 + rng.nextDouble() * 2.5;
      final sa = 0.55 + rng.nextDouble() * 0.45;
      _p.color = const Color(0xFFFFCC00).withValues(alpha: sa);
      canvas.drawCircle(Offset(sx, sy), sr, _p);
    }

    canvas.restore();
  }

  // ---- Solid rounded-rect stroke (for allowed-target highlight) ----
  // Previously dashed via computeMetrics(), which was expensive every frame.
  // A solid pulsing outline is visually equivalent and O(1) to paint.
  void _drawDashedRRect(
      Canvas canvas, RRect rrect, Color color, double strokeWidth, double opacity) {
    canvas.drawRRect(rrect,
        (_sp..color = color.withValues(alpha: opacity)..strokeWidth = strokeWidth));
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
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(box.x + box.size / 2, box.y + box.size + 4),
          width: box.size * 0.7,
          height: 6,
        ),
        (_p..color = Colors.black.withValues(alpha: 0.3)),
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
        canvas.drawLine(
          Offset(cx - normX * (streakLen + i * 6),
              cy - normY * (streakLen + i * 6)),
          Offset(cx - normX * (i * 4), cy - normY * (i * 4)),
          (_sp
            ..color = box.color.light.withValues(alpha: 0.5 - i * 0.12)
            ..strokeWidth = 3 - i * 0.7
            ..strokeCap = StrokeCap.round),
        );
      }
    }

    // Outer aura during drag / throw
    if (isDragged || isThrown) {
      canvas.drawCircle(Offset(cx, cy), box.size * 0.9,
          (_p..color = box.color.bg.withValues(alpha: 0.15)));
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
          Rect.fromLTWH(x, box.y, box.size, box.size), const Radius.circular(6)),
      (_p..color = box.color.dark.withValues(alpha: opacity)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 2, box.y + 2, box.size - 4, box.size - 4),
          const Radius.circular(5)),
      (_p..color = box.color.bg.withValues(alpha: opacity)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 4, box.y + 4, box.size - 8, 6), const Radius.circular(3)),
      (_p..color = box.color.light.withValues(alpha: opacity * 0.7)),
    );
    canvas.drawCircle(
      Offset(x + box.size / 2, box.y + box.size / 2 + 2),
      6,
      (_p..color = box.color.light.withValues(alpha: opacity * 0.9)),
    );
  }

  void _drawProceduralSpecialBox(Canvas canvas, Box box, double opacity,
      {double xOffset = 0.0}) {
    final x = box.x + xOffset;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x, box.y, box.size, box.size), const Radius.circular(6)),
      (_p..color = const Color(0xFF1A1A1A).withValues(alpha: opacity)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x, box.y, box.size, box.size), const Radius.circular(6)),
      (_sp..color = const Color(0xFFFF6600).withValues(alpha: opacity * 0.9)..strokeWidth = 2),
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
          Rect.fromLTWH(fb.x, fb.y, fb.size, fb.size), const Radius.circular(6)),
      (_p..color = fb.color.dark.withValues(alpha: opacity)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(fb.x + 2, fb.y + 2, fb.size - 4, fb.size - 4),
          const Radius.circular(5)),
      (_p..color = fb.color.bg.withValues(alpha: opacity)),
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
    // Stroke variant is rare — skip cache and allocate directly.
    if (strokeColor != null && strokeWidth > 0) {
      final textStyle = TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing);
      final tp = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout();
      double ox = x, oy = y;
      if (align == TextAlign.center) { ox -= tp.width / 2; }
      else if (align == TextAlign.right) { ox -= tp.width; }
      if (baselineCenter) { oy -= tp.height / 2; }
      else { oy -= tp.height * 0.75; }
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
      )..layout();
      strokePainter.paint(canvas, Offset(ox, oy));
      tp.paint(canvas, Offset(ox, oy));
      return;
    }

    final tp = _cachedText(
      text: text,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      align: align,
      letterSpacing: letterSpacing,
    );
    double offsetX = x;
    double offsetY = y;
    if (align == TextAlign.center) { offsetX -= tp.width / 2; }
    else if (align == TextAlign.right) { offsetX -= tp.width; }
    if (baselineCenter) { offsetY -= tp.height / 2; }
    else { offsetY -= tp.height * 0.75; }
    tp.paint(canvas, Offset(offsetX, offsetY));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
