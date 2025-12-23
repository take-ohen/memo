import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'text_utils.dart'; // ★作成した便利関数をインポート
import 'search_result.dart'; // ★検索結果クラスをインポート

class MemoPainter extends CustomPainter {
  final List<String> lines;
  final double charWidth;
  final double charHeight;
  final double lineHeight;
  final bool showGrid;
  final bool isOverwriteMode; // 上書きモード
  final bool isRectangularSelection; // 矩形選択フラグ
  final int cursorRow;
  final int cursorCol;
  final TextStyle textStyle; // TextPainter に渡すスタイル
  final String composingText; // 未確定文字
  final int? selectionOriginRow; // 選択開始位置Row
  final int? selectionOriginCol; // 選択開始位置Col
  final bool showCursor;
  final List<SearchResult> searchResults; // ★検索結果リスト
  final int currentSearchIndex; // ★現在の検索結果インデックス

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
    this.selectionOriginRow,
    this.selectionOriginCol,
    required this.showCursor,
    this.isRectangularSelection = false, // 矩形選択 defalutはfalse
    this.searchResults = const [], // ★初期値は空
    this.currentSearchIndex = -1, // ★初期値は-1
  });

  @override
  void paint(Canvas canvas, Size size) {
    // --------------------------------------------------------
    // 選択範囲の背景描画 (テキストより先に描く)
    // --------------------------------------------------------
    if (selectionOriginRow != null && selectionOriginCol != null) {
      if (isRectangularSelection) {
        // 矩形選択の描画処理（カーソル描画より前に行う)
        _drawRectangularSelection(canvas);
      } else {
        // [新規] 通常選択の描画処理 (Shiftのみ)
        _drawNormalSelection(canvas);
      }
    }

    // --------------------------------------------------------
    // 0.5 検索結果のハイライト描画 (テキストより先に描く)
    // --------------------------------------------------------
    if (searchResults.isNotEmpty) {
      _drawSearchResults(canvas);
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
    // 2. カーソル位置のX座標計算 (全角対応・虚空対応)
    // --------------------------------------------------------
    double cursorPixelX = _calculateVisualX(cursorRow, cursorCol);
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
    }

    // --------------------------------------------------------
    // 4. カーソルの描画
    // -------------------------------------------------------
    if (showCursor) {
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
    }
    // --------------------------------------------------------
    // 5. グリッド線 (showGrid時)
    // --------------------------------------------------------
    if (showGrid) {
      final gridpaint = Paint()
        ..color = Colors.grey.withValues(alpha: 0.3)
        ..strokeWidth = 1.0;

      // 縦線
      for (double x = 0; x < size.width; x += charWidth) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridpaint);
      }
      // 横線
      for (double y = 0; y < size.height; y += lineHeight) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridpaint);
      }
    }
  }

  // ★検索結果のハイライト描画ロジック
  void _drawSearchResults(Canvas canvas) {
    final paintHighlight = Paint()
      ..color = Colors.yellow.withOpacity(0.4); // 通常のヒット色
    final paintCurrent = Paint()
      ..color = Colors.orange.withOpacity(0.6); // 現在選択中のヒット色

    for (int i = 0; i < searchResults.length; i++) {
      final result = searchResults[i];

      // 行が存在しない場合はスキップ
      if (result.lineIndex >= lines.length) continue;

      String line = lines[result.lineIndex];

      // 範囲外ガード
      if (result.startCol >= line.length) continue;

      int endCol = min(result.startCol + result.length, line.length);

      String preText = line.substring(0, result.startCol);
      String matchText = line.substring(result.startCol, endCol);

      double startX = TextUtils.calcTextWidth(preText) * charWidth;
      double width = TextUtils.calcTextWidth(matchText) * charWidth;
      double top = result.lineIndex * lineHeight;

      canvas.drawRect(
        Rect.fromLTWH(startX, top, width, lineHeight),
        (i == currentSearchIndex) ? paintCurrent : paintHighlight,
      );
    }
  }

  // 矩形選択のロジック (VisualX基準)
  void _drawRectangularSelection(Canvas canvas) {
    final paint = Paint()
      ..color = Colors.green.withValues(alpha: 0.3); // 矩形は色を変えると分かりやすい

    int startRow = min(selectionOriginRow!, cursorRow);
    int endRow = max(selectionOriginRow!, cursorRow);

    // 始点と終点の「見た目のX座標」を計算
    double originVX = _calculateVisualX(
      selectionOriginRow!,
      selectionOriginCol!,
    );
    double cursorVX = _calculateVisualX(cursorRow, cursorCol);

    double left = min(originVX, cursorVX);
    double right = max(originVX, cursorVX);

    // 行ごとの描画 (矩形なのでX座標は固定)
    for (int i = startRow; i <= endRow; i++) {
      double top = i * lineHeight;
      double bottom = top + lineHeight;

      canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), paint);
    }
  }

  // 通常選択の描画ロジック（行またぎ対応)
  void _drawNormalSelection(Canvas canvas) {
    final paint = Paint()..color = Colors.blue.withValues(alpha: 0.3); // 選択色

    // 1. 始点と終点を「上から下へ」の順序に整理する
    int startRow = selectionOriginRow!;
    int startCol = selectionOriginCol!;
    int endRow = cursorRow;
    int endCol = cursorCol;

    // 反転している場合は入れ替える
    if (startRow > endRow || (startRow == endRow && startCol > endCol)) {
      int t;
      t = startRow;
      startRow = endRow;
      endRow = t;
      t = startCol;
      startCol = endCol;
      endCol = t;
    }

    // 2. 行ごとに描画範囲を計算して塗りつぶす
    for (int i = startRow; i <= endRow; i++) {
      if (i >= lines.length) break;

      String line = lines[i];
      int lineLen = line.length;

      // この行における選択開始位置と終了位置
      // 開始行なら startCol、それ以外の行(中間行)なら 0
      int localStart = (i == startRow) ? startCol : 0;

      // 終了行なら endCol、それ以外の行(中間行・開始行)なら行末(lineLen)
      int localEnd = (i == endRow) ? endCol : lineLen;

      // ★【修正箇所】: インデックスが行の長さを超えないようにクランプする
      // カーソルが虚空にあっても、substring は文字数までで行う必要がある
      if (localStart > lineLen) localStart = lineLen;
      if (localEnd > lineLen) localEnd = lineLen;
      // 念のため負の値もガード
      if (localStart < 0) localStart = 0;
      if (localEnd < 0) localEnd = 0;

      // 部分文字列の取得 (クランプ済みなので落ちない)
      String preText = line.substring(0, localStart);
      String selText = line.substring(localStart, localEnd);

      // 幅の計算 (TextUtilsの実装に依存)
      double startX = TextUtils.calcTextWidth(preText).toDouble() * charWidth;
      double selWidth = TextUtils.calcTextWidth(selText).toDouble() * charWidth;

      // 行末を超えて選択されている場合（改行部分の描画）
      // 条件: 「この行が終了行ではない（次の行まで続く）」 または
      //      「終了行だがカーソルが行末より右（虚空）にある」
      bool isPastLineEnd = (i < endRow) || (i == endRow && endCol > lineLen);
      if (isPastLineEnd) {
        selWidth += charWidth / 2; // 改行分として少し幅を足す
      }

      // 描画座標の決定
      // 行の高さ (例: 24.0) や 左側のパディング (例: 40.0) はプロジェクト定数に合わせてください
      double top = i * lineHeight;
      double bottom = top + lineHeight;

      canvas.drawRect(
        Rect.fromLTRB(startX, top, startX + selWidth, bottom),
        paint,
      );
    }
  }

  // ★ヘルパー: 指定した行・列の VisualX (ピクセル) を計算
  // 虚空(行末より右)にある場合も、スペースで埋めたと仮定して計算する
  double _calculateVisualX(int row, int col) {
    String line = "";
    if (row < lines.length) {
      line = lines[row];
    }

    String textBefore = "";
    if (col <= line.length) {
      textBefore = line.substring(0, col);
    } else {
      // 虚空対応: 足りない分をスペースで埋める
      textBefore = line + (' ' * (col - line.length));
    }

    return TextUtils.calcTextWidth(textBefore) * charWidth;
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
        oldDelegate.selectionOriginRow != selectionOriginRow ||
        oldDelegate.selectionOriginCol != selectionOriginCol ||
        oldDelegate.isRectangularSelection != isRectangularSelection ||
        oldDelegate.composingText != composingText ||
        oldDelegate.searchResults != searchResults || // ★変更検知に追加
        oldDelegate.currentSearchIndex != currentSearchIndex; // ★変更検知に追加
  }
}

class LineNumberPainter extends CustomPainter {
  final int lineCount;
  final double lineHeight;
  final TextStyle textStyle;

  LineNumberPainter({
    required this.lineCount,
    required this.lineHeight,
    required this.textStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < lineCount; i++) {
      final textSpan = TextSpan(text: '${i + 1}', style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
      );
      textPainter.layout(minWidth: size.width);
      textPainter.paint(canvas, Offset(0, i * lineHeight));
    }
  }

  @override
  bool shouldRepaint(covariant LineNumberPainter oldDelegate) {
    return oldDelegate.lineCount != lineCount ||
        oldDelegate.lineHeight != lineHeight ||
        oldDelegate.textStyle != textStyle;
  }
}
