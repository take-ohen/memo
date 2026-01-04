import 'package:flutter/material.dart';
import 'editor_controller.dart';
import 'font_manager.dart';
import 'l10n/app_localizations.dart';
import 'color_picker_widget.dart'; // 新規Widgetをインポート
import 'memo_painter.dart'; // プレビュー描画用

enum SettingsTab { editor, ui, view }

enum ColorTarget { background, text, lineNumber, ruler, grid }

class SettingsDialog extends StatefulWidget {
  final EditorController controller;
  final SettingsTab initialTab;

  const SettingsDialog({
    super.key,
    required this.controller,
    this.initialTab = SettingsTab.editor,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FontManager _fontManager = FontManager();
  bool _isLoading = false;

  // Editor Settings
  late TextEditingController _editorFontController;
  late double _editorFontSize;
  late bool _editorBold;
  late bool _editorItalic;
  late int _minColumns;
  late int _minLines;

  // UI Settings
  late TextEditingController _uiFontController;
  late double _uiFontSize;
  late bool _uiBold;
  late bool _uiItalic;

  // Editor Colors
  late int _editorBackgroundColor;
  late int _editorTextColor;

  // View Settings (Line Number & Ruler)
  late int _lineNumberColor;
  late double _lineNumberFontSize;
  late int _rulerColor;
  late double _rulerFontSize;
  late int _gridColor;

  // Viewタブ用状態
  ColorTarget _activeColorTarget = ColorTarget.background;

  // プレビュー用ダミーデータ
  final List<String> _previewLines = [
    'void main() {',
    '  print("Hello, World!");',
    '  // Preview Code',
    '}',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );

    // 初期値のロード
    _editorFontController = TextEditingController(
      text: widget.controller.fontFamily,
    );
    _editorFontSize = widget.controller.fontSize;
    _editorBold = widget.controller.editorBold;
    _editorItalic = widget.controller.editorItalic;
    _minColumns = widget.controller.minColumns;
    _minLines = widget.controller.minLines;

    _uiFontController = TextEditingController(
      text: widget.controller.uiFontFamily,
    );
    _uiFontSize = widget.controller.uiFontSize;
    _uiBold = widget.controller.uiBold;
    _uiItalic = widget.controller.uiItalic;

    _editorBackgroundColor = widget.controller.editorBackgroundColor;
    _editorTextColor = widget.controller.editorTextColor;

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
    _tabController.dispose();
    _editorFontController.dispose();
    _uiFontController.dispose();
    super.dispose();
  }

  void _applySettings() {
    widget.controller.setEditorFont(
      _editorFontController.text,
      _editorFontSize,
      _editorBold,
      _editorItalic,
    );
    widget.controller.setCanvasSize(_minColumns, _minLines);
    widget.controller.setUiFont(
      _uiFontController.text,
      _uiFontSize,
      _uiBold,
      _uiItalic,
    );
    widget.controller.setEditorColors(_editorBackgroundColor, _editorTextColor);
    widget.controller.setViewSettings(
      lnColor: _lineNumberColor,
      lnSize: _lineNumberFontSize,
      rColor: _rulerColor,
      rSize: _rulerFontSize,
      gColor: _gridColor,
    );
    Navigator.of(context).pop();
  }

  // --- 共通パーツ: フォント設定セクション ---
  Widget _buildFontSection({
    required BuildContext context,
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
        _buildSectionTitle('Font Settings'),
        // フォント選択
        LayoutBuilder(
          builder: (context, constraints) {
            return DropdownMenu<String>(
              width: constraints.maxWidth,
              controller: fontController,
              enableFilter: true,
              requestFocusOnTap: true,
              label: Text(s.labelFontFamily),
              dropdownMenuEntries: fontList.map((f) {
                return DropdownMenuEntry<String>(value: f, label: f);
              }).toList(),
              onSelected: (value) {
                if (value != null) {
                  setState(() {
                    fontController.text = value;
                  });
                }
              },
            );
          },
        ),
        const SizedBox(height: 16),
        // サイズ
        Row(
          children: [
            Text("${s.labelFontSize}: ${fontSize.toStringAsFixed(1)}"),
            Expanded(
              child: Slider(
                value: fontSize,
                min: 8.0,
                max: 72.0,
                divisions: 128,
                onChanged: (v) => setState(() => onSizeChanged(v)),
              ),
            ),
          ],
        ),
        // スタイル
        Row(
          children: [
            Checkbox(
              value: isBold,
              onChanged: (v) => setState(() => onBoldChanged(v)),
            ),
            Text(s.labelBold),
            const SizedBox(width: 16),
            Checkbox(
              value: isItalic,
              onChanged: (v) => setState(() => onItalicChanged(v)),
            ),
            Text(s.labelItalic),
          ],
        ),
      ],
    );
  }

  // --- 共通パーツ: キャンバス設定セクション ---
  Widget _buildCanvasSection({
    required int minColumns,
    required int minLines,
    required Function(int, int) onCanvasSizeChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Canvas Size (Min)",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        // Columns
        Row(
          children: [
            SizedBox(width: 60, child: Text("Cols: $minColumns")),
            Expanded(
              child: Slider(
                value: minColumns.toDouble(),
                min: 80,
                max: 1000,
                divisions: 920,
                onChanged: (v) =>
                    setState(() => onCanvasSizeChanged(v.toInt(), minLines)),
              ),
            ),
          ],
        ),
        // Lines
        Row(
          children: [
            SizedBox(width: 60, child: Text("Lines: $minLines")),
            Expanded(
              child: Slider(
                value: minLines.toDouble(),
                min: 40,
                max: 1000,
                divisions: 960,
                onChanged: (v) =>
                    setState(() => onCanvasSizeChanged(minColumns, v.toInt())),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- 共通パーツ: プレビュー ---
  Widget _buildPreviewSection({
    required BuildContext context,
    required TextEditingController fontController,
    required double fontSize,
    required bool isBold,
    required bool isItalic,
  }) {
    final s = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Text("Preview", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SizedBox(
          height: 100, // 高さを固定してオーバーフローを防ぐ
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: SingleChildScrollView(
              child: Text(
                s.previewText,
                style: TextStyle(
                  fontFamily: fontController.text,
                  fontSize: fontSize,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Editorタブの構築 ---
  Widget _buildEditorTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFontSection(
            context: context,
            fontList: _fontManager.monospaceFonts,
            fontController: _editorFontController,
            fontSize: _editorFontSize,
            isBold: _editorBold,
            isItalic: _editorItalic,
            onSizeChanged: (v) => _editorFontSize = v,
            onBoldChanged: (v) => _editorBold = v ?? false,
            onItalicChanged: (v) => _editorItalic = v ?? false,
          ),
          _buildPreviewSection(
            context: context,
            fontController: _editorFontController,
            fontSize: _editorFontSize,
            isBold: _editorBold,
            isItalic: _editorItalic,
          ),
        ],
      ),
    );
  }

  // --- UIタブの構築 ---
  Widget _buildUiTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFontSection(
            context: context,
            fontList: _fontManager.allFonts,
            fontController: _uiFontController,
            fontSize: _uiFontSize,
            isBold: _uiBold,
            isItalic: _uiItalic,
            onSizeChanged: (v) => _uiFontSize = v,
            onBoldChanged: (v) => _uiBold = v ?? false,
            onItalicChanged: (v) => _uiItalic = v ?? false,
          ),
          _buildPreviewSection(
            context: context,
            fontController: _uiFontController,
            fontSize: _uiFontSize,
            isBold: _uiBold,
            isItalic: _uiItalic,
          ),
        ],
      ),
    );
  }

  Widget _buildViewTab(BuildContext context) {
    // プレビュー用のメトリクス計算
    final previewTextStyle = TextStyle(
      fontFamily: _editorFontController.text,
      fontSize: _editorFontSize,
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
    switch (_activeColorTarget) {
      case ColorTarget.background:
        currentColor = Color(_editorBackgroundColor);
        break;
      case ColorTarget.text:
        currentColor = Color(_editorTextColor);
        break;
      case ColorTarget.lineNumber:
        currentColor = Color(_lineNumberColor);
        break;
      case ColorTarget.ruler:
        currentColor = Color(_rulerColor);
        break;
      case ColorTarget.grid:
        currentColor = Color(_gridColor);
        break;
    }

    // 行番号とルーラーの設定UI
    return Padding(
      padding: const EdgeInsets.all(8.0), // 余白を削減
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- 左側: プレビューエリア (Expanded) ---
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('Preview'),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                    ),
                    child: Column(
                      children: [
                        // ルーラー
                        Container(
                          height: 24,
                          color: Colors.grey.shade200,
                          child: Row(
                            children: [
                              const SizedBox(width: 40), // 行番号分のスペース
                              Expanded(
                                child: ClipRect(
                                  child: CustomPaint(
                                    size: const Size(double.infinity, 24),
                                    painter: ColumnRulerPainter(
                                      charWidth: charWidth,
                                      lineHeight: 24,
                                      textStyle: TextStyle(
                                        fontFamily: _editorFontController.text,
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
                        // エディタ本体
                        Expanded(
                          child: Row(
                            children: [
                              // 行番号
                              Container(
                                width: 40,
                                color: Colors.grey.shade200,
                                child: CustomPaint(
                                  size: Size.infinite,
                                  painter: LineNumberPainter(
                                    lineCount: _previewLines.length,
                                    lineHeight: lineHeight,
                                    textStyle: TextStyle(
                                      fontFamily: _editorFontController.text,
                                      fontSize: _lineNumberFontSize,
                                      color: Color(_lineNumberColor),
                                    ),
                                  ),
                                ),
                              ),
                              // テキストエリア
                              Expanded(
                                child: Container(
                                  color: Color(_editorBackgroundColor),
                                  child: ClipRect(
                                    child: CustomPaint(
                                      painter: MemoPainter(
                                        lines: _previewLines,
                                        charWidth: charWidth,
                                        charHeight: charHeight,
                                        lineHeight: lineHeight,
                                        showGrid: true, // グリッド確認のため常時ON
                                        isOverwriteMode: false,
                                        cursorRow: 0,
                                        cursorCol: 0,
                                        textStyle: previewTextStyle.copyWith(
                                          color: Color(_editorTextColor),
                                          fontWeight: _editorBold
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          fontStyle: _editorItalic
                                              ? FontStyle.italic
                                              : FontStyle.normal,
                                        ),
                                        composingText: "",
                                        showCursor: true,
                                        gridColor: Color(_gridColor),
                                      ),
                                      size: Size.infinite,
                                    ),
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
                const SizedBox(height: 8),
                // Canvas Size設定を左下に配置
                _buildCanvasSection(
                  minColumns: _minColumns,
                  minLines: _minLines,
                  onCanvasSizeChanged: (c, l) {
                    _minColumns = c;
                    _minLines = l;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // --- 右側: 設定コントロール (固定幅) ---
          SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('Settings'),
                // 編集対象の選択
                Row(
                  children: [
                    const Text("Target:", style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 30,
                        child: DropdownButton<ColorTarget>(
                          isExpanded: true,
                          value: _activeColorTarget,
                          underline: Container(height: 1, color: Colors.grey),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: ColorTarget.background,
                              child: Text("Background"),
                            ),
                            DropdownMenuItem(
                              value: ColorTarget.text,
                              child: Text("Text"),
                            ),
                            DropdownMenuItem(
                              value: ColorTarget.lineNumber,
                              child: Text("Line Number"),
                            ),
                            DropdownMenuItem(
                              value: ColorTarget.ruler,
                              child: Text("Ruler"),
                            ),
                            DropdownMenuItem(
                              value: ColorTarget.grid,
                              child: Text("Grid"),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _activeColorTarget = value;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // カラーピッカー (埋め込み)
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ColorPickerWidget(
                    color: currentColor,
                    onColorChanged: (newColor) {
                      setState(() {
                        switch (_activeColorTarget) {
                          case ColorTarget.background:
                            _editorBackgroundColor = newColor.value;
                            break;
                          case ColorTarget.text:
                            _editorTextColor = newColor.value;
                            break;
                          case ColorTarget.lineNumber:
                            _lineNumberColor = newColor.value;
                            break;
                          case ColorTarget.ruler:
                            _rulerColor = newColor.value;
                            break;
                          case ColorTarget.grid:
                            _gridColor = newColor.value;
                            break;
                        }
                      });
                    },
                  ),
                ),

                const SizedBox(height: 8),
                // フォントサイズ調整用スライダー (行番号・ルーラー用)
                if (_activeColorTarget == ColorTarget.lineNumber)
                  _buildSlider(
                    label: 'Font Size',
                    value: _lineNumberFontSize,
                    onChanged: (v) => setState(() => _lineNumberFontSize = v),
                  ),
                if (_activeColorTarget == ColorTarget.ruler)
                  _buildSlider(
                    label: 'Font Size',
                    value: _rulerFontSize,
                    onChanged: (v) => setState(() => _rulerFontSize = v),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: 8.0,
            max: 32.0,
            divisions: 48,
            label: value.toStringAsFixed(1),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 40, child: Text(value.toStringAsFixed(1))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 850,
          maxHeight: 550,
        ), // 横長に拡張
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: s.settingsTabEditor),
                Tab(text: s.settingsTabUi),
                const Tab(text: 'View'),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(s.msgScanningFonts),
                        ],
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        // エディタ設定タブ
                        _buildEditorTab(context),
                        // UI設定タブ
                        _buildUiTab(context),
                        // 表示設定タブ
                        _buildViewTab(context),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _isLoading ? null : _rescanFonts,
                    icon: const Icon(Icons.refresh),
                    label: Text(s.btnScanFonts),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _applySettings,
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
