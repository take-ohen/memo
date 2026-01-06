import 'editor_document.dart';
import 'search_result.dart';

/// 全タブ検索(Grep)の結果を保持するクラス
class GrepResult {
  final EditorDocument document;
  final SearchResult searchResult;
  final String line; // ヒットした行のテキスト

  GrepResult({
    required this.document,
    required this.searchResult,
    required this.line,
  });
}
