/// Single source of truth for every tunable layout / visual constant.
/// Change a value here and it propagates everywhere automatically.
class GameConfig {
  GameConfig._();

  // ── Canvas defaults ──────────────────────────────────────────────────────
  // Actual values are overwritten by GameController.setGameSize() at runtime.
  static const double baseWidth = 360.0;
  static const double baseHeight = 600.0;

  // ── HUD ──────────────────────────────────────────────────────────────────
  static const double hudBottom = 114.0;

  // ── Box ──────────────────────────────────────────────────────────────────
  static const double boxSize = 50.0;

  // ── Conveyor ─────────────────────────────────────────────────────────────
  static const double conveyorWidth = 52.0;
  static const double conveyorGap = 14.0;
  static const int conveyorMaxCount = 5;

  // ── Gate ─────────────────────────────────────────────────────────────────
  // gateHeight  — used by GameController to compute the gateY anchor position.
  // gateSpriteHeight — actual drawn height of the gate image / procedural rect.
  static const double gateHeight = 40.0;
  static const double gateSpriteHeight = 60.0;
  static const double gateOffset = 1.0;

  // ── 3-D Perspective ──────────────────────────────────────────────────────
  // perspDepth    — horizontal inset per side at the top (far) edge of the belt.
  // railWidthTop  — rail thickness at the top (far) end.
  // railWidthBottom — rail thickness at the bottom (close) end.
  static const double perspDepth = 10.0;
  static const double railWidthTop = 1.0;
  static const double railWidthBottom = 5.5;

  // ── Box spawn frequency ──────────────────────────────────────────────────
  // Interval between spawns on a single belt at level 1 (ms).
  // Shrinks by 200 ms per level, bottoms out at spawnIntervalMin.
  // Each spawn gets ±30 % jitter (0.7 … 1.3 × the base interval).
  static const double spawnIntervalBase = 8000;
  static const double spawnIntervalMin = 4000;
  static const double spawnIntervalJitterMin = 0.7;
  static const double spawnIntervalJitterMax = 1.3;

  // ── Generator ────────────────────────────────────────────────────────────
  // Front = isDown belt (spawn end at top).  Back = isUp belt (spawn end at bottom).
  // ExtraW  — pixels added beyond the belt-edge width for the image rect.
  // OffsetX — horizontal shift applied to the image rect left edge.
  // OffsetY — vertical shift applied to the image rect top edge (back only).
  static const double generatorFrontExtraW = 30.0;
  static const double generatorFrontOffsetX = -15.0;
  static const double generatorBackExtraW = 40.0;
  static const double generatorBackOffsetX = -18.0;
  static const double generatorBackOffsetY = -30.0;
}
