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
  // HUD.svg viewBox: 800×195. Rendered at full game width, maintaining aspect ratio.
  static const double hudSvgW = 800.0;
  static const double hudSvgH = 195.0;
  // Derived HUD image height (baseWidth * 195 / 800 = 97.5 at baseWidth=400).
  static double get hudImageHeight => baseWidth * hudSvgH / hudSvgW;
  // Named slot positions in HUD SVG coordinates (x, y, width, height).
  static const double hudScoreX = 14.0,  hudScoreY = 132.0, hudScoreW = 216.0, hudScoreH = 50.0;
  static const double hudLevelX = 322.0, hudLevelY = 132.0, hudLevelW = 156.0, hudLevelH = 50.0;
  static const double hudLivesX = 570.0, hudLivesY = 132.0, hudLivesW = 172.0, hudLivesH = 50.0;

  // ── Box ──────────────────────────────────────────────────────────────────
  static const double boxSize = 40.0;

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
  // Panel sits between the progress bar and the generator/conveyor zone.
  // comboAreaTop: after hudImageHeight (97.5) + 4px progress bar + gap.
  static const double comboAreaTop = 106.0;
  // comboAreaHeight: (comboAreaWidth-8) * containerSvgH / containerSvgW ≈ 77.
  static const double comboAreaHeight = 77.0;
  static const double comboAreaWidth = 220.0;
  // Number of recipe slots (drives _generateComboArea).
  static const int comboSlotCount = 2;
  // container.svg viewBox: 800×290. Rendered at comboAreaWidth, maintaining aspect ratio.
  static const double containerSvgW = 800.0;
  static const double containerSvgH = 290.0;
  // Named slot positions in container SVG coordinates (x, y, width, height).
  static const double containerSlot1X = 78.0,  containerSlot1Y = 75.0, containerSlot1W = 160.0, containerSlot1H = 165.0;
  static const double containerSlot2X = 282.0, containerSlot2Y = 75.0, containerSlot2W = 160.0, containerSlot2H = 165.0;
  static const double containerSlot3X = 523.0, containerSlot3Y = 75.0, containerSlot3W = 160.0, containerSlot3H = 165.0;

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
