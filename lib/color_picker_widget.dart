import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'l10n/app_localizations.dart';

class ColorPickerWidget extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onColorChanged;

  const ColorPickerWidget({
    super.key,
    required this.color,
    required this.onColorChanged,
  });

  @override
  State<ColorPickerWidget> createState() => _ColorPickerWidgetState();
}

class _ColorPickerWidgetState extends State<ColorPickerWidget>
    with SingleTickerProviderStateMixin {
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
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 36,
          child: TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.palette, size: 14),
                    const SizedBox(width: 4),
                    Text(s.labelPresets, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.tune, size: 14),
                    const SizedBox(width: 4),
                    Text(s.labelCustom, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],
            labelPadding: EdgeInsets.zero,
            labelStyle: const TextStyle(fontSize: 12),
          ),
        ),
        SizedBox(
          height: 180,
          child: TabBarView(
            controller: _tabController,
            children: [_buildPresetsTab(), _buildCustomTab()],
          ),
        ),
      ],
    );
  }

  Widget _buildPresetsTab() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 12, // さらに小さく (8 -> 12)
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _presets.length,
      itemBuilder: (context, index) {
        final color = _presets[index];
        final isSelected = widget.color.toARGB32() == color.toARGB32();
        return InkWell(
          onTap: () => widget.onColorChanged(color),
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
                ? const Icon(Icons.check, color: Colors.grey)
                : null,
          ),
        );
      },
    );
  }

  Widget _buildCustomTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          _buildColorSlider('R', widget.color.r * 255, (v) {
            widget.onColorChanged(widget.color.withValues(red: v / 255));
          }),
          _buildColorSlider('G', widget.color.g * 255, (v) {
            widget.onColorChanged(widget.color.withValues(green: v / 255));
          }),
          _buildColorSlider('B', widget.color.b * 255, (v) {
            widget.onColorChanged(widget.color.withValues(blue: v / 255));
          }),
          const SizedBox(height: 4),
          _buildColorSlider('A', widget.color.a * 255, (v) {
            widget.onColorChanged(widget.color.withValues(alpha: v / 255));
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
    // カーソル移動問題を避けるため、キーは値に依存させない
    final controller = TextEditingController(text: intValue.toString());
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: value,
                min: 0,
                max: 255,
                divisions: 255,
                label: intValue.toString(),
                onChanged: onChanged,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _RangeTextInputFormatter(0, 255),
              ],
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 8,
                ),
                border: OutlineInputBorder(),
              ),
              onChanged: (text) {
                final val = double.tryParse(text);
                if (val != null) {
                  onChanged(val);
                }
              },
            ),
          ),
        ],
      ),
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
