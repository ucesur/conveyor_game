import 'package:flutter/material.dart';

/// Represents a color used for boxes and conveyors.
/// Each color has three shades: main (bg), light, and dark.
class BoxColor {
  final String id;
  final Color bg;
  final Color light;
  final Color dark;

  const BoxColor({
    required this.id,
    required this.bg,
    required this.light,
    required this.dark,
  });

  static const List<BoxColor> all = [
    BoxColor(
      id: 'red',
      bg: Color(0xFFEF4444),
      light: Color(0xFFFCA5A5),
      dark: Color(0xFF991B1B),
    ),
    BoxColor(
      id: 'blue',
      bg: Color(0xFF3B82F6),
      light: Color(0xFF93C5FD),
      dark: Color(0xFF1E40AF),
    ),
    BoxColor(
      id: 'green',
      bg: Color(0xFF22C55E),
      light: Color(0xFF86EFAC),
      dark: Color(0xFF15803D),
    ),
    BoxColor(
      id: 'yellow',
      bg: Color(0xFFEAB308),
      light: Color(0xFFFDE047),
      dark: Color(0xFF854D0E),
    ),
    BoxColor(
      id: 'purple',
      bg: Color(0xFFA855F7),
      light: Color(0xFFD8B4FE),
      dark: Color(0xFF6B21A8),
    ),
  ];
}
