import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:math';
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
  final int? selectionOriginRow; // 選択開始位置Row
  final int? selectionOriginCol; // 選択開始位置Col

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
    required this.selectionOriginRow,
    required this.selectionOriginCol,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // --------------------------------------------------------
    // 0. 選択範囲の背景描画 (テキストより先に描く)
    // --------------------------------------------------------
    if (selectionOriginRow != null && selectionOriginCol != null) {
      final paintSelection = Paint()
        ..color = Colors.blue.withValues(alpha: 0.3);

      // 矩形の範囲を計算
      // 行: 開始行と現在のカーソル行の小さい方～大きい方
      int startRow = min(selectionOriginRow!, cursorRow);
      int endRow = max(selectionOriginRow!, cursorRow);

      //  「見た目のX座標 (VisualX)」を計算して基準にする
      //   これにより、行の中身に関わらず、垂直に真っ直ぐな矩形を描く

      // 開始地点の VisualX を計算
      String originLine = "";
      if (selectionOriginRow! < lines.length) {
        originLine = lines[selectionOriginRow!];
      }
      String originText = "";
      if (selectionOriginCol! <= originLine.length) {
        originText = originLine.substring(0, selectionOriginCol!);
      } else {
        originText =
            originLine + (' ' * (selectionOriginCol! - originLine.length));
      }
      double originVisualX = TextUtils.calcTextWidth(originText) * charWidth;

      // 現在カーソルの VisualX を計算
      String cursorLine = "";
      if (cursorRow < lines.length) {
        cursorLine = lines[cursorRow];
      }
      String cursorText = "";
      if (cursorCol <= cursorLine.length) {
        cursorText = cursorLine.substring(0, cursorCol);
      } else {
        cursorText = cursorLine + (' ' * (cursorCol - cursorLine.length));
      }
      double cursorVisualX = TextUtils.calcTextWidth(cursorText) * charWidth;

      // 矩形の左端(Left)と右端(Right)を決定
      double rectLeft = min(originVisualX, cursorVisualX);
      double rectRight = max(originVisualX, cursorVisualX);

      // 3. 行ごとに矩形を描画
      for (int i = startRow; i <= endRow; i++) {
        double top = i * lineHeight;
        double bottom = top + lineHeight;

        // VisualXを直接指定して描画するので、行の中身（全角半角）に影響されない
        canvas.drawRect(
          Rect.fromLTRB(rectLeft, top, rectRight, bottom),
          paintSelection,
        );
      }
    }

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
