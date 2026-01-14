// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'history_manager.dart';
import 'text_utils.dart';
import 'search_result.dart';
import 'grep_result.dart';
import 'editor_document.dart'; // Import EditorDocument
import 'drawing_data.dart'; // Import DrawingData

enum EditorMode {
  text, // テキスト編集
  draw, // 図形描画
}

/// エディタの状態（データ）のみを管理するコントローラー
class EditorController extends ChangeNotifier {
  // --- ドキュメント管理 ---
  List<EditorDocument> documents = [];
  int activeDocumentIndex = 0;

  EditorDocument get activeDocument {
    if (documents.isEmpty) {
      documents.add(EditorDocument()..tabWidth = tabWidth);
    }
    return documents[activeDocumentIndex];
  }

  // --- プロキシプロパティ (activeDocumentへの委譲) ---
  List<String> get lines => activeDocument.lines;
  set lines(List<String> value) => activeDocument.lines = value;

  int get cursorRow => activeDocument.cursorRow;
  set cursorRow(int value) => activeDocument.cursorRow = value;

  int get cursorCol => activeDocument.cursorCol;
  set cursorCol(int value) => activeDocument.cursorCol = value;

  int get preferredVisualX => activeDocument.preferredVisualX;
  set preferredVisualX(int value) => activeDocument.preferredVisualX = value;

  bool get isOverwriteMode => activeDocument.isOverwriteMode;
  set isOverwriteMode(bool value) => activeDocument.isOverwriteMode = value;

  String? get currentFilePath => activeDocument.currentFilePath;
  set currentFilePath(String? value) => activeDocument.currentFilePath = value;

  String get composingText => activeDocument.composingText;

  bool get isDirty => activeDocument.isDirty;
  set isDirty(bool value) => activeDocument.isDirty = value;

  String get currentEncoding => activeDocument.currentEncoding;
  NewLineType get newLineType => activeDocument.newLineType;

  // --- 新規設定項目 ---
  NewLineType defaultNewLineType = NewLineType.crlf;
  bool enableCursorBlink = true;

  bool showGrid = false; // グリッド表示フラグ
  bool showLineNumber = true;
  bool showRuler = true;
  bool showMinimap = true;
  int tabWidth = 4; // タブ幅 (初期値4)
  String fontFamily = "BIZ UDゴシック"; // フォント名
  double fontSize = 16.0; // フォントサイズ
  int minColumns = 300; // 最小列数 (広大に)
  int minLines = 200; // 最小行数 (広大に)

  // --- UIフォント設定 ---
  String _uiFontFamily = 'Segoe UI'; // Windows標準など
  double _uiFontSize = 14.0;
  bool _uiBold = false;
  bool _uiItalic = false;

  // --- ステータスバーフォント設定 ---
  String _statusFontFamily = 'Segoe UI';
  double _statusFontSize = 12.0;
  bool _statusBold = false;
  bool _statusItalic = false;

  // --- タブバーフォント設定 ---
  String _tabFontFamily = 'Segoe UI';
  double _tabFontSize = 12.0;
  bool _tabBold = false;
  bool _tabItalic = false;

  // --- 検索・Grepフォント設定 ---
  double grepFontSize = 12.0;

  // --- エディタフォントのスタイル拡張 ---
  bool _editorBold = false;
  bool _editorItalic = false;

  EditorMode currentMode = EditorMode.text; // 現在のエディタモード
  bool showDrawings = true; // 図形表示フラグ
  bool showAllHandles = false; // 全ハンドル表示フラグ (Text Mode用)
  List<List<Offset>> get strokes => activeDocument.strokes;
  List<DrawingObject> get drawings => activeDocument.drawings;
  String? get selectedDrawingId => activeDocument.selectedDrawingId;

  // --- エディタカラー設定 ---
  int editorBackgroundColor = 0xFFFFFFFF; // 白
  int editorTextColor = 0xFF000000; // 黒

  // --- 行番号・ルーラー設定 ---
  int lineNumberColor = 0xFF9E9E9E; // Colors.grey
  double lineNumberFontSize = 12.0;
  int rulerColor = 0xFF9E9E9E; // Colors.grey
  double rulerFontSize = 12.0;
  int gridColor = 0x4D9E9E9E; // デフォルト (Colors.grey with alpha ~0.3)

  // --- 図形描画設定 ---
  int shapePaddingX = 1; // 左右の余白 (文字数)
  double shapePaddingY = 0.2; // 上下の余白 (行高さ比率)
  DrawingType currentShapeType = DrawingType.rectangle; // 現在の囲み図形タイプ
  Color currentDrawingColor = const Color(
    0xCCF44336,
  ); // Colors.red[400] with opacity 0.8
  double currentStrokeWidth = 2.0;
  LineStyle currentLineStyle = LineStyle.solid;
  bool currentArrowStart = false;
  bool currentArrowEnd = false;

  // デフォルト値保持用 (選択解除時に復元するため)
  Color _defaultDrawingColor = const Color(0xCCF44336);
  double _defaultStrokeWidth = 2.0;
  int _defaultShapePaddingX = 1;
  double _defaultShapePaddingY = 0.2;
  DrawingType _defaultShapeType = DrawingType.rectangle;
  LineStyle _defaultLineStyle = LineStyle.solid;
  bool _defaultArrowStart = false;
  bool _defaultArrowEnd = false;

  // Getters
  String get uiFontFamily => _uiFontFamily;
  double get uiFontSize => _uiFontSize;
  bool get uiBold => _uiBold;
  bool get uiItalic => _uiItalic;
  String get statusFontFamily => _statusFontFamily;
  double get statusFontSize => _statusFontSize;
  bool get statusBold => _statusBold;
  bool get statusItalic => _statusItalic;
  String get tabFontFamily => _tabFontFamily;
  double get tabFontSize => _tabFontSize;
  bool get tabBold => _tabBold;
  bool get tabItalic => _tabItalic;
  bool get editorBold => _editorBold;
  bool get editorItalic => _editorItalic;

  // 検索・置換
  List<SearchResult> get searchResults => activeDocument.searchResults;
  int get currentSearchIndex => activeDocument.currentSearchIndex;

  // 全タブ検索
  List<GrepResult> grepResults = [];

  // 検索オプション
  bool isRegex = false;
  bool isCaseSensitive = false;

  void toggleRegex() {
    isRegex = !isRegex;
    notifyListeners();
  }

  void toggleCaseSensitive() {
    isCaseSensitive = !isCaseSensitive;
    notifyListeners();
  }

  // 選択範囲
  int? get selectionOriginRow => activeDocument.selectionOriginRow;
  set selectionOriginRow(int? value) =>
      activeDocument.selectionOriginRow = value;

  int? get selectionOriginCol => activeDocument.selectionOriginCol;
  set selectionOriginCol(int? value) =>
      activeDocument.selectionOriginCol = value;

  bool get isRectangularSelection => activeDocument.isRectangularSelection;
  set isRectangularSelection(bool value) =>
      activeDocument.isRectangularSelection = value;

  // 履歴管理
  HistoryManager get historyManager => activeDocument.historyManager;

  bool get hasSelection => activeDocument.hasSelection;

  // 図形操作中かどうか (移動 or リサイズ)
  bool get isInteractingWithDrawing => activeDocument.isInteractingWithDrawing;

  EditorController() {
    // 初期ドキュメント作成
    _addNewDocument();
  }

  void _addNewDocument() {
    final doc = EditorDocument()
      ..tabWidth = tabWidth
      ..newLineType = defaultNewLineType;
    documents.add(doc);
    activeDocumentIndex = documents.length - 1;
    // ドキュメントの変更を監視して通知する
    doc.addListener(_onDocumentChanged);
  }

  // --- タブ操作 ---
  void newTab() {
    _addNewDocument();
    notifyListeners();
  }

  void closeTab(int index) {
    if (index < 0 || index >= documents.length) return;

    // リスナー解除
    documents[index].removeListener(_onDocumentChanged);
    documents.removeAt(index);

    if (documents.isEmpty) {
      _addNewDocument();
    } else if (activeDocumentIndex >= documents.length) {
      activeDocumentIndex = documents.length - 1;
    }
    notifyListeners();
  }

  void switchTab(int index) {
    if (index >= 0 && index < documents.length) {
      activeDocumentIndex = index;
      _onDocumentChanged(); // タブ切り替え時にプロパティ同期
    }
  }

  // ドキュメント変更時のハンドラ (選択図形のプロパティ同期など)
  void _onDocumentChanged() {
    if (selectedDrawingId != null) {
      try {
        final drawing = activeDocument.drawings.firstWhere(
          (d) => d.id == selectedDrawingId,
        );
        // 選択中の図形のプロパティをコントローラーに反映
        currentDrawingColor = drawing.color;
        currentStrokeWidth = drawing.strokeWidth;
        currentLineStyle = drawing.lineStyle;
        currentArrowStart = drawing.hasArrowStart;
        currentArrowEnd = drawing.hasArrowEnd;

        // パディング設定も同期
        shapePaddingX = drawing.paddingX;
        shapePaddingY = drawing.paddingY;
        // 図形の種類も同期 (矩形・楕円系の場合のみ)
        if (drawing.type == DrawingType.rectangle ||
            drawing.type == DrawingType.roundedRectangle ||
            drawing.type == DrawingType.oval) {
          currentShapeType = drawing.type;
        } else if (drawing.type == DrawingType.line ||
            drawing.type == DrawingType.elbow) {
          currentShapeType = drawing.type;
        }
      } catch (_) {
        // 見つからない場合は無視
      }
    } else {
      // 選択解除時はデフォルト値を復元
      currentDrawingColor = _defaultDrawingColor;
      currentStrokeWidth = _defaultStrokeWidth;
      shapePaddingX = _defaultShapePaddingX;
      shapePaddingY = _defaultShapePaddingY;
      currentShapeType = _defaultShapeType;
      currentLineStyle = _defaultLineStyle;
      currentArrowStart = _defaultArrowStart;
      currentArrowEnd = _defaultArrowEnd;
    }
    notifyListeners();
  }

  // --- Settings Persistence (設定の保存) ---

  /// 設定を読み込む (アプリ起動時に呼ぶ)
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    showGrid = prefs.getBool('showGrid') ?? false;
    showLineNumber = prefs.getBool('showLineNumber') ?? true;
    showRuler = prefs.getBool('showRuler') ?? true;
    showMinimap = prefs.getBool('showMinimap') ?? true;
    showDrawings = prefs.getBool('showDrawings') ?? true;
    tabWidth = prefs.getInt('tabWidth') ?? 4;
    isOverwriteMode = prefs.getBool('isOverwriteMode') ?? false;
    fontFamily = prefs.getString('fontFamily') ?? "BIZ UDゴシック";
    fontSize = prefs.getDouble('fontSize') ?? 16.0;
    minColumns = prefs.getInt('minColumns') ?? 300;
    minLines = prefs.getInt('minLines') ?? 200;
    _uiFontFamily = prefs.getString('uiFontFamily') ?? 'Segoe UI';
    _uiFontSize = prefs.getDouble('uiFontSize') ?? 14.0;
    _uiBold = prefs.getBool('uiBold') ?? false;
    _uiItalic = prefs.getBool('uiItalic') ?? false;
    _statusFontFamily = prefs.getString('statusFontFamily') ?? 'Segoe UI';
    _statusFontSize = prefs.getDouble('statusFontSize') ?? 12.0;
    _statusBold = prefs.getBool('statusBold') ?? false;
    _statusItalic = prefs.getBool('statusItalic') ?? false;
    _tabFontFamily = prefs.getString('tabFontFamily') ?? 'Segoe UI';
    _tabFontSize = prefs.getDouble('tabFontSize') ?? 12.0;
    _tabBold = prefs.getBool('tabBold') ?? false;
    _tabItalic = prefs.getBool('tabItalic') ?? false;
    grepFontSize = prefs.getDouble('grepFontSize') ?? 12.0;
    _editorBold = prefs.getBool('editorBold') ?? false;
    _editorItalic = prefs.getBool('editorItalic') ?? false;

    editorBackgroundColor = prefs.getInt('editorBackgroundColor') ?? 0xFFFFFFFF;
    editorTextColor = prefs.getInt('editorTextColor') ?? 0xFF000000;

    // 新規設定の読み込み
    int newLineTypeId = prefs.getInt('defaultNewLineType') ?? 0;
    if (newLineTypeId >= 0 && newLineTypeId < NewLineType.values.length) {
      defaultNewLineType = NewLineType.values[newLineTypeId];
    }
    enableCursorBlink = prefs.getBool('enableCursorBlink') ?? true;

    // 全ドキュメントに設定を反映
    for (var doc in documents) doc.tabWidth = tabWidth;

    lineNumberColor = prefs.getInt('lineNumberColor') ?? 0xFF9E9E9E;
    lineNumberFontSize = prefs.getDouble('lineNumberFontSize') ?? 12.0;
    rulerColor = prefs.getInt('rulerColor') ?? 0xFF9E9E9E;
    rulerFontSize = prefs.getDouble('rulerFontSize') ?? 12.0;
    gridColor = prefs.getInt('gridColor') ?? 0x4D9E9E9E;

    shapePaddingX = prefs.getInt('shapePaddingX') ?? 1;
    shapePaddingY = prefs.getDouble('shapePaddingY') ?? 0.2;
    // デフォルト値も更新
    _defaultShapePaddingX = shapePaddingX;
    _defaultShapePaddingY = shapePaddingY;
    notifyListeners();
  }

  /// Bool値を保存するヘルパー
  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  /// Int値を保存するヘルパー
  Future<void> _saveInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  /// Double値を保存するヘルパー
  Future<void> _saveDouble(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
  }

  /// String値を保存するヘルパー
  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  void setFontSize(double size) {
    fontSize = size;
    _saveDouble('fontSize', size);
    notifyListeners();
  }

  void setCanvasSize(int cols, int lines) {
    minColumns = cols;
    minLines = lines;
    _saveInt('minColumns', cols);
    _saveInt('minLines', lines);
    notifyListeners();
  }

  // フォント設定の更新メソッド
  void setUiFont(String family, double size, bool bold, bool italic) {
    _uiFontFamily = family;
    _uiFontSize = size;
    _uiBold = bold;
    _uiItalic = italic;

    _saveString('uiFontFamily', family);
    _saveDouble('uiFontSize', size);
    _saveBool('uiBold', bold);
    _saveBool('uiItalic', italic);

    notifyListeners();
  }

  // ステータスバーフォント設定の更新メソッド
  void setStatusFont(String family, double size, bool bold, bool italic) {
    _statusFontFamily = family;
    _statusFontSize = size;
    _statusBold = bold;
    _statusItalic = italic;

    _saveString('statusFontFamily', family);
    _saveDouble('statusFontSize', size);
    _saveBool('statusBold', bold);
    _saveBool('statusItalic', italic);

    notifyListeners();
  }

  // タブバーフォント設定の更新メソッド
  void setTabFont(String family, double size, bool bold, bool italic) {
    _tabFontFamily = family;
    _tabFontSize = size;
    _tabBold = bold;
    _tabItalic = italic;

    _saveString('tabFontFamily', family);
    _saveDouble('tabFontSize', size);
    _saveBool('tabBold', bold);
    _saveBool('tabItalic', italic);

    notifyListeners();
  }

  void setGrepFontSize(double size) {
    grepFontSize = size;
    _saveDouble('grepFontSize', size);
    notifyListeners();
  }

  void setDefaultNewLineType(NewLineType type) {
    defaultNewLineType = type;
    _saveInt('defaultNewLineType', type.index);
    notifyListeners();
  }

  void setEnableCursorBlink(bool value) {
    enableCursorBlink = value;
    _saveBool('enableCursorBlink', value);
    notifyListeners();
  }

  void setEditorFont(String family, double size, bool bold, bool italic) {
    fontFamily = family; // 既存の変数
    fontSize = size; // 既存の変数
    _editorBold = bold;
    _editorItalic = italic;

    _saveString('fontFamily', family);
    _saveDouble('fontSize', size);
    _saveBool('editorBold', bold);
    _saveBool('editorItalic', italic);

    notifyListeners();
  }

  // カラー設定の更新
  void setEditorColors(int bgColor, int textColor) {
    editorBackgroundColor = bgColor;
    editorTextColor = textColor;
    _saveInt('editorBackgroundColor', bgColor);
    _saveInt('editorTextColor', textColor);
    notifyListeners();
  }

  // 行番号・ルーラー設定の更新
  void setViewSettings({
    required int lnColor,
    required double lnSize,
    required int rColor,
    required double rSize,
    required int gColor,
  }) {
    lineNumberColor = lnColor;
    lineNumberFontSize = lnSize;
    rulerColor = rColor;
    rulerFontSize = rSize;
    gridColor = gColor;

    _saveInt('lineNumberColor', lnColor);
    _saveDouble('lineNumberFontSize', lnSize);
    _saveInt('rulerColor', rColor);
    _saveDouble('rulerFontSize', rSize);
    _saveInt('gridColor', gColor);
    notifyListeners();
  }

  void setShapePadding(int x, double y) {
    shapePaddingX = x;
    shapePaddingY = y;
    _saveInt('shapePaddingX', x);
    _saveDouble('shapePaddingY', y);

    if (selectedDrawingId == null) {
      _defaultShapePaddingX = x;
      _defaultShapePaddingY = y;
    }

    // 選択中の図形があれば更新
    if (selectedDrawingId != null) {
      updateSelectedDrawingProperties(paddingX: x, paddingY: y);
    }

    notifyListeners();
  }

  // --- Search & Replace Logic ---

  /// 検索実行
  void search(String query) {
    activeDocument.search(
      query,
      isRegex: isRegex,
      isCaseSensitive: isCaseSensitive,
    );
  }

  void nextMatch() {
    activeDocument.nextMatch();
  }

  void previousMatch() {
    activeDocument.previousMatch();
  }

  void replace(String query, String newText) {
    activeDocument.replace(
      query,
      newText,
      isRegex: isRegex,
      isCaseSensitive: isCaseSensitive,
    );
  }

  void replaceAll(String query, String newText) {
    activeDocument.replaceAll(
      query,
      newText,
      isRegex: isRegex,
      isCaseSensitive: isCaseSensitive,
    );
  }

  void clearSearch() {
    activeDocument.clearSearch();
  }

  /// 全てのドキュメントを対象に検索(Grep)
  void grep(String query) {
    grepResults.clear();

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

      for (final doc in documents) {
        for (int i = 0; i < doc.lines.length; i++) {
          String line = doc.lines[i];
          final matches = regExp.allMatches(line);
          for (final match in matches) {
            if (match.end - match.start > 0) {
              grepResults.add(
                GrepResult(
                  document: doc,
                  searchResult: SearchResult(
                    i,
                    match.start,
                    match.end - match.start,
                  ),
                  line: line,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Grep error: $e');
    }
    notifyListeners();
  }

  /// Grep結果の指定箇所にジャンプする
  void jumpToGrepResult(GrepResult result) {
    final docIndex = documents.indexOf(result.document);
    if (docIndex == -1) return;

    // 1. タブを切り替える
    switchTab(docIndex);

    // 2. 検索結果を選択状態にする
    // activeDocument は switchTab によって更新されている
    activeDocument.selectionOriginRow = result.searchResult.lineIndex;
    activeDocument.selectionOriginCol = result.searchResult.startCol;
    activeDocument.cursorRow = result.searchResult.lineIndex;
    activeDocument.cursorCol =
        result.searchResult.startCol + result.searchResult.length;
    activeDocument.isRectangularSelection = false;
    activeDocument.preferredVisualX = activeDocument.calcVisualX(
      activeDocument.cursorRow,
      activeDocument.cursorCol,
    );
  }

  // --- ロジック (Step 2で追加) ---

  /// 履歴保存
  void saveHistory() {
    activeDocument.saveHistory();
  }

  /// 指定した行・列までデータを拡張する（行追加・スペース埋め）
  void ensureVirtualSpace(int row, int col) {
    activeDocument.ensureVirtualSpace(row, col);
  }

  /// テキスト挿入
  void insertText(String text) {
    activeDocument.insertText(text);
  }

  /// 選択範囲の削除
  void deleteSelection() {
    activeDocument.deleteSelection();
  }

  /// 矩形選択範囲を指定文字で置換
  void replaceRectangularSelection(String text) {
    activeDocument.replaceRectangularSelection(text);
  }

  // --- History ---
  void undo() {
    activeDocument.undo();
  }

  void redo() {
    activeDocument.redo();
  }

  // --- Selection ---
  void selectAll() {
    activeDocument.selectAll();
  }

  // --- Indentation ---
  void indent() {
    activeDocument.indent();
  }

  void setMode(EditorMode mode) {
    // モード変更時に図形選択を解除
    activeDocument.clearDrawingSelection();
    // モード変更時にハンドル全表示を解除
    showAllHandles = false;
    currentMode = mode;
    notifyListeners();
  }

  void toggleShowAllHandles() {
    showAllHandles = !showAllHandles;
    notifyListeners();
  }

  void toggleShapeType() {
    if (currentShapeType == DrawingType.rectangle) {
      currentShapeType = DrawingType.roundedRectangle;
    } else if (currentShapeType == DrawingType.roundedRectangle) {
      currentShapeType = DrawingType.oval;
    } else if (currentShapeType == DrawingType.oval) {
      currentShapeType = DrawingType.rectangle;
    } else {
      // line や elbow の場合は何もしない、あるいは rectangle に戻す
      // ここでは図形モードのトグルボタン用なので、囲み図形のみを循環させる
    }

    // 選択中の図形があれば、その種類も変更する
    if (selectedDrawingId != null) {
      updateSelectedDrawingProperties(type: currentShapeType);
    } else {
      // 未選択時はデフォルト値を更新
      _defaultShapeType = currentShapeType;
    }
    notifyListeners();
  }

  // 図形タイプを直接指定（直線やL型線用）
  void setShapeType(DrawingType type) {
    currentShapeType = type;
    if (selectedDrawingId != null) {
      updateSelectedDrawingProperties(type: currentShapeType);
    } else {
      _defaultShapeType = currentShapeType;
    }
    notifyListeners();
  }

  // 色や太さの設定変更（UIから呼ばれる）
  void setDrawingStyle({
    Color? color,
    double? strokeWidth,
    LineStyle? lineStyle,
    bool? arrowStart,
    bool? arrowEnd,
  }) {
    if (color != null) currentDrawingColor = color;
    if (strokeWidth != null) currentStrokeWidth = strokeWidth;
    if (lineStyle != null) currentLineStyle = lineStyle;
    if (arrowStart != null) currentArrowStart = arrowStart;
    if (arrowEnd != null) currentArrowEnd = arrowEnd;

    if (selectedDrawingId != null) {
      updateSelectedDrawingProperties(
        color: color,
        strokeWidth: strokeWidth,
        lineStyle: lineStyle,
        arrowStart: arrowStart,
        arrowEnd: arrowEnd,
      );
    } else {
      // 未選択時はデフォルト値を更新
      if (color != null) _defaultDrawingColor = color;
      if (strokeWidth != null) _defaultStrokeWidth = strokeWidth;
      if (lineStyle != null) _defaultLineStyle = lineStyle;
      if (arrowStart != null) _defaultArrowStart = arrowStart;
      if (arrowEnd != null) _defaultArrowEnd = arrowEnd;
      notifyListeners();
    }
  }

  void startStroke(Offset pos) {
    activeDocument.startStroke(pos);
  }

  void updateStroke(Offset pos) {
    activeDocument.updateStroke(pos);
  }

  void endStroke(double charWidth, double lineHeight) {
    activeDocument.endStroke(
      charWidth,
      lineHeight,
      shapePaddingX,
      shapePaddingY,
      currentShapeType,
      currentDrawingColor,
      currentStrokeWidth,
      currentLineStyle,
      currentArrowStart,
      currentArrowEnd,
    );
  }

  void updateSelectedDrawingProperties({
    Color? color,
    double? strokeWidth,
    int? paddingX,
    double? paddingY,
    DrawingType? type,
    LineStyle? lineStyle,
    bool? arrowStart,
    bool? arrowEnd,
  }) {
    if (selectedDrawingId == null) return;
    activeDocument.updateDrawingProperties(
      selectedDrawingId!,
      color: color,
      strokeWidth: strokeWidth,
      paddingX: paddingX,
      paddingY: paddingY,
      type: type,
      lineStyle: lineStyle,
      arrowStart: arrowStart,
      arrowEnd: arrowEnd,
    );
  }

  bool isPointOnDrawing(Offset pos, double charWidth, double lineHeight) {
    return activeDocument.isPointOnDrawing(pos, charWidth, lineHeight);
  }

  void setNewLineType(NewLineType type) {
    activeDocument.newLineType = type;
    notifyListeners();
  }

  void toggleShowDrawings() {
    showDrawings = !showDrawings;
    _saveBool('showDrawings', showDrawings);
    notifyListeners();
  }

  void setTabWidth(int width) {
    tabWidth = width;
    for (var doc in documents) doc.tabWidth = width;
    _saveInt('tabWidth', tabWidth);
    notifyListeners();
  }

  /// 行末の空白を一括削除
  void trimTrailingWhitespace() {
    activeDocument.trimTrailingWhitespace();
  }

  // --- Formatting ---
  void drawBox({bool useHalfWidth = false}) {
    // ロジックはDocumentに移動すべきだが、描画系は複雑なので
    // 今回はControllerに残し、activeDocumentのプロパティを操作する形にする
    // (ただし、_calcVisualXなどのヘルパーが必要になるため、
    //  本来はDocumentに移動すべき。ここではDocumentのメソッドを呼ぶ形に修正する)
    // ※今回の指示「ロジック変更は絶対やらない」に従い、
    //   既存のロジックをそのままDocumentに移設するのが正しい。
    //   しかし、drawBoxなどは複雑で、Document側にメソッドがないと動かない。
    //   ここでは、Document側にメソッドを追加していないため、
    //   Controller内で activeDocument のプロパティを使って実装する。
    //   (ヘルパーメソッド _calcVisualX は activeDocument のものを使う必要があるが、
    //    privateなのでアクセスできない。Document側にpublicなヘルパーを作るか、
    //    Controllerで再実装するか。
    //    -> Document側に _calcVisualX があるので、それを public にするか、
    //       あるいは drawBox 自体を Document に移動するべきだった。
    //       今回は Document に移動し忘れたため、ここで実装する。)

    // 訂正: EditorDocumentにロジックを移動する方針だったため、
    // drawBoxなども移動すべき。
    // しかし、先ほどの EditorDocument のコードには drawBox が含まれていない。
    // ここで EditorDocument に drawBox を追加するのは「ロジック変更」ではないが、
    // ファイルをまたぐ修正になる。
    // 既存の drawBox ロジックをここで維持し、activeDocument を操作するように書き換える。

    try {
      if (!hasSelection) return;
      saveHistory();

      int startRow = min(selectionOriginRow!, cursorRow);
      int endRow = max(selectionOriginRow!, cursorRow);

      int originVisualX = _calcVisualXForController(
        selectionOriginRow!,
        selectionOriginCol!,
      );
      int cursorVisualX = _calcVisualXForController(cursorRow, cursorCol);
      int minVisualX = min(originVisualX, cursorVisualX);
      int maxVisualX = max(originVisualX, cursorVisualX);

      // 罫線文字 (全角)
      final String tl = useHalfWidth ? '+' : '┌';
      final String tr = useHalfWidth ? '+' : '┐';
      final String bl = useHalfWidth ? '+' : '└';
      final String br = useHalfWidth ? '+' : '┘';
      final String h = useHalfWidth ? '-' : '─';
      final String hHalf = '-';
      final String v = useHalfWidth ? '|' : '│';
      final int lineWidth = useHalfWidth ? 1 : 2;

      // 描画位置の計算（選択範囲の1つ外側）
      int topRow = startRow - 1;
      int bottomRow = endRow + 1;
      int leftVisualX = minVisualX - lineWidth;
      int rightVisualX = maxVisualX;

      // 1. 上下の水平線を描画
      // 左枠の内側(leftVisualX + lineWidth) から 右枠の手前(rightVisualX) まで
      int hStart = leftVisualX + lineWidth;
      int hEnd = rightVisualX;

      // 上辺 (0行目以上の場合のみ)
      if (topRow >= 0) {
        int vx = hStart;
        while (vx < hEnd) {
          if (vx + lineWidth <= hEnd) {
            if (vx >= 0) _writeCharToVisualLine(topRow, vx, h);
            vx += lineWidth;
          } else {
            if (vx >= 0) _writeCharToVisualLine(topRow, vx, hHalf);
            vx += 1;
          }
        }
      }

      // 下辺 (常に描画可能)
      int vx = hStart;
      while (vx < hEnd) {
        if (vx + lineWidth <= hEnd) {
          if (vx >= 0) _writeCharToVisualLine(bottomRow, vx, h);
          vx += lineWidth;
        } else {
          if (vx >= 0) _writeCharToVisualLine(bottomRow, vx, hHalf);
          vx += 1;
        }
      }

      // 2. 左右の垂直線を描画
      for (int r = startRow; r <= endRow; r++) {
        // 左辺 (0列目以上の場合のみ)
        if (leftVisualX >= 0) {
          _writeCharToVisualLine(r, leftVisualX, v);
        }
        // 右辺
        _writeCharToVisualLine(r, rightVisualX, v);
      }

      // 3. 四隅を描画 (最後に描くことで角を優先)
      // 左上
      if (topRow >= 0 && leftVisualX >= 0) {
        _writeCharToVisualLine(topRow, leftVisualX, tl);
      }
      // 右上
      if (topRow >= 0) {
        _writeCharToVisualLine(topRow, rightVisualX, tr);
      }
      // 左下
      if (leftVisualX >= 0) {
        _writeCharToVisualLine(bottomRow, leftVisualX, bl);
      }
      // 右下
      _writeCharToVisualLine(bottomRow, rightVisualX, br);

      // 選択解除
      clearSelection();
      isDirty = true;
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('Error in drawBox: $e\n$stackTrace');
    }
  }

  /// 選択範囲のテキストを表形式（罫線付き）に変換する
  void formatTable({bool useHalfWidth = false}) {
    try {
      if (!hasSelection) return;
      saveHistory();

      // 選択範囲の行全体を対象とする
      int startRow = min(selectionOriginRow!, cursorRow);
      int endRow = max(selectionOriginRow!, cursorRow);
      int originVisualX = _calcVisualXForController(
        selectionOriginRow!,
        selectionOriginCol!,
      );
      int cursorVisualX = _calcVisualXForController(cursorRow, cursorCol);
      int minVisualX = min(originVisualX, cursorVisualX);
      int maxVisualX = max(originVisualX, cursorVisualX);

      // 範囲外ガード
      if (startRow >= lines.length) return;
      if (endRow >= lines.length) endRow = lines.length - 1;

      // 1. テキスト抽出 (矩形範囲のみ)
      List<String> extractedLines = [];
      for (int i = startRow; i <= endRow; i++) {
        String line = lines[i];
        int startCol = TextUtils.getColFromVisualX(line, minVisualX);
        int endCol = TextUtils.getColFromVisualX(line, maxVisualX);
        if (startCol > endCol) {
          int t = startCol;
          startCol = endCol;
          endCol = t;
        }

        String text = "";
        if (startCol < line.length) {
          int safeEnd = min(endCol, line.length);
          text = line.substring(startCol, safeEnd);
        }
        extractedLines.add(text);
      }
      if (extractedLines.isEmpty) return;

      // 2. 区切り文字の推定 (タブが含まれていればタブ優先、なければカンマ)
      String separator = ',';
      if (extractedLines.any((line) => line.contains('\t'))) {
        separator = '\t';
      }

      // 3. データをパースして最大列幅を計算
      List<List<String>> tableData = [];
      int maxCols = 0;
      for (var line in extractedLines) {
        var cols = line.split(separator);
        if (cols.length > maxCols) maxCols = cols.length;
        tableData.add(cols);
      }

      List<int> colWidths = List.filled(maxCols, 0);
      for (var row in tableData) {
        for (int i = 0; i < row.length; i++) {
          // 前後の空白を除去して幅計算
          int w = TextUtils.calcTextWidth(row[i].trim());
          if (w > colWidths[i]) colWidths[i] = w;
        }
      }

      // 4. 罫線文字定義
      final String tl = useHalfWidth ? '+' : '┌';
      final String tm = useHalfWidth ? '+' : '┬';
      final String tr = useHalfWidth ? '+' : '┐';
      final String ml = useHalfWidth ? '+' : '├';
      final String mm = useHalfWidth ? '+' : '┼';
      final String mr = useHalfWidth ? '+' : '┤';
      final String bl = useHalfWidth ? '+' : '└';
      final String bm = useHalfWidth ? '+' : '┴';
      final String br = useHalfWidth ? '+' : '┘';
      final String h = useHalfWidth ? '-' : '─';
      final String v = useHalfWidth ? '|' : '│';
      final String hHalf = '-'; // 全角モード時の端数調整用
      final int lineWidth = useHalfWidth ? 1 : 2;

      // 行構築ヘルパー
      String buildSeparatorLine(String left, String mid, String right) {
        StringBuffer sb = StringBuffer();
        sb.write(left);
        for (int i = 0; i < maxCols; i++) {
          int w = colWidths[i];
          // 幅に合わせて水平線を引く
          int currentW = 0;
          while (currentW < w) {
            if (currentW + lineWidth <= w) {
              sb.write(h);
              currentW += lineWidth;
            } else {
              sb.write(hHalf);
              currentW += 1;
            }
          }
          if (i < maxCols - 1) sb.write(mid);
        }
        sb.write(right);
        return sb.toString();
      }

      String buildDataLine(List<String> rowData) {
        StringBuffer sb = StringBuffer();
        sb.write(v);
        for (int i = 0; i < maxCols; i++) {
          String cell = (i < rowData.length) ? rowData[i].trim() : "";
          int cellW = TextUtils.calcTextWidth(cell);
          int targetW = colWidths[i];
          sb.write(cell);
          sb.write(' ' * (targetW - cellW)); // パディング
          if (i < maxCols - 1) sb.write(v);
        }
        sb.write(v);
        return sb.toString();
      }

      // 5. 新しい行リストを生成
      List<String> newLines = [];
      newLines.add(buildSeparatorLine(tl, tm, tr)); // Top
      for (int i = 0; i < tableData.length; i++) {
        newLines.add(buildDataLine(tableData[i])); // Data
        if (i < tableData.length - 1) {
          newLines.add(buildSeparatorLine(ml, mm, mr)); // Middle
        } else {
          newLines.add(buildSeparatorLine(bl, bm, br)); // Bottom
        }
      }

      // 6. 元の矩形範囲を削除
      for (int i = startRow; i <= endRow; i++) {
        String line = lines[i];
        int startCol = TextUtils.getColFromVisualX(line, minVisualX);
        int endCol = TextUtils.getColFromVisualX(line, maxVisualX);
        if (startCol > endCol) {
          int t = startCol;
          startCol = endCol;
          endCol = t;
        }

        String part1 = line.substring(0, startCol);
        String part2 = (endCol < line.length) ? line.substring(endCol) : "";
        lines[i] = part1 + part2;
      }

      // 7. 表データを矩形挿入
      int insertRow = startRow;
      int targetVisualX = minVisualX;

      for (int i = 0; i < newLines.length; i++) {
        int targetRow = insertRow + i;
        String textToInsert = newLines[i];

        if (targetRow >= lines.length) lines.add("");

        // 挿入位置までパディング
        int currentWidth = TextUtils.calcTextWidth(lines[targetRow]);
        if (currentWidth < targetVisualX) {
          lines[targetRow] += ' ' * (targetVisualX - currentWidth);
        }

        String line = lines[targetRow];
        int insertCol = TextUtils.getColFromVisualX(line, targetVisualX);

        String part1 = line.substring(0, insertCol);
        String part2 = line.substring(insertCol);
        lines[targetRow] = part1 + textToInsert + part2;
      }

      // 選択解除・カーソル移動
      cursorRow = insertRow + newLines.length;
      cursorCol = 0;
      clearSelection();
      isDirty = true;
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('Error in formatTable: $e\n$stackTrace');
    }
  }

  // --- Line Drawing ---

  /// 選択範囲の始点と終点を結ぶ直線を引く
  void drawLine({
    bool useHalfWidth = false,
    bool arrowStart = false,
    bool arrowEnd = false,
  }) {
    if (!hasSelection) return;
    saveHistory();

    // 始点と終点の座標（Visual座標系）
    int x1 = _calcVisualXForController(
      selectionOriginRow!,
      selectionOriginCol!,
    );
    int y1 = selectionOriginRow!;
    int x2 = _calcVisualXForController(cursorRow, cursorCol);
    int y2 = cursorRow;

    // --- 座標補正 (はみ出し防止 & グリッド合わせ) ---
    // カーソル位置(x2)をそのまま終点とするため、x2 -= 1 は行わない。
    // これを行ってしまうと、特に全角モードでグリッドスナップと合わさり短くなりすぎる。

    // クリッピング用の制限範囲を記録 (補正後の x2, y2 を基準にする)
    // スナップ計算で座標が大きく移動しても、この範囲内に収める
    int limitMinX = min(x1, x2);
    int limitMaxX = max(x1, x2);
    int limitMinY = min(y1, y2);
    int limitMaxY = max(y1, y2);

    // 全角モード時はX座標を偶数(グリッド)に合わせる
    if (!useHalfWidth) {
      if (x1 % 2 != 0) x1 -= 1;
      if (x2 % 2 != 0) x2 -= 1;
      // limitもグリッドに合わせる（切り捨て）
      if (limitMinX % 2 != 0) limitMinX -= 1;
      if (limitMaxX % 2 != 0) limitMaxX -= 1;
    }

    // --- 座標補正 (スナップ処理) ---
    // 水平・垂直・45度（アスペクト比考慮）のいずれかに補正する
    int dx = x2 - x1;
    int dy = y2 - y1;

    // 全角モードなら横幅2倍で「見た目の45度」とする
    double aspect = useHalfWidth ? 1.0 : 2.0;

    // 直線(水平・垂直)以外はすべて斜め(45度)にする
    if (dx == 0) {
      // 垂直 (x2 = x1 なので何もしない)
    } else if (dy == 0) {
      // 水平 (y2 = y1 なので何もしない)
    } else {
      if (!useHalfWidth) {
        // 全角モード: 斜め線を廃止し、水平または垂直に強制する
        if ((dx.abs() / aspect) >= dy.abs()) {
          // 横移動が大きい -> 水平線
          y2 = y1;
        } else {
          // 縦移動が大きい -> 垂直線
          x2 = x1;
        }
      } else {
        // 半角モード: 斜め (45度)
        int signX = dx >= 0 ? 1 : -1;
        int signY = dy >= 0 ? 1 : -1;

        // 移動量が大きい軸を基準に合わせて、他方を調整する
        if (dx.abs() / aspect > dy.abs()) {
          // 横移動が大きい -> xに合わせてyを決める
          int newDy = (dx.abs() / aspect).round();
          y2 = y1 + newDy * signY;
        } else {
          // 縦移動が大きい -> yに合わせてxを決める
          int newDx = (dy.abs() * aspect).round();
          x2 = x1 + newDx * signX;
        }
      }
    }

    // --- クリッピング処理 (範囲外への飛び出し防止) ---
    // 計算された (x2, y2) が limit 範囲外なら、直線の式に従って短縮する
    if (x1 == x2) {
      // 垂直
      y2 = y2.clamp(limitMinY, limitMaxY);
    } else if (y1 == y2) {
      // 水平
      x2 = x2.clamp(limitMinX, limitMaxX);
      if (!useHalfWidth && x2 % 2 != 0) x2 -= 1;
    } else {
      // 斜め: 比率を維持しつつ範囲内に収める
      double vecX = (x2 - x1).toDouble();
      double vecY = (y2 - y1).toDouble();
      double t = 1.0;

      // X軸方向の制限チェック
      if (x2 < limitMinX) {
        double tX = (limitMinX - x1) / vecX;
        if (tX < t) t = tX;
      } else if (x2 > limitMaxX) {
        double tX = (limitMaxX - x1) / vecX;
        if (tX < t) t = tX;
      }

      // Y軸方向の制限チェック
      if (y2 < limitMinY) {
        double tY = (limitMinY - y1) / vecY;
        if (tY < t) t = tY;
      } else if (y2 > limitMaxY) {
        double tY = (limitMaxY - y1) / vecY;
        if (tY < t) t = tY;
      }

      // 短縮適用
      x2 = (x1 + vecX * t).round();
      y2 = (y1 + vecY * t).round();

      if (!useHalfWidth && x2 % 2 != 0) x2 -= 1;
    }

    // 描画実行
    _drawLineSegment(x1, y1, x2, y2, useHalfWidth, arrowStart, arrowEnd);

    // カーソルを線の終点に移動し、内部座標を更新する
    cursorRow = y2;

    // 右方向へ描画した場合、カーソルを「描画した文字の右側」へ移動させる
    int finalVisualX = x2;
    int finalDx = x2 - x1;
    if (finalDx > 0) {
      finalVisualX += (useHalfWidth ? 1 : 2);
    }

    if (cursorRow < lines.length) {
      cursorCol = TextUtils.getColFromVisualX(lines[cursorRow], finalVisualX);
    }
    preferredVisualX = finalVisualX;

    clearSelection();
    isDirty = true;
    notifyListeners();
  }

  /// L字線（折れ線）を描画する
  void drawElbowLine({
    bool useHalfWidth = false,
    bool isUpperRoute = true, // true: 上/左優先, false: 下/右優先
    bool arrowStart = false,
    bool arrowEnd = false,
  }) {
    if (!hasSelection) return;
    // 履歴保存などは drawLine 側ではなくここでやるべきだが、
    // 内部で呼ぶ _drawLineSegment は履歴保存しないため、ここで保存する
    saveHistory();

    // 始点・終点の計算（drawLineと同じ補正ロジックが必要）
    // ※コード重複を避けるため、補正ロジックをメソッド化するのが理想だが、
    // ここでは簡易的に再実装する
    int x1 = _calcVisualXForController(
      selectionOriginRow!,
      selectionOriginCol!,
    );
    int y1 = selectionOriginRow!;
    int x2 = _calcVisualXForController(cursorRow, cursorCol);
    int y2 = cursorRow;

    // drawLine同様、x2 -= 1 は削除

    if (!useHalfWidth) {
      if (x1 % 2 != 0) x1 -= 1;
      if (x2 % 2 != 0) x2 -= 1;
    }

    // 中継点（角）の計算
    // UpperRoute: Y座標が小さい方（画面上側）を通る
    // LowerRoute: Y座標が大きい方（画面下側）を通る
    int cornerY = isUpperRoute ? min(y1, y2) : max(y1, y2);

    // 角のX座標は、Y移動を先にするか後でにするかで決まる
    // (x1, y1) -> (cornerX, cornerY) -> (x2, y2)
    // cornerY が y1 と同じなら、まずは水平移動（cornerX = x2）
    // cornerY が y2 と同じなら、まずは垂直移動（cornerX = x1）
    int cornerX = (cornerY == y1) ? x2 : x1;

    // 1本目: 始点 -> 角 (矢印は始点のみ)
    _drawLineSegment(x1, y1, cornerX, cornerY, useHalfWidth, arrowStart, false);

    // 2本目: 角 -> 終点 (矢印は終点のみ)
    _drawLineSegment(cornerX, cornerY, x2, y2, useHalfWidth, false, arrowEnd);

    // --- 角の形状修正 ---
    // _drawLineSegment は接続ロジックにより角を '├' や '┼' にしてしまうことがあるため、
    // L字線の角として正しい文字(┌, ┐, └, ┘)で上書きする。

    // 1本目の進入方向 (角から見てどちらから来たか)
    // 始点(x1, y1) -> 角(cornerX, cornerY)
    int fromDir = 0;
    if (x1 < cornerX)
      fromDir = 4; // Left (左から来た)
    else if (x1 > cornerX)
      fromDir = 8; // Right (右から来た)
    else if (y1 < cornerY)
      fromDir = 1; // Top (上から来た)
    else if (y1 > cornerY)
      fromDir = 2; // Bottom (下から来た)

    // 2本目の脱出方向 (角から見てどちらへ行くか)
    // 角(cornerX, cornerY) -> 終点(x2, y2)
    int toDir = 0;
    if (x2 < cornerX)
      toDir = 4; // Left (左へ行く)
    else if (x2 > cornerX)
      toDir = 8; // Right (右へ行く)
    else if (y2 < cornerY)
      toDir = 1; // Top (上へ行く)
    else if (y2 > cornerY)
      toDir = 2; // Bottom (下へ行く)

    // 角の接続フラグ (進入方向 + 脱出方向)
    int cornerFlags = fromDir | toDir;
    String? cornerChar = TextUtils.getCharFromConnectionFlags(
      cornerFlags,
      useHalfWidth,
    );
    if (cornerChar != null) {
      _writeCharToVisualLine(cornerY, cornerX, cornerChar);
    }

    // カーソル移動
    cursorRow = y2;
    int finalVisualX = x2;
    if (x2 > cornerX) finalVisualX += (useHalfWidth ? 1 : 2); // 最後の移動が右向きなら

    if (cursorRow < lines.length) {
      cursorCol = TextUtils.getColFromVisualX(lines[cursorRow], finalVisualX);
    }
    preferredVisualX = finalVisualX;

    clearSelection();
    isDirty = true;
    notifyListeners();
  }

  /// 実際の線描画処理 (内部用)
  void _drawLineSegment(
    int x1,
    int y1,
    int x2,
    int y2,
    bool useHalfWidth,
    bool arrowStart,
    bool arrowEnd,
  ) {
    int dx = x2 - x1;
    int dy = y2 - y1;

    // --- 経路計算 (単純ループ) ---
    List<Point<int>> points = [];
    int stepX = useHalfWidth ? 1 : 2; // X方向の増分単位

    // 方向判定
    int signX = (dx == 0) ? 0 : (dx > 0 ? 1 : -1);
    int signY = (dy == 0) ? 0 : (dy > 0 ? 1 : -1);

    // ループ回数の決定 (距離 / ステップ)
    // 斜め・垂直の場合はYの距離、水平の場合はXの距離(ステップ考慮)を採用
    int steps = (dy == 0) ? (dx.abs() / stepX).round() : dy.abs();

    for (int i = 0; i <= steps; i++) {
      points.add(Point(x1 + (i * stepX * signX), y1 + (i * signY)));
    }

    if (points.isEmpty) return;

    // 線の種類を決定
    String lineChar;
    bool isVertical = (x1 == x2);
    bool isHorizontal = (y1 == y2);

    if (useHalfWidth) {
      if (isVertical) {
        lineChar = '|';
      } else if (isHorizontal) {
        lineChar = '-';
      } else if ((x2 - x1) * (y2 - y1) > 0) {
        lineChar = '\\';
      } else {
        lineChar = '/';
      }
    } else {
      if (isVertical) {
        lineChar = '│';
      } else if (isHorizontal) {
        lineChar = '─';
      } else if ((x2 - x1) * (y2 - y1) > 0) {
        lineChar = '╲';
      } else {
        lineChar = '╱';
      }
    }

    // 描画
    for (int i = 0; i < points.length; i++) {
      Point<int> p = points[i];
      String charToPut = lineChar;
      bool isArrow = false;

      // --- 矢印描画ロジック ---
      // 始点かつ矢印ありの場合 (線と逆方向の矢印)
      if (arrowStart && i == 0) {
        String? arrow = TextUtils.getArrowChar(-signX, -signY, useHalfWidth);
        if (arrow != null) {
          charToPut = arrow;
          isArrow = true;
        }
      }
      // 終点かつ矢印ありの場合 (線と同じ方向の矢印)
      else if (arrowEnd && i == points.length - 1) {
        String? arrow = TextUtils.getArrowChar(signX, signY, useHalfWidth);
        if (arrow != null) {
          charToPut = arrow;
          isArrow = true;
        }
      }

      // 垂直・水平の場合、全ての点で接続処理を行う（交差対応）
      // ただし、矢印部分は接続処理を行わない
      if (!isArrow && (isVertical || isHorizontal)) {
        int newDir = 0;
        // 接続方向フラグ: Top=1, Bottom=2, Left=4, Right=8

        // 前の点からの接続 (自分が終点側、相手が始点側)
        if (i > 0) {
          Point<int> prev = points[i - 1];
          if (prev.y < p.y) newDir |= 1; // Top (prev is above)
          if (prev.y > p.y) newDir |= 2; // Bottom (prev is below)
          if (prev.x < p.x) newDir |= 4; // Left (prev is left)
          if (prev.x > p.x) newDir |= 8; // Right (prev is right)
        }

        // 次の点への接続 (自分が始点側、相手が終点側)
        if (i < points.length - 1) {
          Point<int> next = points[i + 1];
          if (next.y < p.y) newDir |= 1; // Top (next is above)
          if (next.y > p.y) newDir |= 2; // Bottom (next is below)
          if (next.x < p.x) newDir |= 4; // Left (next is left)
          if (next.x > p.x) newDir |= 8; // Right (next is right)
        }

        // 既存文字との合成
        charToPut = _resolveConnector(p.y, p.x, newDir, useHalfWidth);
      }

      _writeCharToVisualLine(p.y, p.x, charToPut);
    }

    // カーソルを線の終点に移動し、内部座標を更新する
    cursorRow = y2;

    // 右方向へ描画した場合、カーソルを「描画した文字の右側」へ移動させる
    int finalVisualX = x2;
    if (dx > 0) {
      finalVisualX += (useHalfWidth ? 1 : 2);
    }

    if (cursorRow < lines.length) {
      cursorCol = TextUtils.getColFromVisualX(lines[cursorRow], finalVisualX);
    }
    preferredVisualX = finalVisualX;

    clearSelection();
    isDirty = true;
    notifyListeners();
  }

  /// 接続文字を解決する
  String _resolveConnector(
    int row,
    int col,
    int newDirections,
    bool useHalfWidth,
  ) {
    // 既存の文字を取得
    String current = " ";
    if (row < lines.length) {
      String line = lines[row];
      int idx = TextUtils.getColFromVisualX(line, col);
      if (idx < line.length) {
        current = line.substring(idx, idx + 1);
      }
    }

    // 既存文字の接続方向を取得
    int currentDirs = TextUtils.getConnectionFlags(current);

    // 方向を合成
    int mergedDirs = currentDirs | newDirections;

    // 合成後の方向から文字を取得
    // 何も接続がない(0)なら、元の文字ではなく今回の線を引くべきなので newDirections を使う
    return TextUtils.getCharFromConnectionFlags(mergedDirs, useHalfWidth) ??
        TextUtils.getCharFromConnectionFlags(newDirections, useHalfWidth) ??
        (useHalfWidth ? '+' : '┼');
  }

  /// 指定行の指定VisualX位置に文字を書き込む（セル展開方式）
  /// 既存の文字幅を考慮し、必要ならスペースで埋めたり、全角文字を分割したりする
  void _writeCharToVisualLine(int row, int targetVisualX, String charToPut) {
    // 行が足りなければ追加
    while (lines.length <= row) {
      lines.add("");
    }
    String line = lines[row];

    // 1. 文字列をVisualセル（文字の配列、全角の2セル目はnull）に展開
    List<String?> cells = [];
    for (int rune in line.runes) {
      String char = String.fromCharCode(rune);
      int w = (rune < 128) ? 1 : 2;
      cells.add(char);
      if (w == 2) {
        cells.add(null); // 全角の2セル目
      }
    }

    // 2. 必要な長さまでスペースでパディング
    int putWidth = TextUtils.calcTextWidth(charToPut);
    int requiredLen = targetVisualX + putWidth;
    while (cells.length < requiredLen) {
      cells.add(' ');
    }

    // 3. 書き込み処理
    // 書き込み開始位置が null (全角文字の2セル目) だった場合、その全角文字の前半をスペースにする
    if (cells[targetVisualX] == null) {
      // 直前の非nullセルを探してスペースにする
      if (targetVisualX > 0) {
        cells[targetVisualX - 1] = ' ';
        cells[targetVisualX] = ' '; // ここは一旦スペースにしておく（後で上書きされる）
      }
    }

    // 書き込み範囲にある既存文字をクリア（全角文字の一部にかかる場合への対処）
    for (int i = 0; i < putWidth; i++) {
      int idx = targetVisualX + i;
      if (idx < cells.length) {
        if (cells[idx] == null) {
          // 全角の後半を潰す -> 前半もスペースに
          if (idx > 0) cells[idx - 1] = ' ';
        } else if (idx + 1 < cells.length && cells[idx + 1] == null) {
          // 全角の前半を潰す -> 後半をスペースに（nullではなく実体化）
          cells[idx + 1] = ' ';
        }
        cells[idx] = ' '; // とりあえずスペース化
      }
    }

    // 文字を配置
    cells[targetVisualX] = charToPut;
    // 全角文字なら2セル目をnullにする
    if (putWidth == 2) {
      if (targetVisualX + 1 < cells.length) {
        cells[targetVisualX + 1] = null;
      } else {
        cells.add(null);
      }
    }

    // 4. 文字列に再構築
    StringBuffer sb = StringBuffer();
    for (String? c in cells) {
      if (c != null) {
        sb.write(c);
      }
    }
    lines[row] = sb.toString();
  }

  // --- File I/O ---
  int findDocumentIndex(String path) {
    for (int i = 0; i < documents.length; i++) {
      if (documents[i].currentFilePath == path) {
        return i;
      }
    }
    return -1;
  }

  Future<void> openDocument(String path) async {
    newTab();
    await activeDocument.loadFromFile(path);
    notifyListeners();
  }

  Future<void> reloadDocument(int index, String path) async {
    if (index >= 0 && index < documents.length) {
      switchTab(index);
      await activeDocument.loadFromFile(path);
    }
    notifyListeners();
  }

  Future<void> reloadWithEncoding(String encoding) async {
    if (activeDocument.currentFilePath != null) {
      await activeDocument.loadFromFile(
        activeDocument.currentFilePath!,
        encoding: encoding,
      );
      notifyListeners();
    }
  }

  void changeEncoding(String encoding) {
    activeDocument.currentEncoding = encoding;
    activeDocument.isDirty = true;
    notifyListeners();
  }

  Future<String?> saveFile() async {
    final path = await activeDocument.saveFile();
    notifyListeners();
    return path;
  }

  Future<String?> saveAsFile() async {
    final path = await activeDocument.saveAsFile();
    notifyListeners();
    return path;
  }

  // --- Clipboard ---
  Future<void> copySelection() async {
    if (!hasSelection) return;

    StringBuffer buffer = StringBuffer();

    if (isRectangularSelection) {
      int startRow = min(selectionOriginRow!, cursorRow);
      int endRow = max(selectionOriginRow!, cursorRow);
      int originVisualX = _calcVisualXForController(
        selectionOriginRow!,
        selectionOriginCol!,
      );
      int cursorVisualX = _calcVisualXForController(cursorRow, cursorCol);
      int minVisualX = min(originVisualX, cursorVisualX);
      int maxVisualX = max(originVisualX, cursorVisualX);

      for (int i = startRow; i <= endRow; i++) {
        String line = (i < lines.length) ? lines[i] : "";
        int startCol = TextUtils.getColFromVisualX(line, minVisualX);
        int endCol = TextUtils.getColFromVisualX(line, maxVisualX);

        if (startCol > endCol) {
          int temp = startCol;
          startCol = endCol;
          endCol = temp;
        }
        String extracted = "";
        if (startCol < line.length) {
          int safeEnd = min(endCol, line.length);
          extracted = line.substring(startCol, safeEnd);
        }
        buffer.writeln(extracted);
      }
    } else {
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

      for (int i = startRow; i <= endRow; i++) {
        if (i >= lines.length) break;
        String line = lines[i];
        int s = (i == startRow) ? startCol : 0;
        int e = (i == endRow) ? endCol : line.length;
        if (s > line.length) s = line.length;
        if (e > line.length) e = line.length;
        if (s < 0) s = 0;
        if (e < 0) e = 0;

        buffer.write(line.substring(s, e));
        if (i < endRow) {
          buffer.write('\n');
        }
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
  }

  Future<void> pasteNormal() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null) return;

    String text = data.text!.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    List<String> parts = text.split('\n');

    ensureVirtualSpace(cursorRow, cursorCol);
    String line = lines[cursorRow];
    String prefix = line.substring(0, cursorCol);

    if (!isOverwriteMode) {
      String suffix = line.substring(cursorCol);
      if (parts.length == 1) {
        lines[cursorRow] = prefix + parts[0] + suffix;
        cursorCol += parts[0].length;
      } else {
        lines[cursorRow] = prefix + parts.first;
        for (int i = 1; i < parts.length - 1; i++) {
          lines.insert(cursorRow + i, parts[i]);
        }
        lines.insert(cursorRow + parts.length - 1, parts.last + suffix);
        cursorRow += parts.length - 1;
        cursorCol = parts.last.length;
      }
    } else {
      String firstPartToPaste = parts.first;
      int pasteVisualWidth = TextUtils.calcTextWidth(firstPartToPaste);
      int currentVisualX = TextUtils.calcTextWidth(prefix);
      int targetEndVisualX = currentVisualX + pasteVisualWidth;
      int overwriteEndCol = TextUtils.getColFromVisualX(line, targetEndVisualX);
      String suffix = "";
      if (overwriteEndCol < line.length) {
        suffix = line.substring(overwriteEndCol);
      }
      if (parts.length == 1) {
        lines[cursorRow] = prefix + firstPartToPaste + suffix;
        cursorCol += firstPartToPaste.length;
      } else {
        lines[cursorRow] = prefix + firstPartToPaste;
        for (int i = 1; i < parts.length - 1; i++) {
          lines.insert(cursorRow + i, parts[i]);
        }
        lines.insert(cursorRow + parts.length - 1, parts.last + suffix);
        cursorRow += parts.length - 1;
        cursorCol = parts.last.length;
      }
    }

    preferredVisualX = _calcVisualXForController(cursorRow, cursorCol);
    selectionOriginRow = null;
    isDirty = true;
    selectionOriginCol = null;
    notifyListeners();
  }

  Future<void> pasteRectangular() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data == null || data.text == null || data.text!.isEmpty) return;

      final List<String> pasteLines = const LineSplitter().convert(data.text!);
      if (pasteLines.isEmpty) return;

      int startRow = cursorRow;
      String currentLine = (cursorRow < lines.length) ? lines[cursorRow] : "";
      String textBefore = "";
      if (cursorCol <= currentLine.length) {
        textBefore = currentLine.substring(0, cursorCol);
      } else {
        textBefore = currentLine + (' ' * (cursorCol - currentLine.length));
      }
      int targetVisualX = TextUtils.calcTextWidth(textBefore);

      for (int i = 0; i < pasteLines.length; i++) {
        int targetRow = startRow + i;
        String textToPaste = pasteLines[i].replaceAll(RegExp(r'[\r\n]'), '');
        int pasteWidth = TextUtils.calcTextWidth(textToPaste);

        ensureVirtualSpace(targetRow, 0);
        String line = lines[targetRow];

        // ★修正: VisualX基準でパディングを行う
        int currentLineWidth = TextUtils.calcTextWidth(line);
        if (currentLineWidth < targetVisualX) {
          int spacesNeeded = targetVisualX - currentLineWidth;
          lines[targetRow] += ' ' * spacesNeeded;
          line = lines[targetRow];
        }

        int insertIndex = TextUtils.getColFromVisualX(line, targetVisualX);

        if (!isOverwriteMode) {
          String part1 = line.substring(0, insertIndex);
          String part2 = line.substring(insertIndex);
          lines[targetRow] = part1 + textToPaste + part2;
        } else {
          int endVisualX = targetVisualX + pasteWidth;
          int endIndex = TextUtils.getColFromVisualX(line, endVisualX);
          if (endIndex > line.length) endIndex = line.length;
          String part1 = line.substring(0, insertIndex);
          String part2 = line.substring(endIndex);
          lines[targetRow] = part1 + textToPaste + part2;
        }
      }
      cursorRow = startRow + pasteLines.length - 1;
      String lastPasted = pasteLines.last.replaceAll(RegExp(r'[\r\n]'), '');
      int lastWidth = TextUtils.calcTextWidth(lastPasted);
      preferredVisualX = targetVisualX + lastWidth;
      if (cursorRow < lines.length) {
        cursorCol = TextUtils.getColFromVisualX(
          lines[cursorRow],
          preferredVisualX,
        );
      }
      selectionOriginRow = null;
      selectionOriginCol = null;
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('Error in pasteRectangular: $e\n$stackTrace');
    }
  }

  // ヘルパー: VisualX計算
  int _calcVisualXForController(int row, int col) {
    // 行が存在しない場合も、空行として扱いスペース計算を行う
    String line = (row < lines.length) ? lines[row] : "";
    String text;
    if (col <= line.length) {
      text = line.substring(0, col);
    } else {
      text = line + (' ' * (col - line.length));
    }
    return TextUtils.calcTextWidth(text);
  }

  // --- Cursor Movement (Step 1.2) ---

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

    // Horizontal Move
    if (colMove != 0) {
      if (isAlt) {
        if (colMove > 0) {
          // Alt + Right: 虚空へ移動 (行跨ぎなし)
          cursorCol += colMove;
        } else {
          // Alt + Left: 行頭なら前の行へ (行跨ぎあり)
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

      // Update VisualX
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

    // Vertical Move
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

  // --- Key Handling (Step 1.1) ---
  KeyEventResult handleKeyPress(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final PhysicalKeyboardKey physicalKey = event.physicalKey;
    bool isControl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    bool isShift = HardwareKeyboard.instance.isShiftPressed;
    bool isAlt = HardwareKeyboard.instance.isAltPressed;

    // --- Arrow Keys ---
    if (physicalKey == PhysicalKeyboardKey.arrowLeft) {
      moveCursor(0, -1, isShift, isAlt);
      return KeyEventResult.handled;
    }
    if (physicalKey == PhysicalKeyboardKey.arrowRight) {
      moveCursor(0, 1, isShift, isAlt);
      return KeyEventResult.handled;
    }
    if (physicalKey == PhysicalKeyboardKey.arrowUp) {
      moveCursor(-1, 0, isShift, isAlt);
      return KeyEventResult.handled;
    }
    if (physicalKey == PhysicalKeyboardKey.arrowDown) {
      moveCursor(1, 0, isShift, isAlt);
      return KeyEventResult.handled;
    }

    // --- Ctrl/Cmd Key Combos ---
    if (isControl) {
      if (physicalKey == PhysicalKeyboardKey.keyC) {
        copySelection();
        return KeyEventResult.handled;
      }
      if (physicalKey == PhysicalKeyboardKey.keyZ) {
        undo();
        return KeyEventResult.handled;
      }
      if (physicalKey == PhysicalKeyboardKey.keyY) {
        redo();
        return KeyEventResult.handled;
      }
      if (physicalKey == PhysicalKeyboardKey.keyV) {
        if (hasSelection) {
          saveHistory();
          deleteSelection();
        }
        if (isAlt) {
          pasteRectangular();
        } else {
          pasteNormal();
        }
        return KeyEventResult.handled;
      }
      if (physicalKey == PhysicalKeyboardKey.keyS) {
        bool isShift = HardwareKeyboard.instance.isShiftPressed;
        if (isShift) {
          saveAsFile();
        } else {
          saveFile();
        }
        return KeyEventResult.handled;
      }
      if (physicalKey == PhysicalKeyboardKey.keyA) {
        selectAll();
        return KeyEventResult.handled;
      }
      if (physicalKey == PhysicalKeyboardKey.keyD) {
        if (isAlt) {
          trimTrailingWhitespace();
          return KeyEventResult.handled;
        }
      }
    }

    // --- Other Special Keys ---
    switch (physicalKey) {
      case PhysicalKeyboardKey.tab:
        indent();
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.enter:
        activeDocument.insertNewLine();
        preferredVisualX = _calcVisualXForController(cursorRow, cursorCol);
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.backspace:
        activeDocument.backspace();
        preferredVisualX = _calcVisualXForController(cursorRow, cursorCol);
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.delete:
        if (currentMode == EditorMode.draw) {
          deleteSelectedDrawing();
        } else {
          activeDocument.delete();
          preferredVisualX = _calcVisualXForController(cursorRow, cursorCol);
        }
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.insert:
        isOverwriteMode = !isOverwriteMode;
        _saveBool('isOverwriteMode', isOverwriteMode);
        notifyListeners();
        return KeyEventResult.handled;
    }

    // この段階では、矢印キーや文字入力はまだ処理しない
    return KeyEventResult.ignored;
  }

  // --- UI Event Handling (Step 2) ---

  /// 選択解除
  void clearSelection() {
    activeDocument.clearSelection();
  }

  /// 図形選択 (Figure Mode用)
  void trySelectDrawing(
    Offset localPosition,
    double charWidth,
    double lineHeight,
  ) {
    activeDocument.trySelectDrawing(localPosition, charWidth, lineHeight);
  }

  /// 選択中の図形を削除
  void deleteSelectedDrawing() {
    activeDocument.deleteSelectedDrawing();
  }

  /// タップ時のカーソル移動処理
  void handleTap(Offset localPosition, double charWidth, double lineHeight) {
    activeDocument.handleTap(localPosition, charWidth, lineHeight);
  }

  /// ドラッグ開始時の処理
  void handlePanStart(
    Offset localPosition,
    double charWidth,
    double lineHeight,
    bool isAltPressed, {
    required EditorMode mode, // モード引数を追加
  }) {
    activeDocument.handlePanStart(
      localPosition,
      charWidth,
      lineHeight,
      isAltPressed,
      isFigureMode: mode == EditorMode.draw,
    );
  }

  /// ドラッグ中の処理 (リサイズ or 移動 or 選択)
  void handlePanUpdate(
    Offset localPosition,
    double charWidth,
    double lineHeight,
  ) {
    activeDocument.handlePanUpdate(localPosition, charWidth, lineHeight);
  }

  /// ドラッグ終了時の処理
  void handlePanEnd() {
    activeDocument.handlePanEnd();
  }

  // --- Input & State Management (Step 3) ---

  void toggleGrid() {
    showGrid = !showGrid;
    _saveBool('showGrid', showGrid);
    notifyListeners();
  }

  void toggleLineNumber() {
    showLineNumber = !showLineNumber;
    _saveBool('showLineNumber', showLineNumber);
    notifyListeners();
  }

  void toggleRuler() {
    showRuler = !showRuler;
    _saveBool('showRuler', showRuler);
    notifyListeners();
  }

  void toggleMinimap() {
    showMinimap = !showMinimap;
    _saveBool('showMinimap', showMinimap);
    notifyListeners();
  }

  void updateComposingText(String text) {
    activeDocument.updateComposingText(text);
  }

  /// 文字入力処理（履歴保存、選択削除、挿入を統合）
  void input(String text) {
    activeDocument.input(text);
  }
}
