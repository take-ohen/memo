import 'dart:convert';

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
  //  bool _isInsertMode = true;
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

    // Insertキー(モード切替)
    //    if (physicalKey == PhysicalKeyboardKey.insert) {
    //    _isInsertMode = !_isInsertMode;
    //      return KeyEventResult.handled;
    //    }

    // Ctrl + C
    if (isControl && physicalKey == PhysicalKeyboardKey.keyC) {
      // 選択範囲があればコピー（矩形選択されていれば矩形コピーになるロジックは既存のまま）
      _copySelection();
      return KeyEventResult.handled;
    }

    // Ctrl + V + ...
    if (isControl && physicalKey == PhysicalKeyboardKey.keyV) {
      if (isAlt) {
        // Ctrl + Alt + V 矩形貼り付け
        _pasteRectangular();
      } else {
        // Ctrl + V 通常貼り付け
        _pasteNormal();
      }
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
