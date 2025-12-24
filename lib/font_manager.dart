import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class FontManager {
  static final FontManager _instance = FontManager._internal();
  factory FontManager() => _instance;
  FontManager._internal();

  List<String> _allFonts = [];
  List<String> _monospaceFonts = [];

  List<String> get allFonts => _allFonts;
  List<String> get monospaceFonts => _monospaceFonts;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  /// フォントリストを読み込む（キャッシュがあればそれを使用）
  Future<void> loadFonts() async {
    if (_isLoaded) return;

    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final data = jsonDecode(jsonString);
        _allFonts = List<String>.from(data['all'] ?? []);
        _monospaceFonts = List<String>.from(data['mono'] ?? []);
        _isLoaded = true;
        debugPrint("Loaded fonts from cache: ${_allFonts.length} fonts");
        return;
      }
    } catch (e) {
      debugPrint("Error loading font cache: $e");
    }

    // キャッシュがない場合はスキャン
    await scanSystemFonts();
  }

  /// システムフォントをスキャンして等倍判定を行う
  Future<void> scanSystemFonts() async {
    List<String> rawFonts = [];

    try {
      if (Platform.isWindows) {
        // Windows: PowerShellを使用してフォント一覧を取得
        // レジストリ直接参照よりも確実で、ユーザーインストールフォントも含む
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          r"Add-Type -AssemblyName System.Drawing; (New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name }",
        ]);

        if (result.exitCode == 0) {
          final output = result.stdout as String;
          final lines = output.split(RegExp(r'\r\n|\r|\n'));
          for (var line in lines) {
            if (line.trim().isNotEmpty) {
              rawFonts.add(line.trim());
            }
          }
        } else {
          debugPrint("PowerShell error: ${result.stderr}");
        }
      } else if (Platform.isLinux) {
        // Linux: fc-list コマンドを使用
        final result = await Process.run('fc-list', [':', 'family']);
        if (result.exitCode == 0) {
          final output = result.stdout as String;
          final lines = output.split('\n');
          for (var line in lines) {
            // カンマ区切りで複数の名前がある場合がある
            final families = line.split(',');
            for (var f in families) {
              if (f.trim().isNotEmpty) {
                rawFonts.add(f.trim());
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error scanning fonts: $e");
    }

    // 重複除去とソート
    _allFonts = rawFonts.toSet().toList()..sort();
    _monospaceFonts = [];

    // 等倍フォント判定 (実測)
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (var font in _allFonts) {
      // 'i' と 'W' の幅が同じなら等倍とみなす
      textPainter.text = TextSpan(
        text: 'i',
        style: TextStyle(fontFamily: font, fontSize: 20),
      );
      textPainter.layout();
      final widthI = textPainter.width;

      textPainter.text = TextSpan(
        text: 'W',
        style: TextStyle(fontFamily: font, fontSize: 20),
      );
      textPainter.layout();
      final widthW = textPainter.width;

      if (widthI > 0 && (widthI - widthW).abs() < 0.1) {
        _monospaceFonts.add(font);
      }
    }

    _isLoaded = true;
    await _saveCache();
    debugPrint(
      "Scanned: ${_allFonts.length} fonts, ${_monospaceFonts.length} mono",
    );
  }

  Future<File> _getCacheFile() async {
    Directory dir;
    try {
      dir = await getApplicationSupportDirectory();
    } catch (e) {
      // path_providerが使えない場合のフォールバック
      dir = Directory.current;
    }
    return File('${dir.path}/font_cache.json');
  }

  Future<void> _saveCache() async {
    try {
      final file = await _getCacheFile();
      final data = {'all': _allFonts, 'mono': _monospaceFonts};
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint("Error saving font cache: $e");
    }
  }
}
