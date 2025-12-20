import 'dart:math';
import 'package:flutter/material.dart';
import 'history_manager.dart';
import 'text_utils.dart';

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

  // 選択範囲
  int? selectionOriginRow;
  int? selectionOriginCol;
  bool isRectangularSelection = false;

  // 履歴管理
  final HistoryManager historyManager = HistoryManager();

  bool get hasSelection =>
      selectionOriginRow != null && selectionOriginCol != null;

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

    String startLine = (startRow < lines.length) ? lines[startRow] : "";
    String prefix = (startCol < startLine.length)
        ? startLine.substring(0, startCol)
        : startLine;

    String endLine = (endRow < lines.length) ? lines[endRow] : "";
    String suffix = (endCol < endLine.length) ? endLine.substring(endCol) : "";

    lines[startRow] = prefix + suffix;

    if (endRow > startRow) {
      lines.removeRange(startRow + 1, endRow + 1);
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

  // ヘルパー: VisualX計算
  int _calcVisualX(int row, int col) {
    if (row >= lines.length) return 0;
    String line = lines[row];
    String text;
    if (col <= line.length) {
      text = line.substring(0, col);
    } else {
      text = line + (' ' * (col - line.length));
    }
    return TextUtils.calcTextWidth(text);
  }
}
