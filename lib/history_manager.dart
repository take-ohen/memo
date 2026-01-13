import 'package:flutter/foundation.dart';
import 'drawing_data.dart';

/// 履歴の1エントリ
class HistoryEntry {
  final List<String> lines;
  final int cursorRow;
  final int cursorCol;
  final List<DrawingObject> drawings;

  HistoryEntry(this.lines, this.cursorRow, this.cursorCol, this.drawings);
}

/// Undo/Redo のスタック管理を行うクラス
class HistoryManager {
  final List<HistoryEntry> _undoStack = [];
  final List<HistoryEntry> _redoStack = [];
  static const int _maxStackSize = 100;

  /// 現在の状態を履歴に保存する
  void save(
    List<String> lines,
    int cursorRow,
    int cursorCol,
    List<DrawingObject> drawings,
  ) {
    // List<String>のディープコピーを作成して保存
    final drawingsCopy = drawings.map((d) => d.copy()).toList();
    final entry = HistoryEntry(
      List.from(lines),
      cursorRow,
      cursorCol,
      drawingsCopy,
    );

    _undoStack.add(entry);

    if (_undoStack.length > _maxStackSize) {
      _undoStack.removeAt(0);
    }

    // 新しい操作をしたらRedoスタックはクリア
    _redoStack.clear();
  }

  /// Undoを実行し、戻すべき状態を返す（スタックが空ならnull）
  HistoryEntry? undo(
    List<String> currentLines,
    int currentRow,
    int currentCol,
    List<DrawingObject> currentDrawings,
  ) {
    if (_undoStack.isEmpty) return null;

    // 現在の状態をRedoスタックへ退避
    final drawingsCopy = currentDrawings.map((d) => d.copy()).toList();
    _redoStack.add(
      HistoryEntry(
        List.from(currentLines),
        currentRow,
        currentCol,
        drawingsCopy,
      ),
    );

    return _undoStack.removeLast();
  }

  /// Redoを実行し、進めるべき状態を返す（スタックが空ならnull）
  HistoryEntry? redo(
    List<String> currentLines,
    int currentRow,
    int currentCol,
    List<DrawingObject> currentDrawings,
  ) {
    if (_redoStack.isEmpty) return null;

    // 現在の状態をUndoスタックへ退避
    final drawingsCopy = currentDrawings.map((d) => d.copy()).toList();
    _undoStack.add(
      HistoryEntry(
        List.from(currentLines),
        currentRow,
        currentCol,
        drawingsCopy,
      ),
    );

    return _redoStack.removeLast();
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
}
