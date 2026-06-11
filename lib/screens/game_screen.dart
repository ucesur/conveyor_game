import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../game/game_config.dart';
import '../game/game_controller.dart';
import '../models/box_color.dart';
import '../models/game_assets.dart';
import '../models/game_audio.dart';
import '../widgets/game_painter.dart';
import '../services/score_service.dart';
import '../services/score_repository.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final GameController _game;
  late final Ticker _ticker;
  bool _ready = false;
  bool _showSettings = false;
  bool _scoreSubmitted = false;

  final _fps = ValueNotifier<int>(0);
  int _frameCount = 0;
  double _lastFpsTime = 0;

  @override
  void initState() {
    super.initState();
    _game = GameController();
    _game.addListener(_onGameChange);
    _ticker = createTicker((elapsed) {
      final ms = elapsed.inMicroseconds / 1000.0;
      _game.update(ms);
      _frameCount++;
      if (ms - _lastFpsTime >= 1000.0) {
        _fps.value = _frameCount;
        _frameCount = 0;
        _lastFpsTime = ms;
      }
    });
    // Don't start the ticker until assets are decoded — otherwise the
    // first frame paints with the procedural fallback and pops to sprites
    // a moment later.
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    await GameAssets.instance.init();
    await Future.wait([
      GameAssets.instance.load(),
      GameAudio.instance.load(),
    ]);
    if (!mounted) return;
    setState(() => _ready = true);
    _ticker.start();
  }

  void _onGameChange() {
    if (_game.gameState == GameState.gameover && !_scoreSubmitted) {
      _scoreSubmitted = true;
      if (_game.score > 0) {
        ScoreService.instance.submitScore(
          ScoreEntry(score: _game.score, level: _game.level),
        );
      }
    } else if (_game.gameState == GameState.playing) {
      _scoreSubmitted = false;
    }
  }

  @override
  void dispose() {
    _game.removeListener(_onGameChange);
    _ticker.dispose();
    _game.dispose();
    _fps.dispose();
    GameAudio.instance.dispose();
    super.dispose();
  }

  /// Converts a pointer position from widget pixels into game coordinates.
  /// The canvas fills the full layout area, so the scale is simply
  /// width / gameWidth (gameHeight is set proportionally in setGameSize).
  Offset _toGameCoords(Offset local, Size size) {
    final scale = size.width / GameController.gameWidth;
    return Offset(local.dx / scale, local.dy / scale);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFFBBF24),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: AspectRatio(
            aspectRatio: GameConfig.baseWidth / GameConfig.baseHeight,
            child: LayoutBuilder(builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          // Inform the controller of the actual screen dimensions so conveyor
          // heights and game-space coordinates scale correctly.
          GameController.setGameSize(size.width, size.height);
          // Scale from game-coord (360-wide) to widget pixels so HUD-aligned
          // widgets like the pause button follow the painter across screen
          // sizes instead of drifting into the LIVES cluster on wider layouts.
          final scale = size.width / GameController.gameWidth;
          return Stack(
            children: [
              // --- Game canvas + input ---
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) =>
                    _game.handleStart(_toGameCoords(e.localPosition, size)),
                onPointerMove: (e) =>
                    _game.handleMove(_toGameCoords(e.localPosition, size)),
                onPointerUp: (_) => _game.handleEnd(),
                onPointerCancel: (_) => _game.handleEnd(),
                child: AnimatedBuilder(
                  animation: _game,
                  builder: (context, _) {
                    return Transform.translate(
                      offset: _game.shakeOffset,
                      child: CustomPaint(
                        painter: GamePainter(_game),
                        size: Size.infinite,
                      ),
                    );
                  },
                ),
              ),
              // --- Pause button (visible only while playing) ---
              // Positioned in the empty HUD gap between the LEVEL value
              // (game x=180) and the LIVES cluster (game x=300). Coordinates
              // scale from game px so it hugs the HUD on any screen width.
              Positioned(
                left: 220 * scale,
                top: 17 * scale,
                width: 28 * scale,
                height: 28 * scale,
                child: AnimatedBuilder(
                  animation: _game,
                  builder: (context, _) {
                    if (_game.gameState != GameState.playing) {
                      return const SizedBox.shrink();
                    }
                    return _PauseButton(onTap: _game.pauseGame);
                  },
                ),
              ),
              // --- Debug: maintenance toggle per conveyor ---
              Positioned(
                bottom: 8,
                left: 8,
                child: AnimatedBuilder(
                  animation: _game,
                  builder: (context, _) {
                    if (!_game.debugSlots) return const SizedBox.shrink();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < _game.conveyors.length; i++)
                          GestureDetector(
                            onTap: () => _game.debugToggleMaintenance(
                                _game.conveyors[i].id),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              width: 28,
                              height: 28,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: _game.conveyors[i].maintenance
                                    ? const Color(0xFFFBBF24)
                                        .withValues(alpha: 0.25)
                                    : const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _game.conveyors[i].maintenance
                                      ? const Color(0xFFFBBF24)
                                      : const Color(0xFF475569),
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'M${i + 1}',
                                  style: TextStyle(
                                    color: _game.conveyors[i].maintenance
                                        ? const Color(0xFFFBBF24)
                                        : const Color(0xFF475569),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              // --- Debug: haptics toggle (visible only when debug is on) ---
              Positioned(
                bottom: 8,
                right: 88,
                child: AnimatedBuilder(
                  animation: _game,
                  builder: (context, _) {
                    if (!_game.debugSlots) return const SizedBox.shrink();
                    final on = _game.hapticsEnabled;
                    return GestureDetector(
                      onTap: _game.toggleHaptics,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: on
                              ? const Color(0xFF22C55E).withValues(alpha: 0.25)
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: on
                                ? const Color(0xFF22C55E)
                                : const Color(0xFF475569),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          on ? Icons.vibration : Icons.phone_android,
                          color: on
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF475569),
                          size: 18,
                        ),
                      ),
                    );
                  },
                ),
              ),
              // --- Debug: stop conveyors (visible only when debug is on) ---
              Positioned(
                bottom: 8,
                right: 48,
                child: AnimatedBuilder(
                  animation: _game,
                  builder: (context, _) {
                    if (!_game.debugSlots) return const SizedBox.shrink();
                    final on = _game.debugPaused;
                    return GestureDetector(
                      onTap: _game.toggleDebugPaused,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: on
                              ? const Color(0xFFFF6600).withValues(alpha: 0.25)
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: on
                                ? const Color(0xFFFF6600)
                                : const Color(0xFF475569),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          on ? Icons.play_arrow : Icons.pause,
                          color: on
                              ? const Color(0xFFFF6600)
                              : const Color(0xFF475569),
                          size: 18,
                        ),
                      ),
                    );
                  },
                ),
              ),
              // --- FPS counter (above debug toggle, visible only in debug) ---
              Positioned(
                bottom: 48,
                right: 8,
                child: AnimatedBuilder(
                  animation: _game,
                  builder: (context, _) {
                    return ValueListenableBuilder<int>(
                      valueListenable: _fps,
                      builder: (context, fps, _) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: const Color(0xFF475569), width: 1),
                        ),
                        child: Text(
                          '$fps fps',
                          style: TextStyle(
                            color: fps >= 55
                                ? const Color(0xFF22C55E)
                                : fps >= 30
                                    ? const Color(0xFFFBBF24)
                                    : const Color(0xFFF87171),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // --- Debug slots toggle (bottom-right corner) ---
              Positioned(
                bottom: 8,
                right: 8,
                child: AnimatedBuilder(
                  animation: _game,
                  builder: (context, _) {
                    final on = _game.debugSlots;
                    return GestureDetector(
                      onTap: _game.toggleDebugSlots,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: on
                              ? const Color(0xFF00FF00).withValues(alpha: 0.2)
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: on
                                ? const Color(0xFF00FF00)
                                : const Color(0xFF475569),
                            width: 1,
                          ),
                        ),
                        child: Icon(Icons.grid_on,
                            color: on
                                ? const Color(0xFF00FF00)
                                : const Color(0xFF475569),
                            size: 18),
                      ),
                    );
                  },
                ),
              ),
              // --- Overlays: Menu, Paused, Game Over ---
              // Positioned.fill so the overlay Container receives tight
              // constraints and actually covers the Stack — otherwise it
              // hugs its Column content and anchors to the top-left.
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _game,
                  builder: (context, _) {
                    if (_game.gameState == GameState.menu) {
                      return _MenuOverlay(
                          onStart: _game.startGame,
                          onSettings: () => setState(() => _showSettings = true),
                          highScore: _game.highScore);
                    } else if (_game.gameState == GameState.paused) {
                      return _PausedOverlay(
                          onResume: _game.resumeGame,
                          onMenu: _game.exitToMenu,
                          onSettings: () => setState(() => _showSettings = true));
                    } else if (_game.gameState == GameState.gameover) {
                      return _GameOverOverlay(
                          score: _game.score,
                          level: _game.level,
                          highScore: _game.highScore,
                          onRestart: _game.startGame);
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              // --- Settings overlay (covers everything, driven by widget state) ---
              if (_showSettings)
                Positioned.fill(
                  child: _SettingsOverlay(
                    game: _game,
                    onClose: () => setState(() => _showSettings = false),
                  ),
                ),
            ],
          );
        }),
          ),
        ),
      ),
    );
  }
}

// -------------------- Pause button (HUD) --------------------
// Sized by its parent Positioned so the glyph scales with the HUD. Icon
// size derived from LayoutBuilder's shortest side keeps a consistent
// padding inside the rounded frame across screen widths.
class _PauseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _PauseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final side = constraints.biggest.shortestSide;
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(side * 0.2),
            border: Border.all(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.8), width: 1),
          ),
          child: Icon(Icons.pause,
              color: const Color(0xFFFBBF24), size: side * 0.7),
        ),
      );
    });
  }
}

// -------------------- Paused overlay --------------------
class _PausedOverlay extends StatelessWidget {
  final VoidCallback onResume;
  final VoidCallback onMenu;
  final VoidCallback onSettings;
  const _PausedOverlay(
      {required this.onResume,
      required this.onMenu,
      required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A).withValues(alpha: 0.85),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('PAUSED',
              style: TextStyle(
                  color: Color(0xFFFBBF24),
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4)),
          const SizedBox(height: 32),
          _YellowButton(label: 'RESUME', onPressed: onResume),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onSettings,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text('SETTINGS',
                  style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2)),
            ),
          ),
          GestureDetector(
            onTap: onMenu,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text('MENU',
                  style: TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2)),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------- Menu overlay --------------------
class _MenuOverlay extends StatefulWidget {
  final VoidCallback onStart;
  final VoidCallback onSettings;
  final int highScore;
  const _MenuOverlay(
      {required this.onStart,
      required this.onSettings,
      required this.highScore});

  @override
  State<_MenuOverlay> createState() => _MenuOverlayState();
}

class _MenuOverlayState extends State<_MenuOverlay> {
  List<ScoreEntry>? _leaders;

  @override
  void initState() {
    super.initState();
    ScoreService.instance.getTopScores(limit: 10).then((list) {
      if (mounted) setState(() => _leaders = list);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          color: const Color(0xFF0F172A).withValues(alpha: 0.9),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('CONVEYOR',
                    style: TextStyle(
                        color: Color(0xFFFBBF24),
                        fontSize: 38,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('MATCH',
                    style: TextStyle(
                        color: Color(0xFFFBBF24),
                        fontSize: 38,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text(
                  'Drag boxes to a NEIGHBOR\nconveyor of the matching color.\nBoxes can only hop one lane!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFFCBD5E1), fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in BoxColor.all.take(3))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: c.bg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: c.dark, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (widget.highScore > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('Best: ${widget.highScore}',
                        style: const TextStyle(
                            color: Color(0xFFFBBF24),
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ),
                _YellowButton(label: 'START', onPressed: widget.onStart),
                const SizedBox(height: 24),
                _buildLeaderboard(),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        // Gear button — top-right corner
        Positioned(
          top: 12,
          right: 12,
          child: GestureDetector(
            onTap: widget.onSettings,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF475569)),
              ),
              child: const Icon(Icons.settings,
                  color: Color(0xFF94A3B8), size: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Expanded(child: Divider(color: Color(0xFF334155))),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'HIGH SCORES',
                style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2),
              ),
            ),
            Expanded(child: Divider(color: Color(0xFF334155))),
          ],
        ),
        const SizedBox(height: 10),
        if (_leaders == null)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Color(0xFF475569), strokeWidth: 2),
              ),
            ),
          )
        else if (_leaders!.isEmpty)
          const Text(
            'No scores yet — be the first!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF475569), fontSize: 12),
          )
        else
          for (int i = 0; i < _leaders!.length; i++)
            _LeaderRow(rank: i + 1, entry: _leaders![i], myScore: -1),
      ],
    );
  }
}

// -------------------- Game-over overlay --------------------
class _GameOverOverlay extends StatefulWidget {
  final int score;
  final int level;
  final int highScore;
  final VoidCallback onRestart;
  const _GameOverOverlay({
    required this.score,
    required this.level,
    required this.highScore,
    required this.onRestart,
  });

  @override
  State<_GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<_GameOverOverlay> {
  List<ScoreEntry>? _leaders;

  @override
  void initState() {
    super.initState();
    // Short delay so the submission we just sent has time to land.
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      ScoreService.instance
          .getTopScores(limit: 5)
          .then((list) { if (mounted) setState(() => _leaders = list); });
    });
  }

  @override
  Widget build(BuildContext context) {
    final newHigh = widget.score >= widget.highScore && widget.score > 0;
    return Container(
      color: const Color(0xFF0F172A).withValues(alpha: 0.95),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 8),
            const Text('GAME OVER',
                style: TextStyle(
                    color: Color(0xFFF87171),
                    fontSize: 30,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            const Text('SCORE',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
            Text('${widget.score}',
                style: const TextStyle(
                    color: Color(0xFFFBBF24),
                    fontSize: 48,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('LEVEL REACHED',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
            Text('${widget.level}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (newHigh)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('🏆 New High Score!',
                    style: TextStyle(
                        color: Color(0xFFFBBF24),
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
            _YellowButton(label: 'PLAY AGAIN', onPressed: widget.onRestart),
            const SizedBox(height: 20),
            _buildLeaderboard(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'TOP SCORES',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 2),
        ),
        const SizedBox(height: 8),
        if (_leaders == null)
          const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  color: Color(0xFF475569), strokeWidth: 2),
            ),
          )
        else if (_leaders!.isEmpty)
          const Text('No scores yet',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF475569), fontSize: 12))
        else
          for (int i = 0; i < _leaders!.length; i++)
            _LeaderRow(rank: i + 1, entry: _leaders![i], myScore: widget.score),
      ],
    );
  }
}

class _LeaderRow extends StatelessWidget {
  final int rank;
  final ScoreEntry entry;
  final int myScore;
  const _LeaderRow(
      {required this.rank, required this.entry, required this.myScore});

  @override
  Widget build(BuildContext context) {
    final isMe = entry.score == myScore;
    final rankColor = rank == 1
        ? const Color(0xFFFFD700)
        : rank == 2
            ? const Color(0xFFC0C0C0)
            : rank == 3
                ? const Color(0xFFCD7F32)
                : const Color(0xFF475569);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isMe
            ? const Color(0xFFFBBF24).withValues(alpha: 0.12)
            : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isMe ? const Color(0xFFFBBF24) : const Color(0xFF334155),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text('#$rank',
                style: TextStyle(
                    color: rankColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Text('${entry.score}',
                style: TextStyle(
                    color: isMe ? const Color(0xFFFBBF24) : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ),
          Text('Lv.${entry.level}',
              style:
                  const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
        ],
      ),
    );
  }
}

// -------------------- Settings overlay --------------------
class _SettingsOverlay extends StatefulWidget {
  final GameController game;
  final VoidCallback onClose;
  const _SettingsOverlay({required this.game, required this.onClose});

  @override
  State<_SettingsOverlay> createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends State<_SettingsOverlay> {
  bool _confirmReset = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A).withValues(alpha: 0.97),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'SETTINGS',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Color(0xFFFBBF24),
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 3),
          ),
          const SizedBox(height: 36),
          // Haptics toggle
          _SettingsRow(
            label: 'Haptics',
            icon: widget.game.hapticsEnabled
                ? Icons.vibration
                : Icons.phone_android,
            value: widget.game.hapticsEnabled,
            onToggle: () {
              widget.game.toggleHaptics();
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
          // High score reset
          _buildResetRow(),
          const SizedBox(height: 40),
          GestureDetector(
            onTap: () {
              setState(() => _confirmReset = false);
              widget.onClose();
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'BACK',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResetRow() {
    if (widget.game.highScore == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: const Text(
          'No high score yet',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF475569), fontSize: 14),
        ),
      );
    }

    if (!_confirmReset) {
      return GestureDetector(
        onTap: () => setState(() => _confirmReset = true),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF475569)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('High Score',
                  style:
                      TextStyle(color: Color(0xFFCBD5E1), fontSize: 15)),
              Row(
                children: [
                  Text(
                    '${widget.game.highScore}',
                    style: const TextStyle(
                        color: Color(0xFFFBBF24),
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 12),
                  const Text('RESET',
                      style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Confirmation
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEF4444)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Reset high score?',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    widget.game.resetHighScore();
                    setState(() => _confirmReset = false);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFFEF4444).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: const Color(0xFFEF4444)),
                    ),
                    child: const Text('YES',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _confirmReset = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: const Color(0xFF475569)),
                    ),
                    child: const Text('NO',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -------------------- Settings row (toggle) --------------------
class _SettingsRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool value;
  final VoidCallback onToggle;
  const _SettingsRow(
      {required this.label,
      required this.icon,
      required this.value,
      required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final activeColor = const Color(0xFF22C55E);
    final inactiveColor = const Color(0xFF475569);
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: value ? activeColor : const Color(0xFF475569)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon,
                    color: value ? activeColor : const Color(0xFF94A3B8),
                    size: 20),
                const SizedBox(width: 12),
                Text(label,
                    style: const TextStyle(
                        color: Color(0xFFCBD5E1), fontSize: 15)),
              ],
            ),
            // Animated pill toggle
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 44,
              height: 24,
              decoration: BoxDecoration(
                color: value
                    ? activeColor.withValues(alpha: 0.25)
                    : const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: value ? activeColor : inactiveColor),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                alignment:
                    value ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: value ? activeColor : inactiveColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------- Shared yellow pill button --------------------
class _YellowButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  const _YellowButton({required this.label, required this.onPressed});

  @override
  State<_YellowButton> createState() => _YellowButtonState();
}

class _YellowButtonState extends State<_YellowButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFBBF24),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(widget.label,
              style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
