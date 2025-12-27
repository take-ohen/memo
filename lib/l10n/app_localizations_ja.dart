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
  String get menuView => '表示';

  @override
  String get menuShowGrid => 'グリッド表示';

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
}
