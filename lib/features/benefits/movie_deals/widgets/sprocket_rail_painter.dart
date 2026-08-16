// lib/features/benefits/movie_deals/widgets/sprocket_rail_painter.dart
import 'package:flutter/material.dart';

/// A film-strip sprocket rail down one edge of a result frame — the same
/// hand-painted-texture technique as _CircuitPainter (card_detail_screen.dart)
/// and _RingPainter, rather than an image asset or a decorative border.
/// Hole count and spacing are computed from the actual painted height so the
/// rail always looks correctly perforated regardless of the frame's content
/// height, instead of a fixed hole count that would look sparse on a tall
/// frame or crowded on a short one.
class SprocketRailPainter extends CustomPainter {
  const SprocketRailPainter({required this.holeColor});

  final Color holeColor;

  static const double _holeSize = 6;
  static const double _holeSpacing = 20;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = holeColor
      ..style = PaintingStyle.fill;

    final holeCount = (size.height / _holeSpacing).floor().clamp(2, 100);
    final totalHolesHeight = holeCount * _holeSpacing;
    final topOffset = (size.height - totalHolesHeight) / 2 + _holeSpacing / 2;

    for (var i = 0; i < holeCount; i++) {
      final center = Offset(size.width / 2, topOffset + i * _holeSpacing);
      final rect = Rect.fromCenter(center: center, width: _holeSize, height: _holeSize);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
    }
  }

  @override
  bool shouldRepaint(SprocketRailPainter oldDelegate) => oldDelegate.holeColor != holeColor;
}
