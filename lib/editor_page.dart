import 'dart:io';
import 'dart:ui' as ui;
import 'dart:convert'; // Encoding用

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';

import 'l10n/app_localizations.dart';
// 分割したファイルをインポート
import 'memo_painter.dart';
import 'drawing_painter.dart';
import 'text_utils.dart';
import 'history_manager.dart';
import 'file_io_helper.dart'; // FileIOHelperをインポート
import 'editor_controller.dart'; // コントローラーをインポート
// 相対パスからpackageパスへ変更
import 'editor_document.dart'; // NewLineTypeのためにインポート
import 'settings_dialog.dart'; // 設定ダイアログをインポート
import 'grep_result.dart';
import 'drawing_data.dart'; // DrawingTypeのためにインポート
import 'color_picker_widget.dart'; // 色選択用

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
  late final AppLifecycleListener _listener;

  TextInputConnection? _inputConnection;

  // 検索・置換UI用
  bool _showSearchBar = false;
  bool _isReplaceMode = false;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showGrepResults = false;
  double _grepPanelHeight = 250.0; // Grepパネルの高さ

  // カーソル点滅処理
  Timer? _cursorBlinkTimer;
  bool _showCursor = true; // カーソル表示フラグ
  MouseCursor _currentMouseCursor = SystemMouseCursors.text; // 現在のマウスカーソル

  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _rulerScrollController = ScrollController(); // ルーラー用
  final ScrollController _scrollbarScrollController =
      ScrollController(); // 固定スクロールバー用
  final ScrollController _grepScrollController = ScrollController(); // Grep結果用
  final ScrollController _grepHorizontalScrollController =
      ScrollController(); // Grep結果横スクロール用
  final FocusNode _focusNode = FocusNode();

  // ミニマップ用
  static const double _minimapLineHeight = 3.0;
  static const double _minimapCharWidth = 2.0;
  static const double _minimapWidth = 100.0;

  final GlobalKey _painterKey = GlobalKey();
  
  // ドロワー操作用のキー
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // プロパティバー用コントローラー
  late TextEditingController _widthController;
  late TextEditingController _paddingXController;
  late TextEditingController _paddingYController;
  late TextEditingController _rowsController;
  late TextEditingController _colsController;
  final FocusNode _widthFocus = FocusNode();
  final FocusNode _paddingXFocus = FocusNode();
  final FocusNode _paddingYFocus = FocusNode();
  final FocusNode _rowsFocus = FocusNode();
  final FocusNode _colsFocus = FocusNode();

  // 図形リスト用フィルタ
  DrawingType? _drawingListFilter;

  // コントローラーの設定値を使用するように変更
  TextStyle get _textStyle => TextStyle(
    fontFamily: _controller.fontFamily,
    fontSize: _controller.fontSize,
    fontWeight: _controller.editorBold ? FontWeight.bold : FontWeight.normal,
    fontStyle: _controller.editorItalic ? FontStyle.italic : FontStyle.normal,
    color: Color(_controller.editorTextColor), // 設定値を適用
    // フォールバックフォントを指定して、記号などが意図しない幅で表示されるのを防ぐ
    fontFamilyFallback: const [
      'Meiryo',
      'Yu Gothic',
      'MS Gothic',
      'Consolas',
      'Courier New',
      'monospace',
    ],
  );

  TextStyle get _lineNumberStyle => TextStyle(
    fontFamily: _controller.fontFamily,
    fontSize: _controller.lineNumberFontSize, // 設定値を使用
    color: Color(_controller.lineNumberColor), // 設定値を使用
    fontFamilyFallback: const ['Meiryo', 'Yu Gothic', 'MS Gothic', 'monospace'],
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

    // プロパティバー用コントローラー初期化
    _widthController = TextEditingController();
    _paddingXController = TextEditingController();
    _paddingYController = TextEditingController();
    _rowsController = TextEditingController();
    _colsController = TextEditingController();

    _syncPropertyInputs(); // 初期値反映

    // リスナー登録
    _controller.addListener(_syncPropertyInputs);

    _widthFocus.addListener(() {
      if (!_widthFocus.hasFocus) _commitWidth();
    });
    _paddingXFocus.addListener(() {
      if (!_paddingXFocus.hasFocus) _commitPadding();
    });
    _paddingYFocus.addListener(() {
      if (!_paddingYFocus.hasFocus) _commitPadding();
    });
    _rowsFocus.addListener(() {
      if (!_rowsFocus.hasFocus) _commitTableGrid();
    });
    _colsFocus.addListener(() {
      if (!_colsFocus.hasFocus) _commitTableGrid();
    });

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

    // スクロール同期の設定
    _setupScrollSync();

    // アプリ終了リスナーの設定
    _listener = AppLifecycleListener(onExitRequested: _handleExitRequest);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncPropertyInputs);
    _listener.dispose();
    _controller.dispose();
    _searchController.dispose();
    _replaceController.dispose();
    _searchFocusNode.dispose();
    _focusNode.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _rulerScrollController.dispose();
    _scrollbarScrollController.dispose();
    _grepScrollController.dispose();
    _grepHorizontalScrollController.dispose();
    _cursorBlinkTimer?.cancel(); // カーソル点滅用
    _widthController.dispose();
    _paddingXController.dispose();
    _paddingYController.dispose();
    _rowsController.dispose();
    _colsController.dispose();
    _widthFocus.dispose();
    _paddingXFocus.dispose();
    _paddingYFocus.dispose();
    _rowsFocus.dispose();
    _colsFocus.dispose();
    super.dispose();
  }

  // スクロール同期ロジック
  bool _isSyncing = false;
  void _setupScrollSync() {
    // エディタ本体 -> ルーラー & スクロールバー
    _horizontalScrollController.addListener(() {
      if (_isSyncing) return;
      if (_horizontalScrollController.hasClients) {
        _isSyncing = true;
        final offset = _horizontalScrollController.offset;
        if (_rulerScrollController.hasClients) {
          _rulerScrollController.jumpTo(offset);
        }
        if (_scrollbarScrollController.hasClients) {
          _scrollbarScrollController.jumpTo(offset);
        }
        _isSyncing = false;
      }
    });

    // ルーラー -> エディタ本体 & スクロールバー
    _rulerScrollController.addListener(() {
      if (_isSyncing) return;
      if (_rulerScrollController.hasClients) {
        _isSyncing = true;
        final offset = _rulerScrollController.offset;
        if (_horizontalScrollController.hasClients) {
          _horizontalScrollController.jumpTo(offset);
        }
        if (_scrollbarScrollController.hasClients) {
          _scrollbarScrollController.jumpTo(offset);
        }
        _isSyncing = false;
        // ルーラー操作時もIME位置更新が必要かもしれない
        _updateImeWindowPosition();
      }
    });

    // スクロールバー -> エディタ本体 & ルーラー
    _scrollbarScrollController.addListener(() {
      if (_isSyncing) return;
      if (_scrollbarScrollController.hasClients) {
        _isSyncing = true;
        final offset = _scrollbarScrollController.offset;
        if (_horizontalScrollController.hasClients) {
          _horizontalScrollController.jumpTo(offset);
        }
        if (_rulerScrollController.hasClients) {
          _rulerScrollController.jumpTo(offset);
        }
        _isSyncing = false;
        _updateImeWindowPosition();
      }
    });

    // 垂直スクロール同期 (エディタ -> ミニマップ)
    _verticalScrollController.addListener(() {
      if (_isSyncing) return;
      // setStateを呼んでMinimapPainterのviewportYを更新させる
      setState(() {});

      // ミニマップは固定表示なのでスクロール同期は不要
      // IME位置更新のみ行う
      _updateImeWindowPosition();
    });
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

  // マウスホバー時の処理（カーソル形状の切り替え）
  void _handleHover(PointerHoverEvent event) {
    // 1. Drawモード: 十字カーソル (図形上は移動カーソル)
    if (_controller.currentMode == EditorMode.draw) {
      // Ctrl押下時は常に描画カーソル (強制新規描画モード)
      bool isControl = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      if (isControl) {
        setState(() => _currentMouseCursor = SystemMouseCursors.precise);
        return;
      }

      bool isHit = _controller.isPointOnDrawing(
        event.localPosition,
        _charWidth,
        _lineHeight,
      );

      // テーブルの罫線判定
      if (_controller.currentShapeType == DrawingType.table &&
          _controller.selectedDrawingId != null) {
        final tableCursor = _controller.getTableCursorType(
          event.localPosition,
          _charWidth,
          _lineHeight,
        );
        if (tableCursor == 1) isHit = true; // Row Resize
        if (tableCursor == 2) isHit = true; // Col Resize

        if (tableCursor == 1) {
          setState(() => _currentMouseCursor = SystemMouseCursors.resizeRow);
          return;
        } else if (tableCursor == 2) {
          setState(() => _currentMouseCursor = SystemMouseCursors.resizeColumn);
          return;
        }
      }

      setState(() {
        _currentMouseCursor = isHit
            ? SystemMouseCursors.move
            : SystemMouseCursors.precise;
      });
      return;
    }

    // 2. Textモード: 常にIビーム (図形は無視)
    /*
    final bool isHit = _controller.isPointOnDrawing(
      event.localPosition,
      _charWidth,
      _lineHeight,
    );
    */

    setState(() {
      _currentMouseCursor = SystemMouseCursors.text;
    });
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

  // アプリ終了リクエストのハンドリング
  Future<ui.AppExitResponse> _handleExitRequest() async {
    // 未保存のドキュメントがあるか確認
    final unsavedDocs = _controller.documents
        .where((doc) => doc.isDirty)
        .toList();

    if (unsavedDocs.isEmpty) {
      return ui.AppExitResponse.exit;
    }

    final s = AppLocalizations.of(context)!;

    // 1つずつ確認
    for (final doc in unsavedDocs) {
      // 対象のタブをアクティブにする
      final index = _controller.documents.indexOf(doc);
      _controller.switchTab(index);

      // ダイアログを表示
      final result = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.titleExitConfirmation),
          content: Text("${doc.displayName} への変更を保存しますか？"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(0), // キャンセル
              child: Text(s.labelCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(1), // 保存しない
              child: Text(s.btnExitWithoutSave),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(2), // 保存する
              child: Text(s.btnSaveAndExit),
            ),
          ],
        ),
      );

      switch (result) {
        case 0: // キャンセル
        case null:
          return ui.AppExitResponse.cancel;
        case 1: // 保存しない
          continue; // 次のファイルへ
        case 2: // 保存する
          final savedPath = await _controller.saveFile();
          if (savedPath == null && doc.isDirty) {
            return ui.AppExitResponse.cancel; // 保存キャンセル時は終了中断
          }
          break;
      }
    }

    return ui.AppExitResponse.exit;
  }

  // --- ファイル操作 ---

  // ファイルを開く
  Future<void> _openFile() async {
    // 1. パスを取得
    final String? path = await FileIOHelper.instance.pickFilePath();
    if (path == null) return;

    // 2. 重複チェック
    final int index = _controller.findDocumentIndex(path);

    if (index != -1) {
      // 3. 重複あり -> 確認ダイアログ
      if (!mounted) return;
      final s = AppLocalizations.of(context)!;

      final bool? shouldReload = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.titleConfirmation),
          content: Text(s.msgFileAlreadyOpen),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false), // キャンセル
              child: Text(s.labelCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true), // 読み直す
              child: Text(s.btnReload),
            ),
          ],
        ),
      );

      if (shouldReload == true) {
        await _controller.reloadDocument(index, path);
      }
    } else {
      // 4. 重複なし -> 新規タブ
      await _controller.openDocument(path);
    }
  }

  // 上書き保存 (Ctrl + S)
  Future<void> _saveFile() async {
    try {
      final path = await _controller.saveFile();
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.msgSaved(path)),
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

  // タブを閉じる処理（未保存チェック付き）
  Future<void> _handleCloseTab(int index) async {
    final doc = _controller.documents[index];
    if (doc.isDirty) {
      // 未保存の変更がある場合、ダイアログを表示
      final result = await showDialog<int>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('確認'),
            content: Text('${doc.displayName} への変更を保存しますか？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(0), // キャンセル
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(1), // 保存しない
                child: const Text('保存しない'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(2), // 保存する
                child: const Text('保存する'),
              ),
            ],
          );
        },
      );

      if (result == null || result == 0) {
        // キャンセル
        return;
      } else if (result == 1) {
        // 保存せずに閉じる
        _controller.closeTab(index);
      } else if (result == 2) {
        // 保存して閉じる
        final savedPath = await doc.saveFile();
        if (savedPath != null) {
          _controller.closeTab(index);
        }
      }
    } else {
      // 変更なし -> そのまま閉じる
      _controller.closeTab(index);
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
      _inputConnection?.show();
      print("IME接続開始！");
    }
  }

  void _updateImeWindowPosition() {
    final input = _inputConnection;
    final context = _painterKey.currentContext;

    if (input == null || !input.attached || context == null) {
      return;
    }

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final double safeCharWidth = _charWidth > 0 ? _charWidth : 16.0;
    final double safeLineHeight = _lineHeight > 0 ? _lineHeight : 24.0;

    final Matrix4 transform = renderBox.getTransformTo(null);
    input.setEditableSizeAndTransform(renderBox.size, transform);

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

    input.setComposingRect(
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
    // 水平スクロールバーと重ならないようにするための下部マージン
    // スクロールバーの高さ(約16px) + α として、2行分確保する
    final double bottomMargin = _lineHeight * 2;

    if (cursorY < currentScrollY) {
      _verticalScrollController.jumpTo(cursorY);
    } else if (cursorY + _lineHeight >
        currentScrollY + viewportHeight - bottomMargin) {
      // カーソル行がマージンの上に来るようにスクロール
      _verticalScrollController.jumpTo(
        cursorY + _lineHeight - viewportHeight + bottomMargin,
      );
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
    final s = AppLocalizations.of(context)!;

    return Card(
      elevation: 4.0,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: TextStyle(fontSize: _controller.grepFontSize),
                    decoration: InputDecoration(
                      labelText: s.labelSearch,
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
                const SizedBox(width: 8),
                // Regex
                FilterChip(
                  label: const Text('.*'),
                  tooltip: s.labelRegex,
                  selected: _controller.isRegex,
                  onSelected: (selected) {
                    _controller.toggleRegex();
                    _controller.search(_searchController.text);
                  },
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(2),
                  showCheckmark: false,
                ),
                const SizedBox(width: 4),
                // Case Sensitive
                FilterChip(
                  label: const Text('Aa'),
                  tooltip: s.labelCaseSensitive,
                  selected: _controller.isCaseSensitive,
                  onSelected: (selected) {
                    _controller.toggleCaseSensitive();
                    _controller.search(_searchController.text);
                  },
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(2),
                  showCheckmark: false,
                ),
                const SizedBox(width: 8),
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
                TextButton(
                  onPressed: () {
                    setState(() => _showGrepResults = true);
                    _controller.grep(_searchController.text);
                  },
                  child: Text(s.labelFindAll),
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
                      style: TextStyle(fontSize: _controller.grepFontSize),
                      decoration: InputDecoration(
                        labelText: s.labelReplace,
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
                    child: Text(s.labelReplace),
                  ),
                  TextButton(
                    onPressed: () {
                      _controller.replaceAll(
                        _searchController.text,
                        _replaceController.text,
                      );
                    },
                    child: Text(s.labelReplaceAll),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Grep結果パネルのビルド
  Widget _buildGrepResultsPanel() {
    if (!_showGrepResults || _controller.grepResults.isEmpty) {
      return const SizedBox.shrink();
    }
    final s = AppLocalizations.of(context)!;

    // コンテンツの最大幅を計算
    double maxContentWidth = 0.0;
    final double charW = _charWidth > 0 ? _charWidth : 10.0;

    // 全結果を走査して最大幅を求める (パフォーマンス注意だが要件優先)
    for (final result in _controller.grepResults) {
      // ファイル名部分の概算 + 行内容の幅
      String prefix =
          '${result.document.displayName}:${result.searchResult.lineIndex + 1}: ';
      int visualLength = TextUtils.calcTextWidth(prefix + result.line);
      double width = visualLength * charW + 20.0; // パディング分余裕を持たせる
      if (width > maxContentWidth) maxContentWidth = width;
    }

    return Container(
      height: _grepPanelHeight,
      decoration: BoxDecoration(color: Colors.grey.shade100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // リサイズハンドル
          MouseRegion(
            cursor: SystemMouseCursors.resizeRow,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragUpdate: (details) {
                setState(() {
                  // 上にドラッグ(マイナス)で高さを増やす
                  _grepPanelHeight -= details.delta.dy;
                  // 最小・最大サイズの制限
                  if (_grepPanelHeight < 100.0) _grepPanelHeight = 100.0;
                  final maxHeight = MediaQuery.of(context).size.height * 0.8;
                  if (_grepPanelHeight > maxHeight) {
                    _grepPanelHeight = maxHeight;
                  }
                });
              },
              child: Container(
                height: 8.0,
                color: Colors.grey.shade300,
                alignment: Alignment.center,
                child: Container(
                  width: 40,
                  height: 2,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade500,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          ),
          // パネルヘッダー
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.grey.shade200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${s.labelGrepResults} (${_controller.grepResults.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _showGrepResults = false),
                ),
              ],
            ),
          ),
          // 結果リスト
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final finalWidth = max(maxContentWidth, constraints.maxWidth);
                return Scrollbar(
                  controller: _grepScrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  // 縦スクロールバー: ListView(depth=1)の縦方向通知のみ拾う
                  notificationPredicate: (notif) =>
                      notif.depth == 1 && notif.metrics.axis == Axis.vertical,
                  child: Scrollbar(
                    controller: _grepHorizontalScrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    // 横スクロールバー: SingleChildScrollView(depth=0)の横方向通知のみ拾う
                    notificationPredicate: (notif) =>
                        notif.depth == 0 &&
                        notif.metrics.axis == Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: _grepHorizontalScrollController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: finalWidth,
                        height: constraints.maxHeight,
                        child: ListView.separated(
                          controller: _grepScrollController,
                          itemCount: _controller.grepResults.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final result = _controller.grepResults[index];
                            return _GrepResultRow(
                              result: result,
                              textStyle: _textStyle,
                              fontSize: _controller.grepFontSize,
                              onTap: () {
                                _controller.jumpToGrepResult(result);
                                _scrollToCursor();
                              },
                            );
                          },
                        ),
                      ),
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

  // タブバーの構築
  Widget _buildTabBar() {
    // タブフォント設定
    final tabTextStyle = TextStyle(
      fontFamily: _controller.tabFontFamily,
      fontSize: _controller.tabFontSize,
      fontWeight: _controller.tabBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: _controller.tabItalic ? FontStyle.italic : FontStyle.normal,
    );

    return Container(
      height: 32,
      color: Colors.grey.shade300,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _controller.documents.length,
              itemBuilder: (context, index) {
                final doc = _controller.documents[index];
                final isActive = index == _controller.activeDocumentIndex;
                final title = doc.displayName + (doc.isDirty ? ' *' : '');

                return InkWell(
                  onTap: () => _controller.switchTab(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    color: isActive ? Colors.white : Colors.grey.shade300,
                    child: Row(
                      children: [
                        Text(
                          title,
                          style: tabTextStyle.copyWith(
                            // アクティブなタブは太字にする（設定で既に太字なら太字のまま）
                            fontWeight: isActive ? FontWeight.bold : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _handleCloseTab(index),
                          child: const Icon(Icons.close, size: 16),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            onPressed: () => _controller.newTab(),
            tooltip: AppLocalizations.of(context)!.tooltipNewTab,
          ),
          IconButton(
            icon: const Icon(Icons.text_fields),
            onPressed: () => _controller.setMode(EditorMode.text),
            tooltip: 'Text Mode',
            color: _controller.currentMode == EditorMode.text
                ? Colors.blue
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.draw),
            onPressed: () {
              if (_controller.showDrawings) {
                _controller.setMode(EditorMode.draw);
              }
            },
            tooltip: 'Draw Mode',
            color: _controller.currentMode == EditorMode.draw
                ? Colors.blue
                : null,
          ),
          // --- Text Mode: ハンドル表示切替 ---
          if (_controller.currentMode == EditorMode.text)
            IconButton(
              icon: Icon(
                _controller.showAllHandles
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
              ),
              onPressed: () => _controller.toggleShowAllHandles(),
              tooltip: 'Show Handles',
            ),
          // --- Figure Mode: 削除ボタン ---
          if (_controller.currentMode == EditorMode.draw)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _controller.deleteSelectedDrawing(),
              tooltip: 'Delete Selected Drawing',
            ),
        ],
      ),
    );
  }

  // ミニマップの構築
  Widget _buildMinimap(double editorWidth, double editorHeight) {
    // 現在のビューポート情報
    double viewportOffsetY = 0;
    double viewportHeight = 0;
    double viewportOffsetX = 0;
    double viewportWidth = 0;

    if (_verticalScrollController.hasClients &&
        _horizontalScrollController.hasClients) {
      try {
        viewportOffsetY = _verticalScrollController.offset;
        viewportHeight = _verticalScrollController.position.viewportDimension;
        viewportOffsetX = _horizontalScrollController.offset;
        viewportWidth = _horizontalScrollController.position.viewportDimension;
      } catch (e) {
        // 取得失敗時は無視 (初期値0のまま)
      }
    }

    // エディタ全体のサイズ (docSize)
    Size docSize = Size(editorWidth, editorHeight);

    return Container(
      width: _minimapWidth,
      // 高さは親(Column -> Expanded -> Row)によって決まるため、指定しないかdouble.infinity
      height: double.infinity,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Colors.grey.shade300)),
        color: const Color(0xFFF5F5F5),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onTapDown: (details) => _handleMinimapInput(
              details.localPosition,
              constraints.maxHeight,
              docSize,
            ),
            onPanUpdate: (details) => _handleMinimapInput(
              details.localPosition,
              constraints.maxHeight,
              docSize,
            ),
            child: CustomPaint(
              size: Size(_minimapWidth, constraints.maxHeight),
              painter: MinimapPainter(
                lines: _controller.lines,
                docSize: docSize,
                viewportRect: Rect.fromLTWH(
                  viewportOffsetX,
                  viewportOffsetY,
                  viewportWidth,
                  viewportHeight,
                ),
                charWidth: _charWidth,
                lineHeight: _lineHeight,
                textStyle: _textStyle,
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleMinimapInput(
    Offset localPos,
    double minimapHeight,
    Size docSize,
  ) {
    if (!_verticalScrollController.hasClients ||
        !_horizontalScrollController.hasClients)
      return;

    // スケール計算 (Painterと同じロジック)
    double scaleX = _minimapWidth / docSize.width;
    double scaleY = minimapHeight / docSize.height;
    double scale = min(scaleX, scaleY);
    if (scale == 0) return;

    // クリック位置をドキュメント座標へ逆変換
    double targetEditorY = localPos.dy / scale;
    double targetEditorX = localPos.dx / scale;

    // ビューポートの中心に合わせる
    double viewportHeight = 0;
    double viewportWidth = 0;
    try {
      viewportHeight = _verticalScrollController.position.viewportDimension;
      viewportWidth = _horizontalScrollController.position.viewportDimension;
    } catch (e) {
      return;
    }

    double finalScrollY = targetEditorY - viewportHeight / 2;
    double finalScrollX = targetEditorX - viewportWidth / 2;

    // 範囲制限 (Y)
    double maxScrollY = _verticalScrollController.position.maxScrollExtent;
    if (finalScrollY < 0) finalScrollY = 0;
    if (finalScrollY > maxScrollY) finalScrollY = maxScrollY;

    // 範囲制限 (X)
    double maxScrollX = _horizontalScrollController.position.maxScrollExtent;
    if (finalScrollX < 0) finalScrollX = 0;
    if (finalScrollX > maxScrollX) finalScrollX = maxScrollX;

    _verticalScrollController.jumpTo(finalScrollY);
    _horizontalScrollController.jumpTo(finalScrollX);
  }

  // メニューバーの構築
  Widget _buildMenuBar() {
    // MenuBarも横幅いっぱいに広がろうとするため、Row(min)でラップして左寄せ・最小サイズにする
    final s = AppLocalizations.of(context)!;
    return Align(
      alignment: Alignment.centerLeft,
      child: MenuBar(
        children: [
          // File
          SubmenuButton(
            menuChildren: [
              MenuItemButton(
                onPressed: _openFile,
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyO,
                  control: true,
                ),
                child: MenuAcceleratorLabel(s.menuOpen),
              ),
              MenuItemButton(
                onPressed: _saveFile,
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyS,
                  control: true,
                ),
                child: MenuAcceleratorLabel(s.menuSave),
              ),
              MenuItemButton(
                onPressed: _saveAsFile,
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyS,
                  control: true,
                  shift: true,
                ),
                child: MenuAcceleratorLabel(s.menuSaveAs),
              ),
              const Divider(),
              MenuItemButton(
                onPressed: () async {
                  await windowManager.close();
                },
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.f4,
                  alt: true,
                ),
                child: MenuAcceleratorLabel(s.menuExit),
              ),
            ],
            child: MenuAcceleratorLabel(s.menuFile),
          ),
          // Edit
          SubmenuButton(
            menuChildren: [
              MenuItemButton(
                onPressed: _undo,
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyZ,
                  control: true,
                ),
                child: MenuAcceleratorLabel(s.menuUndo),
              ),
              MenuItemButton(
                onPressed: _redo,
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyY,
                  control: true,
                ),
                child: MenuAcceleratorLabel(s.menuRedo),
              ),
              const Divider(), // 区切り線
              MenuItemButton(
                onPressed: () => _controller.cutSelection(),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyX,
                  control: true,
                ),
                child: MenuAcceleratorLabel(s.menuCut),
              ),
              MenuItemButton(
                onPressed: () => _controller.copySelection(),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyC,
                  control: true,
                ),
                child: MenuAcceleratorLabel(s.menuCopy),
              ),
              MenuItemButton(
                onPressed: () => _controller.pasteNormal(),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyV,
                  control: true,
                ),
                child: MenuAcceleratorLabel(s.menuPaste),
              ),
              MenuItemButton(
                onPressed: () => _controller.pasteRectangular(),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyV,
                  control: true,
                  alt: true,
                ),
                child: MenuAcceleratorLabel(s.menuPasteRect),
              ),
              const Divider(),
              MenuItemButton(
                onPressed: () => _controller.trimTrailingWhitespace(),
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyD,
                  control: true,
                  alt: true,
                ),
                child: MenuAcceleratorLabel(s.menuTrimTrailingWhitespace),
              ),
              const Divider(),
              MenuItemButton(
                onPressed: () {
                  setState(() {
                    _showSearchBar = true;
                    _isReplaceMode = false;
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _searchFocusNode.requestFocus();
                  });
                },
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyF,
                  control: true,
                ),
                child: MenuAcceleratorLabel(s.menuFind),
              ),
              MenuItemButton(
                onPressed: () {
                  setState(() {
                    _showSearchBar = true;
                    _isReplaceMode = true;
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _searchFocusNode.requestFocus();
                  });
                },
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyH,
                  control: true,
                ),
                child: MenuAcceleratorLabel(s.menuReplace),
              ),
            ],
            child: MenuAcceleratorLabel(s.menuEdit),
          ),
          // Format
          SubmenuButton(
            menuChildren: [
              // 1. Box & Table
              SubmenuButton(
                menuChildren: [
                  MenuItemButton(
                    onPressed: () => _controller.drawBox(useHalfWidth: false),
                    child: MenuAcceleratorLabel(s.menuDrawBoxDouble),
                  ),
                  MenuItemButton(
                    onPressed: () => _controller.drawBox(useHalfWidth: true),
                    child: MenuAcceleratorLabel(s.menuDrawBoxSingle),
                  ),
                  const Divider(),
                  MenuItemButton(
                    onPressed: () => _controller.formatTable(useHalfWidth: false),
                    child: MenuAcceleratorLabel(s.menuFormatTableDouble),
                  ),
                  MenuItemButton(
                    onPressed: () => _controller.formatTable(useHalfWidth: true),
                    child: MenuAcceleratorLabel(s.menuFormatTableSingle),
                  ),
                ],
                child: MenuAcceleratorLabel(s.menuFormatBoxTable),
              ),
              // 2. Line & Arrow
              SubmenuButton(
                menuChildren: [
                  MenuItemButton(
                    onPressed: () => _controller.drawLine(useHalfWidth: false),
                    child: MenuAcceleratorLabel(s.menuDrawLineDouble),
                  ),
                  MenuItemButton(
                    onPressed: () => _controller.drawLine(useHalfWidth: true),
                    child: MenuAcceleratorLabel(s.menuDrawLineSingle),
                  ),
                  const Divider(),
                  MenuItemButton(
                    onPressed: () =>
                        _controller.drawLine(useHalfWidth: false, arrowEnd: true),
                    child: MenuAcceleratorLabel(s.menuArrowEndDouble),
                  ),
                  MenuItemButton(
                    onPressed: () =>
                        _controller.drawLine(useHalfWidth: true, arrowEnd: true),
                    child: MenuAcceleratorLabel(s.menuArrowEndSingle),
                  ),
                  MenuItemButton(
                    onPressed: () => _controller.drawLine(
                      useHalfWidth: false,
                      arrowStart: true,
                      arrowEnd: true,
                    ),
                    child: MenuAcceleratorLabel(s.menuArrowBothDouble),
                  ),
                  MenuItemButton(
                    onPressed: () => _controller.drawLine(
                      useHalfWidth: true,
                      arrowStart: true,
                      arrowEnd: true,
                    ),
                    child: MenuAcceleratorLabel(s.menuArrowBothSingle),
                  ),
                ],
                child: MenuAcceleratorLabel(s.menuFormatLineArrow),
              ),
              // 3. Elbow Line
              SubmenuButton(
                menuChildren: [
                  MenuItemButton(
                    onPressed: () => _controller.drawElbowLine(
                      isUpperRoute: true,
                      useHalfWidth: false,
                      arrowEnd: true,
                    ),
                    child: MenuAcceleratorLabel(s.menuElbowUpperDouble),
                  ),
                  MenuItemButton(
                    onPressed: () => _controller.drawElbowLine(
                      isUpperRoute: true,
                      useHalfWidth: true,
                      arrowEnd: true,
                    ),
                    child: MenuAcceleratorLabel(s.menuElbowUpperSingle),
                  ),
                  MenuItemButton(
                    onPressed: () => _controller.drawElbowLine(
                      isUpperRoute: false,
                      useHalfWidth: false,
                      arrowEnd: true,
                    ),
                    child: MenuAcceleratorLabel(s.menuElbowLowerDouble),
                  ),
                  MenuItemButton(
                    onPressed: () => _controller.drawElbowLine(
                      isUpperRoute: false,
                      useHalfWidth: true,
                      arrowEnd: true,
                    ),
                    child: MenuAcceleratorLabel(s.menuElbowLowerSingle),
                  ),
                ],
                child: MenuAcceleratorLabel(s.menuFormatElbow),
              ),
            ],
            child: MenuAcceleratorLabel(s.menuFormat),
          ),
          // View
          SubmenuButton(
            menuChildren: [
              MenuItemButton(
                onPressed: () => _controller.toggleGrid(),
                child: Row(
                  children: [
                    Icon(
                      _controller.showGrid
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(s.menuShowGrid),
                  ],
                ),
              ),
              MenuItemButton(
                onPressed: () => _controller.toggleLineNumber(),
                child: Row(
                  children: [
                    Icon(
                      _controller.showLineNumber
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(s.menuShowLineNumbers),
                  ],
                ),
              ),
              MenuItemButton(
                onPressed: () => _controller.toggleRuler(),
                child: Row(
                  children: [
                    Icon(
                      _controller.showRuler
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(s.menuShowRuler),
                  ],
                ),
              ),
              MenuItemButton(
                onPressed: () => _controller.toggleMinimap(),
                child: Row(
                  children: [
                    Icon(
                      _controller.showMinimap
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(s.menuShowMinimap),
                  ],
                ),
              ),
              MenuItemButton(
                onPressed: () => _controller.toggleShowDrawings(),
                child: Row(
                  children: [
                    Icon(
                      _controller.showDrawings
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(s.menuShowDrawings),
                  ],
                ),
              ),
            ],
            child: MenuAcceleratorLabel(s.menuView),
          ),
          // Settings (最上位)
          SubmenuButton(
            menuChildren: [
              MenuItemButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => SettingsDialog(
                      controller: _controller,
                      initialTab: SettingsTab.textEditor,
                    ),
                  );
                },
                child: MenuAcceleratorLabel(s.menuSettingsEditor),
              ),
              MenuItemButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => SettingsDialog(
                      controller: _controller,
                      initialTab: SettingsTab.interface,
                    ),
                  );
                },
                child: MenuAcceleratorLabel(s.menuSettingsUi),
              ),
              MenuItemButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => SettingsDialog(
                      controller: _controller,
                      initialTab: SettingsTab.general,
                    ),
                  );
                },
                child: MenuAcceleratorLabel(s.menuSettingsGeneral),
              ),
            ],
            child: MenuAcceleratorLabel(s.menuSettings),
          ),
          // Help
          SubmenuButton(
            menuChildren: [
              MenuItemButton(
                onPressed: () async => await _controller.openHelpTab(),
                child: MenuAcceleratorLabel(s.menuHelpUsage),
              ),
              MenuItemButton(
                onPressed: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'Free-form Memo',
                    applicationVersion: '1.0.0',
                  );
                },
                child: MenuAcceleratorLabel(s.menuAbout),
              ),
            ],
            child: MenuAcceleratorLabel(s.menuHelp),
          ),
        ],
      ),
    );
  }

  // ツールバーの構築 (旧AppBarの内容)
  Widget _buildToolbar() {
    final s = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisSize: MainAxisSize.min, // 中身のサイズに合わせる
        children: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _openFile,
            tooltip: s.menuOpen,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveFile,
            tooltip: '${s.menuSave} (Ctrl+S)',
          ),
          IconButton(
            icon: const Icon(Icons.save_as),
            onPressed: _saveAsFile,
            tooltip: '${s.menuSaveAs} (Ctrl+Shift+S)',
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: Icon(_controller.showGrid ? Icons.grid_on : Icons.grid_off),
            onPressed: () {
              _controller.toggleGrid();
            },
            tooltip: s.menuShowGrid,
          ),
          IconButton(
            icon: Icon(
              _controller.showDrawings ? Icons.visibility : Icons.visibility_off,
            ),
            onPressed: () => _controller.toggleShowDrawings(),
            tooltip: s.menuShowDrawings,
          ),
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
            tooltip: s.tooltipDrawingList,
          ),
          PopupMenuButton<int>(
            tooltip: s.tooltipTabWidth,
            icon: const Icon(Icons.space_bar),
            onSelected: (value) {
              _controller.setTabWidth(value);
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                checked: _controller.tabWidth == 2,
                value: 2,
                child: Text(s.labelTabWidthItem('2')),
              ),
              CheckedPopupMenuItem(
                checked: _controller.tabWidth == 4,
                value: 4,
                child: Text(s.labelTabWidthItem('4')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showColorPickerDialog() {
    final s = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: _controller,
        builder: (context, child) {
          return AlertDialog(
            title: Text(s.titleSelectColor),
            content: SizedBox(
              width: 340, // 幅を少し広げる
              child: ColorPickerWidget(
                initialColor: _controller.currentDrawingColor,
                onColorChanged: (color) {
                  _controller.setDrawingStyle(color: color);
                },
                savedColors: _controller.savedColors
                    .map((e) => Color(e))
                    .toList(),
                onSaveColor: (color) => _controller.addSavedColor(color.value),
                onDeleteColor: (color) =>
                    _controller.removeSavedColor(color.value),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(s.btnClose),
              ),
            ],
          );
        },
      ),
    );
  }

  // プロパティ入力値の同期
  void _syncPropertyInputs() {
    if (!mounted) return;

    // Width
    if (!_widthFocus.hasFocus) {
      String newText = (_controller.currentShapeType == DrawingType.marker)
          ? (_controller.currentMarkerHeight * 100).toStringAsFixed(0)
          : _controller.currentStrokeWidth.toStringAsFixed(1);
      if (_widthController.text != newText) {
        _widthController.text = newText;
      }
    }

    // Padding X
    if (!_paddingXFocus.hasFocus) {
      String newText = _controller.shapePaddingX.toString();
      if (_paddingXController.text != newText) {
        _paddingXController.text = newText;
      }
    }

    // Padding Y
    if (!_paddingYFocus.hasFocus) {
      String newText = _controller.shapePaddingY.toStringAsFixed(1);
      if (_paddingYController.text != newText) {
        _paddingYController.text = newText;
      }
    }

    // Table Rows/Cols
    if (_controller.currentShapeType == DrawingType.table) {
      int rows = 3;
      int cols = 3;

      if (_controller.selectedDrawingId != null) {
        final drawing = _controller.activeDocument
            .getDrawing(_controller.selectedDrawingId!);
        rows = drawing.tableRowPositions.length + 1;
        cols = drawing.tableColPositions.length + 1;
      } else {
        // 未選択時はデフォルト値
        rows = _controller.currentAttributes.tableRows;
        cols = _controller.currentAttributes.tableCols;
      }
      
      if (!_rowsFocus.hasFocus) {
        String newRows = rows.toString();
        if (_rowsController.text != newRows) {
          _rowsController.text = newRows;
        }
      }
      if (!_colsFocus.hasFocus) {
        String newCols = cols.toString();
        if (_colsController.text != newCols) {
          _colsController.text = newCols;
        }
      }
    }
  }

  // 図形一覧ドロワーの構築
  Widget _buildDrawingListDrawer() {
    final s = AppLocalizations.of(context)!;
    
    // フィルタリング
    List<DrawingObject> drawings = _controller.drawings;
    if (_drawingListFilter != null) {
      drawings = drawings.where((d) => d.type == _drawingListFilter).toList();
    }
    // 範囲選択による絞り込み
    if (_controller.filteredDrawingIds != null) {
      drawings = drawings.where((d) => _controller.filteredDrawingIds!.contains(d.id)).toList();
    }
    // 新しい順に並べ替え
    final reversedDrawings = drawings.reversed.toList();

    return Drawer(
      width: 300,
      child: Column(
        children: [
          // ヘッダー
          Container(
            height: kToolbarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  s.titleDrawingList,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          // フィルタ & 範囲選択
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                const Icon(Icons.filter_list, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<DrawingType?>(
                    isExpanded: true,
                    isDense: true,
                    value: _drawingListFilter,
                    hint: Text(s.labelAllTypes, style: const TextStyle(fontSize: 12)),
                    underline: Container(),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(s.labelAllTypes, style: const TextStyle(fontSize: 12)),
                      ),
                      ...DrawingType.values.map((type) {
                        String label;
                        IconData icon;
                        switch (type) {
                          case DrawingType.line: label = s.typeLine; icon = Icons.show_chart; break;
                          case DrawingType.elbow: label = s.typeElbow; icon = Icons.turn_right; break;
                          case DrawingType.rectangle: label = s.typeRectangle; icon = Icons.crop_square; break;
                          case DrawingType.roundedRectangle: label = s.typeRoundedRect; icon = Icons.rounded_corner; break;
                          case DrawingType.oval: label = s.typeOval; icon = Icons.circle_outlined; break;
                          case DrawingType.burst: label = s.typeBurst; icon = Icons.new_releases; break;
                          case DrawingType.marker: label = s.typeMarker; icon = Icons.format_paint; break;
                          case DrawingType.image: label = s.typeImage; icon = Icons.image; break;
                          case DrawingType.table: label = s.typeTable; icon = Icons.grid_4x4; break;
                        }
                        return DropdownMenuItem(
                          value: type,
                          child: Row(children: [
                            Icon(icon, size: 16, color: Colors.black54),
                            const SizedBox(width: 8),
                            Text(label, style: const TextStyle(fontSize: 12)),
                          ]),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _drawingListFilter = val;
                        _controller.setHighlightedDrawingType(val);
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          // 範囲選択ボタン
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: Colors.grey.shade100,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.select_all, size: 16),
              label: Text(s.btnSelectAreaFilter, style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () {
                Navigator.of(context).pop(); // ドロワーを閉じる
                _controller.startAreaSelectionMode(); // 範囲選択モード開始
              },
            ),
          ),
          const Divider(height: 1),
          // リスト
          Expanded(
            child: reversedDrawings.isEmpty
                ? Center(child: Text(s.msgNoDrawings))
                : ListView.separated(
                    itemCount: reversedDrawings.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final drawing = reversedDrawings[index];
                      final isSelected =
                          drawing.id == _controller.selectedDrawingId;

                      IconData icon;
                      String label;
                      switch (drawing.type) {
                        case DrawingType.line:
                          icon = Icons.show_chart;
                          label = s.typeLine;
                          break;
                        case DrawingType.elbow:
                          icon = Icons.turn_right;
                          label = s.typeElbow;
                          break;
                        case DrawingType.rectangle:
                          icon = Icons.crop_square;
                          label = s.typeRectangle;
                          break;
                        case DrawingType.roundedRectangle:
                          icon = Icons.rounded_corner;
                          label = s.typeRoundedRect;
                          break;
                        case DrawingType.oval:
                          icon = Icons.circle_outlined;
                          label = s.typeOval;
                          break;
                        case DrawingType.burst:
                          icon = Icons.new_releases;
                          label = s.typeBurst;
                          break;
                        case DrawingType.marker:
                          icon = Icons.format_paint;
                          label = s.typeMarker;
                          break;
                        case DrawingType.image:
                          icon = Icons.image;
                          label = s.typeImage;
                          break;
                        case DrawingType.table:
                          icon = Icons.grid_4x4;
                          label = s.typeTable;
                          break;
                        default:
                          icon = Icons.edit;
                          label = 'Drawing';
                      }

                      return MouseRegion(
                        onEnter: (_) => _controller.setHighlightedDrawing(drawing.id),
                        onExit: (_) => _controller.setHighlightedDrawing(null),
                        child: ListTile(
                          dense: true,
                          visualDensity: const VisualDensity(vertical: -4),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          minLeadingWidth: 20,
                          horizontalTitleGap: 8,
                          leading: Icon(icon, size: 16),
                          title: Row(
                            children: [
                              Text(label, style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 8),
                              Text(
                                'R:${drawing.points.first.row} C:${drawing.points.first.col}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                          selected: isSelected,
                          selectedTileColor: Colors.blue.withOpacity(0.1),
                          onTap: () => _jumpToDrawing(drawing),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, size: 16, color: Colors.grey),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            onPressed: () => _controller.deleteDrawing(drawing.id),
                            tooltip: s.tooltipDelete,
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

  // 図形へのジャンプ処理
  void _jumpToDrawing(DrawingObject drawing) {
    // 1. 図形を選択状態にする
    _controller.selectDrawing(drawing.id);
    // Drawモードに切り替え
    if (_controller.currentMode != EditorMode.draw) {
      _controller.setMode(EditorMode.draw);
    }

    // 2. 座標計算 (簡易的に始点を使用)
    if (drawing.points.isNotEmpty) {
      final p = drawing.points.first;
      double y = p.row * _lineHeight;
      // 文字列幅の計算はコストがかかるので、簡易的に文字数 * 平均幅で推定するか、
      // 正確に計算するか。ここでは正確さを優先して計算する。
      String line = "";
      if (p.row < _controller.lines.length) {
        line = _controller.lines[p.row];
      }
      String textBefore = "";
      if (p.col <= line.length) {
        textBefore = line.substring(0, p.col);
      } else {
        textBefore = line + (' ' * (p.col - line.length));
      }
      double x = TextUtils.calcTextWidth(textBefore) * _charWidth;

      // 3. スクロール (画面中央に来るように)
      if (_verticalScrollController.hasClients) {
        double viewportH = _verticalScrollController.position.viewportDimension;
        double targetY = max(0.0, y - viewportH / 2);
        _verticalScrollController.jumpTo(targetY);
      }
      if (_horizontalScrollController.hasClients) {
        double viewportW = _horizontalScrollController.position.viewportDimension;
        double targetX = max(0.0, x - viewportW / 2);
        _horizontalScrollController.jumpTo(targetX);
      }
    }

    // ドロワーを閉じる（お好みで）
    // Navigator.of(context).pop(); 
  }

  void _commitWidth() {
    final val = double.tryParse(_widthController.text);
    if (val != null) {
      if (_controller.currentShapeType == DrawingType.marker) {
        _controller.setDrawingStyle(markerHeight: (val / 100.0).clamp(0.0, 1.0));
      } else {
        if (val > 0) _controller.setDrawingStyle(strokeWidth: val);
      }
    } else {
      _syncPropertyInputs(); // 不正な値なら元に戻す
    }
  }

  void _commitPadding() {
    final x = int.tryParse(_paddingXController.text);
    final y = double.tryParse(_paddingYController.text);

    // どちらか一方でも有効な値があれば更新する
    if (x != null || y != null) {
      final newX = x ?? _controller.shapePaddingX;
      final newY = y ?? _controller.shapePaddingY;
      _controller.setShapePadding(newX, newY);
    } else {
      // 両方無効なら元の値に戻す
      // _syncPropertyInputsはフォーカスがあると更新しないため、ここで強制的に戻す
      _paddingXController.text = _controller.shapePaddingX.toString();
      _paddingYController.text = _controller.shapePaddingY.toStringAsFixed(1);
    }
  }

  void _commitTableGrid() {
    final rows = int.tryParse(_rowsController.text);
    final cols = int.tryParse(_colsController.text);

    if (rows != null && cols != null && rows > 0 && cols > 0) {
      _controller.setTableGrid(rows, cols);
    }
  }

  // プロパティバーの構築 (Draw Mode用)
  Widget _buildPropertyBar() {
    if (_controller.currentMode != EditorMode.draw) {
      return const SizedBox.shrink();
    }

    final s = AppLocalizations.of(context)!;
    final type = _controller.currentShapeType;
    final isLineFamily = type == DrawingType.line || type == DrawingType.elbow;
    final isRectFamily =
        type == DrawingType.rectangle ||
        type == DrawingType.roundedRectangle ||
        type == DrawingType.oval ||
        type == DrawingType.burst;
    final isMarker = type == DrawingType.marker;
    final isTable = type == DrawingType.table;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.grey.shade200,
      child: Row(
        children: [
          Text('${s.labelShape}:', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          PopupMenuButton<DrawingType>(
            tooltip: s.tooltipShapeType,
            icon: Icon(
              _controller.currentShapeType == DrawingType.line
                  ? Icons
                        .show_chart // 直線 (仮)
                  : _controller.currentShapeType == DrawingType.elbow
                  ? Icons
                        .turn_right // L型
                  : _controller.currentShapeType == DrawingType.marker
                  ? Icons.format_paint
                  : _controller.currentShapeType == DrawingType.rectangle
                  ? Icons.crop_square
                  : _controller.currentShapeType == DrawingType.roundedRectangle
                  ? Icons.rounded_corner 
                  : _controller.currentShapeType == DrawingType.burst
                  ? Icons.new_releases 
                  : _controller.currentShapeType == DrawingType.image
                  ? Icons.image
                  : _controller.currentShapeType == DrawingType.table
                  ? Icons.grid_4x4
                  : Icons.circle_outlined,
              size: 18,
            ),
            onSelected: (type) => _controller.setShapeType(type),
            itemBuilder: (context) {
              // 選択中は同系列のみ表示
              if (_controller.selectedDrawingId != null) {
                if (isLineFamily) {
                  return [
                    PopupMenuItem(
                      value: DrawingType.line,
                      child: Row(children: [
                        const Icon(Icons.show_chart, color: Colors.black54),
                        const SizedBox(width: 8),
                        Text(s.typeLine),
                      ]),
                    ),
                    PopupMenuItem(
                      value: DrawingType.elbow,
                      child: Row(children: [
                        const Icon(Icons.turn_right, color: Colors.black54),
                        const SizedBox(width: 8),
                        Text(s.typeElbow),
                      ]),
                    ),
                  ];
                } else if (isRectFamily) {
                  return [
                    PopupMenuItem(
                      value: DrawingType.rectangle,
                      child: Row(children: [
                        const Icon(Icons.crop_square, color: Colors.black54),
                        const SizedBox(width: 8),
                        Text(s.typeRectangle),
                      ]),
                    ),
                    PopupMenuItem(
                      value: DrawingType.roundedRectangle,
                      child: Row(children: [
                        const Icon(Icons.rounded_corner, color: Colors.black54),
                        const SizedBox(width: 8),
                        Text(s.typeRoundedRect),
                      ]),
                    ),
                    PopupMenuItem(
                      value: DrawingType.oval,
                      child: Row(children: [
                        const Icon(Icons.circle_outlined, color: Colors.black54),
                        const SizedBox(width: 8),
                        Text(s.typeOval),
                      ]),
                    ),
                    PopupMenuItem(
                      value: DrawingType.burst,
                      child: Row(children: [
                        const Icon(Icons.new_releases, color: Colors.black54),
                        const SizedBox(width: 8),
                        Text(s.typeBurst),
                      ]),
                    ),
                  ];
                } else if (_controller.currentShapeType == DrawingType.image) {
                  return [
                    PopupMenuItem(
                      value: DrawingType.image,
                      child: Row(children: [
                        const Icon(Icons.image, color: Colors.black54),
                        const SizedBox(width: 8),
                        Text(s.typeImage),
                      ]),
                    ),
                    PopupMenuItem(
                      value: DrawingType.table,
                      child: Row(children: [
                        const Icon(Icons.grid_4x4, color: Colors.black54),
                        const SizedBox(width: 8),
                        Text(s.typeTable),
                      ]),
                    ),
                  ];
                } else {
                  return [
                    PopupMenuItem(
                      value: DrawingType.marker,
                      child: Row(children: [
                        const Icon(Icons.format_paint, color: Colors.black54),
                        const SizedBox(width: 8),
                        Text(s.typeMarker),
                      ]),
                    ),
                  ];
                }
              }
              return [
                PopupMenuItem(
                  value: DrawingType.line,
                  child: Row(children: [
                    const Icon(Icons.show_chart, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(s.typeLine),
                  ]),
                ),
                PopupMenuItem(
                  value: DrawingType.elbow,
                  child: Row(children: [
                    const Icon(Icons.turn_right, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(s.typeElbow),
                  ]),
                ),
                PopupMenuItem(
                  value: DrawingType.marker,
                  child: Row(children: [
                    const Icon(Icons.format_paint, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(s.typeMarker),
                  ]),
                ),
                PopupMenuItem(
                  value: DrawingType.rectangle,
                  child: Row(children: [
                    const Icon(Icons.crop_square, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(s.typeRectangle),
                  ]),
                ),
                PopupMenuItem(
                  value: DrawingType.roundedRectangle,
                  child: Row(children: [
                    const Icon(Icons.rounded_corner, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(s.typeRoundedRect),
                  ]),
                ),
                PopupMenuItem(
                  value: DrawingType.oval,
                  child: Row(children: [
                    const Icon(Icons.circle_outlined, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(s.typeOval),
                  ]),
                ),
                PopupMenuItem(
                  value: DrawingType.burst,
                  child: Row(children: [
                    const Icon(Icons.new_releases, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(s.typeBurst),
                  ]),
                ),
                PopupMenuItem(
                  value: DrawingType.image,
                  child: Row(children: [
                    const Icon(Icons.image, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(s.typeImage),
                  ]),
                ),
                PopupMenuItem(
                  value: DrawingType.table,
                  child: Row(children: [
                    const Icon(Icons.grid_4x4, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(s.typeTable),
                  ]),
                ),
              ];
            },
          ),
          const SizedBox(width: 16),
          Text('${s.labelColor}:', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showColorPickerDialog,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _controller.currentDrawingColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // --- Table Settings ---
          if (isTable) ...[
            Text('${s.labelRows}:', style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            SizedBox(
              width: 40,
              child: TextField(
                controller: _rowsController,
                focusNode: _rowsFocus,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _commitTableGrid(),
              ),
            ),
            const SizedBox(width: 8),
            Text('${s.labelCols}:', style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            SizedBox(
              width: 40,
              child: TextField(
                controller: _colsController,
                focusNode: _colsFocus,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _commitTableGrid(),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Text(
            _controller.currentShapeType == DrawingType.marker
                ? '${s.labelHeight}:'
                : '${s.labelWidth}:',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 50,
            child: TextField(
              controller: _widthController,
              focusNode: _widthFocus,
              enabled: !isLineFamily,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 4,
                ),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _commitWidth(),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _controller.currentShapeType == DrawingType.marker ? '%' : 'px',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(width: 16),
          Text('${s.labelPaddingX}:', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          SizedBox(
            width: 40,
            child: TextField(
              controller: _paddingXController,
              focusNode: _paddingXFocus,
              enabled: !isLineFamily,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 4,
                ),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _commitPadding(),
            ),
          ),
          const SizedBox(width: 8),
          Text('${s.labelPaddingY}:', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          SizedBox(
            width: 40,
            child: TextField(
              controller: _paddingYController,
              focusNode: _paddingYFocus,
              enabled: !isLineFamily && !isMarker,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 4,
                ),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _commitPadding(),
            ),
          ),
          const SizedBox(width: 16),
          Text('${s.labelStyle}:', style: const TextStyle(fontSize: 12)),
          PopupMenuButton<LineStyle>(
            enabled: !isMarker,
            tooltip: s.tooltipLineStyle,
            icon: Icon(
              _controller.currentLineStyle == LineStyle.solid
                  ? Icons.remove
                  : _controller.currentLineStyle == LineStyle.dotted
                  ? Icons.more_horiz
                  : _controller.currentLineStyle == LineStyle.dashed
                  ? Icons.power_input
                  : Icons.drag_handle, // Double
              size: 18,
              color: isMarker ? Colors.grey : null,
            ),
            onSelected: (style) =>
                _controller.setDrawingStyle(lineStyle: style),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: LineStyle.solid,
                child: Row(children: [
                  const Icon(Icons.remove, color: Colors.black54),
                  const SizedBox(width: 8),
                  Text(s.styleSolid),
                ]),
              ),
              PopupMenuItem(
                value: LineStyle.dotted,
                child: Row(children: [
                  const Icon(Icons.more_horiz, color: Colors.black54),
                  const SizedBox(width: 8),
                  Text(s.styleDotted),
                ]),
              ),
              PopupMenuItem(
                value: LineStyle.dashed,
                child: Row(children: [
                  const Icon(Icons.power_input, color: Colors.black54),
                  const SizedBox(width: 8),
                  Text(s.styleDashed),
                ]),
              ),
              PopupMenuItem(
                value: LineStyle.doubleLine,
                child: Row(children: [
                  const Icon(Icons.drag_handle, color: Colors.black54),
                  const SizedBox(width: 8),
                  Text(s.styleDouble),
                ]),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // 矢印設定 (始点)
          IconButton(
            icon: Icon(
              Icons.west,
              size: 18,
              color: isLineFamily
                  ? (_controller.currentArrowStart ? Colors.blue : Colors.grey)
                  : Colors.grey.withOpacity(0.3),
            ),
            onPressed: isLineFamily
                ? () => _controller.setDrawingStyle(
                    arrowStart: !_controller.currentArrowStart,
                  )
                : null,
            tooltip: s.tooltipStartArrow,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          // 矢印設定 (終点)
          IconButton(
            icon: Icon(
              Icons.east,
              size: 18,
              color: isLineFamily
                  ? (_controller.currentArrowEnd ? Colors.blue : Colors.grey)
                  : Colors.grey.withOpacity(0.3),
            ),
            onPressed: isLineFamily
                ? () => _controller.setDrawingStyle(
                    arrowEnd: !_controller.currentArrowEnd,
                  )
                : null,
            tooltip: s.tooltipEndArrow,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          // L字線のルート切り替え
          if (type == DrawingType.elbow)
            IconButton(
              icon: Icon(
                _controller.currentIsUpperRoute
                    ? Icons.vertical_align_top
                    : Icons.vertical_align_bottom,
                size: 18,
              ),
              onPressed: () => _controller.setDrawingStyle(
                isUpperRoute: !_controller.currentIsUpperRoute,
              ),
              tooltip: _controller.currentIsUpperRoute ? s.tooltipRouteUpper : s.tooltipRouteLower,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),

          // デフォルト設定ボタン (図形選択時のみ表示)
          if (_controller.selectedDrawingId != null) ...[
            const SizedBox(width: 8),
            Container(width: 1, height: 20, color: Colors.grey.shade400),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.save_as, size: 18),
              onPressed: () {
                _controller.setSelectionAsDefault();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(s.msgSetDefault),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              tooltip: s.tooltipSetDefault,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // UIフォント設定
    final uiFontStyle = TextStyle(
      fontFamily: _controller.uiFontFamily,
      fontSize: _controller.uiFontSize,
      fontWeight: _controller.uiBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: _controller.uiItalic ? FontStyle.italic : FontStyle.normal,
    );

    // UIフォント設定を適用するためのThemeラッパー
    return Theme(
      data: Theme.of(context).copyWith(
        // 念のためTextThemeも上書き
        textTheme: Theme.of(
          context,
        ).textTheme.copyWith(labelLarge: uiFontStyle),
        // メニューボタンのテーマ (ドロップダウン項目用)
        menuButtonTheme: MenuButtonThemeData(
          style: ButtonStyle(
            textStyle: WidgetStateProperty.all(uiFontStyle),
            // 文字色も明示的に指定して適用を確実にする
            foregroundColor: WidgetStateProperty.all(Colors.black87),
            // アイコンサイズもフォントサイズに合わせて調整
            iconSize: WidgetStateProperty.all(_controller.uiFontSize + 4),
          ),
        ),
      ),
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
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

    // 2. 図形の最大範囲を計算
    double maxDrawingX = 0;
    double maxDrawingY = 0;

    for (final drawing in _controller.drawings) {
      for (final point in drawing.points) {
        // Y座標の計算
        double y = (point.row + point.dy) * _lineHeight;
        if (y > maxDrawingY) maxDrawingY = y;

        // X座標の計算 (行テキストを考慮)
        String line = "";
        if (point.row < _controller.lines.length) {
          line = _controller.lines[point.row];
        }
        String textBefore = "";
        if (point.col <= line.length) {
          textBefore = line.substring(0, point.col);
        } else {
          textBefore = line + (' ' * (point.col - line.length));
        }
        double x = (TextUtils.calcTextWidth(textBefore) + point.dx) * _charWidth;
        if (x > maxDrawingX) maxDrawingX = x;
      }
      // パディング分を考慮して少し広げる
      if (drawing.paddingX > 0 || drawing.paddingY > 0) {
        maxDrawingX += drawing.paddingX * _charWidth;
        maxDrawingY += drawing.paddingY * _lineHeight;
      }
    }

    // 3. エディタ領域のサイズ決定 (テキストと図形の両方を包含し、画面サイズ以上の余白を持たせる)
    Size screenSize = MediaQuery.of(context).size;
    double minCanvasWidth = _controller.minColumns * _charWidth;
    double minCanvasHeight = _controller.minLines * _lineHeight;

    double editorWidth = max(
      minCanvasWidth,
      max(textContentWidth, maxDrawingX) + screenSize.width / 2,
    );
    double editorHeight = max(
      minCanvasHeight,
      max(textContentHeight, maxDrawingY) + screenSize.height / 2,
    );

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _buildDrawingListDrawer(),
      drawerScrimColor: Colors.transparent, // 背景を暗くしない
      onEndDrawerChanged: (isOpened) {
        if (!isOpened) {
          _controller.resetDrawerHighlights();
        }
      },
      // appBar: AppBar(...), // 削除
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start, // 左寄せ
        children: [
          _buildMenuBar(), // メニューバー
          _buildToolbar(), // ツールバー
          _buildPropertyBar(), // プロパティバー (新規追加)
          _buildTabBar(), // タブバー
          if (_showGrepResults) const Divider(height: 1),
          // --- 列ルーラーエリア ---
          if (_controller.showRuler)
            Container(
              key: const Key('rulerArea'),
              height: 24,
              color: Colors.grey.shade200,
              child: Row(
                children: [
                  // 行番号エリアの上部（空白）
                  SizedBox(width: lineNumberAreaWidth),
                  // ルーラー本体
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _rulerScrollController,
                      scrollDirection: Axis.horizontal,
                      child: CustomPaint(
                        size: Size(editorWidth, 24),
                        painter: ColumnRulerPainter(
                          charWidth: _charWidth,
                          lineHeight: 24, // ルーラーの高さ固定
                          textStyle: _lineNumberStyle.copyWith(
                            // ルーラー用の設定を適用
                            fontSize: _controller.rulerFontSize,
                            color: Color(_controller.rulerColor),
                          ),
                          editorWidth: editorWidth,
                        ),
                      ),
                    ),
                  ),
                  // ミニマップの幅分だけ余白を空ける（レイアウト合わせ）
                  Container(width: _minimapWidth, color: Colors.grey.shade200),
                ],
              ),
            ),
          // --- エディタ本体 ---
          Expanded(
            child: Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // メインエリア (行番号 + エディタ)
                    Expanded(
                      child: Stack(
                        children: [
                          // 1. コンテンツ (垂直スクロール + 水平スクロール)
                          Scrollbar(
                            controller: _verticalScrollController,
                            thumbVisibility: true,
                            trackVisibility: true,
                            child: SingleChildScrollView(
                              controller: _verticalScrollController,
                              scrollDirection: Axis.vertical,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 行番号エリア
                                  if (_controller.showLineNumber)
                                    Container(
                                      key: const Key('lineNumberArea'),
                                      width: lineNumberAreaWidth,
                                      height: editorHeight,
                                      color: Colors.grey.shade200,
                                      child: CustomPaint(
                                        size: Size(
                                          lineNumberAreaWidth,
                                          editorHeight,
                                        ),
                                        painter: LineNumberPainter(
                                          lineCount: _controller.lines.length,
                                          lineHeight: _lineHeight,
                                          textStyle: _lineNumberStyle,
                                        ),
                                      ),
                                    ),
                                  // エディタエリア
                                  Expanded(
                                    child: Focus(
                                      focusNode: _focusNode,
                                      onKeyEvent:
                                          (FocusNode node, KeyEvent event) {
                                            final result = _handleKeyPress(
                                              event,
                                            );
                                            return result;
                                          },
                                      child: SingleChildScrollView(
                                        controller: _horizontalScrollController,
                                        scrollDirection: Axis.horizontal,
                                        child: MouseRegion(
                                          cursor: _currentMouseCursor,
                                          onHover: _handleHover,
                                          child: GestureDetector(
                                            onTapDown: (details) {
                                              _resetCursorBlink();

                                              bool isControl = HardwareKeyboard.instance.isControlPressed ||
                                                  HardwareKeyboard.instance.isMetaPressed;

                                              if (_controller.currentMode ==
                                                  EditorMode.draw) {
                                                // Figureモード: 図形選択のみ
                                                if (!isControl) {
                                                  _controller.trySelectDrawing(
                                                    details.localPosition,
                                                    _charWidth,
                                                    _lineHeight,
                                                  );
                                                } else {
                                                  _controller.clearDrawingSelection();
                                                }
                                              } else {
                                                // Textモード: テキスト移動のみ
                                                _controller.clearSelection();
                                                _controller.handleTap(
                                                  details.localPosition,
                                                  _charWidth,
                                                  _lineHeight,
                                                );
                                              }

                                              _focusNode.requestFocus();
                                              WidgetsBinding.instance
                                                  .addPostFrameCallback((_) {
                                                    _updateImeWindowPosition();
                                                  });
                                            },
                                            onPanStart: (details) {
                                              _resetCursorBlink();

                                              // 範囲選択モード (フィルタ用)
                                              if (_controller.isAreaSelectionMode) {
                                                _controller.updateAreaSelection(
                                                  details.localPosition,
                                                  details.localPosition,
                                                );
                                                return;
                                              }

                                              bool isControl = HardwareKeyboard.instance.isControlPressed ||
                                                  HardwareKeyboard.instance.isMetaPressed;

                                              if (_controller.currentMode ==
                                                  EditorMode.draw) {
                                                // 図形上なら移動/変形、そうでなければ新規描画
                                                if (!isControl && _controller
                                                    .isPointOnDrawing(
                                                      details.localPosition,
                                                      _charWidth,
                                                      _lineHeight,
                                                    )) {
                                                  _controller.handlePanStart(
                                                    details.localPosition,
                                                    _charWidth,
                                                    _lineHeight,
                                                    HardwareKeyboard
                                                        .instance
                                                        .isAltPressed,
                                                    mode: EditorMode
                                                        .draw, // ★修正: mode引数を追加
                                                  );
                                                } else {
                                                  _controller.startStroke(
                                                    details.localPosition,
                                                  );
                                                }
                                              } else {
                                                // Textモード: テキスト選択
                                                _controller.handlePanStart(
                                                  details.localPosition,
                                                  _charWidth,
                                                  _lineHeight,
                                                  HardwareKeyboard
                                                      .instance
                                                      .isAltPressed,
                                                  mode: EditorMode
                                                      .text, // ★修正: mode引数を追加
                                                );
                                              }

                                              _focusNode.requestFocus();
                                              WidgetsBinding.instance
                                                  .addPostFrameCallback((_) {
                                                    _updateImeWindowPosition();
                                                  });
                                            },
                                            onPanUpdate: (details) {
                                              _resetCursorBlink();

                                              // 範囲選択モード
                                              if (_controller.isAreaSelectionMode && _controller.areaSelectionRect != null) {
                                                _controller.updateAreaSelection(
                                                  _controller.areaSelectionRect!.topLeft, // 始点は維持
                                                  details.localPosition,
                                                );
                                                return;
                                              }

                                              if (_controller.currentMode ==
                                                  EditorMode.draw) {
                                                // 移動中なら移動処理、描画中なら描画処理
                                                if (_controller
                                                    .isInteractingWithDrawing) {
                                                  _controller.handlePanUpdate(
                                                    details.localPosition,
                                                    _charWidth,
                                                    _lineHeight,
                                                  );
                                                } else {
                                                  _controller.updateStroke(
                                                    details.localPosition,
                                                  );
                                                }
                                              } else {
                                                // Textモード: テキスト選択更新
                                                _controller.handlePanUpdate(
                                                  details.localPosition,
                                                  _charWidth,
                                                  _lineHeight,
                                                );
                                              }

                                              WidgetsBinding.instance
                                                  .addPostFrameCallback((_) {
                                                    _updateImeWindowPosition();
                                                  });
                                            },
                                            onPanEnd: (details) async {
                                              // 範囲選択モード終了
                                              if (_controller.isAreaSelectionMode) {
                                                _controller.endAreaSelection(
                                                  _charWidth,
                                                  _lineHeight,
                                                );
                                                _scaffoldKey.currentState?.openEndDrawer(); // ドロワー再表示
                                                return;
                                              }

                                              if (_controller.currentMode ==
                                                  EditorMode.draw) {
                                                if (_controller
                                                    .isInteractingWithDrawing) {
                                                  _controller.handlePanEnd();
                                                } else {
                                                  // 描画中だったかチェック
                                                  bool wasDrawing =
                                                      _controller.isDrawing;
                                                  DrawingType type =
                                                      _controller
                                                          .currentShapeType;

                                                  _controller.endStroke(
                                                    _charWidth,
                                                    _lineHeight,
                                                  );

                                                  // 画像ツールで描画が完了した場合
                                                  if (wasDrawing &&
                                                      type ==
                                                          DrawingType.image) {
                                                    if (_controller
                                                        .drawings.isNotEmpty) {
                                                      final last = _controller
                                                          .drawings.last;
                                                      if (last.type ==
                                                              DrawingType
                                                                  .image &&
                                                          last.filePath ==
                                                              null) {
                                                        final path =
                                                            await FileIOHelper
                                                                .instance
                                                                .pickImagePath();
                                                        if (path != null) {
                                                          await _controller
                                                              .setImagePath(
                                                                last.id,
                                                                path,
                                                              );
                                                        } else {
                                                          _controller
                                                              .deleteDrawing(
                                                                last.id,
                                                              );
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              } else {
                                                _controller.handlePanEnd();
                                              }
                                            },
                                            child: Container(
                                              color: Color(
                                                _controller
                                                    .editorBackgroundColor,
                                              ), // 背景色を適用
                                              width: editorWidth,
                                              height: editorHeight,
                                              child: Stack(
                                                children: [
                                                  CustomPaint(
                                                    key: _painterKey,
                                                    painter: MemoPainter(
                                                      lines: _controller.lines,
                                                      charWidth: _charWidth,
                                                      charHeight: _charHeight,
                                                      showGrid:
                                                          _controller.showGrid,
                                                      isOverwriteMode:
                                                          _controller
                                                              .isOverwriteMode,
                                                      cursorRow:
                                                          _controller.cursorRow,
                                                      cursorCol:
                                                          _controller.cursorCol,
                                                      lineHeight: _lineHeight,
                                                      textStyle: _textStyle,
                                                      composingText: _controller
                                                          .composingText,
                                                      selectionOriginRow:
                                                          _controller
                                                              .selectionOriginRow,
                                                      selectionOriginCol:
                                                          _controller
                                                              .selectionOriginCol,
                                                      showCursor:
                                                          _controller
                                                              .enableCursorBlink
                                                          ? _showCursor
                                                          : true,
                                                      isRectangularSelection:
                                                          _controller
                                                              .isRectangularSelection,
                                                      searchResults: _controller
                                                          .searchResults,
                                                      currentSearchIndex:
                                                          _controller
                                                              .currentSearchIndex,
                                                      gridColor: Color(
                                                        _controller.gridColor,
                                                      ),
                                                      drawings:
                                                          _controller.drawings,
                                                      selectedDrawingId:
                                                          _controller
                                                              .selectedDrawingId,
                                                      shapePaddingX: _controller
                                                          .shapePaddingX,
                                                      shapePaddingY: _controller
                                                          .shapePaddingY,
                                                      showDrawings: _controller
                                                          .showDrawings,
                                                      showAllHandles:
                                                          _controller
                                                              .showAllHandles,
                                                      highlightedDrawingId: _controller.highlightedDrawingId,
                                                      highlightedDrawingType: _controller.highlightedDrawingType,
                                                      areaSelectionRect: _controller.areaSelectionRect,
                                                      editorBackgroundColor: _controller.editorBackgroundColor,
                                                      imageCache: _controller.imageCache,
                                                    ),
                                                    size: Size.infinite,
                                                  ),
                                                  CustomPaint(
                                                    painter: DrawingPainter(
                                                      strokes:
                                                          _controller.strokes,
                                                      lines: _controller.lines,
                                                      charWidth: _charWidth,
                                                      lineHeight: _lineHeight,
                                                    ),
                                                    size: Size.infinite,
                                                  ),
                                                ],
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
                          // 2. 水平スクロールバー (固定表示・エディタ幅のみ)
                          Positioned(
                            left: lineNumberAreaWidth, // 行番号の右から
                            right: 0, // 右端まで
                            bottom: 0, // 下端固定
                            child: Scrollbar(
                              controller:
                                  _scrollbarScrollController, // 専用コントローラー
                              thumbVisibility: true,
                              trackVisibility: true,
                              // ダミーのスクロールビュー (コントローラーを共有して同期)
                              child: SingleChildScrollView(
                                controller:
                                    _scrollbarScrollController, // 専用コントローラー
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: editorWidth,
                                  height: 16, // 操作しやすい高さに設定
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // --- ミニマップエリア (固定) ---
                    if (_controller.showMinimap)
                      Container(
                        key: const Key('minimapArea'),
                        child: _buildMinimap(editorWidth, editorHeight),
                      ),
                  ],
                ),
                // 検索バー (オーバーレイ表示)
                if (_showSearchBar)
                  Positioned(top: 0, right: 24, child: _buildSearchBar()),
              ],
            ),
          ),
          // Grep結果パネル
          _buildGrepResultsPanel(),
          // --- ステータスバー ---
          Container(
            color: Colors.grey.shade300,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            // DefaultTextStyleを使って一括でスタイルを適用する（王道）
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: _controller.statusFontFamily,
                fontSize: _controller.statusFontSize,
                fontWeight: _controller.statusBold
                    ? FontWeight.bold
                    : FontWeight.normal,
                fontStyle: _controller.statusItalic
                    ? FontStyle.italic
                    : FontStyle.normal,
                color: Colors.black87,
              ),
              child: Row(
                children: [
                  // 変更状態
                  Text(
                    _controller.isDirty
                        ? AppLocalizations.of(context)!.statusUnsaved
                        : "",
                  ),
                  const Spacer(),
                  // カーソル位置
                  Text(
                    "Ln ${_controller.cursorRow + 1}, Col ${_controller.cursorCol + 1}",
                  ),
                  const SizedBox(width: 16),
                  // 文字コード
                  PopupMenuButton<String>(
                    tooltip: '文字コード',
                    child: Text(_controller.currentEncoding.toUpperCase()),
                    onSelected: (encoding) async {
                      // 読み直すか、保存設定を変更するか確認
                      final s = AppLocalizations.of(context)!;
                      final int? result = await showDialog<int>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('文字コード変更'),
                          content: Text('"$encoding" に変更します。\n処理を選択してください。'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(0), // キャンセル
                              child: Text(s.labelCancel),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(1), // 保存設定のみ変更
                              child: const Text('保存設定のみ変更'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(2), // 読み直し
                              child: const Text('読み直す'),
                            ),
                          ],
                        ),
                      );

                      if (result == 1) {
                        _controller.changeEncoding(encoding);
                      } else if (result == 2) {
                        await _controller.reloadWithEncoding(encoding);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'utf-8', child: Text('UTF-8')),
                      const PopupMenuItem(
                        value: 'shift_jis',
                        child: Text('Shift_JIS'),
                      ),
                      const PopupMenuItem(
                        value: 'euc-jp',
                        child: Text('EUC-JP'),
                      ),
                      const PopupMenuItem(
                        value: 'iso-8859-1',
                        child: Text('Latin1'),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  // 改行コード
                  PopupMenuButton<NewLineType>(
                    tooltip: '改行コード',
                    child: Text(_controller.newLineType.label),
                    onSelected: (value) {
                      _controller.setNewLineType(value);
                    },
                    itemBuilder: (context) => NewLineType.values.map((type) {
                      return CheckedPopupMenuItem<NewLineType>(
                        value: type,
                        checked: _controller.newLineType == type,
                        child: Text(type.label),
                      );
                    }).toList(),
                  ),
                ],
              ),
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
      // IME確定後にフォーカスが外れるのを防ぐため、明示的に要求する
      if (!_focusNode.hasFocus) {
        _focusNode.requestFocus();
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

class _GrepResultRow extends StatelessWidget {
  final GrepResult result;
  final TextStyle textStyle;
  final double fontSize;
  final VoidCallback onTap;

  const _GrepResultRow({
    required this.result,
    required this.textStyle,
    required this.fontSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text:
                    '${result.document.displayName}:${result.searchResult.lineIndex + 1}: ',
                style: TextStyle(
                  fontSize: fontSize,
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text: result.line,
                style: textStyle.copyWith(fontSize: fontSize),
              ),
            ],
          ),
          softWrap: false,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }
}
