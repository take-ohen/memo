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
}
