import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../game/game_controller.dart';
import '../models/box_color.dart';
import '../models/game_assets.dart';
import '../widgets/game_painter.dart';

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

  @override
  void initState() {
    super.initState();
    _game = GameController();
    // Drives the game update each frame — elapsed is in microseconds, we
    // convert to milliseconds to match the React `performance.now()` units.
    _ticker = createTicker((elapsed) {
      final ms = elapsed.inMicroseconds / 1000.0;
      _game.update(ms);
    });
    // Don't start the ticker until assets are decoded — otherwise the
    // first frame paints with the procedural fallback and pops to sprites
    // a moment later.
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    await GameAssets.instance.init();
    await GameAssets.instance.load();
    if (!mounted) return;
    setState(() => _ready = true);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _game.dispose();
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
                          highScore: _game.highScore);
                    } else if (_game.gameState == GameState.paused) {
                      return _PausedOverlay(
                          onResume: _game.resumeGame,
                          onMenu: _game.exitToMenu);
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
            ],
          );
        }),
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
  const _PausedOverlay({required this.onResume, required this.onMenu});

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
class _MenuOverlay extends StatelessWidget {
  final VoidCallback onStart;
  final int highScore;
  const _MenuOverlay({required this.onStart, required this.highScore});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A).withValues(alpha: 0.9),
      padding: const EdgeInsets.all(24),
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
          const SizedBox(height: 24),
          const Text(
            'Drag boxes to a NEIGHBOR\nconveyor of the matching color.\nBoxes can only hop one lane!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
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
          const SizedBox(height: 32),
          if (highScore > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('High Score: $highScore',
                  style: const TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ),
          _YellowButton(label: 'START', onPressed: onStart),
        ],
      ),
    );
  }
}

// -------------------- Game-over overlay --------------------
class _GameOverOverlay extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final newHigh = score >= highScore && score > 0;
    return Container(
      color: const Color(0xFF0F172A).withValues(alpha: 0.95),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('GAME OVER',
              style: TextStyle(
                  color: Color(0xFFF87171),
                  fontSize: 30,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          const Text('SCORE',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
          Text('$score',
              style: const TextStyle(
                  color: Color(0xFFFBBF24),
                  fontSize: 48,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('LEVEL REACHED',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
          Text('$level',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (newHigh)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('🏆 New High Score!',
                  style: TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 8),
          _YellowButton(label: 'PLAY AGAIN', onPressed: onRestart),
        ],
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
