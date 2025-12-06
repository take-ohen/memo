import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

// 分割したファイルをインポート
import 'memo_painter.dart';
import 'text_utils.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with TextInputClient {
  double _charWidth = 0.0;
  double _charHeight = 0.0;
  double _lineHeight = 0.0;
  int _cursorRow = 0;
  int _cursorCol = 0;
  int _preferredVisualX = 0;
  bool _isOverwriteMode = false;
  List<String> _lines = [''];

  bool _showGrid = false;
  TextInputConnection? _inputConnection;
  String _composingText = "";

  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _painterKey = GlobalKey();

  static const _textStyle = TextStyle(
    fontFamily: 'BIZ UDゴシック',
    fontSize: 16.0,
    color: Colors.black,
  );

  @override
  void initState() {
    super.initState();
    _calculateGlyphMetrics();
    WidgetsBinding.instance;

    _focusNode.addListener(_handleFocusChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      if (_focusNode.hasFocus) {
        _activateIme(context);
      }
    });

    _verticalScrollController.addListener(_updateImeWindowPosition);
    _horizontalScrollController.addListener(_updateImeWindowPosition);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  void _calculateGlyphMetrics() {
    final painter = TextPainter(
      text: const TextSpan(text: 'M', style: _textStyle),
      textDirection: TextDirection.ltr,
    );
    painter.layout();

    setState(() {
      _charWidth = painter.width;
      _charHeight = painter.height;
      _lineHeight = _charHeight * 1.2;
    });
  }

  void _handleTap(TapDownDetails details) {
    if (_charWidth == 0 || _charHeight == 0) return;

    setState(() {
      final Offset tapPosition = details.localPosition;
      int clickedVisualX = (tapPosition.dx / _charWidth).round();
      int clickedRow = (tapPosition.dy / _lineHeight).floor();

      _cursorRow = max(0, clickedRow);

      String currentLine = "";
      if (_cursorRow < _lines.length) {
        currentLine = _lines[_cursorRow];
      }

      // ★共通関数使用
      int lineVisualWidth = TextUtils.calcTextWidth(currentLine);

      if (clickedVisualX <= lineVisualWidth) {
        _cursorCol = _getColFromVisualX(currentLine, clickedVisualX);
      } else {
        int gap = clickedVisualX - lineVisualWidth;
        _cursorCol = currentLine.length + gap;
      }

      _preferredVisualX = clickedVisualX;

      _focusNode.requestFocus();

      WidgetsBinding.instance.addPersistentFrameCallback((_) {
        _updateImeWindowPosition();
      });
    });
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _activateIme(context);
        }
      });
    } else {
      _inputConnection?.close();
      _inputConnection = null;
    }
  }

  KeyEventResult _handleKeyPress(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final PhysicalKeyboardKey physicalKey = event.physicalKey;
    final String? character = event.character;
    bool isAlt = HardwareKeyboard.instance.isAltPressed;

    int currentLineLength = 0;
    if (_cursorRow < _lines.length) {
      currentLineLength = _lines[_cursorRow].length;
    }
    switch (physicalKey) {
      case PhysicalKeyboardKey.enter:
        final currentLine = _lines[_cursorRow];
        final part1 = currentLine.substring(0, _cursorCol);
        final part2 = currentLine.substring(_cursorCol);

        _lines[_cursorRow] = part1;
        _lines.insert(_cursorRow + 1, part2);

        _cursorRow++;
        _cursorCol = 0;
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.backspace:
        if (_cursorCol > 0) {
          final currentLine = _lines[_cursorRow];
          final part1 = currentLine.substring(0, _cursorCol - 1);
          final part2 = currentLine.substring(_cursorCol);
          _lines[_cursorRow] = part1 + part2;
          _cursorCol--;
        } else if (_cursorRow > 0) {
          final lineToAppend = _lines[_cursorRow];
          final prevLineLength = _lines[_cursorRow - 1].length;
          _lines[_cursorRow - 1] += lineToAppend;
          _lines.removeAt(_cursorRow);
          _cursorRow--;
          _cursorCol = prevLineLength;
        } else {
          return KeyEventResult.handled;
        }
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.delete:
        if (_cursorRow >= _lines.length) return KeyEventResult.handled;

        final currentLine = _lines[_cursorRow];

        if (_cursorCol < currentLine.length) {
          final part1 = currentLine.substring(0, _cursorCol);
          final part2 = (_cursorCol + 1 < currentLine.length)
              ? currentLine.substring(_cursorCol + 1)
              : '';
          _lines[_cursorRow] = part1 + part2;
        } else if (_cursorCol == currentLine.length) {
          if (_cursorRow < _lines.length - 1) {
            final nextLine = _lines[_cursorRow + 1];
            _lines[_cursorRow] += nextLine;
            _lines.removeAt(_cursorRow + 1);
          }
        }
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.insert:
        setState(() {
          _isOverwriteMode = !_isOverwriteMode;
        });
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.arrowLeft:
        if (_cursorCol > 0) {
          _cursorCol--;
        } else if (_cursorRow > 0) {
          _cursorRow--;
          _cursorCol = _lines[_cursorRow].length;
        }
        String currentLine = _lines[_cursorRow];
        String textUpToCursor = currentLine.substring(
          0,
          min(_cursorCol, currentLine.length),
        );
        // ★共通関数使用
        _preferredVisualX = TextUtils.calcTextWidth(textUpToCursor);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.arrowRight:
        if (isAlt) {
          _cursorCol++;
        } else {
          if (_cursorCol < currentLineLength) {
            _cursorCol++;
          } else if (_cursorRow < _lines.length - 1) {
            _cursorRow++;
            _cursorCol = 0;
          }
          String line = _lines[_cursorRow];
          String textUpToCursor = line.substring(
            0,
            min(_cursorCol, line.length),
          );
          // ★共通関数使用
          _preferredVisualX = TextUtils.calcTextWidth(textUpToCursor);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.arrowUp:
        if (isAlt) {
          if (_cursorRow > 0) {
            _cursorRow--;
          }
        } else {
          if (_cursorRow > 0) {
            _cursorRow--;
          }
        }

        if (_cursorRow < _lines.length) {
          String line = _lines[_cursorRow];
          // ★共通関数使用
          int lineWidth = TextUtils.calcTextWidth(line);

          if (isAlt && _preferredVisualX > lineWidth) {
            int gap = _preferredVisualX - lineWidth;
            _cursorCol = line.length + gap;
          } else {
            _cursorCol = _getColFromVisualX(line, _preferredVisualX);
          }
        } else {
          _cursorCol = _preferredVisualX;
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.arrowDown:
        if (isAlt) {
          _cursorRow++;
        } else {
          if (_cursorRow < _lines.length - 1) {
            _cursorRow++;
          }
        }

        if (_cursorRow < _lines.length) {
          String line = _lines[_cursorRow];
          // ★共通関数使用
          int lineWidth = TextUtils.calcTextWidth(line);

          if (isAlt && _preferredVisualX > lineWidth) {
            int gap = _preferredVisualX - lineWidth;
            _cursorCol = line.length + gap;
          } else {
            _cursorCol = _getColFromVisualX(line, _preferredVisualX);
          }
        } else {
          _cursorCol = _preferredVisualX;
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });
        return KeyEventResult.handled;

      default:
        if (character != null && character.isNotEmpty) {
          _fillVirtualSpaceIfNeeded();
          _insertText(character);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
    }
  }

  void _insertText(String text) {
    if (text.isEmpty) return;

    if (_cursorRow >= _lines.length) {
      int newLinesNeeded = _cursorRow - _lines.length + 1;
      for (int i = 0; i < newLinesNeeded; i++) {
        _lines.add("");
      }
    }

    var currentLine = _lines[_cursorRow];

    if (_cursorCol > currentLine.length) {
      int spacesNeeded = _cursorCol - currentLine.length;
      currentLine += ' ' * spacesNeeded;
    }

    String part1 = currentLine.substring(0, _cursorCol);
    String part2 = currentLine.substring(_cursorCol);

    if (_isOverwriteMode && part2.isNotEmpty) {
      // ★共通関数使用
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
      }
    }

    _lines[_cursorRow] = part1 + text + part2;
    _cursorCol += text.length;

    String newLine = _lines[_cursorRow];
    int safeEnd = min(_cursorCol, newLine.length);
    // ★共通関数使用
    _preferredVisualX = TextUtils.calcTextWidth(newLine.substring(0, safeEnd));

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateImeWindowPosition();
      });
    }
  }

  void _fillVirtualSpaceIfNeeded() {
    while (_lines.length <= _cursorRow) {
      _lines.add("");
    }
    if (_cursorCol > _lines[_cursorRow].length) {
      _lines[_cursorRow] = _lines[_cursorRow].padRight(_cursorCol);
    }
  }

  // ★重複していた _calcTextWidth を削除し、共通関数の TextUtils.calcTextWidth を使用

  int _getColFromVisualX(String line, int targetVisualX) {
    int currentVisualX = 0;
    for (int i = 0; i < line.runes.length; i++) {
      int charWidth = (line.runes.elementAt(i) < 128) ? 1 : 2;
      if (currentVisualX + charWidth > targetVisualX) {
        if ((targetVisualX - currentVisualX) <
            (currentVisualX + charWidth - targetVisualX)) {
          return i;
        } else {
          return i + 1;
        }
      }
      currentVisualX += charWidth;
    }
    return line.length;
  }

  void _activateIme(BuildContext context) {
    if (_inputConnection == null || !_inputConnection!.attached) {
      final viewId = View.of(context).viewId;
      print("IME接続試行 View ID: $viewId");

      final config = TextInputConfiguration(
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        viewId: viewId,
        readOnly: false,
      );

      _inputConnection = TextInput.attach(this, config);
      _inputConnection!.show();
      print("IME接続開始！");
    }
  }

  void _updateImeWindowPosition() {
    if (_inputConnection == null ||
        !_inputConnection!.attached ||
        _painterKey.currentContext == null) {
      return;
    }

    final RenderBox? renderBox =
        _painterKey.currentContext!.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final double safeCharWidth = _charWidth > 0 ? _charWidth : 16.0;
    final double safeLineHeight = _lineHeight > 0 ? _lineHeight : 24.0;

    final Matrix4 transform = renderBox.getTransformTo(null);
    _inputConnection!.setEditableSizeAndTransform(renderBox.size, transform);

    String currentLine = "";
    if (_cursorRow < _lines.length) {
      currentLine = _lines[_cursorRow];
    }

    String textBeforeCursor = "";
    if (_cursorCol <= currentLine.length) {
      textBeforeCursor = currentLine.substring(0, _cursorCol);
    } else {
      textBeforeCursor =
          currentLine + (' ' * (_cursorCol - currentLine.length));
    }

    // ★共通関数使用
    int visualX = TextUtils.calcTextWidth(textBeforeCursor);
    final double localPixelX = visualX * safeCharWidth;
    final double localPixelY = _cursorRow * safeLineHeight;

    _inputConnection!.setComposingRect(
      Rect.fromLTWH(localPixelX, localPixelY, safeCharWidth, safeLineHeight),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Free-form Memo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Row(
            children: [
              const Text('Grid'),
              Switch(
                value: _showGrid,
                onChanged: (value) {
                  setState(() {
                    _showGrid = value;
                  });
                },
              ),
            ],
          ),
        ],
      ),
      body: Scrollbar(
        controller: _verticalScrollController,
        thumbVisibility: true,
        trackVisibility: true,
        child: Scrollbar(
          controller: _horizontalScrollController,
          thumbVisibility: true,
          trackVisibility: true,
          notificationPredicate: (notif) => notif.depth == 1,
          child: SingleChildScrollView(
            controller: _verticalScrollController,
            scrollDirection: Axis.vertical,
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: (FocusNode node, KeyEvent event) {
                final result = _handleKeyPress(event);
                if (result == KeyEventResult.handled) {
                  setState(() {});
                }
                return result;
              },
              child: SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
                child: GestureDetector(
                  onTapDown: _handleTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 2000,
                      minHeight: 2000,
                    ),
                    child: CustomPaint(
                      key: _painterKey,
                      painter: MemoPainter(
                        lines: _lines,
                        charWidth: _charWidth,
                        charHeight: _charHeight,
                        showGrid: _showGrid,
                        isOverwriteMode: _isOverwriteMode,
                        cursorRow: _cursorRow,
                        cursorCol: _cursorCol,
                        lineHeight: _lineHeight,
                        textStyle: _textStyle,
                        composingText: _composingText,
                      ),
                      size: Size.infinite,
                      child: Container(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // IME必須メソッド
  @override
  TextEditingValue get currentTextEditingValue => TextEditingValue.empty;

  @override
  void updateEditingValue(TextEditingValue value) {
    print("IMEからの入力: text=${value.text}, composing=${value.composing}");
    if (!value.composing.isValid) {
      if (value.text.isNotEmpty) {
        setState(() {
          _insertText(value.text);
          _composingText = "";
        });
      }
      if (_inputConnection != null && _inputConnection!.attached) {
        _inputConnection!.setEditingState(TextEditingValue.empty);
      }
    } else {
      setState(() {
        _composingText = value.text;
      });
      _updateImeWindowPosition();
    }
  }

  @override
  void performAction(TextInputAction action) {
    print("IMEアクション: $action");
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}
  @override
  void showAutocorrectionPromptRect(int start, int end) {}
  @override
  void connectionClosed() {
    print("IME接続が切れました");
    _inputConnection = null;
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}
  @override
  void insertContent(KeyboardInsertedContent content) {}
  @override
  void showToolbar() {}
  @override
  AutofillScope? get currentAutofillScope => null;
}
