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
import '../models/game_assets.dart';

part 'painters/hud_layer.dart';
part 'painters/combo_layer.dart';
part 'painters/belt_layer.dart';
part 'painters/box_layer.dart';
part 'painters/effect_layer.dart';

// ---- Per-conveyor geometry cache ----
class _ConvGeom {
  final double h;
  final double xLean;
  final Path bodyPath;
  final Float64List? shearMatrix;
  _ConvGeom({required this.h, required this.xLean, required this.bodyPath, this.shearMatrix});
}

// ---- Library-level paint singletons ----
// Top-level so all part files can use them without GamePainter. prefix.
// Reuse between frames — callers set properties before each draw call.
final _p  = Paint();
final _sp = Paint()..style = PaintingStyle.stroke;

final _hudBgPaint          = Paint()..color = const Color(0xFF0F172A);
final _progressBgPaint     = Paint()..color = const Color(0xFF1E293B);
final _progressYellowPaint = Paint()..color = const Color(0xFFFBBF24);
final _liveRedPaint        = Paint()..color = const Color(0xFFEF4444);
final _liveDeadPaint       = Paint()..color = const Color(0xFF475569);
final _liveStrokePaint     = Paint()
  ..color = const Color(0xFFFCA5A5)
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1;
final _beltFallbackPaint   = Paint()..color = const Color(0xFF475569);
final _spritePaint         = Paint()..filterQuality = FilterQuality.medium;

// Background gradient cache
Paint?  _bgPaint;
double  _bgCachedWidth  = 0;
double  _bgCachedHeight = 0;

// Text cache
final _textCache    = <String, TextPainter>{};
const _textCacheMax = 128;

// Conveyor geometry cache
final _convGeomCache = <int, _ConvGeom>{};

/// Thin coordinator — all drawing logic lives in `painters/` part files.
class GamePainter extends CustomPainter {
  final GameController game;
  final Paint _particlePaint = Paint();

  GamePainter(this.game) : super(repaint: game);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / GameController.gameWidth);

    final now = game.currentTime;
    _drawBackground(canvas);
    _drawHUD(canvas);
    if (game.comboArea != null) _drawComboArea(canvas, now);
    for (final conv in game.conveyors) { _drawConveyor(canvas, conv, now); }
    _drawTrail(canvas);
    for (final box in game.boxes) { _drawBox(canvas, box); }
    _drawParticles(canvas, now);
    _drawGeneratorBacks(canvas, now);
    _drawFallingBoxes(canvas);
    if (game.comboCount >= 2) _drawComboBalloon(canvas, now);
    _drawPopups(canvas, now);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  // ---- Shared draw utilities (called by layer extensions) ----
  void _drawSprite(Canvas canvas, ui.Image image, Rect dst, {double opacity = 1.0}) {
    _spritePaint.colorFilter = opacity < 1.0
        ? ColorFilter.mode(Colors.white.withValues(alpha: opacity), BlendMode.modulate)
        : null;
    canvas.drawImageRect(image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        dst, _spritePaint);
  }

  void _drawDashedRRect(Canvas canvas, RRect rrect, Color color,
      double strokeWidth, double opacity) {
    canvas.drawRRect(rrect,
        (_sp..color = color.withValues(alpha: opacity)..strokeWidth = strokeWidth));
  }

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
    if (strokeColor != null && strokeWidth > 0) {
      final style = TextStyle(color: color, fontSize: fontSize,
          fontWeight: fontWeight, letterSpacing: letterSpacing);
      final tp = TextPainter(text: TextSpan(text: text, style: style),
          textAlign: align, textDirection: TextDirection.ltr)..layout();
      final ox = _alignX(x, align, tp.width);
      final oy = baselineCenter ? y - tp.height / 2 : y - tp.height * 0.75;
      final stroke = TextPainter(
        text: TextSpan(text: text, style: style.copyWith(
          foreground: Paint()..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth..color = strokeColor)),
        textAlign: align, textDirection: TextDirection.ltr,
      )..layout();
      stroke.paint(canvas, Offset(ox, oy));
      tp.paint(canvas, Offset(ox, oy));
      return;
    }

    final key = '$text\x00${color.a}_${color.r}_${color.g}_${color.b}'
        '\x00$fontSize\x00${fontWeight.index}\x00${align.index}\x00$letterSpacing';
    var tp = _textCache[key];
    if (tp == null) {
      if (_textCache.length >= _textCacheMax) _textCache.remove(_textCache.keys.first);
      tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: color,
            fontSize: fontSize, fontWeight: fontWeight, letterSpacing: letterSpacing)),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout();
      _textCache[key] = tp;
    }
    final ox = _alignX(x, align, tp.width);
    final oy = baselineCenter ? y - tp.height / 2 : y - tp.height * 0.75;
    tp.paint(canvas, Offset(ox, oy));
  }

  static double _alignX(double x, TextAlign align, double w) {
    if (align == TextAlign.center) return x - w / 2;
    if (align == TextAlign.right)  return x - w;
    return x;
  }
}
