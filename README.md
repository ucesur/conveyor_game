# Conveyor Match — Flutter

A Flutter puzzle game where you drag and fling colored boxes between neighboring conveyor belts so each box reaches the gate matching its color.

## Gameplay

- Boxes spawn on conveyor belts and slide toward a colored gate at the far end.
- Match the **box color** to the **gate color** to score a point.
- You can drag or swipe/fling a box to the **immediately adjacent** conveyor only (one lane hop).
- Wrong color through a gate costs a life. You start with 4 lives.
- Score combos by sending consecutive boxes of the same color through their gate.
- Belts occasionally enter **MAINTENANCE** (direction reversal, drops rejected) and **RESIZE** (height animates) to keep things chaotic.
- Each level adds more belts, more colors, and faster speeds. Up to 5 belts, up to 5 colors.

## Running the project

```bash
flutter pub get
flutter run                        # connected device
flutter run -d chrome              # web
flutter run -d windows             # desktop
flutter build apk                  # Android release
flutter build web                  # web release
```

The game locks to portrait orientation and renders onto a fixed 360 × (screen-aspect) virtual canvas, letterboxed via `AspectRatio` + `ClipRRect`.

## Project layout

```
lib/
├── main.dart                    # App entry — forces portrait, dark theme
├── models/
│   ├── box.dart                 # Sliding/draggable box + throw animation state
│   ├── box_color.dart           # 5-color palette (bg / dark / light variants)
│   ├── conveyor.dart            # Belt state (direction, height, maintenance, resize)
│   ├── falling_box.dart         # Short-lived box that falls into the gate on score
│   ├── particle.dart            # Dust particle spawned on box landing
│   ├── popup.dart               # Floating "+1" / "✗" / "⚠" popups
│   └── transition.dart          # Level-up splash state
├── game/
│   └── game_controller.dart     # All game state + frame update loop + input handling
├── widgets/
│   └── game_painter.dart        # Pure CustomPainter — reads controller, never writes
└── screens/
    └── game_screen.dart         # Ticker owner, pointer-event bridge, overlays
```

## Architecture

**Data flow:** `Ticker` → `GameController.update(ms)` → `notifyListeners()` → `AnimatedBuilder` → `GamePainter.paint()`

`GameController` is the single source of truth — a `ChangeNotifier` that owns all game state. `GamePainter` is a pure read-only `CustomPainter`; it never writes back to the controller.

Pointer events land in widget pixels; `GameScreen` converts them to the 360-wide game coordinate space before passing to the controller.

### Game loop (frame capped at 50 ms dt)

1. Expire popups older than 800 ms.
2. Stochastic checks trigger maintenance (direction reversal) and resize on random idle belts.
3. End any completed maintenance / resize animations.
4. Advance throw animations; commit boxes to target belt on landing (spawns dust particles).
5. Advance falling-box and particle effects.
6. `_spawnBoxes` — places a new box just off the entry end of each belt that has a free entry slot.
7. `_moveBoxes` — advances non-dragged boxes; boxes reaching the gate are scored or penalise a life.
8. `_checkLevelUp` — level threshold is `Σ(6 + i×4)` for i in 1..level-1.

### Drag / fling rules

- **Drag-and-drop**: release over a belt to land the box in the nearest free slot.
- **Swipe/fling**: a fast horizontal flick at release auto-targets the adjacent belt in the swipe direction (averaged over the last 3 trail points to handle natural deceleration).
- Drop target must be the source belt or its immediate visual neighbor — no skipping lanes.
- MAINTENANCE belts reject all drops; box snaps back to source.
- If the closest slot is occupied, search outward up to `nSlots` candidates before giving up.

### Conveyor states

A belt can be `maintenance` (reversed, striped overlay, drops rejected) or `resizing` (height animating via cubic ease-in-out). Always call `getCurrentHeight(conv, now)` — never read `conv.height` directly during a resize.

### Scoring

- Correct gate: `+1` base; consecutive same-color hits multiply up to `×4` (combo).
- Wrong gate: `−1 life`, screen shake, combo resets.
- Game over at 0 lives; high score tracked in memory for the session.

### Rendering

`shouldRepaint` returns `true` unconditionally (repaints gated by `ChangeNotifier`). Pure `Canvas` calls — no image assets or external fonts. Diagonal-stripe maintenance overlay, radial-gradient gate glow, cubic easing on resize, and dust-particle burst on box landing are all procedural.
