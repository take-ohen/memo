import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';

// 分割したファイルをインポート
import 'memo_painter.dart';
import 'text_utils.dart';
import 'history_manager.dart';
import 'editor_controller.dart'; // コントローラーをインポート
import 'package:free_memo_editor/file_io_helper.dart'; // 相対パスからpackageパスへ変更

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  // テスト時にカーソル点滅タイマーを無効化するためのフラグ
  @visibleForTesting
  static bool disableCursorBlink = false;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with TextInputClient {
  double _charWidth = 0.0;
  double _charHeight = 0.0;
  double _lineHeight = 0.0;

  // コントローラー (状態保持用)
  late EditorController _controller;

  bool _showGrid = false;
  TextInputConnection? _inputConnection;
  String _composingText = "";

  // カーソル点滅処理
  Timer? _cursorBlinkTimer;
  bool _showCursor = true; // カーソル表示フラグ

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
  int get debugCursorCol => _controller.cursorCol;

  @visibleForTesting
  int get debugCursorRow => _controller.cursorRow;

  @visibleForTesting
  List<String> get debugLines => _controller.lines;

  @override
  void initState() {
    super.initState();
    _controller = EditorController(); // コントローラー初期化
    // コントローラーの変更を検知して画面を更新する (Step 2以降でロジックを移動した際に必要)
    _controller.addListener(() => setState(() {}));

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
    _controller.dispose();
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

      _controller.cursorRow = max(0, clickedRow);

      String currentLine = "";
      if (_controller.cursorRow < _controller.lines.length) {
        currentLine = _controller.lines[_controller.cursorRow];
      }

      // ★共通関数使用
      int lineVisualWidth = TextUtils.calcTextWidth(currentLine);

      if (clickedVisualX <= lineVisualWidth) {
        _controller.cursorCol = TextUtils.getColFromVisualX(
          currentLine,
          clickedVisualX,
        );
      } else {
        int gap = clickedVisualX - lineVisualWidth;
        _controller.cursorCol = currentLine.length + gap;
      }

      _controller.preferredVisualX = clickedVisualX;

      _focusNode.requestFocus();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateImeWindowPosition();
      });
    });
  }

  // ヘルパー関数 カーソル移動処理の前後に呼ぶ
  void _handleSelectionOnMove(bool isShift, bool isAlt) {
    if (isShift) {
      _controller.selectionOriginRow ??= _controller.cursorRow;
      _controller.selectionOriginCol ??= _controller.cursorCol;
      _controller.isRectangularSelection = isAlt; // Altキーの状態に合わせてモード切替
    } else {
      _controller.selectionOriginRow = null;
      _controller.selectionOriginCol = null;
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
    if (EditorPage.disableCursorBlink) return; // テスト時はタイマーを起動しない

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
    _controller.saveHistory();
  }

  // --- UNDO (Ctrl+Z) ---
  void _undo() {
    final entry = _controller.historyManager.undo(
      _controller.lines,
      _controller.cursorRow,
      _controller.cursorCol,
    );
    if (entry != null) {
      _applyHistoryEntry(entry);
    }
  }

  // --- REDO (Ctrl+Y) ---
  void _redo() {
    final entry = _controller.historyManager.redo(
      _controller.lines,
      _controller.cursorRow,
      _controller.cursorCol,
    );
    if (entry != null) {
      _applyHistoryEntry(entry);
    }
  }

  // 履歴エントリを現在の状態に適用するヘルパー
  void _applyHistoryEntry(HistoryEntry entry) {
    setState(() {
      _controller.lines = List.from(entry.lines); // リストを再生成
      _controller.cursorRow = entry.cursorRow;
      _controller.cursorCol = entry.cursorCol;

      // 選択状態は解除
      _controller.selectionOriginRow = null;
      _controller.selectionOriginCol = null;

      // VisualX更新
      if (_controller.cursorRow < _controller.lines.length) {
        String line = _controller.lines[_controller.cursorRow];
        if (_controller.cursorCol > line.length)
          _controller.cursorCol = line.length;
        _controller.preferredVisualX = TextUtils.calcTextWidth(
          line.substring(0, _controller.cursorCol),
        );
      }
    });
  }

  // キー処理
  KeyEventResult _handleKeyPress(KeyEvent event) {
    // IME入力中（未確定文字がある）場合は、エディタとしてのキー処理（カーソル移動や選択など）をスキップし、
    // IMEに処理を任せる。これにより、変換中のShiftキーなどで意図しない範囲選択が発生するのを防ぐ。
    if (_composingText.isNotEmpty) {
      return KeyEventResult.ignored;
    }

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
          if (_controller.selectionOriginRow != null) {
            _controller.saveHistory();
            _controller.deleteSelection();
          }
          _pasteRectangular();
        } else {
          // Ctrl + V 通常貼り付け
          if (_controller.selectionOriginRow != null) {
            _controller.saveHistory();
            _controller.deleteSelection();
          }
          _pasteNormal();
        }
        return KeyEventResult.handled;
      }

      // Save (Ctrl + S) / Save As (Ctrl + Shift + S)
      if (physicalKey == PhysicalKeyboardKey.keyS) {
        if (isShift) {
          _saveAsFile();
        } else {
          _saveFile();
        }
        return KeyEventResult.handled;
      }

      // Select All (Ctrl + A)
      if (physicalKey == PhysicalKeyboardKey.keyA) {
        _selectAll();
        return KeyEventResult.handled;
      }
    }

    //    int currentLineLength = 0;
    if (_controller.cursorRow < _controller.lines.length) {
      //      currentLineLength = _controller.lines[_controller.cursorRow].length;
    }
    switch (physicalKey) {
      case PhysicalKeyboardKey.enter:
        _controller.saveHistory(); // UNDO用 状態保存
        _controller.deleteSelection(); // 選択範囲があれば削除
        final currentLine = _controller.lines[_controller.cursorRow];
        final part1 = currentLine.substring(0, _controller.cursorCol);
        final part2 = currentLine.substring(_controller.cursorCol);

        _controller.lines[_controller.cursorRow] = part1;
        _controller.lines.insert(_controller.cursorRow + 1, part2);

        _controller.cursorRow++;
        _controller.cursorCol = 0;
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.backspace:
        _controller.saveHistory(); // UNDO用 状態保存
        if (_controller.selectionOriginRow != null) {
          _controller.deleteSelection(); // 選択範囲削除のみで終了
          return KeyEventResult.handled;
        }

        if (_controller.cursorCol > 0) {
          final currentLine = _controller.lines[_controller.cursorRow];
          final part1 = currentLine.substring(0, _controller.cursorCol - 1);
          final part2 = currentLine.substring(_controller.cursorCol);
          _controller.lines[_controller.cursorRow] = part1 + part2;
          _controller.cursorCol--;
        } else if (_controller.cursorRow > 0) {
          final lineToAppend = _controller.lines[_controller.cursorRow];
          final prevLineLength =
              _controller.lines[_controller.cursorRow - 1].length;
          _controller.lines[_controller.cursorRow - 1] += lineToAppend;
          _controller.lines.removeAt(_controller.cursorRow);
          _controller.cursorRow--;
          _controller.cursorCol = prevLineLength;
        } else {
          return KeyEventResult.handled;
        }
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.delete:
        _controller.saveHistory(); // UNDO用 状態保存
        if (_controller.selectionOriginRow != null) {
          _controller.deleteSelection(); // 選択範囲削除のみで終了
          return KeyEventResult.handled;
        }

        if (_controller.cursorRow >= _controller.lines.length)
          return KeyEventResult.handled;

        final currentLine = _controller.lines[_controller.cursorRow];

        if (_controller.cursorCol < currentLine.length) {
          final part1 = currentLine.substring(0, _controller.cursorCol);
          final part2 = (_controller.cursorCol + 1 < currentLine.length)
              ? currentLine.substring(_controller.cursorCol + 1)
              : '';
          _controller.lines[_controller.cursorRow] = part1 + part2;
        } else if (_controller.cursorCol == currentLine.length) {
          if (_controller.cursorRow < _controller.lines.length - 1) {
            final nextLine = _controller.lines[_controller.cursorRow + 1];
            _controller.lines[_controller.cursorRow] += nextLine;
            _controller.lines.removeAt(_controller.cursorRow + 1);
          }
        }
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.insert:
        setState(() {
          _controller.isOverwriteMode = !_controller.isOverwriteMode;
        });
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.arrowLeft:
        _handleSelectionOnMove(isShift, isAlt); // 選択状態更新

        // カーソルの移動
        // Altの有無に関わらず、行頭なら前の行に戻る(行跨ぎ)
        if (_controller.cursorCol > 0) {
          _controller.cursorCol--;
        } else if (_controller.cursorRow > 0) {
          _controller.cursorRow--;
          _controller.cursorCol =
              _controller.lines[_controller.cursorRow].length;
        }

        // 見た目のカーソル位置の更新
        String currentLine = _controller.lines[_controller.cursorRow];

        // 虚空(Alt)に対応するため、テキスト取得範囲を調整
        String textUpToCursor;
        if (_controller.cursorCol <= currentLine.length) {
          textUpToCursor = currentLine.substring(0, _controller.cursorCol);
        } else {
          // 虚空部分はスペースとみなして計算
          textUpToCursor =
              currentLine +
              (" " * (_controller.cursorCol - currentLine.length));
        }

        _controller.preferredVisualX = TextUtils.calcTextWidth(textUpToCursor);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });

        return KeyEventResult.handled;

      case PhysicalKeyboardKey.arrowRight:
        // 選択状態更新
        _handleSelectionOnMove(isShift, isAlt);

        String currentLine = _controller.lines[_controller.cursorRow];

        // カーソルの移動
        if (isAlt) {
          // Alt 押下 折り返さず無限に右へ
          _controller.cursorCol++;
        } else {
          // Alt なし 行末で次へ折り返し
          if (_controller.cursorCol < currentLine.length) {
            _controller.cursorCol++;
          } else if (_controller.cursorRow < _controller.lines.length - 1) {
            _controller.cursorRow++;
            _controller.cursorCol = 0;
          }
        }

        // 見た目のカーソル位置の更新
        if (_controller.cursorRow < _controller.lines.length) {
          String line = _controller.lines[_controller.cursorRow];
          String textUpToCursor;
          if (_controller.cursorCol <= line.length) {
            textUpToCursor = line.substring(0, _controller.cursorCol);
          } else {
            // 虚空部分はスペースとみなして計算
            textUpToCursor =
                line + (" " * (_controller.cursorCol - line.length));
          }
          _controller.preferredVisualX = TextUtils.calcTextWidth(
            textUpToCursor,
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.arrowUp:
        // 選択状態更新
        _handleSelectionOnMove(isShift, isAlt);

        // 行の移動
        if (_controller.cursorRow > 0) {
          _controller.cursorRow--;
        }

        // 列の計算
        if (_controller.cursorRow < _controller.lines.length) {
          String line = _controller.lines[_controller.cursorRow];
          int lineWidth = TextUtils.calcTextWidth(line);

          if (isAlt && _controller.preferredVisualX > lineWidth) {
            int gap = _controller.preferredVisualX - lineWidth;
            _controller.cursorCol = line.length + gap;
          } else {
            _controller.cursorCol = TextUtils.getColFromVisualX(
              line,
              _controller.preferredVisualX,
            );
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
        if (_controller.cursorRow < _controller.lines.length - 1 || isAlt) {
          _controller.cursorRow++;
        }

        // 列の計算  upと同様
        if (_controller.cursorRow < _controller.lines.length) {
          String line = _controller.lines[_controller.cursorRow];
          int lineWidth = TextUtils.calcTextWidth(line);

          if (isAlt && _controller.preferredVisualX > lineWidth) {
            int gap = _controller.preferredVisualX - lineWidth;
            _controller.cursorCol = line.length + gap;
          } else {
            _controller.cursorCol = TextUtils.getColFromVisualX(
              line,
              _controller.preferredVisualX,
            );
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });

        return KeyEventResult.handled;

      default:
        if (character != null && character.isNotEmpty) {
          _controller.saveHistory(); // UNDO用 状態保存
          // 矩形選択時は専用の置換処理を行う
          if (_controller.isRectangularSelection &&
              _controller.selectionOriginRow != null) {
            _controller.replaceRectangularSelection(character);
          } else {
            _controller.deleteSelection(); // 選択範囲があれば削除
            _controller.ensureVirtualSpace(
              _controller.cursorRow,
              _controller.cursorCol,
            );
            _controller.insertText(character);
          }
          // IME窓の更新はControllerではできないのでここで行う
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateImeWindowPosition();
          });
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
    }
  }

  // 選択範囲をコピーする。
  void _copySelection() async {
    // 選択されていない場合何もしない。
    if (_controller.selectionOriginRow == null ||
        _controller.selectionOriginCol == null)
      return;

    StringBuffer buffer = StringBuffer();

    if (_controller.isRectangularSelection) {
      // --- 矩形選択コピー ---
      // 範囲の特定（行）
      int startRow = min(
        _controller.selectionOriginRow!,
        _controller.cursorRow,
      );
      int endRow = max(_controller.selectionOriginRow!, _controller.cursorRow);

      // 範囲の特定( 見た目のX座標: VisualX )
      // Painterと同じロジックで「矩形の左端」と「矩形の右端」を算出する

      // 開始地点のVisualX
      String originLine = "";
      if (_controller.selectionOriginRow! < _controller.lines.length) {
        originLine = _controller.lines[_controller.selectionOriginRow!];
      }
      String originText = "";
      if (_controller.selectionOriginCol! <= originLine.length) {
        originText = originLine.substring(0, _controller.selectionOriginCol!);
      } else {
        originText =
            originLine +
            (' ' * (_controller.selectionOriginCol! - originLine.length));
      }
      // 共通関数
      int originVisualX = TextUtils.calcTextWidth(originText);

      // カーソル地点のVisualX
      String cursorLine = "";
      if (_controller.cursorRow < _controller.lines.length) {
        cursorLine = _controller.lines[_controller.cursorRow];
      }
      String cursorText = "";
      if (_controller.cursorCol <= cursorLine.length) {
        cursorText = cursorLine.substring(0, _controller.cursorCol);
      } else {
        cursorText =
            cursorLine + (' ' * (_controller.cursorCol - cursorLine.length));
      }
      // 共通関数
      int cursorVisualX = TextUtils.calcTextWidth(cursorText);

      int minVisualX = min(originVisualX, cursorVisualX);
      int maxVisualX = max(originVisualX, cursorVisualX);

      for (int i = startRow; i <= endRow; i++) {
        String line = "";
        if (i < _controller.lines.length) {
          line = _controller.lines[i];
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
      int startRow = _controller.selectionOriginRow!;
      int startCol = _controller.selectionOriginCol!;
      int endRow = _controller.cursorRow;
      int endCol = _controller.cursorCol;

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
        if (i >= _controller.lines.length) break;
        String line = _controller.lines[i];

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

    int startRow = _controller.cursorRow;

    // 基準となるVisualXを計算
    // 現在行をcurrentLineに入れる。なければ空
    String currentLine = "";
    if (_controller.cursorRow < _controller.lines.length) {
      currentLine = _controller.lines[_controller.cursorRow];
    }

    // カーソル位置までのテキスト幅を計算
    // 行末より右(虚空)にいる場合も考慮してスペース埋め想定で計算
    String textBefore = ""; // カーソル位置までのテキスト
    if (_controller.cursorCol <= currentLine.length) {
      textBefore = currentLine.substring(0, _controller.cursorCol);
    } else {
      textBefore =
          currentLine + (' ' * (_controller.cursorCol - currentLine.length));
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

        // 行拡張とターゲット位置までのスペース埋めを共通関数で行う
        // ただし、targetVisualX は見た目の幅なので、文字数(col)に変換する必要があるが、
        // ここでは簡易的に「足りない幅分スペースを足す」という既存ロジックを維持しつつ、
        // 行拡張部分だけ共通化、あるいは _ensureVirtualSpace を活用する形に修正。

        if (targetRow >= _controller.lines.length) {
          _controller.ensureVirtualSpace(targetRow, 0); // 行だけ作る
        }

        String line = _controller.lines[targetRow]; // 挿入している行

        // ターゲット位置までスペースで埋める (虚空対策)
        int insertIndex = TextUtils.getColFromVisualX(line, targetVisualX);

        // 挿入位置までスペースで埋める
        if (insertIndex > line.length) {
          _controller.ensureVirtualSpace(targetRow, insertIndex);
          line = _controller.lines[targetRow]; // 更新された行を再取得
        }

        // 分岐: 挿入と上書きをモードで振り分けて処理
        if (!_controller.isOverwriteMode) {
          // --- 挿入モード (Insert) ---
          // 既存の文字を右へずらす
          String part1 = line.substring(0, insertIndex);
          String part2 = line.substring(insertIndex);
          _controller.lines[targetRow] = part1 + textToPaste + part2;
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

          _controller.lines[targetRow] = part1 + textToPaste + part2;
        }
      }
      // カーソル移動: 貼り付けたブロックの右下に移動
      _controller.cursorRow = startRow + pasteLines.length - 1;

      // 最終行の貼り付け後の位置へ
      String lastPasted = pasteLines.last.replaceAll(RegExp(r'[\r\n]'), '');
      int lastWidth = TextUtils.calcTextWidth(lastPasted);
      _controller.preferredVisualX = targetVisualX + lastWidth;

      // Col再計算
      if (_controller.cursorRow < _controller.lines.length) {
        _controller.cursorCol = TextUtils.getColFromVisualX(
          _controller.lines[_controller.cursorRow],
          _controller.preferredVisualX,
        );
      }

      // 選択解除
      _controller.selectionOriginRow = null;
      _controller.selectionOriginCol = null;
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
      _controller.ensureVirtualSpace(
        _controller.cursorRow,
        _controller.cursorCol,
      );
      String line = _controller.lines[_controller.cursorRow];

      String prefix = line.substring(0, _controller.cursorCol);

      // モード分岐
      if (!_controller.isOverwriteMode) {
        // --- [挿入モード] ---
        String suffix = line.substring(_controller.cursorCol);

        if (parts.length == 1) {
          // 単一行貼り付け
          _controller.lines[_controller.cursorRow] = prefix + parts[0] + suffix;
          _controller.cursorCol += parts[0].length;
          /*  _preferredVisualX = TextUtils.calcTextWidth(
            _controller.lines[_controller.cursorRow].substring(0, _controller.cursorCol),
            );
        */
        } else {
          // 複数行貼り付け (行分割発生)
          _controller.lines[_controller.cursorRow] = prefix + parts.first;
          for (int i = 1; i < parts.length - 1; i++) {
            _controller.lines.insert(_controller.cursorRow + i, parts[i]);
          }
          _controller.lines.insert(
            _controller.cursorRow + parts.length - 1,
            parts.last + suffix,
          );

          // カーソル更新
          _controller.cursorRow += parts.length - 1;
          _controller.cursorCol = parts.last.length; // suffixの前
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
          _controller.lines[_controller.cursorRow] =
              prefix + firstPartToPaste + suffix;
          _controller.cursorCol += firstPartToPaste.length;
        } else {
          // [複数行]
          // 1行目: prefix + 貼り付け1行目 (suffixはここではつかない)
          _controller.lines[_controller.cursorRow] = prefix + firstPartToPaste;

          // 中間行: そのまま挿入
          for (int i = 1; i < parts.length - 1; i++) {
            _controller.lines.insert(_controller.cursorRow + i, parts[i]);
          }

          // ★修正ポイント: 最終行に、計算しておいた suffix を結合する
          // これにより「カーソル以降の文字が全て消える」バグが解消される
          _controller.lines.insert(
            _controller.cursorRow + parts.length - 1,
            parts.last + suffix,
          );

          _controller.cursorRow += parts.length - 1;
          _controller.cursorCol = parts.last.length;
        } // if (parts.length)
      } // if (!_isOverwriteMode

      // VisualX更新
      if (_controller.cursorRow < _controller.lines.length) {
        String currentLine = _controller.lines[_controller.cursorRow];
        if (_controller.cursorCol > currentLine.length)
          _controller.cursorCol = currentLine.length;
        _controller.preferredVisualX = TextUtils.calcTextWidth(
          currentLine.substring(0, _controller.cursorCol),
        );
      }

      _controller.selectionOriginRow = null;
      _controller.selectionOriginCol = null;
    });

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updateImeWindowPosition(),
    );
  }

  // 全選択 (Ctrl + A)
  void _selectAll() {
    setState(() {
      _controller.selectionOriginRow = 0;
      _controller.selectionOriginCol = 0;
      _controller.cursorRow = _controller.lines.length - 1;
      _controller.cursorCol = _controller.lines.last.length;
      _controller.isRectangularSelection = false; // 全選択は通常選択モードで

      // VisualX更新
      String line = _controller.lines[_controller.cursorRow];
      _controller.preferredVisualX = TextUtils.calcTextWidth(line);
    });
  }

  // --- ファイル操作 ---

  // ファイルを開く
  Future<void> _openFile() async {
    try {
      // FileIOHelper経由でパスを取得
      String? path = await FileIOHelper.instance.pickFilePath();
      if (path != null) {
        String content = await FileIOHelper.instance.readFileAsString(path);

        // 履歴に現在の状態を保存（ロードを取り消せるようにする場合）
        _saveHistory();

        setState(() {
          _controller.currentFilePath = path;
          // 改行コードを統一して分割
          content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
          _controller.lines = content.split('\n');
          if (_controller.lines.isEmpty) {
            _controller.lines = [''];
          }

          // カーソルリセット
          _controller.cursorRow = 0;
          _controller.cursorCol = 0;
          _controller.preferredVisualX = 0;
          _controller.selectionOriginRow = null;
          _controller.selectionOriginCol = null;
        });
      }
    } catch (e) {
      debugPrint('Error opening file: $e');
    }
  }

  // 上書き保存 (Ctrl + S)
  Future<void> _saveFile() async {
    // パスがない場合は「名前を付けて保存」へ
    if (_controller.currentFilePath == null) {
      await _saveAsFile();
      return;
    }

    try {
      String content = _controller.lines.join('\n'); // 改行コードはLFで結合
      await FileIOHelper.instance.writeStringToFile(
        _controller.currentFilePath!,
        content,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存しました: ${_controller.currentFilePath}'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving file: $e');
    }
  }

  // 名前を付けて保存 (Ctrl + Shift + S)
  Future<void> _saveAsFile() async {
    try {
      // FileIOHelper経由でパスを取得
      String? outputFile = await FileIOHelper.instance.saveFilePath();

      if (outputFile != null) {
        setState(() {
          _controller.currentFilePath = outputFile;
        });
        String content = _controller.lines.join('\n'); // 改行コードはLFで結合
        await FileIOHelper.instance.writeStringToFile(outputFile, content);
      }
    } catch (e) {
      debugPrint('Error saving file: $e');
    }
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
    if (_controller.cursorRow < _controller.lines.length) {
      currentLine = _controller.lines[_controller.cursorRow];
    }

    String textBeforeCursor = "";
    if (_controller.cursorCol <= currentLine.length) {
      textBeforeCursor = currentLine.substring(0, _controller.cursorCol);
    } else {
      textBeforeCursor =
          currentLine + (' ' * (_controller.cursorCol - currentLine.length));
    }

    // ★共通関数使用
    int visualX = TextUtils.calcTextWidth(textBeforeCursor);
    final double localPixelX = visualX * safeCharWidth;
    final double localPixelY = _controller.cursorRow * safeLineHeight;

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
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _openFile,
            tooltip: '開く',
          ),
          IconButton(
            icon: const Icon(Icons.save), // 上書き保存
            onPressed: _saveFile,
            tooltip: '上書き保存 (Ctrl+S)',
          ),
          IconButton(
            icon: const Icon(Icons.save_as), // 名前を付けて保存
            onPressed: _saveAsFile,
            tooltip: '名前を付けて保存 (Ctrl+Shift+S)',
          ),
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
                      _controller.selectionOriginRow = null;
                      _controller.selectionOriginCol = null;
                    });
                  },
                  //ドラッグ開始 (選択範囲の始点を記録)
                  onPanStart: (details) {
                    //                    _isDragging = true;
                    _resetCursorBlink();
                    _handleTap(details.localPosition);

                    setState(() {
                      // ドラッグ開始点を記録
                      _controller.selectionOriginRow = _controller.cursorRow;
                      _controller.selectionOriginCol = _controller.cursorCol;
                      // Altキーが押されていれば矩形選択モード
                      _controller.isRectangularSelection =
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
                    //                    _isDragging = false;
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 2000,
                      minHeight: 2000,
                    ),
                    child: CustomPaint(
                      key: _painterKey,
                      painter: MemoPainter(
                        lines: _controller.lines,
                        charWidth: _charWidth,
                        charHeight: _charHeight,
                        showGrid: _showGrid,
                        isOverwriteMode: _controller.isOverwriteMode,
                        cursorRow: _controller.cursorRow,
                        cursorCol: _controller.cursorCol,
                        lineHeight: _lineHeight,
                        textStyle: _textStyle,
                        composingText: _composingText,
                        selectionOriginRow: _controller.selectionOriginRow,
                        selectionOriginCol: _controller.selectionOriginCol,
                        showCursor: _showCursor,
                        isRectangularSelection:
                            _controller.isRectangularSelection,
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
        _controller.insertText(value.text);
        _composingText = "";
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
