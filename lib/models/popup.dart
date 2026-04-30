import 'dart:ui';

/// A floating popup that animates upward and fades — used for "+1", "✗", etc.
class Popup {
  final int id;
  final double x;
  final double y;
  final String text;
  final Color color;
  final double size;
  double createdAt;

  Popup({
    required this.id,
    required this.x,
    required this.y,
    required this.text,
    required this.color,
    required this.createdAt,
    this.size = 22,
  });
}
