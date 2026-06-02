import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'box_color.dart';
import 'special_type.dart';

/// Singleton that decodes box / gate / conveyor PNGs once at startup so the
/// painter can blit them each frame without re-reading the asset bundle.
///
/// Any missing file is silently absorbed — the matching `*Image` getter then
/// returns null and the painter falls back to its procedural drawing, which
/// lets the game ship with a partial asset set.
class GameAssets {
  GameAssets._();
  static final GameAssets instance = GameAssets._();

  final Map<String, ui.Image> _boxes = {};
  final Map<String, ui.Image> _gates = {};
  final Map<String, ui.Image> _specials = {};
  ui.Image? _background;
  ui.Image? _generatorFront;
  ui.Image? _generatorBack;
  ui.Image? _belt;
  ui.Image? _hud;
  ui.Image? _container;
  ui.Image? _bubble;
  bool _loaded = false;

  /// Reserved for future warm-up steps (font registration etc.) so callers
  /// can keep the symmetric `init() → load()` shape.
  Future<void> init() async {}

  /// Decodes every `assets/boxes/{id}.png`, `assets/gates/{id}.png`, and
  /// `assets/conveyors/{id}.png` for ids in [BoxColor.all]. Idempotent.
  Future<void> load() async {
    if (_loaded) return;
    _background = await _tryLoad('assets/background/background.png');
    _generatorFront = await _tryLoad('assets/generator/generator_front.png');
    _generatorBack = await _tryLoad('assets/generator/generator_back.png');
    _belt = await _tryLoad('assets/conveyors/belt.png');
    _hud = await _tryLoad('assets/ui/HUD.png');
    _container = await _tryLoad('assets/ui/container.png');
    _bubble = await _tryLoad('assets/splash/bubble.png');
    for (final color in BoxColor.all) {
      final box = await _tryLoad('assets/boxes/${color.id}.png');
      if (box != null) _boxes[color.id] = box;
      final gate = await _tryLoad('assets/gates/${color.id}.png');
      if (gate != null) _gates[color.id] = gate;
    }
    for (final type in SpecialType.values) {
      final img = await _tryLoad('assets/boxes/specials/${type.name}.png');
      if (img != null) _specials[type.name] = img;
    }
    _loaded = true;
  }

  Future<ui.Image?> _tryLoad(String path) async {
    try {
      final data = await rootBundle.load(path);
      final codec =
          await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  ui.Image? get backgroundImage => _background;
  ui.Image? get generatorFrontImage => _generatorFront;
  ui.Image? get generatorBackImage => _generatorBack;
  ui.Image? get hudImage => _hud;
  ui.Image? get containerImage => _container;
  ui.Image? get bubbleImage => _bubble;
  ui.Image? boxImage(BoxColor color) => _boxes[color.id];
  ui.Image? gateImage(BoxColor color) => _gates[color.id];
  ui.Image? conveyorImage(BoxColor color) => _belt;
  ui.Image? specialImage(SpecialType type) => _specials[type.name];
}
