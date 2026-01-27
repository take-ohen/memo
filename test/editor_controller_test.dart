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
    // activeDocumentをリセットするためにタブを閉じて新規作成するか、中身をクリアする
    controller.lines = ['']; // セッター経由でactiveDocument.linesが更新される
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
      // 上書きモードなので、枠線を描画するための余白(スペース)を上下左右に持たせておく
      controller.lines = [
        '', // 0行目: 上辺用スペース
        '  あいう  ', // 1行目: データ (左にスペース2つ=全角枠線分)
        '  ABC     ', // 2行目: データ
        '', // 3行目: 下辺用スペース
      ];

      // 2. 操作: 1行目の"あいう"から2行目の"ABC"までを選択
      controller.selectionOriginRow = 1;
      controller.selectionOriginCol = 2; // "  " の後
      controller.cursorRow = 2;
      controller.cursorCol = 8; // "  ABC" (幅5) + 余白分含めて幅6になるように調整 -> "  ABC   "

      // 3. 実行: 囲み枠
      controller.drawBox();

      // 4. 検証
      // 期待される形状:
      // ┌──────┐ (全角3文字=幅6)
      // │あいう│
      // │ABC   │ (幅3文字+"ABC"で幅6に合わせる)
      // └──────┘

      // 0行目: 上辺
      expect(controller.lines[0], contains('┌'));
      expect(controller.lines[0], contains('┐'));

      // 1行目: データ行
      expect(controller.lines[1], contains('│あいう│'));
      // 2行目: データ行 (パディング含む)
      expect(controller.lines[2], contains('│ABC   │'));

      // 3行目: 下辺
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
      // 0行目より上(上辺)、0列目より左(左辺)には描画できないため、
      // 描画可能な右辺と下辺のみが描画されることを確認

      // 0行目: A│ (右辺のみ。左辺なし)
      expect(controller.lines[0], contains('A│'));

      // 1行目: -┘ (下辺のみ。幅1に対して全角線(幅2)は引けないため、端数処理で半角ハイフンになる)
      expect(controller.lines[1], contains('-┘'));
    });

    test('囲み枠 drawBox (行の一部のみ)', () {
      // 1. 準備: データセット "A   B C   D E"
      // 枠線(全角幅2)を描画するための余白(スペース)を持たせておく
      controller.lines = ['A   B C   D E'];

      // 2. 操作: "B C" (index 2~5) を選択
      // "A   " (4文字) -> B開始
      // "B C" (3文字) -> C終了
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 4; // "B"の前
      controller.cursorRow = 0;
      controller.cursorCol = 7; // "C"の後ろ

      // 3. 実行
      controller.drawBox();

      // 4. 検証
      // startRow=0 なので、上辺は描画されない。
      // 左右の枠線は描画される。
      // 期待: "A │B C│ D E" (0行目)
      // A(0) + sp(1) + │(2,3) + B(4) + sp(5) + C(6) + │(7,8) + sp(9) + D(10)...
      expect(controller.lines[0], contains('A │B C│ D E'));
      // 下辺は1行目に描画される
      expect(controller.lines[1], contains('└'));
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

    test('行末の空白削除 trimTrailingWhitespace', () {
      // 1. 準備
      controller.lines = [
        'abc   ', // 半角スペース
        'あいう　　', // 全角スペース
        '   def', // 行頭スペース（消えないはず）
        '   ', // 空白のみ（空行になるはず）
      ];

      // 2. 実行
      controller.trimTrailingWhitespace();

      // 3. 検証
      expect(controller.lines[0], equals('abc'));
      expect(controller.lines[1], equals('あいう'));
      expect(controller.lines[2], equals('   def'));
      expect(controller.lines[3], equals(''));
    });

    test('直線描画 drawLine (接続処理)', () {
      // 1. 準備: 縦線がある状態
      // │
      // │
      // │
      controller.lines = ['  │  ', '  │  ', '  │  '];

      // 2. 操作: 真ん中の行を横切るように選択 (十字接続)
      // "  │  " の左(0)から右(4)へ
      controller.selectionOriginRow = 1;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 1;
      controller.cursorCol = 5; // 幅5

      // 3. 実行
      controller.drawLine();

      // 4. 検証: 十字路 '┼' になっているか
      // 期待: ─┼─ (半角スペース2つが全角罫線1つに置換される)
      expect(controller.lines[1], contains('─┼─'));

      // 5. 操作: 下の行から右へT字接続
      // 2行目の縦線から右へ引く
      controller.selectionOriginRow = 2;
      controller.selectionOriginCol = 2; // '│' の位置
      controller.cursorRow = 2;
      controller.cursorCol = 5;

      // 6. 実行
      controller.drawLine();

      // 7. 検証: T字路 '├' になっているか
      // 元:   │
      // 引く: ├────
      // 期待:   ├─
      // 注意: 左側のスペースは維持される
      expect(controller.lines[2], contains('  ├─'));
    });

    test('直線描画 drawLine (水平線・単独)', () {
      // 1. 準備: 空白
      controller.lines = ['          '];

      // 2. 操作: 水平に線を引く
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 0;
      controller.cursorCol = 10;

      // 3. 実行
      controller.drawLine(useHalfWidth: false);

      // 4. 検証
      // 以前は端点が┼になっていたが、今は─になるはず
      // 期待: ─────
      expect(controller.lines[0], contains('─────'));
    });

    test('直線描画 drawLine (全角モードは水平垂直強制)', () {
      // 1. 準備
      controller.lines = ['     ', '     ', '     '];

      // 2. 操作: (0,0) から (2, 5) へドラッグ
      // 全角モードでは斜め線は廃止され、移動量の大きい軸にスナップされる
      // dx=5, dy=2. aspect=2.0. dx/aspect(2.5) > dy(2) -> 水平線になるはず
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 2;
      controller.cursorCol = 5; // VisualX=5

      // 3. 実行
      controller.drawLine(useHalfWidth: false);

      // 4. 検証
      // 水平線 (0,0) -> (0, 4) (x2は偶数補正される)
      // 距離4 / ステップ2 = 2ステップ。始点含めて3文字描画される。
      // 期待: ─── (全角線3文字)
      expect(controller.lines[0], contains('───'));
      // カーソルは (0, 6) へ
      expect(controller.cursorRow, 0);
      expect(controller.preferredVisualX, 6);
    });

    test('直線描画 drawLine (半角・左斜め -> 水平強制)', () {
      // 1. 準備
      controller.lines = ['     ', '     ', '     '];

      // 2. 操作: (2, 2) から (0, 0) へドラッグ (左上へ)
      // 半角モード
      controller.selectionOriginRow = 2;
      controller.selectionOriginCol = 2;
      controller.cursorRow = 0;
      controller.cursorCol = 0;

      // 3. 実行
      controller.drawLine(useHalfWidth: true);

      // 4. 検証
      // (2,2) -> (0,0)
      // dx=-2, dy=-2. |dx| >= |dy| なので水平線に強制される (y2=y1=2)
      // (2,2) -> (0,2) の水平線
      // 0行目、1行目は変化なし
      expect(controller.lines[0], equals('     '));
      expect(controller.lines[1], equals('     '));
      // 2行目に水平線 (VisualX 0~2)
      expect(controller.lines[2], startsWith('--'));
    });

    test('直線描画 drawLine (全角・範囲外クリッピング)', () {
      // 1. 準備
      controller.lines = ['     ', '     ', '     '];

      // 2. 操作: (0,0) から (5, 2) へドラッグ (全角モード)
      // dx=5, dy=2. 横移動が大きい -> 水平線になる
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 2;
      controller.cursorCol = 5;

      // 3. 実行
      controller.drawLine(useHalfWidth: false);

      // 4. 検証
      // 水平線 (0,0) -> (0, 4)
      expect(controller.lines[0], contains('───'));
      expect(controller.cursorRow, 0);
    });

    test('直線描画 drawLine (右から左へ水平線)', () {
      // 1. 準備
      controller.lines = ['          '];

      // 2. 操作: (0, 10) から (0, 4) へドラッグ (右から左)
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 10;
      controller.cursorRow = 0;
      controller.cursorCol = 4;

      // 3. 実行
      controller.drawLine(useHalfWidth: false);

      // 4. 検証
      // 10, 8, 6, 4 の位置に線が引かれる。
      // 期待: 4の位置から線が始まっていること (VisualX=4)
      // "    ────" (スペース4つ + 全角線4つ)
      expect(controller.lines[0], equals('    ────'));

      // カーソル位置も 4 になっていること
      expect(controller.cursorCol, 4);
    });

    test('直線描画 drawLine (極端なアスペクト比での判定)', () {
      // 1. 準備
      // 十分な広さのキャンバスを用意
      controller.lines = List.generate(5, (_) => '          ');

      // 2. 操作: 横長 (0,0) -> (1, 10)
      // dx=10 (全角5文字分), dy=1.
      // 全角モード: 横移動が大きい -> 水平線
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 1;
      controller.cursorCol = 10;

      // 3. 実行
      controller.drawLine(useHalfWidth: false);

      // 4. 検証
      // 水平線
      expect(controller.lines[0], contains('─────'));

      // 5. 操作: 縦長 (0,0) -> (4, 2)
      // dx=2 (全角1文字分), dy=4.
      // 全角モード: 縦移動が大きい -> 垂直線
      controller.lines = List.generate(5, (_) => '          '); // リセット
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 4;
      controller.cursorCol = 4; // 全角2文字分(VisualX=4)確保しないと、補正でdx=0(垂直)になってしまう

      controller.drawLine(useHalfWidth: false);

      // 垂直線
      expect(controller.lines[0], startsWith('│'));
    });

    test('直線描画 drawLine (極端なアスペクト比 -> 水平/垂直強制)', () {
      // 1. 準備
      // 十分な広さのキャンバスを用意
      controller.lines = List.generate(12, (_) => '          ');

      // 2. 操作: 横長 (0,0) -> (1, 10) 半角モード
      // dx=10, dy=1.
      // 横移動が大きい -> 水平線
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 1;
      controller.cursorCol = 10;

      // 3. 実行
      controller.drawLine(useHalfWidth: true);

      // 4. 検証
      // 水平線
      expect(controller.lines[0], startsWith('-'));

      // 5. 操作: 縦長 (0,0) -> (10, 1) 半角モード
      // dx=1, dy=10.
      controller.lines = List.generate(12, (_) => '          '); // リセット
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 10;
      controller.cursorCol =
          2; // 幅1(VisualX=1)だと補正でdx=0(垂直)になるため、幅2(VisualX=2)にする

      controller.drawLine(useHalfWidth: true);

      // 縦移動が大きい -> 垂直線
      expect(controller.lines[0], startsWith('|'));
    });

    test('L字線描画 drawElbowLine (上折れ・下折れ)', () {
      // 1. 準備
      controller.lines = List.generate(5, (_) => '          ');

      // 2. 操作: (0,0) -> (2, 4) 上折れ
      // 始点(0,0) -> 角(0,4) -> 終点(2,4)
      // 0行目: ──┐ (始点は水平線、角は┐)
      // 1行目:     │
      // 2行目:     │ (終点は垂直線)
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 2;
      controller.cursorCol = 4; // VisualX=4

      // 3. 実行
      controller.drawElbowLine(isUpperRoute: true);

      // 4. 検証
      // 始点から角までは水平線、角のみ折れ曲がり文字
      expect(controller.lines[0], contains('──┐'));
      expect(controller.lines[1], contains('    │'));
      expect(controller.lines[2], contains('    │'));

      // 5. 操作: (0,0) -> (2, 4) 下折れ
      // 始点(0,0) -> 角(2,0) -> 終点(2,4)
      // 0行目: │ (始点は垂直線)
      // 1行目: │
      // 2行目: └── (角は└、終点は水平線)
      controller.lines = List.generate(5, (_) => '          '); // リセット
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 2;
      controller.cursorCol = 4;

      // 6. 実行
      controller.drawElbowLine(isUpperRoute: false);

      // 7. 検証
      expect(controller.lines[0], startsWith('│'));
      expect(controller.lines[1], startsWith('│'));
      expect(controller.lines[2], contains('└──'));
    });

    // --- 矢印描画テスト (全パターン) ---
    // ※ UIメニューには「始点のみ」はありませんが、コントローラーのロジック確認のためテストします。

    test('全角矢印・右向き (水平)', () {
      // 1. 準備
      controller.lines = ['          '];
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 0;
      controller.cursorCol = 4;

      // 終点のみ: ──→
      controller.drawLine(useHalfWidth: false, arrowEnd: true);
      expect(controller.lines[0], contains('──→'));

      // 始点のみ: ←── (始点は進行方向と逆の矢印)
      controller.lines = ['          '];
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 0;
      controller.cursorCol = 4;
      controller.drawLine(useHalfWidth: false, arrowStart: true);
      expect(controller.lines[0], contains('←──'));

      // 両端: ←─→
      controller.lines = ['          '];
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 0;
      controller.cursorCol = 4;
      controller.drawLine(
        useHalfWidth: false,
        arrowStart: true,
        arrowEnd: true,
      );
      expect(controller.lines[0], contains('←─→'));
    });

    test('全角矢印・左向き (水平)', () {
      // 始点(0,4) -> 終点(0,0) 左へドラッグ
      // 終点のみ: ←──
      controller.lines = ['          '];
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 4;
      controller.cursorRow = 0;
      controller.cursorCol = 0;
      controller.drawLine(useHalfWidth: false, arrowEnd: true);
      expect(controller.lines[0], contains('←──'));

      // 始点のみ: ──→ (始点は右端。進行方向(左)の逆なので右矢印)
      controller.lines = ['          '];
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 4;
      controller.cursorRow = 0;
      controller.cursorCol = 0;
      controller.drawLine(useHalfWidth: false, arrowStart: true);
      expect(controller.lines[0], contains('──→'));

      // 両端: ←─→
      controller.lines = ['          '];
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 4;
      controller.cursorRow = 0;
      controller.cursorCol = 0;
      controller.drawLine(
        useHalfWidth: false,
        arrowStart: true,
        arrowEnd: true,
      );
      expect(controller.lines[0], contains('←─→'));
    });

    test('全角矢印・下向き (垂直)', () {
      // (0,0) -> (2,0)
      // 終点のみ
      controller.lines = ['  ', '  ', '  '];
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 2;
      controller.cursorCol = 0;
      controller.drawLine(useHalfWidth: false, arrowEnd: true);
      expect(controller.lines[0], startsWith('│'));
      expect(controller.lines[1], startsWith('│'));
      expect(controller.lines[2], startsWith('↓'));

      // 始点のみ
      controller.lines = ['  ', '  ', '  '];
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 2;
      controller.cursorCol = 0;
      controller.drawLine(useHalfWidth: false, arrowStart: true);
      expect(controller.lines[0], startsWith('↑'));
      expect(controller.lines[1], startsWith('│'));
      expect(controller.lines[2], startsWith('│'));

      // 両端
      controller.lines = ['  ', '  ', '  '];
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 2;
      controller.cursorCol = 0;
      controller.drawLine(
        useHalfWidth: false,
        arrowStart: true,
        arrowEnd: true,
      );
      expect(controller.lines[0], startsWith('↑'));
      expect(controller.lines[1], startsWith('│'));
      expect(controller.lines[2], startsWith('↓'));
    });

    test('全角矢印・上向き (垂直)', () {
      // (2,0) -> (0,0)
      // 終点のみ
      controller.lines = ['  ', '  ', '  '];
      controller.selectionOriginRow = 2;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 0;
      controller.cursorCol = 0;
      controller.drawLine(useHalfWidth: false, arrowEnd: true);
      expect(controller.lines[0], startsWith('↑'));
      expect(controller.lines[1], startsWith('│'));
      expect(controller.lines[2], startsWith('│'));

      // 始点のみ
      controller.lines = ['  ', '  ', '  '];
      controller.selectionOriginRow = 2;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 0;
      controller.cursorCol = 0;
      controller.drawLine(useHalfWidth: false, arrowStart: true);
      expect(controller.lines[0], startsWith('│'));
      expect(controller.lines[1], startsWith('│'));
      expect(controller.lines[2], startsWith('↓'));
    });

    // --- 半角矢印テスト ---
    test('半角矢印・右向き (水平)', () {
      // (0,0) -> (0,2) 半角2文字分
      // 終点のみ: ->
      controller.lines = ['   '];
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 0;
      controller.cursorCol = 2;
      controller.drawLine(useHalfWidth: true, arrowEnd: true);
      expect(controller.lines[0], contains('->'));

      // 始点のみ: <-
      controller.lines = ['   '];
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 0;
      controller.cursorCol = 2;
      controller.drawLine(useHalfWidth: true, arrowStart: true);
      expect(controller.lines[0], contains('<-'));

      // 両端: <->
      controller.lines = ['   '];
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 0;
      controller.cursorCol = 2;
      controller.drawLine(useHalfWidth: true, arrowStart: true, arrowEnd: true);
      expect(controller.lines[0], contains('<->'));
    });

    test('半角矢印・下向き (垂直)', () {
      // (0,0) -> (2,0)
      // 両端: A ... V (半角縦線の特例)
      controller.lines = [' ', ' ', ' '];
      controller.selectionOriginRow = 0;
      controller.selectionOriginCol = 0;
      controller.cursorRow = 2;
      controller.cursorCol = 0;
      controller.drawLine(useHalfWidth: true, arrowStart: true, arrowEnd: true);
      expect(controller.lines[0], startsWith('A'));
      expect(controller.lines[1], startsWith('|'));
      expect(controller.lines[2], startsWith('V'));
    });

    // --- タブ管理機能テスト ---
    group('タブ管理機能 (Tab Management)', () {
      test('初期状態', () {
        // デフォルトで1つのドキュメントがあるはず
        expect(controller.documents.length, 1);
        expect(controller.activeDocumentIndex, 0);
        expect(controller.lines, ['']);
      });

      test('新規タブ作成 newTab', () {
        // 1つ目のタブを編集
        controller.lines = ['Tab 1 Content'];

        // 新規タブ作成
        controller.newTab();

        // タブ数が増え、インデックスが移動していること
        expect(controller.documents.length, 2);
        expect(controller.activeDocumentIndex, 1);

        // 新しいタブは空であること
        expect(controller.lines, ['']);

        // 前のタブの内容が維持されているか確認（切り替えテスト含む）
        controller.switchTab(0);
        expect(controller.activeDocumentIndex, 0);
        expect(controller.lines, ['Tab 1 Content']);
      });

      test('タブ切り替えと編集の独立性 switchTab', () {
        // Tab 1: "Doc 1"
        controller.lines = ['Doc 1'];

        // Tab 2作成: "Doc 2"
        controller.newTab();
        controller.lines = ['Doc 2'];

        // Tab 1に戻って確認
        controller.switchTab(0);
        expect(controller.lines, ['Doc 1']);

        // Tab 2に戻って確認
        controller.switchTab(1);
        expect(controller.lines, ['Doc 2']);
      });

      test('タブを閉じる closeTab', () {
        // 3つのタブを用意
        controller.lines = ['Tab 0'];
        controller.newTab();
        controller.lines = ['Tab 1'];
        controller.newTab();
        controller.lines = ['Tab 2'];

        expect(controller.documents.length, 3);
        expect(controller.activeDocumentIndex, 2); // 現在 Tab 2

        // 真ん中のタブ(Index 1)を閉じる
        controller.closeTab(1);

        // 数が減っていること
        expect(controller.documents.length, 2);

        // 残ったタブの中身を確認 (Tab 0 と Tab 2 が残っているはず)
        controller.switchTab(0);
        expect(controller.lines, ['Tab 0']);
        controller.switchTab(1);
        expect(controller.lines, ['Tab 2']);
      });

      test('最後のタブを閉じた時の挙動', () {
        // 1つしかない状態で閉じる
        controller.closeTab(0);

        // 新しい空のタブが生成され、ドキュメント数は1のまま維持される
        expect(controller.documents.length, 1);
        expect(controller.lines, ['']);
      });
    });
  });
}
