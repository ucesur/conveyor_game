import 'box_color.dart';

enum ConveyorDirection { up, down }

/// Represents a single conveyor belt in the game.
class Conveyor {
  final int id;
  final BoxColor color;
  double x;
  final double y;
  final double width;
  double height;
  double speed;
  ConveyorDirection direction;

  // Maintenance state (when the belt temporarily stops to reverse direction)
  bool maintenance;
  double maintenanceEnd;
  ConveyorDirection? pendingDirection;

  // Resize state (when the belt smoothly changes height)
  bool resizing;
  double resizeStart;
  double fromHeight;
  double toHeight;

  Conveyor({
    required this.id,
    required this.color,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.speed,
    required this.direction,
    this.maintenance = false,
    this.maintenanceEnd = 0,
    this.pendingDirection,
    this.resizing = false,
    this.resizeStart = 0,
    double? fromHeight,
    double? toHeight,
  })  : fromHeight = fromHeight ?? height,
        toHeight = toHeight ?? height;
}
