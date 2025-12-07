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

  // 矩形選択の範囲の開始位置
  int? _selectionOriginRow;
  int? _selectionOriginCol;

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
      // 選択解除(タップ時はリセット)
      _selectionOriginRow = null;
      _selectionOriginCol = null;

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
        _cursorCol = TextUtils.getColFromVisualX(currentLine, clickedVisualX);
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
    bool isShift = HardwareKeyboard.instance.isShiftPressed;
    bool isControl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed; // for  Mac

    if (isControl && physicalKey == PhysicalKeyboardKey.keyC) {
      _copySelection();
      return KeyEventResult.handled;
    }

    //
    if (isShift) {
      if (_selectionOriginRow == null) {
        setState(() {
          _selectionOriginRow = _cursorRow;
          _selectionOriginCol = _cursorCol;
        });
      }
    } else {
      // Shiftが押されていなければ選択解除 (矢印キー以外で解除したい場合もあるので
      // ここでリセットするかは要件次第だが、一旦移動系はリセット前提)
      // ただし、文字入力時などは別途考える必要あり。今回は矢印移動で解説。
    }

    // ヘルパー関数 カーソル移動処理の前後に呼ぶ
    void handleSelectionOnMove() {
      if (isShift) {
        _selectionOriginRow ??= _cursorRow;
        _selectionOriginCol ??= _cursorCol;
      } else {
        _selectionOriginRow = null;
        _selectionOriginCol = null;
      }
    }

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
        handleSelectionOnMove(); // 選択状態更新
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
        _preferredVisualX = TextUtils.calcTextWidth(textUpToCursor);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.arrowRight:
        handleSelectionOnMove(); // 選択状態更新
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
          _preferredVisualX = TextUtils.calcTextWidth(textUpToCursor);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.arrowUp:
        handleSelectionOnMove();
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
          int lineWidth = TextUtils.calcTextWidth(line);

          if (isAlt && _preferredVisualX > lineWidth) {
            int gap = _preferredVisualX - lineWidth;
            _cursorCol = line.length + gap;
          } else {
            _cursorCol = TextUtils.getColFromVisualX(line, _preferredVisualX);
          }
        } else {
          _cursorCol = _preferredVisualX;
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.arrowDown:
        handleSelectionOnMove();
        if (isAlt) {
          _cursorRow++;
        } else {
          if (_cursorRow < _lines.length - 1) {
            _cursorRow++;
          }
        }

        if (_cursorRow < _lines.length) {
          String line = _lines[_cursorRow];
          int lineWidth = TextUtils.calcTextWidth(line);

          if (isAlt && _preferredVisualX > lineWidth) {
            int gap = _preferredVisualX - lineWidth;
            _cursorCol = line.length + gap;
          } else {
            _cursorCol = TextUtils.getColFromVisualX(line, _preferredVisualX);
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

  // 選択範囲をコピーする。
  void _copySelection() async {
    // 選択されていない場合何もしない。
    if (_selectionOriginRow == null || _selectionOriginCol == null) return;

    // 範囲の特定（行）
    int startRow = min(_selectionOriginRow!, _cursorRow);
    int endRow = max(_selectionOriginRow!, _cursorRow);

    // 範囲の特定( 見た目のX座標: VisualX )
    // Painterと同じロジックで「矩形の左端」と「矩形の右端」を算出する

    // 開始地点のVisualX
    String originLine = "";
    if (_selectionOriginRow! < _lines.length) {
      originLine = _lines[_selectionOriginRow!];
    }
    String originText = "";
    if (_selectionOriginCol! <= originLine.length) {
      originText = originLine.substring(0, _selectionOriginCol!);
    } else {
      originText =
          originLine + (' ' * (_selectionOriginCol! - originLine.length));
    }
    // 共通関数
    int originVisualX = TextUtils.calcTextWidth(originText);

    // カーソル地点のVisualX
    String cursorLine = "";
    if (_cursorRow < _lines.length) {
      cursorLine = _lines[_cursorRow];
    }
    String cursorText = "";
    if (_cursorCol <= cursorLine.length) {
      cursorText = cursorLine.substring(0, _cursorCol);
    } else {
      cursorText = cursorLine + (' ' * (_cursorCol - cursorLine.length));
    }
    // 共通関数
    int cursorVisualX = TextUtils.calcTextWidth(cursorText);

    int minVisualX = min(originVisualX, cursorVisualX);
    int maxVisualX = max(originVisualX, cursorVisualX);

    // 各行からテキストを抽出して結合
    StringBuffer buffer = StringBuffer();

    for (int i = startRow; i <= endRow; i++) {
      String line = "";
      if (i < _lines.length) {
        line = _lines[i];
      }
      // VisualX から 文字列のインデックス(col) に変換
      // ★共通関数
      int startCol = TextUtils.getColFromVisualX(line, minVisualX);
      int endCol = TextUtils.getColFromVisualX(line, maxVisualX);

      if (startCol > endCol) {
        int temp = startCol;
        startCol = endCol;
        endCol = temp;
      }

      // 文字列切り出し
      // endColが行の長さを超えないようにガード
      String extracted = "";
      if (startCol < line.length) {
        int safeEnd = min(endCol, line.length);
        extracted = line.substring(startCol, safeEnd);
      }

      // 必要であれば、矩形として形を保つために右側をスペースで埋める処理をここに入れることも可能ですが、
      // まずは「ある文字だけコピー」します。

      buffer.writeln(extracted);
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));

    print("Copied to clipboard:\n${buffer.toString()}");
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
                        selectionOriginRow: _selectionOriginRow,
                        selectionOriginCol: _selectionOriginCol,
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
