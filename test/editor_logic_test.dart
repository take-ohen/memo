// test/editor_logic_test.dart
import 'dart:io'; // ファイル操作用
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
//
import 'package:free_memo_editor/editor_page.dart';
import 'package:free_memo_editor/file_io_helper.dart'; // 追加
import 'package:free_memo_editor/editor_controller.dart'; // 追加
import 'package:free_memo_editor/memo_painter.dart'; // LineNumberPainter用

void main() {
  testWidgets('矢印キー操作 (上、下、左、右) 動作確認', (WidgetTester tester) async {
    // 1. アプリ起動と設定
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    // エディタを起動(ポンプ)する
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    // 画面完了を待つ
    await tester.pump();

    // Stateを取得 (内部変数をチェックするため)
    // 画面上にあるウィジェットを探し、その内部状態（State）を取得します。
    final state = tester.state(find.byType(EditorPage)) as dynamic;

    // 2. テキスト入力: "abc" (改行) "de"
    // Row 0: "abc" (3文字)
    // Row 1: "de"  (2文字)
    // tapAtは不安定なので、キー連打で確実に(0,0)に戻す
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.pump();

    // キーイベントで確実に入力を行う (enterTextだと改行が反映されない場合があるため)
    // "abc"
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    // 改行 (Enter)
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    // "de"
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump(); // 描画更新

    // 初期状態確認: カーソルは入力直後なので末尾 (Row 1, Col 2) にあるはず
    expect(state.debugCursorRow, 1, reason: "初期位置: 2行目");
    expect(state.debugCursorCol, 2, reason: "初期位置: 2文字目の後ろ");

    // --- Test: ファイル末尾での右移動 (止まるはず) ---
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(state.debugCursorRow, 1, reason: "末尾で右: 行変わらず");
    expect(state.debugCursorCol, 2, reason: "末尾で右: 列変わらず");

    // --- Test: 上移動 (1行目へ) ---
    // (1, 2) -> (0, 2) ('c'の手前あたり)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(state.debugCursorRow, 0, reason: "上移動: 1行目へ");
    expect(state.debugCursorCol, 2, reason: "上移動: 列は維持されるはず");

    // --- Test: ファイル先頭行での上移動 (止まるはず) ---
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(state.debugCursorRow, 0, reason: "最上行で上: 行変わらず");

    // --- Test: 下移動 (2行目へ) ---
    // (0, 2) -> (1, 2)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(state.debugCursorRow, 1, reason: "下移動: 2行目へ");
    expect(state.debugCursorCol, 2, reason: "下移動: 列は維持されるはず");

    // --- Test: 左移動で行跨ぎ (行頭 -> 前の行の末尾) ---
    // まず行頭 (1, 0) まで移動
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft); // -> 1, 1
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft); // -> 1, 0
    await tester.pump();
    expect(state.debugCursorCol, 0, reason: "2行目の行頭に移動完了");

    // 左へ (ここで行跨ぎ発生！) -> (0, 3) "abc"の後ろ
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(state.debugCursorRow, 0, reason: "左移動で行跨ぎ: 前の行へ");
    expect(state.debugCursorCol, 3, reason: "左移動で行跨ぎ: 前の行の末尾(3)へ");

    // --- Test: 右移動で行跨ぎ (行末 -> 次の行の先頭) ---
    // (0, 3) -> (1, 0)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(state.debugCursorRow, 1, reason: "右移動で行跨ぎ: 次の行へ");
    expect(state.debugCursorCol, 0, reason: "右移動で行跨ぎ: 次の行の先頭(0)へ");

    // --- Test: ファイル先頭での左移動 (止まるはず) ---
    // まず (0,0) まで戻る
    // 現在 (1,0) なので、左へ行くと (0,3)。そこから左へ3回で (0,0)
    for (int i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.pump();
    expect(state.debugCursorRow, 0);
    expect(state.debugCursorCol, 0);

    // さらに左へ
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(state.debugCursorRow, 0, reason: "ファイル先頭で左: 移動しない");
    expect(state.debugCursorCol, 0, reason: "ファイル先頭で左: 移動しない");
  });

  testWidgets('Alt + 矢印キー操作 (上、下、左、右) 動作確認 (Void move & Wrap)', (
    WidgetTester tester,
  ) async {
    // 1. アプリ起動
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    await tester.pump();

    final state = tester.state(find.byType(EditorPage)) as dynamic;

    // 2. テキスト入力 "abc" (改行) "de"
    // tapAtは不安定なので、キー連打で確実に(0,0)に戻す
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.pump();

    // "abc"
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    // 改行
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    // "de"
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();

    // --- Test: Alt + Down (虚空への移動) ---
    // 現在 (1, 2) -> Alt+Down -> (2, 2) になるはず
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.pump();

    expect(state.debugCursorRow, 2, reason: "Alt+Down: 行数制限を超えて移動できるはず");
    expect(state.debugCursorCol, 2, reason: "Alt+Down: 列位置(VisualX)は維持されるはず");

    // --- Test: Alt + Up (戻る) ---
    // (2, 2) -> Alt+Up -> (1, 2)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.pump();

    expect(state.debugCursorRow, 1, reason: "Alt+Up: 元の行に戻る");

    // --- Test: Alt + Right (虚空への移動) ---
    // まず (0, 3) "abc"の後ろへ移動
    // タップが不安定なため、キー連打で確実に (0,0) に戻す
    for (int i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.pump();

    for (int i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    // Alt+Right -> (0, 4)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.pump();

    expect(state.debugCursorRow, 0);
    expect(state.debugCursorCol, 4, reason: "Alt+Right: 行末を超えて移動できるはず");

    // --- Test: Alt + Left (行跨ぎ) ---

    // タップでのリセットは不安定なため、キー連打で確実に (0,0) に戻す
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.pump();

    // (0,0) から "de"の先頭 (1, 0) へ移動
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // (1, 0)
    await tester.pump();

    // Alt+Left -> (0, 3) "abc"の後ろへ戻る (通常移動と同じ挙動)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.pump();

    expect(state.debugCursorRow, 0, reason: "Alt+Left: 前の行に戻るはず(行跨ぎ)");
    expect(state.debugCursorCol, 3, reason: "Alt+Left: 前の行の末尾へ");
  });

  testWidgets('Copy, Paste, and Rectangular Paste Logic', (
    WidgetTester tester,
  ) async {
    // 1. クリップボードのモック化 (システムへのアクセスをインターセプト)
    final List<MethodCall> log = <MethodCall>[];
    String? mockClipboardData;

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        log.add(methodCall);
        if (methodCall.method == 'Clipboard.setData') {
          // コピー: データを変数に保存
          final Map<String, dynamic> args =
              methodCall.arguments as Map<String, dynamic>;
          mockClipboardData = args['text'] as String?;
          return null;
        } else if (methodCall.method == 'Clipboard.getData') {
          // 貼り付け: 変数からデータを返す
          return {'text': mockClipboardData};
        }
        return null;
      },
    );

    // 2. アプリ起動
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    await tester.pump();

    final state = tester.state(find.byType(EditorPage)) as dynamic;

    // 3. テキスト入力
    // Row 0: "abcde"
    // Row 1: "fghij"
    // tapAtは不安定なので、キー連打で確実に(0,0)に戻す
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.pump();

    // "abcde" + Enter + "fghij"
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();

    // --- Test: 範囲選択とコピー (Ctrl + C) ---
    // カーソルを (0, 1) 'b' の前へ移動
    // tapAtは不安定なので、キー連打で確実に(0,0)に戻す
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // (0,1)
    await tester.pump();

    // Shift + Down で (1, 1) へ範囲選択
    // 始点(0,1)～終点(1,1)。現在の実装では矩形範囲としてコピーされるはず。
    // 0行目の 'b' (index 1) と 1行目の 'g' (index 1) が対象。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(
      LogicalKeyboardKey.arrowRight,
    ); // 幅を持たせるために右へ1つ広げる
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    debugPrint(
      "DEBUG TEST: After Selection - Row=${state.debugCursorRow}, Col=${state.debugCursorCol}",
    );

    // コピー実行 (Ctrl + C)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    // 検証: クリップボードに "b" と "g" が含まれているか
    expect(mockClipboardData, contains("b"));
    expect(mockClipboardData, contains("g"));

    // --- Test: 矩形貼り付け (Ctrl + Alt + V) ---
    // 準備: クリップボードに "1\n2" をセット
    mockClipboardData = "1\n2";

    // カーソルを (0, 4) 'e' の前へ移動
    // ここもキー連打で確実にリセット
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    for (int i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.pump();

    // 矩形貼り付け実行 (Ctrl + Alt + V)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    // 検証: カーソル位置が貼り付け後の右下 (1, 5) にあるか
    // 0行目: "abcd" + "1" + "e" -> "abcd1e" (5文字目の後ろ)
    // 1行目: "fghi" + "2" + "j" -> "fghi2j" (5文字目の後ろ)
    expect(state.debugCursorRow, 1, reason: "矩形貼り付け後: 最終行へ");
    expect(state.debugCursorCol, 5, reason: "矩形貼り付け後: 貼り付けた文字の後ろへ");

    // モック解除
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('普通貼付け (Ctrl+V) and 矩形モード (Normal vs Rectangular)', (
    WidgetTester tester,
  ) async {
    // 1. クリップボードのモック化
    final List<MethodCall> log = <MethodCall>[];
    String? mockClipboardData;

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        log.add(methodCall);
        if (methodCall.method == 'Clipboard.setData') {
          final Map<String, dynamic> args =
              methodCall.arguments as Map<String, dynamic>;
          mockClipboardData = args['text'] as String?;
          return null;
        } else if (methodCall.method == 'Clipboard.getData') {
          return {'text': mockClipboardData};
        }
        return null;
      },
    );

    // 2. アプリ起動
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    await tester.pump();

    final state = tester.state(find.byType(EditorPage)) as dynamic;

    // 3. テキスト入力
    // Row 0: "abcde"
    // Row 1: "fghij"
    // カーソルリセット
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.pump();

    // 入力
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();

    // --- Test: 通常貼り付け (Ctrl + V) ---
    // 準備: クリップボードに "XYZ" をセット
    mockClipboardData = "XYZ";

    // カーソルを (0, 0) へ
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.pump();

    // 貼り付け実行 (Ctrl + V)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    // 検証: カーソルが3文字進んでいるか ("XYZ"の分)
    // 元: "abcde" -> "XYZabcde"
    expect(state.debugCursorRow, 0, reason: "通常貼り付け後: 行は変わらず");
    expect(state.debugCursorCol, 3, reason: "通常貼り付け後: 3文字分進む");

    // --- Test: 通常選択コピー (Shift + Arrow) ---
    // カーソルを (1, 1) 'g' の前へ移動
    // 現在 (0, 3)。下へ行って (1, 3)。左へ2回で (1, 1)。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    // 選択開始: (1, 1) から (1, 3) まで ('g', 'h')
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // (1, 2)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // (1, 3)
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    // コピー実行 (Ctrl + C)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    // 検証: "gh" がコピーされているか
    expect(mockClipboardData, equals("gh"), reason: "通常選択コピー: 行内選択");

    // --- Test: 矩形選択コピー (Shift + Alt + Arrow) ---
    // カーソルを (0, 1) 'Y' の前へ
    // 現在の状態:
    // Row 0: "XYZabcde"
    // Row 1: "fghij"

    // カーソルリセット
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // (0, 1)
    await tester.pump();

    // 矩形選択: (0, 1) から (1, 2) まで
    // Row 0: index 1 ('Y')
    // Row 1: index 1 ('g')
    // 幅: 1文字分

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt); // Alt押下

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // (1, 1)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // (1, 2) 幅確保

    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    // コピー実行
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    // 検証: 矩形コピー
    // Row 0: "XYZ..." の index 1 ('Y')
    // Row 1: "fgh..." の index 1 ('g')
    // 期待値: "Y\ng\n" (実装により末尾改行の有無が異なるが、trim()で吸収)
    expect(
      mockClipboardData?.trim(),
      equals("Y\ng"),
      reason: "矩形選択コピー: 縦に切り出される",
    );

    // モック解除
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('Overwrite Selection (Normal & Rectangular)', (
    WidgetTester tester,
  ) async {
    // 1. アプリ起動
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    await tester.pump();

    final state = tester.state(find.byType(EditorPage)) as dynamic;

    // 2. テキスト入力
    // Row 0: "abcde"
    // Row 1: "fghij"
    // カーソルリセット
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.pump();

    // 入力
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();

    // --- Test 1: 通常選択の上書き ---
    // カーソルを (0, 1) 'b' の前へ
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // (0, 1)
    await tester.pump();

    // "bc" を選択 (Shift + Right x 2)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    // "X" を入力 (選択範囲 "bc" が消えて "X" になるはず)
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();

    // 検証: "abcde" -> "axde"
    expect(
      state.debugLines[0],
      equals("axde"),
      reason: "通常選択の上書き: 選択範囲が置換されること",
    );

    // --- Test 2: 矩形選択の上書き ---
    // 状態リセット: テキストを "abcde", "fghij" に戻すのは手間なので、
    // 現在の "aXde", "fghij" をベースにテストする

    // カーソルを (0, 1) 'X' の前へ
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // (0, 1)
    await tester.pump();

    // 矩形選択: (0, 1) から (1, 2) まで
    // Row 0: "axde" の index 1 ('x')
    // Row 1: "fghij" の index 1 ('g')
    // 幅: 1文字分 (Right x 1)

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt); // Alt押下(矩形)

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // (1, 1)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // (1, 2) 幅確保

    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    // "Y" を入力 (矩形範囲が消えて "Y" になるはず)
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.pump();

    // 検証:
    // Row 0: "axde" -> "ayde" ('x'が'y'に)
    // Row 1: "fghij" -> "fyhij" ('g'が'y'に)
    expect(state.debugLines[0], equals("ayde"), reason: "矩形選択の上書き(Row0)");
    expect(state.debugLines[1], equals("fyhij"), reason: "矩形選択の上書き(Row1)");
  });

  testWidgets('Shift Key Selection Logic (No selection on Shift only)', (
    WidgetTester tester,
  ) async {
    // 1. アプリ起動
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    await tester.pump();

    // 2. テキスト入力 "abc"
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();

    // カーソルを先頭へ (0,0)
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.pump();

    // --- Test: Shiftキーを押すだけ (KeyDown) ---
    // これだけでは選択モードに入らないことを確認したいが、
    // 内部状態が見えないため、次の操作で確認する。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    // --- Test: Shiftを押したまま右へ ---
    // ここで初めて選択モードになり、(0,0) -> (0,1) が選択されるはず
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    // Shiftを離す
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    // クリップボードモック設定
    String? mockClipboardData;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final args = methodCall.arguments as Map<String, dynamic>;
          mockClipboardData = args['text'] as String?;
        }
        return null;
      },
    );

    // コピー実行 (Ctrl + C)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    // 検証: "a" がコピーされていること
    expect(mockClipboardData, equals("a"), reason: "Shift+Rightで選択され、コピーできること");

    // モック解除
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('IME Composing Logic (Ignore keys during composition)', (
    WidgetTester tester,
  ) async {
    // 1. アプリ起動
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    await tester.pump();

    final state = tester.state(find.byType(EditorPage)) as dynamic;

    // 2. テキスト入力 "abc"
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();

    // カーソル位置確認: (0, 3)
    expect(state.debugCursorCol, 3);

    // --- Test: IME入力中状態にする ---
    // updateEditingValue を呼んで composing 状態を作る
    // "d" を入力中で未確定の状態をシミュレート
    state.updateEditingValue(
      const TextEditingValue(text: 'd', composing: TextRange(start: 0, end: 1)),
    );
    await tester.pump();

    // --- Test: 矢印キー操作 (無視されるべき) ---
    // 左キーを押す
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    // 検証: カーソル位置は (0, 3) のまま変わっていないはず
    expect(state.debugCursorCol, 3, reason: "IME入力中は矢印キーが無視されること");

    // --- Test: Shift + 矢印キー (無視されるべき) ---
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    expect(state.debugCursorCol, 3, reason: "IME入力中はShift+矢印も無視されること");

    // --- Test: IME確定 ---
    // composingを解除して確定させる
    state.updateEditingValue(
      const TextEditingValue(text: 'd', composing: TextRange.empty),
    );
    await tester.pump();

    // 確定処理により "abc" + "d" -> "abcd" となり、カーソルは 4 に進むはず
    expect(state.debugCursorCol, 4, reason: "IME確定後は文字が挿入されカーソルが進む");

    // 確定後はキー操作が可能になるはず
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(state.debugCursorCol, 3, reason: "IME確定後は矢印キー操作が可能");
  });

  testWidgets('Select All (Ctrl+A) Logic', (WidgetTester tester) async {
    // 1. アプリ起動
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    await tester.pump();

    // 2. テキスト入力 "abc\nde"
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();

    // 3. 全選択 (Ctrl + A)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    // 4. コピーして検証 (Ctrl + C)
    String? mockClipboardData;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final args = methodCall.arguments as Map<String, dynamic>;
          mockClipboardData = args['text'] as String?;
        }
        return null;
      },
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    // 改行コードの違いを吸収して比較
    final normalizedClipboard = mockClipboardData?.replaceAll('\r\n', '\n');
    expect(normalizedClipboard, equals("abc\nde"), reason: "全選択で全文がコピーされること");

    // モック解除
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('File Save & Load Logic (Mocking FilePicker)', (
    WidgetTester tester,
  ) async {
    // カーソル点滅タイマーを無効化して、pumpAndSettleを使えるようにする
    EditorPage.disableCursorBlink = true;

    // 1. テスト用の一時ディレクトリとファイルを作成
    final tempDir = Directory.systemTemp.createTempSync('memo_test');

    final testFile = File('${tempDir.path}/test_input.txt');
    testFile.writeAsStringSync('Hello\nWorld'); // 初期データ

    final savePath = '${tempDir.path}/test_output.txt';

    // 2. FileIOHelper のモック差し替え
    // FilePickerPlatform を直接いじるのではなく、自前のラッパーを差し替える
    final mockHelper = MockFileIOHelper();
    mockHelper.mockPickPath = testFile.path;
    mockHelper.mockSavePath = savePath;
    FileIOHelper.instance = mockHelper;

    // 3. アプリ起動
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    await tester.pump();
    final state = tester.state(find.byType(EditorPage)) as dynamic;

    // --- Test: ファイルを開く ---
    // UIの「開く」ボタンをタップ
    await tester.tap(find.byIcon(Icons.folder_open));
    // タイマーを無効化したので、pumpAndSettle で安全に非同期処理の完了と描画安定を待てる
    await tester.pumpAndSettle();

    // 検証: ファイルの内容が読み込まれているか
    expect(state.debugLines.length, 2);
    expect(state.debugLines[0], "Hello");
    expect(state.debugLines[1], "World");

    // --- Test: 編集して保存 ---
    // 1行目を "Hello Edited" に変更
    // カーソルは読み込み直後 (0,0) にあるはず
    // 行末へ移動して " Edited" を追記
    for (int i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();

    // UIの「名前を付けて保存」ボタンをタップ (Icons.save_as)
    await tester.tap(find.byIcon(Icons.save_as));
    await tester.pumpAndSettle();

    // 検証: 保存先のファイルに書き込まれているか
    final outputFile = File(savePath);
    expect(outputFile.existsSync(), isTrue, reason: "保存ファイルが作成されていること");
    final content = outputFile.readAsStringSync();
    expect(content, contains("Hello edit\nWorld"), reason: "編集内容が保存されていること");
    // ※注: キー入力シミュレーションは高速なため、"edit"までしか入らない場合や
    // "Edited"全て入る場合があるが、containsで検証。

    // 後始末
    tempDir.deleteSync(recursive: true);
  });
  testWidgets('Input in Void (Virtual Space) should not crash', (
    WidgetTester tester,
  ) async {
    // 1. アプリ起動
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(EditorPage)) as dynamic;

    // 2. 虚空へ移動 (Alt + Down 連打)
    // 初期状態は1行。10回下へ移動すれば確実に虚空(10行目)になる。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.pump();

    // 検証: カーソルが10行目にあること
    expect(state.debugCursorRow, 10, reason: "Alt+Downで虚空(10行目)に移動できていること");

    // 検証: まだ行は増えていないこと(1行のまま)
    // ※ここが重要。データがない場所に入力しようとする状況を作る。
    expect(state.debugLines.length, 1, reason: "入力前は行数は増えていないこと");

    // 3. 文字入力 ("a")
    // ★修正前はここで RangeError が発生してクラッシュする
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();

    // 4. 検証
    // クラッシュせずにここに来ればOK

    // 行数が自動拡張されていること (0行目〜10行目 なので 計11行になるはず)
    expect(state.debugLines.length, 11, reason: "入力により行が自動拡張されること");

    // 10行目に "a" が入っていること
    expect(state.debugLines[10], "a", reason: "虚空に入力した文字が反映されること");
  });

  testWidgets('Backspace and Delete in Void (Virtual Space)', (
    WidgetTester tester,
  ) async {
    // 1. アプリ起動
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(EditorPage)) as dynamic;

    // 2. テキスト入力 "abc"
    await tester.tap(find.byType(EditorPage));
    await tester.pump();

    // タップ位置によりカーソルが移動してしまうため、強制的に(0,0)へ戻す
    for (int i = 0; i < 50; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();

    // --- Test 1: 行内虚空での Backspace ---
    // カーソルを (0, 5) へ移動 ("abc" は長さ3なので、2文字分虚空)
    // Alt + Right で移動
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // 4
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // 5
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.pump();

    expect(state.debugCursorCol, 5, reason: "カーソルが虚空(5列目)にあること");

    // Backspace押下
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(state.debugCursorCol, 4, reason: "虚空でのBackspaceはカーソルが左に移動すること");
    expect(state.debugLines[0], "abc", reason: "虚空でのBackspaceで文字が消えていないこと");

    // --- Test 2: 完全虚空行での Backspace ---
    // カーソルを (2, 2) へ移動 (データは0行目のみ。1, 2行目は存在しない)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // 1行目
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // 2行目
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft); // 3列目
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft); // 2列目
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.pump();

    expect(state.debugCursorRow, 2, reason: "カーソルが虚空行(2行目)にあること");
    expect(state.debugCursorCol, 2, reason: "カーソルが2列目にあること");

    // Backspace押下
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(state.debugCursorRow, 2, reason: "行は変わらないこと");
    expect(state.debugCursorCol, 1, reason: "カーソルが左に移動すること");
    expect(state.debugLines.length, 1, reason: "行データは増えていないこと(1行のまま)");

    // --- Test 3: 行内虚空での Delete (行結合) ---
    // リセットして再構築
    await tester.pumpWidget(MaterialApp(home: EditorPage(key: UniqueKey())));
    await tester.pumpAndSettle();
    final state2 = tester.state(find.byType(EditorPage)) as dynamic;

    // 入力:
    // abc
    // def
    await tester.tap(find.byType(EditorPage));
    await tester.pump();

    // タップ位置によりカーソルが移動してしまうため、強制的に(0,0)へ戻す
    for (int i = 0; i < 50; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(); // Enterの処理を確定させる
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();

    // テスト準備が正しく行われたか確認
    expect(state2.debugLines.length, 2, reason: "テスト準備: 2行あること");
    expect(state2.debugLines[1], "def", reason: "テスト準備: 2行目が'def'であること");

    // カーソルを (0, 5) へ移動 (abcの後ろの虚空)
    // まず (0,0)へ戻す
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    // "abc"の後ろ(3)へ
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);

    // Alt+Right で 5 まで移動
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // 4
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // 5
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.pump();

    expect(state2.debugCursorRow, 0);
    expect(state2.debugCursorCol, 5);

    // Delete押下
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    // 期待値: "abc  def"
    // "abc"(3文字) + "  "(2文字分のスペース) + "def"
    expect(
      state2.debugLines[0],
      "abc  def",
      reason: "虚空Deleteでスペース埋め＋行結合が行われること",
    );
    expect(state2.debugLines.length, 1, reason: "行が結合されて1行になること");
  });

  testWidgets('Search and Replace Logic', (WidgetTester tester) async {
    // 1. アプリ起動
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    await tester.pump();

    final state = tester.state(find.byType(EditorPage)) as dynamic;
    final EditorController controller = state.debugController;

    // 2. テキスト入力 "abc abc abc"
    // カーソルリセット
    for (int i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();

    expect(state.debugLines[0], "abc abc abc");

    // --- Test: 検索 (Search) ---
    // Ctrl + F で検索バーを開く
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    // 検索ワード "abc" を入力
    // 検索バーのTextFieldを探して入力
    final searchField = find.widgetWithText(TextField, '検索');
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, "abc");
    await tester.pump();

    // 検証: 3件ヒットしているか
    expect(controller.searchResults.length, 3, reason: "3つの 'abc' が見つかるはず");
    expect(controller.currentSearchIndex, 0, reason: "最初は0番目が選択されているはず");

    // 「次へ」ボタン (arrow_downward) を押す
    await tester.tap(find.byIcon(Icons.arrow_downward));
    await tester.pump();

    // 検証: インデックスが 1 に進むか
    expect(controller.currentSearchIndex, 1, reason: "次へボタンでインデックスが進むこと");

    // --- Test: 置換 (Replace) ---
    // Ctrl + H で置換モードへ
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    // 置換ワード "def" を入力
    final replaceField = find.widgetWithText(TextField, '置換');
    expect(replaceField, findsOneWidget);
    await tester.enterText(replaceField, "def");
    await tester.pump();

    // 「置換」ボタンを押す (現在の選択箇所のみ置換)
    // 現在のインデックスは 1 (真ん中の "abc")
    await tester.tap(find.text('置換'));
    await tester.pump();

    // 検証: 真ん中だけ "def" になっているか -> "abc def abc"
    expect(state.debugLines[0], "abc def abc", reason: "現在の選択箇所のみ置換されること");
    // 置換後は再検索され、インデックスが維持または調整される
    expect(controller.searchResults.length, 2, reason: "残りの 'abc' は2つ");

    // 「全て置換」ボタンを押す
    await tester.tap(find.text('全て置換'));
    await tester.pump();

    // 検証: 全て "def" になっているか -> "def def def"
    expect(state.debugLines[0], "def def def", reason: "全て置換されること");
    expect(controller.searchResults.length, 0, reason: "'abc' はもう無いはず");
  });
}

// --- Mock Class ---

class MockFileIOHelper extends FileIOHelper {
  String? mockPickPath;
  String? mockSavePath;

  @override
  Future<String?> pickFilePath() async {
    return mockPickPath;
  }

  @override
  Future<String?> saveFilePath() async {
    return mockSavePath;
  }

  @override
  Future<String> readFileAsString(String path) async {
    // テスト時は同期的に読み込むことでハングを防ぐ
    return File(path).readAsStringSync();
  }

  @override
  Future<void> writeStringToFile(String path, String content) async {
    // テスト時は同期的に書き込むことでハングを防ぐ
    File(path).writeAsStringSync(content);
  }
}
