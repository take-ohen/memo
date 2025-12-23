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

  TextInputConnection? _inputConnection;

  // 検索・置換UI用
  bool _showSearchBar = false;
  bool _isReplaceMode = false;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // カーソル点滅処理
  Timer? _cursorBlinkTimer;
  bool _showCursor = true; // カーソル表示フラグ

  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _painterKey = GlobalKey();

  // コントローラーの設定値を使用するように変更
  TextStyle get _textStyle => TextStyle(
    fontFamily: _controller.fontFamily,
    fontSize: _controller.fontSize,
    color: Colors.black,
  );

  TextStyle get _lineNumberStyle => TextStyle(
    fontFamily: _controller.fontFamily,
    fontSize: _controller.fontSize,
    color: Colors.grey,
  );

  // テスト専用のゲッター(抜け道)
  @visibleForTesting
  int get debugCursorCol => _controller.cursorCol;

  @visibleForTesting
  int get debugCursorRow => _controller.cursorRow;

  @visibleForTesting
  List<String> get debugLines => _controller.lines;

  @visibleForTesting
  EditorController get debugController => _controller;

  @override
  void initState() {
    super.initState();
    _controller = EditorController(); // コントローラー初期化

    // 設定読み込み
    _controller.loadSettings();

    // コントローラーの変更を検知して画面を更新する
    // フォントサイズ変更時などにメトリクス再計算が必要
    _controller.addListener(() => _calculateGlyphMetrics());

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
    _searchController.dispose();
    _replaceController.dispose();
    _searchFocusNode.dispose();
    _focusNode.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _cursorBlinkTimer?.cancel(); // カーソル点滅用
    super.dispose();
  }

  void _calculateGlyphMetrics() {
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: _textStyle),
      textDirection: TextDirection.ltr,
    );
    painter.layout();

    setState(() {
      _charWidth = painter.width;
      _charHeight = painter.height;
      _lineHeight = _charHeight * 1.2;
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
    _controller.undo();
  }

  // --- REDO (Ctrl+Y) ---
  void _redo() {
    _controller.redo();
  }

  // キー処理
  KeyEventResult _handleKeyPress(KeyEvent event) {
    // IME入力中（未確定文字がある）場合は、エディタとしてのキー処理（カーソル移動や選択など）をスキップし、
    // IMEに処理を任せる。これにより、変換中のShiftキーなどで意図しない範囲選択が発生するのを防ぐ。
    if (_controller.composingText.isNotEmpty) {
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final PhysicalKeyboardKey physicalKey = event.physicalKey;

    // 検索・置換ショートカット
    bool isControl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (isControl) {
      if (physicalKey == PhysicalKeyboardKey.keyF) {
        setState(() {
          _showSearchBar = true;
          _isReplaceMode = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchFocusNode.requestFocus();
        });
        return KeyEventResult.handled;
      }
      if (physicalKey == PhysicalKeyboardKey.keyH) {
        setState(() {
          _showSearchBar = true;
          _isReplaceMode = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchFocusNode.requestFocus();
        });
        return KeyEventResult.handled;
      }
    }
    if (physicalKey == PhysicalKeyboardKey.escape) {
      if (_showSearchBar) {
        setState(() {
          _showSearchBar = false;
          _controller.clearSearch();
          _focusNode.requestFocus(); // エディタにフォーカスを戻す
        });
        return KeyEventResult.handled;
      }
    }

    // --- Step 1.1: コントローラーに処理を委譲 ---
    final result = _controller.handleKeyPress(event);
    if (result == KeyEventResult.handled) {
      // コントローラーが処理したので、IME窓の位置を更新して終了
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _updateImeWindowPosition(),
      );
      return KeyEventResult.handled;
    }

    final String? character = event.character;
    switch (physicalKey) {
      default:
        if (character != null && character.isNotEmpty) {
          _controller.input(character);
          // IME窓の更新はControllerではできないのでここで行う
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateImeWindowPosition();
          });
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
    }
  }

  // --- ファイル操作 ---

  // ファイルを開く
  Future<void> _openFile() async {
    await _controller.openFile();
  }

  // 上書き保存 (Ctrl + S)
  Future<void> _saveFile() async {
    try {
      final path = await _controller.saveFile();
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存しました: $path'),
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
    await _controller.saveAsFile();
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

  // カーソル位置へスクロールする
  void _scrollToCursor() {
    if (!_verticalScrollController.hasClients ||
        !_horizontalScrollController.hasClients)
      return;

    // 垂直スクロール
    final double cursorY = _controller.cursorRow * _lineHeight;
    final double viewportHeight =
        _verticalScrollController.position.viewportDimension;
    final double currentScrollY = _verticalScrollController.offset;

    if (cursorY < currentScrollY) {
      _verticalScrollController.jumpTo(cursorY);
    } else if (cursorY + _lineHeight > currentScrollY + viewportHeight) {
      _verticalScrollController.jumpTo(cursorY + _lineHeight - viewportHeight);
    }

    // 水平スクロール
    final double cursorX = _controller.preferredVisualX * _charWidth;
    final double viewportWidth =
        _horizontalScrollController.position.viewportDimension;
    final double currentScrollX = _horizontalScrollController.offset;
    final double margin = _charWidth * 4; // 少し余裕を持たせる

    if (cursorX < currentScrollX) {
      _horizontalScrollController.jumpTo(max(0.0, cursorX - margin));
    } else if (cursorX > currentScrollX + viewportWidth) {
      _horizontalScrollController.jumpTo(cursorX - viewportWidth + margin);
    }
  }

  // 検索バーのビルド
  Widget _buildSearchBar() {
    if (!_showSearchBar) return const SizedBox.shrink();

    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: const InputDecoration(
                    labelText: '検索',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(8),
                  ),
                  onChanged: (value) {
                    _controller.search(value);
                    _scrollToCursor();
                  },
                  onSubmitted: (value) {
                    _controller.nextMatch();
                    _scrollToCursor();
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_upward),
                onPressed: () {
                  _controller.previousMatch();
                  _scrollToCursor();
                },
                tooltip: '前へ',
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward),
                onPressed: () {
                  _controller.nextMatch();
                  _scrollToCursor();
                },
                tooltip: '次へ',
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _showSearchBar = false;
                    _controller.clearSearch();
                    _focusNode.requestFocus();
                  });
                },
                tooltip: '閉じる (Esc)',
              ),
            ],
          ),
          if (_isReplaceMode) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replaceController,
                    decoration: const InputDecoration(
                      labelText: '置換',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(8),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _controller.replace(
                      _searchController.text,
                      _replaceController.text,
                    );
                  },
                  child: const Text('置換'),
                ),
                TextButton(
                  onPressed: () {
                    _controller.replaceAll(
                      _searchController.text,
                      _replaceController.text,
                    );
                  },
                  child: const Text('全て置換'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 行番号エリアの幅を計算 (桁数 * 文字幅 + パディング)
    int digits = _controller.lines.length.toString().length;
    double lineNumberAreaWidth = digits * _charWidth + 20.0;

    // 1. コンテンツのサイズ計算 (最大行幅と総行数)
    double maxLineWidth = 0;
    for (var line in _controller.lines) {
      double w = TextUtils.calcTextWidth(line).toDouble();
      if (w > maxLineWidth) maxLineWidth = w;
    }
    double textContentWidth = maxLineWidth * _charWidth;
    double textContentHeight = _controller.lines.length * _lineHeight;

    // 2. エディタ領域のサイズ決定 (画面サイズ以上の余白を持たせる)
    Size screenSize = MediaQuery.of(context).size;
    double minCanvasSize = _controller.minCanvasSize; // 設定値を使用

    double editorWidth = max(
      minCanvasSize,
      textContentWidth + screenSize.width / 2,
    );
    double editorHeight = max(
      minCanvasSize,
      textContentHeight + screenSize.height / 2,
    );

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
                value: _controller.showGrid,
                onChanged: (value) {
                  _controller.toggleGrid();
                },
              ),
            ],
          ),
          PopupMenuButton<int>(
            tooltip: 'タブ幅設定',
            icon: const Icon(Icons.space_bar),
            onSelected: (value) {
              _controller.setTabWidth(value);
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                checked: _controller.tabWidth == 2,
                value: 2,
                child: const Text('Tab Width: 2'),
              ),
              CheckedPopupMenuItem(
                checked: _controller.tabWidth == 4,
                value: 4,
                child: const Text('Tab Width: 4'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: Scrollbar(
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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- 行番号エリア ---
                      Container(
                        width: lineNumberAreaWidth,
                        height: editorHeight, // エディタの高さに合わせる
                        color: Colors.grey.shade200,
                        child: CustomPaint(
                          size: Size(lineNumberAreaWidth, editorHeight),
                          painter: LineNumberPainter(
                            lineCount: _controller.lines.length,
                            lineHeight: _lineHeight,
                            textStyle: _lineNumberStyle,
                          ),
                        ),
                      ),
                      // --- エディタエリア ---
                      Expanded(
                        child: Focus(
                          focusNode: _focusNode,
                          onKeyEvent: (FocusNode node, KeyEvent event) {
                            final result = _handleKeyPress(event);
                            return result;
                          },
                          child: SingleChildScrollView(
                            controller: _horizontalScrollController,
                            scrollDirection: Axis.horizontal,
                            child: GestureDetector(
                              // タップダウン； カーソル移動＆選択解除
                              onTapDown: (details) {
                                _resetCursorBlink();
                                _controller.clearSelection();
                                _controller.handleTap(
                                  details.localPosition,
                                  _charWidth,
                                  _lineHeight,
                                );
                                _focusNode.requestFocus();
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  _updateImeWindowPosition();
                                });
                              },
                              //ドラッグ開始 (選択範囲の始点を記録)
                              onPanStart: (details) {
                                _resetCursorBlink();
                                _controller.handlePanStart(
                                  details.localPosition,
                                  _charWidth,
                                  _lineHeight,
                                  HardwareKeyboard.instance.isAltPressed,
                                );
                                _focusNode.requestFocus();
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  _updateImeWindowPosition();
                                });
                              },
                              // ドラッグ中(カーソル位置を更新=選択範囲の最終位置が変わる)
                              onPanUpdate: (details) {
                                _resetCursorBlink();
                                _controller.handleTap(
                                  details.localPosition,
                                  _charWidth,
                                  _lineHeight,
                                );
                                // ドラッグ中はフォーカス要求は不要だが、IME位置更新は必要かもしれない
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  _updateImeWindowPosition();
                                });
                              },
                              onPanEnd: (details) {
                                //                    _isDragging = false;
                              },
                              child: Container(
                                width: editorWidth,
                                height: editorHeight,
                                child: CustomPaint(
                                  key: _painterKey,
                                  painter: MemoPainter(
                                    lines: _controller.lines,
                                    charWidth: _charWidth,
                                    charHeight: _charHeight,
                                    showGrid: _controller.showGrid,
                                    isOverwriteMode:
                                        _controller.isOverwriteMode,
                                    cursorRow: _controller.cursorRow,
                                    cursorCol: _controller.cursorCol,
                                    lineHeight: _lineHeight,
                                    textStyle: _textStyle,
                                    composingText: _controller.composingText,
                                    selectionOriginRow:
                                        _controller.selectionOriginRow,
                                    selectionOriginCol:
                                        _controller.selectionOriginCol,
                                    showCursor: _showCursor,
                                    isRectangularSelection:
                                        _controller.isRectangularSelection,
                                    searchResults:
                                        _controller.searchResults, // ★追加
                                    currentSearchIndex:
                                        _controller.currentSearchIndex, // ★追加
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
                    ],
                  ),
                ),
              ),
            ),
          ),
          // --- ステータスバー ---
          Container(
            height: 24,
            color: Colors.grey.shade300,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                // 変更状態
                SizedBox(
                  width: 80,
                  child: Text(
                    _controller.isDirty ? "未保存 *" : "",
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                // カーソル位置
                Text(
                  "Ln ${_controller.cursorRow + 1}, Col ${_controller.cursorCol + 1}",
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 16),
                // 文字コード
                Text(
                  _controller.currentEncoding.name,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
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
        _controller.input(value.text);
        _controller.updateComposingText("");
      }
      if (_inputConnection != null && _inputConnection!.attached) {
        _inputConnection!.setEditingState(TextEditingValue.empty);
      }
    } else {
      _controller.updateComposingText(value.text);
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
