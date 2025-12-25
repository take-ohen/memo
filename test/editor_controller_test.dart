import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:free_memo_editor/editor_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EditorController controller;
  String? mockClipboardText;

  setUp(() async {
    // SharedPreferencesのモック
    SharedPreferences.setMockInitialValues({});

    // クリップボードのモック設定
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall methodCall,
        ) async {
          if (methodCall.method == 'Clipboard.getData') {
            return {'text': mockClipboardText};
          }
          if (methodCall.method == 'Clipboard.setData') {
            final args = methodCall.arguments as Map<dynamic, dynamic>;
            mockClipboardText = args['text'] as String?;
            return null;
          }
          return null;
        });

    controller = EditorController();
    await controller.loadSettings();

    // テストごとに状態をリセット
    mockClipboardText = null;
    controller.lines = [''];
    controller.cursorRow = 0;
    controller.cursorCol = 0;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('EditorController Tests', () {
    test('虚空への矩形貼り付け (全角半角混在)', () async {
      // 1. 準備: 貼り付けるデータ (全角含む)
      mockClipboardText = "あA\nいB";

      // 2. 操作: 虚空へカーソル移動 (2行目, 4文字目相当の位置へ)
      // linesは初期状態で [''] なので、2行目は存在しない
      controller.cursorRow = 2;
      controller.cursorCol = 4; // 半角4文字分

      // 3. 実行: 矩形貼り付け
      await controller.pasteRectangular();

      // 4. 検証
      // 行が自動的に拡張されていること (0,1,2,3行目まであるはず)
      expect(controller.lines.length, greaterThanOrEqualTo(4));

      // 2行目: スペース4つ + "あA"
      // 虚空パディングが効いていれば、指定位置から貼り付けられる
      expect(controller.lines[2], equals('    あA'));

      // 3行目: スペース4つ + "いB"
      // 矩形貼り付けなので、2行目と同じ垂直位置(VisualX)に揃うはず
      expect(controller.lines[3], equals('    いB'));
    });

    test('囲み枠 drawBox (通常 & 全角)', () {
      // 1. 準備: データセット
      controller.lines = ['あいう', 'ABC'];

      // 2. 操作: 全体を選択
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 1;
      controller.cursorCol = 6; // 修正: "あいう"(幅6)を囲むため、幅6まで選択範囲を広げる

      // 3. 実行: 囲み枠
      controller.drawBox();

      // 4. 検証
      // 期待される形状:
      // ┌──────┐ (全角3文字=幅6)
      // │あいう│
      // │ABC   │ (幅3文字+"ABC"で幅6に合わせる)
      // └──────┘

      // 上辺
      expect(controller.lines[0], contains('┌'));
      expect(controller.lines[0], contains('┐'));

      // データ行
      expect(controller.lines[1], contains('│あいう│'));
      // "ABC" (幅3) なので "あいう" (幅6) に合わせるためスペース3つ追加される
      expect(controller.lines[2], contains('│ABC   │'));

      // 下辺
      expect(controller.lines[3], contains('└'));
      expect(controller.lines[3], contains('┘'));
    });

    test('囲み枠 drawBox (左上端 0,0)', () {
      // 1. 準備
      controller.lines = ['A'];

      // 2. 操作: 0行0列を選択
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 0;
      controller.cursorCol = 1;

      // 3. 実行
      controller.drawBox();

      // 4. 検証
      // 0行目より上、0列目より左には描画できないため、
      // 自動的に拡張され、囲まれているはず

      // 0行目: ┌-┐ (挿入された行。幅不足の端数処理で - になる)
      expect(controller.lines[0], contains('┌'));
      expect(controller.lines[0], contains('┐'));

      // 1行目: │A│ (元の行がシフトされ、枠がついた)
      expect(controller.lines[1], contains('│A'));
    });

    test('囲み枠 drawBox (行の一部のみ)', () {
      // 1. 準備: データセット "A B C D E"
      controller.lines = ['A B C D E'];

      // 2. 操作: "B C" (index 2~5) を選択
      // "A " (2文字) -> B開始
      // "B C" (3文字)
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 2; // "B"の前
      controller.cursorRow = 0;
      controller.cursorCol = 5; // "C"の後ろ

      // 3. 実行
      controller.drawBox();

      // 4. 検証
      // startRow=0 なので、上に行が挿入される -> 元の行は index 1 になる。
      // 期待: "A │B C│ D E"
      // 行末まで枠が伸びていないこと (" D E" が枠外にあること)
      expect(controller.lines[1], contains('A │B C│ D E'));
      expect(controller.lines[0], isNot(contains('D E'))); // 上辺にデータが含まれていないこと
    });

    test('テーブル作成 formatTable (全角半角混在)', () {
      // 1. 準備: カンマ区切りデータ
      controller.lines = [
        '品名,価格',
        'りんご,100', // 全角3文字(幅6), 半角3文字(幅3)
        'A,20', // 半角1文字(幅1), 半角2文字(幅2)
      ];

      // 2. 操作: 全体を選択 (最大幅を含むように修正)
      // 左下(2行目先頭)から右上(0行目末尾)へ選択
      controller.selectionOriginRow = 2;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 0;
      controller.cursorCol = 5; // "品名,価格".length = 5

      // 3. 実行
      controller.formatTable();

      // 4. 検証
      // 最大幅: 1列目="りんご"(6), 2列目="価格"(4) -> "100"(3) -> "価格"が最大
      // 期待される形状:
      // ┌──────┬────┐
      // │品名  │価格│
      // ├──────┼────┤
      // │りんご│100 │
      // ├──────┼────┤
      // │A     │20  │
      // └──────┴────┘

      // 罫線チェック
      expect(controller.lines[0], startsWith('┌'));
      expect(controller.lines[0], endsWith('┐'));

      // データ行チェック (パディング含む)
      // "りんご" は幅6。最大幅6なのでパディングなし
      expect(controller.lines.any((line) => line.contains('│りんご│')), isTrue);

      // "A" は幅1。最大幅6なのでスペース5つ
      expect(controller.lines.any((line) => line.contains('│A     │')), isTrue);
    });
  });
}
