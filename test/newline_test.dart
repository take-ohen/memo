import 'package:flutter_test/flutter_test.dart';
import 'package:free_memo_editor/editor_document.dart';
import 'package:free_memo_editor/file_io_helper.dart';

// --- モッククラスの定義 ---
class MockFileIOHelper implements FileIOHelper {
  // テスト用設定値
  String? mockPickPath;
  String mockFileContent = '';

  // 検証用記録値
  String? lastWrittenPath;
  String? lastWrittenContent;

  @override
  Future<String?> pickFilePath() async {
    return mockPickPath;
  }

  @override
  Future<String> readFileAsString(String path) async {
    return mockFileContent;
  }

  @override
  Future<String?> saveFilePath() async {
    return mockPickPath;
  }

  @override
  Future<void> writeStringToFile(String path, String content) async {
    lastWrittenPath = path;
    lastWrittenContent = content;
  }
}

void main() {
  late MockFileIOHelper mockHelper;
  late EditorDocument document;

  setUp(() {
    // 1. モックの準備と差し替え
    mockHelper = MockFileIOHelper();
    FileIOHelper.instance = mockHelper;

    // 2. テスト対象のドキュメント作成
    document = EditorDocument();
  });

  group('NewLineType Detection (Open File)', () {
    test('Detects CRLF correctly', () async {
      mockHelper.mockPickPath = '/test/crlf.txt';
      mockHelper.mockFileContent = 'Line1\r\nLine2\r\nLine3';

      await document.openFile();

      expect(document.newLineType, NewLineType.crlf);
      expect(document.lines.length, 3);
    });

    test('Detects CR correctly', () async {
      mockHelper.mockPickPath = '/test/cr.txt';
      mockHelper.mockFileContent = 'Line1\rLine2\rLine3';

      await document.openFile();

      expect(document.newLineType, NewLineType.cr);
      expect(document.lines.length, 3);
    });

    test('Detects LF correctly', () async {
      mockHelper.mockPickPath = '/test/lf.txt';
      mockHelper.mockFileContent = 'Line1\nLine2\nLine3';

      await document.openFile();

      expect(document.newLineType, NewLineType.lf);
      expect(document.lines.length, 3);
    });
  });

  group('NewLineType Saving', () {
    test('Saves with CRLF', () async {
      document.lines = ['A', 'B'];
      document.newLineType = NewLineType.crlf;
      document.currentFilePath = '/test/save.txt';

      await document.saveFile();

      expect(mockHelper.lastWrittenContent, 'A\r\nB');
    });

    test('Saves with LF', () async {
      document.lines = ['A', 'B'];
      document.newLineType = NewLineType.lf;
      document.currentFilePath = '/test/save.txt';

      await document.saveFile();

      expect(mockHelper.lastWrittenContent, 'A\nB');
    });
  });
}
