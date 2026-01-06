import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'history_manager.dart';
import 'text_utils.dart';
import 'search_result.dart';
import 'file_io_helper.dart';

enum NewLineType {
  lf,
  crlf,
  cr;

  String get label {
    switch (this) {
      case NewLineType.lf:
        return 'LF';
      case NewLineType.crlf:
        return 'CRLF';
      case NewLineType.cr:
        return 'CR';
    }
  }
}

/// 1つのドキュメント（ファイル）の状態と編集ロジックを管理するクラス
class EditorDocument extends ChangeNotifier {
  // --- 状態変数 ---
  List<String> lines = [''];
  int cursorRow = 0;
  int cursorCol = 0;
  int preferredVisualX = 0;
  bool isOverwriteMode = false;
  String? currentFilePath;
  String composingText = "";
  bool isDirty = false;
  Encoding currentEncoding = utf8;
  NewLineType newLineType = NewLineType.lf;

  // 自動生成されたタイトル
  static int _untitledCounter = 1;
  late final String _defaultTitle;

  EditorDocument() {
    _defaultTitle = 'Untitled-${_untitledCounter++}';
  }

  // 検索・置換
  List<SearchResult> searchResults = [];
  int currentSearchIndex = -1;

  // 選択範囲
  int? selectionOriginRow;
  int? selectionOriginCol;
  bool isRectangularSelection = false;

  // 履歴管理
  final HistoryManager historyManager = HistoryManager();

  // 設定値（Controllerから渡される、またはデフォルト）
  int tabWidth = 4;

  bool get hasSelection =>
      selectionOriginRow != null && selectionOriginCol != null;

  // 表示名を取得
  String get displayName {
    if (currentFilePath != null) {
      return currentFilePath!.split(Platform.pathSeparator).last;
    }
    return _defaultTitle;
  }

  // --- Search & Replace Logic ---

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

    if (searchResults.isNotEmpty) {
      currentSearchIndex = 0;
      int baseRow = cursorRow;
      int baseCol = cursorCol;

      if (hasSelection) {
        if (selectionOriginRow! < cursorRow ||
            (selectionOriginRow! == cursorRow &&
                selectionOriginCol! < cursorCol)) {
          baseRow = selectionOriginRow!;
          baseCol = selectionOriginCol!;
        }
      }

      for (int i = 0; i < searchResults.length; i++) {
        final result = searchResults[i];
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

    selectionOriginRow = result.lineIndex;
    selectionOriginCol = result.startCol;
    cursorRow = result.lineIndex;
    cursorCol = result.startCol + result.length;
    isRectangularSelection = false;

    preferredVisualX = _calcVisualX(cursorRow, cursorCol);
  }

  void replace(String query, String newText) {
    if (searchResults.isEmpty || currentSearchIndex == -1) return;
    final result = searchResults[currentSearchIndex];

    saveHistory();

    selectionOriginRow = result.lineIndex;
    selectionOriginCol = result.startCol;
    cursorRow = result.lineIndex;
    cursorCol = result.startCol + result.length;

    deleteSelection();
    insertText(newText);

    search(query);
  }

  void replaceAll(String query, String newText) {
    if (query.isEmpty) return;
    saveHistory();

    for (int i = 0; i < lines.length; i++) {
      lines[i] = lines[i].replaceAll(query, newText);
    }

    search(query);
  }

  void clearSearch() {
    searchResults.clear();
    currentSearchIndex = -1;
    notifyListeners();
  }

  // --- Editing Logic ---

  void saveHistory() {
    historyManager.save(lines, cursorRow, cursorCol);
  }

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

    isDirty = true;
    String newLine = lines[cursorRow];
    int safeEnd = min(cursorCol, newLine.length);
    preferredVisualX = TextUtils.calcTextWidth(newLine.substring(0, safeEnd));

    notifyListeners();
  }

  void deleteSelection() {
    if (!hasSelection) return;

    if (isRectangularSelection) {
      _deleteRectangularSelection();
    } else {
      _deleteNormalSelection();
    }
    selectionOriginRow = null;
    selectionOriginCol = null;
    isDirty = true;
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
    isDirty = true;
  }

  void _deleteRectangularSelection() {
    int startRow = min(selectionOriginRow!, cursorRow);
    int endRow = max(selectionOriginRow!, cursorRow);

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
    cursorRow = startRow;
    if (cursorRow < lines.length) {
      cursorCol = TextUtils.getColFromVisualX(lines[cursorRow], minVisualX);
      if (cursorCol > lines[cursorRow].length) {
        cursorCol = lines[cursorRow].length;
      }
    }
    isDirty = true;
  }

  void replaceRectangularSelection(String text) {
    if (!hasSelection) return;

    int startRow = min(selectionOriginRow!, cursorRow);
    int endRow = max(selectionOriginRow!, cursorRow);

    int originVisualX = _calcVisualX(selectionOriginRow!, selectionOriginCol!);
    int cursorVisualX = _calcVisualX(cursorRow, cursorCol);

    int minVisualX = min(originVisualX, cursorVisualX);
    int maxVisualX = max(originVisualX, cursorVisualX);

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

      if (i == startRow) {
        newCursorCol = part1.length + text.length;
      }
    }

    cursorRow = newCursorRow;
    cursorCol = newCursorCol;

    selectionOriginRow = null;
    selectionOriginCol = null;

    if (cursorRow < lines.length) {
      String line = lines[cursorRow];
      if (cursorCol > line.length) cursorCol = line.length;
      preferredVisualX = TextUtils.calcTextWidth(line.substring(0, cursorCol));
    }

    isDirty = true;
    notifyListeners();
  }

  void undo() {
    final entry = historyManager.undo(lines, cursorRow, cursorCol);
    if (entry != null) {
      isDirty = true;
      _applyHistoryEntry(entry);
    }
  }

  void redo() {
    final entry = historyManager.redo(lines, cursorRow, cursorCol);
    if (entry != null) {
      isDirty = true;
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

  void selectAll() {
    selectionOriginRow = 0;
    selectionOriginCol = 0;
    cursorRow = lines.length - 1;
    cursorCol = lines.last.length;
    isRectangularSelection = false;
    preferredVisualX = _calcVisualX(cursorRow, cursorCol);
    notifyListeners();
  }

  void indent() {
    saveHistory();
    deleteSelection();
    insertText(' ' * tabWidth);
  }

  void trimTrailingWhitespace() {
    saveHistory();
    bool changed = false;
    for (int i = 0; i < lines.length; i++) {
      String original = lines[i];
      String trimmed = original.trimRight();
      if (original != trimmed) {
        lines[i] = trimmed;
        changed = true;
      }
    }
    if (changed) {
      isDirty = true;
      notifyListeners();
    }
  }

  int _calcVisualX(int row, int col) {
    String line = (row < lines.length) ? lines[row] : "";
    String text;
    if (col <= line.length) {
      text = line.substring(0, col);
    } else {
      text = line + (' ' * (col - line.length));
    }
    return TextUtils.calcTextWidth(text);
  }

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

    if (colMove != 0) {
      if (isAlt) {
        if (colMove > 0) {
          cursorCol += colMove;
        } else {
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

  void clearSelection() {
    selectionOriginRow = null;
    selectionOriginCol = null;
    notifyListeners();
  }

  void handleTap(Offset localPosition, double charWidth, double lineHeight) {
    if (charWidth == 0 || lineHeight == 0) return;

    int clickedVisualX = (localPosition.dx / charWidth).floor();
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

  void updateComposingText(String text) {
    composingText = text;
    notifyListeners();
  }

  void input(String text) {
    if (text.isEmpty) return;

    saveHistory();

    if (isRectangularSelection && selectionOriginRow != null) {
      replaceRectangularSelection(text);
    } else {
      deleteSelection();
      insertText(text);
    }
  }

  // --- File I/O ---
  Future<void> openFile() async {
    try {
      String? path = await FileIOHelper.instance.pickFilePath();
      if (path != null) {
        String content = await FileIOHelper.instance.readFileAsString(path);
        saveHistory();
        currentFilePath = path;

        if (content.contains('\r\n')) {
          newLineType = NewLineType.crlf;
        } else if (content.contains('\r')) {
          newLineType = NewLineType.cr;
        } else {
          newLineType = NewLineType.lf;
        }

        content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
        lines = content.split('\n');
        if (lines.isEmpty) {
          lines = [''];
        }
        cursorRow = 0;
        cursorCol = 0;
        preferredVisualX = 0;
        selectionOriginRow = null;
        isDirty = false;
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
      String separator;
      switch (newLineType) {
        case NewLineType.crlf:
          separator = '\r\n';
          break;
        case NewLineType.cr:
          separator = '\r';
          break;
        case NewLineType.lf:
        default:
          separator = '\n';
      }
      String content = lines.join(separator);
      await FileIOHelper.instance.writeStringToFile(currentFilePath!, content);
      isDirty = false;
      notifyListeners();
      return currentFilePath;
    } catch (e) {
      debugPrint('Error saving file: $e');
      return null;
    }
  }

  Future<String?> saveAsFile() async {
    try {
      String? outputFile = await FileIOHelper.instance.saveFilePath(
        initialFileName: displayName,
      );
      if (outputFile != null) {
        currentFilePath = outputFile;
        String separator;
        switch (newLineType) {
          case NewLineType.crlf:
            separator = '\r\n';
            break;
          case NewLineType.cr:
            separator = '\r';
            break;
          case NewLineType.lf:
          default:
            separator = '\n';
        }
        String content = lines.join(separator);
        await FileIOHelper.instance.writeStringToFile(outputFile, content);
        isDirty = false;
        notifyListeners();
        return outputFile;
      }
    } catch (e) {
      debugPrint('Error saving file: $e');
    }
    return null;
  }
}
