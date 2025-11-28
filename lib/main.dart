import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HardwareKeyboardのため
import 'dart:math';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Free-form Memo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const EditorPage(),
    );
  }
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with TextInputClient {
  double _charWidth = 0.0; // 1文字の幅
  double _charHeight = 0.0; // 1文字の高さ
  double _lineHeight = 0.0; // 1行の高さ
  int _cursorRow = 0; // 初期のカーソル位置
  int _cursorCol = 0; // 初期のカーソル位置
  List<String> _lines = ['']; // エディタのテキストエリア

  //  グリッド表示のON/OFFを管理する変数を追加
  bool _showGrid = false; // デフォルトはOFFにしておきます

  // 追加: IMEとの接続を管理する変数
  TextInputConnection? _inputConnection;

  // スクロールバーを表示されるためのコントローラーの明示
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  // フォーカスノードを追加
  final FocusNode _focusNode = FocusNode();

  static const _textStyle = TextStyle(
    fontFamily: 'BIZ UDゴシック',
    fontSize: 16.0,
    color: Colors.black,
  );

  @override
  void initState() {
    super.initState();
    _calculateGlyphMetrics();
    // フレーム描画後に実行する必要があるため、
    // 非同期で呼び出すでフォーカスを当てる。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });

    // ★★★ 調査用リスナーを追加 ★★★
    // スクロールが発生するたびに、どこから呼び出されたかを出力する
    //_verticalScrollController.addListener(() {
    //  print(
    //    '--- Vertical Scroll Detected! Offset: ${_verticalScrollController.offset} ---',
    //  );
    //  debugPrintStack();
    //});
  }

  @override
  void dispose() {
    _focusNode.dispose(); // focusノードの破棄
    _horizontalScrollController.dispose(); // ScrollConttrollerの破棄
    _verticalScrollController.dispose(); // ScrollConttrollerの破棄
    super.dispose();
  }

  void _calculateGlyphMetrics() {
    // Mの文字をサンプルにして幅と高さを算出

    final painter = TextPainter(
      text: const TextSpan(text: 'M', style: _textStyle),
      textDirection: TextDirection.ltr,
    );
    painter.layout(); // ここで計算が実行される。

    setState(() {
      _charWidth = painter.width;
      _charHeight = painter.height;
      _lineHeight = _charHeight * 1.2; // 行の高さは、1.2倍
    });
  }

  // マウスがクリックされたときの実装
  void _handleTap(TapDownDetails details) {
    // charWidthやcharHeightが未計算の場合は処理を中断
    if (_charWidth == 0 || _charHeight == 0) return;

    // グリッド座標への変換
    // タップ位置を文字幅・文字高さで割ることで、行と列のインデックスを算出

    setState(() {
      final Offset tapPosition = details.localPosition;
      int colIndex = (tapPosition.dx / _charWidth).round();
      int rowIndex = (tapPosition.dy / _lineHeight).floor();

      _cursorRow = max(0, rowIndex); // マイナスは防ぐ
      _cursorCol = max(0, colIndex); // マイナスは防ぐ

      // フォーカスを取得する（キーボード入力への準備）
      _focusNode.requestFocus();

      // IME接続を開始！
      _activateIme();
    });
  }

  // KeyboardListener の キーを押されたときの実装。
  KeyEventResult _handleKeyPress(KeyEvent event) {
    // KeyDownEvent 以外は標準の処理に任せる。
    // ただし、押しっぱなしにした場合は,KeyDownEventではなく、
    // KeyRepeatEventが返ってくるのでそちらも押しっぱなしする場合,
    // それも確認しないといけない。
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // キーが押された 瞬間(KeyDownEvent) の処理 のみを行う。

    // PhysicalKeyboardKey は Enter や Backspace などの特定キーを識別するために使用
    final PhysicalKeyboardKey physicalKey = event.physicalKey;
    // character は入力された文字そのもの（例: 'a', '1', 'あ'）
    final String? character = event.character;

    // Altキーが押されているかチェック
    bool isAlt = HardwareKeyboard.instance.isAltPressed;

    // 現在の行の長さを取得（行が存在しない場合は 0 とする）
    int currentLineLength = 0;
    if (_cursorRow < _lines.length) {
      currentLineLength = _lines[_cursorRow].length;
    }
    switch (physicalKey) {
      case PhysicalKeyboardKey.enter:
        // Shiftキーと同時押しされた場合は、デフォルト動作
        // （改行なしの決定など）を避けるため、
        // ここで特殊な操作（例：コードエディタでのインデント挿入など）を定義しない。

        // 現在の行を取得
        final currentLine = _lines[_cursorRow];

        // 現在のカーソル位置で文字列を分割
        final part1 = currentLine.substring(0, _cursorCol);
        final part2 = currentLine.substring(_cursorCol);

        // 既存の行を part1 で上書き
        _lines[_cursorRow] = part1;

        // 新しい行として part2 を挿入
        _lines.insert(_cursorRow + 1, part2);

        // カーソル位置を新しい行の先頭に移動
        _cursorRow++;
        _cursorCol = 0; // 新しい行の先頭（0列目）に移動

        return KeyEventResult.handled;
      case PhysicalKeyboardKey.backspace:
        if (_cursorCol > 0) {
          // パターン 1: カーソルが行の途中にある場合
          final currentLine = _lines[_cursorRow];

          // カーソル位置の直前の文字を削除
          final part1 = currentLine.substring(0, _cursorCol - 1);
          final part2 = currentLine.substring(_cursorCol);
          _lines[_cursorRow] = part1 + part2;

          // カーソルを一つ前に移動
          _cursorCol--;
        } else if (_cursorRow > 0) {
          // パターン 2: カーソルが行の先頭 (0列目) にあり、かつ1行目ではない場合

          // 現在の行の内容を保存
          final lineToAppend = _lines[_cursorRow];

          // カーソルを前の行の末尾に移動させる準備
          final prevLineLength = _lines[_cursorRow - 1].length;

          // 現在の行の内容を前の行の末尾に追加（結合）
          _lines[_cursorRow - 1] += lineToAppend;

          // 現在の行をリストから削除
          _lines.removeAt(_cursorRow);

          // カーソルを前の行に移動させ、位置を結合した場所の末尾に設定
          _cursorRow--;
          _cursorCol = prevLineLength;
        } else {
          // パターン 3: カーソルが1行目の先頭にある場合 (何もしない)
          return KeyEventResult.handled;
        }
        return KeyEventResult.handled;
      case PhysicalKeyboardKey.arrowLeft:
        // 左キー カーソルを左に移動( 最小 0 )
        _cursorCol = max(0, _cursorCol - 1);
        return KeyEventResult.handled;
      case PhysicalKeyboardKey.arrowRight:
        if (isAlt) {
          // [Alt] 虚空移動: 制限なしで右へ
          _cursorCol++;
        } else {
          // [通常] 行末で止まり、それ以上で次行へ
          if (_cursorCol < currentLineLength) {
            _cursorCol++;
          } else if (_cursorRow < _lines.length - 1) {
            // 次の行の先頭へ
            _cursorRow++;
            _cursorCol = 0;
          }
        }
        return KeyEventResult.handled;
      case PhysicalKeyboardKey.arrowUp:
        // 上キー
        final int newRow = max(0, _cursorRow - 1);
        _cursorRow = newRow;
        // 新しい行の長さに合わせてカーソル位置を調整（行末を超えないように）
        _cursorCol = min(_lines[newRow].length, _cursorCol);
        return KeyEventResult.handled;
      case PhysicalKeyboardKey.arrowDown:
        if (isAlt) {
          // [Alt] 虚空移動: 制限なしで下へ
          _cursorRow++;
        } else {
          // [通常] データがある行までしか移動できない
          if (_cursorRow < _lines.length - 1) {
            _cursorRow++;
            // 移動先の行の長さに合わせる（スナップ）
            int nextLineLen = _lines[_cursorRow].length;
            _cursorCol = min(_cursorCol, nextLineLen);
          }
        }
        return KeyEventResult.handled;
      default:
        if (character != null && character.isNotEmpty) {
          // 通常の文字挿

          // 文字入力モードの最初で「虚空」を「実データ」に変換する
          _fillVirtualSpaceIfNeeded();

          // 現在の行の文字列を取得
          final String currentLine = _lines[_cursorRow];

          // 文字列をカーソルの位置で分割し、間に新しい文字を挿入
          final String newLine =
              currentLine.substring(0, _cursorCol) +
              character +
              currentLine.substring(_cursorCol);

          _lines[_cursorRow] = newLine; // _lines の該当行を新しい文字列で更新
          _cursorCol++; // カーソル位置（col）を1つ右へ移動
          return KeyEventResult.handled;
        }
        // 関係ないキー（Shift単体など）は無視して、システムに任せる
        return KeyEventResult.ignored;
    }
  }

  // カーソル位置までデータを埋める
  void _fillVirtualSpaceIfNeeded() {
    //  縦の拡張: カーソル行まで空行を増やす
    while (_lines.length <= _cursorRow) {
      _lines.add("");
    }

    // 横の拡張: カーソル列までスペースで埋める
    if (_cursorCol > _lines[_cursorRow].length) {
      // padRight で足りない分を半角スペースで埋める
      _lines[_cursorRow] = _lines[_cursorRow].padRight(_cursorCol);
    }
  }

  // IMEに接続する関数
  void _activateIme() {
    if (_inputConnection == null || !_inputConnection!.attached) {
      // 構成設定（OSに「これはただのテキストだよ」と伝える）
      final config = TextInputConfiguration(
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        // Flutter 3.22以降は必須
        viewId: View.of(context).viewId,
      );

      // 接続開始！ (this は TextInputClient である自分自身)
      _inputConnection = TextInput.attach(this, config);

      // キーボードを表示（スマホの場合。デスクトップでも念のため呼ぶ）
      _inputConnection!.show();
      print("IME接続開始！");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Free-form Memo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // ★ 2. アプリバーに切り替えスイッチを追加
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
      body:
          // 水平方向でスクロールバーを表示する
          Scrollbar(
            controller: _verticalScrollController,
            thumbVisibility: true, // スクロールバーの表示を明示する。
            trackVisibility: true, // 常にスクロールバーを表示させる。
            child: Scrollbar(
              controller: _horizontalScrollController,
              thumbVisibility: true,
              trackVisibility: true,
              notificationPredicate: (notif) => notif.depth == 1, //念のため深さ１を指定
              // 垂直スクロールバーの表示
              child: SingleChildScrollView(
                controller: _verticalScrollController,
                scrollDirection: Axis.vertical,
                // 垂直のスクロールバーの表示
                // イベントを消費しないKeyboardListenerではなく Focusを使う。
                child: Focus(
                  focusNode: _focusNode,
                  // onKeyEventではなく onKey:を使う
                  onKeyEvent: (FocusNode node, KeyEvent event) {
                    // キー処理ロジックを実行し、結果を受け取る。
                    final result = _handleKeyPress(event);

                    // 処理済み (handled) の場合のみ setState を実行する。
                    if (result == KeyEventResult.handled) {
                      setState(() {
                        // _handleKeyPress で既に状態変数は更新済み。
                        // 何も書かなくて良い。
                      });
                    }
                    // 3. 結果を Flutter に返却し、予期せぬスクロールを防ぎます
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
                          painter: MemoPainter(
                            lines: _lines,
                            charWidth: _charWidth,
                            charHeight: _charHeight,
                            showGrid: _showGrid, // Grid ON/OFFの状態をPainterに渡す
                            cursorRow: _cursorRow, // カーソルの位置を渡す
                            cursorCol: _cursorCol,
                            lineHeight: _lineHeight,
                            textStyle: _textStyle,
                          ),
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
  // ------------------------------------------------------------------
  // TextInputClient の必須実装 ↓
  // ------------------------------------------------------------------

  // Q. IME「今のテキストの状態（どこにカーソルがあるか等）を教えて？」
  // A. とりあえず「空っぽです」と答えておく（後で実装）
  @override
  TextEditingValue get currentTextEditingValue {
    return TextEditingValue.empty;
  }

  // Q. IME「ユーザーが文字を入力したよ！このデータを受け取って！」
  // A. ここに日本語入力のデータが流れてきます。今はログに出すだけ。
  @override
  void updateEditingValue(TextEditingValue value) {
    print("IMEからの入力: text=${value.text}, composing=${value.composing}");

    // ★重要: ここで受け取ったデータを _lines に反映させる処理を後で書く
  }

  // Q. IME「エンターキー(決定/検索ボタンなど)が押されたよ」
  // A. 必要なら処理する
  @override
  void performAction(TextInputAction action) {
    print("IMEアクション: $action");
  }

  // その他、必須だが今回は使わないメソッド（空でOK）
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

  // 最新の FlutterのAutofill機能に対応するための必須ゲッター(追加)
  @override
  AutofillScope? get currentAutofillScope => null;

  // ------------------------------------------------------------------
  //  TextInputClient の必須実装 ↑
  // ------------------------------------------------------------------
}

class MemoPainter extends CustomPainter {
  final List<String> lines;
  final double charWidth;
  final double charHeight;
  final double lineHeight;
  final bool showGrid;
  final int cursorRow;
  final int cursorCol;
  final TextStyle textStyle; // TextPainter に渡すスタイル

  MemoPainter({
    required this.lines,
    required this.charWidth,
    required this.charHeight,
    required this.showGrid,
    required this.cursorRow,
    required this.cursorCol,
    required this.lineHeight,
    required this.textStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // カーソル描画のための設定
    final cursorPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.square;

    double verticalOffset = 0.0; // Y 座標初期値

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];

      final textSpan = TextSpan(text: line, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );

      // layoutの実行
      textPainter.layout(minWidth: 0, maxWidth: size.width);

      // テキストの描画
      // (0, verticalOffset)の位置から開始
      textPainter.paint(canvas, Offset(0, verticalOffset));

      verticalOffset += lineHeight;
    }

    // カーソルの描画
    //  charWidth * cursorCol でX座標を計算
    final double cursorX = cursorCol * charWidth;
    final double cursorY = cursorRow * lineHeight;

    // カーソル描画の開始点と終了点を計算
    final Offset startPoint = Offset(cursorX, cursorY);
    // lineHeight を使用して終了Y座標を計算
    final Offset endPoint = Offset(cursorX, cursorY + lineHeight);

    canvas.drawLine(startPoint, endPoint, cursorPaint);

    // showGridがtrueのときだけ線を描く
    if (showGrid) {
      final paint = Paint()
        ..color = Colors.grey.withValues(alpha: 0.3)
        ..strokeWidth = 1.0;

      for (double x = 0; x < size.width; x += charWidth) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }

      for (double y = 0; y < size.height; y += lineHeight) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant MemoPainter oldDelegate) {
    // ★ 6. グリッドの表示設定が変わった時も再描画する
    return oldDelegate.lines != lines ||
        oldDelegate.charWidth != charWidth ||
        oldDelegate.charHeight != charHeight ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.cursorRow != cursorRow ||
        oldDelegate.cursorCol != cursorCol ||
        oldDelegate.textStyle != textStyle;
  }
}
