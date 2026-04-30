import 'box_color.dart';

class FallingBox {
  double x;
  double y;
  double vy;
  final double size;
  final BoxColor color;
  final double startY;
  final double disappearY;

  FallingBox({
    required this.x,
    required this.y,
    required this.vy,
    required this.size,
    required this.color,
    required this.startY,
    required this.disappearY,
  });
}
