# CLAUDE.md

## Commands

```bash
flutter pub get
flutter run                        # connected device
flutter run -d chrome|windows      # web / desktop
flutter test
flutter analyze
flutter build apk|web
```

> `test/widget_test.dart` references a deleted `MyApp` — ignore or replace with a `ConveyorMatchApp` smoke test.

## Architecture

Fixed **360×600 virtual canvas**, letterboxed via `AspectRatio` + `ClipRRect`.

**Data flow:** `Ticker` → `GameController.update(ms)` → `notifyListeners()` → `AnimatedBuilder` → `GamePainter.paint()`

`GameController` (`lib/game/game_controller.dart`) is the single source of truth — extends `ChangeNotifier`, owns `boxes`, `conveyors`, `popups`, `transition`, `score`, `lives`, `level`, `gameState`.

Pointer events arrive in widget pixels; `GameScreen._toGameCoords()` converts via `_computeScale` + letterbox offsets.

### Files

| File | Role |
|---|---|
| `lib/game/game_controller.dart` | Game loop, physics, spawn/move/score, drag rules, maintenance & resize |
| `lib/widgets/game_painter.dart` | Pure `CustomPainter` — reads controller, never writes |
| `lib/screens/game_screen.dart` | Ticker owner, pointer-event bridge, overlays |
| `lib/models/conveyor.dart` | Belt state (direction, height, maintenance, resize) |
| `lib/models/box.dart` | Box state (position, drag trail, velocity) |
| `lib/models/box_color.dart` | 5 `BoxColor` entries with `bg`/`dark`/`light` variants |
| `lib/models/popup.dart` | Short-lived "+1" / "✗" / warning popups |
| `lib/models/transition.dart` | Level-up splash (`level`, `startTime`) |

### Game loop (frame capped at 50 ms dt)

1. Expire popups > 800 ms old.
2. `LevelTransition` active → freeze gameplay for 2400 ms, then `setupLevel`.
3. Stochastic checks trigger maintenance (direction reversal) and resize on random belts.
4. `_spawnBoxes` — places box just off the entry end of a random belt.
5. `_moveBoxes` — advances non-dragged boxes; boxes reaching the gate are scored.
6. `_checkLevelUp` — `pointsForLevel(lvl) = Σ(6 + i*4)`.

### Drag rules

- Drop only onto source belt or adjacent one (`|targetId − sourceId| ≤ 1`).
- MAINTENANCE belts reject drops; box snaps back.
- Occupied slot: nudge up to 20 × 10 px against travel direction for a free gap.
- `allowedTargets` drives green dashed glow (reachable) / red tint (forbidden) in painter.

### Conveyor states

Belt can be `maintenance` (reversed, striped, boxes frozen) or `resizing` (height animating via `_easeInOut`). Always call `getCurrentHeight(conv, now)` — never read `conv.height` directly during resize.

### Rendering

`shouldRepaint` returns `true` unconditionally (rebuilds gated by `ChangeNotifier`). Pure `Canvas` calls — no image assets or external fonts.

## Linter

`analysis_options.yaml` extends `flutter_lints`; enables `prefer_const_constructors`, `prefer_const_literals_to_create_immutables`; disables `avoid_print`.
