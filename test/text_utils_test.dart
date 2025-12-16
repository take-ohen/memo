import 'package:flutter_test/flutter_test.dart';
// プロジェクト名に合わせてインポートパスを修正してください
// 例: import 'package:flutter_freememo/text_utils.dart';
// わからない場合は、lib/text_utils.dart の中身が見えるように相対パスなどで調整します
// ここでは簡易的に相対パスのイメージで書きますが、通常は package:アプリ名/... です
import 'package:free_memo_editor/text_utils.dart';

void main() {
  group('TextUtils Logic Tests', () {
    // 1. 文字幅計算のテスト
    test('calcTextWidth should calculate correct width', () {
      // 半角のみ
      expect(TextUtils.calcTextWidth('abc'), 3);
      // 全角のみ
      expect(TextUtils.calcTextWidth('あいう'), 6);
      // 混在
      expect(TextUtils.calcTextWidth('aあbい'), 6); // 1+2+1+2 = 6
      // 空文字
      expect(TextUtils.calcTextWidth(''), 0);
    });

    // 2. 座標からカーソル位置(col)を逆算するロジックのテスト
    // ※ 現在このロジックは EditorPage内に _getColFromVisualX として存在していますが、
    //    テスト可能なように TextUtils に移動させることを推奨します。
    //    もし移動済みなら以下のテストが有効になります。

    test('getColFromVisualX should return correct index', () {
      const line = 'aあb'; // 幅: 1, 2, 1 => 累積: 1, 3, 4

      expect(TextUtils.getColFromVisualX(line, 1), 1);
      expect(TextUtils.getColFromVisualX(line, 3), 2);
      expect(TextUtils.getColFromVisualX(line, 4), 3);

      // 'a'の真ん中あたり -> 0 ('a'の前) or 1 ('a'の後)?
      // ロジック依存ですが、今回は「近い方」または「超えたら次」

      // 0.5 (aの前半) -> index 0
      // 1.5 (あ の前半) -> index 1
      // 2.5 (あ の後半) -> index 1 or 2 (ロジックによる)
    });
  });
}
