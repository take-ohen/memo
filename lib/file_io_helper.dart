// lib/file_io_helper.dart
import 'package:file_picker/file_picker.dart';
import 'dart:io';

/// ファイル入出力を抽象化するヘルパークラス
/// テスト時にモックに差し替えることで、FilePickerへの直接依存を回避する。
class FileIOHelper {
  // シングルトン的なインスタンス。テスト時にこれを書き換える。
  static FileIOHelper instance = FileIOHelper();

  /// ファイルを開くダイアログを表示し、パスを返す
  Future<String?> pickFilePath() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'dart', 'json', 'xml', 'log'],
      );
      return result?.files.single.path;
    } catch (e) {
      // エラーハンドリングが必要ならここで行う
      return null;
    }
  }

  /// 名前を付けて保存ダイアログを表示し、パスを返す
  Future<String?> saveFilePath({String? initialFileName}) async {
    try {
      return await FilePicker.platform.saveFile(
        dialogTitle: '名前を付けて保存',
        fileName: initialFileName ?? 'memo.txt',
      );
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
