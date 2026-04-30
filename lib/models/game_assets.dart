import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'box_color.dart';

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
  final Map<String, ui.Image> _conveyors = {};
  bool _loaded = false;

  /// Reserved for future warm-up steps (font registration etc.) so callers
  /// can keep the symmetric `init() → load()` shape.
  Future<void> init() async {}

  /// Decodes every `assets/boxes/{id}.png`, `assets/gates/{id}.png`, and
  /// `assets/conveyors/{id}.png` for ids in [BoxColor.all]. Idempotent.
  Future<void> load() async {
    if (_loaded) return;
    for (final color in BoxColor.all) {
      final box = await _tryLoad('assets/boxes/${color.id}.png');
      if (box != null) _boxes[color.id] = box;
      final gate = await _tryLoad('assets/gates/${color.id}.png');
      if (gate != null) _gates[color.id] = gate;
      final conveyor = await _tryLoad('assets/conveyors/${color.id}.png');
      if (conveyor != null) _conveyors[color.id] = conveyor;
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

  ui.Image? boxImage(BoxColor color) => _boxes[color.id];
  ui.Image? gateImage(BoxColor color) => _gates[color.id];
  ui.Image? conveyorImage(BoxColor color) => _conveyors[color.id];
}
