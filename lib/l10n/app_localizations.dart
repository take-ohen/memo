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

  /// No description provided for @menuShowDrawings.
  ///
  /// In en, this message translates to:
  /// **'Show Drawings'**
  String get menuShowDrawings;

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

  /// No description provided for @labelCanvasSizeMin.
  ///
  /// In en, this message translates to:
  /// **'Canvas Size (Min)'**
  String get labelCanvasSizeMin;

  /// No description provided for @labelColumns.
  ///
  /// In en, this message translates to:
  /// **'Cols'**
  String get labelColumns;

  /// No description provided for @labelLines.
  ///
  /// In en, this message translates to:
  /// **'Lines'**
  String get labelLines;

  /// No description provided for @labelPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get labelPreview;

  /// No description provided for @labelSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get labelSettings;

  /// No description provided for @labelEditTarget.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get labelEditTarget;

  /// No description provided for @labelBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get labelBackground;

  /// No description provided for @labelText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get labelText;

  /// No description provided for @labelLineNumber.
  ///
  /// In en, this message translates to:
  /// **'Line Number'**
  String get labelLineNumber;

  /// No description provided for @labelRuler.
  ///
  /// In en, this message translates to:
  /// **'Ruler'**
  String get labelRuler;

  /// No description provided for @labelGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get labelGrid;

  /// No description provided for @labelPresets.
  ///
  /// In en, this message translates to:
  /// **'Presets (Select & Delete)'**
  String get labelPresets;

  /// No description provided for @labelCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get labelCustom;

  /// No description provided for @labelCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get labelCancel;

  /// No description provided for @labelOK.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get labelOK;

  /// No description provided for @msgUnsavedFiles.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes. Do you want to save them before exiting?'**
  String get msgUnsavedFiles;

  /// No description provided for @titleExitConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Confirm Exit'**
  String get titleExitConfirmation;

  /// No description provided for @btnSaveAndExit.
  ///
  /// In en, this message translates to:
  /// **'Save and Exit'**
  String get btnSaveAndExit;

  /// No description provided for @btnExitWithoutSave.
  ///
  /// In en, this message translates to:
  /// **'Exit without Saving'**
  String get btnExitWithoutSave;

  /// No description provided for @labelRegex.
  ///
  /// In en, this message translates to:
  /// **'Regular Expression'**
  String get labelRegex;

  /// No description provided for @labelCaseSensitive.
  ///
  /// In en, this message translates to:
  /// **'Case Sensitive'**
  String get labelCaseSensitive;

  /// No description provided for @labelFindAll.
  ///
  /// In en, this message translates to:
  /// **'Find All'**
  String get labelFindAll;

  /// No description provided for @labelGrepResults.
  ///
  /// In en, this message translates to:
  /// **'Grep Results'**
  String get labelGrepResults;

  /// No description provided for @labelEditorFont.
  ///
  /// In en, this message translates to:
  /// **'Editor Font'**
  String get labelEditorFont;

  /// No description provided for @labelUiFont.
  ///
  /// In en, this message translates to:
  /// **'UI Font (Menu, Status Bar)'**
  String get labelUiFont;

  /// No description provided for @labelEditorColors.
  ///
  /// In en, this message translates to:
  /// **'Editor Colors'**
  String get labelEditorColors;

  /// No description provided for @labelBehavior.
  ///
  /// In en, this message translates to:
  /// **'Behavior'**
  String get labelBehavior;

  /// No description provided for @labelTabWidth.
  ///
  /// In en, this message translates to:
  /// **'Tab Width'**
  String get labelTabWidth;

  /// No description provided for @labelNewLineCode.
  ///
  /// In en, this message translates to:
  /// **'New Line Code'**
  String get labelNewLineCode;

  /// No description provided for @labelCursorBlink.
  ///
  /// In en, this message translates to:
  /// **'Cursor Blink'**
  String get labelCursorBlink;

  /// No description provided for @labelEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get labelEnable;

  /// No description provided for @labelSearchSettings.
  ///
  /// In en, this message translates to:
  /// **'Search & Grep Settings'**
  String get labelSearchSettings;

  /// No description provided for @labelGutterRulerColors.
  ///
  /// In en, this message translates to:
  /// **'Gutter & Ruler Colors'**
  String get labelGutterRulerColors;

  /// No description provided for @labelLineNumberSize.
  ///
  /// In en, this message translates to:
  /// **'Line No. Size'**
  String get labelLineNumberSize;

  /// No description provided for @labelRulerSize.
  ///
  /// In en, this message translates to:
  /// **'Ruler Size'**
  String get labelRulerSize;

  /// No description provided for @labelPreviewSearch.
  ///
  /// In en, this message translates to:
  /// **'Search Keyword'**
  String get labelPreviewSearch;

  /// No description provided for @labelPreviewGrep.
  ///
  /// In en, this message translates to:
  /// **'Result line...'**
  String get labelPreviewGrep;

  /// No description provided for @menuSettingsEditor.
  ///
  /// In en, this message translates to:
  /// **'Text Editor...'**
  String get menuSettingsEditor;

  /// No description provided for @menuSettingsUi.
  ///
  /// In en, this message translates to:
  /// **'Interface...'**
  String get menuSettingsUi;

  /// No description provided for @menuSettingsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General...'**
  String get menuSettingsGeneral;

  /// No description provided for @labelMenuBarFont.
  ///
  /// In en, this message translates to:
  /// **'Menu Bar Font'**
  String get labelMenuBarFont;

  /// No description provided for @labelStatusBarFont.
  ///
  /// In en, this message translates to:
  /// **'Status Bar Font'**
  String get labelStatusBarFont;

  /// No description provided for @labelTabBarFont.
  ///
  /// In en, this message translates to:
  /// **'Tab Bar Font'**
  String get labelTabBarFont;

  /// No description provided for @settingsTabGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsTabGeneral;

  /// No description provided for @tooltipNewTab.
  ///
  /// In en, this message translates to:
  /// **'New Tab'**
  String get tooltipNewTab;

  /// No description provided for @titleConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Confirmation'**
  String get titleConfirmation;

  /// No description provided for @msgFileAlreadyOpen.
  ///
  /// In en, this message translates to:
  /// **'This file is already open.\nDo you want to reload it? (Unsaved changes will be lost)'**
  String get msgFileAlreadyOpen;

  /// No description provided for @btnReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get btnReload;

  /// No description provided for @labelShape.
  ///
  /// In en, this message translates to:
  /// **'Shape'**
  String get labelShape;

  /// No description provided for @labelColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get labelColor;

  /// No description provided for @labelWidth.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get labelWidth;

  /// No description provided for @labelHeight.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get labelHeight;

  /// No description provided for @labelPaddingX.
  ///
  /// In en, this message translates to:
  /// **'Pad X'**
  String get labelPaddingX;

  /// No description provided for @labelPaddingY.
  ///
  /// In en, this message translates to:
  /// **'Pad Y'**
  String get labelPaddingY;

  /// No description provided for @labelStyle.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get labelStyle;

  /// No description provided for @labelRows.
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get labelRows;

  /// No description provided for @labelCols.
  ///
  /// In en, this message translates to:
  /// **'Cols'**
  String get labelCols;

  /// No description provided for @typeLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get typeLine;

  /// No description provided for @typeElbow.
  ///
  /// In en, this message translates to:
  /// **'Elbow'**
  String get typeElbow;

  /// No description provided for @typeRectangle.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get typeRectangle;

  /// No description provided for @typeRoundedRect.
  ///
  /// In en, this message translates to:
  /// **'Rounded Rect'**
  String get typeRoundedRect;

  /// No description provided for @typeOval.
  ///
  /// In en, this message translates to:
  /// **'Oval'**
  String get typeOval;

  /// No description provided for @typeBurst.
  ///
  /// In en, this message translates to:
  /// **'Burst'**
  String get typeBurst;

  /// No description provided for @typeMarker.
  ///
  /// In en, this message translates to:
  /// **'Marker'**
  String get typeMarker;

  /// No description provided for @typeImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get typeImage;

  /// No description provided for @typeTable.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get typeTable;

  /// No description provided for @styleSolid.
  ///
  /// In en, this message translates to:
  /// **'Solid'**
  String get styleSolid;

  /// No description provided for @styleDotted.
  ///
  /// In en, this message translates to:
  /// **'Dotted'**
  String get styleDotted;

  /// No description provided for @styleDashed.
  ///
  /// In en, this message translates to:
  /// **'Dashed'**
  String get styleDashed;

  /// No description provided for @styleDouble.
  ///
  /// In en, this message translates to:
  /// **'Double'**
  String get styleDouble;

  /// No description provided for @tooltipShapeType.
  ///
  /// In en, this message translates to:
  /// **'Shape Type'**
  String get tooltipShapeType;

  /// No description provided for @tooltipLineStyle.
  ///
  /// In en, this message translates to:
  /// **'Line Style'**
  String get tooltipLineStyle;

  /// No description provided for @tooltipStartArrow.
  ///
  /// In en, this message translates to:
  /// **'Start Arrow'**
  String get tooltipStartArrow;

  /// No description provided for @tooltipEndArrow.
  ///
  /// In en, this message translates to:
  /// **'End Arrow'**
  String get tooltipEndArrow;

  /// No description provided for @tooltipRouteUpper.
  ///
  /// In en, this message translates to:
  /// **'Route: Upper'**
  String get tooltipRouteUpper;

  /// No description provided for @tooltipRouteLower.
  ///
  /// In en, this message translates to:
  /// **'Route: Lower'**
  String get tooltipRouteLower;

  /// No description provided for @tooltipSetDefault.
  ///
  /// In en, this message translates to:
  /// **'Set as Default Style'**
  String get tooltipSetDefault;

  /// No description provided for @msgSetDefault.
  ///
  /// In en, this message translates to:
  /// **'Set current style as default'**
  String get msgSetDefault;

  /// No description provided for @titleDrawingList.
  ///
  /// In en, this message translates to:
  /// **'Drawing List'**
  String get titleDrawingList;

  /// No description provided for @labelAllTypes.
  ///
  /// In en, this message translates to:
  /// **'All Types'**
  String get labelAllTypes;

  /// No description provided for @btnSelectAreaFilter.
  ///
  /// In en, this message translates to:
  /// **'Select Area to Filter'**
  String get btnSelectAreaFilter;

  /// No description provided for @msgNoDrawings.
  ///
  /// In en, this message translates to:
  /// **'No drawings'**
  String get msgNoDrawings;

  /// No description provided for @tooltipDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get tooltipDelete;

  /// No description provided for @tooltipTabWidth.
  ///
  /// In en, this message translates to:
  /// **'Tab Width Settings'**
  String get tooltipTabWidth;

  /// No description provided for @labelTabWidthItem.
  ///
  /// In en, this message translates to:
  /// **'Tab Width: {width}'**
  String labelTabWidthItem(Object width);

  /// No description provided for @titleSelectColor.
  ///
  /// In en, this message translates to:
  /// **'Select Color'**
  String get titleSelectColor;

  /// No description provided for @btnClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get btnClose;

  /// No description provided for @tooltipAddPreset.
  ///
  /// In en, this message translates to:
  /// **'Add to Presets'**
  String get tooltipAddPreset;

  /// No description provided for @tooltipDrawingList.
  ///
  /// In en, this message translates to:
  /// **'Drawing List'**
  String get tooltipDrawingList;
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
