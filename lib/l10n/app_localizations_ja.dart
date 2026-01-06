// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get menuFile => 'ファイル';

  @override
  String get menuOpen => '開く';

  @override
  String get menuSave => '保存';

  @override
  String get menuSaveAs => '名前を付けて保存...';

  @override
  String get menuEdit => '編集';

  @override
  String get menuUndo => '元に戻す';

  @override
  String get menuRedo => 'やり直し';

  @override
  String get menuCut => '切り取り';

  @override
  String get menuCopy => 'コピー';

  @override
  String get menuPasteRect => '矩形貼り付け';

  @override
  String get menuPaste => '貼り付け';

  @override
  String get menuFind => '検索';

  @override
  String get menuTrimTrailingWhitespace => '行末の空白を削除';

  @override
  String get menuReplace => '置換';

  @override
  String get menuFormat => '整形';

  @override
  String get menuDrawBoxDouble => '枠線で囲む (全角)';

  @override
  String get menuDrawBoxSingle => '枠線で囲む (半角)';

  @override
  String get menuFormatTableDouble => '表に変換 (全角)';

  @override
  String get menuFormatTableSingle => '表に変換 (半角)';

  @override
  String get menuDrawLineDouble => '直線を引く (全角)';

  @override
  String get menuDrawLineSingle => '直線を引く (半角)';

  @override
  String get menuArrowEndDouble => '矢印 (終点・全角)';

  @override
  String get menuArrowEndSingle => '矢印 (終点・半角)';

  @override
  String get menuArrowBothDouble => '矢印 (両端・全角)';

  @override
  String get menuArrowBothSingle => '矢印 (両端・半角)';

  @override
  String get menuElbowUpperDouble => 'L字線 (上折れ・全角)';

  @override
  String get menuElbowUpperSingle => 'L字線 (上折れ・半角)';

  @override
  String get menuElbowLowerDouble => 'L字線 (下折れ・全角)';

  @override
  String get menuElbowLowerSingle => 'L字線 (下折れ・半角)';

  @override
  String get menuView => '表示';

  @override
  String get menuShowGrid => 'グリッド表示';

  @override
  String get menuShowLineNumbers => '行番号を表示';

  @override
  String get menuShowRuler => '列ルーラーを表示';

  @override
  String get menuShowMinimap => 'ミニマップを表示';

  @override
  String get menuSettings => '設定';

  @override
  String get menuFont => 'フォント...';

  @override
  String get menuHelp => 'ヘルプ';

  @override
  String get menuAbout => 'このアプリについて';

  @override
  String get statusUnsaved => '未保存 *';

  @override
  String get labelSearch => '検索';

  @override
  String get labelReplace => '置換';

  @override
  String get labelReplaceAll => '全て置換';

  @override
  String msgSaved(Object path) {
    return '保存しました: $path';
  }

  @override
  String get settingsTabEditor => 'エディタ';

  @override
  String get settingsTabUi => 'UI / メニュー';

  @override
  String get labelFontFamily => 'フォント名';

  @override
  String get labelFontSize => 'サイズ';

  @override
  String get labelBold => '太字';

  @override
  String get labelItalic => '斜体';

  @override
  String get btnScanFonts => 'フォント一覧を更新';

  @override
  String get msgScanningFonts => 'フォントをスキャン中...';

  @override
  String get previewText =>
      'The quick brown fox jumps over the lazy dog. 0123456789 日本語のテスト';

  @override
  String get labelCanvasSizeMin => 'キャンバスサイズ (最小)';

  @override
  String get labelColumns => '列数';

  @override
  String get labelLines => '行数';

  @override
  String get labelPreview => 'プレビュー';

  @override
  String get labelSettings => '設定';

  @override
  String get labelEditTarget => '編集対象';

  @override
  String get labelBackground => '背景';

  @override
  String get labelText => '文字';

  @override
  String get labelLineNumber => '行番号';

  @override
  String get labelRuler => 'ルーラー';

  @override
  String get labelGrid => 'グリッド';

  @override
  String get labelPresets => 'プリセット';

  @override
  String get labelCustom => 'カスタム';

  @override
  String get labelCancel => 'キャンセル';

  @override
  String get labelOK => 'OK';

  @override
  String get msgUnsavedFiles => '保存されていない変更があります。終了前に保存しますか？';

  @override
  String get titleExitConfirmation => '終了の確認';

  @override
  String get btnSaveAndExit => '保存して終了';

  @override
  String get btnExitWithoutSave => '保存せずに終了';

  @override
  String get labelRegex => '正規表現';

  @override
  String get labelCaseSensitive => '大文字小文字を区別';

  @override
  String get labelFindAll => '全て検索';

  @override
  String get labelGrepResults => '全体検索結果';
}
