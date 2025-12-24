import 'package:flutter/material.dart';
import 'editor_controller.dart';
import 'font_manager.dart';
import 'l10n/app_localizations.dart';

class SettingsDialog extends StatefulWidget {
  final EditorController controller;

  const SettingsDialog({super.key, required this.controller});

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

  // UI Settings
  late TextEditingController _uiFontController;
  late double _uiFontSize;
  late bool _uiBold;
  late bool _uiItalic;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // 初期値のロード
    _editorFontController = TextEditingController(
      text: widget.controller.fontFamily,
    );
    _editorFontSize = widget.controller.fontSize;
    _editorBold = widget.controller.editorBold;
    _editorItalic = widget.controller.editorItalic;

    _uiFontController = TextEditingController(
      text: widget.controller.uiFontFamily,
    );
    _uiFontSize = widget.controller.uiFontSize;
    _uiBold = widget.controller.uiBold;
    _uiItalic = widget.controller.uiItalic;

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
    widget.controller.setUiFont(
      _uiFontController.text,
      _uiFontSize,
      _uiBold,
      _uiItalic,
    );
    Navigator.of(context).pop();
  }

  Widget _buildFontTab({
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

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // フォント選択 (入力も可能)
          LayoutBuilder(
            builder: (context, constraints) {
              return DropdownMenu<String>(
                width: constraints.maxWidth,
                controller: fontController,
                enableFilter: true, // 入力してフィルタリング可能
                requestFocusOnTap: true, // タップで入力可能にする
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
          const Divider(height: 32),
          // プレビュー
          Expanded(
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
      ),
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
                        _buildFontTab(
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
                        // UI設定タブ
                        _buildFontTab(
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
