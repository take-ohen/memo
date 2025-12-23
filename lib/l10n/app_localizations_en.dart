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
  String get menuPaste => 'Paste';

  @override
  String get menuView => 'View';

  @override
  String get menuShowGrid => 'Show Grid';

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
}
