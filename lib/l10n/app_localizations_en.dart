// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get menuFile => 'File';

  @override
  String get menuOpen => 'Open';

  @override
  String get menuSave => 'Save';

  @override
  String get menuSaveAs => 'Save As...';

  @override
  String get menuEdit => 'Edit';

  @override
  String get menuUndo => 'Undo';

  @override
  String get menuRedo => 'Redo';

  @override
  String get menuCut => 'Cut';

  @override
  String get menuCopy => 'Copy';

  @override
  String get menuPasteRect => 'Paste Rectangular';

  @override
  String get menuPaste => 'Paste';

  @override
  String get menuFind => 'Find';

  @override
  String get menuTrimTrailingWhitespace => 'Trim Trailing Whitespace';

  @override
  String get menuReplace => 'Replace';

  @override
  String get menuFormat => 'Format';

  @override
  String get menuDrawBoxDouble => 'Draw Box (Double/Full)';

  @override
  String get menuDrawBoxSingle => 'Draw Box (Single/Half)';

  @override
  String get menuFormatTableDouble => 'Convert to Table (Double/Full)';

  @override
  String get menuFormatTableSingle => 'Convert to Table (Single/Half)';

  @override
  String get menuDrawLineDouble => 'Draw Line (Double/Full)';

  @override
  String get menuDrawLineSingle => 'Draw Line (Single/Half)';

  @override
  String get menuArrowEndDouble => 'Arrow (End/Full)';

  @override
  String get menuArrowEndSingle => 'Arrow (End/Half)';

  @override
  String get menuArrowBothDouble => 'Arrow (Both/Full)';

  @override
  String get menuArrowBothSingle => 'Arrow (Both/Half)';

  @override
  String get menuElbowUpperDouble => 'Elbow Line (Upper/Full)';

  @override
  String get menuElbowUpperSingle => 'Elbow Line (Upper/Half)';

  @override
  String get menuElbowLowerDouble => 'Elbow Line (Lower/Full)';

  @override
  String get menuElbowLowerSingle => 'Elbow Line (Lower/Half)';

  @override
  String get menuView => 'View';

  @override
  String get menuShowGrid => 'Show Grid';

  @override
  String get menuShowLineNumbers => 'Show Line Numbers';

  @override
  String get menuShowRuler => 'Show Column Ruler';

  @override
  String get menuShowMinimap => 'Show Minimap';

  @override
  String get menuSettings => 'Settings';

  @override
  String get menuFont => 'Font...';

  @override
  String get menuHelp => 'Help';

  @override
  String get menuAbout => 'About';

  @override
  String get statusUnsaved => 'Unsaved *';

  @override
  String get labelSearch => 'Search';

  @override
  String get labelReplace => 'Replace';

  @override
  String get labelReplaceAll => 'Replace All';

  @override
  String msgSaved(Object path) {
    return 'Saved: $path';
  }

  @override
  String get settingsTabEditor => 'Editor';

  @override
  String get settingsTabUi => 'UI / Menu';

  @override
  String get labelFontFamily => 'Font Family';

  @override
  String get labelFontSize => 'Font Size';

  @override
  String get labelBold => 'Bold';

  @override
  String get labelItalic => 'Italic';

  @override
  String get btnScanFonts => 'Rescan Fonts';

  @override
  String get msgScanningFonts => 'Scanning fonts...';

  @override
  String get previewText =>
      'The quick brown fox jumps over the lazy dog. 0123456789';
}
