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
---
---