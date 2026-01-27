import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:charset_converter/charset_converter.dart';
import 'history_manager.dart';
import 'text_utils.dart';
import 'search_result.dart';
import 'file_io_helper.dart';
import 'drawing_data.dart';

enum NewLineType {
  lf,
  crlf,
  cr;

  String get label {
    switch (this) {
      case NewLineType.lf:
        return 'LF';
      case NewLineType.crlf:
        return 'CRLF';
      case NewLineType.cr:
        return 'CR';
    }
  }
}

/// 1つのドキュメント（ファイル）の状態と編集ロジックを管理するクラス
class EditorDocument extends ChangeNotifier {
  // --- 状態変数 ---
  List<String> lines = [''];
  int cursorRow = 0;
  int cursorCol = 0;
  int preferredVisualX = 0;
  bool isOverwriteMode = false;
  String? currentFilePath;
  String composingText = "";
  TextRange composingSelection = TextRange.empty;
  bool isDirty = false;
  String currentEncoding = 'utf-8';
  NewLineType newLineType = NewLineType.lf;
  bool isReadOnly = false; // 読み取り専用フラグ
  String? title; // ドキュメントタイトル (ファイル名より優先)

  // 自動生成されたタイトル
  static int _untitledCounter = 1;
  late final String _defaultTitle;

  EditorDocument() {
    _defaultTitle = 'Untitled-${_untitledCounter++}';
  }

  // 検索・置換
  List<SearchResult> searchResults = [];
  int currentSearchIndex = -1;

  // 選択範囲
  int? selectionOriginRow;
  int? selectionOriginCol;
  bool isRectangularSelection = false;

  // 図形データ (フリーハンドのストローク)
  // 確定済みの図形 (AnchorPointベース)
  List<DrawingObject> drawings = [];
  String? selectedDrawingId; // 選択中の図形ID
  // 描画中のプレビュー用 (Offsetベース)
  List<List<Offset>> strokes = [];
  List<Offset>? _currentStroke;

  // 図形操作用
  int? _activeHandleIndex; // 操作中のハンドルのインデックス
  bool _isMovingDrawing = false; // 図形移動中フラグ
  List<AnchorPoint>? _initialDrawingPoints; // 移動開始時の図形座標（移動量の基準）
  int? _dragStartRow; // ドラッグ開始時の行
  int? _dragStartCol; // ドラッグ開始時の列
  int? _activeTableDividerIndex; // 操作中のテーブル区切り線のインデックス
  bool _activeTableDividerIsRow = false; // true: 行(横線), false: 列(縦線)

  // 図形操作中かどうか
  bool get isInteractingWithDrawing =>
      _activeHandleIndex != null ||
      _isMovingDrawing ||
      _activeTableDividerIndex != null;

  // 描画中かどうか (ストロークが存在するか)
  bool get isDrawing => _currentStroke != null && _currentStroke!.isNotEmpty;

  // 履歴管理
  final HistoryManager historyManager = HistoryManager();

  // 設定値（Controllerから渡される、またはデフォルト）
  int tabWidth = 4;

  bool get hasSelection =>
      selectionOriginRow != null && selectionOriginCol != null;

  // 表示名を取得
  String get displayName {
    if (title != null) return title!;
    if (currentFilePath != null) {
      return currentFilePath!.split(Platform.pathSeparator).last;
    }
    return _defaultTitle;
  }

  // --- Search & Replace Logic ---

  void search(
    String query, {
    bool isRegex = false,
    bool isCaseSensitive = false,
  }) {
    searchResults.clear();
    currentSearchIndex = -1;

    if (query.isEmpty) {
      notifyListeners();
      return;
    }

    try {
      RegExp regExp;
      if (isRegex) {
        regExp = RegExp(query, caseSensitive: isCaseSensitive);
      } else {
        regExp = RegExp(RegExp.escape(query), caseSensitive: isCaseSensitive);
      }

      for (int i = 0; i < lines.length; i++) {
        String line = lines[i];
        final matches = regExp.allMatches(line);
        for (final match in matches) {
          if (match.end - match.start > 0) {
            searchResults.add(
              SearchResult(i, match.start, match.end - match.start),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }

    if (searchResults.isNotEmpty) {
      currentSearchIndex = 0;
      int baseRow = cursorRow;
      int baseCol = cursorCol;

      if (hasSelection) {
        if (selectionOriginRow! < cursorRow ||
            (selectionOriginRow! == cursorRow &&
                selectionOriginCol! < cursorCol)) {
          baseRow = selectionOriginRow!;
          baseCol = selectionOriginCol!;
        }
      }

      for (int i = 0; i < searchResults.length; i++) {
        final result = searchResults[i];
        if (result.lineIndex > baseRow ||
            (result.lineIndex == baseRow && result.startCol >= baseCol)) {
          currentSearchIndex = i;
          break;
        }
      }
      _jumpToSearchResult(currentSearchIndex);
    }
    notifyListeners();
  }

  void nextMatch() {
    if (searchResults.isEmpty) return;
    currentSearchIndex = (currentSearchIndex + 1) % searchResults.length;
    _jumpToSearchResult(currentSearchIndex);
    notifyListeners();
  }

  void previousMatch() {
    if (searchResults.isEmpty) return;
    currentSearchIndex =
        (currentSearchIndex - 1 + searchResults.length) % searchResults.length;
    _jumpToSearchResult(currentSearchIndex);
    notifyListeners();
  }

  void _jumpToSearchResult(int index) {
    if (index < 0 || index >= searchResults.length) return;
    final result = searchResults[index];

    selectionOriginRow = result.lineIndex;
    selectionOriginCol = result.startCol;
    cursorRow = result.lineIndex;
    cursorCol = result.startCol + result.length;
    isRectangularSelection = false;

    preferredVisualX = calcVisualX(cursorRow, cursorCol);
  }

  void replace(
    String query,
    String newText, {
    bool isRegex = false,
    bool isCaseSensitive = false,
  }) {
    if (isReadOnly) return;
    if (searchResults.isEmpty || currentSearchIndex == -1) return;
    final result = searchResults[currentSearchIndex];

    saveHistory();

    selectionOriginRow = result.lineIndex;
    selectionOriginCol = result.startCol;
    cursorRow = result.lineIndex;
    cursorCol = result.startCol + result.length;

    deleteSelection();
    insertText(newText);

    search(query, isRegex: isRegex, isCaseSensitive: isCaseSensitive);
  }

  void replaceAll(
    String query,
    String newText, {
    bool isRegex = false,
    bool isCaseSensitive = false,
  }) {
    if (isReadOnly) return;
    if (query.isEmpty) return;
    saveHistory();

    try {
      RegExp regExp;
      if (isRegex) {
        regExp = RegExp(query, caseSensitive: isCaseSensitive);
      } else {
        regExp = RegExp(RegExp.escape(query), caseSensitive: isCaseSensitive);
      }

      for (int i = 0; i < lines.length; i++) {
        lines[i] = lines[i].replaceAll(regExp, newText);
      }
    } catch (e) {
      debugPrint('ReplaceAll error: $e');
    }

    search(query, isRegex: isRegex, isCaseSensitive: isCaseSensitive);
  }

  void clearSearch() {
    searchResults.clear();
    currentSearchIndex = -1;
    notifyListeners();
  }

  // --- Editing Logic ---

  // --- Drawing Logic ---

  void startStroke(Offset pos) {
    if (isReadOnly) return;
    _currentStroke = [pos];
    strokes.add(_currentStroke!);
    notifyListeners();
  }

  void updateStroke(Offset pos) {
    if (isReadOnly) return;
    if (_currentStroke != null) {
      _currentStroke!.add(pos);
      notifyListeners();
    }
  }

  void endStroke(
    double charWidth,
    double lineHeight,
    int paddingX,
    double paddingY,
    DrawingType shapeType,
    Color color,
    double strokeWidth,
    double markerHeight,
    LineStyle lineStyle,
    bool arrowStart,
    bool arrowEnd,
  ) {
    if (isReadOnly) return;
    if (_currentStroke == null || _currentStroke!.isEmpty) return;

    final startPoint = _currentStroke!.first;
    final endPoint = _currentStroke!.last;

    // 線図形 (直線・L字線) の場合
    if (shapeType == DrawingType.line || shapeType == DrawingType.elbow) {
      _createLineOrElbow(
        startPoint,
        endPoint,
        charWidth,
        lineHeight,
        shapeType,
        color,
        strokeWidth,
        lineStyle,
        arrowStart,
        arrowEnd,
      );
      return;
    }

    // --- 囲み図形 (矩形・楕円・角丸) の処理 ---

    // 1. ストローク全体の外接矩形を計算 (テキスト検出用 & 正規化)
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (final p in _currentStroke!) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    // 2. グリッド吸着 (Snap to Grid)
    // 行 (Row) の計算
    // 矩形が少しかかっている行も含めるように floor を使用
    // 浮動小数点の誤差対策として、微小値を許容する
    const double epsilon = 0.001;
    int minRow = ((minY + epsilon) / lineHeight).floor();
    if (minRow < 0) minRow = 0;
    int maxRow = ((maxY - epsilon) / lineHeight).floor();
    if (maxRow < minRow) maxRow = minRow;

    // 3. テキストコンテンツに基づく列 (VisualX) の補正
    // まずはラフな範囲 (VisualX) を計算
    int rawStartVX = (minX / charWidth).floor();
    int rawEndVX = (maxX / charWidth).ceil();

    int contentMinVX = 999999;
    int contentMaxVX = -999999;
    int contentMinRow = 999999;
    int contentMaxRow = -999999;
    bool hasContent = false;

    // 指定された行範囲内のテキストを走査し、矩形内にある「文字」の範囲を探す
    for (int r = minRow; r <= maxRow; r++) {
      if (r >= lines.length) break;
      String line = lines[r];

      int currentVX = 0;
      for (int i = 0; i < line.runes.length; i++) {
        int w = (line.runes.elementAt(i) < 128) ? 1 : 2;
        int charStartVX = currentVX;
        int charEndVX = currentVX + w;
        currentVX += w;

        // 文字の範囲が、ラフな矩形範囲と交差しているか
        if (charEndVX > rawStartVX && charStartVX < rawEndVX) {
          // 空白でないかチェック
          String char = String.fromCharCode(line.runes.elementAt(i));
          if (char.trim().isNotEmpty) {
            hasContent = true;
            if (charStartVX < contentMinVX) contentMinVX = charStartVX;
            if (charEndVX > contentMaxVX) contentMaxVX = charEndVX;
            if (r < contentMinRow) contentMinRow = r;
            if (r > contentMaxRow) contentMaxRow = r;
          }
        }
      }
    }

    // 文字が見つかったらその範囲に、なければ元のラフな範囲（グリッドスナップ）に合わせる
    int finalMinVX = hasContent ? contentMinVX : (minX / charWidth).round();
    int finalMaxVX = hasContent ? contentMaxVX : (maxX / charWidth).round();
    int finalMinRow = hasContent ? contentMinRow : minRow;
    int finalMaxRow = hasContent ? contentMaxRow : maxRow;

    // 4. 始点・終点への割り当てとパディング適用 (正規化: 常に左上 -> 右下)
    // min/max を使用して、常に左上を始点、右下を終点とする
    int startVX = finalMinVX - (hasContent ? paddingX : 0);
    int endVX = finalMaxVX + (hasContent ? paddingX : 0);

    int startR = finalMinRow;
    double startDy = -paddingY;

    int endR = finalMaxRow;
    double endDy = 1.0 + paddingY;

    // 5. AnchorPointの作成
    AnchorPoint p1 = _createSnapAnchor(startR, startVX, dy: startDy);
    AnchorPoint p2 = _createSnapAnchor(endR, endVX, dy: endDy);

    // 6. DrawingObjectを作成 (指定されたタイプを使用)
    final newDrawing = DrawingObject(
      id: DateTime.now().toIso8601String(), // 簡易ID
      type: shapeType, // 矩形 or 楕円
      points: [p1, p2],
      color: color,
      strokeWidth: strokeWidth,
      markerHeight: markerHeight,
      paddingX: paddingX,
      paddingY: paddingY,
      lineStyle: lineStyle,
      hasArrowStart: arrowStart,
      hasArrowEnd: arrowEnd,
    );

    saveHistory(); // 履歴保存
    drawings.add(newDrawing);
    selectedDrawingId = newDrawing.id; // 新規図形を選択状態にする

    // 描画中の一時ストロークをクリア
    _currentStroke = null;
    strokes.clear();
    notifyListeners();
  }

  // 線・L字線生成ロジック
  void _createLineOrElbow(
    Offset start,
    Offset end,
    double charWidth,
    double lineHeight,
    DrawingType type,
    Color color,
    double strokeWidth,
    LineStyle lineStyle,
    bool arrowStart,
    bool arrowEnd,
  ) {
    // 始点・終点を最も近いグリッド交点(行境界・文字境界)にスナップ
    int startRow = (start.dy / lineHeight).round();
    int startVX = (start.dx / charWidth).round();

    int endRow = (end.dy / lineHeight).round();
    int endVX = (end.dx / charWidth).round();

    AnchorPoint p1 = _createSnapAnchor(
      max(0, startRow),
      startVX,
      dy: 0.0, // 行境界に合わせる
    );
    AnchorPoint p2 = _createSnapAnchor(
      max(0, endRow),
      endVX,
      dy: 0.0, // 行境界に合わせる
    );

    List<AnchorPoint> points = [p1, p2];
    bool isUpperRoute = true;

    if (type == DrawingType.elbow &&
        _currentStroke != null &&
        _currentStroke!.isNotEmpty) {
      // L字線: 軌跡から角の位置を判定
      // ストロークの中間点を取得
      Offset midPoint = _currentStroke![_currentStroke!.length ~/ 2];

      // 角の候補
      // C1: 横移動優先 (start.y を維持して end.x へ) -> (end.x, start.y)
      Offset c1 = Offset(end.dx, start.dy);
      // C2: 縦移動優先 (start.x を維持して end.y へ) -> (start.x, end.y)
      Offset c2 = Offset(start.dx, end.dy);

      // 中間点がどちらに近いか
      double dist1 = (midPoint - c1).distanceSquared;
      double dist2 = (midPoint - c2).distanceSquared;

      if (dist1 < dist2) {
        // 横移動優先: (start.x, start.y) -> (end.x, start.y) -> (end.x, end.y)
        // 角のY座標は start.y (p1.y)
        // p1.y < p2.y (下り) なら min(y1,y2) = y1 なので Upper
        // p1.y > p2.y (上り) なら max(y1,y2) = y1 なので !Upper
        isUpperRoute = (startRow <= endRow);
      } else {
        // 縦移動優先: (start.x, start.y) -> (start.x, end.y) -> (end.x, end.y)
        // 角のY座標は end.y (p2.y)
        // p1.y < p2.y (下り) なら max(y1,y2) = y2 なので !Upper
        // p1.y > p2.y (上り) なら min(y1,y2) = y2 なので Upper
        isUpperRoute = (startRow > endRow);
      }
    }

    final newDrawing = DrawingObject(
      id: DateTime.now().toIso8601String(),
      type: type,
      points: points,
      color: color,
      strokeWidth: strokeWidth,
      lineStyle: lineStyle,
      hasArrowStart: arrowStart,
      hasArrowEnd: arrowEnd,
      isUpperRoute: isUpperRoute,
    );

    saveHistory(); // 履歴保存
    drawings.add(newDrawing);
    selectedDrawingId = newDrawing.id; // 新規図形を選択状態にする
    _currentStroke = null;
    strokes.clear();
    notifyListeners();
  }

  DrawingType getDrawingType(String id) {
    final drawing = drawings.firstWhere((d) => d.id == id);
    return drawing.type;
  }

  DrawingObject getDrawing(String id) {
    return drawings.firstWhere((d) => d.id == id);
  }

  // 図形プロパティの更新
  void updateDrawingProperties(
    String id, {
    Color? color,
    double? strokeWidth,
    double? markerHeight,
    int? paddingX,
    double? paddingY,
    DrawingType? type, // 追加
    LineStyle? lineStyle,
    bool? arrowStart,
    bool? arrowEnd,
    bool? isUpperRoute,
    String? filePath,
    List<double>? tableRowPositions,
    List<double>? tableColPositions,
  }) {
    if (isReadOnly) return;
    final index = drawings.indexWhere((d) => d.id == id);
    if (index == -1) return;

    saveHistory();
    final drawing = drawings[index];

    if (color != null) drawing.color = color;
    if (strokeWidth != null) drawing.strokeWidth = strokeWidth;
    if (markerHeight != null) drawing.markerHeight = markerHeight;
    if (type != null) {
      drawing.type = type;
    }
    if (lineStyle != null) drawing.lineStyle = lineStyle;
    if (arrowStart != null) drawing.hasArrowStart = arrowStart;
    if (arrowEnd != null) drawing.hasArrowEnd = arrowEnd;
    if (isUpperRoute != null) drawing.isUpperRoute = isUpperRoute;
    if (filePath != null) drawing.filePath = filePath;
    if (tableRowPositions != null) drawing.tableRowPositions = tableRowPositions;
    if (tableColPositions != null) drawing.tableColPositions = tableColPositions;

    // パディング更新 (矩形系のみ)
    if ((paddingX != null || paddingY != null) &&
        (drawing.type == DrawingType.rectangle ||
            drawing.type == DrawingType.oval ||
            drawing.type == DrawingType.roundedRectangle ||
            drawing.type == DrawingType.burst ||
            drawing.type == DrawingType.marker)) {
      int oldPx = drawing.paddingX;
      double oldPy = drawing.paddingY;
      int newPx = paddingX ?? oldPx;
      double newPy = paddingY ?? oldPy;

      drawing.paddingX = newPx;
      drawing.paddingY = newPy;

      // 座標再計算: 元のパディングを戻して新しいパディングを適用
      if (drawing.points.length >= 2) {
        // p1 (Top-Left)
        drawing.points[0].col += (oldPx - newPx);
        drawing.points[0].dy = -newPy;
        // p2 (Bottom-Right)
        drawing.points[1].col -= (oldPx - newPx);
        drawing.points[1].dy = 1.0 + newPy;
      }
    }

    // リストの参照を変更して、MemoPainterのshouldRepaintで変更を検知させる
    drawings = List.from(drawings);
    notifyListeners();
  }

  // 画像サイズに合わせて図形（終点）をリサイズ
  void resizeDrawingToImageSize(
    String id,
    double imageWidth,
    double imageHeight,
    double charWidth,
    double lineHeight,
  ) {
    if (isReadOnly) return;
    final index = drawings.indexWhere((d) => d.id == id);
    if (index == -1) return;

    saveHistory();
    final drawing = drawings[index];

    // 始点のピクセル座標を取得
    if (drawing.points.isEmpty) return;
    final startPoint = drawing.points[0];
    final startOffset = _resolveAnchor(startPoint, charWidth, lineHeight);

    // 終点のピクセル座標を計算
    final endOffset = startOffset + Offset(imageWidth, imageHeight);

    // 終点をAnchorPointに変換
    final endPoint = _convertToAnchor(endOffset, charWidth, lineHeight);

    // 図形のポイントを更新 (始点はそのまま、終点を更新)
    if (drawing.points.length < 2) {
      drawing.points.add(endPoint);
    } else {
      drawing.points[1] = endPoint;
    }

    notifyListeners();
  }

  // 指定座標に図形があるか判定（UIのカーソル変更用）
  bool isPointOnDrawing(Offset pos, double charWidth, double lineHeight) {
    for (int i = drawings.length - 1; i >= 0; i--) {
      if (_isHit(drawings[i], pos, charWidth, lineHeight)) {
        return true;
      }
    }
    return false;
  }

  // 指定された矩形範囲に含まれる（交差する）図形のIDリストを取得
  List<String> getDrawingsInRect(Rect selectionRect, double charWidth, double lineHeight) {
    List<String> result = [];
    for (final drawing in drawings) {
      // 図形のバウンディングボックスを計算
      double minX = double.infinity, maxX = -double.infinity;
      double minY = double.infinity, maxY = -double.infinity;
      
      final points = drawing.points.map((p) => _resolveAnchor(p, charWidth, lineHeight)).toList();
      if (points.isEmpty) continue;

      for (final p in points) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
      
      final drawingRect = Rect.fromLTRB(minX, minY, maxX, maxY);
      
      // 交差判定 (少しでもかかっていれば対象とする)
      if (selectionRect.overlaps(drawingRect)) {
        result.add(drawing.id);
      }
    }
    return result;
  }

  // --- Eraser Logic ---

  void eraseDrawing(Offset pos, double charWidth, double lineHeight) {
    if (isReadOnly) return;
    // 逆順で走査（上にあるものを優先して消す）
    for (int i = drawings.length - 1; i >= 0; i--) {
      final drawing = drawings[i];
      if (_isHit(drawing, pos, charWidth, lineHeight)) {
        saveHistory(); // 履歴保存
        drawings.removeAt(i);
        notifyListeners();
        return; // 1回のイベントで1つ消す（ドラッグで連続して消せるようにするため）
      }
    }
  }

  // 図形選択を解除
  void clearDrawingSelection() {
    if (selectedDrawingId != null) {
      selectedDrawingId = null;
      notifyListeners();
    }
  }

  // 選択中の図形を削除
  void deleteSelectedDrawing() {
    if (isReadOnly) return;
    if (selectedDrawingId == null) return;
    saveHistory();
    drawings.removeWhere((d) => d.id == selectedDrawingId);
    selectedDrawingId = null;
    notifyListeners();
  }

  // 指定IDの図形を削除 (画像挿入キャンセル時など)
  void deleteDrawing(String id) {
    if (isReadOnly) return;
    saveHistory();
    drawings.removeWhere((d) => d.id == id);
    if (selectedDrawingId == id) selectedDrawingId = null;
    notifyListeners();
  }

  bool _isHit(
    DrawingObject drawing,
    Offset pos,
    double charWidth,
    double lineHeight,
  ) {
    // 座標復元
    List<Offset> points = drawing.points
        .map((p) => _resolveAnchor(p, charWidth, lineHeight))
        .toList();
    if (points.isEmpty) return false;

    // 許容誤差 (タッチ操作なども考慮して広めに設定)
    const double hitThreshold = 10.0;

    if (drawing.type == DrawingType.line) {
      // 線分との距離判定
      if (points.length < 2) return false;
      return _distanceToLineSegment(pos, points.first, points.last) <
          hitThreshold;
    } else {
      // 矩形範囲判定
      if (points.length < 2) return false;
      final rect = Rect.fromPoints(points[0], points[1]);

      // 楕円の場合は描画時と同様に少し広げて判定
      // 矩形・角丸矩形も同様に「枠線付近」のみをヒットとする
      // (内部が透明なため、中身をクリックしても反応しないようにする)
      final outer = rect.inflate(hitThreshold);
      final inner = rect.deflate(hitThreshold);

      // 図形が小さすぎて内側がない場合は、全体をヒットとする
      if (rect.width < hitThreshold * 2 || rect.height < hitThreshold * 2) {
        return outer.contains(pos);
      }
      // 内部も含めてヒットとする
      return outer.contains(pos);
    }
  }

  // 点Pと線分ABの距離を計算
  double _distanceToLineSegment(Offset p, Offset a, Offset b) {
    final double dx = b.dx - a.dx;
    final double dy = b.dy - a.dy;
    if (dx == 0 && dy == 0) return (p - a).distance;

    // t = ((P-A) . (B-A)) / |B-A|^2
    final double t =
        ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / (dx * dx + dy * dy);

    if (t < 0) return (p - a).distance;
    if (t > 1) return (p - b).distance;

    final Offset projection = Offset(a.dx + t * dx, a.dy + t * dy);
    return (p - projection).distance;
  }

  // グリッド吸着用のAnchorPoint作成ヘルパー
  AnchorPoint _createSnapAnchor(int row, int visualX, {double dy = 0.0}) {
    // 行が存在しない場合でも、論理的な位置として保持する
    String line = "";
    if (row < lines.length) {
      line = lines[row];
    }

    // 修正: 行末より右側（虚空）の計算を追加
    int lineVisualWidth = TextUtils.calcTextWidth(line);
    int col;
    if (visualX <= lineVisualWidth) {
      col = TextUtils.getColFromVisualX(line, visualX);
    } else {
      // 行末より右にある場合は、差分をそのまま加算
      col = line.length + (visualX - lineVisualWidth);
    }

    // dx, dy を 0 にすることでグリッドに吸着させる
    // dyは行高さに対する比率として保存する (例: -0.2 や 1.2)
    return AnchorPoint(row: row, col: col, dx: 0.0, dy: dy);
  }

  // 座標変換ロジック: Offset(px) -> AnchorPoint(row, col, dx, dy)
  AnchorPoint _convertToAnchor(Offset p, double charWidth, double lineHeight) {
    // 行番号
    int row = (p.dy / lineHeight).floor();
    if (row < 0) row = 0;

    // 行内オフセットY
    // ピクセルではなく比率(0.0~1.0)で保存
    double dy = (p.dy - (row * lineHeight)) / lineHeight;

    // 行テキスト取得
    String line = "";
    if (row < lines.length) {
      line = lines[row];
    }

    // 文字位置(col)計算
    int visualX = (p.dx / charWidth).floor();
    int col = TextUtils.getColFromVisualX(line, visualX);

    // 文字位置からのオフセットX計算 (正確な文字の開始位置からの差分)
    String textBefore = "";
    if (col <= line.length) {
      textBefore = line.substring(0, col);
    } else {
      textBefore = line + (' ' * (col - line.length));
    }
    double charStartX = TextUtils.calcTextWidth(textBefore) * charWidth;
    // ピクセルではなく比率で保存
    double dx = (p.dx - charStartX) / charWidth;

    return AnchorPoint(row: row, col: col, dx: dx, dy: dy);
  }

  // AnchorPoint -> Offset 変換ロジック (当たり判定用)
  Offset _resolveAnchor(
    AnchorPoint anchor,
    double charWidth,
    double lineHeight,
  ) {
    // 比率(dy) * 行高さ(lineHeight) でピクセルに戻す
    double y = anchor.row * lineHeight + (anchor.dy * lineHeight);

    String line = "";
    if (anchor.row < lines.length) {
      line = lines[anchor.row];
    }

    String textBefore = "";
    if (anchor.col <= line.length) {
      textBefore = line.substring(0, anchor.col);
    } else {
      textBefore = line + (' ' * (anchor.col - line.length));
    }

    // 比率(dx) * 文字幅(charWidth) でピクセルに戻す
    double x =
        TextUtils.calcTextWidth(textBefore) * charWidth +
        (anchor.dx * charWidth);
    return Offset(x, y);
  }

  // テキスト挿入に伴うアンカー位置の更新
  void _updateAnchorsOnInsert(int row, int col, int length) {
    for (final drawing in drawings) {
      for (final point in drawing.points) {
        if (point.row == row && point.col >= col) {
          point.col += length;
        }
      }
    }
  }

  // テキスト削除に伴うアンカー位置の更新
  void _updateAnchorsOnDelete(int row, int col, int length) {
    for (final drawing in drawings) {
      for (final point in drawing.points) {
        if (point.row == row) {
          if (point.col >= col + length) {
            point.col -= length;
          } else if (point.col > col) {
            // 削除範囲内にあったアンカーは削除開始位置に寄せる
            point.col = col;
            point.dx = 0.0; // オフセットもリセット
          }
        }
      }
    }
  }

  void saveHistory() {
    historyManager.save(lines, cursorRow, cursorCol, drawings);
  }

  void ensureVirtualSpace(int row, int col) {
    if (row >= lines.length) {
      int newLinesNeeded = row - lines.length + 1;
      for (int i = 0; i < newLinesNeeded; i++) {
        lines.add("");
      }
    }
    if (col > lines[row].length) {
      lines[row] = lines[row].padRight(col);
    }
  }

  void insertText(String text) {
    if (isReadOnly) return;
    if (text.isEmpty) return;

    ensureVirtualSpace(cursorRow, cursorCol);

    String currentLine = lines[cursorRow];
    String part1 = currentLine.substring(0, cursorCol);
    String part2 = currentLine.substring(cursorCol);

    if (isOverwriteMode && part2.isNotEmpty) {
      int inputVisualWidth = TextUtils.calcTextWidth(text);
      int removeLength = 0;
      int currentVisualWidth = 0;

      var iterator = part2.runes.iterator;
      while (iterator.moveNext()) {
        if (currentVisualWidth >= inputVisualWidth && removeLength > 0) {
          break;
        }
        int rune = iterator.current;
        int charWidth = (rune < 128) ? 1 : 2;
        currentVisualWidth += charWidth;
        removeLength += (rune > 0xFFFF) ? 2 : 1;
      }

      if (removeLength > 0) {
        if (part2.length >= removeLength) {
          part2 = part2.substring(removeLength);
        } else {
          part2 = "";
        }
        // 上書きモードでの削除分を反映
        _updateAnchorsOnDelete(cursorRow, cursorCol, removeLength);
      }
    }

    // 挿入分を反映
    _updateAnchorsOnInsert(cursorRow, cursorCol, text.length);

    lines[cursorRow] = part1 + text + part2;
    cursorCol += text.length;

    isDirty = true;
    String newLine = lines[cursorRow];
    int safeEnd = min(cursorCol, newLine.length);
    preferredVisualX = TextUtils.calcTextWidth(newLine.substring(0, safeEnd));

    notifyListeners();
  }

  void deleteSelection() {
    if (isReadOnly) return;
    if (!hasSelection) return;

    if (isRectangularSelection) {
      _deleteRectangularSelection();
    } else {
      _deleteNormalSelection();
    }
    selectionOriginRow = null;
    selectionOriginCol = null;
    isDirty = true;
    notifyListeners();
  }

  void _deleteNormalSelection() {
    int startRow = selectionOriginRow!;
    int startCol = selectionOriginCol!;
    int endRow = cursorRow;
    int endCol = cursorCol;

    if (startRow > endRow || (startRow == endRow && startCol > endCol)) {
      int t = startRow;
      startRow = endRow;
      endRow = t;
      t = startCol;
      startCol = endCol;
      endCol = t;
    }

    if (startRow >= lines.length) {
      cursorRow = startRow;
      cursorCol = startCol;
      return;
    }

    String startLine = (startRow < lines.length) ? lines[startRow] : "";
    String prefix = (startCol < startLine.length)
        ? startLine.substring(0, startCol)
        : startLine;

    String endLine = (endRow < lines.length) ? lines[endRow] : "";
    String suffix = (endCol < endLine.length) ? endLine.substring(endCol) : "";

    lines[startRow] = prefix + suffix;

    if (endRow > startRow) {
      int removeEndIndex = endRow + 1;
      if (removeEndIndex > lines.length) {
        removeEndIndex = lines.length;
      }
      if (removeEndIndex > startRow + 1) {
        lines.removeRange(startRow + 1, removeEndIndex);
      }
    }

    // 図形更新ロジック (単一行・複数行対応)
    int deletedLinesCount = endRow - startRow;
    for (final drawing in drawings) {
      for (final point in drawing.points) {
        if (point.row == startRow) {
          if (point.col >= startCol) {
            // startRow行目の削除範囲以降 -> startColに寄せる
            // (単一行削除の場合は削除文字数分詰める)
            if (startRow == endRow) {
              point.col -= (endCol - startCol);
            } else {
              point.col = startCol;
              point.dx = 0;
            }
          }
        } else if (point.row > startRow && point.row < endRow) {
          // 間の行 -> startRow, startCol に寄せる
          point.row = startRow;
          point.col = startCol;
          point.dx = 0;
        } else if (point.row == endRow) {
          // endRow行目 -> startRow行目に結合
          point.row = startRow;
          // endColより前の部分はstartColに寄せ、それ以降は結合後の位置へシフト
          point.col = startCol + max(0, point.col - endCol);
        } else if (point.row > endRow) {
          // それ以降の行 -> 行詰め
          point.row -= deletedLinesCount;
        }
      }
    }

    cursorRow = startRow;
    cursorCol = startCol;
    isDirty = true;
  }

  void _deleteRectangularSelection() {
    int startRow = min(selectionOriginRow!, cursorRow);
    int endRow = max(selectionOriginRow!, cursorRow);

    int originVisualX = calcVisualX(selectionOriginRow!, selectionOriginCol!);
    int cursorVisualX = calcVisualX(cursorRow, cursorCol);

    int minVisualX = min(originVisualX, cursorVisualX);
    int maxVisualX = max(originVisualX, cursorVisualX);

    for (int i = startRow; i <= endRow; i++) {
      if (i >= lines.length) continue;
      String line = lines[i];

      int startCol = TextUtils.getColFromVisualX(line, minVisualX);
      int endCol = TextUtils.getColFromVisualX(line, maxVisualX);

      if (startCol > endCol) {
        int t = startCol;
        startCol = endCol;
        endCol = t;
      }
      if (startCol > line.length) startCol = line.length;
      if (endCol > line.length) endCol = line.length;

      String part1 = line.substring(0, startCol);
      String part2 = line.substring(endCol);
      lines[i] = part1 + part2;

      // 削除分を反映
      _updateAnchorsOnDelete(i, startCol, endCol - startCol);
    }
    cursorRow = startRow;
    if (cursorRow < lines.length) {
      cursorCol = TextUtils.getColFromVisualX(lines[cursorRow], minVisualX);
      if (cursorCol > lines[cursorRow].length) {
        cursorCol = lines[cursorRow].length;
      }
    }
    isDirty = true;
  }

  void replaceRectangularSelection(String text) {
    if (isReadOnly) return;
    if (!hasSelection) return;

    int startRow = min(selectionOriginRow!, cursorRow);
    int endRow = max(selectionOriginRow!, cursorRow);

    int originVisualX = calcVisualX(selectionOriginRow!, selectionOriginCol!);
    int cursorVisualX = calcVisualX(cursorRow, cursorCol);

    int minVisualX = min(originVisualX, cursorVisualX);
    int maxVisualX = max(originVisualX, cursorVisualX);

    int newCursorRow = startRow;
    int newCursorCol = 0;

    for (int i = startRow; i <= endRow; i++) {
      if (i >= lines.length) continue;
      String line = lines[i];

      int startCol = TextUtils.getColFromVisualX(line, minVisualX);
      int endCol = TextUtils.getColFromVisualX(line, maxVisualX);

      if (startCol > endCol) {
        int t = startCol;
        startCol = endCol;
        endCol = t;
      }
      if (startCol > line.length) startCol = line.length;
      if (endCol > line.length) endCol = line.length;

      String part1 = line.substring(0, startCol);
      String part2 = line.substring(endCol);
      lines[i] = part1 + text + part2;

      // 削除と挿入を反映
      _updateAnchorsOnDelete(i, startCol, endCol - startCol);
      _updateAnchorsOnInsert(i, startCol, text.length);

      if (i == startRow) {
        newCursorCol = part1.length + text.length;
      }
    }

    cursorRow = newCursorRow;
    cursorCol = newCursorCol;

    selectionOriginRow = null;
    selectionOriginCol = null;

    if (cursorRow < lines.length) {
      String line = lines[cursorRow];
      if (cursorCol > line.length) cursorCol = line.length;
      preferredVisualX = TextUtils.calcTextWidth(line.substring(0, cursorCol));
    }

    isDirty = true;
    notifyListeners();
  }

  void undo() {
    if (isReadOnly) return;
    final entry = historyManager.undo(lines, cursorRow, cursorCol, drawings);
    if (entry != null) {
      isDirty = true;
      _applyHistoryEntry(entry);
    }
  }

  void redo() {
    if (isReadOnly) return;
    final entry = historyManager.redo(lines, cursorRow, cursorCol, drawings);
    if (entry != null) {
      isDirty = true;
      _applyHistoryEntry(entry);
    }
  }

  void _applyHistoryEntry(HistoryEntry entry) {
    lines = List.from(entry.lines);
    cursorRow = entry.cursorRow;
    cursorCol = entry.cursorCol;
    // 図形の復元 (コピーして適用)
    drawings = entry.drawings.map((d) => d.copy()).toList();
    selectionOriginRow = null;
    selectionOriginCol = null;
    preferredVisualX = calcVisualX(cursorRow, cursorCol);
    notifyListeners();
  }

  void selectAll() {
    selectionOriginRow = 0;
    selectionOriginCol = 0;
    cursorRow = lines.length - 1;
    cursorCol = lines.last.length;
    isRectangularSelection = false;
    preferredVisualX = calcVisualX(cursorRow, cursorCol);
    notifyListeners();
  }

  void indent() {
    if (isReadOnly) return;
    saveHistory();
    deleteSelection();
    insertText(' ' * tabWidth);
  }

  void trimTrailingWhitespace() {
    if (isReadOnly) return;
    saveHistory();
    bool changed = false;
    for (int i = 0; i < lines.length; i++) {
      String original = lines[i];
      String trimmed = original.trimRight();
      if (original != trimmed) {
        lines[i] = trimmed;
        changed = true;
      }
    }
    if (changed) {
      isDirty = true;
      notifyListeners();
    }
  }

  // --- キー操作に対応する編集メソッド (図形更新付き) ---

  // 改行挿入
  void insertNewLine() {
    if (isReadOnly) return;
    saveHistory();
    deleteSelection();
    ensureVirtualSpace(cursorRow, cursorCol);

    final currentLine = lines[cursorRow];
    final part1 = currentLine.substring(0, cursorCol);
    final part2 = currentLine.substring(cursorCol);

    lines[cursorRow] = part1;
    lines.insert(cursorRow + 1, part2);

    // 図形の更新
    for (final drawing in drawings) {
      for (final point in drawing.points) {
        if (point.row == cursorRow && point.col >= cursorCol) {
          // 現在行のカーソル以降にある図形 -> 次の行へ移動
          point.row += 1;
          point.col -= cursorCol;
        } else if (point.row > cursorRow) {
          // それ以降の行にある図形 -> 行番号+1
          point.row += 1;
        }
      }
    }

    cursorRow++;
    cursorCol = 0;
    isDirty = true;
    notifyListeners();
  }

  // Backspace
  void backspace() {
    if (isReadOnly) return;
    saveHistory();
    if (hasSelection) {
      deleteSelection();
      return;
    }

    // 虚空行での処理
    if (cursorRow >= lines.length) {
      if (cursorCol > 0) {
        cursorCol--;
      } else if (cursorRow > 0) {
        cursorRow--;
        cursorCol = (cursorRow < lines.length) ? lines[cursorRow].length : 0;
      }
      isDirty = true;
      notifyListeners();
      return;
    }

    if (cursorCol > 0) {
      // 行内削除
      String line = lines[cursorRow];
      // カーソルが行末より右にある(行内虚空)場合
      if (cursorCol > line.length) {
        cursorCol--;
      } else {
        // 簡易的に1文字削除 (サロゲートペア等は考慮していないが既存動作準拠)
        String part1 = line.substring(0, cursorCol - 1);
        String part2 = line.substring(cursorCol);
        lines[cursorRow] = part1 + part2;
        _updateAnchorsOnDelete(cursorRow, cursorCol - 1, 1);
        cursorCol--;
      }
    } else if (cursorRow > 0) {
      // 行結合 (前の行へ)
      String lineToAppend = lines[cursorRow];
      String prevLine = lines[cursorRow - 1];
      int prevLineLength = prevLine.length;

      lines[cursorRow - 1] += lineToAppend;
      lines.removeAt(cursorRow);

      // 図形の更新
      for (final drawing in drawings) {
        for (final point in drawing.points) {
          if (point.row == cursorRow) {
            // 現在行にある図形 -> 前の行の末尾へ移動
            point.row -= 1;
            point.col += prevLineLength;
          } else if (point.row > cursorRow) {
            // それ以降の行 -> 行番号-1
            point.row -= 1;
          }
        }
      }
      cursorRow--;
      cursorCol = prevLineLength;
    }
    isDirty = true;
    notifyListeners();
  }

  // Delete
  void delete() {
    if (isReadOnly) return;
    saveHistory();
    if (hasSelection) {
      deleteSelection();
      return;
    }
    if (cursorRow >= lines.length) return;

    String line = lines[cursorRow];
    if (cursorCol < line.length) {
      // 行内削除
      String part1 = line.substring(0, cursorCol);
      String part2 = line.substring(cursorCol + 1);
      lines[cursorRow] = part1 + part2;
      _updateAnchorsOnDelete(cursorRow, cursorCol, 1);
    } else if (cursorRow < lines.length - 1) {
      // 行結合 (次の行を吸い上げる)
      String nextLine = lines[cursorRow + 1];
      int currentLength = line.length;

      // カーソルが行末より右にある場合、スペースで埋める
      if (cursorCol > currentLength) {
        lines[cursorRow] = line.padRight(cursorCol);
        currentLength = cursorCol;
      }

      lines[cursorRow] += nextLine;
      lines.removeAt(cursorRow + 1);

      // 図形の更新
      for (final drawing in drawings) {
        for (final point in drawing.points) {
          if (point.row == cursorRow + 1) {
            // 次の行にある図形 -> 現在行の末尾へ移動
            point.row -= 1;
            point.col += currentLength;
          } else if (point.row > cursorRow + 1) {
            // それ以降の行 -> 行番号-1
            point.row -= 1;
          }
        }
      }
    }
    isDirty = true;
    notifyListeners();
  }

  int calcVisualX(int row, int col) {
    String line = (row < lines.length) ? lines[row] : "";
    String text;
    if (col <= line.length) {
      text = line.substring(0, col);
    } else {
      text = line + (' ' * (col - line.length));
    }
    return TextUtils.calcTextWidth(text);
  }

  void _handleSelectionOnMove(bool isShift, bool isAlt) {
    if (isShift) {
      selectionOriginRow ??= cursorRow;
      selectionOriginCol ??= cursorCol;
      isRectangularSelection = isAlt;
    } else {
      selectionOriginRow = null;
      selectionOriginCol = null;
    }
  }

  void moveCursor(int rowMove, int colMove, bool isShift, bool isAlt) {
    _handleSelectionOnMove(isShift, isAlt);

    if (colMove != 0) {
      if (isAlt) {
        if (colMove > 0) {
          cursorCol += colMove;
        } else {
          if (cursorCol > 0) {
            cursorCol += colMove;
          } else if (cursorRow > 0) {
            cursorRow--;
            cursorCol = lines[cursorRow].length;
          }
        }
        if (cursorCol < 0) cursorCol = 0;
      } else {
        int currentLineLength = (cursorRow < lines.length)
            ? lines[cursorRow].length
            : 0;
        if (colMove > 0) {
          if (cursorCol < currentLineLength) {
            cursorCol++;
          } else if (cursorRow < lines.length - 1) {
            cursorRow++;
            cursorCol = 0;
          }
        } else {
          if (cursorCol > 0) {
            cursorCol--;
          } else if (cursorRow > 0) {
            cursorRow--;
            cursorCol = lines[cursorRow].length;
          }
        }
      }

      if (cursorRow < lines.length) {
        String line = lines[cursorRow];
        String textUpToCursor;
        if (cursorCol <= line.length) {
          textUpToCursor = line.substring(0, cursorCol);
        } else {
          textUpToCursor = line + (" " * (cursorCol - line.length));
        }
        preferredVisualX = TextUtils.calcTextWidth(textUpToCursor);
      }
    }

    if (rowMove != 0) {
      if (isAlt) {
        cursorRow += rowMove;
        if (cursorRow < 0) cursorRow = 0;
      } else {
        cursorRow += rowMove;
        if (cursorRow < 0) cursorRow = 0;
        if (cursorRow >= lines.length) cursorRow = lines.length - 1;
      }

      if (cursorRow < lines.length) {
        String line = lines[cursorRow];
        int lineWidth = TextUtils.calcTextWidth(line);

        if (isAlt && preferredVisualX > lineWidth) {
          int gap = preferredVisualX - lineWidth;
          cursorCol = line.length + gap;
        } else {
          cursorCol = TextUtils.getColFromVisualX(line, preferredVisualX);
        }
      } else {
        cursorCol = preferredVisualX;
      }
    }

    notifyListeners();
  }

  void clearSelection() {
    selectionOriginRow = null;
    selectionOriginCol = null;
    notifyListeners();
  }

  void handleTap(Offset localPosition, double charWidth, double lineHeight) {
    if (charWidth == 0 || lineHeight == 0) return;

    // ★修正: handleTapはテキストカーソル移動専用にする（図形選択は行わない）

    int clickedVisualX = (localPosition.dx / charWidth).floor();
    int clickedRow = (localPosition.dy / lineHeight).floor();

    cursorRow = max(0, clickedRow);

    String currentLine = "";
    if (cursorRow < lines.length) {
      currentLine = lines[cursorRow];
    }

    int lineVisualWidth = TextUtils.calcTextWidth(currentLine);

    if (clickedVisualX <= lineVisualWidth) {
      cursorCol = TextUtils.getColFromVisualX(currentLine, clickedVisualX);
    } else {
      int gap = clickedVisualX - lineVisualWidth;
      cursorCol = currentLine.length + gap;
    }

    preferredVisualX = clickedVisualX;
    notifyListeners();
  }

  // ★新設: 図形選択専用メソッド
  void trySelectDrawing(
    Offset localPosition,
    double charWidth,
    double lineHeight,
  ) {
    for (int i = drawings.length - 1; i >= 0; i--) {
      if (_isHit(drawings[i], localPosition, charWidth, lineHeight)) {
        selectedDrawingId = drawings[i].id;
        notifyListeners();
        return;
      }
    }
    // 何もヒットしなければ選択解除
    if (selectedDrawingId != null) {
      selectedDrawingId = null;
      notifyListeners();
    }
  }

  void handlePanStart(
    Offset localPosition,
    double charWidth,
    double lineHeight,
    bool isAltPressed, {
    bool isFigureMode = false, // ★モード引数を追加
  }) {
    // 1. 図形操作 (Figureモードの場合のみ)
    if (isFigureMode) {
      if (isReadOnly) return; // 読み取り専用なら図形操作（移動・リサイズ）は禁止
      if (selectedDrawingId != null) {
        final drawingIndex = drawings.indexWhere(
          (d) => d.id == selectedDrawingId,
        );
        if (drawingIndex != -1) {
          final drawing = drawings[drawingIndex];

          // A. ハンドル判定 (リサイズ)
          final points = drawing.points
              .map((p) => _resolveAnchor(p, charWidth, lineHeight))
              .toList();

          // 修正: 描画されているハンドルの位置に合わせて判定座標を調整する
          List<Offset> hitTestPoints = [];

          if (drawing.type == DrawingType.line ||
              drawing.type == DrawingType.elbow ||
              points.length < 2) {
            // 線などはそのまま
            hitTestPoints = points;
          } else {
            // 矩形系（特にBurstなどパディングがあるもの）は、MemoPainterでハンドルが内側に描画されているため、
            // 当たり判定もそれに合わせる。
            final p1 = points[0];
            final p2 = points[1];

            final double padPixelX = drawing.paddingX * charWidth;
            final double padPixelY = drawing.paddingY * lineHeight;
            const double halfSize = 4.0; // ハンドルサイズ(8.0)の半分

            double offsetX = halfSize + padPixelX;
            double offsetY = halfSize + padPixelY;

            double width = (p1.dx - p2.dx).abs();
            double height = (p1.dy - p2.dy).abs();

            if (width < offsetX * 2) offsetX = width / 2;
            if (height < offsetY * 2) offsetY = height / 2;

            // P1 (Top-Left側) -> 内側へ
            double dx1 = (p1.dx < p2.dx) ? offsetX : -offsetX;
            double dy1 = (p1.dy < p2.dy) ? offsetY : -offsetY;
            hitTestPoints.add(p1 + Offset(dx1, dy1));

            // P2 (Bottom-Right側) -> 内側へ
            double dx2 = (p2.dx < p1.dx) ? offsetX : -offsetX;
            double dy2 = (p2.dy < p1.dy) ? offsetY : -offsetY;
            hitTestPoints.add(p2 + Offset(dx2, dy2));
          }

          for (int i = 0; i < hitTestPoints.length; i++) {
            if ((hitTestPoints[i] - localPosition).distance < 20.0) {
              _activeHandleIndex = i;
              return;
            }
          }

          // B. テーブル罫線判定
          if (drawing.type == DrawingType.table) {
            final rect = Rect.fromPoints(points[0], points[1]);
            const double hitThreshold = 8.0;

            // 横線
            for (int i = 0; i < drawing.tableRowPositions.length; i++) {
              double y = rect.top + rect.height * drawing.tableRowPositions[i];
              double snappedY = (y / lineHeight).round() * lineHeight;
              if ((localPosition.dy - snappedY).abs() < hitThreshold &&
                  localPosition.dx >= rect.left &&
                  localPosition.dx <= rect.right) {
                _activeTableDividerIndex = i;
                _activeTableDividerIsRow = true;
                return;
              }
            }

            // 縦線
            for (int i = 0; i < drawing.tableColPositions.length; i++) {
              double x = rect.left + rect.width * drawing.tableColPositions[i];
              double snappedX = (x / charWidth).round() * charWidth;
              if ((localPosition.dx - snappedX).abs() < hitThreshold &&
                  localPosition.dy >= rect.top &&
                  localPosition.dy <= rect.bottom) {
                _activeTableDividerIndex = i;
                _activeTableDividerIsRow = false;
                return;
              }
            }
          }

          // C. 図形本体判定 (移動)
          if (_isHit(drawing, localPosition, charWidth, lineHeight)) {
            _isMovingDrawing = true;
            _initialDrawingPoints = drawing.points
                .map(
                  (p) =>
                      AnchorPoint(row: p.row, col: p.col, dx: p.dx, dy: p.dy),
                )
                .toList();
            _dragStartRow = (localPosition.dy / lineHeight).floor();
            _dragStartCol = (localPosition.dx / charWidth).round();
            return;
          }
        }
      }
      // Figureモードで図形以外をドラッグした場合、何もしない（テキスト選択には行かない）
      return;
    }

    // 2. テキスト選択 (Textモードの場合のみ)
    handleTap(localPosition, charWidth, lineHeight);
    selectionOriginRow = cursorRow;
    selectionOriginCol = cursorCol;
    isRectangularSelection = isAltPressed;
    notifyListeners();
  }

  // テーブルのカーソルタイプ判定 (0:なし, 1:Row, 2:Col)
  int getTableCursorType(Offset pos, double charWidth, double lineHeight) {
    if (selectedDrawingId == null) return 0;
    final index = drawings.indexWhere((d) => d.id == selectedDrawingId);
    if (index == -1) return 0;
    final drawing = drawings[index];
    if (drawing.type != DrawingType.table) return 0;

    final points = drawing.points
        .map((p) => _resolveAnchor(p, charWidth, lineHeight))
        .toList();
    if (points.length < 2) return 0;
    final rect = Rect.fromPoints(points[0], points[1]);

    const double hitThreshold = 8.0;

    // 横線判定
    for (final ratio in drawing.tableRowPositions) {
      double y = rect.top + rect.height * ratio;
      double snappedY = (y / lineHeight).round() * lineHeight;
      if ((pos.dy - snappedY).abs() < hitThreshold &&
          pos.dx >= rect.left &&
          pos.dx <= rect.right) {
        return 1; // Resize Row
      }
    }

    // 縦線判定
    for (final ratio in drawing.tableColPositions) {
      double x = rect.left + rect.width * ratio;
      double snappedX = (x / charWidth).round() * charWidth;
      if ((pos.dx - snappedX).abs() < hitThreshold &&
          pos.dy >= rect.top &&
          pos.dy <= rect.bottom) {
        return 2; // Resize Col
      }
    }
    return 0;
  }

  void handlePanUpdate(
    Offset localPosition,
    double charWidth,
    double lineHeight,
  ) {
    if (isReadOnly) return;
    // A. リサイズ中
    if (_activeHandleIndex != null && selectedDrawingId != null) {
      final index = drawings.indexWhere((d) => d.id == selectedDrawingId);
      if (index != -1) {
        final drawing = drawings[index];

        // パディングによる座標ズレの補正
        // 画面上のハンドル位置(localPosition)から、論理的な枠の位置(points)を逆算する
        double correctionX = 0.0;
        double correctionY = 0.0;

        // 線・Elbow以外（矩形系）で、かつ2点の場合
        if (drawing.type != DrawingType.line &&
            drawing.type != DrawingType.elbow &&
            drawing.points.length == 2) {
          final double padPixelX = drawing.paddingX * charWidth;
          final double padPixelY = drawing.paddingY * lineHeight;
          const double halfHandleSize = 4.0;

          // MemoPainter._drawHandles で使用しているオフセット量
          double offsetX = halfHandleSize + padPixelX;
          double offsetY = halfHandleSize + padPixelY;

          // 対角点（固定されている側の点）の座標を取得
          int otherIndex = (_activeHandleIndex == 0) ? 1 : 0;
          Offset otherPoint = _resolveAnchor(
            drawing.points[otherIndex],
            charWidth,
            lineHeight,
          );

          // マウス位置が対角点に対してどちら側にあるかで補正方向を決定
          // ハンドルは「内側」にあるので、本来の枠は「外側」にある
          if (localPosition.dx < otherPoint.dx) {
            correctionX = -offsetX;
          } else {
            correctionX = offsetX;
          }

          if (localPosition.dy < otherPoint.dy) {
            correctionY = -offsetY;
          } else {
            correctionY = offsetY;
          }
        }

        // グリッドに吸着させる
        int row = ((localPosition.dy + correctionY) / lineHeight).round();
        int visualX = ((localPosition.dx + correctionX) / charWidth).round();

        // 新しい座標を設定 (dx, dyは0にしてグリッドに合わせる)
        final newPoint = _createSnapAnchor(max(0, row), visualX, dy: 0.0);
        drawings[index].points[_activeHandleIndex!] = newPoint;

        notifyListeners();
      }
      return;
    }

    // B. テーブル罫線移動中
    if (_activeTableDividerIndex != null && selectedDrawingId != null) {
      final index = drawings.indexWhere((d) => d.id == selectedDrawingId);
      if (index != -1) {
        final drawing = drawings[index];
        final points = drawing.points
            .map((p) => _resolveAnchor(p, charWidth, lineHeight))
            .toList();
        final rect = Rect.fromPoints(points[0], points[1]);

        if (_activeTableDividerIsRow) {
          // 横線移動
          double newY = localPosition.dy;
          // グリッドスナップ
          newY = (newY / lineHeight).round() * lineHeight;

          // 範囲制限 (前の線 < 自分 < 次の線)
          double minRatio = 0.0;
          if (_activeTableDividerIndex! > 0) {
            minRatio = drawing.tableRowPositions[_activeTableDividerIndex! - 1];
          }
          double maxRatio = 1.0;
          if (_activeTableDividerIndex! <
              drawing.tableRowPositions.length - 1) {
            maxRatio = drawing.tableRowPositions[_activeTableDividerIndex! + 1];
          }

          double newRatio = (newY - rect.top) / rect.height;
          // 少し余裕を持たせる (0.01)
          newRatio = newRatio.clamp(minRatio + 0.01, maxRatio - 0.01);
          drawing.tableRowPositions[_activeTableDividerIndex!] = newRatio;
        } else {
          // 縦線移動
          double newX = localPosition.dx;
          newX = (newX / charWidth).round() * charWidth;

          double minRatio = 0.0;
          if (_activeTableDividerIndex! > 0) {
            minRatio = drawing.tableColPositions[_activeTableDividerIndex! - 1];
          }
          double maxRatio = 1.0;
          if (_activeTableDividerIndex! <
              drawing.tableColPositions.length - 1) {
            maxRatio = drawing.tableColPositions[_activeTableDividerIndex! + 1];
          }

          double newRatio = (newX - rect.left) / rect.width;
          newRatio = newRatio.clamp(minRatio + 0.01, maxRatio - 0.01);
          drawing.tableColPositions[_activeTableDividerIndex!] = newRatio;
        }
        notifyListeners();
      }
      return;
    }

    // C. 移動中
    if (_isMovingDrawing &&
        selectedDrawingId != null &&
        _initialDrawingPoints != null) {
      final index = drawings.indexWhere((d) => d.id == selectedDrawingId);
      if (index != -1) {
        int currentRow = (localPosition.dy / lineHeight).floor();
        int currentVisualX = (localPosition.dx / charWidth).round();

        int deltaRow = currentRow - _dragStartRow!;
        int deltaVisualX = currentVisualX - _dragStartCol!;

        // 初期座標に差分を加えて更新
        for (int i = 0; i < drawings[index].points.length; i++) {
          final initial = _initialDrawingPoints![i];
          final current = drawings[index].points[i];

          // 1. 新しい行を計算
          int newRow = max(0, initial.row + deltaRow);
          current.row = newRow;

          // 2. 初期のVisualX(見た目の位置)を計算
          int initialVisualX = calcVisualX(initial.row, initial.col);

          // 3. 新しいVisualXを計算
          int targetVisualX = max(0, initialVisualX + deltaVisualX);

          // 4. 新しい行のテキストに合わせて col (文字インデックス) を逆算
          // これにより、全角/半角が混在していても見た目の位置・サイズが維持される
          current.col = _getColFromVisualXInRow(newRow, targetVisualX);

          // dx, dy (相対位置) は初期値を維持してズレを防ぐ
          current.dx = initial.dx;
          current.dy = initial.dy;
        }
        notifyListeners();
      }
      return;
    }

    // D. テキスト選択中
    handleTap(localPosition, charWidth, lineHeight);
  }

  // 指定行におけるVisualXからcolを逆算するヘルパー (虚空対応版)
  int _getColFromVisualXInRow(int row, int targetVisualX) {
    String line = "";
    if (row < lines.length) {
      line = lines[row];
    }
    int lineVisualWidth = TextUtils.calcTextWidth(line);
    
    if (targetVisualX <= lineVisualWidth) {
      return TextUtils.getColFromVisualX(line, targetVisualX);
    } else {
      // 行末より右（虚空）の場合は、差分をそのまま加算
      return line.length + (targetVisualX - lineVisualWidth);
    }
  }

  void handlePanEnd() {
    if (_activeHandleIndex != null ||
        _isMovingDrawing ||
        _activeTableDividerIndex != null) {
      saveHistory(); // 操作完了時に履歴保存
      _activeHandleIndex = null;
      _isMovingDrawing = false;
      _initialDrawingPoints = null;
      _dragStartRow = null;
      _dragStartCol = null;
      _activeTableDividerIndex = null;
    }
  }

  void updateComposingText(String text, {TextRange selection = TextRange.empty}) {
    composingText = text;
    composingSelection = selection;
    notifyListeners();
  }

  void input(String text) {
    if (isReadOnly) return;
    if (text.isEmpty) return;

    saveHistory();

    if (isRectangularSelection && selectionOriginRow != null) {
      replaceRectangularSelection(text);
    } else {
      deleteSelection();
      insertText(text);
    }
  }

  // --- File I/O ---
  Future<void> loadFromFile(String path, {String? encoding}) async {
    try {
      final bytes = await FileIOHelper.instance.readFileAsBytes(path);
      String content;

      if (encoding != null) {
        // 指定されたエンコーディングで読み込む
        currentEncoding = encoding;
        if (currentEncoding.toLowerCase() == 'utf-8') {
          content = utf8.decode(bytes);
        } else {
          content = await CharsetConverter.decode(currentEncoding, bytes);
        }
      } else {
        // 自動判別（簡易）: UTF-8 で試してダメなら Shift_JIS (CP932)
        try {
          content = utf8.decode(bytes);
          currentEncoding = 'utf-8';
        } catch (_) {
          currentEncoding = 'shift_jis';
          content = await CharsetConverter.decode(currentEncoding, bytes);
        }
      }

      // 図形データの読み込み
      drawings = []; // 初期化
      final drawFilePath = _getDrawFilePath(path);
      if (await FileIOHelper.instance.fileExists(drawFilePath)) {
        try {
          final jsonString = await FileIOHelper.instance.readFileAsString(drawFilePath);
          final List<dynamic> jsonList = jsonDecode(jsonString);
          drawings = jsonList
              .map((e) => DrawingObject.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (e) {
          debugPrint('Error loading drawing data: $e');
        }
      }

      saveHistory();
      currentFilePath = path;

      if (content.contains('\r\n')) {
        newLineType = NewLineType.crlf;
      } else if (content.contains('\r')) {
        newLineType = NewLineType.cr;
      } else {
        newLineType = NewLineType.lf;
      }

      content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      lines = content.split('\n');
      if (lines.isEmpty) {
        lines = [''];
      }
      cursorRow = 0;
      cursorCol = 0;
      preferredVisualX = 0;
      selectionOriginRow = null;
      isDirty = false;
      selectionOriginCol = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error opening file: $e');
    }
  }

  Future<String?> saveFile() async {
    if (currentFilePath == null) {
      return await saveAsFile();
    }
    try {
      String separator;
      switch (newLineType) {
        case NewLineType.crlf:
          separator = '\r\n';
          break;
        case NewLineType.cr:
          separator = '\r';
          break;
        case NewLineType.lf:
        default:
          separator = '\n';
      }
      String content = lines.join(separator);
      List<int> encodedBytes;
      if (currentEncoding.toLowerCase() == 'utf-8') {
        encodedBytes = utf8.encode(content);
      } else {
        encodedBytes = await CharsetConverter.encode(currentEncoding, content);
      }
      await FileIOHelper.instance.writeBytesToFile(currentFilePath!, encodedBytes);

      // 図形データの保存
      await _saveDrawings(currentFilePath!);

      isDirty = false;
      notifyListeners();
      return currentFilePath;
    } catch (e) {
      debugPrint('Error saving file: $e');
      return null;
    }
  }

  Future<String?> saveAsFile() async {
    try {
      String? outputFile = await FileIOHelper.instance.saveFilePath(
        initialFileName: displayName,
      );
      if (outputFile != null) {
        currentFilePath = outputFile;
        String separator;
        switch (newLineType) {
          case NewLineType.crlf:
            separator = '\r\n';
            break;
          case NewLineType.cr:
            separator = '\r';
            break;
          case NewLineType.lf:
          default:
            separator = '\n';
        }
        String content = lines.join(separator);
        List<int> encodedBytes;
        if (currentEncoding.toLowerCase() == 'utf-8') {
          encodedBytes = utf8.encode(content);
        } else {
          encodedBytes = await CharsetConverter.encode(
            currentEncoding,
            content,
          );
        }
        await FileIOHelper.instance.writeBytesToFile(outputFile, encodedBytes);

        // 図形データの保存
        await _saveDrawings(outputFile);

        isDirty = false;
        notifyListeners();
        return outputFile;
      }
    } catch (e) {
      debugPrint('Error saving file: $e');
    }
    return null;
  }

  // 図形ファイルパスの生成 (拡張子を _draw.json に置換)
  String _getDrawFilePath(String txtPath) {
    final dotIndex = txtPath.lastIndexOf('.');
    if (dotIndex != -1) {
      return '${txtPath.substring(0, dotIndex)}_draw.json';
    }
    return '${txtPath}_draw.json';
  }

  // 図形保存のヘルパーメソッド
  Future<void> _saveDrawings(String txtPath) async {
    final drawFilePath = _getDrawFilePath(txtPath);
    if (drawings.isNotEmpty) {
      try {
        final jsonList = drawings.map((d) => d.toJson()).toList();
        final jsonString = jsonEncode(jsonList);
        await FileIOHelper.instance.writeStringToFile(drawFilePath, jsonString);
      } catch (e) {
        debugPrint('Error saving drawing data: $e');
      }
    } else {
      // 図形がない場合、古いファイルがあれば削除する（ゴミを残さない）
      if (await FileIOHelper.instance.fileExists(drawFilePath)) {
        try {
          await FileIOHelper.instance.deleteFile(drawFilePath);
        } catch (e) {
          debugPrint('Error deleting drawing file: $e');
        }
      }
    }
  }
}
