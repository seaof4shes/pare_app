import 'package:flutter/material.dart';

/// Soft concentric rings used as a background accent (splash + login header).
class RingsPainter extends CustomPainter {
  const RingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final base = size.shortestSide / 2;

    const rings = [(0.98, 0.08), (0.71, 0.10), (0.44, 0.12)];

    for (final (factor, alpha) in rings) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: alpha);

      canvas.drawCircle(center, base * factor, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
