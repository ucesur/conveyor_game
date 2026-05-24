part of '../game_painter.dart';

extension ComboLayer on GamePainter {
  void _drawComboArea(Canvas canvas, double now) {
    final area   = game.comboArea!;
    final panelX = (GameController.gameWidth - GameConfig.comboAreaWidth) / 2;
    final panelY = GameConfig.comboAreaTop;
    final panelW = GameConfig.comboAreaWidth - 8.0;
    final panelH = panelW * GameConfig.containerSvgH / GameConfig.containerSvgW;
    final panelRect  = Rect.fromLTWH(panelX, panelY, panelW, panelH);
    final panelRRect = RRect.fromRectAndRadius(panelRect, const Radius.circular(8));

    final isComplete    = area.completionTime != null;
    final completePulse = isComplete
        ? (0.5 + 0.5 * sin((now - area.completionTime!) * 0.015)).clamp(0.0, 1.0)
        : 0.0;

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

    final containerImg = GameAssets.instance.containerImage;
    if (containerImg != null) {
      _drawSprite(canvas, containerImg, panelRect);
    } else {
      canvas.drawRRect(panelRRect, _hudBgPaint);
      canvas.drawRRect(panelRRect, (_sp..color = const Color(0xFF1E3A5F)..strokeWidth = 1));
    }

    if (isComplete) {
      canvas.drawRRect(panelRRect, (_sp
        ..color = const Color(0xFFFBBF24).withValues(alpha: 0.6 + completePulse * 0.4)
        ..strokeWidth = 2.0));
    }

    // Recipe slots
    for (int i = 0; i < area.recipe.length; i++) {
      final slot     = [slot1, slot2][i];
      final color    = area.recipe[i];
      final isDone   = i < area.progress || isComplete;
      final isCurrent = !isComplete && i == area.progress;
      final alpha    = isDone || isCurrent ? 1.0 : 0.35;
      final pulse    = isCurrent ? (0.5 + 0.5 * sin(now * 0.008)) : 0.0;
      const pad      = 3.0;
      final boxRect  = Rect.fromLTWH(slot.left + pad, slot.top + pad,
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

      if (isCurrent) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(boxRect.inflate(3), const Radius.circular(9)),
          (_sp..color = color.light.withValues(alpha: 0.4 + pulse * 0.6)..strokeWidth = 2),
        );
      }
      if (isDone) {
        _drawText(canvas, '✓', slot.center.dx, slot.center.dy,
            color: Colors.white,
            fontSize: slot.height * 0.45,
            fontWeight: FontWeight.bold,
            align: TextAlign.center,
            baselineCenter: true);
      }
    }

    // Reward slot
    final rewardAlpha = isComplete ? (0.7 + completePulse * 0.3) : 1.0;
    final rewardFallback = switch (area.reward) {
      SpecialType.bomb => '💣',
      SpecialType.icy  => '❄',
    };
    const pad      = 3.0;
    final spriteRect = Rect.fromLTWH(slot3.left + pad, slot3.top + pad,
        slot3.width - pad * 2, slot3.height - pad * 2);

    final specialImg = GameAssets.instance.specialImage(area.reward);
    if (specialImg != null) {
      _drawSprite(canvas, specialImg, spriteRect, opacity: rewardAlpha);
    } else {
      canvas.drawRRect(RRect.fromRectAndRadius(spriteRect, const Radius.circular(6)),
          (_p..color = const Color(0xFF1A1A1A).withValues(alpha: rewardAlpha)));
      _drawText(canvas, rewardFallback,
          slot3.center.dx, slot3.top + slot3.height * 0.45,
          color: Colors.white.withValues(alpha: rewardAlpha),
          fontSize: slot3.height * 0.38,
          align: TextAlign.center,
          baselineCenter: true);
    }
  }
}
