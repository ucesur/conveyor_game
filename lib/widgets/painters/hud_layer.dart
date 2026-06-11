part of '../game_painter.dart';

extension HudLayer on GamePainter {
  void _drawBackground(Canvas canvas) {
    final w = GameController.gameWidth;
    final h = GameController.gameHeight;
    final dst = Rect.fromLTWH(0, 0, w, h);
    final bgImg = GameAssets.instance.backgroundImage;
    if (bgImg != null) {
      _spritePaint.colorFilter = null;
      canvas.drawImageRect(bgImg,
          Rect.fromLTWH(0, 0, bgImg.width.toDouble(), bgImg.height.toDouble()),
          dst, _spritePaint);
      return;
    }
    if (_bgPaint == null || _bgCachedWidth != w || _bgCachedHeight != h) {
      _bgCachedWidth  = w;
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

  void _drawHUD(Canvas canvas) {
    final gw  = GameController.gameWidth;
    final hudH = GameConfig.hudImageHeight;
    final sx  = gw / GameConfig.hudSvgW;
    final sy  = hudH / GameConfig.hudSvgH;

    final hudImg = GameAssets.instance.hudImage;
    if (hudImg != null) {
      _drawSprite(canvas, hudImg, Rect.fromLTWH(0, 0, gw, hudH));
    } else {
      canvas.drawRect(Rect.fromLTWH(0, 0, gw, hudH), _hudBgPaint);
    }

    double slotCX(double svgX, double svgW) => (svgX + svgW / 2) * sx;
    double slotCY(double svgY, double svgH) => (svgY + svgH / 2) * sy;

    _drawText(canvas, '${game.score}',
        slotCX(GameConfig.hudScoreX, GameConfig.hudScoreW),
        slotCY(GameConfig.hudScoreY, GameConfig.hudScoreH),
        color: Colors.white,
        fontSize: GameConfig.hudScoreH * sy * 0.72,
        fontWeight: FontWeight.bold,
        align: TextAlign.center,
        baselineCenter: true);

    _drawText(canvas, '${game.level}',
        slotCX(GameConfig.hudLevelX, GameConfig.hudLevelW),
        slotCY(GameConfig.hudLevelY, GameConfig.hudLevelH),
        color: Colors.white,
        fontSize: GameConfig.hudLevelH * sy * 0.72,
        fontWeight: FontWeight.bold,
        align: TextAlign.center,
        baselineCenter: true);

    // Lives dots
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
      canvas.drawCircle(Offset(dx, liCY), dotR, alive ? _liveRedPaint : _liveDeadPaint);
      if (alive) canvas.drawCircle(Offset(dx, liCY), dotR, _liveStrokePaint);
    }

    // HUD labels: SCORE / LEVEL / LIVES
    final lH = GameConfig.hudScoreLblH * sy;
    _drawHudLabel(canvas,
        AppStrings.scoreLbl,
        slotCX(GameConfig.hudScoreLblX, GameConfig.hudScoreLblW),
        slotCY(GameConfig.hudScoreLblY, GameConfig.hudScoreLblH),
        lH);
    _drawHudLabel(canvas,
        AppStrings.levelLbl,
        slotCX(GameConfig.hudLevelLblX, GameConfig.hudLevelLblW),
        slotCY(GameConfig.hudLevelLblY, GameConfig.hudLevelLblH),
        lH);
    _drawHudLabel(canvas,
        AppStrings.livesLbl,
        slotCX(GameConfig.hudLivesLblX, GameConfig.hudLivesLblW),
        slotCY(GameConfig.hudLivesLblY, GameConfig.hudLivesLblH),
        lH);

    // Progress bar
    final current  = game.pointsForLevel(game.level);
    final next     = game.pointsForLevel(game.level + 1);
    final ptsNeeded = next - current;
    final pct = ptsNeeded == 0
        ? 0.0
        : min(100.0, ((game.score - current) / ptsNeeded) * 100);
    canvas.drawRect(Rect.fromLTWH(0, hudH, gw, 4), _progressBgPaint);
    canvas.drawRect(Rect.fromLTWH(0, hudH, gw * pct / 100, 4), _progressYellowPaint);
  }

  /// Draws a HUD label (SCORE / LEVEL / LIVES) with the golden-amber gradient
  /// and dark-brown stroke that matches the SVG/PNG reference style.
  void _drawHudLabel(Canvas canvas, String text, double cx, double cy, double height) {
    final fontSize = height * 0.68;
    const strokeColor = Color(0xFF3A1A06);
    const gradientColors = [Color(0xFFE8A040), Color(0xFFB86820), Color(0xFF6B3410)];
    const gradientStops = [0.0, 0.45, 1.0];

    // Stroke pass — drawn first so the fill sits on top.
    final strokeSpan = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: 3.0,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = strokeColor,
      ),
    );
    final strokeTp = TextPainter(
        text: strokeSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center)
      ..layout();
    final ox = cx - strokeTp.width / 2;
    final oy = cy - strokeTp.height / 2;
    strokeTp.paint(canvas, Offset(ox, oy));

    // Fill pass — golden-amber → dark-brown top-to-bottom gradient.
    final gradRect = Rect.fromLTWH(ox, oy, strokeTp.width, strokeTp.height);
    final fillSpan = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: 3.0,
        foreground: Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: gradientColors,
            stops: gradientStops,
          ).createShader(gradRect),
      ),
    );
    final fillTp = TextPainter(
        text: fillSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center)
      ..layout();
    fillTp.paint(canvas, Offset(ox, oy));
  }
}
