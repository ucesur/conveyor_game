# CLAUDE.md

## Commands
`flutter pub get` · `flutter run [-d chrome|windows]` · `flutter test` · `flutter analyze` · `flutter build apk|web`

> `test/widget_test.dart` has deleted `MyApp` — ignore or replace with `ConveyorMatchApp` smoke test.

## Architecture

**Canvas:** 360×600, letterboxed via `AspectRatio`+`ClipRRect`.  
**Data flow:** `Ticker` → `GameController.update(ms)` → `notifyListeners()` → `AnimatedBuilder` → `GamePainter.paint()`  
**Coords:** pointer events in widget px; `GameScreen._toGameCoords()` converts via `_computeScale` + letterbox offsets.

### Controller — `lib/game/`

`GameController` (`game_controller.dart`) holds all state and calls system methods. Logic is split into **`part of`** extension files in `systems/` — same library, full private access, no circular imports.

| File | System |
|---|---|
| `game_controller.dart` | State fields, constants, `update()`, `setupLevel`, state transitions, shared utils |
| `systems/belt_system.dart` | Maintenance reversals, resize, freeze |
| `systems/box_system.dart` | Slot helpers, spawn, move, gate scoring |
| `systems/drag_system.dart` | Drag start/move/end, throw animation, `throwPose` |
| `systems/particle_system.dart` | Dust, explosion, ice particles, belt explosion |
| `systems/combo_system.dart` | Combo area, special box spawning, bomb/icy triggers |
| `systems/level_system.dart` | Level-up, belt addition |

### Painter — `lib/widgets/`

`GamePainter` (`game_painter.dart`) is a thin coordinator. Paint singletons are library-level top-level variables. Layers are **`part of`** extensions.

| File | Layer |
|---|---|
| `game_painter.dart` | `paint()` orchestrator, shared utils (`_drawText`, `_drawSprite`) |
| `painters/hud_layer.dart` | Background, HUD bar, lives, progress |
| `painters/belt_layer.dart` | Conveyor body, overlays, gate, explosion wave |
| `painters/combo_layer.dart` | Combo recipe panel |
| `painters/box_layer.dart` | Boxes, trail, falling boxes |
| `painters/effect_layer.dart` | Particles, popups |

### Extensibility hooks

| File | Purpose |
|---|---|
| `game/specials/special_effect.dart` | `abstract SpecialEffect` + `SpecialRegistry` — add new special types without touching core |
| `game/stages/game_stage.dart` | `abstract GameStage` + `NormalStage` — override spawn, scoring, or update for boss stages |

**Adding a new special type:**
1. Add entry to `SpecialType` enum
2. Create `lib/game/specials/my_effect.dart` implementing `SpecialEffect`
3. Call `SpecialRegistry.register(MyEffect())` at app startup

**Adding a boss stage:**
1. Create `lib/game/stages/boss_stage.dart` extending `GameStage`
2. Set `controller.currentStage = BossStage()` before `setupLevel`

### Models — `lib/models/`
`Conveyor` · `Box` · `BoxColor` · `Popup` · `Particle` · `FallingBox` · `BeltExplosion` · `ComboArea` · `SpecialType` · `GameAssets`

### Game loop (dt capped 50 ms)
1. Expire popups >800 ms. 2. Resume: shift timestamps. 3. Belt events (reversals, resize, freeze). 4. Throw animations. 5. Particles + falling boxes. 6. Spawn + move boxes (gate → score). 7. Level-up check. 8. Combo reset. 9. Belt explosion cleanup. 10. `currentStage.onUpdate`.

### Drag rules
Drop onto source or adjacent belt only (`|targetId−sourceId|≤1`). MAINTENANCE rejects. Occupied slot → nudge. `allowedTargets` → green glow / red tint.

### Conveyor states
`maintenance` (reversed, striped, frozen boxes) · `resizing` (height animating) · `frozen` (icy). Always `getCurrentHeight(conv, now)` — never `conv.height` directly.

### Rendering
`shouldRepaint` always `true` (gated by `ChangeNotifier`). Pure `Canvas`. Library-level paint singletons (`_p`, `_sp`, etc.) shared across all painter layers.

## Linter
`analysis_options.yaml`: extends `flutter_lints`; enables `prefer_const_constructors`, `prefer_const_literals_to_create_immutables`; disables `avoid_print`.
