# 開発ログ

## [2024-05-21] タブ終了時のアプリ終了処理とUndo修正

### 1. 要求
* 最後のタブを閉じた際、新規タブを作成するのではなくアプリを終了させたい。
* 矩形貼り付け等の操作後にUndoを行うと、貼り付け前の状態まで戻ってしまう問題を修正したい。

### 2. 方針
* **タブ終了処理**: `_handleCloseTab` で残りタブ数が1枚の場合、`windowManager.close()` を呼び出す。未保存時はダイアログで確認し、「保存しない」選択時はフラグをクリアして終了する。
* **Undo修正**: `pasteNormal`, `pasteRectangular` メソッド内で、ドキュメント変更直前に `saveHistory()` を呼び出すように修正する。

### 3. 説明
* 最後のタブを閉じる挙動を一般的なエディタ（VSCode等）の挙動に合わせた。
* 貼り付け操作が履歴スタックに積まれていなかったため、明示的に保存することでUndoが正しく機能するようにした。

### 4. 変更内容

#### `lib/editor_page.dart`
* `_handleCloseTab` に終了判定ロジックを追加。

```dart
    // 最後のタブの場合、アプリを終了する
    if (_controller.documents.length == 1) {
      final doc = _controller.documents[index];
      // ... (未保存確認ダイアログ) ...
      if (result == 1) {
        // 保存せずに終了
        doc.isDirty = false; // 終了処理で再確認されないようフラグクリア
        await windowManager.close();
      }
      // ...
      return;
    }
```

#### `lib/editor_controller.dart`
* `pasteNormal`, `pasteRectangular` に `saveHistory()` を追加。

```dart
    final List<String> pasteLines = const LineSplitter().convert(data.text!);
    if (pasteLines.isEmpty) return;

    saveHistory(); // ★追加: 変更前に履歴保存
```

---

## [2024-05-21] ファイルのドラッグ＆ドロップ対応

### 1. 要求
* エクスプローラー等からファイルをドラッグ＆ドロップして開けるようにしたい。

### 2. 方針
* `desktop_drop` パッケージを導入し、`Scaffold` を `DropTarget` でラップしてドロップイベントを検知する。
* ドロップされたファイルパスを取得し、既存のファイルオープンロジック（重複チェック含む）を利用して開く。

### 3. 説明
* 複数ファイルの同時ドロップにも対応し、順次新しいタブで開くように実装した。
* 既に開いているファイルがドロップされた場合は、既存ロジック同様にリロード確認を行う。

### 4. 変更内容

#### `lib/editor_page.dart`
* `desktop_drop` をインポートし、`_buildScaffold` で `DropTarget` を追加。`_handleDroppedFiles` メソッドを実装。

---

## [2024-05-21] タブバーのスクロール対応

### 1. 要求
* 開いているファイルが多数になると、タブが隠れてクリックできなくなる問題を解消したい。

### 2. 方針
* タブバーの左右にスクロール用の矢印ボタンを追加する。
* タブバー上でのマウスホイール操作（縦スクロール）を横スクロールに変換して適用する。

### 3. 説明
* `ScrollController` をタブバーの `ListView` に適用し、ボタン操作やホイールイベントで制御できるようにした。
* `Listener` ウィジェットで `PointerScrollEvent` を検知し、直感的なスクロール操作を実現した。

### 4. 変更内容

#### `lib/editor_page.dart`
* `_tabScrollController` を追加し、`_buildTabBar` 内で矢印ボタンとホイール検知ロジックを実装。

---

## [2024-05-21] テスト環境の整備とロジック検証

### 1. 要求
* テストがハングアップする問題を解消し、Undo/Redoやタブ終了処理のロジックを検証したい。

### 2. 方針
* **モック化**: `window_manager` (アプリ終了) や `Clipboard` (コピペ) などの外部依存をモック化し、テスト環境で動作するようにする。
* **ファイルI/O**: テスト時は同期処理を行う `MockFileIOHelper` を使用し、非同期待ちによるタイムアウトを防ぐ。
* **テスト追加**: 矩形貼り付けのUndo/Redo、タブ終了時の挙動確認テストを追加。

### 3. 説明
* `MethodChannel` のハンドラをオーバーライドすることで、ネイティブプラグインの呼び出しをテスト内でインターセプト・制御可能にした。
* これにより、CI/CD等でも安定して実行可能なテスト基盤が整った。

### 4. 変更内容
* `test/editor_logic_test.dart`: `window_manager`, `Clipboard` のモック設定を追加。Undo/Redoテストケースを追加。
* `lib/file_io_helper.dart`: ファイル存在確認・削除メソッドを追加（テスト容易性向上）。
* `lib/editor_document.dart`: 直接の `File` クラス利用を廃止し、Helper経由に変更。

---

## [2024-05-21] D&D機能のテスト追加とデッドロック解消

### 1. 要求
* ドラッグ＆ドロップによるファイルオープン処理（新規・重複・複数）をテストで検証したい。
* ダイアログが表示されるテストケースで発生するデッドロック（ハングアップ）を解消したい。

### 2. 方針
* **テスト用フック**: `EditorPage` に `handleDroppedFilesForTesting` を追加し、テストコードからD&Dロジックを直接呼び出せるようにする。
* **非同期制御**: ダイアログが表示される処理を `await` せずに `Future` として保持し、テストコード側でダイアログ操作を行ってから `await` することでデッドロックを回避する。

### 3. 説明
* `cross_file` パッケージの `XFile` を使用したD&Dシミュレーションテストを実装。
* 重複ファイルドロップ時の「キャンセル」「読み直す」の挙動を検証可能にした。

### 4. 変更内容
* `lib/editor_page.dart`: テスト用メソッド `handleDroppedFilesForTesting` を追加。
* `test/editor_logic_test.dart`: `Drag & Drop Logic` テストケースを追加。

---
---
---

### 202X-XX-XX
## [202X-XX-XX] 図形機能のバグ修正とフォーマット機能のテスト

### 1. 要求
* `Drawing Logic` テストにおいて、図形の移動・リサイズ・Undo操作が失敗する問題を修正したい。
* `Format Logic` テストにおいて、`drawBox` が正しく描画されない問題を修正したい。

### 2. 方針
* **図形移動/リサイズ**: テストコード側のドラッグ操作シミュレーションを改善し、`onPanStart` が確実に発火するように微小移動を追加する。
* **Undo/Redo**: `saveHistory` メソッドで図形リストをディープコピーするように修正し、履歴データの汚染を防ぐ。また、保存タイミングを操作開始時（変更前）に変更する。
* **Draw Box**: テストデータの左端にパディングを追加し、枠線描画用のスペースを確保する。

### 3. 説明
* テスト環境特有のジェスチャ認識の問題と、参照渡しによる履歴汚染という実装上のバグを解消した。
* これにより、図形編集機能の信頼性が向上し、テストによる回帰防止が可能になった。

### 4. 変更内容

#### `lib/editor_document.dart`
* `saveHistory`: `drawings` リストを `d.copy()` でディープコピーして保存するように変更。
* `handlePanStart`: 操作開始時に `saveHistory()` を呼び出すように変更。
* `handlePanEnd`: `saveHistory()` の呼び出しを削除。

#### `test/editor_logic_test.dart`
* `Drawing Logic`: ドラッグ操作に `moveBy(Offset(10, 10))` を追加し、ジェスチャ認識を安定化。
* `Format Logic`: `drawBox` テスト用のテキストデータに左パディングを追加。

## [202X-XX-XX] Line & Arrow Logic テストの修正

### 1. 要求
* `Line & Arrow Logic` テストにおいて、矢印描画の検証が失敗する問題を修正したい。

### 2. 方針
* **テストコード修正**: 矢印描画テスト（上書き）において、直前の操作で全角文字が挿入されたことにより、論理座標（col）と描画座標（VisualX）の対応が変化していたため、`cursorCol` の指定値を修正する。

### 3. 説明
* 全角文字（幅2）が含まれる行では、文字数（col）と見た目の幅（VisualX）が一致しない。
* テストコードで固定値 `col=6` を指定していたが、全角線描画後は `col=4` が `VisualX=6` に相当するため、これを修正した。

### 4. 変更内容

#### `test/editor_logic_test.dart`
* `Line & Arrow Logic` テストケース内の `cursorCol` 指定を `6` から `4` に変更。

## [202X-XX-XX] Line & Arrow Logic テストの追加 (Lower Route)

### 1. 要求
* `Line & Arrow Logic` テストにおいて、L字線の下折れ（Lower Route）パターンの検証が不足していたため追加したい。

### 2. 方針
* **テストコード追加**: 上折れ（Upper Route）と同様の座標を使用し、`isUpperRoute: false` で描画した場合の形状を検証するテストケースを追加する。

### 3. 説明
* 上折れだけでなく、下折れの描画ロジックも正しく機能していることを保証する。

### 4. 変更内容

#### `test/editor_logic_test.dart`
* `Line & Arrow Logic` テストケース内に、下折れ（Lower Route）の検証を追加。

## [202X-XX-XX] Line & Arrow Logic テストの修正 (Lower Route期待値)

### 1. 要求
* `Line & Arrow Logic` テストにおいて、L字線（Lower Route）の検証で期待値の記述ミスがありテストが失敗するため修正したい。

### 2. 方針
* **テストコード修正**: 下折れ（Lower Route）の底辺部分の描画結果に対する期待値を、実際の描画ロジック（3文字分）に合わせて修正する。

### 3. 説明
* 座標 `(2, 2)` から `(2, 6)` への水平線は、始点・中間・終点の3ポイントで構成されるため、文字数は3文字（`└──`）となるのが正しい。
* テストコードの期待値が `└───` （4文字）となっていたため修正した。

### 4. 変更内容

#### `test/editor_logic_test.dart`
* `Line & Arrow Logic` テストケース内の `expect` 文を修正。
