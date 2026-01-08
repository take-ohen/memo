import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'editor_controller.dart';
import 'font_manager.dart';
import 'l10n/app_localizations.dart';
import 'color_picker_widget.dart'; // 新規Widgetをインポート
import 'memo_painter.dart'; // プレビュー描画用
import 'editor_document.dart'; // NewLineType用

enum SettingsTab { textEditor, interface, general }

enum ColorTarget { background, text, lineNumber, ruler, grid }

class SettingsDialog extends StatefulWidget {
  final EditorController controller;
  final SettingsTab initialTab;

  const SettingsDialog({
    super.key,
    required this.controller,
    this.initialTab = SettingsTab.textEditor,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final FontManager _fontManager = FontManager();
  bool _isLoading = false;

  // --- 1. Text Editor Settings ---
  late TextEditingController _editorFontController;
  late double _editorFontSize;
  late bool _editorBold;
  late bool _editorItalic;
  late int _tabWidth;
  late NewLineType _defaultNewLineType;
  late bool _enableCursorBlink;
  // Colors for Editor
  late int _editorBackgroundColor;
  late int _editorTextColor;
  ColorTarget _editorColorTarget = ColorTarget.background;

  // --- 2. Interface Settings ---
  late TextEditingController _uiFontController;
  late double _uiFontSize;
  late bool _uiBold;
  late bool _uiItalic;
  late double _grepFontSize;
  // Colors & Sizes for Interface
  late int _lineNumberColor;
  late double _lineNumberFontSize;
  late int _rulerColor;
  late double _rulerFontSize;
  late int _gridColor;
  ColorTarget _interfaceColorTarget = ColorTarget.lineNumber;

  // --- 3. General Settings ---
  late int _minColumns;
  late int _minLines;

  // プレビュー用ダミーデータ
  final List<String> _previewLines = [
    'void main() {',
    '  print("Hello, World!");',
    '  // Preview Code',
    '}',
  ];

  // ウィンドウ移動用オフセット
  Offset _offset = Offset.zero;

  @override
  void initState() {
    super.initState();

    // 初期値のロード
    _editorFontController = TextEditingController(
      text: widget.controller.fontFamily,
    );
    _editorFontSize = widget.controller.fontSize;
    _editorBold = widget.controller.editorBold;
    _editorItalic = widget.controller.editorItalic;
    _tabWidth = widget.controller.tabWidth;
    _defaultNewLineType = widget.controller.defaultNewLineType;
    _enableCursorBlink = widget.controller.enableCursorBlink;
    _editorBackgroundColor = widget.controller.editorBackgroundColor;
    _editorTextColor = widget.controller.editorTextColor;

    _minColumns = widget.controller.minColumns;
    _minLines = widget.controller.minLines;

    _uiFontController = TextEditingController(
      text: widget.controller.uiFontFamily,
    );
    _uiFontSize = widget.controller.uiFontSize;
    _uiBold = widget.controller.uiBold;
    _uiItalic = widget.controller.uiItalic;
    _grepFontSize = widget.controller.grepFontSize;

    _lineNumberColor = widget.controller.lineNumberColor;
    _lineNumberFontSize = widget.controller.lineNumberFontSize;
    _rulerColor = widget.controller.rulerColor;
    _rulerFontSize = widget.controller.rulerFontSize;
    _gridColor = widget.controller.gridColor;

    // フォントリストのロード開始
    _loadFonts();
  }

  Future<void> _loadFonts() async {
    setState(() => _isLoading = true);
    await _fontManager.loadFonts();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _rescanFonts() async {
    setState(() => _isLoading = true);
    await _fontManager.scanSystemFonts();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _editorFontController.dispose();
    _uiFontController.dispose();
    super.dispose();
  }

  void _applySettings() {
    // Text Editor
    widget.controller.setEditorFont(
      _editorFontController.text,
      _editorFontSize,
      _editorBold,
      _editorItalic,
    );
    widget.controller.setTabWidth(_tabWidth);
    widget.controller.setDefaultNewLineType(_defaultNewLineType);
    widget.controller.setEnableCursorBlink(_enableCursorBlink);
    widget.controller.setEditorColors(_editorBackgroundColor, _editorTextColor);

    // Interface
    widget.controller.setUiFont(
      _uiFontController.text,
      _uiFontSize,
      _uiBold,
      _uiItalic,
    );
    widget.controller.setGrepFontSize(_grepFontSize);
    widget.controller.setViewSettings(
      lnColor: _lineNumberColor,
      lnSize: _lineNumberFontSize,
      rColor: _rulerColor,
      rSize: _rulerFontSize,
      gColor: _gridColor,
    );

    // General
    widget.controller.setCanvasSize(_minColumns, _minLines);

    Navigator.of(context).pop();
  }

  // --- 共通パーツ: セクションタイトル ---
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0, top: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const Divider(height: 4),
        ],
      ),
    );
  }

  // --- 共通パーツ: フォント設定 ---
  Widget _buildFontSettings({
    required BuildContext context,
    required String title,
    required List<String> fontList,
    required TextEditingController fontController,
    required double fontSize,
    required bool isBold,
    required bool isItalic,
    required Function(double) onSizeChanged,
    required Function(bool?) onBoldChanged,
    required Function(bool?) onItalicChanged,
  }) {
    final s = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(title),
        // DropdownMenu -> DropdownButton に変更してコンパクト化
        SizedBox(
          height: 24,
          child: DropdownButton<String>(
            value: fontList.contains(fontController.text)
                ? fontController.text
                : null,
            isExpanded: true,
            isDense: true,
            underline: Container(height: 1, color: Colors.grey.shade300),
            style: const TextStyle(fontSize: 11, color: Colors.black),
            items: fontList.map((f) {
              return DropdownMenuItem(
                value: f,
                child: Text(f, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) setState(() => fontController.text = v);
            },
            hint: Text(s.labelFontFamily, style: const TextStyle(fontSize: 11)),
          ),
        ),
        const SizedBox(height: 4),
        _CompactValueInput(
          label: s.labelFontSize,
          value: fontSize,
          min: 8.0,
          max: 72.0,
          onChanged: (v) => setState(() => onSizeChanged(v)),
        ),
        Row(
          children: [
            Checkbox(
              value: isBold,
              visualDensity: const VisualDensity(
                horizontal: -4,
                vertical: -4,
              ), // 極限まで詰める
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => setState(() => onBoldChanged(v)),
            ),
            Text(s.labelBold, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 16),
            Checkbox(
              value: isItalic,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => setState(() => onItalicChanged(v)),
            ),
            Text(s.labelItalic, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ],
    );
  }

  // --- 共通パーツ: カラー設定セクション ---
  Widget _buildColorSection({
    required BuildContext context,
    required String title,
    required ColorTarget activeTarget,
    required List<DropdownMenuItem<ColorTarget>> items,
    required ValueChanged<ColorTarget> onTargetChanged,
    required Color currentColor,
    required ValueChanged<Color> onColorChanged,
  }) {
    final s = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(title),
        Row(
          children: [
            Text(
              "${s.labelEditTarget}: ",
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<ColorTarget>(
                isExpanded: true,
                isDense: true,
                underline: Container(height: 1, color: Colors.grey.shade300),
                style: const TextStyle(fontSize: 11, color: Colors.black),
                value: activeTarget,
                items: items,
                onChanged: (v) {
                  if (v != null) onTargetChanged(v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ColorPickerWidget(
            color: currentColor,
            onColorChanged: onColorChanged,
          ),
        ),
      ],
    );
  }

  // --- Tab 1: Text Editor ---
  Widget _buildTextEditorTab(BuildContext context) {
    final s = AppLocalizations.of(context)!;

    // プレビュー用のメトリクス計算
    final previewTextStyle = TextStyle(
      fontFamily: _editorFontController.text,
      fontSize: _editorFontSize,
      fontWeight: _editorBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: _editorItalic ? FontStyle.italic : FontStyle.normal,
    );
    final textPainter = TextPainter(
      text: TextSpan(text: 'M', style: previewTextStyle),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final charWidth = textPainter.width;
    final charHeight = textPainter.height;
    final lineHeight = charHeight * 1.2;

    // 現在の色を取得
    Color currentColor = _editorColorTarget == ColorTarget.background
        ? Color(_editorBackgroundColor)
        : Color(_editorTextColor);

    return Column(
      children: [
        // --- 1. 固定プレビューエリア (上部) ---
        Container(
          height: 100,
          width: double.infinity,
          color: Colors.grey.shade100,
          padding: const EdgeInsets.all(8),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              color: Color(_editorBackgroundColor),
            ),
            child: ClipRect(
              child: CustomPaint(
                painter: MemoPainter(
                  lines: _previewLines,
                  charWidth: charWidth,
                  charHeight: charHeight,
                  lineHeight: lineHeight,
                  showGrid: false,
                  isOverwriteMode: false,
                  cursorRow: 0,
                  cursorCol: 0,
                  textStyle: previewTextStyle.copyWith(
                    color: Color(_editorTextColor),
                  ),
                  composingText: "",
                  showCursor: _enableCursorBlink, // 点滅設定を反映
                  gridColor: Colors.transparent,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        // --- 2. スクロール設定エリア (下部) ---
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左カラム: フォント & 挙動
                    Expanded(
                      flex: 1,
                      child: Column(
                        children: [
                          _buildFontSettings(
                            context: context,
                            title: s.labelEditorFont,
                            fontList: _fontManager.monospaceFonts,
                            fontController: _editorFontController,
                            fontSize: _editorFontSize,
                            isBold: _editorBold,
                            isItalic: _editorItalic,
                            onSizeChanged: (v) => _editorFontSize = v,
                            onBoldChanged: (v) => _editorBold = v ?? false,
                            onItalicChanged: (v) => _editorItalic = v ?? false,
                          ),
                          const SizedBox(height: 16),
                          _buildSectionTitle(s.labelBehavior),
                          // Tab Width
                          Row(
                            children: [
                              SizedBox(
                                width: 80,
                                child: Text(
                                  s.labelTabWidth,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              Expanded(
                                child: DropdownButton<int>(
                                  value: _tabWidth,
                                  isDense: true,
                                  isExpanded: true,
                                  underline: Container(
                                    height: 1,
                                    color: Colors.grey.shade300,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.black,
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: 2,
                                      child: Text(
                                        "2 ${s.labelColumns}",
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 4,
                                      child: Text(
                                        "4 ${s.labelColumns}",
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 8,
                                      child: Text(
                                        "8 ${s.labelColumns}",
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  ],
                                  onChanged: (v) {
                                    if (v != null)
                                      setState(() => _tabWidth = v);
                                  },
                                ),
                              ),
                            ],
                          ),
                          // Default Line Ending
                          Row(
                            children: [
                              SizedBox(
                                width: 80,
                                child: Text(
                                  s.labelNewLineCode,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              Expanded(
                                child: DropdownButton<NewLineType>(
                                  value: _defaultNewLineType,
                                  isDense: true,
                                  isExpanded: true,
                                  underline: Container(
                                    height: 1,
                                    color: Colors.grey.shade300,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.black,
                                  ),
                                  items: NewLineType.values.map((type) {
                                    return DropdownMenuItem(
                                      value: type,
                                      child: Text(
                                        type.label,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (v) {
                                    if (v != null)
                                      setState(() => _defaultNewLineType = v);
                                  },
                                ),
                              ),
                            ],
                          ),
                          // Cursor Blinking
                          Row(
                            children: [
                              SizedBox(
                                width: 80,
                                child: Text(
                                  s.labelCursorBlink,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              Checkbox(
                                value: _enableCursorBlink,
                                visualDensity: const VisualDensity(
                                  horizontal: -4,
                                  vertical: -4,
                                ),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onChanged: (v) => setState(
                                  () => _enableCursorBlink = v ?? true,
                                ),
                              ),
                              Text(
                                s.labelEnable,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 右カラム: 色設定
                    Expanded(
                      flex: 1,
                      child: _buildColorSection(
                        context: context,
                        title: s.labelEditorColors,
                        activeTarget: _editorColorTarget,
                        items: [
                          DropdownMenuItem(
                            value: ColorTarget.background,
                            child: Text(
                              s.labelBackground,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          DropdownMenuItem(
                            value: ColorTarget.text,
                            child: Text(
                              s.labelText,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                        onTargetChanged: (v) =>
                            setState(() => _editorColorTarget = v),
                        currentColor: currentColor,
                        onColorChanged: (color) {
                          setState(() {
                            if (_editorColorTarget == ColorTarget.background) {
                              _editorBackgroundColor = color.value;
                            } else {
                              _editorTextColor = color.value;
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Tab 2: Interface ---
  Widget _buildInterfaceTab(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    // プレビュー用のメトリクス計算
    final previewTextStyle = TextStyle(
      fontFamily: _uiFontController.text,
      fontSize: _uiFontSize,
    );
    final textPainter = TextPainter(
      text: TextSpan(text: 'M', style: previewTextStyle),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final charWidth = textPainter.width;
    final charHeight = textPainter.height;
    final lineHeight = charHeight * 1.2;

    // 現在選択中の色を取得
    Color currentColor;
    switch (_interfaceColorTarget) {
      case ColorTarget.lineNumber:
        currentColor = Color(_lineNumberColor);
        break;
      case ColorTarget.ruler:
        currentColor = Color(_rulerColor);
        break;
      case ColorTarget.grid:
        currentColor = Color(_gridColor);
        break;
      default:
        currentColor = Colors.black;
    }

    return Column(
      children: [
        // --- 1. 固定プレビューエリア (上部) ---
        Container(
          height: 120,
          width: double.infinity,
          color: Colors.grey.shade100,
          padding: const EdgeInsets.all(8),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              color: Colors.white,
            ),
            child: Stack(
              children: [
                Column(
                  children: [
                    // ルーラー
                    Container(
                      height: 24,
                      color: Colors.grey.shade200,
                      child: Row(
                        children: [
                          const SizedBox(width: 40),
                          Expanded(
                            child: ClipRect(
                              child: CustomPaint(
                                size: const Size(double.infinity, 24),
                                painter: ColumnRulerPainter(
                                  charWidth: charWidth,
                                  lineHeight: 24,
                                  textStyle: TextStyle(
                                    fontFamily: _uiFontController.text,
                                    fontSize: _rulerFontSize,
                                    color: Color(_rulerColor),
                                  ),
                                  editorWidth: 500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 行番号 + グリッド
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            color: Colors.grey.shade200,
                            child: CustomPaint(
                              size: Size.infinite,
                              painter: LineNumberPainter(
                                lineCount: 3,
                                lineHeight: lineHeight,
                                textStyle: TextStyle(
                                  fontFamily: _uiFontController.text,
                                  fontSize: _lineNumberFontSize,
                                  color: Color(_lineNumberColor),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: CustomPaint(
                              painter: MemoPainter(
                                lines: const ["Grid Preview", "", ""],
                                charWidth: charWidth,
                                charHeight: charHeight,
                                lineHeight: lineHeight,
                                showGrid: true, // グリッド確認のため常時ON
                                isOverwriteMode: false,
                                cursorRow: 0,
                                cursorCol: 0,
                                textStyle: previewTextStyle,
                                composingText: "",
                                showCursor: false,
                                gridColor: Color(_gridColor),
                              ),
                              size: Size.infinite,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // 検索バー & Grep結果のダミー表示 (右上に配置)
                Positioned(
                  top: 30,
                  right: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // ダミー検索バー
                      Container(
                        width: 200,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(color: Colors.black12, blurRadius: 4),
                          ],
                        ),
                        child: Text(
                          s.labelPreviewSearch,
                          style: TextStyle(fontSize: _grepFontSize),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // ダミーGrep結果
                      Container(
                        width: 200,
                        padding: const EdgeInsets.all(4),
                        color: Colors.grey.shade100,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'file.txt:1: ',
                                style: TextStyle(
                                  fontSize: _grepFontSize,
                                  color: Colors.blue.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(
                                text: s.labelPreviewGrep,
                                style: TextStyle(
                                  fontFamily: _editorFontController.text,
                                  fontSize: _grepFontSize,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        // --- 2. スクロール設定エリア (下部) ---
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左カラム: UIフォント & 検索設定
                    Expanded(
                      flex: 1,
                      child: Column(
                        children: [
                          _buildFontSettings(
                            context: context,
                            title: s.labelUiFont,
                            fontList: _fontManager.allFonts,
                            fontController: _uiFontController,
                            fontSize: _uiFontSize,
                            isBold: _uiBold,
                            isItalic: _uiItalic,
                            onSizeChanged: (v) => _uiFontSize = v,
                            onBoldChanged: (v) => _uiBold = v ?? false,
                            onItalicChanged: (v) => _uiItalic = v ?? false,
                          ),
                          const SizedBox(height: 16),
                          _buildSectionTitle(s.labelSearchSettings),
                          _CompactValueInput(
                            label: s.labelFontSize,
                            value: _grepFontSize,
                            min: 8.0,
                            max: 24.0,
                            onChanged: (v) => setState(() => _grepFontSize = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 右カラム: Gutter & Ruler (色とサイズ)
                    Expanded(
                      flex: 1,
                      child: Column(
                        children: [
                          _buildColorSection(
                            context: context,
                            title: s.labelGutterRulerColors,
                            activeTarget: _interfaceColorTarget,
                            items: [
                              DropdownMenuItem(
                                value: ColorTarget.lineNumber,
                                child: Text(
                                  s.labelLineNumber,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              DropdownMenuItem(
                                value: ColorTarget.ruler,
                                child: Text(
                                  s.labelRuler,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              DropdownMenuItem(
                                value: ColorTarget.grid,
                                child: Text(
                                  s.labelGrid,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                            onTargetChanged: (v) =>
                                setState(() => _interfaceColorTarget = v),
                            currentColor: currentColor,
                            onColorChanged: (color) {
                              setState(() {
                                switch (_interfaceColorTarget) {
                                  case ColorTarget.lineNumber:
                                    _lineNumberColor = color.value;
                                    break;
                                  case ColorTarget.ruler:
                                    _rulerColor = color.value;
                                    break;
                                  case ColorTarget.grid:
                                    _gridColor = color.value;
                                    break;
                                  default:
                                    break;
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          if (_interfaceColorTarget == ColorTarget.lineNumber)
                            _CompactValueInput(
                              label: s.labelLineNumberSize,
                              value: _lineNumberFontSize,
                              min: 8.0,
                              max: 24.0,
                              onChanged: (v) =>
                                  setState(() => _lineNumberFontSize = v),
                            ),
                          if (_interfaceColorTarget == ColorTarget.ruler)
                            _CompactValueInput(
                              label: s.labelRulerSize,
                              value: _rulerFontSize,
                              min: 8.0,
                              max: 24.0,
                              onChanged: (v) =>
                                  setState(() => _rulerFontSize = v),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Tab 3: General ---
  Widget _buildGeneralTab(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(s.labelCanvasSizeMin),
          _CompactValueInput(
            label: s.labelColumns,
            value: _minColumns.toDouble(),
            min: 80,
            max: 1000,
            divisions: 920,
            onChanged: (v) => setState(() => _minColumns = v.toInt()),
          ),
          const SizedBox(height: 4),
          _CompactValueInput(
            label: s.labelLines,
            value: _minLines.toDouble(),
            min: 40,
            max: 1000,
            divisions: 960,
            onChanged: (v) => setState(() => _minLines = v.toInt()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;

    // 表示するコンテンツとタイトルを決定
    Widget content;
    String title;
    bool showFontScan = false;

    switch (widget.initialTab) {
      case SettingsTab.textEditor:
        title = "${s.settingsTabEditor} ${s.labelSettings}";
        content = _buildTextEditorTab(context);
        showFontScan = true;
        break;
      case SettingsTab.interface:
        title = "${s.settingsTabUi} ${s.labelSettings}";
        content = _buildInterfaceTab(context);
        showFontScan = true;
        break;
      case SettingsTab.general:
        title = "General ${s.labelSettings}";
        content = _buildGeneralTab(context);
        break;
    }

    // ダイアログ全体をドラッグ可能にするためのレイアウト
    return Dialog(
      backgroundColor: Colors.transparent, // 背景透明
      insetPadding: EdgeInsets.zero, // 画面いっぱいに広げる
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ドラッグ移動用のTransform
          Transform.translate(
            offset: _offset,
            child: Container(
              width: 420, // コンパクトな固定幅
              height: 520, // コンパクトな固定高さ
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- タイトルバー (ドラッグハンドル) ---
                  GestureDetector(
                    onPanUpdate: (details) {
                      setState(() => _offset += details.delta);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade300),
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // --- コンテンツ ---
                  Expanded(
                    child: _isLoading
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  s.msgScanningFonts,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          )
                        : content,
                  ),
                  const Divider(height: 1),
                  // --- フッター (ボタン) ---
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (showFontScan)
                          SizedBox(
                            height: 24,
                            child: TextButton.icon(
                              onPressed: _isLoading ? null : _rescanFonts,
                              icon: const Icon(Icons.refresh, size: 14),
                              label: Text(
                                s.btnScanFonts,
                                style: const TextStyle(fontSize: 11),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                        Row(
                          children: [
                            SizedBox(
                              height: 28,
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                child: Text(
                                  s.labelCancel,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 28,
                              child: FilledButton(
                                onPressed: _applySettings,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                child: Text(
                                  s.labelOK,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- コンパクト数値入力 (スライダーなし) ---
class _CompactValueInput extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  const _CompactValueInput({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
  });

  @override
  State<_CompactValueInput> createState() => _CompactValueInputState();
}

class _CompactValueInputState extends State<_CompactValueInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(covariant _CompactValueInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSubmitted(String value) {
    final double? val = double.tryParse(value);
    if (val != null) {
      final clamped = val.clamp(widget.min, widget.max);
      widget.onChanged(clamped);
      _controller.text = clamped.toStringAsFixed(1);
    } else {
      _controller.text = widget.value.toStringAsFixed(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(widget.label, style: const TextStyle(fontSize: 11)),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              border: OutlineInputBorder(),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            onSubmitted: _handleSubmitted,
            onEditingComplete: () {
              _handleSubmitted(_controller.text);
              FocusScope.of(context).unfocus();
            },
          ),
        ),
      ],
    );
  }
}
