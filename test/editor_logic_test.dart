// test/editor_logic_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
//
import 'package:free_memo_editor/editor_page.dart';

void main() {
  testWidgets('矢印キー操作 (上、下、左、右) 動作確認', (WidgetTester tester) async {
    // 1. アプリ起動と設定
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    // エディタを起動(ポンプ)する
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    // 画面完了を待つ
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

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
}
