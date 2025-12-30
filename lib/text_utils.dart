import 'package:flutter/material.dart';

/// テキスト操作に関する汎用的な関数をまとめるクラス
class TextUtils {
  /// 全角・半角の文字幅計算ロジック
  /// 簡易的にASCII(0-127)を幅1、それ以外を幅2として計算する。
  static int calcTextWidth(String text) {
    int width = 0;
    for (int i = 0; i < text.runes.length; i++) {
      // ASCII文字(0-127)は幅1、それ以外は幅2
      width += (text.runes.elementAt(i) < 128) ? 1 : 2;
    }
    return width;
  }

  /// 見た目の幅(visualX)から文字数(col)を逆算する
  static int getColFromVisualX(String line, int targetVisualX) {
    int currentVisualX = 0;
    for (int i = 0; i < line.runes.length; i++) {
      int charWidth = (line.runes.elementAt(i) < 128) ? 1 : 2;

      if (currentVisualX + charWidth > targetVisualX) {
        if ((targetVisualX - currentVisualX) <
            (currentVisualX + charWidth - targetVisualX)) {
          return i;
        } else {
          return i + 1;
        }
      }
      currentVisualX += charWidth;
    }
    return line.length;
  }

  // --- Connection Logic ---
  // Top: 1, Bottom: 2, Left: 4, Right: 8

  static int getConnectionFlags(String char) {
    switch (char) {
      case '│':
      case '|':
        return 1 | 2; // Top | Bottom
      case '─':
      case '-':
        return 4 | 8; // Left | Right
      case '┌':
        return 2 | 8; // Bottom | Right
      case '┐':
        return 2 | 4; // Bottom | Left
      case '└':
        return 1 | 8; // Top | Right
      case '┘':
        return 1 | 4; // Top | Left
      case '├':
        return 1 | 2 | 8; // Top | Bottom | Right
      case '┤':
        return 1 | 2 | 4; // Top | Bottom | Left
      case '┬':
        return 2 | 4 | 8; // Bottom | Left | Right
      case '┴':
        return 1 | 4 | 8; // Top | Left | Right
      case '┼':
      case '+':
        return 1 | 2 | 4 | 8; // All
      default:
        return 0;
    }
  }

  static String? getCharFromConnectionFlags(int flags, bool useHalfWidth) {
    if (useHalfWidth) {
      // 垂直方向のみ (Top, Bottom, Top|Bottom) -> '|'
      if (flags != 0 && (flags & (4 | 8)) == 0) return '|';
      // 水平方向のみ (Left, Right, Left|Right) -> '-'
      if (flags != 0 && (flags & (1 | 2)) == 0) return '-';
      // それ以外 (曲がり角、T字、十字など) -> '+'
      return '+';
    }

    switch (flags) {
      // 単方向 (始点・終点用)
      case 1:
        return '│'; // Top only
      case 2:
        return '│'; // Bottom only
      case 4:
        return '─'; // Left only
      case 8:
        return '─'; // Right only
      // 接続
      case const (1 | 2):
        return '│';
      case const (4 | 8):
        return '─';
      case const (2 | 8):
        return '┌';
      case const (2 | 4):
        return '┐';
      case const (1 | 8):
        return '└';
      case const (1 | 4):
        return '┘';
      case const (1 | 2 | 8):
        return '├';
      case const (1 | 2 | 4):
        return '┤';
      case const (2 | 4 | 8):
        return '┬';
      case const (1 | 4 | 8):
        return '┴';
      case const (1 | 2 | 4 | 8):
        return '┼';
      default:
        return null;
    }
  }

  /// 方向ベクトルから矢印文字を取得する
  static String? getArrowChar(int dx, int dy, bool useHalfWidth) {
    if (dx == 0 && dy == 0) return null;

    if (useHalfWidth) {
      // 半角モード (斜めは対応なし)
      if (dx == 0) return dy > 0 ? 'v' : '^';
      if (dy == 0) return dx > 0 ? '>' : '<';
      return null;
    }

    // 全角モード
    if (dx == 0) return dy > 0 ? '↓' : '↑';
    if (dy == 0) return dx > 0 ? '→' : '←';

    if (dx > 0) return dy > 0 ? '↘' : '↗';
    return dy > 0 ? '↙' : '↖';
  }
}
