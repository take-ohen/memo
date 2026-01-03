import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
  ];

  /// No description provided for @menuFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get menuFile;

  /// No description provided for @menuOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get menuOpen;

  /// No description provided for @menuSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get menuSave;

  /// No description provided for @menuSaveAs.
  ///
  /// In en, this message translates to:
  /// **'Save As...'**
  String get menuSaveAs;

  /// No description provided for @menuEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get menuEdit;

  /// No description provided for @menuUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get menuUndo;

  /// No description provided for @menuRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get menuRedo;

  /// No description provided for @menuCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get menuCut;

  /// No description provided for @menuCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get menuCopy;

  /// No description provided for @menuPasteRect.
  ///
  /// In en, this message translates to:
  /// **'Paste Rectangular'**
  String get menuPasteRect;

  /// No description provided for @menuPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get menuPaste;

  /// No description provided for @menuFind.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get menuFind;

  /// No description provided for @menuTrimTrailingWhitespace.
  ///
  /// In en, this message translates to:
  /// **'Trim Trailing Whitespace'**
  String get menuTrimTrailingWhitespace;

  /// No description provided for @menuReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get menuReplace;

  /// No description provided for @menuFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get menuFormat;

  /// No description provided for @menuDrawBoxDouble.
  ///
  /// In en, this message translates to:
  /// **'Draw Box (Double/Full)'**
  String get menuDrawBoxDouble;

  /// No description provided for @menuDrawBoxSingle.
  ///
  /// In en, this message translates to:
  /// **'Draw Box (Single/Half)'**
  String get menuDrawBoxSingle;

  /// No description provided for @menuFormatTableDouble.
  ///
  /// In en, this message translates to:
  /// **'Convert to Table (Double/Full)'**
  String get menuFormatTableDouble;

  /// No description provided for @menuFormatTableSingle.
  ///
  /// In en, this message translates to:
  /// **'Convert to Table (Single/Half)'**
  String get menuFormatTableSingle;

  /// No description provided for @menuDrawLineDouble.
  ///
  /// In en, this message translates to:
  /// **'Draw Line (Double/Full)'**
  String get menuDrawLineDouble;

  /// No description provided for @menuDrawLineSingle.
  ///
  /// In en, this message translates to:
  /// **'Draw Line (Single/Half)'**
  String get menuDrawLineSingle;

  /// No description provided for @menuArrowEndDouble.
  ///
  /// In en, this message translates to:
  /// **'Arrow (End/Full)'**
  String get menuArrowEndDouble;

  /// No description provided for @menuArrowEndSingle.
  ///
  /// In en, this message translates to:
  /// **'Arrow (End/Half)'**
  String get menuArrowEndSingle;

  /// No description provided for @menuArrowBothDouble.
  ///
  /// In en, this message translates to:
  /// **'Arrow (Both/Full)'**
  String get menuArrowBothDouble;

  /// No description provided for @menuArrowBothSingle.
  ///
  /// In en, this message translates to:
  /// **'Arrow (Both/Half)'**
  String get menuArrowBothSingle;

  /// No description provided for @menuElbowUpperDouble.
  ///
  /// In en, this message translates to:
  /// **'Elbow Line (Upper/Full)'**
  String get menuElbowUpperDouble;

  /// No description provided for @menuElbowUpperSingle.
  ///
  /// In en, this message translates to:
  /// **'Elbow Line (Upper/Half)'**
  String get menuElbowUpperSingle;

  /// No description provided for @menuElbowLowerDouble.
  ///
  /// In en, this message translates to:
  /// **'Elbow Line (Lower/Full)'**
  String get menuElbowLowerDouble;

  /// No description provided for @menuElbowLowerSingle.
  ///
  /// In en, this message translates to:
  /// **'Elbow Line (Lower/Half)'**
  String get menuElbowLowerSingle;

  /// No description provided for @menuView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get menuView;

  /// No description provided for @menuShowGrid.
  ///
  /// In en, this message translates to:
  /// **'Show Grid'**
  String get menuShowGrid;

  /// No description provided for @menuShowLineNumbers.
  ///
  /// In en, this message translates to:
  /// **'Show Line Numbers'**
  String get menuShowLineNumbers;

  /// No description provided for @menuShowRuler.
  ///
  /// In en, this message translates to:
  /// **'Show Column Ruler'**
  String get menuShowRuler;

  /// No description provided for @menuShowMinimap.
  ///
  /// In en, this message translates to:
  /// **'Show Minimap'**
  String get menuShowMinimap;

  /// No description provided for @menuSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get menuSettings;

  /// No description provided for @menuFont.
  ///
  /// In en, this message translates to:
  /// **'Font...'**
  String get menuFont;

  /// No description provided for @menuHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get menuHelp;

  /// No description provided for @menuAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get menuAbout;

  /// No description provided for @statusUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved *'**
  String get statusUnsaved;

  /// No description provided for @labelSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get labelSearch;

  /// No description provided for @labelReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get labelReplace;

  /// No description provided for @labelReplaceAll.
  ///
  /// In en, this message translates to:
  /// **'Replace All'**
  String get labelReplaceAll;

  /// No description provided for @msgSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved: {path}'**
  String msgSaved(Object path);

  /// No description provided for @settingsTabEditor.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get settingsTabEditor;

  /// No description provided for @settingsTabUi.
  ///
  /// In en, this message translates to:
  /// **'UI / Menu'**
  String get settingsTabUi;

  /// No description provided for @labelFontFamily.
  ///
  /// In en, this message translates to:
  /// **'Font Family'**
  String get labelFontFamily;

  /// No description provided for @labelFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get labelFontSize;

  /// No description provided for @labelBold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get labelBold;

  /// No description provided for @labelItalic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get labelItalic;

  /// No description provided for @btnScanFonts.
  ///
  /// In en, this message translates to:
  /// **'Rescan Fonts'**
  String get btnScanFonts;

  /// No description provided for @msgScanningFonts.
  ///
  /// In en, this message translates to:
  /// **'Scanning fonts...'**
  String get msgScanningFonts;

  /// No description provided for @previewText.
  ///
  /// In en, this message translates to:
  /// **'The quick brown fox jumps over the lazy dog. 0123456789'**
  String get previewText;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
