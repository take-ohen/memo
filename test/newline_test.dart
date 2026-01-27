import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_memo_editor/editor_document.dart';
import 'package:free_memo_editor/file_io_helper.dart';

// --- モッククラスの定義 ---
class MockFileIOHelper implements FileIOHelper {
  // テスト用設定値
  String? mockPickPath;

  @override
  Future<String?> pickFilePath() async {
    return mockPickPath;
  }

  @override
  Future<String?> pickImagePath() async {
    return mockPickPath;
  }

  // 以下のメソッドはEditorDocumentから直接呼ばれなくなるため、実装は不要（または空）
  @override
  Future<String> readFileAsString(String path) async => '';
  @override
  Future<String?> saveFilePath({String? initialFileName}) async {
    return mockPickPath;
  }

  @override
  Future<void> writeStringToFile(String path, String content) async {}

  @override
  Future<Uint8List> readFileAsBytes(String path) async {
    return File(path).readAsBytesSync();
  }

  @override
  Future<void> writeBytesToFile(String path, List<int> bytes) async {
    File(path).writeAsBytesSync(bytes);
  }

  @override
  Future<bool> fileExists(String path) async {
    return File(path).existsSync();
  }

  @override
  Future<void> deleteFile(String path) async {}
}

void main() {
  late MockFileIOHelper mockHelper;
  late EditorDocument document;
  late Directory tempDir;

  setUp(() {
    // 1. モックの準備と差し替え
    mockHelper = MockFileIOHelper();
    FileIOHelper.instance = mockHelper;

    // 2. テスト対象のドキュメント作成
    document = EditorDocument();

    // 3. 一時ディレクトリ作成
    tempDir = Directory.systemTemp.createTempSync('newline_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('NewLineType Detection (Open File)', () {
    test('Detects CRLF correctly', () async {
      final file = File('${tempDir.path}/crlf.txt');
      file.writeAsStringSync('Line1\r\nLine2\r\nLine3');
      mockHelper.mockPickPath = file.path;

      await document.loadFromFile(mockHelper.mockPickPath!);

      expect(document.newLineType, NewLineType.crlf);
      expect(document.lines.length, 3);
    });

    test('Detects CR correctly', () async {
      final file = File('${tempDir.path}/cr.txt');
      file.writeAsStringSync('Line1\rLine2\rLine3');
      mockHelper.mockPickPath = file.path;

      await document.loadFromFile(mockHelper.mockPickPath!);

      expect(document.newLineType, NewLineType.cr);
      expect(document.lines.length, 3);
    });

    test('Detects LF correctly', () async {
      final file = File('${tempDir.path}/lf.txt');
      file.writeAsStringSync('Line1\nLine2\nLine3');
      mockHelper.mockPickPath = file.path;

      await document.loadFromFile(mockHelper.mockPickPath!);

      expect(document.newLineType, NewLineType.lf);
      expect(document.lines.length, 3);
    });
  });

  group('NewLineType Saving', () {
    test('Saves with CRLF', () async {
      final file = File('${tempDir.path}/save_crlf.txt');
      document.lines = ['A', 'B'];
      document.newLineType = NewLineType.crlf;
      document.currentFilePath = file.path;

      await document.saveFile();

      expect(file.readAsStringSync(), 'A\r\nB');
    });

    test('Saves with LF', () async {
      final file = File('${tempDir.path}/save_lf.txt');
      document.lines = ['A', 'B'];
      document.newLineType = NewLineType.lf;
      document.currentFilePath = file.path;

      await document.saveFile();

      expect(file.readAsStringSync(), 'A\nB');
    });
  });
}
