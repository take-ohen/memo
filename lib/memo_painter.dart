import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'text_utils.dart'; // ★作成した便利関数をインポート

class MemoPainter extends CustomPainter {
  final List<String> lines;
  final double charWidth;
  final double charHeight;
  final double lineHeight;
  final bool showGrid;
  final bool isOverwriteMode; // 上書きモード
  final int cursorRow;
  final int cursorCol;
  final TextStyle textStyle; // TextPainter に渡すスタイル
  final String composingText; // 未確定文字

  MemoPainter({
    required this.lines,
    required this.charWidth,
    required this.charHeight,
    required this.showGrid,
    required this.isOverwriteMode,
    required this.cursorRow,
    required this.cursorCol,
    required this.lineHeight,
    required this.textStyle,
    required this.composingText,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // --------------------------------------------------------
    // 1. テキスト（確定済み）の描画
    // --------------------------------------------------------
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];

      final textSpan = TextSpan(text: line, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(0, i * lineHeight));

      // 改行マークの描画
      // ★共通化した関数を使用
      int visualWidth = TextUtils.calcTextWidth(line);
      double lineEndX = visualWidth * charWidth;
      double lineY = i * lineHeight;

      //改行マーク用の薄い色
      final markStyle = TextStyle(
        color: Colors.grey.shade500,
        fontSize: textStyle.fontSize,
      );
      final markSpan = TextSpan(text: '↵', style: markStyle);
      final markPainter = TextPainter(
        text: markSpan,
        textDirection: TextDirection.ltr,
      );
      markPainter.layout();
      markPainter.paint(canvas, Offset(lineEndX + 2, lineY));
    }

    // --------------------------------------------------------
    // 2. カーソル位置のX座標計算 (全角対応)
    // --------------------------------------------------------
    double cursorPixelX = 0.0;

    String currentLineText = "";
    if (cursorRow < lines.length) {
      currentLineText = lines[cursorRow];
    }

    String textBeforeCursor = "";
    if (cursorCol <= currentLineText.length) {
      textBeforeCursor = currentLineText.substring(0, cursorCol);
    } else {
      int spacesNeeded = cursorCol - currentLineText.length;
      textBeforeCursor = currentLineText + (' ' * spacesNeeded);
    }

    // ★共通化した関数を使用
    int visualCursorX = TextUtils.calcTextWidth(textBeforeCursor);
    cursorPixelX = visualCursorX * charWidth;

    double cursorPixelY = cursorRow * lineHeight;

    // --------------------------------------------------------
    // 3. 未確定文字 (composingText) の描画
    // --------------------------------------------------------
    if (composingText.isNotEmpty) {
      final composingStyle = TextStyle(
        color: Colors.black,
        fontSize: textStyle.fontSize,
        fontFamily: textStyle.fontFamily,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.solid,
        decorationColor: Colors.blue,
        backgroundColor: Colors.white.withValues(alpha: 0.8),
      );

      final span = TextSpan(text: composingText, style: composingStyle);
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr);
      tp.layout();

      tp.paint(canvas, Offset(cursorPixelX, cursorPixelY));

      // 変換中カーソル位置調整用
      // ★共通化した関数を使用
      // int composingWidth = TextUtils.calcTextWidth(composingText);
      // cursorPixelX += composingWidth * charWidth;
    }

    // --------------------------------------------------------
    // 4. カーソルの描画
    // --------------------------------------------------------
    if (isOverwriteMode) {
      final cursorRect = Rect.fromLTWH(
        cursorPixelX,
        cursorPixelY,
        charWidth,
        lineHeight,
      );
      canvas.drawRect(
        cursorRect,
        Paint()..color = Colors.blue.withValues(alpha: 0.5),
      );
    } else {
      final cursorPaint = Paint()
        ..color = Colors.black
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.square;

      canvas.drawLine(
        Offset(cursorPixelX, cursorPixelY),
        Offset(cursorPixelX, cursorPixelY + lineHeight),
        cursorPaint,
      );
    }
    // --------------------------------------------------------
    // 5. グリッド線 (showGrid時)
    // --------------------------------------------------------
    if (showGrid) {
      final gridpaint = Paint()
        ..color = Colors.grey.withValues(alpha: 0.3)
        ..strokeWidth = 1.0;

      for (double x = 0; x < size.width; x += charWidth) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridpaint);
      }

      for (double y = 0; y < size.height; y += lineHeight) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridpaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant MemoPainter oldDelegate) {
    return listEquals(oldDelegate.lines, lines) ||
        oldDelegate.charWidth != charWidth ||
        oldDelegate.charHeight != charHeight ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.cursorRow != cursorRow ||
        oldDelegate.cursorCol != cursorCol ||
        oldDelegate.textStyle != textStyle ||
        oldDelegate.composingText != composingText;
  }
}
