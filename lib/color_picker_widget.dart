import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'l10n/app_localizations.dart';

class ColorPickerWidget extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;
  final List<Color> savedColors;
  final ValueChanged<Color> onSaveColor;
  final ValueChanged<Color> onDeleteColor;

  const ColorPickerWidget({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
    required this.savedColors,
    required this.onSaveColor,
    required this.onDeleteColor,
  });

  @override
  State<ColorPickerWidget> createState() => _ColorPickerWidgetState();
}

class _ColorPickerWidgetState extends State<ColorPickerWidget> {
  late HSVColor _currentHsvColor;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentHsvColor = HSVColor.fromColor(widget.initialColor);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.delete) {
          final currentColorValue = _currentHsvColor.toColor().value;
          final exists = widget.savedColors.any(
            (c) => c.value == currentColorValue,
          );
          if (exists) {
            widget.onDeleteColor(_currentHsvColor.toColor());
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Saturation / Value Picker Area
          SizedBox(
            height: 150,
            child: _SaturationValuePicker(
              hsvColor: _currentHsvColor,
              onChanged: _onHsvChanged,
            ),
          ),
          const SizedBox(height: 12),
          // 2. Hue Slider
          _HueSlider(hsvColor: _currentHsvColor, onChanged: _onHsvChanged),
          const SizedBox(height: 8),
          // 3. Alpha Slider
          _AlphaSlider(hsvColor: _currentHsvColor, onChanged: _onHsvChanged),
          const SizedBox(height: 12),
          // 4. Preview & Info
          Row(
            children: [
              // Preview Box
              Container(
                width: 60,
                height: 40,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(
                    children: [
                      // Checkerboard background
                      CustomPaint(
                        size: Size.infinite,
                        painter: _CheckerBoardPainter(),
                      ),
                      // Color
                      Container(color: _currentHsvColor.toColor()),
                      // Sample Text
                      Center(
                        child: Text(
                          "Abc",
                          style: TextStyle(
                            color:
                                _currentHsvColor.toColor().computeLuminance() >
                                    0.5
                                ? Colors.black
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Color Info (Hex)
              Expanded(
                child: Text(
                  '#${_currentHsvColor.toColor().value.toRadixString(16).toUpperCase().padLeft(8, '0')}',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              // Add Preset Button
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: s.tooltipAddPreset,
                onPressed: () {
                  widget.onSaveColor(_currentHsvColor.toColor());
                  _focusNode.requestFocus();
                },
              ),
            ],
          ),
          const Divider(),
          // 5. Presets
          Text(
            s.labelPresets,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 100,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: widget.savedColors.length,
              itemBuilder: (context, index) {
                final color = widget.savedColors[index];
                final isSelected =
                    color.value == _currentHsvColor.toColor().value;
                return GestureDetector(
                  onTap: () {
                    _onHsvChanged(HSVColor.fromColor(color));
                    _focusNode.requestFocus();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      border: Border.all(
                        color: isSelected ? Colors.blue : Colors.grey.shade300,
                        width: isSelected ? 3 : 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _onHsvChanged(HSVColor color) {
    setState(() {
      _currentHsvColor = color;
    });
    widget.onColorChanged(color.toColor());
  }
}

// --- Components ---

class _SaturationValuePicker extends StatelessWidget {
  final HSVColor hsvColor;
  final ValueChanged<HSVColor> onChanged;

  const _SaturationValuePicker({
    required this.hsvColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanDown: (details) =>
              _handleInput(details.localPosition, constraints.biggest),
          onPanUpdate: (details) =>
              _handleInput(details.localPosition, constraints.biggest),
          child: Stack(
            children: [
              // Base Hue Color
              Container(
                color: HSVColor.fromAHSV(1.0, hsvColor.hue, 1.0, 1.0).toColor(),
              ),
              // Saturation Gradient (White -> Transparent)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.white, Colors.transparent],
                  ),
                ),
              ),
              // Value Gradient (Transparent -> Black)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black],
                  ),
                ),
              ),
              // Cursor
              Positioned(
                left: hsvColor.saturation * constraints.maxWidth - 5,
                top: (1.0 - hsvColor.value) * constraints.maxHeight - 5,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 2),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleInput(Offset localPos, Size size) {
    final saturation = (localPos.dx / size.width).clamp(0.0, 1.0);
    final value = 1.0 - (localPos.dy / size.height).clamp(0.0, 1.0);
    onChanged(hsvColor.withSaturation(saturation).withValue(value));
  }
}

class _HueSlider extends StatelessWidget {
  final HSVColor hsvColor;
  final ValueChanged<HSVColor> onChanged;

  const _HueSlider({required this.hsvColor, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onPanDown: (details) =>
                _handleInput(details.localPosition, constraints.biggest),
            onPanUpdate: (details) =>
                _handleInput(details.localPosition, constraints.biggest),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFFF0000),
                    Color(0xFFFFFF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FFFF),
                    Color(0xFF0000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0000),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: (hsvColor.hue / 360.0) * constraints.maxWidth - 10,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.grey),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 2),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleInput(Offset localPos, Size size) {
    final hue = ((localPos.dx / size.width) * 360.0).clamp(0.0, 360.0);
    onChanged(hsvColor.withHue(hue));
  }
}

class _AlphaSlider extends StatelessWidget {
  final HSVColor hsvColor;
  final ValueChanged<HSVColor> onChanged;

  const _AlphaSlider({required this.hsvColor, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onPanDown: (details) =>
                _handleInput(details.localPosition, constraints.biggest),
            onPanUpdate: (details) =>
                _handleInput(details.localPosition, constraints.biggest),
            child: Stack(
              children: [
                // Checkerboard
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _CheckerBoardPainter(),
                  ),
                ),
                // Gradient
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      colors: [
                        hsvColor.toColor().withValues(alpha: 0.0),
                        hsvColor.toColor().withValues(alpha: 1.0),
                      ],
                    ),
                  ),
                ),
                // Thumb
                Positioned(
                  left: hsvColor.alpha * constraints.maxWidth - 10,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.grey),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 2),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _handleInput(Offset localPos, Size size) {
    final alpha = (localPos.dx / size.width).clamp(0.0, 1.0);
    onChanged(hsvColor.withAlpha(alpha));
  }
}

class _CheckerBoardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.grey.shade300;
    const double cellSize = 8.0;

    for (double y = 0; y < size.height; y += cellSize) {
      for (double x = 0; x < size.width; x += cellSize) {
        if (((x / cellSize).floor() + (y / cellSize).floor()) % 2 == 0) {
          canvas.drawRect(Rect.fromLTWH(x, y, cellSize, cellSize), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
