import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';

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
  int _cursorRow = 0; // 現在のlines上でのカーソル位置
  int _cursorCol = 0; // 現在のlines上でのカーソル位置(全半角区別なし)
  int _preferredVisualX = 0; // 見た目(全半角区別あり)の現在のカーソル位置(col)
  bool _isOverwriteMode = false; // 上書きモード フラグ
  bool _isDragging = false; // マウスドラッグ開始時のフラグ管理
  List<String> _lines = [''];

  bool _showGrid = false;
  TextInputConnection? _inputConnection;
  String _composingText = "";

  // カーソル点滅処理
  Timer? _cursorBlinkTimer;
  bool _showCursor = true; // カーソル表示フラグ

  // 矩形選択の範囲の開始位置
  int? _selectionOriginRow;
  int? _selectionOriginCol;
  bool _isRectangularSelection = false; // 矩形選択モードフラグ

  // 操作履歴スタック
  List<HistoryEntry> _undoStack = [];
  List<HistoryEntry> _redoStack = [];

  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _painterKey = GlobalKey();

  static const _textStyle = TextStyle(
    fontFamily: 'BIZ UDゴシック',
    fontSize: 16.0,
    color: Colors.black,
  );

  // テスト専用のゲッター(抜け道)
  @visibleForTesting
  int get debugCursorCol => _cursorCol;

  @visibleForTesting
  int get debugCursorRow => _cursorRow;

  @visibleForTesting
  List<String> get debugLines => _lines;

  @override
  void initState() {
    super.initState();
    _calculateGlyphMetrics();
    WidgetsBinding.instance;

    _focusNode.addListener(_handleFocusChange);

    _startCursorTimer(); // カーソル点滅用

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
    _cursorBlinkTimer?.cancel(); // カーソル点滅用
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

  void _handleTap(Offset localPosition) {
    if (_charWidth == 0 || _charHeight == 0) return;

    setState(() {
      int clickedVisualX = (localPosition.dx / _charWidth).round();
      int clickedRow = (localPosition.dy / _lineHeight).floor();

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

  // ヘルパー関数 カーソル移動処理の前後に呼ぶ
  void _handleSelectionOnMove(bool isShift, bool isAlt) {
    if (isShift) {
      _selectionOriginRow ??= _cursorRow;
      _selectionOriginCol ??= _cursorCol;
      _isRectangularSelection = isAlt; // Altキーの状態に合わせてモード切替
    } else {
      _selectionOriginRow = null;
      _selectionOriginCol = null;
    }
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

  // カーソル点滅用のタイマー
  void _startCursorTimer() {
    _cursorBlinkTimer?.cancel();
    _cursorBlinkTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      setState(() {
        _showCursor = !_showCursor;
      });
    });
  }

  // キー・マウス操作があったときにカーソルを点灯状態にする
  void _resetCursorBlink() {
    _cursorBlinkTimer?.cancel();
    setState(() {
      _showCursor = true;
    });
    _startCursorTimer();
  }

  // --- 履歴保存メソッド (変更直前に呼ぶ) ---
  void _saveHistory() {
    // 現在の状態をディープコピーして保存
    // List<String>のコピーを作成することが重要
    final entry = HistoryEntry(List.from(_lines), _cursorRow, _cursorCol);

    _undoStack.add(entry);

    // スタック数制限（任意：例 100回）
    if (_undoStack.length > 100) {
      _undoStack.removeAt(0);
    }

    // 新しい操作をしたらRedoスタックはクリア
    _redoStack.clear();
  }

  // --- UNDO (Ctrl+Z) ---
  void _undo() {
    if (_undoStack.isEmpty) return;

    // 現在の状態をRedoスタックへ退避
    _redoStack.add(HistoryEntry(List.from(_lines), _cursorRow, _cursorCol));

    // Undoスタックから復元
    final entry = _undoStack.removeLast();
    setState(() {
      _lines = List.from(entry.lines); // リストを再生成
      _cursorRow = entry.cursorRow;
      _cursorCol = entry.cursorCol;
      // VisualXなども更新が必要ならここで
      if (_cursorRow < _lines.length) {
        String line = _lines[_cursorRow];
        if (_cursorCol > line.length) _cursorCol = line.length;
        _preferredVisualX = TextUtils.calcTextWidth(
          line.substring(0, _cursorCol),
        );
      }
    });
  }

  // --- REDO (Ctrl+Y) ---
  void _redo() {
    if (_redoStack.isEmpty) return;

    // 現在の状態をUndoスタックへ退避
    _undoStack.add(HistoryEntry(List.from(_lines), _cursorRow, _cursorCol));

    // Redoスタックから復元
    final entry = _redoStack.removeLast();
    setState(() {
      _lines = List.from(entry.lines);
      _cursorRow = entry.cursorRow;
      _cursorCol = entry.cursorCol;
      // VisualX更新
      if (_cursorRow < _lines.length) {
        String line = _lines[_cursorRow];
        if (_cursorCol > line.length) _cursorCol = line.length;
        _preferredVisualX = TextUtils.calcTextWidth(
          line.substring(0, _cursorCol),
        );
      }
    });
  }

  // キー処理
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

    // ctrl/cmd キーの処理
    if (isControl) {
      // Copy (Ctrl + C)
      if (physicalKey == PhysicalKeyboardKey.keyC) {
        // 選択範囲があればコピー（矩形選択されていれば矩形コピーになるロジックは既存のまま）
        _copySelection();
        return KeyEventResult.handled;
      }

      // UNDO (Ctrl + Z)
      if (physicalKey == PhysicalKeyboardKey.keyZ) {
        _undo();
        return KeyEventResult.handled;
      }

      // REDO (Ctrl + Y)
      if (physicalKey == PhysicalKeyboardKey.keyY) {
        _redo();
        return KeyEventResult.handled;
      }

      // 貼り付け(Ctrl + ? + V)
      if (physicalKey == PhysicalKeyboardKey.keyV) {
        if (isAlt) {
          // Ctrl + Alt + V 矩形貼り付け
          if (_selectionOriginRow != null) {
            _saveHistory();
            _deleteSelection();
          }
          _pasteRectangular();
        } else {
          // Ctrl + V 通常貼り付け
          if (_selectionOriginRow != null) {
            _saveHistory();
            _deleteSelection();
          }
          _pasteNormal();
        }
        return KeyEventResult.handled;
      }
    }

    //
    if (isShift) {
      if (_selectionOriginRow == null) {
        setState(() {
          _selectionOriginRow = _cursorRow;
          _selectionOriginCol = _cursorCol;
          _isRectangularSelection = isAlt;
        });
      } else {
        // 選択中もAltの状態を反映させる（動的な切り替え）
        if (_isRectangularSelection != isAlt) {
          setState(() {
            _isRectangularSelection = isAlt;
          });
        }
      }
    } else {
      // Shiftが押されていなければ選択解除 (矢印キー以外で解除したい場合もあるので
      // ここでリセットするかは要件次第だが、一旦移動系はリセット前提)
      // ただし、文字入力時などは別途考える必要あり。今回は矢印移動で解説。
    }

    int currentLineLength = 0;
    if (_cursorRow < _lines.length) {
      currentLineLength = _lines[_cursorRow].length;
    }
    switch (physicalKey) {
      case PhysicalKeyboardKey.enter:
        _saveHistory(); // UNDO用 状態保存
        _deleteSelection(); // 選択範囲があれば削除
        final currentLine = _lines[_cursorRow];
        final part1 = currentLine.substring(0, _cursorCol);
        final part2 = currentLine.substring(_cursorCol);

        _lines[_cursorRow] = part1;
        _lines.insert(_cursorRow + 1, part2);

        _cursorRow++;
        _cursorCol = 0;
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.backspace:
        _saveHistory(); // UNDO用 状態保存
        if (_selectionOriginRow != null) {
          _deleteSelection(); // 選択範囲削除のみで終了
          return KeyEventResult.handled;
        }

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
        _saveHistory(); // UNDO用 状態保存
        if (_selectionOriginRow != null) {
          _deleteSelection(); // 選択範囲削除のみで終了
          return KeyEventResult.handled;
        }

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
        _handleSelectionOnMove(isShift, isAlt); // 選択状態更新

        // カーソルの移動
        // Altの有無に関わらず、行頭なら前の行に戻る(行跨ぎ)
        if (_cursorCol > 0) {
          _cursorCol--;
        } else if (_cursorRow > 0) {
          _cursorRow--;
          _cursorCol = _lines[_cursorRow].length;
        }

        // 見た目のカーソル位置の更新
        String currentLine = _lines[_cursorRow];

        // 虚空(Alt)に対応するため、テキスト取得範囲を調整
        String textUpToCursor;
        if (_cursorCol <= currentLine.length) {
          textUpToCursor = currentLine.substring(0, _cursorCol);
        } else {
          // 虚空部分はスペースとみなして計算
          textUpToCursor =
              currentLine + (" " * (_cursorCol - currentLine.length));
        }

        _preferredVisualX = TextUtils.calcTextWidth(textUpToCursor);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });

        return KeyEventResult.handled;

      case PhysicalKeyboardKey.arrowRight:
        // 選択状態更新
        _handleSelectionOnMove(isShift, isAlt);

        String currentLine = _lines[_cursorRow];

        // カーソルの移動
        if (isAlt) {
          // Alt 押下 折り返さず無限に右へ
          _cursorCol++;
        } else {
          // Alt なし 行末で次へ折り返し
          if (_cursorCol < currentLine.length) {
            _cursorCol++;
          } else if (_cursorRow < _lines.length - 1) {
            _cursorRow++;
            _cursorCol = 0;
          }
        }

        // 見た目のカーソル位置の更新
        if (_cursorRow < _lines.length) {
          String line = _lines[_cursorRow];
          String textUpToCursor;
          if (_cursorCol <= line.length) {
            textUpToCursor = line.substring(0, _cursorCol);
          } else {
            // 虚空部分はスペースとみなして計算
            textUpToCursor = line + (" " * (_cursorCol - line.length));
          }
          _preferredVisualX = TextUtils.calcTextWidth(textUpToCursor);
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.arrowUp:
        // 選択状態更新
        _handleSelectionOnMove(isShift, isAlt);

        // 行の移動
        if (_cursorRow > 0) {
          _cursorRow--;
        }

        // 列の計算
        if (_cursorRow < _lines.length) {
          String line = _lines[_cursorRow];
          int lineWidth = TextUtils.calcTextWidth(line);

          if (isAlt && _preferredVisualX > lineWidth) {
            int gap = _preferredVisualX - lineWidth;
            _cursorCol = line.length + gap;
          } else {
            _cursorCol = TextUtils.getColFromVisualX(line, _preferredVisualX);
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });

        return KeyEventResult.handled;

      case PhysicalKeyboardKey.arrowDown:
        // 選択状態更新
        _handleSelectionOnMove(isShift, isAlt);

        // 行の移動
        // Atlが押されているときは、制限無く移動する。
        if (_cursorRow < _lines.length - 1 || isAlt) {
          _cursorRow++;
        }

        // 列の計算  upと同様
        if (_cursorRow < _lines.length) {
          String line = _lines[_cursorRow];
          int lineWidth = TextUtils.calcTextWidth(line);

          if (isAlt && _preferredVisualX > lineWidth) {
            int gap = _preferredVisualX - lineWidth;
            _cursorCol = line.length + gap;
          } else {
            _cursorCol = TextUtils.getColFromVisualX(line, _preferredVisualX);
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });

        return KeyEventResult.handled;

      default:
        if (character != null && character.isNotEmpty) {
          _saveHistory(); // UNDO用 状態保存
          // 矩形選択時は専用の置換処理を行う
          if (_isRectangularSelection && _selectionOriginRow != null) {
            _replaceRectangularSelection(character);
          } else {
            _deleteSelection(); // 選択範囲があれば削除
            _fillVirtualSpaceIfNeeded();
            _insertText(character);
          }
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

  // 選択範囲を削除する (通常・矩形対応)
  void _deleteSelection() {
    if (_selectionOriginRow == null || _selectionOriginCol == null) return;

    if (_isRectangularSelection) {
      // --- 矩形選択削除 ---
      int startRow = min(_selectionOriginRow!, _cursorRow);
      int endRow = max(_selectionOriginRow!, _cursorRow);

      // VisualX範囲の特定 (copySelectionと同じロジック)
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
      int originVisualX = TextUtils.calcTextWidth(originText);

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
      int cursorVisualX = TextUtils.calcTextWidth(cursorText);

      int minVisualX = min(originVisualX, cursorVisualX);
      int maxVisualX = max(originVisualX, cursorVisualX);

      for (int i = startRow; i <= endRow; i++) {
        if (i >= _lines.length) continue;
        String line = _lines[i];

        int startCol = TextUtils.getColFromVisualX(line, minVisualX);
        int endCol = TextUtils.getColFromVisualX(line, maxVisualX);

        if (startCol > endCol) {
          int t = startCol;
          startCol = endCol;
          endCol = t;
        }
        if (startCol > line.length) startCol = line.length;
        if (endCol > line.length) endCol = line.length;

        String part1 = line.substring(0, startCol);
        String part2 = line.substring(endCol);
        _lines[i] = part1 + part2;
      }
      // カーソルを矩形左上に移動
      _cursorRow = startRow;
      if (_cursorRow < _lines.length) {
        _cursorCol = TextUtils.getColFromVisualX(
          _lines[_cursorRow],
          minVisualX,
        );
        if (_cursorCol > _lines[_cursorRow].length)
          _cursorCol = _lines[_cursorRow].length;
      }
    } else {
      // --- 通常選択削除 ---
      int startRow = _selectionOriginRow!;
      int startCol = _selectionOriginCol!;
      int endRow = _cursorRow;
      int endCol = _cursorCol;

      if (startRow > endRow || (startRow == endRow && startCol > endCol)) {
        int t = startRow;
        startRow = endRow;
        endRow = t;
        t = startCol;
        startCol = endCol;
        endCol = t;
      }

      String startLine = (startRow < _lines.length) ? _lines[startRow] : "";
      String prefix = (startCol < startLine.length)
          ? startLine.substring(0, startCol)
          : startLine;

      String endLine = (endRow < _lines.length) ? _lines[endRow] : "";
      String suffix = (endCol < endLine.length)
          ? endLine.substring(endCol)
          : "";

      _lines[startRow] = prefix + suffix;

      if (endRow > startRow) {
        _lines.removeRange(startRow + 1, endRow + 1);
      }

      _cursorRow = startRow;
      _cursorCol = startCol;
    }
    _selectionOriginRow = null;
    _selectionOriginCol = null;
  }

  // 矩形選択範囲を指定文字で置換する
  void _replaceRectangularSelection(String text) {
    if (_selectionOriginRow == null || _selectionOriginCol == null) return;

    int startRow = min(_selectionOriginRow!, _cursorRow);
    int endRow = max(_selectionOriginRow!, _cursorRow);

    // VisualX範囲の特定
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
    int originVisualX = TextUtils.calcTextWidth(originText);

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
    int cursorVisualX = TextUtils.calcTextWidth(cursorText);

    int minVisualX = min(originVisualX, cursorVisualX);
    int maxVisualX = max(originVisualX, cursorVisualX);

    // カーソル位置更新用
    int newCursorRow = startRow;
    int newCursorCol = 0;

    for (int i = startRow; i <= endRow; i++) {
      if (i >= _lines.length) continue;
      String line = _lines[i];

      int startCol = TextUtils.getColFromVisualX(line, minVisualX);
      int endCol = TextUtils.getColFromVisualX(line, maxVisualX);

      if (startCol > endCol) {
        int t = startCol;
        startCol = endCol;
        endCol = t;
      }
      if (startCol > line.length) startCol = line.length;
      if (endCol > line.length) endCol = line.length;

      String part1 = line.substring(0, startCol);
      String part2 = line.substring(endCol);
      _lines[i] = part1 + text + part2;

      // カーソルは開始行の、挿入した文字の後ろに置く
      if (i == startRow) {
        newCursorCol = part1.length + text.length;
      }
    }

    _cursorRow = newCursorRow;
    _cursorCol = newCursorCol;

    // 選択解除
    _selectionOriginRow = null;
    _selectionOriginCol = null;

    // VisualX更新
    if (_cursorRow < _lines.length) {
      String line = _lines[_cursorRow];
      if (_cursorCol > line.length) _cursorCol = line.length;
      _preferredVisualX = TextUtils.calcTextWidth(
        line.substring(0, _cursorCol),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateImeWindowPosition();
    });
  }

  // 選択範囲をコピーする。
  void _copySelection() async {
    // 選択されていない場合何もしない。
    if (_selectionOriginRow == null || _selectionOriginCol == null) return;

    StringBuffer buffer = StringBuffer();

    if (_isRectangularSelection) {
      // --- 矩形選択コピー ---
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

      for (int i = startRow; i <= endRow; i++) {
        String line = "";
        if (i < _lines.length) {
          line = _lines[i];
        }
        // VisualX から 文字列のインデックス(col) に変換
        int startCol = TextUtils.getColFromVisualX(line, minVisualX);
        int endCol = TextUtils.getColFromVisualX(line, maxVisualX);

        if (startCol > endCol) {
          int temp = startCol;
          startCol = endCol;
          endCol = temp;
        }

        // 文字列切り出し
        String extracted = "";
        if (startCol < line.length) {
          int safeEnd = min(endCol, line.length);
          extracted = line.substring(startCol, safeEnd);
        }
        buffer.writeln(extracted);
      }
    } else {
      // --- 通常選択コピー (ストリーム) ---
      int startRow = _selectionOriginRow!;
      int startCol = _selectionOriginCol!;
      int endRow = _cursorRow;
      int endCol = _cursorCol;

      // 反転対応
      if (startRow > endRow || (startRow == endRow && startCol > endCol)) {
        int t = startRow;
        startRow = endRow;
        endRow = t;
        t = startCol;
        startCol = endCol;
        endCol = t;
      }

      for (int i = startRow; i <= endRow; i++) {
        if (i >= _lines.length) break;
        String line = _lines[i];

        int s = (i == startRow) ? startCol : 0;
        int e = (i == endRow) ? endCol : line.length;

        if (s > line.length) s = line.length;
        if (e > line.length) e = line.length;
        if (s < 0) s = 0;
        if (e < 0) e = 0;

        buffer.write(line.substring(s, e));

        // 最終行以外なら改行を入れる
        if (i < endRow) {
          buffer.write('\n');
        }
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));

    print("Copied to clipboard:\n${buffer.toString()}");
  }

  // 矩形貼り付け (Ctrl + Alt + V)
  Future<void> _pasteRectangular() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null || data.text!.isEmpty) return;

    // 行ごとに分割 (改行コードの除去)
    final List<String> pasteLines = const LineSplitter().convert(data.text!);
    if (pasteLines.isEmpty) return;

    int startRow = _cursorRow;

    // 基準となるVisualXを計算
    // 現在行をcurrentLineに入れる。なければ空
    String currentLine = "";
    if (_cursorRow < _lines.length) {
      currentLine = _lines[_cursorRow];
    }

    // カーソル位置までのテキスト幅を計算
    // 行末より右(虚空)にいる場合も考慮してスペース埋め想定で計算
    String textBefore = ""; // カーソル位置までのテキスト
    if (_cursorCol <= currentLine.length) {
      textBefore = currentLine.substring(0, _cursorCol);
    } else {
      textBefore = currentLine + (' ' * (_cursorCol - currentLine.length));
    }
    int targetVisualX = TextUtils.calcTextWidth(textBefore);

    setState(() {
      // 貼り付けを1行ずつ処理
      for (int i = 0; i < pasteLines.length; i++) {
        int targetRow = startRow + i;
        String textToPaste = pasteLines[i].replaceAll(
          RegExp(r'[\r\n]'),
          '',
        ); // ゴミ除去
        int pasteWidth = TextUtils.calcTextWidth(textToPaste);

        // 行が足りない場合の処理
        if (targetRow >= _lines.length) {
          int needed = targetRow - _lines.length + 1;
          for (int k = 0; k < needed; k++) _lines.add(""); // 足りない部分に改行を入れる。
        }

        // 貼り付け前に、必ず targetVisualX までスペースで埋める
        // これを行わないと、短い行の「末尾」に張り付いてしまい、垂直にならない
        int currentLineWidth = TextUtils.calcTextWidth(_lines[targetRow]);
        if (currentLineWidth < targetVisualX) {
          // 足りない幅の分だけスペースを追加 (半角1文字=幅1前提)
          int spacesNeeded = targetVisualX - currentLineWidth;
          _lines[targetRow] += ' ' * spacesNeeded;
        }

        String line = _lines[targetRow]; // 挿入している行

        // ターゲット位置までスペースで埋める (虚空対策)
        int insertIndex = TextUtils.getColFromVisualX(line, targetVisualX);

        // 安全策: indexが行長を超えないようにガード
        if (insertIndex > line.length) insertIndex = line.length;

        // 分岐: 挿入と上書きをモードで振り分けて処理
        if (!_isOverwriteMode) {
          // --- 挿入モード (Insert) ---
          // 既存の文字を右へずらす
          String part1 = line.substring(0, insertIndex);
          String part2 = line.substring(insertIndex);
          _lines[targetRow] = part1 + textToPaste + part2;
        } else {
          // --- 上書きモード (Overwrite) ---
          // 貼り付ける幅(VisualWidth)の分だけ、既存文字を消す
          int endVisualX = targetVisualX + pasteWidth;
          int endIndex = TextUtils.getColFromVisualX(line, endVisualX);

          // 上書き範囲が行末を超えている場合ガード
          if (endIndex > line.length) endIndex = line.length;

          String part1 = line.substring(0, insertIndex);
          // part2は「上書きされて消える範囲」の後ろから開始
          String part2 = line.substring(endIndex);

          // ※上書きで微妙な隙間（全角半角のズレ）が発生する場合、
          // part2の手前にスペースパディングが必要なケースもありますが、
          // まずは単純置換で実装します。

          _lines[targetRow] = part1 + textToPaste + part2;
        }
      }
      // カーソル移動: 貼り付けたブロックの右下に移動
      _cursorRow = startRow + pasteLines.length - 1;

      // 最終行の貼り付け後の位置へ
      String lastPasted = pasteLines.last.replaceAll(RegExp(r'[\r\n]'), '');
      int lastWidth = TextUtils.calcTextWidth(lastPasted);
      _preferredVisualX = targetVisualX + lastWidth;

      // Col再計算
      if (_cursorRow < _lines.length) {
        _cursorCol = TextUtils.getColFromVisualX(
          _lines[_cursorRow],
          _preferredVisualX,
        );
      }

      // 選択解除
      _selectionOriginRow = null;
      _selectionOriginCol = null;
    });

    // IME窓 更新
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updateImeWindowPosition(),
    );
  }

  // 通常貼り付け (Ctrl + V)
  Future<void> _pasteNormal() async {
    // クリップボードからテキスト取得
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null) return;

    // 改行コード統一
    String text = data.text!.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    List<String> parts = text.split('\n');

    setState(() {
      // 1. カーソル位置まで埋める (虚空対策)
      if (_cursorRow >= _lines.length) {
        int needed = _cursorRow - _lines.length + 1;
        for (int k = 0; k < needed; k++) _lines.add("");
      }
      String line = _lines[_cursorRow];
      if (_cursorCol > line.length) {
        line += ' ' * (_cursorCol - line.length);
        _lines[_cursorRow] = line;
        _cursorCol = line.length;
      }

      String prefix = line.substring(0, _cursorCol);

      // モード分岐
      if (!_isOverwriteMode) {
        // --- [挿入モード] ---
        String suffix = line.substring(_cursorCol);

        if (parts.length == 1) {
          // 単一行貼り付け
          _lines[_cursorRow] = prefix + parts[0] + suffix;
          _cursorCol += parts[0].length;
          /*  _preferredVisualX = TextUtils.calcTextWidth(
            _lines[_cursorRow].substring(0, _cursorCol),
            );
        */
        } else {
          // 複数行貼り付け (行分割発生)
          _lines[_cursorRow] = prefix + parts.first;
          for (int i = 1; i < parts.length - 1; i++) {
            _lines.insert(_cursorRow + i, parts[i]);
          }
          _lines.insert(_cursorRow + parts.length - 1, parts.last + suffix);

          // カーソル更新
          _cursorRow += parts.length - 1;
          _cursorCol = parts.last.length; // suffixの前
        }
      } else {
        // --- [上書きモード] --- (修正箇所)
        // ★修正ポイント: 文字数ではなく「見た目の幅」で上書き範囲を決める

        // 1. 貼り付けるテキスト(1行目)の見た目の幅を計算
        String firstPartToPaste = parts.first;
        int pasteVisualWidth = TextUtils.calcTextWidth(firstPartToPaste);

        // 2. 現在のカーソル位置(VisualX)を取得
        int currentVisualX = TextUtils.calcTextWidth(prefix);

        // 3. 上書き終了位置(VisualX)を計算
        int targetEndVisualX = currentVisualX + pasteVisualWidth;

        // 4. そのVisualXに対応する既存行のインデックス(Col)を逆算
        //    これにより「全角(幅2)を貼れば、半角(幅1)が2文字消える」動作になる
        int overwriteEndCol = TextUtils.getColFromVisualX(
          line,
          targetEndVisualX,
        );

        // 5. 残すべき後ろの文字(suffix)を取得
        String suffix = "";
        if (overwriteEndCol < line.length) {
          suffix = line.substring(overwriteEndCol);
        }
        // ※ overwriteEndColが行末を超えている場合、suffixは空文字(全部上書き)

        if (parts.length == 1) {
          // [単一行] prefix + 貼り付け文字 + 残ったsuffix
          _lines[_cursorRow] = prefix + firstPartToPaste + suffix;
          _cursorCol += firstPartToPaste.length;
        } else {
          // [複数行]
          // 1行目: prefix + 貼り付け1行目 (suffixはここではつかない)
          _lines[_cursorRow] = prefix + firstPartToPaste;

          // 中間行: そのまま挿入
          for (int i = 1; i < parts.length - 1; i++) {
            _lines.insert(_cursorRow + i, parts[i]);
          }

          // ★修正ポイント: 最終行に、計算しておいた suffix を結合する
          // これにより「カーソル以降の文字が全て消える」バグが解消される
          _lines.insert(_cursorRow + parts.length - 1, parts.last + suffix);

          _cursorRow += parts.length - 1;
          _cursorCol = parts.last.length;
        } // if (parts.length)
      } // if (!_isOverwriteMode

      // VisualX更新
      if (_cursorRow < _lines.length) {
        String currentLine = _lines[_cursorRow];
        if (_cursorCol > currentLine.length) _cursorCol = currentLine.length;
        _preferredVisualX = TextUtils.calcTextWidth(
          currentLine.substring(0, _cursorCol),
        );
      }

      _selectionOriginRow = null;
      _selectionOriginCol = null;
    });

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updateImeWindowPosition(),
    );
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
                  // _handleKeyPressの描画はここて一手に引き受ける。
                  setState(() {});
                }
                return result;
              },
              child: SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
                child: GestureDetector(
                  // タップダウン； カーソル移動＆選択解除
                  onTapDown: (details) {
                    _resetCursorBlink();
                    _handleTap(details.localPosition);
                    setState(() {
                      _selectionOriginRow = null;
                      _selectionOriginCol = null;
                    });
                  },
                  //ドラッグ開始 (選択範囲の始点を記録)
                  onPanStart: (details) {
                    _isDragging = true;
                    _resetCursorBlink();
                    _handleTap(details.localPosition);

                    setState(() {
                      // ドラッグ開始点を記録
                      _selectionOriginRow = _cursorRow;
                      _selectionOriginCol = _cursorCol;
                      // Altキーが押されていれば矩形選択モード
                      _isRectangularSelection =
                          HardwareKeyboard.instance.isAltPressed;
                    });
                  },
                  // ドラッグ中(カーソル位置を更新=選択範囲の最終位置が変わる)
                  onPanUpdate: (details) {
                    _resetCursorBlink();
                    _handleTap(details.localPosition);
                    setState(() {});
                  },
                  onPanEnd: (details) {
                    _isDragging = false;
                  },
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
                        showCursor: _showCursor,
                        isRectangularSelection: _isRectangularSelection,
                      ),
                      size: Size.infinite,
                      child: Container(
                        // 画面全体のタッチ判定を有効にするため、透明または白の色を指定
                        color: Colors.transparent,
                      ),
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

// 操作履歴管理クラス
class HistoryEntry {
  final List<String> lines;
  final int cursorRow;
  final int cursorCol;

  HistoryEntry(this.lines, this.cursorRow, this.cursorCol);
}
