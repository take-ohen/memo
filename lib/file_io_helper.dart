// lib/file_io_helper.dart
import 'package:file_selector/file_selector.dart';
import 'dart:io';

/// ファイル入出力を抽象化するヘルパークラス
/// テスト時にモックに差し替えることで、FilePickerへの直接依存を回避する。
class FileIOHelper {
  // シングルトン的なインスタンス。テスト時にこれを書き換える。
  static FileIOHelper instance = FileIOHelper();

  // 共通のフィルタ定義
  final List<XTypeGroup> _typeGroups = [
    const XTypeGroup(
      label: 'Text Files',
      extensions: ['txt', 'md', 'dart', 'json', 'xml', 'log'],
    ),
    const XTypeGroup(label: 'All Files'),
  ];

  /// ファイルを開くダイアログを表示し、パスを返す
  Future<String?> pickFilePath() async {
    try {
      final XFile? file = await openFile(acceptedTypeGroups: _typeGroups);
      return file?.path;
    } catch (e) {
      // エラーハンドリングが必要ならここで行う
      return null;
    }
  }

  /// 名前を付けて保存ダイアログを表示し、パスを返す
  Future<String?> saveFilePath({String? initialFileName}) async {
    try {
      final FileSaveLocation? result = await getSaveLocation(
        acceptedTypeGroups: _typeGroups,
        suggestedName: initialFileName ?? 'memo.txt',
      );
      return result?.path;
    } catch (e) {
      return null;
    }
  }

  /// ファイルの内容を文字列として読み込む
  Future<String> readFileAsString(String path) async {
    final file = File(path);
    return await file.readAsString();
  }

  /// 文字列をファイルに書き込む
  Future<void> writeStringToFile(String path, String content) async {
    final file = File(path);
    await file.writeAsString(content);
  }
}
