import 'dart:ui';
import 'box_color.dart';

/// Visual transform produced by an active [ThrowAnim]. Computing it in
/// the controller (via `throwPose`) keeps the painter agnostic to the
/// throw timeline — it just consumes scale / rotation / lift values.
class ThrowPose {
  final double scaleX;
  final double scaleY;
  final double rotation; // degrees
  final double liftY; // negative = up
  final double opacity;

  const ThrowPose({
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.rotation = 0,
    this.liftY = 0,
    this.opacity = 1.0,
  });
}

/// Animation data for a box that's been released and is flying to a
/// target belt slot. Three back-to-back phases:
///
/// * **Flight** — box position interpolates from start → end with eased
///   spin / scale, driven by [GameController._updateThrows].
/// * **Squash** — box freezes at the landing spot; painter draws an
///   impact stretch (wide+short) easing back toward 1.0.
/// * **Settle** — small overshoot bounce so the landing reads as solid.
///
/// Once `now - startTime` exceeds [totalDuration] the controller clears
/// `box.throwAnim` and the box rejoins normal belt movement.
class ThrowAnim {
  double startTime;
  double startX;
  double startY;
  double endX;
  double endY;
  final int targetConvId;
  final double flightDuration;
  final double squashDuration;
  final double settleDuration;

  ThrowAnim({
    required this.startTime,
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.targetConvId,
    this.flightDuration = 220,
    this.squashDuration = 80,
    this.settleDuration = 100,
  });

  double get totalDuration =>
      flightDuration + squashDuration + settleDuration;
}

/// A single box sliding along a conveyor belt.
class Box {
  final int id;
  double x;
  double y;
  int conveyorId;
  BoxColor color;
  double size;
  bool onConveyor;
  bool entering;

  // Drag state
  int? sourceConveyorId;
  double? dragStartTime;
  double? vx;
  double? vy;
  List<Offset>? trail;

  // Set on release. While non-null the box is locked out of belt movement
  // and gesture pickup until the animation completes.
  ThrowAnim? throwAnim;

  // Which fixed slot (0 = entry end, N-1 = exit end) this box occupies.
  // null  → entering (moving toward slot 0 from outside the belt)
  // 9999  → exiting  (past last slot, moving freely to the gate)
  int? slotIndex;

  Box({
    required this.id,
    required this.x,
    required this.y,
    required this.conveyorId,
    required this.color,
    required this.size,
    this.onConveyor = true,
    this.entering = true,
    this.slotIndex,
    this.sourceConveyorId,
    this.dragStartTime,
    this.vx,
    this.vy,
    this.trail,
    this.throwAnim,
  });
}
