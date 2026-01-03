import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_memo_editor/editor_page.dart';
import 'package:free_memo_editor/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  testWidgets('View menu toggles visibility of UI elements', (
    WidgetTester tester,
  ) async {
    // 1. アプリ（EditorPage）をテスト環境で起動
    // 多言語対応のため MaterialApp でラップする
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en', ''), Locale('ja', '')],
        locale: Locale('en', ''), // テストは英語環境で実施
        home: EditorPage(),
      ),
    );

    // 2. 初期状態の確認: すべて表示されているはず
    // find.byKey で先ほど付けた名札を探す
    expect(find.byKey(const Key('lineNumberArea')), findsOneWidget);
    expect(find.byKey(const Key('rulerArea')), findsOneWidget);
    expect(find.byKey(const Key('minimapArea')), findsOneWidget);

    // --- 行番号の非表示テスト ---
    // Viewメニューを開く
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle(); // アニメーション完了待ち

    // "Show Line Numbers" をタップしてチェックを外す
    await tester.tap(find.text('Show Line Numbers'));
    await tester.pumpAndSettle(); // 再描画待ち

    // 行番号エリアが消えていることを確認 (findsNothing)
    expect(find.byKey(const Key('lineNumberArea')), findsNothing);

    // --- ルーラーの非表示テスト ---
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Column Ruler'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rulerArea')), findsNothing);

    // --- ミニマップの非表示テスト ---
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Minimap'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('minimapArea')), findsNothing);

    // --- 再表示テスト (行番号だけ戻してみる) ---
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Line Numbers'));
    await tester.pumpAndSettle();

    // 復活していることを確認
    expect(find.byKey(const Key('lineNumberArea')), findsOneWidget);
  });
}
