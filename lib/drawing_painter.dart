import 'dart:ui';
import 'package:flutter/material.dart';
import 'drawing_data.dart';
import 'text_utils.dart';

class DrawingPainter extends CustomPainter {
  final List<List<Offset>> strokes; // 描画中のストローク
  final List<String> lines; // 座標復元用
  final double charWidth;
  final double lineHeight;

  DrawingPainter({
    required this.strokes,
    required this.lines,
    required this.charWidth,
    required this.lineHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
          .withOpacity(0.8) // 仮の色（赤）
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // 描画中ストロークの描画 (最前面)
    paint.color = Colors.red.withOpacity(0.8);
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;

      if (stroke.length < 2) {
        // 点の描画
        canvas.drawPoints(PointMode.points, stroke, paint);
        continue;
      }

      final path = Path();
      path.moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant DrawingPainter oldDelegate) {
    // 簡易的に常に再描画（データ比較はコストがかかるため）
    // 本来はリストの長さやリビジョン番号などで比較すべき
    return true;
  }
}
