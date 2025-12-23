import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'history_manager.dart';
import 'text_utils.dart';
import 'search_result.dart';
import 'package:free_memo_editor/file_io_helper.dart';

/// エディタの状態（データ）のみを管理するコントローラー
/// Step 1: ロジックはまだ持たず、変数のコンテナとして機能する
class EditorController extends ChangeNotifier {
  // --- 状態変数 ---
  List<String> lines = [''];
  int cursorRow = 0;
  int cursorCol = 0; // 文字数ベースのカーソル位置
  int preferredVisualX = 0; // カーソル移動時の目標VisualX
  bool isOverwriteMode = false;
  String? currentFilePath;
  bool showGrid = false; // グリッド表示フラグ
  String composingText = ""; // IME未確定文字
  int tabWidth = 4; // タブ幅 (初期値4)
  String fontFamily = "BIZ UDゴシック"; // フォント名
  double fontSize = 16.0; // フォントサイズ
  double minCanvasSize = 2000.0; // 最小キャンバスサイズ

  // 検索・置換
  List<SearchResult> searchResults = [];
  int currentSearchIndex = -1;

  // 選択範囲
  int? selectionOriginRow;
  int? selectionOriginCol;
  bool isRectangularSelection = false;

  // 履歴管理
  final HistoryManager historyManager = HistoryManager();

  bool get hasSelection =>
      selectionOriginRow != null && selectionOriginCol != null;

  // --- Settings Persistence (設定の保存) ---

  /// 設定を読み込む (アプリ起動時に呼ぶ)
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    showGrid = prefs.getBool('showGrid') ?? false;
    tabWidth = prefs.getInt('tabWidth') ?? 4;
    isOverwriteMode = prefs.getBool('isOverwriteMode') ?? false;
    fontFamily = prefs.getString('fontFamily') ?? "BIZ UDゴシック";
    fontSize = prefs.getDouble('fontSize') ?? 16.0;
    minCanvasSize = prefs.getDouble('minCanvasSize') ?? 2000.0;
    notifyListeners();
  }

  /// Bool値を保存するヘルパー
  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  /// Int値を保存するヘルパー
  Future<void> _saveInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  /// Double値を保存するヘルパー
  Future<void> _saveDouble(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
  }

  /// String値を保存するヘルパー
  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  void setFontSize(double size) {
    fontSize = size;
    _saveDouble('fontSize', size);
    notifyListeners();
  }

  void setMinCanvasSize(double size) {
    minCanvasSize = size;
    _saveDouble('minCanvasSize', size);
    notifyListeners();
  }

  // --- Search & Replace Logic ---

  /// 検索実行
  void search(String query) {
    searchResults.clear();
    currentSearchIndex = -1;

    if (query.isEmpty) {
      notifyListeners();
      return;
    }

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];
      int index = line.indexOf(query);
      while (index != -1) {
        searchResults.add(SearchResult(i, index, query.length));
        index = line.indexOf(query, index + 1);
      }
    }

    // カーソル位置に最も近い結果を選択
    if (searchResults.isNotEmpty) {
      currentSearchIndex = 0;

      // 検索基準位置の決定
      // 選択範囲がある場合はその「先頭」を基準にする（入力中のジャンプ防止）
      int baseRow = cursorRow;
      int baseCol = cursorCol;

      if (hasSelection) {
        // 選択範囲の始点（小さい方）を採用
        if (selectionOriginRow! < cursorRow ||
            (selectionOriginRow! == cursorRow &&
                selectionOriginCol! < cursorCol)) {
          baseRow = selectionOriginRow!;
          baseCol = selectionOriginCol!;
        }
      }

      for (int i = 0; i < searchResults.length; i++) {
        final result = searchResults[i];
        // 基準位置以降にある最初の結果を探す
        if (result.lineIndex > baseRow ||
            (result.lineIndex == baseRow && result.startCol >= baseCol)) {
          currentSearchIndex = i;
          break;
        }
      }
      _jumpToSearchResult(currentSearchIndex);
    }
    notifyListeners();
  }

  void nextMatch() {
    if (searchResults.isEmpty) return;
    currentSearchIndex = (currentSearchIndex + 1) % searchResults.length;
    _jumpToSearchResult(currentSearchIndex);
    notifyListeners();
  }

  void previousMatch() {
    if (searchResults.isEmpty) return;
    currentSearchIndex =
        (currentSearchIndex - 1 + searchResults.length) % searchResults.length;
    _jumpToSearchResult(currentSearchIndex);
    notifyListeners();
  }

  void _jumpToSearchResult(int index) {
    if (index < 0 || index >= searchResults.length) return;
    final result = searchResults[index];

    // 検索結果を選択状態にする
    selectionOriginRow = result.lineIndex;
    selectionOriginCol = result.startCol;
    cursorRow = result.lineIndex;
    cursorCol = result.startCol + result.length;
    isRectangularSelection = false;

    // VisualX更新
    preferredVisualX = _calcVisualX(cursorRow, cursorCol);
  }

  void replace(String query, String newText) {
    if (searchResults.isEmpty || currentSearchIndex == -1) return;

    // 現在選択中の箇所が検索結果と一致するか確認（念のため）
    final result = searchResults[currentSearchIndex];

    // 選択範囲削除 & 挿入
    saveHistory();

    // 確実に現在の検索結果を選択状態にする
    selectionOriginRow = result.lineIndex;
    selectionOriginCol = result.startCol;
    cursorRow = result.lineIndex;
    cursorCol = result.startCol + result.length;

    deleteSelection();
    insertText(newText);

    // 再検索してインデックスを維持（または次の候補へ）
    search(query);
  }

  void replaceAll(String query, String newText) {
    if (query.isEmpty) return;
    saveHistory();

    // 行ごとに置換
    for (int i = 0; i < lines.length; i++) {
      lines[i] = lines[i].replaceAll(query, newText);
    }

    // 再検索
    search(query);
  }

  void clearSearch() {
    searchResults.clear();
    currentSearchIndex = -1;
    notifyListeners();
  }

  // --- ロジック (Step 2で追加) ---

  /// 履歴保存
  void saveHistory() {
    historyManager.save(lines, cursorRow, cursorCol);
  }

  /// 指定した行・列までデータを拡張する（行追加・スペース埋め）
  void ensureVirtualSpace(int row, int col) {
    if (row >= lines.length) {
      int newLinesNeeded = row - lines.length + 1;
      for (int i = 0; i < newLinesNeeded; i++) {
        lines.add("");
      }
    }
    if (col > lines[row].length) {
      lines[row] = lines[row].padRight(col);
    }
  }

  /// テキスト挿入
  void insertText(String text) {
    if (text.isEmpty) return;

    ensureVirtualSpace(cursorRow, cursorCol);

    String currentLine = lines[cursorRow];
    String part1 = currentLine.substring(0, cursorCol);
    String part2 = currentLine.substring(cursorCol);

    if (isOverwriteMode && part2.isNotEmpty) {
      int inputVisualWidth = TextUtils.calcTextWidth(text);
      int removeLength = 0;
      int currentVisualWidth = 0;

      var iterator = part2.runes.iterator;
      while (iterator.moveNext()) {
        if (currentVisualWidth >= inputVisualWidth && removeLength > 0) {
          break;
        }
        int rune = iterator.current;
        int charWidth = (rune < 128) ? 1 : 2;
        currentVisualWidth += charWidth;
        removeLength += (rune > 0xFFFF) ? 2 : 1;
      }

      if (removeLength > 0) {
        if (part2.length >= removeLength) {
          part2 = part2.substring(removeLength);
        } else {
          part2 = "";
        }
      }
    }

    lines[cursorRow] = part1 + text + part2;
    cursorCol += text.length;

    // VisualX更新
    String newLine = lines[cursorRow];
    int safeEnd = min(cursorCol, newLine.length);
    preferredVisualX = TextUtils.calcTextWidth(newLine.substring(0, safeEnd));

    notifyListeners();
  }

  /// 選択範囲の削除
  void deleteSelection() {
    if (!hasSelection) return;

    if (isRectangularSelection) {
      _deleteRectangularSelection();
    } else {
      _deleteNormalSelection();
    }
    selectionOriginRow = null;
    selectionOriginCol = null;
    notifyListeners();
  }

  void _deleteNormalSelection() {
    int startRow = selectionOriginRow!;
    int startCol = selectionOriginCol!;
    int endRow = cursorRow;
    int endCol = cursorCol;

    if (startRow > endRow || (startRow == endRow && startCol > endCol)) {
      int t = startRow;
      startRow = endRow;
      endRow = t;
      t = startCol;
      startCol = endCol;
      endCol = t;
    }

    //  開始行が存在しない(虚空)場合は、削除するものがないのでカーソル移動のみで終了
    if (startRow >= lines.length) {
      cursorRow = startRow;
      cursorCol = startCol;
      return;
    }

    String startLine = (startRow < lines.length) ? lines[startRow] : "";
    String prefix = (startCol < startLine.length)
        ? startLine.substring(0, startCol)
        : startLine;

    String endLine = (endRow < lines.length) ? lines[endRow] : "";
    String suffix = (endCol < endLine.length) ? endLine.substring(endCol) : "";

    lines[startRow] = prefix + suffix;

    if (endRow > startRow) {
      // 削除範囲がリストの長さを超えないように制限
      int removeEndIndex = endRow + 1;
      if (removeEndIndex > lines.length) {
        removeEndIndex = lines.length;
      }
      if (removeEndIndex > startRow + 1) {
        lines.removeRange(startRow + 1, removeEndIndex);
      }
    }

    cursorRow = startRow;
    cursorCol = startCol;
  }

  void _deleteRectangularSelection() {
    int startRow = min(selectionOriginRow!, cursorRow);
    int endRow = max(selectionOriginRow!, cursorRow);

    // VisualX範囲の特定
    int originVisualX = _calcVisualX(selectionOriginRow!, selectionOriginCol!);
    int cursorVisualX = _calcVisualX(cursorRow, cursorCol);

    int minVisualX = min(originVisualX, cursorVisualX);
    int maxVisualX = max(originVisualX, cursorVisualX);

    for (int i = startRow; i <= endRow; i++) {
      if (i >= lines.length) continue;
      String line = lines[i];

      int startCol = TextUtils.getColFromVisualX(line, minVisualX);
      int endCol = TextUtils.getColFromVisualX(line, maxVisualX);

      if (startCol > endCol) {
        int t = startCol;
        startCol = endCol;
        endCol = t;
      }
      if (startCol > line.length) startCol = line.length;
      if (endCol > line.length) endCol = line.length;

      String part1 = line.substring(0, startCol);
      String part2 = line.substring(endCol);
      lines[i] = part1 + part2;
    }
    // カーソルを矩形左上に移動
    cursorRow = startRow;
    if (cursorRow < lines.length) {
      cursorCol = TextUtils.getColFromVisualX(lines[cursorRow], minVisualX);
      if (cursorCol > lines[cursorRow].length) {
        cursorCol = lines[cursorRow].length;
      }
    }
  }

  /// 矩形選択範囲を指定文字で置換
  void replaceRectangularSelection(String text) {
    if (!hasSelection) return;

    int startRow = min(selectionOriginRow!, cursorRow);
    int endRow = max(selectionOriginRow!, cursorRow);

    // VisualX範囲の特定
    int originVisualX = _calcVisualX(selectionOriginRow!, selectionOriginCol!);
    int cursorVisualX = _calcVisualX(cursorRow, cursorCol);

    int minVisualX = min(originVisualX, cursorVisualX);
    int maxVisualX = max(originVisualX, cursorVisualX);

    // カーソル位置更新用
    int newCursorRow = startRow;
    int newCursorCol = 0;

    for (int i = startRow; i <= endRow; i++) {
      if (i >= lines.length) continue;
      String line = lines[i];

      int startCol = TextUtils.getColFromVisualX(line, minVisualX);
      int endCol = TextUtils.getColFromVisualX(line, maxVisualX);

      if (startCol > endCol) {
        int t = startCol;
        startCol = endCol;
        endCol = t;
      }
      if (startCol > line.length) startCol = line.length;
      if (endCol > line.length) endCol = line.length;

      String part1 = line.substring(0, startCol);
      String part2 = line.substring(endCol);
      lines[i] = part1 + text + part2;

      // カーソルは開始行の、挿入した文字の後ろに置く
      if (i == startRow) {
        newCursorCol = part1.length + text.length;
      }
    }

    cursorRow = newCursorRow;
    cursorCol = newCursorCol;

    // 選択解除
    selectionOriginRow = null;
    selectionOriginCol = null;

    // VisualX更新
    if (cursorRow < lines.length) {
      String line = lines[cursorRow];
      if (cursorCol > line.length) cursorCol = line.length;
      preferredVisualX = TextUtils.calcTextWidth(line.substring(0, cursorCol));
    }

    notifyListeners();
  }

  // --- History ---
  void undo() {
    final entry = historyManager.undo(lines, cursorRow, cursorCol);
    if (entry != null) {
      _applyHistoryEntry(entry);
    }
  }

  void redo() {
    final entry = historyManager.redo(lines, cursorRow, cursorCol);
    if (entry != null) {
      _applyHistoryEntry(entry);
    }
  }

  void _applyHistoryEntry(HistoryEntry entry) {
    lines = List.from(entry.lines);
    cursorRow = entry.cursorRow;
    cursorCol = entry.cursorCol;
    selectionOriginRow = null;
    selectionOriginCol = null;
    preferredVisualX = _calcVisualX(cursorRow, cursorCol);
    notifyListeners();
  }

  // --- Selection ---
  void selectAll() {
    selectionOriginRow = 0;
    selectionOriginCol = 0;
    cursorRow = lines.length - 1;
    cursorCol = lines.last.length;
    isRectangularSelection = false;
    preferredVisualX = _calcVisualX(cursorRow, cursorCol);
    notifyListeners();
  }

  // --- Indentation ---
  void indent() {
    saveHistory();
    deleteSelection();
    insertText(' ' * tabWidth);
  }

  void setTabWidth(int width) {
    tabWidth = width;
    _saveInt('tabWidth', tabWidth);
    notifyListeners();
  }

  // --- File I/O ---
  Future<void> openFile() async {
    try {
      String? path = await FileIOHelper.instance.pickFilePath();
      if (path != null) {
        String content = await FileIOHelper.instance.readFileAsString(path);
        saveHistory();
        currentFilePath = path;
        content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
        lines = content.split('\n');
        if (lines.isEmpty) {
          lines = [''];
        }
        cursorRow = 0;
        cursorCol = 0;
        preferredVisualX = 0;
        selectionOriginRow = null;
        selectionOriginCol = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error opening file: $e');
    }
  }

  Future<String?> saveFile() async {
    if (currentFilePath == null) {
      return await saveAsFile();
    }
    try {
      String content = lines.join('\n');
      await FileIOHelper.instance.writeStringToFile(currentFilePath!, content);
      return currentFilePath;
    } catch (e) {
      debugPrint('Error saving file: $e');
      return null;
    }
  }

  Future<String?> saveAsFile() async {
    try {
      String? outputFile = await FileIOHelper.instance.saveFilePath();
      if (outputFile != null) {
        currentFilePath = outputFile;
        String content = lines.join('\n');
        await FileIOHelper.instance.writeStringToFile(outputFile, content);
        notifyListeners();
        return outputFile;
      }
    } catch (e) {
      debugPrint('Error saving file: $e');
    }
    return null;
  }

  // --- Clipboard ---
  Future<void> copySelection() async {
    if (!hasSelection) return;

    StringBuffer buffer = StringBuffer();

    if (isRectangularSelection) {
      int startRow = min(selectionOriginRow!, cursorRow);
      int endRow = max(selectionOriginRow!, cursorRow);
      int originVisualX = _calcVisualX(
        selectionOriginRow!,
        selectionOriginCol!,
      );
      int cursorVisualX = _calcVisualX(cursorRow, cursorCol);
      int minVisualX = min(originVisualX, cursorVisualX);
      int maxVisualX = max(originVisualX, cursorVisualX);

      for (int i = startRow; i <= endRow; i++) {
        String line = (i < lines.length) ? lines[i] : "";
        int startCol = TextUtils.getColFromVisualX(line, minVisualX);
        int endCol = TextUtils.getColFromVisualX(line, maxVisualX);

        if (startCol > endCol) {
          int temp = startCol;
          startCol = endCol;
          endCol = temp;
        }
        String extracted = "";
        if (startCol < line.length) {
          int safeEnd = min(endCol, line.length);
          extracted = line.substring(startCol, safeEnd);
        }
        buffer.writeln(extracted);
      }
    } else {
      int startRow = selectionOriginRow!;
      int startCol = selectionOriginCol!;
      int endRow = cursorRow;
      int endCol = cursorCol;

      if (startRow > endRow || (startRow == endRow && startCol > endCol)) {
        int t = startRow;
        startRow = endRow;
        endRow = t;
        t = startCol;
        startCol = endCol;
        endCol = t;
      }

      for (int i = startRow; i <= endRow; i++) {
        if (i >= lines.length) break;
        String line = lines[i];
        int s = (i == startRow) ? startCol : 0;
        int e = (i == endRow) ? endCol : line.length;
        if (s > line.length) s = line.length;
        if (e > line.length) e = line.length;
        if (s < 0) s = 0;
        if (e < 0) e = 0;

        buffer.write(line.substring(s, e));
        if (i < endRow) {
          buffer.write('\n');
        }
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
  }

  Future<void> pasteNormal() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null) return;

    String text = data.text!.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    List<String> parts = text.split('\n');

    ensureVirtualSpace(cursorRow, cursorCol);
    String line = lines[cursorRow];
    String prefix = line.substring(0, cursorCol);

    if (!isOverwriteMode) {
      String suffix = line.substring(cursorCol);
      if (parts.length == 1) {
        lines[cursorRow] = prefix + parts[0] + suffix;
        cursorCol += parts[0].length;
      } else {
        lines[cursorRow] = prefix + parts.first;
        for (int i = 1; i < parts.length - 1; i++) {
          lines.insert(cursorRow + i, parts[i]);
        }
        lines.insert(cursorRow + parts.length - 1, parts.last + suffix);
        cursorRow += parts.length - 1;
        cursorCol = parts.last.length;
      }
    } else {
      String firstPartToPaste = parts.first;
      int pasteVisualWidth = TextUtils.calcTextWidth(firstPartToPaste);
      int currentVisualX = TextUtils.calcTextWidth(prefix);
      int targetEndVisualX = currentVisualX + pasteVisualWidth;
      int overwriteEndCol = TextUtils.getColFromVisualX(line, targetEndVisualX);
      String suffix = "";
      if (overwriteEndCol < line.length) {
        suffix = line.substring(overwriteEndCol);
      }
      if (parts.length == 1) {
        lines[cursorRow] = prefix + firstPartToPaste + suffix;
        cursorCol += firstPartToPaste.length;
      } else {
        lines[cursorRow] = prefix + firstPartToPaste;
        for (int i = 1; i < parts.length - 1; i++) {
          lines.insert(cursorRow + i, parts[i]);
        }
        lines.insert(cursorRow + parts.length - 1, parts.last + suffix);
        cursorRow += parts.length - 1;
        cursorCol = parts.last.length;
      }
    }

    preferredVisualX = _calcVisualX(cursorRow, cursorCol);
    selectionOriginRow = null;
    selectionOriginCol = null;
    notifyListeners();
  }

  Future<void> pasteRectangular() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null || data.text!.isEmpty) return;

    final List<String> pasteLines = const LineSplitter().convert(data.text!);
    if (pasteLines.isEmpty) return;

    int startRow = cursorRow;
    String currentLine = (cursorRow < lines.length) ? lines[cursorRow] : "";
    String textBefore = "";
    if (cursorCol <= currentLine.length) {
      textBefore = currentLine.substring(0, cursorCol);
    } else {
      textBefore = currentLine + (' ' * (cursorCol - currentLine.length));
    }
    int targetVisualX = TextUtils.calcTextWidth(textBefore);

    for (int i = 0; i < pasteLines.length; i++) {
      int targetRow = startRow + i;
      String textToPaste = pasteLines[i].replaceAll(RegExp(r'[\r\n]'), '');
      int pasteWidth = TextUtils.calcTextWidth(textToPaste);

      ensureVirtualSpace(targetRow, 0);
      String line = lines[targetRow];
      int insertIndex = TextUtils.getColFromVisualX(line, targetVisualX);

      if (insertIndex > line.length) {
        ensureVirtualSpace(targetRow, insertIndex);
        line = lines[targetRow];
      }

      if (!isOverwriteMode) {
        String part1 = line.substring(0, insertIndex);
        String part2 = line.substring(insertIndex);
        lines[targetRow] = part1 + textToPaste + part2;
      } else {
        int endVisualX = targetVisualX + pasteWidth;
        int endIndex = TextUtils.getColFromVisualX(line, endVisualX);
        if (endIndex > line.length) endIndex = line.length;
        String part1 = line.substring(0, insertIndex);
        String part2 = line.substring(endIndex);
        lines[targetRow] = part1 + textToPaste + part2;
      }
    }
    cursorRow = startRow + pasteLines.length - 1;
    String lastPasted = pasteLines.last.replaceAll(RegExp(r'[\r\n]'), '');
    int lastWidth = TextUtils.calcTextWidth(lastPasted);
    preferredVisualX = targetVisualX + lastWidth;
    if (cursorRow < lines.length) {
      cursorCol = TextUtils.getColFromVisualX(
        lines[cursorRow],
        preferredVisualX,
      );
    }
    selectionOriginRow = null;
    selectionOriginCol = null;
    notifyListeners();
  }

  // ヘルパー: VisualX計算
  int _calcVisualX(int row, int col) {
    // 行が存在しない場合も、空行として扱いスペース計算を行う
    String line = (row < lines.length) ? lines[row] : "";
    String text;
    if (col <= line.length) {
      text = line.substring(0, col);
    } else {
      text = line + (' ' * (col - line.length));
    }
    return TextUtils.calcTextWidth(text);
  }

  // --- Cursor Movement (Step 1.2) ---

  void _handleSelectionOnMove(bool isShift, bool isAlt) {
    if (isShift) {
      selectionOriginRow ??= cursorRow;
      selectionOriginCol ??= cursorCol;
      isRectangularSelection = isAlt;
    } else {
      selectionOriginRow = null;
      selectionOriginCol = null;
    }
  }

  void moveCursor(int rowMove, int colMove, bool isShift, bool isAlt) {
    _handleSelectionOnMove(isShift, isAlt);

    // Horizontal Move
    if (colMove != 0) {
      if (isAlt) {
        if (colMove > 0) {
          // Alt + Right: 虚空へ移動 (行跨ぎなし)
          cursorCol += colMove;
        } else {
          // Alt + Left: 行頭なら前の行へ (行跨ぎあり)
          if (cursorCol > 0) {
            cursorCol += colMove;
          } else if (cursorRow > 0) {
            cursorRow--;
            cursorCol = lines[cursorRow].length;
          }
        }
        if (cursorCol < 0) cursorCol = 0;
      } else {
        int currentLineLength = (cursorRow < lines.length)
            ? lines[cursorRow].length
            : 0;
        if (colMove > 0) {
          if (cursorCol < currentLineLength) {
            cursorCol++;
          } else if (cursorRow < lines.length - 1) {
            cursorRow++;
            cursorCol = 0;
          }
        } else {
          if (cursorCol > 0) {
            cursorCol--;
          } else if (cursorRow > 0) {
            cursorRow--;
            cursorCol = lines[cursorRow].length;
          }
        }
      }

      // Update VisualX
      if (cursorRow < lines.length) {
        String line = lines[cursorRow];
        String textUpToCursor;
        if (cursorCol <= line.length) {
          textUpToCursor = line.substring(0, cursorCol);
        } else {
          textUpToCursor = line + (" " * (cursorCol - line.length));
        }
        preferredVisualX = TextUtils.calcTextWidth(textUpToCursor);
      }
    }

    // Vertical Move
    if (rowMove != 0) {
      if (isAlt) {
        cursorRow += rowMove;
        if (cursorRow < 0) cursorRow = 0;
      } else {
        cursorRow += rowMove;
        if (cursorRow < 0) cursorRow = 0;
        if (cursorRow >= lines.length) cursorRow = lines.length - 1;
      }

      if (cursorRow < lines.length) {
        String line = lines[cursorRow];
        int lineWidth = TextUtils.calcTextWidth(line);

        if (isAlt && preferredVisualX > lineWidth) {
          int gap = preferredVisualX - lineWidth;
          cursorCol = line.length + gap;
        } else {
          cursorCol = TextUtils.getColFromVisualX(line, preferredVisualX);
        }
      } else {
        cursorCol = preferredVisualX;
      }
    }

    notifyListeners();
  }

  // --- Key Handling (Step 1.1) ---
  KeyEventResult handleKeyPress(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final PhysicalKeyboardKey physicalKey = event.physicalKey;
    bool isControl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    bool isShift = HardwareKeyboard.instance.isShiftPressed;
    bool isAlt = HardwareKeyboard.instance.isAltPressed;

    // --- Arrow Keys ---
    if (physicalKey == PhysicalKeyboardKey.arrowLeft) {
      moveCursor(0, -1, isShift, isAlt);
      return KeyEventResult.handled;
    }
    if (physicalKey == PhysicalKeyboardKey.arrowRight) {
      moveCursor(0, 1, isShift, isAlt);
      return KeyEventResult.handled;
    }
    if (physicalKey == PhysicalKeyboardKey.arrowUp) {
      moveCursor(-1, 0, isShift, isAlt);
      return KeyEventResult.handled;
    }
    if (physicalKey == PhysicalKeyboardKey.arrowDown) {
      moveCursor(1, 0, isShift, isAlt);
      return KeyEventResult.handled;
    }

    // --- Ctrl/Cmd Key Combos ---
    if (isControl) {
      if (physicalKey == PhysicalKeyboardKey.keyC) {
        copySelection();
        return KeyEventResult.handled;
      }
      if (physicalKey == PhysicalKeyboardKey.keyZ) {
        undo();
        return KeyEventResult.handled;
      }
      if (physicalKey == PhysicalKeyboardKey.keyY) {
        redo();
        return KeyEventResult.handled;
      }
      if (physicalKey == PhysicalKeyboardKey.keyV) {
        if (hasSelection) {
          saveHistory();
          deleteSelection();
        }
        if (isAlt) {
          pasteRectangular();
        } else {
          pasteNormal();
        }
        return KeyEventResult.handled;
      }
      if (physicalKey == PhysicalKeyboardKey.keyS) {
        bool isShift = HardwareKeyboard.instance.isShiftPressed;
        if (isShift) {
          saveAsFile();
        } else {
          saveFile();
        }
        return KeyEventResult.handled;
      }
      if (physicalKey == PhysicalKeyboardKey.keyA) {
        selectAll();
        return KeyEventResult.handled;
      }
    }

    // --- Other Special Keys ---
    switch (physicalKey) {
      case PhysicalKeyboardKey.tab:
        indent();
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.enter:
        saveHistory();
        deleteSelection();
        final currentLine = lines[cursorRow];
        final part1 = currentLine.substring(0, cursorCol);
        final part2 = currentLine.substring(cursorCol);
        lines[cursorRow] = part1;
        lines.insert(cursorRow + 1, part2);
        cursorRow++;
        cursorCol = 0;
        notifyListeners();
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.backspace:
        saveHistory();
        if (hasSelection) {
          deleteSelection();
          preferredVisualX = _calcVisualX(cursorRow, cursorCol);
          return KeyEventResult.handled;
        }

        // 行が存在しない(虚空行)場合
        if (cursorRow >= lines.length) {
          if (cursorCol > 0) {
            cursorCol--;
          } else if (cursorRow > 0) {
            cursorRow--;
            // 前の行が存在すればその末尾へ、なければ0へ
            cursorCol = (cursorRow < lines.length)
                ? lines[cursorRow].length
                : 0;
          }
          preferredVisualX = _calcVisualX(cursorRow, cursorCol);
          notifyListeners();
          return KeyEventResult.handled;
        }

        final currentLine = lines[cursorRow];

        // カーソルが行末より右にある(行内虚空)場合
        if (cursorCol > currentLine.length) {
          cursorCol--;
        } else {
          // 実体がある場所での削除
          if (cursorCol > 0) {
            final part1 = currentLine.substring(0, cursorCol - 1);
            final part2 = currentLine.substring(cursorCol);
            lines[cursorRow] = part1 + part2;
            cursorCol--;
          } else if (cursorRow > 0) {
            final lineToAppend = lines[cursorRow];
            final prevLineLength = lines[cursorRow - 1].length;
            lines[cursorRow - 1] += lineToAppend;
            lines.removeAt(cursorRow);
            cursorRow--;
            cursorCol = prevLineLength;
          }
        }
        preferredVisualX = _calcVisualX(cursorRow, cursorCol);
        notifyListeners();
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.delete:
        saveHistory();
        if (hasSelection) {
          deleteSelection();
          preferredVisualX = _calcVisualX(cursorRow, cursorCol);
          return KeyEventResult.handled;
        }

        // 行が存在しない場合は何もしない
        if (cursorRow >= lines.length) return KeyEventResult.handled;

        final currentLine = lines[cursorRow];

        // カーソルが行末以降にある場合
        if (cursorCol >= currentLine.length) {
          // 次の行があれば吸い上げる（結合する）
          if (cursorRow < lines.length - 1) {
            // 現在行をカーソル位置までスペースで埋める
            if (cursorCol > currentLine.length) {
              lines[cursorRow] = currentLine.padRight(cursorCol);
            }
            // 次の行を結合
            lines[cursorRow] += lines[cursorRow + 1];
            lines.removeAt(cursorRow + 1);
          }
        } else {
          // 通常の文字削除
          final part1 = currentLine.substring(0, cursorCol);
          final part2 = (cursorCol + 1 < currentLine.length)
              ? currentLine.substring(cursorCol + 1)
              : '';
          lines[cursorRow] = part1 + part2;
        }
        preferredVisualX = _calcVisualX(cursorRow, cursorCol);
        notifyListeners();
        return KeyEventResult.handled;

      case PhysicalKeyboardKey.insert:
        isOverwriteMode = !isOverwriteMode;
        _saveBool('isOverwriteMode', isOverwriteMode);
        notifyListeners();
        return KeyEventResult.handled;
    }

    // この段階では、矢印キーや文字入力はまだ処理しない
    return KeyEventResult.ignored;
  }

  // --- UI Event Handling (Step 2) ---

  /// 選択解除
  void clearSelection() {
    selectionOriginRow = null;
    selectionOriginCol = null;
    notifyListeners();
  }

  /// タップ時のカーソル移動処理
  void handleTap(Offset localPosition, double charWidth, double lineHeight) {
    if (charWidth == 0 || lineHeight == 0) return;

    int clickedVisualX = (localPosition.dx / charWidth).round();
    int clickedRow = (localPosition.dy / lineHeight).floor();

    cursorRow = max(0, clickedRow);

    String currentLine = "";
    if (cursorRow < lines.length) {
      currentLine = lines[cursorRow];
    }

    int lineVisualWidth = TextUtils.calcTextWidth(currentLine);

    if (clickedVisualX <= lineVisualWidth) {
      cursorCol = TextUtils.getColFromVisualX(currentLine, clickedVisualX);
    } else {
      int gap = clickedVisualX - lineVisualWidth;
      cursorCol = currentLine.length + gap;
    }

    preferredVisualX = clickedVisualX;
    notifyListeners();
  }

  /// ドラッグ開始時の処理
  void handlePanStart(
    Offset localPosition,
    double charWidth,
    double lineHeight,
    bool isAltPressed,
  ) {
    handleTap(localPosition, charWidth, lineHeight);
    selectionOriginRow = cursorRow;
    selectionOriginCol = cursorCol;
    isRectangularSelection = isAltPressed;
    notifyListeners();
  }

  // --- Input & State Management (Step 3) ---

  void toggleGrid() {
    showGrid = !showGrid;
    _saveBool('showGrid', showGrid);
    notifyListeners();
  }

  void updateComposingText(String text) {
    composingText = text;
    notifyListeners();
  }

  /// 文字入力処理（履歴保存、選択削除、挿入を統合）
  void input(String text) {
    if (text.isEmpty) return;

    saveHistory();

    if (isRectangularSelection && selectionOriginRow != null) {
      replaceRectangularSelection(text);
    } else {
      deleteSelection();
      insertText(text); // insertText内でensureVirtualSpaceが呼ばれる
    }
  }
}
