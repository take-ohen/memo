import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_memo_editor/editor_document.dart';
import 'package:free_memo_editor/file_io_helper.dart';

// FileIOHelperのモック
class MockFileIOHelper extends FileIOHelper {
  String? mockPickPath;
  String? mockSavePath;

  @override
  Future<String?> pickFilePath() async => mockPickPath;

  @override
  Future<String?> saveFilePath({String? initialFileName}) async => mockSavePath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EditorDocument document;
  late Directory tempDir;
  late MockFileIOHelper mockHelper;

  // MethodChannelの呼び出しログ
  final List<MethodCall> log = <MethodCall>[];

  setUp(() {
    // 1. MethodChannelのモック化 (charset_converter)
    // ネイティブ側の処理をここで偽装します
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('charset_converter'), (
          MethodCall methodCall,
        ) async {
          log.add(methodCall);

          // エンコード (String -> Uint8List)
          if (methodCall.method == 'encode') {
            final args = methodCall.arguments as Map;
            final charset = args['charset'] as String;
            final data = args['data'] as String;

            if (charset == 'shift_jis') {
              // テスト用ダミー変換: "ABC" -> [0xFF, 0x22, 0x33]
              // 実際にはShift_JISのバイト列ではありませんが、
              // 「変換処理を通ったこと」を確認するために独自の値を使います。
              // UTF-8として不正なバイト(0xFF)を含めることで自動判別のテストを通します。
              if (data == 'ABC') {
                return Uint8List.fromList([0xFF, 0x22, 0x33]);
              }
              return Uint8List.fromList(List.filled(data.length, 0xFF));
            }

            if (charset == 'euc-jp') {
              // テスト用ダミー変換: "あ" -> [0xA4, 0xA2]
              if (data == 'あ') {
                return Uint8List.fromList([0xA4, 0xA2]);
              }
            }
            return Uint8List(0);
          }

          // デコード (Uint8List -> String)
          if (methodCall.method == 'decode') {
            final args = methodCall.arguments as Map;
            final charset = args['charset'] as String;
            final data = args['data'] as Uint8List;

            if (charset == 'shift_jis') {
              // テスト用ダミー逆変換: [0xFF, 0x22, 0x33] -> "ABC"
              if (data.length == 3 &&
                  data[0] == 0xFF &&
                  data[1] == 0x22 &&
                  data[2] == 0x33) {
                return 'ABC';
              }
              return 'UNKNOWN';
            }

            if (charset == 'euc-jp') {
              // テスト用ダミー逆変換: [0xA4, 0xA2] -> "あ"
              if (data.length == 2 && data[0] == 0xA4 && data[1] == 0xA2) {
                return 'あ';
              }
            }
            return '';
          }
          return null;
        });

    // 2. その他のセットアップ
    mockHelper = MockFileIOHelper();
    FileIOHelper.instance = mockHelper;
    document = EditorDocument();
    tempDir = Directory.systemTemp.createTempSync('charset_test');
    log.clear();
  });

  tearDown(() {
    // モック解除
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('charset_converter'),
          null,
        );
    tempDir.deleteSync(recursive: true);
  });

  test('Shift_JISで保存できること (MethodChannel経由)', () async {
    final file = File('${tempDir.path}/sjis_save.txt');

    document.lines = ['ABC'];
    document.currentEncoding = 'shift_jis';
    document.currentFilePath = file.path;

    await document.saveFile();

    // 検証: ファイルにダミーバイト列 [0xFF, 0x22, 0x33] が書き込まれたか
    final bytes = file.readAsBytesSync();
    expect(bytes, equals([0xFF, 0x22, 0x33]));
  });

  test('Shift_JISで読み込めること (MethodChannel経由)', () async {
    final file = File('${tempDir.path}/sjis_load.txt');
    file.writeAsBytesSync([0xFF, 0x22, 0x33]); // ダミーバイト列

    await document.loadFromFile(file.path, encoding: 'shift_jis');

    // 検証: ダミー逆変換により "ABC" になっているか
    expect(document.lines[0], 'ABC');
    expect(document.currentEncoding, 'shift_jis');
  });

  test('EUC-JPで保存できること (MethodChannel経由)', () async {
    final file = File('${tempDir.path}/euc_save.txt');

    document.lines = ['あ'];
    document.currentEncoding = 'euc-jp';
    document.currentFilePath = file.path;

    await document.saveFile();

    final bytes = file.readAsBytesSync();
    expect(bytes, equals([0xA4, 0xA2]));
  });

  test('EUC-JPで読み込めること (MethodChannel経由)', () async {
    final file = File('${tempDir.path}/euc_load.txt');
    file.writeAsBytesSync([0xA4, 0xA2]);

    await document.loadFromFile(file.path, encoding: 'euc-jp');

    expect(document.lines[0], 'あ');
    expect(document.currentEncoding, 'euc-jp');
  });

  test('UTF-8指定時はMethodChannelを使わず保存・読み込みできること', () async {
    // ログをクリアして監視開始
    log.clear();

    final file = File('${tempDir.path}/utf8_test.txt');
    document.lines = ['UTF-8 Test'];
    document.currentEncoding = 'utf-8';
    document.currentFilePath = file.path;

    // 保存
    await document.saveFile();
    // 読み込み
    await document.loadFromFile(file.path, encoding: 'utf-8');

    // 検証: MethodChannel (charset_converter) が一度も呼ばれていないこと
    expect(log, isEmpty, reason: 'UTF-8の場合は標準ライブラリを使うため、プラグインは呼ばれないはず');
    expect(document.lines[0], 'UTF-8 Test');
  });

  test('自動判別: UTF-8として読み込める場合はUTF-8になること', () async {
    final file = File('${tempDir.path}/auto_utf8.txt');
    file.writeAsBytesSync(utf8.encode('Hello UTF-8'));

    // encoding指定なしでロード
    await document.loadFromFile(file.path);

    expect(document.lines[0], 'Hello UTF-8');
    expect(document.currentEncoding, 'utf-8');
  });

  test('自動判別: UTF-8で失敗した場合はShift_JISで再試行すること', () async {
    final file = File('${tempDir.path}/auto_sjis.txt');
    // UTF-8として不正なバイト列 (Shift_JISダミーデータ) を書き込む
    file.writeAsBytesSync([0xFF, 0x22, 0x33]);

    // encoding指定なしでロード
    await document.loadFromFile(file.path);

    expect(document.lines[0], 'ABC'); // ダミー変換結果
    expect(document.currentEncoding, 'shift_jis');
  });
}
