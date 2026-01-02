import 'package:flutter/material.dart';
import 'editor_controller.dart';
import 'font_manager.dart';
import 'l10n/app_localizations.dart';

enum SettingsTab { editor, ui, view }

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

  // View Settings (Line Number & Ruler)
  late int _lineNumberColor;
  late double _lineNumberFontSize;
  late int _rulerColor;
  late double _rulerFontSize;

  // カラープリセット
  final Map<String, int> _colorPresets = {
    'Grey': 0xFF9E9E9E,
    'Black': 0xFF000000,
    'Red': 0xFFF44336,
    'Blue': 0xFF2196F3,
    'Green': 0xFF4CAF50,
  };

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

    _lineNumberColor = widget.controller.lineNumberColor;
    _lineNumberFontSize = widget.controller.lineNumberFontSize;
    _rulerColor = widget.controller.rulerColor;
    _rulerFontSize = widget.controller.rulerFontSize;

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
    widget.controller.setViewSettings(
      lnColor: _lineNumberColor,
      lnSize: _lineNumberFontSize,
      rColor: _rulerColor,
      rSize: _rulerFontSize,
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
        _buildSectionTitle("Canvas Size (Minimum)"),
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
    // 行番号とルーラーの設定UI
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCanvasSection(
            minColumns: _minColumns,
            minLines: _minLines,
            onCanvasSizeChanged: (c, l) {
              _minColumns = c;
              _minLines = l;
            },
          ),
          const Divider(height: 32),
          _buildSectionTitle('Line Numbers'),
          _buildColorPicker(
            label: 'Color',
            value: _lineNumberColor,
            onChanged: (v) => setState(() => _lineNumberColor = v),
          ),
          _buildSlider(
            label: 'Font Size',
            value: _lineNumberFontSize,
            onChanged: (v) => setState(() => _lineNumberFontSize = v),
          ),
          const Divider(height: 32),
          _buildSectionTitle('Column Ruler'),
          _buildColorPicker(
            label: 'Color',
            value: _rulerColor,
            onChanged: (v) => setState(() => _rulerColor = v),
          ),
          _buildSlider(
            label: 'Font Size',
            value: _rulerFontSize,
            onChanged: (v) => setState(() => _rulerFontSize = v),
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

  Widget _buildColorPicker({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label)),
        DropdownButton<int>(
          value: _colorPresets.containsValue(value) ? value : null,
          hint: const Text('Custom'),
          items: _colorPresets.entries.map((e) {
            return DropdownMenuItem(
              value: e.value,
              child: Row(
                children: [
                  Container(width: 16, height: 16, color: Color(e.value)),
                  const SizedBox(width: 8),
                  Text(e.key),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
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
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
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
