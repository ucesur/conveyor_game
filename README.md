# Conveyor Match — Flutter

A Flutter port of the React/TypeScript "Conveyor Match" game. Drag colored boxes between neighboring conveyor belts so each box reaches the gate matching its color.

## Gameplay

- Boxes spawn on conveyor belts and slide toward a colored gate at the end.
- Match the **box color** to the **gate color** to score a point.
- You can drag a box to the **immediately adjacent** conveyor only (one lane hop).
- Wrong color through a gate costs a life. You have 3 lives.
- Belts occasionally enter **MAINTENANCE** (reversing direction) and **RESIZE** (changing length) to keep things chaotic.
- Each level has more belts, more colors, and faster speeds.

## Running the project

This package contains only the Dart/Flutter source. To run it, create a Flutter project shell and drop these files in:

```bash
# 1. Create a new Flutter app
flutter create conveyor_match_app
cd conveyor_match_app

# 2. Replace the default sources with the files from this archive:
#    - lib/           → lib/
#    - pubspec.yaml   → pubspec.yaml
#    - analysis_options.yaml → analysis_options.yaml

# 3. Fetch dependencies and run
flutter pub get
flutter run
```

The game renders onto a fixed 360×600 virtual canvas and scales to fit any device viewport, matching the aspect ratio of the original web game.

## Project layout

```
lib/
├── main.dart                    # App entry
├── models/
│   ├── box.dart                 # A sliding/draggable box
│   ├── box_color.dart           # Color palette (red/blue/green/yellow/purple)
│   ├── conveyor.dart            # A single conveyor belt
│   ├── popup.dart               # Floating "+1" / "✗" popups
│   └── transition.dart          # Level-up splash state
├── game/
│   └── game_controller.dart     # Game state + update loop + input handling
├── widgets/
│   └── game_painter.dart        # CustomPainter that draws the whole scene
└── screens/
    └── game_screen.dart         # Root screen: Ticker + gesture listener + overlays
```

## Architecture notes

- **Game loop**: driven by a `Ticker` in `GameScreen`, which calls `GameController.update(now)` every frame. The controller is a `ChangeNotifier`, and a `CustomPaint` rebound to it repaints on every notification.
- **Input**: the canvas is scaled with `FittedBox`-like logic, so pointer coordinates are converted back into the 360×600 game space before being handed to the controller.
- **Rendering**: one `CustomPainter` draws background, HUD, conveyors, boxes, popups, and the level transition. Menu and game-over overlays are regular Flutter widgets stacked on top.

## Differences from the React version

- Uses `Canvas` drawing instead of SVG — visually equivalent, with a hand-rolled diagonal-stripe pattern for the maintenance overlay and a radial-gradient glow for the level splash.
- Drag animation uses canvas transforms rather than SVG `transform` attributes.
- State is held in a plain `ChangeNotifier` rather than React `useState`/refs.
