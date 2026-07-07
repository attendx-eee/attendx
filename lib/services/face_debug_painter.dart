import 'package:flutter/material.dart';

class FaceDebugPainter extends CustomPainter {
  final Rect? faceRect;
  final Rect? guideRect;
  final Color borderColor;

  const FaceDebugPainter({
    super.repaint,
    required this.faceRect,
    required this.guideRect,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double strokeScale = (size.shortestSide / 400).clamp(2.0, 5.0);

    // Guide rect paint
    final guidePaint = Paint()
      ..color = Colors.blueAccent.withValues(alpha: 0.6)
      ..strokeWidth = strokeScale
      ..style = PaintingStyle.stroke;

    // Face rect paint
    final facePaint = Paint()
      ..color = borderColor
      ..strokeWidth = strokeScale
      ..style = PaintingStyle.stroke;

    // Draw guide rect
    if (guideRect != null) {
      canvas.drawRect(guideRect!, guidePaint);

      // Crosshair at guide center
      final center = guideRect!.center;
      canvas.drawLine(
        Offset(center.dx - 20, center.dy),
        Offset(center.dx + 20, center.dy),
        guidePaint,
      );
      canvas.drawLine(
        Offset(center.dx, center.dy - 20),
        Offset(center.dx, center.dy + 20),
        guidePaint,
      );
    }

    // Draw face rect
    if (faceRect != null) {
      canvas.drawRect(faceRect!, facePaint);
    }
  }

  @override
  bool shouldRepaint(covariant FaceDebugPainter oldDelegate) {
    return oldDelegate.faceRect != faceRect ||
        oldDelegate.guideRect != guideRect ||
        oldDelegate.borderColor != borderColor;
  }
}
