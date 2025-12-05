import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HardwareKeyboardのため
import 'package:flutter/foundation.dart'; // listEquals関数のため
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
  int _preferredVisualX = 0; // 上下移動時に維持したい見た目の幅
  bool _isOverwriteMode = false; // 上書きモードフラグ
  List<String> _lines = ['']; // エディタのテキストエリア

  //  グリッド表示のON/OFFを管理する変数を追加
  bool _showGrid = false; // デフォルトはOFFにしておきます

  // IMEとの接続を管理する変数
  TextInputConnection? _inputConnection;

  // 変換中の文字（未確定文字）を保持する
  String _composingText = "";

  // スクロールバーを表示されるためのコントローラーの明示
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  // フォーカスノードを追加
  final FocusNode _focusNode = FocusNode();

  // 描画エリア(CustomPaint)の正体をつかむためのキー
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

    // Bindingの初期化保証
    WidgetsBinding.instance;

    // リスナーの設定
    _focusNode.addListener(_handleFocusChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // フレーム描画後に実行する必要があるため、
      // 非同期で呼び出すでフォーカスを当てる。
      _focusNode.requestFocus();
      //
      // フォーカスが既に当たっていると判断されてリスナーが動かない場合があるため
      // ここで明示的に呼び出す
      if (_focusNode.hasFocus) {
        _activateIme(context);
      }
    });

    // スクロールするたびにIME位置を更新
    _verticalScrollController.addListener(_updateImeWindowPosition);
    _horizontalScrollController.addListener(_updateImeWindowPosition);

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
      // 1. クリックされた「見た目の位置」を計算
      int clickedVisualX = (tapPosition.dx / _charWidth).round();
      int clickedRow = (tapPosition.dy / _lineHeight).floor();

      // 行は 0 以上、かつ現在の行数より下なら空行として扱う（フリーカーソルなので制限しないが、データアクセス用に行数をチェック）
      _cursorRow = max(0, clickedRow);

      // 現在の行のテキストを取得
      String currentLine = "";
      if (_cursorRow < _lines.length) {
        currentLine = _lines[_cursorRow];
      }

      // その行の「実際の見た目の幅」を計算
      int lineVisualWidth = _calcTextWidth(currentLine);

      // ケースA: 文字が存在する範囲内をクリックした場合
      if (clickedVisualX <= lineVisualWidth) {
        // 見た目の位置から、最適な文字インデックスを逆算する
        _cursorCol = _getColFromVisualX(currentLine, clickedVisualX);
      }
      // ケースB: 文字がない「虚空（右側の空間）」をクリックした場合
      else {
        // 「行の文字数」 + 「足りない分のスペースの数（Visualの差分）」
        // 全角文字が含まれていても、虚空は半角スペース(幅1)で埋めるため、差分をそのまま足せば良い
        int gap = clickedVisualX - lineVisualWidth;
        _cursorCol = currentLine.length + gap;
      }

      // 3. 上下移動用に「見た目の位置」を記憶更新
      // クリックしたその場所を維持したいので、計算結果から再計算せず、クリック位置を採用
      _preferredVisualX = clickedVisualX;

      // フォーカスを取得する（キーボード入力への準備）
      _focusNode.requestFocus();

      // クリックで移動した先にIME窓を追従させる
      WidgetsBinding.instance.addPersistentFrameCallback((_) {
        _updateImeWindowPosition();
      });

      // IME接続を開始！
      // _activateIme(context);
    });
  }

  // フォーカスの状態が変わったときに呼ばれる監視役
  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      // ケース1: フォーカスが当たった時 (ON)
      // View ID の問題を避けるため、念の為フレーム描画後に接続に行く
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // ウィジェットがまだ画面にあるか(mounted)確認してから接続
        if (mounted) {
          _activateIme(context);
        }
      });
    } else {
      // ケース2: フォーカスが外れた時 (OFF)
      // IMEとの接続を確実に切断する
      _inputConnection?.close();
      _inputConnection = null;
    }
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
      // 改行
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
      // バックスペース
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
          // パターン 2: カーソルが行の先頭 (0列目) にあり、かつ1行目ではない場
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
      // Delete
      case PhysicalKeyboardKey.delete:
        // 現在の行が存在しない場合はなにもしない。
        if (_cursorRow >= _lines.length) return KeyEventResult.handled;

        final currentLine = _lines[_cursorRow];

        // カーソルが行の文字数よりも「左」にある場合（文字の上、または途中）
        if (_cursorCol < currentLine.length) {
          // カーソル位置の文字を削除して詰める
          final part1 = currentLine.substring(0, _cursorCol);
          // _cursorCol + 1 が 範囲外でないか確かめる
          final part2 = (_cursorCol + 1 < currentLine.length)
              ? currentLine.substring(_cursorCol + 1)
              : '';
          _lines[_cursorRow] = part1 + part2;
        }
        // カーソルが行末、または行末より右（虚空）にある場合
        // else {
        // カーソルが行末にある場合
        else if (_cursorCol == currentLine.length) {
          // 次の行が存在するか確認
          if (_cursorRow < _lines.length - 1) {
            // 次の行の内容を取得
            final nextLine = _lines[_cursorRow + 1];

            // 現在の行をカーソル位置までスペースで埋める（エディタの思想：空間の実体化）
            // これにより、次の行がカーソル位置に「吸い寄せられる」形で結合される
            // final String paddedCurrentLine = currentLine.padRight(_cursorCol);

            // 結合
            //_lines[_cursorRow] = paddedCurrentLine + nextLine;
            _lines[_cursorRow] += nextLine;

            // 吸い上げた次の行を削除
            _lines.removeAt(_cursorRow + 1);
          }
        }
        return KeyEventResult.handled;

      // INSキー・上書きモード
      case PhysicalKeyboardKey.insert:
        setState(() {
          _isOverwriteMode = !_isOverwriteMode;
        });
        return KeyEventResult.handled;

      //矢印キー
      case PhysicalKeyboardKey.arrowLeft:
        if (_cursorCol > 0) {
          _cursorCol--;
        } else if (_cursorRow > 0) {
          _cursorRow--;
          _cursorCol = _lines[_cursorRow].length;
        }
        // 移動後の位置の「見た目の幅」を記憶
        String currentLine = _lines[_cursorRow];
        String textUpToCursor = currentLine.substring(
          0,
          min(_cursorCol, currentLine.length),
        );
        _preferredVisualX = _calcTextWidth(textUpToCursor);

        // 移動後にIME窓を更新
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });

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
          // 移動後の位置の見た目幅の記憶
          String line = _lines[_cursorRow];
          String textUpToCursor = line.substring(
            0,
            min(_cursorCol, line.length),
          );
          _preferredVisualX = _calcTextWidth(textUpToCursor);
        }
        // 移動後にIME窓を更新
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });

        return KeyEventResult.handled;
      case PhysicalKeyboardKey.arrowUp:
        if (isAlt) {
          // 【Alt+上】完全フリー移動
          // 0より上には行けないが、行データ有無に関係なく移動可能
          if (_cursorRow > 0) {
            _cursorRow--;
          }
        } else {
          // 通常の上移動
          if (_cursorRow > 0) {
            _cursorRow--;
          }
        }

        // 列位置(_cursorCol)の決定
        if (_cursorRow < _lines.length) {
          String line = _lines[_cursorRow];
          int lineWidth = _calcTextWidth(line);

          if (isAlt && _preferredVisualX > lineWidth) {
            int gap = _preferredVisualX - lineWidth;
            _cursorCol = line.length + gap;
          } else {
            _cursorCol = _getColFromVisualX(line, _preferredVisualX);
            // ★修正: 文字列よりも右側への配置を許可
          }
        } else {
          _cursorCol = _preferredVisualX;
        }

        // 移動後にIME窓を更新
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });

        return KeyEventResult.handled;
      case PhysicalKeyboardKey.arrowDown:
        if (isAlt) {
          // 【Alt+下】フリーカーソル移動（行制限なし）
          _cursorRow++;
          // 虚空移動なので、列位置は現在のVisualXを維持（何もしない or VisualXから再計算）
          // 行が存在すれば文字に合わせて吸着、存在しなければVisualXそのものをColとみなす
        } else {
          // 通常の下移動
          if (_cursorRow < _lines.length - 1) {
            _cursorRow++;
          }
        }
        // --- 共通: 列位置(_cursorCol)の決定ロジック ---
        // 行データが存在する場合: 文字列に合わせて配置
        if (_cursorRow < _lines.length) {
          String line = _lines[_cursorRow];
          int lineWidth = _calcTextWidth(line);

          if (isAlt && _preferredVisualX > lineWidth) {
            int gap = _preferredVisualX - lineWidth;
            _cursorCol = line.length + gap;
          } else {
            // 行の文字の中に収まる場合 -> 文字に合わせて吸着
            _cursorCol = _getColFromVisualX(line, _preferredVisualX);
          }
        } else {
          // 行データが存在しない(虚空)場合: VisualX をそのまま Col とする (半角スペース埋め想定)
          _cursorCol = _preferredVisualX;
        }

        // 移動後にIME窓を更新
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateImeWindowPosition();
        });
        return KeyEventResult.handled;
      default:
        if (character != null && character.isNotEmpty) {
          // 通常の文字挿

          // 文字入力モードの最初で「虚空」を「実データ」に変換する
          _fillVirtualSpaceIfNeeded();

          // 現在文字をカーソル行に挿入する。
          _insertText(character);

          return KeyEventResult.handled;
        }
        // 関係ないキー（Shift単体など）は無視して、システムに任せる
        return KeyEventResult.ignored;
    }
  }

  // 文字列を現在の位置にカーソル位置に挿入する共通関数
  void _insertText(String text) {
    if (text.isEmpty) return;

    // ---------------------------------------------------------
    // 行 (Row) の拡張: カーソル位置まで行が足りなければ増やす
    // ---------------------------------------------------------
    if (_cursorRow >= _lines.length) {
      int newLinesNeeded = _cursorRow - _lines.length + 1;
      for (int i = 0; i < newLinesNeeded; i++) {
        _lines.add("");
      }
    }

    var currentLine = _lines[_cursorRow];
    // ---------------------------------------------------------
    // 列 (Col) の拡張: カーソル位置まで文字が足りなければスペースで埋める
    // --------------------------------------------------------
    if (_cursorCol > currentLine.length) {
      int spacesNeeded = _cursorCol - currentLine.length;
      // 必要な文だけ半角スペースを追加する。
      currentLine += ' ' * spacesNeeded;
    }

    // ---------------------------------------------------------
    // 文字の挿入
    // ---------------------------------------------------------
    String part1 = currentLine.substring(0, _cursorCol);
    String part2 = currentLine.substring(_cursorCol);

    // 上書きモード対応
    if (_isOverwriteMode && part2.isNotEmpty) {
      // 入力されたテキストの「見た目の幅」を計算
      int inputVisualWidth = _calcTextWidth(text);
      int removeLength = 0; //削除する文字数
      int currentVisualWidth = 0;

      var iterator = part2.runes.iterator;
      while (iterator.moveNext()) {
        if (currentVisualWidth >= inputVisualWidth && removeLength > 0) {
          break;
        }

        int rune = iterator.current;

        // 半角=1, 全角=2
        int charWidth = (rune < 128) ? 1 : 2; // 簡易幅判定
        currentVisualWidth += charWidth;

        // サロゲートペア(絵文字など)対応: 0xFFFFを超える文字は2単位、それ以外は1単位
        removeLength += (rune > 0xFFFF) ? 2 : 1;
      }

      // 計算した文字数分だけ part2 を削る
      if (removeLength > 0) {
        if (part2.length >= removeLength) {
          part2 = part2.substring(removeLength);
        } else {
          part2 = "";
        }
      }
    }

    // 行を更新（カーソル位置に文字を挟む）
    _lines[_cursorRow] = part1 + text + part2;
    // カーソルを進める。
    _cursorCol += text.length;

    // 入力後はVisuallXも更新しておく。
    String newLine = _lines[_cursorRow];
    // カーソル位置までの文字列で幅を計算（行末を超えていればその分も考慮される）
    int safeEnd = min(_cursorCol, newLine.length);
    _preferredVisualX = _calcTextWidth(newLine.substring(0, safeEnd));

    // IME位置更新
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateImeWindowPosition();
      });
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

  // 全角・半角の文字幅計算ロジック
  // 簡易的にASCII以外を全角として扱う。
  int _calcTextWidth(String text) {
    int width = 0;
    for (int i = 0; i < text.runes.length; i++) {
      // ASCII文字(0-127)は幅1、それ以外は幅2
      width += (text.runes.elementAt(i) < 128) ? 1 : 2;
    }
    return width;
  }

  // 指定した「見た目の幅(targetVisualX)」に最も近い「文字数(col)」を探す
  int _getColFromVisualX(String line, int targetVisualX) {
    int currentVisualX = 0;
    for (int i = 0; i < line.runes.length; i++) {
      int charWidth = (line.runes.elementAt(i) < 128) ? 1 : 2;
      // 次の文字を足すとターゲットを超える場合、
      // どちらに近いかで判定（ここでは単純に超える手前で止めるか、超えたら止めるか）
      // 一般的なエディタ挙動として「半分以上超えたら次」などあるが、
      // ここではシンプルに「超える直前」または「超えた位置」の近い方を採用
      if (currentVisualX + charWidth > targetVisualX) {
        // より近い方を返す
        if ((targetVisualX - currentVisualX) <
            (currentVisualX + charWidth - targetVisualX)) {
          return i;
        } else {
          return i + 1; // 次の文字も含める。
        }
      }
      currentVisualX += charWidth;
    }
    return line.length; // 行末
  }

  // IMEに接続する関数
  void _activateIme(BuildContext context) {
    if (_inputConnection == null || !_inputConnection!.attached) {
      // ViewIDの取得(引数のCoontext)を使う。
      final viewId = View.of(context).viewId;
      print("IME接続試行 View ID: $viewId");

      // 構成設定（OSに「これはただのテキストだよ」と伝える）
      final config = TextInputConfiguration(
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        // Flutter 3.22以降は必須
        // viewId: View.of(context).viewId,
        viewId: viewId,
        readOnly: false,
      );

      // 接続開始！ (this は TextInputClient である自分自身)
      _inputConnection = TextInput.attach(this, config);
      // キーボードを表示（スマホの場合。デスクトップでも念のため呼ぶ）
      _inputConnection!.show();
      print("IME接続開始！");
    }
  }

  // 現在のカーソル位置を計算して、IMEにウィンドウ位置を通知する共通関数
  void _updateImeWindowPosition() {
    // 接続がない、またはキーが紐づいていない場合は何もしない。
    if (_inputConnection == null ||
        !_inputConnection!.attached ||
        _painterKey.currentContext == null) {
      return;
    }

    final RenderBox? renderBox =
        _painterKey.currentContext!.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // 安全な幅・高さ
    final double safeCharWidth = _charWidth > 0 ? _charWidth : 16.0;
    final double safeLineHeight = _lineHeight > 0 ? _lineHeight : 24.0;

    // 1. エディタ(CustomPaint)の変形情報を通知
    // これにより、AppBarの高さやスクロール量
    //(_painterKeyが持っている情報)が自動的に加味されます！

    final Matrix4 transform = renderBox.getTransformTo(null);
    _inputConnection!.setEditableSizeAndTransform(renderBox.size, transform);

    // ローカル座標計算 (CustomPaint左上からの相対位置)
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

    int visualX = _calcTextWidth(textBeforeCursor);
    final double localPixelX = visualX * safeCharWidth;
    final double localPixelY = _cursorRow * safeLineHeight;

    // 通知 (ローカル座標のままでOK)
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
                          key: _painterKey, // 描画エリアの取得のため
                          painter: MemoPainter(
                            lines: _lines,
                            charWidth: _charWidth,
                            charHeight: _charHeight,
                            showGrid: _showGrid, // Grid ON/OFFの状態をPainterに渡す
                            isOverwriteMode: _isOverwriteMode,
                            cursorRow: _cursorRow, // カーソルの位置を渡す
                            cursorCol: _cursorCol,
                            lineHeight: _lineHeight,
                            textStyle: _textStyle,
                            composingText: _composingText, // Painterに渡す未確定文字
                          ),
                          size: Size.infinite, // 適切なサイズ？
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
  // A. ここに日本語入力のデータが流れてきます。
  @override
  void updateEditingValue(TextEditingValue value) {
    print("IMEからの入力: text=${value.text}, composing=${value.composing}");

    // 確定判定: composingの範囲が (-1, -1) なら「確定」
    if (!value.composing.isValid) {
      // 文字があれば挿入する
      if (value.text.isNotEmpty) {
        setState(() {
          _insertText(value.text);
          // 確定したので未確定バッファを空にする
          _composingText = "";
        });
      }
      // 重要: IMEに入力完了を伝え、内部状態をリセット
      // これをしないと、次に入力したときに「あいうえお」が重複して送られてきたりします。
      // 「あなたの仕事は終わりました、次は空っぽから始めてください」と伝えます。
      if (_inputConnection != null && _inputConnection!.attached) {
        _inputConnection!.setEditingState(TextEditingValue.empty);
      }
    }
    // 未確定(変換中)の場合
    else {
      setState(() {
        // IMEから送られてきた変換中の文字を保存して画面更新
        _composingText = value.text;
      });

      //IME 通知関数の呼び出し
      _updateImeWindowPosition();
    }
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
  final bool isOverwriteMode; // 上書きモード
  final int cursorRow;
  final int cursorCol;
  final TextStyle textStyle; // TextPainter に渡すスタイル
  final String composingText; // 未確定文字

  MemoPainter({
    required this.lines,
    required this.charWidth,
    required this.charHeight,
    required this.showGrid,
    required this.isOverwriteMode,
    required this.cursorRow,
    required this.cursorCol,
    required this.lineHeight,
    required this.textStyle,
    required this.composingText,
  });

  // 文字幅計算ヘルパー (Stateと同じロジックが必要)
  int _calcTextWidth(String text) {
    int width = 0;
    for (int i = 0; i < text.runes.length; i++) {
      if (text.runes.elementAt(i) < 128) {
        width += 1;
      } else {
        width += 2;
      }
    }
    return width;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // --------------------------------------------------------
    // 1. テキスト（確定済み）の描画
    // --------------------------------------------------------
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];

      // 描画ロジックの変更:
      // TextSpanでまとめて描画すると文字ごとの位置計算がPainter任せになり、
      // グリッドとズレるため、1文字ずつ、あるいは全角/半角を意識して描画するのが理想ですが、
      // 今回は「等幅フォント」を前提に、全角が半角2つ分の幅を持つとして計算します。
      final textSpan = TextSpan(text: line, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(0, i * lineHeight));

      // 改行マークの描画
      // 行末に改行マーク ↵ を描く。
      // 厳密には最終行に描かない判定が合っても良い。
      // String line = lines[i];
      int visualWidth = _calcTextWidth(line);
      double lineEndX = visualWidth * charWidth;
      double lineY = i * lineHeight;

      //改行マーク用の薄い色
      final markStyle = TextStyle(
        color: Colors.grey.shade500,
        fontSize: textStyle.fontSize,
      );
      final markSpan = TextSpan(text: '↵', style: markStyle);
      final markPainter = TextPainter(
        text: markSpan,
        textDirection: TextDirection.ltr,
      );
      markPainter.layout();
      markPainter.paint(canvas, Offset(lineEndX + 2, lineY)); // 少し右に描く
    }

    // --------------------------------------------------------
    // 2. カーソル位置のX座標計算 (全角対応)
    // --------------------------------------------------------
    double cursorPixelX = 0.0;

    // カーソルがある行の文字列を取得
    String currentLineText = "";
    if (cursorRow < lines.length) {
      currentLineText = lines[cursorRow];
    }

    // カーソル位置までの文字列を取得（虚空対応）
    String textBeforeCursor = "";
    if (cursorCol <= currentLineText.length) {
      textBeforeCursor = currentLineText.substring(0, cursorCol);
    } else {
      // カーソルが行末より先にある場合、スペースで埋めたと仮定して計算
      int spacesNeeded = cursorCol - currentLineText.length;
      textBeforeCursor = currentLineText + (' ' * spacesNeeded);
    }

    // 表示上の幅（単位: 半角文字数）を計算
    int visualCursorX = _calcTextWidth(textBeforeCursor);
    cursorPixelX = visualCursorX * charWidth;

    double cursorPixelY = cursorRow * lineHeight;

    // --------------------------------------------------------
    // 3. 未確定文字 (composingText) の描画
    // --------------------------------------------------------
    // 課題4対応: 虚空でもここに描画される
    if (composingText.isNotEmpty) {
      // 未確定文字用のスタイル
      print('fontsize = ${textStyle.fontSize}');
      final composingStyle = TextStyle(
        color: Colors.black,
        fontSize: textStyle.fontSize,
        fontFamily: textStyle.fontFamily,
        decoration: TextDecoration.underline, // 下線
        decorationStyle: TextDecorationStyle.solid,
        decorationColor: Colors.blue,
        backgroundColor: Colors.white.withValues(
          alpha: 0.8,
        ), // 背景を白くして下の文字を隠す（上書きっぽく見せる）
      );

      final span = TextSpan(text: composingText, style: composingStyle);
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr);
      tp.layout();

      // カーソル位置に描画（既存の文字の上に被せる）
      tp.paint(canvas, Offset(cursorPixelX, cursorPixelY));

      // ※変換中は、カーソルを未確定文字の後ろに表示したい場合
      // visualCursorX に composingText の幅を加算する
      int composingWidth = _calcTextWidth(composingText);
      cursorPixelX += composingWidth * charWidth;
    }

    // --------------------------------------------------------
    // 4. カーソルの描画
    // --------------------------------------------------------
    // 上書きモードならカーソル形状を変える
    if (isOverwriteMode) {
      // ブロックカーソル(文字を覆う四角形)
      final cursorRect = Rect.fromLTWH(
        cursorPixelX,
        cursorPixelY,
        charWidth,
        lineHeight,
      );
      canvas.drawRect(
        cursorRect,
        Paint()..color = Colors.blue.withValues(alpha: 0.5),
      );
    } else {
      // 縦線カーソル
      final cursorPaint = Paint()
        ..color = Colors.black
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.square;

      canvas.drawLine(
        Offset(cursorPixelX, cursorPixelY),
        Offset(cursorPixelX, cursorPixelY + lineHeight),
        cursorPaint,
      );
    }
    // --------------------------------------------------------
    // 5. グリッド線 (showGrid時)
    // --------------------------------------------------------
    // showGridがtrueのときだけ線を描く
    if (showGrid) {
      final gridpaint = Paint()
        ..color = Colors.grey.withValues(alpha: 0.3)
        ..strokeWidth = 1.0;

      for (double x = 0; x < size.width; x += charWidth) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridpaint);
      }

      for (double y = 0; y < size.height; y += lineHeight) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridpaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant MemoPainter oldDelegate) {
    return listEquals(oldDelegate.lines, lines) || // delete処理のため 文字比較が必要
        // oldDelegate.lines != lines || // これはダメ。
        oldDelegate.charWidth != charWidth ||
        oldDelegate.charHeight != charHeight ||
        oldDelegate.showGrid != showGrid || // グリッドの表示設定が変わった時も再描画する
        oldDelegate.cursorRow != cursorRow ||
        oldDelegate.cursorCol != cursorCol ||
        oldDelegate.textStyle != textStyle ||
        oldDelegate.composingText != composingText;
  }
}
