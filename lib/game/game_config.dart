/// Single source of truth for every tunable layout / visual constant.
/// Change a value here and it propagates everywhere automatically.
class GameConfig {
  GameConfig._();

  // ── Canvas defaults ──────────────────────────────────────────────────────
  // Actual values are overwritten by GameController.setGameSize() at runtime.
  static const double baseWidth = 400.0;
  static const double baseHeight = 800.0;

  // ── HUD ──────────────────────────────────────────────────────────────────
  static const double hudBottom = 114.0;

  // ── Box ──────────────────────────────────────────────────────────────────
  static const double boxSize = 50.0;

  // ── Conveyor ─────────────────────────────────────────────────────────────
  static const double conveyorWidth = 52.0;
  static const double conveyorGap = 14.0;
  static const int conveyorMaxCount = 5;
  // Top edge of conveyors as a fraction of total game height.
  static const double conveyorTopFraction = 0.32;
  // Minimum number of box-sized slots every conveyor must have.
  static const int conveyorMinSlots = 5;

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

  // ── Conveyor layout perspective ──────────────────────────────────────────
  // Top of each belt leans toward the layout centre by
  //   (beltCenterX − layoutCenterX) × factor  pixels.
  // 0 = no lean; 0.15 ≈ 20 px for the outermost belt (132 px from centre).
  static const double conveyorPerspectiveXFactor = 0.25;

  // ── Box spawn frequency ──────────────────────────────────────────────────
  // Interval between spawns on a single belt at level 1 (ms).
  // Shrinks by 200 ms per level, bottoms out at spawnIntervalMin.
  // Each spawn gets ±30 % jitter (0.7 … 1.3 × the base interval).
  static const double spawnIntervalBase = 8000;
  static const double spawnIntervalMin = 4000;
  static const double spawnIntervalJitterMin = 0.7;
  static const double spawnIntervalJitterMax = 1.3;

  // ── Combination area ─────────────────────────────────────────────────────
  // Panel sits between the progress bar (y≈64) and the generator/conveyor zone.
  static const double comboAreaTop = 80.0;
  static const double comboAreaHeight = 66.0;
  // Recipe display: comboSlotCount colored boxes with arrows between them.
  static const int comboSlotCount = 2;
  static const double comboRecipeBoxSize = 38.0;
  static const double comboRecipeStartX = 12.0;
  // Space between adjacent recipe boxes (includes the ▶ arrow glyph).
  static const double comboRecipeSpacer = 20.0;

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
