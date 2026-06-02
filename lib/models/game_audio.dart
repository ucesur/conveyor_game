import 'package:audioplayers/audioplayers.dart';

/// Every distinct sound event the game can trigger.
/// File name = `assets/sounds/${effect.name}.mp3`
///   correct.mp3  — correct box scored
///   wrong.mp3    — wrong box scored
///   combo.mp3    — combo streak hit (×2 or higher)
///   levelUp.mp3  — level up fanfare
///   bomb.mp3     — bomb special triggered
///   icy.mp3      — icy special triggered
///   gameOver.mp3 — game over
///   drag.mp3     — box picked up
///   drop.mp3     — box successfully thrown onto a belt
enum SoundEffect {
  correct,
  wrong,
  combo,
  levelUp,
  bomb,
  icy,
  gameOver,
  drag,
  drop,
}

/// Singleton that pre-loads every sound once at startup.
/// Missing files are silently ignored — the matching [play] call becomes a
/// no-op, so the game works fully without any audio assets present.
class GameAudio {
  GameAudio._();
  static final GameAudio instance = GameAudio._();

  final Map<SoundEffect, AudioPlayer> _players = {};
  bool enabled = true;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true; // set early so concurrent calls don't pile up
    for (final effect in SoundEffect.values) {
      // Outer try: catches MissingPluginException if the platform doesn't
      // support audioplayers (Windows desktop, some web configs, etc.).
      // On first failure we stop — no point retrying for every effect.
      AudioPlayer player;
      try {
        player = AudioPlayer();
        await player.setReleaseMode(ReleaseMode.stop);
      } catch (_) {
        enabled = false;
        return;
      }
      // Inner try: catches missing / unregistered asset file only.
      try {
        await player.setSource(AssetSource('sounds/${effect.name}.mp3'));
        _players[effect] = player;
      } catch (_) {
        await player.dispose();
      }
    }
  }

  /// Fire-and-forget; safe to call from the game loop (no await needed).
  void play(SoundEffect effect) {
    if (!enabled) return;
    try {
      _players[effect]
          ?.play(AssetSource('sounds/${effect.name}.mp3'))
          .catchError((_) {});
    } catch (_) {}
  }

  Future<void> dispose() async {
    for (final p in _players.values) {
      await p.dispose();
    }
    _players.clear();
    _loaded = false;
  }
}
