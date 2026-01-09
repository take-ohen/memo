import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const ColorPickerDialog({super.key, required this.initialColor});

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog>
    with SingleTickerProviderStateMixin {
  late Color _currentColor;
  late TabController _tabController;

  // プリセットカラー定義
  final List<Color> _presets = [
    // モノクロ・グレー系
    Colors.white,
    const Color(0xFFF5F5F5), // Grey 100
    const Color(0xFFE0E0E0), // Grey 300
    Colors.grey,
    const Color(0xFF616161), // Grey 700
    const Color(0xFF303030), // Dark Grey
    Colors.black,

    // 背景向け薄い色
    const Color(0xFFFFFDD0), // Cream
    const Color(0xFFE8F5E9), // Light Green
    const Color(0xFFE3F2FD), // Light Blue
    const Color(0xFFFFF3E0), // Light Orange
    const Color(0xFFF3E5F5), // Light Purple
    const Color(0xFFFFEBEE), // Light Red
    const Color(0xFFEFEBE9), // Light Brown
    // 文字・強調向け濃い色
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.brown,
    Colors.blueGrey,
  ];

  @override
  void initState() {
    super.initState();
    _currentColor = widget.initialColor;
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _updateColor(Color color) {
    setState(() {
      _currentColor = color;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 550),
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Presets', icon: Icon(Icons.palette)),
                Tab(text: 'Custom', icon: Icon(Icons.tune)),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildPresetsTab(), _buildCustomTab()],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 現在の色プレビュー
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _currentColor,
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '#${_currentColor.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0')}',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () =>
                            Navigator.of(context).pop(_currentColor),
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

  Widget _buildPresetsTab() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _presets.length,
      itemBuilder: (context, index) {
        final color = _presets[index];
        final isSelected = _currentColor.toARGB32() == color.toARGB32();
        return InkWell(
          onTap: () => _updateColor(color),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.grey.shade300,
                width: isSelected ? 3 : 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: isSelected
                ? const Icon(
                    Icons.check,
                    color: Colors.grey,
                  ) // コントラスト考慮が必要だが簡易的に
                : null,
          ),
        );
      },
    );
  }

  Widget _buildCustomTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildColorSlider('R', _currentColor.r * 255, (v) {
            _updateColor(_currentColor.withValues(red: v / 255));
          }),
          _buildColorSlider('G', _currentColor.g * 255, (v) {
            _updateColor(_currentColor.withValues(green: v / 255));
          }),
          _buildColorSlider('B', _currentColor.b * 255, (v) {
            _updateColor(_currentColor.withValues(blue: v / 255));
          }),
          const Divider(),
          _buildColorSlider('A', _currentColor.a * 255, (v) {
            _updateColor(_currentColor.withValues(alpha: v / 255));
          }),
        ],
      ),
    );
  }

  Widget _buildColorSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    final int intValue = value.round();
    final controller = TextEditingController(text: intValue.toString());

    return Row(
      children: [
        SizedBox(
          width: 30, // ラベル幅を少し広げて余裕を持たせる
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            divisions: 255,
            label: intValue.toString(),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8), // スライダーと入力欄の間隔
        SizedBox(
          width: 60, // 入力欄の幅を拡張 (50 -> 60)
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center, // 数字を中央寄せ
            style: const TextStyle(fontSize: 13), // フォントサイズを少し小さくして収まりよくする
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              _RangeTextInputFormatter(0, 255),
            ],
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (text) {
              final val = double.tryParse(text);
              if (val != null) {
                onChanged(val);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _RangeTextInputFormatter extends TextInputFormatter {
  final int min;
  final int max;

  _RangeTextInputFormatter(this.min, this.max);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final int? value = int.tryParse(newValue.text);
    if (value == null || value < min || value > max) return oldValue;
    return newValue;
  }
}
