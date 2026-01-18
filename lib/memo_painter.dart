import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui';
import 'dart:ui' as ui; // ui.Image用
import 'text_utils.dart'; // ★作成した便利関数をインポート
import 'search_result.dart'; // ★検索結果クラスをインポート
import 'drawing_data.dart'; // ★図形データクラスをインポート

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
  final Color gridColor; // ★グリッド色
  final List<DrawingObject> drawings; // ★図形リスト
  final String? selectedDrawingId; // ★選択中の図形ID
  final int shapePaddingX; // ★図形パディングX (文字数)
  final double shapePaddingY; // ★図形パディングY (行高さ比率)
  final bool showDrawings; // ★図形表示フラグ
  final bool showAllHandles; // ★全ハンドル表示フラグ
  final String? highlightedDrawingId; // ★ハイライト中の図形ID
  final DrawingType? highlightedDrawingType; // ★ハイライト中の図形タイプ (フィルタ用)
  final Rect? areaSelectionRect; // ★範囲選択中の矩形
  final int editorBackgroundColor; // ★エディタ背景色 (補色計算用)
  final Map<String, ui.Image> imageCache; // ★画像キャッシュ

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
    required this.gridColor,
    this.drawings = const [], // ★初期値は空
    this.selectedDrawingId, // ★初期値はnull
    required this.shapePaddingX,
    required this.shapePaddingY,
    required this.showDrawings,
    required this.showAllHandles,
    this.highlightedDrawingId,
    this.highlightedDrawingType,
    this.areaSelectionRect,
    required this.editorBackgroundColor,
    this.imageCache = const {},
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
    // 0.6 グリッド線 (showGrid時) - テキストの下に描画
    // --------------------------------------------------------
    if (showGrid) {
      final gridpaint = Paint()
        ..color = gridColor
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
    // 5. 図形の描画 (最前面)
    // --------------------------------------------------------
    if (showDrawings) {
      _drawDrawings(canvas);
    }

    // --------------------------------------------------------
    // 6. 範囲選択ラバーバンドの描画 (最前面)
    // --------------------------------------------------------
    if (areaSelectionRect != null) {
      final paint = Paint()
        ..color = Colors.blueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      // 破線で描画
      final path = Path()..addRect(areaSelectionRect!);
      final dashedPath = _createDashedPath(path, 4, 4);
      canvas.drawPath(dashedPath, paint);

      // 薄い塗りつぶし
      canvas.drawRect(
        areaSelectionRect!,
        Paint()..color = Colors.blueAccent.withOpacity(0.1),
      );
    }
  }

  // ★検索結果のハイライト描画ロジック
  void _drawSearchResults(Canvas canvas) {
    final paintHighlight = Paint()
      ..color = Colors.yellow.withValues(alpha: 0.4); // 通常のヒット色
    final paintCurrent = Paint()
      ..color = Colors.orange.withValues(alpha: 0.6); // 現在選択中のヒット色

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

  // ★図形描画ロジック
  void _drawDrawings(Canvas canvas) {
    for (final drawing in drawings) {
      final paint = Paint()
        ..color = drawing.color
        ..strokeWidth = drawing.strokeWidth
        ..style = PaintingStyle.stroke;

      // AnchorPoint -> Offset 変換
      final List<Offset> points = drawing.points
          .map((p) => _resolveAnchor(p))
          .toList();

      if (points.isEmpty) continue;

      // パス生成
      Path path = Path();

      // 矢印がある場合の線の短縮量計算
      double arrowShortenLen = 0.0;
      if (drawing.type == DrawingType.line ||
          drawing.type == DrawingType.elbow) {
        double baseWidth = paint.strokeWidth;
        if (drawing.lineStyle == LineStyle.doubleLine) {
          baseWidth *= 3.0;
        }
        double arrowSize = max(12.0, baseWidth * 3.0);
        // 矢印の高さ分(cos30°)だけ短縮。
        arrowShortenLen = (arrowSize * cos(pi / 6));
        if (arrowShortenLen < 0) arrowShortenLen = 0;
      }

      // 図形タイプごとの描画
      switch (drawing.type) {
        case DrawingType.line:
          if (points.length >= 2) {
            Offset p1 = points[0];
            Offset p2 = points[1];

            // 矢印がある場合、線を短くする
            if (drawing.hasArrowStart) {
              p1 = _shortenPoint(p1, p2, arrowShortenLen);
            }
            if (drawing.hasArrowEnd) {
              p2 = _shortenPoint(p2, p1, arrowShortenLen);
            }

            path.moveTo(p1.dx, p1.dy);
            path.lineTo(p2.dx, p2.dy);
          }
          break;
        case DrawingType.elbow: // L型線
          if (points.length >= 2) {
            final p1 = points[0];
            final p2 = points[1];
            // 属性に基づいて角を計算
            // UpperRoute: Y座標が小さい方を通る -> min(y1, y2)
            // LowerRoute: Y座標が大きい方を通る -> max(y1, y2)
            final double cornerY = drawing.isUpperRoute ? min(p1.dy, p2.dy) : max(p1.dy, p2.dy);
            // 角のX座標は、角のY座標と同じYを持つ方の点のX座標ではない方...
            // つまり、cornerY == p1.dy なら、まずは横移動なので cornerX = p2.dx
            final double cornerX = (cornerY == p1.dy) ? p2.dx : p1.dx;

            final corner = Offset(cornerX, cornerY);
            Offset drawP1 = p1;
            Offset drawP2 = p2;

            // 矢印がある場合、線を短くする
            if (drawing.hasArrowStart) {
              drawP1 = _shortenPoint(p1, corner, arrowShortenLen);
            }
            if (drawing.hasArrowEnd) {
              drawP2 = _shortenPoint(p2, corner, arrowShortenLen);
            }

            path.moveTo(drawP1.dx, drawP1.dy);
            path.lineTo(cornerX, cornerY);
            path.lineTo(drawP2.dx, drawP2.dy);
          }
          break;
        case DrawingType.rectangle:
          if (points.length >= 2) {
            final rect = Rect.fromPoints(points[0], points[1]);
            path.addRect(rect);
          }
          break;
        case DrawingType.oval:
          if (points.length >= 2) {
            final rect = Rect.fromPoints(points[0], points[1]);
            path.addOval(rect);
          }
          break;
        case DrawingType.roundedRectangle:
          if (points.length >= 2) {
            final rect = Rect.fromPoints(points[0], points[1]);
            path.addRRect(
              RRect.fromRectAndRadius(rect, const Radius.circular(8)),
            );
          }
          break;
        case DrawingType.burst:
          if (points.length >= 2) {
            final rect = Rect.fromPoints(points[0], points[1]);
            final center = rect.center;
            final double halfW = rect.width / 2;
            final double halfH = rect.height / 2;
            const int spikes = 16;
            const double innerRatio = 0.7;

            for (int i = 0; i < spikes * 2; i++) {
              final double angle = (i * pi) / spikes - (pi / 2); // 上から開始
              final double scale = (i % 2 == 0) ? 1.0 : innerRatio;
              final double x = center.dx + halfW * scale * cos(angle);
              final double y = center.dy + halfH * scale * sin(angle);
              if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
            }
            path.close();
          }
          break;
        case DrawingType.marker:
          if (points.length >= 2) {
            final p1 = _resolveAnchor(drawing.points[0]);
            final p2 = _resolveAnchor(drawing.points[1]);
            final startRow = drawing.points[0].row;
            final endRow = drawing.points[1].row;

            final markerPaint = Paint()
              ..color = drawing
                  .color // 半透明色を想定
              ..style = PaintingStyle.fill;

            for (int r = startRow; r <= endRow; r++) {
              final double lineBottom = (r + 1) * lineHeight;
              final double heightRatio = drawing.markerHeight.clamp(0.0, 1.0);
              final double markerHeight = lineHeight * heightRatio;
              final double markerTop = lineBottom - markerHeight;

              final Rect markerRect = Rect.fromLTRB(
                p1.dx,
                markerTop,
                p2.dx,
                lineBottom,
              );
              canvas.drawRect(markerRect, markerPaint);
            }
          }
          break;
        case DrawingType.image:
          if (points.length >= 2) {
            final rect = Rect.fromPoints(points[0], points[1]);
            final image = (drawing.filePath != null)
                ? imageCache[drawing.filePath!]
                : null;

            if (image != null) {
              paintImage(
                canvas: canvas,
                rect: rect,
                image: image,
                fit: BoxFit.contain, // アスペクト比を維持
                filterQuality: FilterQuality.medium,
              );
            } else {
              // 画像未ロード時のプレースホルダー
              final placeholderPaint = Paint()
                ..color = Colors.grey.withOpacity(0.2)
                ..style = PaintingStyle.fill;
              canvas.drawRect(rect, placeholderPaint);
            }
          }
          break;
        case DrawingType.table:
          if (points.length >= 2) {
            final rect = Rect.fromPoints(points[0], points[1]);
            // 外枠
            path.addRect(rect);

            // 内部線 (横) - グリッド吸着
            for (final ratio in drawing.tableRowPositions) {
              double y = rect.top + rect.height * ratio;
              // 行境界にスナップ
              double snappedY = (y / lineHeight).round() * lineHeight;
              // 枠内に収まる場合のみ描画
              if (snappedY > rect.top + 1 && snappedY < rect.bottom - 1) {
                path.moveTo(rect.left, snappedY);
                path.lineTo(rect.right, snappedY);
              }
            }

            // 内部線 (縦) - グリッド吸着
            for (final ratio in drawing.tableColPositions) {
              double x = rect.left + rect.width * ratio;
              // 文字境界にスナップ
              double snappedX = (x / charWidth).round() * charWidth;
              if (snappedX > rect.left + 1 && snappedX < rect.right - 1) {
                path.moveTo(snappedX, rect.top);
                path.lineTo(snappedX, rect.bottom);
              }
            }
          }
          break;
        default:
          break;
      }

      // 線種に応じた描画
      if (drawing.lineStyle == LineStyle.solid) {
        canvas.drawPath(path, paint);
      } else if (drawing.lineStyle == LineStyle.dotted) {
        // 点線 (2, 2)
        final dashedPath = _createDashedPath(path, 2, 2);
        canvas.drawPath(dashedPath, paint);
      } else if (drawing.lineStyle == LineStyle.dashed) {
        // 破線 (5, 5)
        final dashedPath = _createDashedPath(path, 5, 5);
        canvas.drawPath(dashedPath, paint);
      } else if (drawing.lineStyle == LineStyle.doubleLine) {
        // 二重線: 太い線を描いて、内側を白で抜く (簡易実装)
        final double originalWidth = paint.strokeWidth;

        // 外側
        paint.strokeWidth = originalWidth * 3;
        canvas.drawPath(path, paint);

        // 内側 (白)
        paint.strokeWidth = originalWidth;
        paint.color = Colors.white;
        canvas.drawPath(path, paint);

        // 色と太さを戻す
        paint.color = drawing.color;
        paint.strokeWidth = originalWidth;
      }

      // 矢印描画 (線とL型線のみ)
      if (drawing.type == DrawingType.line ||
          drawing.type == DrawingType.elbow) {
        // 矢印サイズを線の太さに比例させる
        // 二重線の場合は見た目の太さ(3倍)を基準にする
        double baseWidth = paint.strokeWidth;
        if (drawing.lineStyle == LineStyle.doubleLine) {
          baseWidth *= 3.0;
        }
        double arrowSize = max(12.0, baseWidth * 3.0);

        // 矢印の向き計算用ベクトル
        Offset startVecFrom = points.first;
        Offset startVecTo = points.last;
        Offset endVecFrom = points.first;
        Offset endVecTo = points.last;

        if (drawing.type == DrawingType.elbow && points.length >= 2) {
          // L字線の場合、角を考慮してベクトルを計算
          final p1 = points[0];
          final p2 = points[1];
          final double cornerY = drawing.isUpperRoute ? min(p1.dy, p2.dy) : max(p1.dy, p2.dy);
          final double cornerX = (cornerY == p1.dy) ? p2.dx : p1.dx;
          final corner = Offset(cornerX, cornerY);

          // 始点 -> 角 (角が始点と同じ位置なら 始点 -> 終点)
          startVecTo = (corner - p1).distance < 0.1 ? p2 : corner;
          // 角 -> 終点 (角が終点と同じ位置なら 始点 -> 終点)
          endVecFrom = (corner - p2).distance < 0.1 ? p1 : corner;
        }

        if (drawing.hasArrowStart && points.length >= 2) {
          // 始点方向の角度 (進行方向の逆)
          double angle = atan2(startVecTo.dy - startVecFrom.dy, startVecTo.dx - startVecFrom.dx);
          _drawArrow(canvas, startVecFrom, angle + pi, paint, arrowSize);
        }
        if (drawing.hasArrowEnd && points.length >= 2) {
          // 終点方向の角度
          double angle = atan2(endVecTo.dy - endVecFrom.dy, endVecTo.dx - endVecFrom.dx);
          _drawArrow(canvas, endVecTo, angle, paint, arrowSize);
        }
      }

      // 選択中ならハンドルを描画
      if (drawing.id == selectedDrawingId || showAllHandles) {
        _drawHandles(canvas, points, drawing.type, drawing);
      }

      // フィルタ中の図形タイプを強調表示 (薄い黄色)
      if (drawing.type == highlightedDrawingType) {
        _drawTypeHighlight(canvas, points, drawing.type);
      }

      // リストでホバー中の図形を強調表示
      if (drawing.id == highlightedDrawingId) {
        _drawHighlight(canvas, points, drawing.type, drawing);
      }
    }
  }

  // 破線パス生成ヘルパー
  Path _createDashedPath(Path source, double dashWidth, double dashSpace) {
    final Path dest = Path();
    for (final PathMetric metric in source.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        double len = dashWidth;
        if (distance + len > metric.length) {
          len = metric.length - distance;
        }
        dest.addPath(metric.extractPath(distance, distance + len), Offset.zero);
        distance += dashWidth + dashSpace;
      }
    }
    return dest;
  }

  // 矢印描画ヘルパー
  void _drawArrow(
    Canvas canvas,
    Offset tip,
    double angle,
    Paint paint,
    double arrowSize,
  ) {
    const double arrowAngle = pi / 6; // 30度

    final path = Path();
    path.moveTo(tip.dx, tip.dy);
    path.lineTo(
      tip.dx - arrowSize * cos(angle - arrowAngle),
      tip.dy - arrowSize * sin(angle - arrowAngle),
    );
    path.lineTo(
      tip.dx - arrowSize * cos(angle + arrowAngle),
      tip.dy - arrowSize * sin(angle + arrowAngle),
    );
    path.close();

    final arrowPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, arrowPaint);
  }

  // 始点から終点に向かって指定距離だけ進んだ点を返す (線の短縮用)
  Offset _shortenPoint(Offset start, Offset target, double shortenLen) {
    final double dist = (target - start).distance;
    if (dist <= shortenLen) return target; // 距離が短すぎる場合は点にする
    final double t = shortenLen / dist;
    return Offset(
      start.dx + (target.dx - start.dx) * t,
      start.dy + (target.dy - start.dy) * t,
    );
  }

  // ★ハンドル描画ロジック
  void _drawHandles(
    Canvas canvas,
    List<Offset> points,
    DrawingType type,
    DrawingObject drawing,
  ) {
    final paint = Paint();
    const double size = 8.0;
    const double halfSize = size / 2;

    // パディング分(ピクセル)を計算 (図形個別の設定を使用)
    final double padPixelX = drawing.paddingX * charWidth;
    final double padPixelY = drawing.paddingY * lineHeight;

    // 線やフリーハンドは中心に描画（内側という概念が曖昧なため）
    if (type == DrawingType.line ||
        type == DrawingType.elbow ||
        points.length < 2) {
      for (int i = 0; i < points.length; i++) {
        if (i == 0) {
          paint.color = Colors.green; // 始点
        } else if (i == points.length - 1) {
          paint.color = Colors.red; // 終点
        } else {
          paint.color = Colors.blue; // 中間点
        }
        canvas.drawRect(
          Rect.fromCenter(center: points[i], width: size, height: size),
          paint,
        );
      }
      return;
    }

    // 矩形系は枠の内側にハンドルを寄せる
    // さらにパディング分も考慮して内側へずらす
    final p1 = points[0];
    final p2 = points[1];

    // 幅と高さを計算
    double width = (p1.dx - p2.dx).abs();
    double height = (p1.dy - p2.dy).abs();

    // オフセット量の基本値
    double offsetX = halfSize + padPixelX;
    double offsetY = halfSize + padPixelY;

    // 幅・高さが小さい場合は、中心を超えないように制限する (幅0ならオフセット0になる)
    if (width < offsetX * 2) offsetX = width / 2;
    if (height < offsetY * 2) offsetY = height / 2;

    // P1のハンドル (相手の点に向かってずらす)
    paint.color = Colors.green; // 始点
    double dx1 = (p1.dx < p2.dx) ? offsetX : -offsetX;
    double dy1 = (p1.dy < p2.dy) ? offsetY : -offsetY;
    canvas.drawRect(
      Rect.fromCenter(center: p1 + Offset(dx1, dy1), width: size, height: size),
      paint,
    );

    // P2のハンドル
    paint.color = Colors.red; // 終点
    double dx2 = (p2.dx < p1.dx) ? offsetX : -offsetX;
    double dy2 = (p2.dy < p1.dy) ? offsetY : -offsetY;
    canvas.drawRect(
      Rect.fromCenter(center: p2 + Offset(dx2, dy2), width: size, height: size),
      paint,
    );
  }

  // ★ハイライト描画ロジック (リストホバー用)
  void _drawHighlight(
    Canvas canvas,
    List<Offset> points,
    DrawingType type,
    DrawingObject drawing,
  ) {
    // 背景色の補色を計算
    final bgColor = Color(editorBackgroundColor);
    final compColor = Color.fromARGB(255, 255 - bgColor.red, 255 - bgColor.green, 255 - bgColor.blue);

    final paint = Paint()
      ..color = compColor // 補色を使用
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    if (points.isEmpty) return;

    // 簡易的に矩形または線で囲む
    if (type == DrawingType.line ||
        type == DrawingType.elbow ||
        points.length < 2) {
      // 線系: パスをなぞるのが理想だが、簡易的に各点を結ぶか、バウンディングボックスを表示
      // ここではバウンディングボックスを表示
      double minX = double.infinity, maxX = -double.infinity;
      double minY = double.infinity, maxY = -double.infinity;
      for (final p in points) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
      // 少し広げる
      final rect = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(4.0);
      canvas.drawRect(rect, paint);
    } else {
      // 矩形系
      final rect = Rect.fromPoints(points[0], points[1]).inflate(4.0);
      if (type == DrawingType.oval) {
        canvas.drawOval(rect, paint);
      } else if (type == DrawingType.roundedRectangle) {
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
        canvas.drawRRect(rrect, paint);
      } else {
        canvas.drawRect(rect, paint);
      }
    }
  }

  // ★タイプ別ハイライト描画ロジック (フィルタ用)
  void _drawTypeHighlight(
    Canvas canvas,
    List<Offset> points,
    DrawingType type,
  ) {
    // 背景色の補色を計算 (少し透明度を入れて区別するか、同じ補色を使う)
    final bgColor = Color(editorBackgroundColor);
    final compColor = Color.fromARGB(255, 255 - bgColor.red, 255 - bgColor.green, 255 - bgColor.blue);

    final paint = Paint()
      ..color = compColor.withOpacity(0.6) // フィルタは少し薄めの補色
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    if (points.isEmpty) return;

    // 簡易的にバウンディングボックスを表示
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final rect = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(2.0);
    canvas.drawRect(rect, paint);
  }

  // ★AnchorPoint -> Offset 変換 (MemoPainter内での簡易実装)
  Offset _resolveAnchor(AnchorPoint anchor) {
    // 行が存在しない場合のガード
    String line = (anchor.row < lines.length) ? lines[anchor.row] : "";

    // Y座標: 行番号 * 行高さ + 相対オフセット
    double y = (anchor.row + anchor.dy) * lineHeight;

    // X座標: 文字列幅(px) + 相対オフセット
    // 文字列幅の計算
    String textBefore = "";
    if (anchor.col <= line.length) {
      textBefore = line.substring(0, anchor.col);
    } else {
      textBefore = line + (' ' * (anchor.col - line.length));
    }
    double x = (TextUtils.calcTextWidth(textBefore) + anchor.dx) * charWidth;

    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant MemoPainter oldDelegate) {
    return listEquals(oldDelegate.lines, lines) ||
        oldDelegate.charWidth != charWidth ||
        oldDelegate.charHeight != charHeight ||
        oldDelegate.lineHeight != lineHeight ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.isOverwriteMode != isOverwriteMode ||
        oldDelegate.cursorRow != cursorRow ||
        oldDelegate.cursorCol != cursorCol ||
        oldDelegate.textStyle != textStyle ||
        oldDelegate.selectionOriginRow != selectionOriginRow ||
        oldDelegate.selectionOriginCol != selectionOriginCol ||
        oldDelegate.isRectangularSelection != isRectangularSelection ||
        oldDelegate.composingText != composingText ||
        oldDelegate.showCursor != showCursor ||
        oldDelegate.searchResults != searchResults ||
        oldDelegate.currentSearchIndex != currentSearchIndex ||
        oldDelegate.gridColor != gridColor ||
        !listEquals(oldDelegate.drawings, drawings) || // ★図形の変更検知
        oldDelegate.selectedDrawingId != selectedDrawingId || // ★選択状態の変更検知
        oldDelegate.shapePaddingX != shapePaddingX ||
        oldDelegate.shapePaddingY != shapePaddingY ||
        oldDelegate.showDrawings != showDrawings ||
        oldDelegate.showAllHandles != showAllHandles ||
        oldDelegate.highlightedDrawingId != highlightedDrawingId ||
        oldDelegate.highlightedDrawingType != highlightedDrawingType ||
        oldDelegate.areaSelectionRect != areaSelectionRect ||
        oldDelegate.editorBackgroundColor != editorBackgroundColor ||
        oldDelegate.imageCache != imageCache;
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

class ColumnRulerPainter extends CustomPainter {
  final double charWidth;
  final double lineHeight;
  final TextStyle textStyle;
  final double editorWidth;

  ColumnRulerPainter({
    required this.charWidth,
    required this.lineHeight,
    required this.textStyle,
    required this.editorWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey
      ..strokeWidth = 1.0;

    // 描画範囲の計算 (画面に見える範囲だけでなく、全体を描画してスクロールさせる)
    // editorWidth は十分な大きさを持っている前提
    int maxCols = (editorWidth / charWidth).ceil();

    for (int i = 1; i <= maxCols; i++) {
      double x = i * charWidth;

      if (i % 10 == 0) {
        // 10列ごと: 長い線と数値
        canvas.drawLine(
          Offset(x, size.height),
          Offset(x, size.height - 8),
          paint,
        );

        final textSpan = TextSpan(
          text: '$i',
          style: textStyle, // サイズ調整を削除し、渡されたスタイルをそのまま使う
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        // 数値を線の左側に寄せて表示
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, size.height - 20),
        );
      } else if (i % 5 == 0) {
        // 5列ごと: 短い線
        canvas.drawLine(
          Offset(x, size.height),
          Offset(x, size.height - 5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ColumnRulerPainter oldDelegate) {
    return oldDelegate.charWidth != charWidth ||
        oldDelegate.lineHeight != lineHeight ||
        oldDelegate.textStyle != textStyle ||
        oldDelegate.editorWidth != editorWidth;
  }
}

class MinimapPainter extends CustomPainter {
  final List<String> lines;
  final Size docSize; // ドキュメント全体のサイズ
  final Rect viewportRect; // 現在の表示範囲 (ドキュメント座標系)
  final double charWidth;
  final double lineHeight;
  final TextStyle textStyle; // エディタ本体のテキストスタイル

  MinimapPainter({
    required this.lines,
    required this.docSize,
    required this.viewportRect,
    required this.charWidth,
    required this.lineHeight,
    required this.textStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 背景
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFFF5F5F5),
    );

    // スケール計算: ドキュメント全体をミニマップ領域(size)に収める
    // アスペクト比を維持しつつ、全体が入るように min(scaleX, scaleY) を採用
    double scaleX = size.width / docSize.width;
    double scaleY = size.height / docSize.height;
    double scale = min(scaleX, scaleY);

    // 座標系を縮小
    canvas.save();
    canvas.scale(scale);

    // テキスト描画設定
    // 縮小されるので、フォントサイズは元のままでOK（scaleで小さくなる）
    // ただし、あまりに小さいと描画負荷が高いので、簡易描画に切り替える手もあるが、
    // ここでは要望通り文字を描画する。
    final minimapStyle = textStyle.copyWith(
      color: Colors.grey.shade600,
      fontSize: lineHeight, // 元の高さ
      height: 1.0,
    );

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].isEmpty) continue;

      textPainter.text = TextSpan(text: lines[i], style: minimapStyle);
      // layoutの幅制限は解除（縮小して全体を表示するため）
      textPainter.layout();

      textPainter.paint(canvas, Offset(0, i * lineHeight));
    }

    // ビューポート枠（現在の表示範囲）
    final viewportPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    // 枠線
    final viewportBorderPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / scale; // 縮小されても線幅を保つ

    canvas.drawRect(viewportRect, viewportPaint);
    canvas.drawRect(viewportRect, viewportBorderPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MinimapPainter oldDelegate) {
    return oldDelegate.lines != lines ||
        oldDelegate.docSize != docSize ||
        oldDelegate.viewportRect != viewportRect ||
        oldDelegate.textStyle != textStyle;
  }
}
