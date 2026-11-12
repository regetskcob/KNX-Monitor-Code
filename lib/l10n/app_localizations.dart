import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

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
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('de'), Locale('en')];

  /// Subtitle under the app name on the splash screen.
  ///
  /// In de, this message translates to:
  /// **'Gruppenmonitor für KNXnet/IP'**
  String get splashSubtitle;

  /// Generic cancel button.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get commonCancel;

  /// Number of group addresses.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Gruppenadresse} other{{count} Gruppenadressen}}'**
  String groupAddressCount(int count);

  /// Number of devices.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Gerät} other{{count} Geräte}}'**
  String deviceCount(int count);

  /// Subtitle on the connect screen.
  ///
  /// In de, this message translates to:
  /// **'Mit KNX/IP-Gateway verbinden'**
  String get connectSubtitle;

  /// Label of the gateway host field.
  ///
  /// In de, this message translates to:
  /// **'Gateway'**
  String get connectGateway;

  /// Label of the port field; also its validation error.
  ///
  /// In de, this message translates to:
  /// **'Port'**
  String get connectPort;

  /// Validation error: host field empty.
  ///
  /// In de, this message translates to:
  /// **'IP-Adresse eingeben'**
  String get connectHostEmpty;

  /// Validation error: IPv6 address entered.
  ///
  /// In de, this message translates to:
  /// **'Nur IPv4'**
  String get connectHostIpv4Only;

  /// Validation error: host is not a valid address.
  ///
  /// In de, this message translates to:
  /// **'Ungültige Adresse'**
  String get connectHostInvalid;

  /// Connect button.
  ///
  /// In de, this message translates to:
  /// **'Verbinden'**
  String get connectButton;

  /// Heading above recently used gateways.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt verwendet'**
  String get connectRecent;

  /// Button opening the recordings list.
  ///
  /// In de, this message translates to:
  /// **'Aufnahmen ansehen'**
  String get connectViewRecordings;

  /// Catalog tile title when no project is imported.
  ///
  /// In de, this message translates to:
  /// **'Keine Gruppenadressen'**
  String get catalogNone;

  /// Catalog tile subtitle fallback when no project/file name is known.
  ///
  /// In de, this message translates to:
  /// **'importiert'**
  String get catalogImported;

  /// Catalog tile hint when nothing is imported.
  ///
  /// In de, this message translates to:
  /// **'ETS-Projekt (.knxproj), XKNX-Editor-Projekt (.xknx) oder Gruppenadressen-CSV für Namen, Datentypen & Geräte'**
  String get catalogHint;

  /// Button replacing the imported project.
  ///
  /// In de, this message translates to:
  /// **'Ersetzen'**
  String get catalogReplace;

  /// Button importing a project.
  ///
  /// In de, this message translates to:
  /// **'Importieren'**
  String get catalogImport;

  /// Snackbar after a successful import; summary e.g. "12 group addresses · 3 devices".
  ///
  /// In de, this message translates to:
  /// **'{summary} importiert'**
  String catalogImportedSnack(String summary);

  /// Snackbar when the import failed.
  ///
  /// In de, this message translates to:
  /// **'Import fehlgeschlagen: {error}'**
  String catalogImportFailed(String error);

  /// Import error for an unsupported file type.
  ///
  /// In de, this message translates to:
  /// **'Bitte eine .knxproj-, .xknx- oder .csv-Datei wählen.'**
  String get catalogPickFile;

  /// Title of the project password dialog.
  ///
  /// In de, this message translates to:
  /// **'Projektpasswort'**
  String get passwordTitle;

  /// Password dialog text after a wrong password.
  ///
  /// In de, this message translates to:
  /// **'Das Passwort war falsch. Bitte erneut versuchen.'**
  String get passwordWrong;

  /// Password dialog explanation.
  ///
  /// In de, this message translates to:
  /// **'Das ETS-Projekt ist geschützt. Das Passwort wird nur zum Öffnen verwendet und nicht gespeichert.'**
  String get passwordPrompt;

  /// Password field label.
  ///
  /// In de, this message translates to:
  /// **'Passwort'**
  String get passwordLabel;

  /// Tooltip: reveal password.
  ///
  /// In de, this message translates to:
  /// **'Anzeigen'**
  String get passwordShow;

  /// Tooltip: hide password.
  ///
  /// In de, this message translates to:
  /// **'Verbergen'**
  String get passwordHide;

  /// Button opening the protected project.
  ///
  /// In de, this message translates to:
  /// **'Öffnen'**
  String get passwordOpen;

  /// Caption of the live bus activity bars.
  ///
  /// In de, this message translates to:
  /// **'letzte 60 s'**
  String get activityLast60s;

  /// Caption of the activity bars of a recording.
  ///
  /// In de, this message translates to:
  /// **'über die Aufnahme'**
  String get activityOverRecording;

  /// Telegram type GroupValueWrite.
  ///
  /// In de, this message translates to:
  /// **'Schreiben'**
  String get typeWrite;

  /// Telegram type GroupValueRead.
  ///
  /// In de, this message translates to:
  /// **'Lesen'**
  String get typeRead;

  /// Telegram type GroupValueResponse.
  ///
  /// In de, this message translates to:
  /// **'Antwort'**
  String get typeResponse;

  /// Issue label: telegram was repeated.
  ///
  /// In de, this message translates to:
  /// **'Wiederholt'**
  String get issueRepeatedLabel;

  /// Issue explanation: repeated telegram.
  ///
  /// In de, this message translates to:
  /// **'Erster Versuch nicht quittiert – Teilnehmer fehlt oder Linie gestört.'**
  String get issueRepeatedHint;

  /// Issue label: own telegram not acknowledged.
  ///
  /// In de, this message translates to:
  /// **'Nicht quittiert'**
  String get issueNotConfirmedLabel;

  /// Issue explanation: not acknowledged.
  ///
  /// In de, this message translates to:
  /// **'Kein Empfänger hat das Telegramm bestätigt.'**
  String get issueNotConfirmedHint;

  /// Issue label: read request without response.
  ///
  /// In de, this message translates to:
  /// **'Keine Antwort'**
  String get issueUnansweredLabel;

  /// Issue explanation: unanswered read.
  ///
  /// In de, this message translates to:
  /// **'Kein Gerät hat geantwortet – Lese-Flag oder Status-Sender fehlt?'**
  String get issueUnansweredHint;

  /// Issue label: data length does not match the DPT.
  ///
  /// In de, this message translates to:
  /// **'Länge ≠ DPT'**
  String get issueSizeMismatchLabel;

  /// Issue explanation: size mismatch.
  ///
  /// In de, this message translates to:
  /// **'Die Datenlänge passt nicht zum Datenpunkttyp aus dem Projekt.'**
  String get issueSizeMismatchHint;

  /// Issue label: group address missing in the project.
  ///
  /// In de, this message translates to:
  /// **'Nicht im Projekt'**
  String get issueUnknownAddressLabel;

  /// Issue explanation: unknown group address.
  ///
  /// In de, this message translates to:
  /// **'Diese Gruppenadresse ist im ETS-Projekt nicht angelegt.'**
  String get issueUnknownAddressHint;

  /// Issue label: sender not in the project topology.
  ///
  /// In de, this message translates to:
  /// **'Gerät unbekannt'**
  String get issueUnknownDeviceLabel;

  /// Issue explanation: unknown device.
  ///
  /// In de, this message translates to:
  /// **'Die physikalische Adresse ist im ETS-Projekt keinem Gerät zugeordnet.'**
  String get issueUnknownDeviceHint;

  /// Issue label: unusual hop count.
  ///
  /// In de, this message translates to:
  /// **'Hop'**
  String get issueUnusualHopLabel;

  /// Issue explanation: unusual hop count.
  ///
  /// In de, this message translates to:
  /// **'Routingzähler ≠ 6: Telegramm lief über Koppler (oder 7 = unbegrenzt).'**
  String get issueUnusualHopHint;

  /// Issue label: a central-off address received the value 1.
  ///
  /// In de, this message translates to:
  /// **'Zentral-Aus mit Ein'**
  String get issueCentralOffOnLabel;

  /// Issue explanation: central-off address received the value 1.
  ///
  /// In de, this message translates to:
  /// **'Laut Name eine Zentral-Aus-Adresse, aber der Wert ist 1 – je nach Aktor schaltet das alles ein. Zentral-Aus sollte nur 0 senden.'**
  String get issueCentralOffOnHint;

  /// Connection lost due to a socket error.
  ///
  /// In de, this message translates to:
  /// **'Socket-Fehler: {error}'**
  String errorSocket(String error);

  /// Connect timeout.
  ///
  /// In de, this message translates to:
  /// **'Gateway antwortet nicht.'**
  String get errorGatewayNoResponse;

  /// Network error while connecting.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkfehler: {error}'**
  String errorNetwork(String error);

  /// Sending while disconnected.
  ///
  /// In de, this message translates to:
  /// **'Nicht verbunden.'**
  String get errorNotConnected;

  /// Gateway rejected a tunneling request; status is hex.
  ///
  /// In de, this message translates to:
  /// **'Gateway hat Telegramm abgelehnt (0x{status}).'**
  String errorTelegramRejected(String status);

  /// Tunneling ack timeout.
  ///
  /// In de, this message translates to:
  /// **'Keine Bestätigung vom Gateway.'**
  String get errorNoAck;

  /// Gateway closed the tunnel.
  ///
  /// In de, this message translates to:
  /// **'Verbindung vom Gateway beendet.'**
  String get errorClosedByGateway;

  /// Heartbeat timeout.
  ///
  /// In de, this message translates to:
  /// **'Gateway antwortet nicht mehr.'**
  String get errorGatewayStoppedResponding;

  /// Connect status 0x24 (no more connections).
  ///
  /// In de, this message translates to:
  /// **'Gateway meldet: keine freien Tunnel.'**
  String get errorNoFreeTunnel;

  /// Connect status 0x22 (connection type).
  ///
  /// In de, this message translates to:
  /// **'Gateway unterstützt keinen Tunnelbetrieb.'**
  String get errorTunnelUnsupported;

  /// Connect status 0x23 (connection option).
  ///
  /// In de, this message translates to:
  /// **'Gateway unterstützt die Verbindungsoption nicht.'**
  String get errorOptionUnsupported;

  /// Other connect status; status is hex.
  ///
  /// In de, this message translates to:
  /// **'Verbindung abgelehnt (Status 0x{status}).'**
  String errorConnectionRejected(String status);

  /// Project password was wrong.
  ///
  /// In de, this message translates to:
  /// **'Falsches Projektpasswort.'**
  String get projectPasswordWrong;

  /// Project needs a password.
  ///
  /// In de, this message translates to:
  /// **'Projekt ist passwortgeschützt.'**
  String get projectPasswordRequired;

  /// Import error: not a zip.
  ///
  /// In de, this message translates to:
  /// **'Keine gültige .knxproj-Datei.'**
  String get projectInvalidFile;

  /// Fallback name of a device without name.
  ///
  /// In de, this message translates to:
  /// **'Gerät'**
  String get projectDefaultDevice;

  /// Fallback name of a group address without name.
  ///
  /// In de, this message translates to:
  /// **'Gruppenadresse'**
  String get projectDefaultGroup;

  /// Import error: no group addresses.
  ///
  /// In de, this message translates to:
  /// **'Projekt enthält keine Gruppenadressen.'**
  String get projectNoGroups;

  /// Import error: no project data.
  ///
  /// In de, this message translates to:
  /// **'Keine Projektdaten in der Datei gefunden.'**
  String get projectNoData;

  /// Import error: 0.xml missing.
  ///
  /// In de, this message translates to:
  /// **'0.xml fehlt im Projekt.'**
  String get projectMissing0xml;

  /// Import error: archive error.
  ///
  /// In de, this message translates to:
  /// **'Projekt nicht lesbar: {error}'**
  String projectUnreadable(String error);

  /// CSV import error: empty file.
  ///
  /// In de, this message translates to:
  /// **'Datei ist leer.'**
  String get csvEmpty;

  /// CSV import error: no address column.
  ///
  /// In de, this message translates to:
  /// **'Keine Adressspalte gefunden.'**
  String get csvNoAddressColumn;

  /// CSV import error: no group addresses.
  ///
  /// In de, this message translates to:
  /// **'Keine Gruppenadressen gefunden.'**
  String get csvNoGroups;

  /// DPT 1.001 value 0.
  ///
  /// In de, this message translates to:
  /// **'Aus'**
  String get dpt1Off;

  /// DPT 1.001 value 1.
  ///
  /// In de, this message translates to:
  /// **'Ein'**
  String get dpt1On;

  /// DPT 1.002 value 0.
  ///
  /// In de, this message translates to:
  /// **'Falsch'**
  String get dpt1False;

  /// DPT 1.002 value 1.
  ///
  /// In de, this message translates to:
  /// **'Wahr'**
  String get dpt1True;

  /// DPT 1.003 value 0.
  ///
  /// In de, this message translates to:
  /// **'Gesperrt'**
  String get dpt1Disable;

  /// DPT 1.003 value 1.
  ///
  /// In de, this message translates to:
  /// **'Freigegeben'**
  String get dpt1Enable;

  /// DPT 1.005 value 0.
  ///
  /// In de, this message translates to:
  /// **'Kein Alarm'**
  String get dpt1NoAlarm;

  /// DPT 1.005 value 1.
  ///
  /// In de, this message translates to:
  /// **'Alarm'**
  String get dpt1Alarm;

  /// DPT 1.007 value 0.
  ///
  /// In de, this message translates to:
  /// **'Verringern'**
  String get dpt1Decrease;

  /// DPT 1.007 value 1.
  ///
  /// In de, this message translates to:
  /// **'Erhöhen'**
  String get dpt1Increase;

  /// DPT 1.008 value 0 (blinds up).
  ///
  /// In de, this message translates to:
  /// **'Auf'**
  String get dpt1Up;

  /// DPT 1.008 value 1 (blinds down).
  ///
  /// In de, this message translates to:
  /// **'Ab'**
  String get dpt1Down;

  /// DPT 1.009 value 0.
  ///
  /// In de, this message translates to:
  /// **'Offen'**
  String get dpt1Open;

  /// DPT 1.009 value 1.
  ///
  /// In de, this message translates to:
  /// **'Geschlossen'**
  String get dpt1Close;

  /// DPT 1.010 value 0; also DPT 3 stop.
  ///
  /// In de, this message translates to:
  /// **'Stopp'**
  String get dpt1Stop;

  /// DPT 1.010 value 1.
  ///
  /// In de, this message translates to:
  /// **'Start'**
  String get dpt1Start;

  /// DPT 1.011 value 0.
  ///
  /// In de, this message translates to:
  /// **'Inaktiv'**
  String get dpt1Inactive;

  /// DPT 1.011 value 1.
  ///
  /// In de, this message translates to:
  /// **'Aktiv'**
  String get dpt1Active;

  /// DPT 1.017 value.
  ///
  /// In de, this message translates to:
  /// **'Trigger'**
  String get dpt1Trigger;

  /// DPT 1.018 value 0.
  ///
  /// In de, this message translates to:
  /// **'Nicht belegt'**
  String get dpt1NotOccupied;

  /// DPT 1.018 value 1.
  ///
  /// In de, this message translates to:
  /// **'Belegt'**
  String get dpt1Occupied;

  /// DPT 1.019 (window/door) value 0.
  ///
  /// In de, this message translates to:
  /// **'Geschlossen'**
  String get dpt1Closed;

  /// DPT 1.019 (window/door) value 1.
  ///
  /// In de, this message translates to:
  /// **'Offen'**
  String get dpt1Opened;

  /// DPT 1.024 value 0.
  ///
  /// In de, this message translates to:
  /// **'Tag'**
  String get dpt1Day;

  /// DPT 1.024 value 1.
  ///
  /// In de, this message translates to:
  /// **'Nacht'**
  String get dpt1Night;

  /// DPT 2 control bit set.
  ///
  /// In de, this message translates to:
  /// **'Zwang'**
  String get dpt2Forced;

  /// DPT 2 control bit not set.
  ///
  /// In de, this message translates to:
  /// **'Frei'**
  String get dpt2Free;

  /// DPT 3.007 dimming up.
  ///
  /// In de, this message translates to:
  /// **'Heller'**
  String get dpt3Brighter;

  /// DPT 3.007 dimming down.
  ///
  /// In de, this message translates to:
  /// **'Dunkler'**
  String get dpt3Darker;

  /// DPT 17.001 scene number.
  ///
  /// In de, this message translates to:
  /// **'Szene {number}'**
  String dptSceneNumber(int number);

  /// DPT 18.001 scene store.
  ///
  /// In de, this message translates to:
  /// **'Szene {number} speichern'**
  String dptSceneStore(int number);

  /// DPT 18.001 scene recall.
  ///
  /// In de, this message translates to:
  /// **'Szene {number} abrufen'**
  String dptSceneRecall(int number);

  /// Scene learn flag in interpretation list.
  ///
  /// In de, this message translates to:
  /// **'lernen'**
  String get dptSceneLearn;

  /// HVAC mode 0.
  ///
  /// In de, this message translates to:
  /// **'Auto'**
  String get hvacAuto;

  /// HVAC mode 1.
  ///
  /// In de, this message translates to:
  /// **'Komfort'**
  String get hvacComfort;

  /// HVAC mode 2.
  ///
  /// In de, this message translates to:
  /// **'Standby'**
  String get hvacStandby;

  /// HVAC mode 3 (night/economy).
  ///
  /// In de, this message translates to:
  /// **'Nacht'**
  String get hvacEconomy;

  /// HVAC mode 4 (frost/heat protection).
  ///
  /// In de, this message translates to:
  /// **'Frostschutz'**
  String get hvacProtection;

  /// Name of DPT 1.001.
  ///
  /// In de, this message translates to:
  /// **'Schalten'**
  String get dptNameSwitch;

  /// Name of DPT 1.008.
  ///
  /// In de, this message translates to:
  /// **'Auf/Ab'**
  String get dptNameUpDown;

  /// Name of DPT 5.001.
  ///
  /// In de, this message translates to:
  /// **'Prozent'**
  String get dptNamePercent;

  /// Name of unsigned counter DPTs.
  ///
  /// In de, this message translates to:
  /// **'Zähler'**
  String get dptNameCounter;

  /// Name of signed value DPTs.
  ///
  /// In de, this message translates to:
  /// **'Vorzeichen'**
  String get dptNameSigned;

  /// Name of DPT 17.001.
  ///
  /// In de, this message translates to:
  /// **'Szene'**
  String get dptNameScene;

  /// Name of float DPTs (9.xxx, 14.xxx).
  ///
  /// In de, this message translates to:
  /// **'Gleitkomma'**
  String get dptNameFloat;

  /// Name of DPT 10.001.
  ///
  /// In de, this message translates to:
  /// **'Uhrzeit'**
  String get dptNameTime;

  /// Name of DPT 11.001.
  ///
  /// In de, this message translates to:
  /// **'Datum'**
  String get dptNameDate;

  /// Name of DPT 19.001.
  ///
  /// In de, this message translates to:
  /// **'Datum/Zeit'**
  String get dptNameDateTime;

  /// Name of DPT 16.000.
  ///
  /// In de, this message translates to:
  /// **'Text'**
  String get dptNameText;

  /// Short weekday Monday (DPT 10).
  ///
  /// In de, this message translates to:
  /// **'Mo'**
  String get weekdayMon;

  /// Short weekday Tuesday.
  ///
  /// In de, this message translates to:
  /// **'Di'**
  String get weekdayTue;

  /// Short weekday Wednesday.
  ///
  /// In de, this message translates to:
  /// **'Mi'**
  String get weekdayWed;

  /// Short weekday Thursday.
  ///
  /// In de, this message translates to:
  /// **'Do'**
  String get weekdayThu;

  /// Short weekday Friday.
  ///
  /// In de, this message translates to:
  /// **'Fr'**
  String get weekdayFri;

  /// Short weekday Saturday.
  ///
  /// In de, this message translates to:
  /// **'Sa'**
  String get weekdaySat;

  /// Short weekday Sunday.
  ///
  /// In de, this message translates to:
  /// **'So'**
  String get weekdaySun;

  /// Write format option for DPT 1.001.
  ///
  /// In de, this message translates to:
  /// **'Ein/Aus'**
  String get writeFormatSwitch;

  /// Write format option for DPT 5.010.
  ///
  /// In de, this message translates to:
  /// **'Zahl 0–255'**
  String get writeFormatNumber;

  /// Write format option for DPT 9.xxx.
  ///
  /// In de, this message translates to:
  /// **'Kommazahl'**
  String get writeFormatDecimal;

  /// Write format option for DPT 17.001.
  ///
  /// In de, this message translates to:
  /// **'Szene 1–64'**
  String get writeFormatScene;

  /// Write format option for raw hex bytes.
  ///
  /// In de, this message translates to:
  /// **'Hex-Rohdaten'**
  String get writeFormatHex;

  /// Label of the write format dropdown.
  ///
  /// In de, this message translates to:
  /// **'Format'**
  String get writeFormatLabel;

  /// Label of the value input field.
  ///
  /// In de, this message translates to:
  /// **'Wert'**
  String get writeValueLabel;

  /// Button sending a GroupValueWrite.
  ///
  /// In de, this message translates to:
  /// **'Schreiben'**
  String get writeButton;

  /// Status after writing a value.
  ///
  /// In de, this message translates to:
  /// **'Geschrieben: {value}'**
  String writeDone(String value);

  /// Error when the input cannot be encoded.
  ///
  /// In de, this message translates to:
  /// **'Ungültiger Wert für {format}.'**
  String writeInvalidValue(String format);

  /// Suffix: bus acknowledged the telegram.
  ///
  /// In de, this message translates to:
  /// **'vom Bus bestätigt'**
  String get confirmAcknowledged;

  /// Suffix: bus did not acknowledge.
  ///
  /// In de, this message translates to:
  /// **'nicht quittiert – kein Empfänger?'**
  String get confirmNotAcknowledged;

  /// Suffix: no confirmation within timeout.
  ///
  /// In de, this message translates to:
  /// **'keine Bestätigung vom Gateway'**
  String get confirmNoConfirmation;

  /// Error for an invalid group address input.
  ///
  /// In de, this message translates to:
  /// **'Ungültige Gruppenadresse.'**
  String get sendInvalidAddress;

  /// Status after sending a read request; confirmation is a suffix like " · acknowledged by the bus".
  ///
  /// In de, this message translates to:
  /// **'Leseanfrage gesendet{confirmation}. Die Antwort erscheint im Monitor.'**
  String sendReadSent(String confirmation);

  /// Title of the send sheet.
  ///
  /// In de, this message translates to:
  /// **'Gruppenadresse lesen / schreiben'**
  String get sendTitle;

  /// Button sending a GroupValueRead.
  ///
  /// In de, this message translates to:
  /// **'Wert lesen'**
  String get sendReadValue;

  /// Label of the group address field.
  ///
  /// In de, this message translates to:
  /// **'Gruppenadresse'**
  String get sendGroupAddress;

  /// Hint of the group address field with a project loaded.
  ///
  /// In de, this message translates to:
  /// **'1/2/3 oder Name'**
  String get sendGroupAddressHint;

  /// Screen reader label of the activity bars; period e.g. "last 60 s".
  ///
  /// In de, this message translates to:
  /// **'Busaktivität {period}'**
  String activitySemantics(String period);

  /// Kennzahl: durchschnittliche Telegramme je Minute im gewählten Zeitraum
  ///
  /// In de, this message translates to:
  /// **'Tel./min jetzt'**
  String get activityRate;

  /// Metric label: total telegrams.
  ///
  /// In de, this message translates to:
  /// **'Gesamt'**
  String get activityTotal;

  /// Metric label: repeated telegrams.
  ///
  /// In de, this message translates to:
  /// **'Wiederholt'**
  String get healthRepeated;

  /// Tooltip of the repeated metric.
  ///
  /// In de, this message translates to:
  /// **'Wiederholte Telegramme – Hinweis auf fehlende Quittungen'**
  String get healthRepeatedTooltip;

  /// Metric label: read requests without response.
  ///
  /// In de, this message translates to:
  /// **'Ohne Antwort'**
  String get healthUnanswered;

  /// Tooltip of the unanswered metric.
  ///
  /// In de, this message translates to:
  /// **'Leseanfragen ohne Antwort innerhalb von 3 s'**
  String get healthUnansweredTooltip;

  /// Sender column for telegrams sent by this app.
  ///
  /// In de, this message translates to:
  /// **'Gesendet'**
  String get rowSent;

  /// Second line under "Sent" in the wide table.
  ///
  /// In de, this message translates to:
  /// **'dieser Tunnel'**
  String get rowThisTunnel;

  /// Table column header: time.
  ///
  /// In de, this message translates to:
  /// **'Zeit'**
  String get columnTime;

  /// Table column header: telegram type.
  ///
  /// In de, this message translates to:
  /// **'Art'**
  String get columnType;

  /// Table column header: group address.
  ///
  /// In de, this message translates to:
  /// **'Adresse'**
  String get columnAddress;

  /// Table column header: name.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get columnName;

  /// Table column header: sender (individual address).
  ///
  /// In de, this message translates to:
  /// **'Absender'**
  String get columnSender;

  /// Table column header: value.
  ///
  /// In de, this message translates to:
  /// **'Wert'**
  String get columnValue;

  /// Tooltip of the type badge of an own telegram.
  ///
  /// In de, this message translates to:
  /// **'{type} (gesendet)'**
  String badgeSentTooltip(String type);

  /// Screen reader label of the type badge of an own telegram.
  ///
  /// In de, this message translates to:
  /// **'{type}, gesendet'**
  String badgeSentSemantics(String type);

  /// Legend entry explaining outlined badges.
  ///
  /// In de, this message translates to:
  /// **'umrandet: selbst gesendet'**
  String get legendOutlinedSent;

  /// Empty state of the live list.
  ///
  /// In de, this message translates to:
  /// **'Warte auf Telegramme …'**
  String get liveWaiting;

  /// Button scrolling to the newest telegram.
  ///
  /// In de, this message translates to:
  /// **'Neueste'**
  String get liveNewest;

  /// Generic save button.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get commonSave;

  /// PDF title and file name prefix of the live export.
  ///
  /// In de, this message translates to:
  /// **'KNX-Telegramme'**
  String get monitorExportTitle;

  /// Menu item clearing the log.
  ///
  /// In de, this message translates to:
  /// **'Monitor leeren'**
  String get monitorClear;

  /// Menu item importing a project.
  ///
  /// In de, this message translates to:
  /// **'ETS-Projekt oder CSV importieren …'**
  String get monitorImport;

  /// Menu item removing the imported project.
  ///
  /// In de, this message translates to:
  /// **'Projektdaten entfernen'**
  String get monitorRemoveProject;

  /// Menu item disconnecting.
  ///
  /// In de, this message translates to:
  /// **'Trennen'**
  String get monitorDisconnect;

  /// Connection status: connecting.
  ///
  /// In de, this message translates to:
  /// **'Verbinde …'**
  String get monitorConnecting;

  /// Connection status: disconnected.
  ///
  /// In de, this message translates to:
  /// **'Getrennt'**
  String get monitorDisconnected;

  /// Connection status for screen readers: connected.
  ///
  /// In de, this message translates to:
  /// **'Verbunden'**
  String get monitorConnected;

  /// Tooltip: resume the paused display.
  ///
  /// In de, this message translates to:
  /// **'Fortsetzen'**
  String get monitorResume;

  /// Tooltip: pause the display.
  ///
  /// In de, this message translates to:
  /// **'Anzeige pausieren'**
  String get monitorPause;

  /// Banner text when the tunnel was disconnected.
  ///
  /// In de, this message translates to:
  /// **'Verbindung getrennt.'**
  String get monitorConnectionLost;

  /// Button reconnecting the tunnel.
  ///
  /// In de, this message translates to:
  /// **'Neu verbinden'**
  String get monitorReconnect;

  /// Default name of a new recording, e.g. "Recording 10-14 15:20".
  ///
  /// In de, this message translates to:
  /// **'Aufnahme {date} {time}'**
  String recordingDefaultName(String date, String time);

  /// Snackbar after saving a recording.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ gespeichert · {count, plural, =1{1 Telegramm} other{{count} Telegramme}}'**
  String recordingSaved(String name, int count);

  /// Snackbar action opening the saved recording.
  ///
  /// In de, this message translates to:
  /// **'Ansehen'**
  String get recordingView;

  /// Tooltip of the record button.
  ///
  /// In de, this message translates to:
  /// **'Aufnahme starten'**
  String get recordingStart;

  /// Dialog title when renaming a recording.
  ///
  /// In de, this message translates to:
  /// **'Aufnahme bearbeiten'**
  String get recordingEdit;

  /// Dialog title when stopping a recording.
  ///
  /// In de, this message translates to:
  /// **'Aufnahme speichern'**
  String get recordingSave;

  /// Info in the save recording dialog.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Telegramm aufgenommen.} other{{count} Telegramme aufgenommen.}}'**
  String recordingCaptured(int count);

  /// Recording name field label.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get recordingName;

  /// Recording note field label.
  ///
  /// In de, this message translates to:
  /// **'Notiz (optional)'**
  String get recordingNoteLabel;

  /// Recording note field hint.
  ///
  /// In de, this message translates to:
  /// **'Was wurde geprüft? Befund?'**
  String get recordingNoteHint;

  /// Button closing the dialog and continuing to record.
  ///
  /// In de, this message translates to:
  /// **'Weiter aufnehmen'**
  String get recordingContinue;

  /// Button stopping and saving the recording.
  ///
  /// In de, this message translates to:
  /// **'Beenden & speichern'**
  String get recordingStopAndSave;

  /// Generic delete button.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get commonDelete;

  /// Metric/heading label: telegrams.
  ///
  /// In de, this message translates to:
  /// **'Telegramme'**
  String get labelTelegrams;

  /// Number of telegrams.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Telegramm} other{{count} Telegramme}}'**
  String telegramCount(int count);

  /// Title of the recordings list; tooltip of its button.
  ///
  /// In de, this message translates to:
  /// **'Aufnahmen'**
  String get recordingsTitle;

  /// Empty state of the recordings list.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Aufnahmen – im Monitor auf „Aufnehmen“ tippen.'**
  String get recordingsEmpty;

  /// Metric label: recording start time.
  ///
  /// In de, this message translates to:
  /// **'Beginn'**
  String get recordingsStart;

  /// Metric label: recording duration.
  ///
  /// In de, this message translates to:
  /// **'Dauer'**
  String get recordingsDuration;

  /// Delete confirmation title.
  ///
  /// In de, this message translates to:
  /// **'Aufnahme löschen?'**
  String get recordingDeleteTitle;

  /// Delete confirmation text.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ wird endgültig entfernt.'**
  String recordingDeleteText(String name);

  /// Tooltip of the share PDF button of a recording.
  ///
  /// In de, this message translates to:
  /// **'Aufnahme als PDF'**
  String get recordingPdf;

  /// Menu item editing a recording.
  ///
  /// In de, this message translates to:
  /// **'Name & Notiz bearbeiten'**
  String get recordingEditMenu;

  /// Menu item deleting a recording.
  ///
  /// In de, this message translates to:
  /// **'Aufnahme löschen'**
  String get recordingDeleteMenu;

  /// Tooltip: pause playback.
  ///
  /// In de, this message translates to:
  /// **'Wiedergabe anhalten'**
  String get playerPause;

  /// Tooltip: play recording.
  ///
  /// In de, this message translates to:
  /// **'Aufnahme abspielen'**
  String get playerPlay;

  /// Tooltip: seek to start.
  ///
  /// In de, this message translates to:
  /// **'Zum Anfang'**
  String get playerRestart;

  /// Tooltip of the playback speed chip.
  ///
  /// In de, this message translates to:
  /// **'Geschwindigkeit'**
  String get playerSpeed;

  /// Tooltip of the overflow menu.
  ///
  /// In de, this message translates to:
  /// **'Mehr'**
  String get commonMore;

  /// Tab: overview cards.
  ///
  /// In de, this message translates to:
  /// **'Über­sicht'**
  String get tabOverview;

  /// Tab: live list.
  ///
  /// In de, this message translates to:
  /// **'Live'**
  String get tabLive;

  /// Search hint without project.
  ///
  /// In de, this message translates to:
  /// **'Filter: 1/2/3, 1.1.5, Wert …'**
  String get filterHint;

  /// Search hint with an imported project.
  ///
  /// In de, this message translates to:
  /// **'Filter: Name, Gerät, 1/2/3, Wert …'**
  String get filterHintProject;

  /// Tooltip clearing the search field.
  ///
  /// In de, this message translates to:
  /// **'Filter löschen'**
  String get filterClear;

  /// Tooltip of the selection button.
  ///
  /// In de, this message translates to:
  /// **'Telegramme auswählen für PDF'**
  String get selectForPdfTooltip;

  /// Menu item starting the selection.
  ///
  /// In de, this message translates to:
  /// **'Auswählen für PDF'**
  String get selectForPdf;

  /// Menu item exporting everything as PDF.
  ///
  /// In de, this message translates to:
  /// **'Alles als PDF'**
  String get exportAllPdf;

  /// Tooltip closing the selection mode.
  ///
  /// In de, this message translates to:
  /// **'Auswahl beenden'**
  String get selectEnd;

  /// Title in selection mode with nothing selected.
  ///
  /// In de, this message translates to:
  /// **'Telegramme auswählen'**
  String get selectTitle;

  /// Title in selection mode.
  ///
  /// In de, this message translates to:
  /// **'{count} ausgewählt'**
  String selectCount(int count);

  /// Button deselecting all.
  ///
  /// In de, this message translates to:
  /// **'Keine'**
  String get selectNone;

  /// Button selecting all.
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get selectAll;

  /// Button exporting the selection.
  ///
  /// In de, this message translates to:
  /// **'Als PDF ({count})'**
  String selectExport(int count);

  /// Generic close tooltip.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get commonClose;

  /// Generic "no".
  ///
  /// In de, this message translates to:
  /// **'Nein'**
  String get commonNo;

  /// File name prefix of the history PDF.
  ///
  /// In de, this message translates to:
  /// **'Verlauf {name}'**
  String detailsHistoryPdfName(String name);

  /// Line in the copied telegram summary.
  ///
  /// In de, this message translates to:
  /// **'{type} von {sender} um {time}'**
  String detailsSummaryLine(String type, String sender, String time);

  /// Section title: issues of the telegram.
  ///
  /// In de, this message translates to:
  /// **'Hinweise'**
  String get detailsIssues;

  /// Section title: value history.
  ///
  /// In de, this message translates to:
  /// **'Verlauf'**
  String get detailsHistory;

  /// Tooltip: show history as chart.
  ///
  /// In de, this message translates to:
  /// **'Diagramm'**
  String get detailsChart;

  /// Tooltip: show history as list.
  ///
  /// In de, this message translates to:
  /// **'Liste'**
  String get detailsList;

  /// Tooltip of the history export button.
  ///
  /// In de, this message translates to:
  /// **'Verlauf als PDF exportieren'**
  String get detailsHistoryPdf;

  /// Section title: write a value.
  ///
  /// In de, this message translates to:
  /// **'Wert schreiben'**
  String get detailsWriteValue;

  /// Snackbar after sending a read request; confirmation is a suffix like " · acknowledged by the bus".
  ///
  /// In de, this message translates to:
  /// **'Leseanfrage gesendet{confirmation}'**
  String detailsReadSent(String confirmation);

  /// No description provided for @detailsCurrent.
  ///
  /// In de, this message translates to:
  /// **'Aktuell'**
  String get detailsCurrent;

  /// No description provided for @detailsComment.
  ///
  /// In de, this message translates to:
  /// **'Kommentar'**
  String get detailsComment;

  /// No description provided for @detailsRemember.
  ///
  /// In de, this message translates to:
  /// **'Merken'**
  String get detailsRemember;

  /// Button filtering the monitor by this address.
  ///
  /// In de, this message translates to:
  /// **'Filtern'**
  String get detailsFilter;

  /// Snackbar after copying.
  ///
  /// In de, this message translates to:
  /// **'In die Zwischenablage kopiert'**
  String get detailsCopied;

  /// Button copying the telegram summary.
  ///
  /// In de, this message translates to:
  /// **'Kopieren'**
  String get detailsCopy;

  /// Section title: telegram data.
  ///
  /// In de, this message translates to:
  /// **'Telegramm'**
  String get detailsTelegram;

  /// Info label: group address description.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung'**
  String get detailsDescription;

  /// Info label: telegram priority.
  ///
  /// In de, this message translates to:
  /// **'Priorität'**
  String get detailsPriority;

  /// Telegram priority system.
  ///
  /// In de, this message translates to:
  /// **'System'**
  String get prioritySystem;

  /// Telegram priority normal.
  ///
  /// In de, this message translates to:
  /// **'Normal'**
  String get priorityNormal;

  /// Telegram priority urgent.
  ///
  /// In de, this message translates to:
  /// **'Dringend'**
  String get priorityUrgent;

  /// Telegram priority low.
  ///
  /// In de, this message translates to:
  /// **'Niedrig'**
  String get priorityLow;

  /// Info value: telegram was repeated.
  ///
  /// In de, this message translates to:
  /// **'Ja – erster Versuch nicht quittiert'**
  String get detailsRepeatedYes;

  /// Info label: hop count.
  ///
  /// In de, this message translates to:
  /// **'Routingzähler'**
  String get detailsHopCount;

  /// Hop count 6: directly from the sender.
  ///
  /// In de, this message translates to:
  /// **'direkt'**
  String get detailsHopDirect;

  /// Hop count 7: unlimited.
  ///
  /// In de, this message translates to:
  /// **'unbegrenzt'**
  String get detailsHopUnlimited;

  /// Hop count below 6: number of couplers passed.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{über 1 Koppler} other{über {count} Koppler}}'**
  String detailsHopCouplers(int count);

  /// Info label: bus confirmation of an own telegram.
  ///
  /// In de, this message translates to:
  /// **'Bestätigung'**
  String get detailsConfirmation;

  /// Info value: own telegram acknowledged.
  ///
  /// In de, this message translates to:
  /// **'Vom Bus quittiert – empfangen; ob ausgeführt, zeigt die Rückmeldung'**
  String get detailsAcknowledged;

  /// Info label: payload.
  ///
  /// In de, this message translates to:
  /// **'Daten'**
  String get detailsData;

  /// Section title: devices linked to the group address.
  ///
  /// In de, this message translates to:
  /// **'Verknüpfte Geräte ({count})'**
  String detailsLinkedDevices(int count);

  /// Section title: interpretations without known DPT.
  ///
  /// In de, this message translates to:
  /// **'Mögliche Deutungen'**
  String get detailsInterpretations;

  /// Section title: interpretations with known DPT.
  ///
  /// In de, this message translates to:
  /// **'Weitere Deutungen'**
  String get detailsMoreInterpretations;

  /// History list: telegram sent by this app.
  ///
  /// In de, this message translates to:
  /// **'gesendet'**
  String get detailsSentLower;

  /// History list footer when truncated.
  ///
  /// In de, this message translates to:
  /// **'… und {count} ältere'**
  String detailsOlder(int count);

  /// Communication object number.
  ///
  /// In de, this message translates to:
  /// **'KO {number}'**
  String detailsObject(int number);

  /// Linked object sends on this group address.
  ///
  /// In de, this message translates to:
  /// **'sendet'**
  String get detailsSends;

  /// Linked object receives this group address.
  ///
  /// In de, this message translates to:
  /// **'empfängt'**
  String get detailsReceives;

  /// Screen reader label of the history chart.
  ///
  /// In de, this message translates to:
  /// **'Verlaufsdiagramm mit {count} Werten, zuletzt {last}'**
  String chartSemantics(int count, String last);

  /// Overview section for brightness values.
  ///
  /// In de, this message translates to:
  /// **'Helligkeit'**
  String get boardBrightness;

  /// Overview section fallback title for a main group without name.
  ///
  /// In de, this message translates to:
  /// **'Hauptgruppe {number}'**
  String boardMainGroup(int number);

  /// Empty state of the overview.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Werte empfangen'**
  String get boardEmpty;

  /// Screen reader label of an overview section header.
  ///
  /// In de, this message translates to:
  /// **'{title}, {count, plural, =1{1 Adresse} other{{count} Adressen}}'**
  String boardSectionSemantics(String title, int count);

  /// Title of the diagnostics screen; tooltip of its button.
  ///
  /// In de, this message translates to:
  /// **'Diagnose'**
  String get diagnosticsTitle;

  /// Device name fallback when the address is not in the project.
  ///
  /// In de, this message translates to:
  /// **'nicht im Projekt'**
  String get diagNotInProject;

  /// Scope: group addresses named like status/feedback.
  ///
  /// In de, this message translates to:
  /// **'Rückmeldungen'**
  String get diagScopeStatus;

  /// Diagnostics card: find devices in programming mode.
  ///
  /// In de, this message translates to:
  /// **'Programmiermodus'**
  String get diagProgTitle;

  /// Explanation of the programming mode card.
  ///
  /// In de, this message translates to:
  /// **'Findet Geräte, deren Programmier-LED leuchtet – z. B. wenn die ETS „mehrere Geräte im Programmiermodus“ meldet.'**
  String get diagProgText;

  /// Button label while searching.
  ///
  /// In de, this message translates to:
  /// **'Suche läuft …'**
  String get diagSearching;

  /// Button starting the search.
  ///
  /// In de, this message translates to:
  /// **'Suchen'**
  String get diagSearch;

  /// Result: nothing found.
  ///
  /// In de, this message translates to:
  /// **'Kein Gerät im Programmiermodus.'**
  String get diagProgNone;

  /// Error for an invalid individual address.
  ///
  /// In de, this message translates to:
  /// **'Bitte eine physikalische Adresse wie 1.1.18 eingeben.'**
  String get diagAddressInvalid;

  /// Diagnostics card: check an individual address.
  ///
  /// In de, this message translates to:
  /// **'Physikalische Adresse prüfen'**
  String get diagAddressTitle;

  /// Explanation of the address check card.
  ///
  /// In de, this message translates to:
  /// **'Prüft wie die ETS, ob eine Adresse belegt ist, und liest die Maskenversion des Geräts.'**
  String get diagAddressText;

  /// Button starting the address check.
  ///
  /// In de, this message translates to:
  /// **'Prüfen'**
  String get diagCheck;

  /// Address check result: device present.
  ///
  /// In de, this message translates to:
  /// **'belegt'**
  String get diagAddressPresent;

  /// Address check result: free.
  ///
  /// In de, this message translates to:
  /// **'frei – kein Gerät hat quittiert'**
  String get diagAddressFree;

  /// Address check result: unknown.
  ///
  /// In de, this message translates to:
  /// **'unklar – keine Bestätigung vom Gateway'**
  String get diagAddressUnknown;

  /// Device mask version (hex).
  ///
  /// In de, this message translates to:
  /// **'Maskenversion {mask}'**
  String diagMaskVersion(String mask);

  /// PDF summary label: time range.
  ///
  /// In de, this message translates to:
  /// **'Zeitraum'**
  String get pdfPeriod;

  /// PDF summary label: number of values.
  ///
  /// In de, this message translates to:
  /// **'Werte'**
  String get pdfValues;

  /// PDF summary label: minimum value.
  ///
  /// In de, this message translates to:
  /// **'Minimum'**
  String get pdfMinimum;

  /// PDF summary label: maximum value.
  ///
  /// In de, this message translates to:
  /// **'Maximum'**
  String get pdfMaximum;

  /// PDF summary label: average value.
  ///
  /// In de, this message translates to:
  /// **'Mittelwert'**
  String get pdfAverage;

  /// PDF footer with creation date and time.
  ///
  /// In de, this message translates to:
  /// **'Erstellt mit Busclear · {date} {time} Uhr'**
  String pdfFooterCreated(String date, String time);

  /// PDF footer page number.
  ///
  /// In de, this message translates to:
  /// **'Seite {page} von {total}'**
  String pdfPage(int page, int total);

  /// PDF heading of the recording note.
  ///
  /// In de, this message translates to:
  /// **'Notiz'**
  String get pdfNote;

  /// PDF sender column for telegrams sent by this app.
  ///
  /// In de, this message translates to:
  /// **'dieses Gerät'**
  String get pdfThisDevice;

  /// Übersicht: Sektion für Wetterdaten
  ///
  /// In de, this message translates to:
  /// **'Wetter'**
  String get boardWeather;

  /// Übersicht: Sektion für Verbrauchs- und Leistungsmessungen
  ///
  /// In de, this message translates to:
  /// **'Energie & Leistung'**
  String get boardEnergy;

  /// Übersicht: Sektion für Datum und Uhrzeit
  ///
  /// In de, this message translates to:
  /// **'Datum & Zeit'**
  String get boardDateTime;

  /// Kennzahl: selbst gesendete Telegramme
  ///
  /// In de, this message translates to:
  /// **'Gesendet'**
  String get activitySent;

  /// Übersicht: Sektion für Alarm- und Störmeldungen
  ///
  /// In de, this message translates to:
  /// **'Alarme & Störungen'**
  String get boardAlarms;

  /// Kennzeichnung eines aktiven Alarms
  ///
  /// In de, this message translates to:
  /// **'Alarm'**
  String get alarmLabel;

  /// Kennzeichnung einer aktiven Störung
  ///
  /// In de, this message translates to:
  /// **'Störung'**
  String get faultLabel;

  /// Kennzahl: Anzahl aktiver Alarme/Störungen
  ///
  /// In de, this message translates to:
  /// **'Alarme aktiv'**
  String get activityAlarms;

  /// Details: Überschrift der Alarmkarte
  ///
  /// In de, this message translates to:
  /// **'Aktive Meldung'**
  String get detailsAlarmTitle;

  /// Details: Erklärung bei aktivem Alarm
  ///
  /// In de, this message translates to:
  /// **'Diese Adresse meldet einen Alarm.'**
  String get detailsAlarmAlarm;

  /// Details: Erklärung bei aktiver Störung
  ///
  /// In de, this message translates to:
  /// **'Diese Adresse meldet eine Störung bzw. einen Defekt.'**
  String get detailsAlarmFault;

  /// Schnellfilter: nur aktive Alarme/Störungen
  ///
  /// In de, this message translates to:
  /// **'Alarme'**
  String get quickAlarm;

  /// Schnellfilter: nur wiederholte Telegramme
  ///
  /// In de, this message translates to:
  /// **'Wiederholt'**
  String get quickRepeated;

  /// Schnellfilter: Leseanfragen ohne Antwort
  ///
  /// In de, this message translates to:
  /// **'Ohne Antwort'**
  String get quickUnanswered;

  /// Schnellfilter: unbekannte Adressen/Geräte
  ///
  /// In de, this message translates to:
  /// **'Nicht im Projekt'**
  String get quickUnknown;

  /// Tooltip/Menü: gespeicherte Filter
  ///
  /// In de, this message translates to:
  /// **'Gespeicherte Filter'**
  String get savedFilters;

  /// Menüeintrag: aktuellen Filter speichern
  ///
  /// In de, this message translates to:
  /// **'Aktuellen Filter speichern'**
  String get saveCurrentFilter;

  /// Hinweis: keine gespeicherten Filter
  ///
  /// In de, this message translates to:
  /// **'Noch keine gespeicherten Filter'**
  String get noSavedFilters;

  /// Tooltip: gespeicherten Filter löschen
  ///
  /// In de, this message translates to:
  /// **'Gespeicherten Filter löschen'**
  String get deleteFilter;

  /// Tooltip/Titel: Hilfe zur Filtersyntax
  ///
  /// In de, this message translates to:
  /// **'Filter-Hilfe'**
  String get filterHelp;

  /// Hilfetext zur Filtersyntax
  ///
  /// In de, this message translates to:
  /// **'Leerzeichen = UND · Komma = ODER · -begriff = NICHT\n\n1/2/3 exakt · 1/2 Bereich · 1/*/3 oder 1/2/1* mit Platzhalter\n1.1.5 Absender · 1.1.* Linie · von:1.1.5\n\ntyp:w|r|a (Schreiben, Lesen, Antwort)\ndpt:9 oder dpt:9.001\nzeit:14:05 · zeit:14:05-14:10 (Uhrzeit, ohne das Ende)\nist:alarm · ist:wiederholt · ist:antwort · ist:projekt\nist:eigen · ist:fremd (selbst gesendet bzw. vom Bus)\nmesspunkt:1.2 oder messpunkt:1.2|1.3 (gesehen an diesen Messpunkten) · ist:einzeln (nur an einem Messpunkt)\n\nAlles andere sucht in Name, Bereich, Gerät und Wert – Umlaute egal (kuche findet Küche).\n\nMehrere ODER-Gruppen bekommen in der Liste je eine Farbe. „Kontext“ zeigt die Sekunden vor und nach jedem Treffer.\n\nBeispiele:\n1/*/* ist:antwort – unbeantwortete Leseanfragen in Hauptgruppe 1\nküche, bad -schalten – Küche oder Bad, ohne Schalten'**
  String get filterHelpBody;

  /// Titel: Abgleich Busverkehr mit ETS-Projekt
  ///
  /// In de, this message translates to:
  /// **'Projekt-Abgleich'**
  String get checkTitle;

  /// Hinweis: kein Projekt geladen
  ///
  /// In de, this message translates to:
  /// **'Importiere ein ETS-Projekt oder eine Gruppenadressen-CSV, um den Busverkehr damit abzugleichen.'**
  String get checkNoProject;

  /// Abschnitt: unbekannte Gruppenadressen
  ///
  /// In de, this message translates to:
  /// **'Gruppenadressen nicht im Projekt'**
  String get checkUnknownAddresses;

  /// Abschnitt: unbekannte physikalische Adressen
  ///
  /// In de, this message translates to:
  /// **'Absender nicht im Projekt'**
  String get checkUnknownDevices;

  /// Abschnitt: DPT-Längenfehler
  ///
  /// In de, this message translates to:
  /// **'Datenlänge passt nicht zum DPT'**
  String get checkSizeMismatch;

  /// Abschnitt: Projektadressen ohne Telegramm
  ///
  /// In de, this message translates to:
  /// **'Nie auf dem Bus gesehen'**
  String get checkNeverSeen;

  /// Hinweis: Abschnitt ohne Einträge
  ///
  /// In de, this message translates to:
  /// **'Keine Abweichungen'**
  String get checkAllGood;

  /// Anzahl Absender
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Absender} other{{count} Absender}}'**
  String checkSenders(int count);

  /// Anzahl Gruppenadressen
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Gruppenadresse} other{{count} Gruppenadressen}}'**
  String checkGroups(int count);

  /// Datenlänge erwartet vs. gesehen
  ///
  /// In de, this message translates to:
  /// **'erwartet {expected}, gesehen {seen}'**
  String checkExpected(String expected, String seen);

  /// Datenlänge in Byte
  ///
  /// In de, this message translates to:
  /// **'{count} Byte'**
  String checkBytes(int count);

  /// Datenlänge: Wert im APCI
  ///
  /// In de, this message translates to:
  /// **'≤ 6 bit'**
  String get checkSmall;

  /// Liste gekürzt
  ///
  /// In de, this message translates to:
  /// **'… und {count} weitere'**
  String checkMore(int count);

  /// Erklärung zu nie gesehenen Adressen
  ///
  /// In de, this message translates to:
  /// **'Hängt vom Beobachtungszeitraum ab – selten genutzte Adressen tauchen erst später auf.'**
  String get checkNeverSeenHint;

  /// Titel: Gateway-Infoseite
  ///
  /// In de, this message translates to:
  /// **'Gateway'**
  String get gatewayTitle;

  /// Gateway-Info: IP und Port
  ///
  /// In de, this message translates to:
  /// **'Adresse'**
  String get gatewayAddress;

  /// Gateway-Info: KNX-Medium
  ///
  /// In de, this message translates to:
  /// **'Medium'**
  String get gatewayMedium;

  /// Gateway-Info: eigene PA
  ///
  /// In de, this message translates to:
  /// **'Physikalische Adresse'**
  String get gatewayIndividual;

  /// Gateway-Info: Seriennummer
  ///
  /// In de, this message translates to:
  /// **'Seriennummer'**
  String get gatewaySerial;

  /// Gateway-Info: MAC
  ///
  /// In de, this message translates to:
  /// **'MAC-Adresse'**
  String get gatewayMac;

  /// Gateway-Info: Multicast-Adresse
  ///
  /// In de, this message translates to:
  /// **'Routing-Multicast'**
  String get gatewayMulticast;

  /// Gateway-Info: Programmiermodus
  ///
  /// In de, this message translates to:
  /// **'Programmiermodus'**
  String get gatewayProgMode;

  /// Gateway-Info: eigene Tunnelverbindung
  ///
  /// In de, this message translates to:
  /// **'Dieser Tunnel'**
  String get gatewayTunnel;

  /// Gateway-Info: Tunneladresse und Kanal
  ///
  /// In de, this message translates to:
  /// **'{address} · Kanal {channel}'**
  String gatewayTunnelValue(String address, int channel);

  /// Gateway-Info: Dienstfamilien
  ///
  /// In de, this message translates to:
  /// **'Unterstützte Dienste'**
  String get gatewayServices;

  /// Gateway-Info: Tunnelplätze
  ///
  /// In de, this message translates to:
  /// **'Tunnelplätze'**
  String get gatewaySlots;

  /// Tunnelplatz frei
  ///
  /// In de, this message translates to:
  /// **'frei'**
  String get gatewaySlotFree;

  /// Tunnelplatz belegt
  ///
  /// In de, this message translates to:
  /// **'belegt'**
  String get gatewaySlotBusy;

  /// Gateway-Info nicht verfügbar
  ///
  /// In de, this message translates to:
  /// **'Das Gateway hat noch keine Selbstbeschreibung geliefert.'**
  String get gatewayUnknown;

  /// Ja
  ///
  /// In de, this message translates to:
  /// **'Ja'**
  String get yes;

  /// Nein
  ///
  /// In de, this message translates to:
  /// **'Nein'**
  String get no;

  /// Button: Gateways im lokalen Netz suchen
  ///
  /// In de, this message translates to:
  /// **'Gateways suchen'**
  String get scanGateways;

  /// Gateway-Suche läuft
  ///
  /// In de, this message translates to:
  /// **'Suche im lokalen Netz …'**
  String get scanRunning;

  /// Gateway-Suche ohne Ergebnis
  ///
  /// In de, this message translates to:
  /// **'Kein KNXnet/IP-Gerät gefunden.'**
  String get scanNone;

  /// Überschrift: gefundene Gateways
  ///
  /// In de, this message translates to:
  /// **'Gefunden'**
  String get scanFound;

  /// Titel: Statistik-Ansicht
  ///
  /// In de, this message translates to:
  /// **'Statistik'**
  String get statsTitle;

  /// Kennzahl: beobachteter Zeitraum
  ///
  /// In de, this message translates to:
  /// **'Zeitraum'**
  String get statsSpan;

  /// Kennzahl: Telegramme pro Minute
  ///
  /// In de, this message translates to:
  /// **'Ø Tel./min'**
  String get statsPerMinute;

  /// No description provided for @monitorPauseShort.
  ///
  /// In de, this message translates to:
  /// **'Pause'**
  String get monitorPauseShort;

  /// No description provided for @statsPerMinuteShort.
  ///
  /// In de, this message translates to:
  /// **'Tel./Min'**
  String get statsPerMinuteShort;

  /// No description provided for @statsSendersShort.
  ///
  /// In de, this message translates to:
  /// **'Sender'**
  String get statsSendersShort;

  /// No description provided for @statsGroupsShort.
  ///
  /// In de, this message translates to:
  /// **'Adressen'**
  String get statsGroupsShort;

  /// Abschnitt: Absender mit den meisten Telegrammen
  ///
  /// In de, this message translates to:
  /// **'Top-Sender'**
  String get statsSenders;

  /// Abschnitt: Gruppenadressen mit den meisten Telegrammen
  ///
  /// In de, this message translates to:
  /// **'Top-Gruppenadressen'**
  String get statsGroups;

  /// Abschnitt: Flatterer
  ///
  /// In de, this message translates to:
  /// **'Sendet auffällig oft'**
  String get statsFlappers;

  /// Erklärung Flatterer
  ///
  /// In de, this message translates to:
  /// **'Im Mittel öfter als alle 10 s – zu kurze Sendezyklen oder Messwerte ohne Hysterese?'**
  String get statsFlappersHint;

  /// Abschnitt: Sekunden mit den meisten Telegrammen
  ///
  /// In de, this message translates to:
  /// **'Lastspitzen'**
  String get statsPeaks;

  /// Wiederholungsquote eines Absenders
  ///
  /// In de, this message translates to:
  /// **'{rate} wiederholt'**
  String statsRepeatRate(String rate);

  /// Mittlerer Sendeabstand
  ///
  /// In de, this message translates to:
  /// **'alle {interval}'**
  String statsEvery(String interval);

  /// Telegramme in einer Sekunde
  ///
  /// In de, this message translates to:
  /// **'{count} Tel./s'**
  String statsPerSecond(int count);

  /// Hinweis: leere Statistik
  ///
  /// In de, this message translates to:
  /// **'Noch keine Telegramme für eine Statistik.'**
  String get statsEmpty;

  /// Titel des Statistik-PDFs
  ///
  /// In de, this message translates to:
  /// **'Bus-Statistik'**
  String get statsPdfTitle;

  /// Titel: Trigger-Aufnahme
  ///
  /// In de, this message translates to:
  /// **'Trigger-Aufnahme'**
  String get triggerTitle;

  /// Erklärung Trigger-Aufnahme
  ///
  /// In de, this message translates to:
  /// **'Nimmt automatisch auf, sobald die Bedingung eintritt – inklusive der Telegramme davor. Ideal für sporadische Fehler.'**
  String get triggerExplain;

  /// Feld: Trigger-Bedingung
  ///
  /// In de, this message translates to:
  /// **'Bedingung'**
  String get triggerCondition;

  /// Trigger: bestimmte Gruppenadresse
  ///
  /// In de, this message translates to:
  /// **'Gruppenadresse'**
  String get triggerKindAddress;

  /// Trigger: aktiver Alarm
  ///
  /// In de, this message translates to:
  /// **'Alarm oder Störung'**
  String get triggerKindAlarm;

  /// Trigger: Wiederholung
  ///
  /// In de, this message translates to:
  /// **'Wiederholtes Telegramm'**
  String get triggerKindRepeated;

  /// Trigger: unbeantwortete Leseanfrage
  ///
  /// In de, this message translates to:
  /// **'Leseanfrage ohne Antwort'**
  String get triggerKindUnanswered;

  /// Trigger: unbekannte Gruppenadresse
  ///
  /// In de, this message translates to:
  /// **'Adresse nicht im Projekt'**
  String get triggerKindUnknown;

  /// Feld: Wertbedingung
  ///
  /// In de, this message translates to:
  /// **'Wert enthält (optional)'**
  String get triggerValue;

  /// Slider: Vorlauf
  ///
  /// In de, this message translates to:
  /// **'Vorlauf: {count} Telegramme'**
  String triggerPre(int count);

  /// Slider: Nachlauf
  ///
  /// In de, this message translates to:
  /// **'Nachlauf: {count} Telegramme'**
  String triggerPost(int count);

  /// Schalter: Trigger erneut scharf
  ///
  /// In de, this message translates to:
  /// **'Danach erneut scharf schalten'**
  String get triggerRearm;

  /// Button: Trigger scharf schalten
  ///
  /// In de, this message translates to:
  /// **'Scharf schalten'**
  String get triggerArm;

  /// Button: Trigger deaktivieren
  ///
  /// In de, this message translates to:
  /// **'Trigger aus'**
  String get triggerDisarm;

  /// Statuschip: Trigger aktiv
  ///
  /// In de, this message translates to:
  /// **'Trigger scharf'**
  String get triggerArmed;

  /// Statuschip: Trigger nimmt auf
  ///
  /// In de, this message translates to:
  /// **'Trigger nimmt auf'**
  String get triggerRecording;

  /// Snackbar nach Trigger-Aufnahme
  ///
  /// In de, this message translates to:
  /// **'Trigger ausgelöst: „{name}“ gespeichert'**
  String triggerFired(String name);

  /// Name einer Trigger-Aufnahme
  ///
  /// In de, this message translates to:
  /// **'Trigger: {condition}'**
  String triggerRecordingName(String condition);

  /// Notiz einer Trigger-Aufnahme
  ///
  /// In de, this message translates to:
  /// **'Automatisch aufgenommen. Bedingung: {condition}. Ausgelöst um {time}, {pre} Telegramme Vorlauf, {post} Nachlauf.'**
  String triggerNote(String condition, String time, int pre, int post);

  /// Fehler: ungültige Gruppenadresse
  ///
  /// In de, this message translates to:
  /// **'Bitte eine Gruppenadresse wie 1/2/3 eingeben.'**
  String get triggerInvalidAddress;

  /// Menü: alle Telegramme als CSV
  ///
  /// In de, this message translates to:
  /// **'Alles als CSV'**
  String get exportAllCsv;

  /// Menü: alle Telegramme als ETS-XML
  ///
  /// In de, this message translates to:
  /// **'Alles als ETS-Telegrammdatei'**
  String get exportAllEts;

  /// Tooltip: Auswahl als CSV
  ///
  /// In de, this message translates to:
  /// **'Als CSV'**
  String get exportCsv;

  /// Tooltip: Auswahl als ETS-XML
  ///
  /// In de, this message translates to:
  /// **'Als ETS-Telegrammdatei'**
  String get exportEts;

  /// Snackbar: Datei gespeichert
  ///
  /// In de, this message translates to:
  /// **'Gespeichert: {name}'**
  String exportSaved(String name);

  /// Snackbar: Export fehlgeschlagen
  ///
  /// In de, this message translates to:
  /// **'Export fehlgeschlagen: {error}'**
  String exportFailed(String error);

  /// Tooltip: ETS-XML als Aufnahme importieren
  ///
  /// In de, this message translates to:
  /// **'ETS-Telegrammdatei importieren'**
  String get recordingsImport;

  /// Snackbar: Import erfolgreich
  ///
  /// In de, this message translates to:
  /// **'„{name}“ importiert · {count} Telegramme'**
  String recordingsImported(String name, int count);

  /// Snackbar: Import fehlgeschlagen
  ///
  /// In de, this message translates to:
  /// **'Import fehlgeschlagen: {error}'**
  String recordingsImportFailed(String error);

  /// Recordings: title of the import preview
  ///
  /// In de, this message translates to:
  /// **'Aufnahme importieren'**
  String get recImportTitle;

  /// Import preview: label of the source format
  ///
  /// In de, this message translates to:
  /// **'Quelle'**
  String get recImportSource;

  /// Import preview: label of the period
  ///
  /// In de, this message translates to:
  /// **'Zeitraum'**
  String get recImportPeriod;

  /// Import preview: label of the number of telegrams
  ///
  /// In de, this message translates to:
  /// **'Telegramme'**
  String get recImportTelegrams;

  /// Import preview: label of the telegrams left out
  ///
  /// In de, this message translates to:
  /// **'Nicht lesbar'**
  String get recImportSkipped;

  /// Import preview: every telegram was read
  ///
  /// In de, this message translates to:
  /// **'keine'**
  String get recImportSkippedNone;

  /// Import preview: telegrams without RawData
  ///
  /// In de, this message translates to:
  /// **'{count} ohne Rohdaten'**
  String recImportSkipNoData(int count);

  /// Import preview: telegrams without timestamp
  ///
  /// In de, this message translates to:
  /// **'{count} ohne lesbare Zeit'**
  String recImportSkipTime(int count);

  /// Import preview: acknowledgements, device telegrams, damaged frames
  ///
  /// In de, this message translates to:
  /// **'{count} keine Gruppentelegramme'**
  String recImportSkipFrame(int count);

  /// Import preview: lines not in the format of the file
  ///
  /// In de, this message translates to:
  /// **'{count} unlesbare Zeilen'**
  String recImportSkipLine(int count);

  /// Import: source format
  ///
  /// In de, this message translates to:
  /// **'Busclear-Aufnahme'**
  String get recImportFormatRecording;

  /// Import: source format
  ///
  /// In de, this message translates to:
  /// **'Busclear-Langzeitverlauf'**
  String get recImportFormatHistory;

  /// Import: source format
  ///
  /// In de, this message translates to:
  /// **'Busclear-CSV'**
  String get recImportFormatCsv;

  /// Import: source format
  ///
  /// In de, this message translates to:
  /// **'ETS-Telegrammdatei (XML)'**
  String get recImportFormatEtsXml;

  /// Import: source format
  ///
  /// In de, this message translates to:
  /// **'ETS-Telegrammdateien (ZIP)'**
  String get recImportFormatEtsZip;

  /// Import preview: name of the recording
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get recImportName;

  /// Import preview: the recording is older than the current project state
  ///
  /// In de, this message translates to:
  /// **'Namen und Datentypen nach dem Projektstand, der bis {date} galt.'**
  String recImportState(String date);

  /// Import preview: what importing does
  ///
  /// In de, this message translates to:
  /// **'Wird als eigene Aufnahme dieser Installation gespeichert und als importiert gekennzeichnet. Der Langzeitverlauf bleibt, wie er ist.'**
  String get recImportHint;

  /// Import preview: confirm button
  ///
  /// In de, this message translates to:
  /// **'Importieren'**
  String get recImportConfirm;

  /// Recordings: mark of an imported recording
  ///
  /// In de, this message translates to:
  /// **'Importiert'**
  String get recImportedMark;

  /// Recording: source of an imported recording
  ///
  /// In de, this message translates to:
  /// **'Importiert aus {file}'**
  String recImportedFrom(String file);

  /// Import: too many telegrams
  ///
  /// In de, this message translates to:
  /// **'Die Datei enthält mehr als {count} Telegramme. Exportiere einen kürzeren Zeitraum.'**
  String recImportErrorTooMany(int count);

  /// Import: unknown file format
  ///
  /// In de, this message translates to:
  /// **'Dieses Format kennt Busclear nicht. Lesbar sind Busclear-Aufnahmen, die Telegramm-CSV und ETS-Telegrammdateien (Gruppenmonitor oder Busmonitor als XML).'**
  String get recImportErrorUnknown;

  /// Import: XML with DOCTYPE refused
  ///
  /// In de, this message translates to:
  /// **'Die XML-Datei bringt eine Dokumenttyp-Deklaration mit und wird deshalb nicht gelesen. ETS-Telegrammdateien haben keine.'**
  String get recImportErrorDoctype;

  /// Import: recognized format, damaged content
  ///
  /// In de, this message translates to:
  /// **'Die Datei ist beschädigt und lässt sich nicht lesen.'**
  String get recImportErrorDamaged;

  /// Import: no telegram found
  ///
  /// In de, this message translates to:
  /// **'In der Datei ist kein Gruppentelegramm.'**
  String get recImportErrorEmpty;

  /// Import: zip over the limits
  ///
  /// In de, this message translates to:
  /// **'Das Archiv entpackt sich zu mehr, als ein Import annimmt.'**
  String get recImportErrorArchive;

  /// Diagnose: Titel Linienscan
  ///
  /// In de, this message translates to:
  /// **'Linienscan'**
  String get scanTitle;

  /// Diagnose: Erklärung Linienscan
  ///
  /// In de, this message translates to:
  /// **'Prüft alle Adressen einer Linie wie die ETS und gleicht sie mit dem Projekt ab. Ein voller Scan dauert einige Minuten.'**
  String get scanExplain;

  /// Feld: Bereich.Linie
  ///
  /// In de, this message translates to:
  /// **'Linie'**
  String get scanLine;

  /// Bereich der Teilnehmernummern
  ///
  /// In de, this message translates to:
  /// **'Teilnehmer {from}–{to}'**
  String scanRange(int from, int to);

  /// Button: Linienscan starten
  ///
  /// In de, this message translates to:
  /// **'Scan starten'**
  String get scanStart;

  /// Fehler: ungültige Linie
  ///
  /// In de, this message translates to:
  /// **'Bitte eine Linie wie 1.1 eingeben.'**
  String get scanInvalidLine;

  /// Linienscan: belegte Adressen
  ///
  /// In de, this message translates to:
  /// **'Belegt'**
  String get scanPresent;

  /// Linienscan: fehlende Geräte
  ///
  /// In de, this message translates to:
  /// **'Im Projekt, antwortet nicht'**
  String get scanMissing;

  /// Linienscan: unerwartete Geräte
  ///
  /// In de, this message translates to:
  /// **'Antwortet, nicht im Projekt'**
  String get scanUnexpected;

  /// Linienscan: Anzahl geprüfter Adressen
  ///
  /// In de, this message translates to:
  /// **'Geprüft'**
  String get scanChecked;

  /// No description provided for @mapGraphSelected.
  ///
  /// In de, this message translates to:
  /// **'Verbindungen'**
  String get mapGraphSelected;

  /// No description provided for @mapGraphHint.
  ///
  /// In de, this message translates to:
  /// **'Zoomen zeigt mehr Details. Tippe auf ein Gerät für seine Verbindungen.'**
  String get mapGraphHint;

  /// No description provided for @mapGraphAll.
  ///
  /// In de, this message translates to:
  /// **'Alle Geräte'**
  String get mapGraphAll;

  /// No description provided for @mapGraphUnlinked.
  ///
  /// In de, this message translates to:
  /// **'Geräte ohne Verbindung'**
  String get mapGraphUnlinked;

  /// Titel: Kommunikationskarte
  ///
  /// In de, this message translates to:
  /// **'Kommunikationskarte'**
  String get mapTitle;

  /// Spalte: Sender einer Gruppenadresse
  ///
  /// In de, this message translates to:
  /// **'Sender'**
  String get mapSenders;

  /// Spalte: Empfänger laut Projekt
  ///
  /// In de, this message translates to:
  /// **'Empfänger (Projekt)'**
  String get mapReceivers;

  /// Spalte: Gruppenadressen, auf die ein Gerät hört
  ///
  /// In de, this message translates to:
  /// **'Hört auf'**
  String get mapListens;

  /// Spalte: Gruppenadressen, auf die ein Gerät sendet
  ///
  /// In de, this message translates to:
  /// **'Sendet auf'**
  String get mapSends;

  /// Spalte leer
  ///
  /// In de, this message translates to:
  /// **'Keine'**
  String get mapNone;

  /// Kante: beobachtete Telegramme
  ///
  /// In de, this message translates to:
  /// **'{count}× beobachtet'**
  String mapObserved(int count);

  /// Kante: nur im Projekt verknüpft
  ///
  /// In de, this message translates to:
  /// **'nur im Projekt'**
  String get mapProjectOnly;

  /// Kante: beobachtet, aber nicht im Projekt
  ///
  /// In de, this message translates to:
  /// **'nicht im Projekt verknüpft'**
  String get mapNotInProject;

  /// Suchfeld Kommunikationskarte
  ///
  /// In de, this message translates to:
  /// **'Adresse oder Gerät suchen …'**
  String get mapSearch;

  /// Hinweis: leere Karte
  ///
  /// In de, this message translates to:
  /// **'Noch kein Busverkehr für eine Karte.'**
  String get mapEmpty;

  /// Erklärung Kommunikationskarte
  ///
  /// In de, this message translates to:
  /// **'Antippen rückt einen Knoten in die Mitte. Linien: durchgezogen = beobachtet, gestrichelt = nur im Projekt.'**
  String get mapHint;

  /// Titel: Langzeitverlauf
  ///
  /// In de, this message translates to:
  /// **'Langzeitverlauf'**
  String get historyTitle;

  /// Erklärung Langzeitverlauf
  ///
  /// In de, this message translates to:
  /// **'Speichert jeden Tag allen Busverkehr, solange der Monitor verbunden ist – zum nachträglichen Ansehen, Abspielen und Exportieren.'**
  String get historyExplain;

  /// Langzeitverlauf aus
  ///
  /// In de, this message translates to:
  /// **'Aus'**
  String get historyOff;

  /// Aufbewahrungsdauer
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Tag} other{{count} Tage}}'**
  String historyDays(int count);

  /// Speicherbelegung
  ///
  /// In de, this message translates to:
  /// **'Belegt: {size}'**
  String historyUsage(String size);

  /// Name eines Verlaufstags
  ///
  /// In de, this message translates to:
  /// **'Verlauf {date}'**
  String historyDayName(String date);

  /// Button: gesamten Verlauf löschen
  ///
  /// In de, this message translates to:
  /// **'Verlauf löschen'**
  String get historyDeleteAll;

  /// Hinweis: Verlauf leer
  ///
  /// In de, this message translates to:
  /// **'Noch keine Tage gespeichert.'**
  String get historyEmpty;

  /// Rückfrage vor Aus: Titel
  ///
  /// In de, this message translates to:
  /// **'Verlauf ausschalten?'**
  String get historyOffConfirmTitle;

  /// Rückfrage vor Aus: Knopf
  ///
  /// In de, this message translates to:
  /// **'Ausschalten und löschen'**
  String get historyOffConfirm;

  /// Import: Datei zu groß
  ///
  /// In de, this message translates to:
  /// **'Die Datei ist mit {mb} MB zu groß für eine Aufnahme. Exportiere einen kürzeren Zeitraum (höchstens 100 MB).'**
  String recordingsImportTooLarge(int mb);

  /// Wiederherstellung abgebrochen: Titel
  ///
  /// In de, this message translates to:
  /// **'Sicherung nur teilweise zurückgespielt'**
  String get backupRestorePartialTitle;

  /// Wiederherstellung abgebrochen: Text
  ///
  /// In de, this message translates to:
  /// **'{count} Dateien sind schon aus der Sicherung, danach ist ein Fehler aufgetreten (zum Beispiel voller Speicher). Die App startet jetzt neu. Spiel die Sicherung danach noch einmal ein.'**
  String backupRestorePartial(int count);

  /// Hinweis: Aus löscht
  ///
  /// In de, this message translates to:
  /// **'Ausschalten löscht den gespeicherten Verlauf.'**
  String get historyOffHint;

  /// Ansicht: nach Objekten gruppiert
  ///
  /// In de, this message translates to:
  /// **'Ob­jekte'**
  String get tabObjects;

  /// Hinweis: keine Objekte
  ///
  /// In de, this message translates to:
  /// **'Noch keine Objekte erkannt – dafür braucht es Gruppenadressen mit Namensschema (z. B. „EG FL F01 Auf/Ab“) und Busverkehr.'**
  String get objectsEmpty;

  /// Sektion: Objekte ohne Raum
  ///
  /// In de, this message translates to:
  /// **'Weitere'**
  String get objectsOther;

  /// Spalte: Befehls-Gruppenadressen eines Objekts
  ///
  /// In de, this message translates to:
  /// **'Befehle'**
  String get objectCommands;

  /// Spalte: Rückmelde-Gruppenadressen eines Objekts
  ///
  /// In de, this message translates to:
  /// **'Rückmeldungen'**
  String get objectFeedback;

  /// Aktion: Monitor filtern
  ///
  /// In de, this message translates to:
  /// **'Monitor auf dieses Objekt filtern'**
  String get objectFilter;

  /// Erklärung Objektansicht
  ///
  /// In de, this message translates to:
  /// **'Erkannt am gemeinsamen Namensanfang. Durchgezogen = Wert empfangen, gestrichelt = noch kein Telegramm.'**
  String get objectHint;

  /// Anzahl Adressen eines Objekts
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Adresse} other{{count} Adressen}}'**
  String objectMembers(int count);

  /// Device info (diagnostics)
  ///
  /// In de, this message translates to:
  /// **'Geräteinfo lesen'**
  String get diagDeviceInfo;

  /// Device info (diagnostics)
  ///
  /// In de, this message translates to:
  /// **'Gerät hat keine Verbindung angenommen.'**
  String get diagDeviceInfoFailed;

  /// Device info (diagnostics)
  ///
  /// In de, this message translates to:
  /// **'Hersteller'**
  String get devManufacturer;

  /// Device info (diagnostics)
  ///
  /// In de, this message translates to:
  /// **'Seriennummer'**
  String get devSerial;

  /// Device info (diagnostics)
  ///
  /// In de, this message translates to:
  /// **'stimmt mit Projekt überein'**
  String get devSerialMatch;

  /// Device info (diagnostics)
  ///
  /// In de, this message translates to:
  /// **'weicht vom Projekt ab ({serial})'**
  String devSerialMismatch(String serial);

  /// Device info (diagnostics)
  ///
  /// In de, this message translates to:
  /// **'Bestellnummer'**
  String get devOrder;

  /// Device info (diagnostics)
  ///
  /// In de, this message translates to:
  /// **'Hardware-Typ'**
  String get devHardware;

  /// Device info (diagnostics)
  ///
  /// In de, this message translates to:
  /// **'Firmware'**
  String get devFirmware;

  /// Device info (diagnostics)
  ///
  /// In de, this message translates to:
  /// **'Programmiermodus'**
  String get devProgMode;

  /// Device info (diagnostics)
  ///
  /// In de, this message translates to:
  /// **'Applikation'**
  String get devApplication;

  /// Device info (diagnostics)
  ///
  /// In de, this message translates to:
  /// **'Maskenversion'**
  String get devMask;

  /// Device info (diagnostics)
  ///
  /// In de, this message translates to:
  /// **'an'**
  String get devOn;

  /// Device info (diagnostics)
  ///
  /// In de, this message translates to:
  /// **'aus'**
  String get devOff;

  /// Device info (diagnostics)
  ///
  /// In de, this message translates to:
  /// **'nicht unterstützt'**
  String get devUnsupported;

  /// Setting that shows all tools directly
  ///
  /// In de, this message translates to:
  /// **'Expertenmodus'**
  String get expertMode;

  /// Expert mode explanation
  ///
  /// In de, this message translates to:
  /// **'Werkzeuge, Exporte und alle Kennzahlen direkt anzeigen'**
  String get expertModeHint;

  /// Tools page title / menu entry
  ///
  /// In de, this message translates to:
  /// **'Werkzeuge'**
  String get toolsTitle;

  /// Tools: diagnostics description
  ///
  /// In de, this message translates to:
  /// **'Programmiermodus, Adressen prüfen, Geräteinfo, Linienscan'**
  String get toolDiagnostics;

  /// Tools: project check description
  ///
  /// In de, this message translates to:
  /// **'Busverkehr mit dem ETS-Projekt abgleichen'**
  String get toolCheck;

  /// Tools: statistics description
  ///
  /// In de, this message translates to:
  /// **'Häufigste Adressen und Absender, Ausreißer'**
  String get toolStats;

  /// Tools: communication map description
  ///
  /// In de, this message translates to:
  /// **'Wer spricht mit wem'**
  String get toolMap;

  /// Tools: trigger description
  ///
  /// In de, this message translates to:
  /// **'Aufnahme automatisch bei einem Ereignis starten'**
  String get toolTrigger;

  /// Tools: recordings description
  ///
  /// In de, this message translates to:
  /// **'Gespeicherte Aufnahmen und Langzeitverlauf'**
  String get toolRecordings;

  /// Menu entry opening the export sheet
  ///
  /// In de, this message translates to:
  /// **'Exportieren'**
  String get exportMenu;

  /// No description provided for @planFeatureFullExport.
  ///
  /// In de, this message translates to:
  /// **'Volle Exporte: ETS-Datei, ZIP, Diagramme'**
  String get planFeatureFullExport;

  /// Export sheet: start selection
  ///
  /// In de, this message translates to:
  /// **'Telegramme auswählen …'**
  String get exportSelect;

  /// Export sheet: selection hint
  ///
  /// In de, this message translates to:
  /// **'Nur bestimmte Telegramme als PDF, CSV oder ETS-Datei'**
  String get exportSelectHint;

  /// Menu entry opening the project sheet
  ///
  /// In de, this message translates to:
  /// **'ETS-Projekt'**
  String get projectMenu;

  /// Remove imported project
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get projectRemove;

  /// Hint above overview when no project is loaded
  ///
  /// In de, this message translates to:
  /// **'Ohne ETS-Projekt siehst du nur Rohwerte. Mit Projekt erscheinen Namen, Einheiten und Geräte.'**
  String get projectHintRaw;

  /// Dismiss a hint
  ///
  /// In de, this message translates to:
  /// **'Ausblenden'**
  String get commonDismiss;

  /// Countdown until automatic reconnect
  ///
  /// In de, this message translates to:
  /// **'Neuer Versuch in {seconds} s'**
  String monitorRetryIn(int seconds);

  /// Menu: pin a section to the top
  ///
  /// In de, this message translates to:
  /// **'Oben anheften'**
  String get sectionPin;

  /// Menu/tooltip: unpin a section
  ///
  /// In de, this message translates to:
  /// **'Nicht mehr anheften'**
  String get sectionUnpin;

  /// Semantics hint on section headers
  ///
  /// In de, this message translates to:
  /// **'Lange drücken zum Anheften'**
  String get sectionPinHint;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Busmonitor'**
  String get busmonTitle;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Alle Frames auf der Leitung: Quittungen, Wiederholungen, gestörte Telegramme'**
  String get busmonTool;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Zeigt alles auf der Leitung, auch Quittungen und gestörte Telegramme. Der Live-Monitor pausiert so lange und verbindet sich danach wieder.'**
  String get busmonHint;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Busmonitor wird gestartet …'**
  String get busmonConnecting;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Busmonitor nicht möglich: {error}'**
  String busmonFailed(String error);

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get busmonRetry;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Frames'**
  String get busmonFrames;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Telegramme'**
  String get busmonTelegrams;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'ACK'**
  String get busmonAck;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'NAK/BUSY'**
  String get busmonNegative;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Fehler'**
  String get busmonErrors;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Wiederholt'**
  String get busmonRepeated;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Ohne ACK'**
  String get busmonUnacked;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Quittungen ausblenden'**
  String get busmonHideAcks;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Nur Auffälligkeiten'**
  String get busmonOnlyProblems;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Noch nichts auf der Leitung'**
  String get busmonEmpty;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Prüfsumme falsch'**
  String get busmonChecksum;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Übertragungsfehler'**
  String get busmonStatusError;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Einzeladressiert'**
  String get busmonIndividual;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Quittung: angenommen'**
  String get busmonAckText;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Quittung: abgelehnt (NAK)'**
  String get busmonNakText;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Quittung: beschäftigt (BUSY)'**
  String get busmonBusyText;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Quittung: NAK + BUSY'**
  String get busmonNakBusyText;

  /// Bus monitor
  ///
  /// In de, this message translates to:
  /// **'Nicht lesbarer Frame'**
  String get busmonUnknownText;

  /// Overview section with pinned group addresses
  ///
  /// In de, this message translates to:
  /// **'Favoriten'**
  String get favorites;

  /// Tooltip: pin a group address
  ///
  /// In de, this message translates to:
  /// **'Als Favorit oben anheften'**
  String get favoriteAdd;

  /// Tooltip: unpin a group address
  ///
  /// In de, this message translates to:
  /// **'Aus den Favoriten entfernen'**
  String get favoriteRemove;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Buslast'**
  String get busmonLoad;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Belegung der Leitung (TP, 9600 bit/s), Mittel der letzten 10 s. Dauerhaft über 50 % deutet auf Probleme hin.'**
  String get busmonLoadHint;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Spitze {value} %'**
  String busmonLoadPeak(String value);

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Absender'**
  String get busmonSenders;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Geräte mit Wiederholungen oder fehlenden Quittungen zuerst. Tippen filtert die Liste.'**
  String get busmonSendersHint;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Frame-Details'**
  String get busmonDetails;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Frame antippen für Details'**
  String get busmonTapHint;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Steuerfeld'**
  String get busmonFieldControl;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Wiederholung'**
  String get busmonFieldRepeat;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Hop-Count'**
  String get busmonFieldHops;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Länge'**
  String get busmonFieldLength;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Nutzdaten'**
  String get busmonFieldPayload;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Prüfsumme'**
  String get busmonFieldChecksum;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Status'**
  String get busmonFieldStatus;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Gateway-Zeit'**
  String get busmonFieldTimestamp;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Quittung'**
  String get busmonFieldAck;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Quelle'**
  String get busmonFieldSource;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Ziel'**
  String get busmonFieldTarget;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'Rohdaten'**
  String get busmonFieldRaw;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'ja'**
  String get busmonYes;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'nein'**
  String get busmonNo;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'korrekt'**
  String get busmonChecksumOk;

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'falsch (erwartet {expected})'**
  String busmonChecksumBad(String expected);

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'fehlerfrei, Sequenz {seq}'**
  String busmonStatusOk(int seq);

  /// Bus monitor side panel
  ///
  /// In de, this message translates to:
  /// **'{frames} Frames'**
  String busmonSenderStats(int frames);

  /// Notification title for an alarm
  ///
  /// In de, this message translates to:
  /// **'Alarm: {name}'**
  String notifyAlarmTitle(String name);

  /// Notification title for a fault
  ///
  /// In de, this message translates to:
  /// **'Störung: {name}'**
  String notifyFaultTitle(String name);

  /// Menu toggle for alarm notifications
  ///
  /// In de, this message translates to:
  /// **'Alarm-Mitteilungen'**
  String get notifyMenu;

  /// Empty state when a filter hides everything
  ///
  /// In de, this message translates to:
  /// **'Nichts passt zum Filter'**
  String get filterNoMatch;

  /// Empty monitor explanation
  ///
  /// In de, this message translates to:
  /// **'Viele Geräte senden nur bei Änderung. Den aktuellen Stand kannst du aktiv abfragen.'**
  String get emptyMonitorHint;

  /// Empty monitor action: open status read
  ///
  /// In de, this message translates to:
  /// **'Status lesen'**
  String get emptyReadStatus;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Topologie'**
  String get topoTitle;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Linien, Koppler und linienübergreifende Kommunikation'**
  String get topoTool;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Aus ETS-Projekt und beobachtetem Verkehr. Das Gateway sieht seine eigene Linie und nur das, was Koppler aus anderen Linien weiterleiten. Der Hop-Count zeigt, über wie viele Koppler ein Telegramm kam.'**
  String get topoHint;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Linie {line}'**
  String topoLine(String line);

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Gateway'**
  String get topoGatewayHere;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Geräte'**
  String get topoDevices;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Aktiv'**
  String get topoActive;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Telegramme'**
  String get topoTelegrams;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Koppler bis Gateway'**
  String get topoCouplers;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Koppler {address} · {name}'**
  String topoCoupler(String address, String name);

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'nicht im Projekt (Tunnel/Visu?)'**
  String get topoNotInProject;

  /// Topology tool: sender 15.15.255, the factory address of KNX devices and of the KNX HAT in a Busclear Box
  ///
  /// In de, this message translates to:
  /// **'Werksadresse (Box-Modul oder neues Gerät?)'**
  String get topoFactoryAddress;

  /// Topology tool: device whose address names a line that is not in the project, but which sits on the gateway line
  ///
  /// In de, this message translates to:
  /// **'Die Adresse gehört zu Linie {line}, die es im Projekt nicht gibt. Die Telegramme kommen ohne Koppler an, das Gerät hängt also an Linie {gateway}. Gib ihm eine freie Adresse dieser Linie.'**
  String topoStrayHint(String line, String gateway);

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'nicht gesehen'**
  String get topoSilent;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Linien­über­greifend'**
  String get topoCross;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Adressen mit Geräten in mehreren Linien: welche Linien senden, welche zuhören, und wie viele Telegramme aus anderen Linien schon beobachtet wurden.'**
  String get topoCrossHint;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Koppler prüfen'**
  String get topoCheck;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Liest Adressen, deren sendendes Gerät hinter einem Koppler sitzt. Antwortet es, leitet der Koppler in beide Richtungen weiter. Nur Leseanfragen – es wird nichts geschaltet.'**
  String get topoCheckHint;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Prüfe {done} / {total} …'**
  String topoCheckRunning(int done, int total);

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Antwort von {source}'**
  String topoCheckPassed(String source);

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'keine Antwort – Filtertabelle oder Lesen-Flag'**
  String get topoCheckNoAnswer;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Keine Adresse mit sendendem Gerät hinter einem Koppler.'**
  String get topoCheckNone;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Auffälligkeiten'**
  String get topoIssues;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Keine Auffälligkeiten im bisherigen Verkehr.'**
  String get topoNoIssues;

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'{source} kommt mit Hop-Count {observed} statt {expected} – sitzt wahrscheinlich in einer anderen Linie, als die Adresse sagt.'**
  String topoMismatch(String source, int observed, int expected);

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'{address} {name}: {count}× aus anderer Linie weitergeleitet, obwohl hier laut Projekt niemand zuhört. Für Visualisierungen (X1, Home Assistant) oft gewollt, sonst leitet der Koppler evtl. alles weiter.'**
  String topoUnneeded(String address, String name, int count);

  /// Topology tool
  ///
  /// In de, this message translates to:
  /// **'Für die Topologie wird ein ETS-Projekt (.knxproj) mit Geräten benötigt; ohne Projekt zeigt die Ansicht nur beobachtete Absender.'**
  String get topoNoProject;

  /// Cross-line row: sending lines
  ///
  /// In de, this message translates to:
  /// **'sendet {lines}'**
  String topoSends(String lines);

  /// Cross-line row: listening lines
  ///
  /// In de, this message translates to:
  /// **'hört {lines}'**
  String topoListens(String lines);

  /// Coupler check: path ok, object not readable
  ///
  /// In de, this message translates to:
  /// **'keine Antwort, Telegramme kommen aber durch den Koppler – Lesen-Flag fehlt'**
  String get topoCheckNoReadFlag;

  /// Device sheet: telegrams sent by the device
  ///
  /// In de, this message translates to:
  /// **'Gesendet'**
  String get devSent;

  /// Device sheet: telegrams to addresses the device listens to
  ///
  /// In de, this message translates to:
  /// **'Empfangen'**
  String get devReceived;

  /// Device sheet: number of linked group addresses
  ///
  /// In de, this message translates to:
  /// **'Adressen'**
  String get devGroups;

  /// Device sheet hint
  ///
  /// In de, this message translates to:
  /// **'Telegramme an Gruppenadressen, mit denen das Gerät laut Projekt verknüpft ist.'**
  String get devReceivedHint;

  /// Device sheet: device unknown
  ///
  /// In de, this message translates to:
  /// **'Nicht im Projekt – empfangene Telegramme lassen sich nicht zuordnen.'**
  String get devNoLinks;

  /// Device sheet empty list
  ///
  /// In de, this message translates to:
  /// **'Noch keine Telegramme'**
  String get devNothing;

  /// Device sheet action
  ///
  /// In de, this message translates to:
  /// **'Im Monitor filtern'**
  String get devFilterMonitor;

  /// Device sheet subtitle
  ///
  /// In de, this message translates to:
  /// **'Linie {line} · Hop {hops}'**
  String devLineHops(String line, String hops);

  /// Screen reader hint on a sender that opens its device sheet
  ///
  /// In de, this message translates to:
  /// **'Öffnet das Geräteblatt'**
  String get devOpenHint;

  /// Tooltip/button: filter the live list by all senders of a line
  ///
  /// In de, this message translates to:
  /// **'Linie {line} im Monitor zeigen'**
  String devLineShow(String line);

  /// Title of the project sheet
  ///
  /// In de, this message translates to:
  /// **'ETS-Projekt'**
  String get projectTitle;

  /// Title: list of the project states of an installation
  ///
  /// In de, this message translates to:
  /// **'Projektstände'**
  String get projectStatesTitle;

  /// Project sheet: row that opens the project states
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Projektstand} other{{count} Projektstände}}'**
  String projectStatesRow(int count);

  /// Project states: explanation above the list
  ///
  /// In de, this message translates to:
  /// **'Jedes importierte Projekt gilt ab einem Datum. Telegramme aus der Zeit davor behalten Namen und Datentyp des Stands, der damals galt.'**
  String get projectStatesIntro;

  /// Project states: mark of the current state
  ///
  /// In de, this message translates to:
  /// **'Aktuell'**
  String get projectStateCurrent;

  /// Project states: the oldest state has no start date
  ///
  /// In de, this message translates to:
  /// **'Von Anfang an'**
  String get projectStateFromStart;

  /// Project states: start date of a state
  ///
  /// In de, this message translates to:
  /// **'Seit {date}'**
  String projectStateSince(String date);

  /// Project states: state without project or file name
  ///
  /// In de, this message translates to:
  /// **'Projekt ohne Namen'**
  String get projectStateUnnamed;

  /// Project states: the oldest state has nothing to compare with
  ///
  /// In de, this message translates to:
  /// **'Erster Stand'**
  String get projectStateFirst;

  /// Project states: nothing changed against the state before
  ///
  /// In de, this message translates to:
  /// **'Gruppenadressen unverändert'**
  String get projectStateNoChanges;

  /// Project states: number of added group addresses
  ///
  /// In de, this message translates to:
  /// **'{count} neu'**
  String projectStateAdded(int count);

  /// Project states: number of removed group addresses
  ///
  /// In de, this message translates to:
  /// **'{count} entfernt'**
  String projectStateRemoved(int count);

  /// Project states: number of renamed group addresses
  ///
  /// In de, this message translates to:
  /// **'{count} umbenannt'**
  String projectStateRenamed(int count);

  /// Project states: number of group addresses whose data type changed
  ///
  /// In de, this message translates to:
  /// **'{count} mit neuem Datentyp'**
  String projectStateRetyped(int count);

  /// Project states: section of added group addresses
  ///
  /// In de, this message translates to:
  /// **'Neu'**
  String get projectStateAddedTitle;

  /// Project states: section of removed group addresses
  ///
  /// In de, this message translates to:
  /// **'Entfernt'**
  String get projectStateRemovedTitle;

  /// Project states: section of renamed group addresses
  ///
  /// In de, this message translates to:
  /// **'Umbenannt'**
  String get projectStateRenamedTitle;

  /// Project states: section of group addresses with a changed data type
  ///
  /// In de, this message translates to:
  /// **'Datentyp geändert'**
  String get projectStateRetypedTitle;

  /// Project states: a group address without data type
  ///
  /// In de, this message translates to:
  /// **'ohne Typ'**
  String get projectStateNoType;

  /// Project states: title of the list of changes
  ///
  /// In de, this message translates to:
  /// **'Änderungen zum Stand davor'**
  String get projectStateChanges;

  /// Project states: empty detail side on wide screens
  ///
  /// In de, this message translates to:
  /// **'Wähle einen Stand, um zu sehen, was er geändert hat.'**
  String get projectStateSelect;

  /// Project states: button to correct the start date
  ///
  /// In de, this message translates to:
  /// **'Datum ändern'**
  String get projectStateSetDate;

  /// Project states: title of the date picker (e.g. the day the installation was reprogrammed)
  ///
  /// In de, this message translates to:
  /// **'Ab wann gilt dieser Stand?'**
  String get projectStateDateHelp;

  /// Project states: the date cannot be changed
  ///
  /// In de, this message translates to:
  /// **'Zwischen dem Stand davor und dem danach liegt kein freier Tag.'**
  String get projectStateDateNoRoom;

  /// Project states: button and dialog title
  ///
  /// In de, this message translates to:
  /// **'Stand entfernen'**
  String get projectStateRemove;

  /// Project states: confirm removing the current state
  ///
  /// In de, this message translates to:
  /// **'Das Projekt davor wird wieder das aktuelle. Das importierte Projekt ist dann weg.'**
  String get projectStateRemoveCurrent;

  /// Project states: confirm removing a state in the middle
  ///
  /// In de, this message translates to:
  /// **'Der Stand davor gilt dann bis zum nächsten Stand. Alte Telegramme aus dieser Zeit tragen dann dessen Namen.'**
  String get projectStateRemovePast;

  /// Project states: confirm removing the oldest state
  ///
  /// In de, this message translates to:
  /// **'Der nächste Stand gilt dann von Anfang an.'**
  String get projectStateRemoveOldest;

  /// Details of an old telegram: it is named with an older project state
  ///
  /// In de, this message translates to:
  /// **'Name und Datentyp nach dem Projektstand, der bis {date} galt.'**
  String projectStateNote(String date);

  /// Details of an old telegram: the name of the address in the current project
  ///
  /// In de, this message translates to:
  /// **'Heute: {name}'**
  String projectStateNoteToday(String name);

  /// Details of an old telegram: the address is not in the current project
  ///
  /// In de, this message translates to:
  /// **'Im heutigen Projekt gibt es diese Adresse nicht mehr.'**
  String get projectStateNoteGone;

  /// Recording from before the current project state: quiet line above the content
  ///
  /// In de, this message translates to:
  /// **'Vor dem {date} aufgenommen: Namen und Datentypen nach dem Projektstand von damals.'**
  String projectStateRecordingNote(String date);

  /// Confirm deleting history
  ///
  /// In de, this message translates to:
  /// **'Gesamten Langzeitverlauf löschen? Das lässt sich nicht rückgängig machen.'**
  String get historyDeleteConfirm;

  /// Activity bar range label
  ///
  /// In de, this message translates to:
  /// **'letzte Stunde'**
  String get activityLastHour;

  /// Activity bar range label
  ///
  /// In de, this message translates to:
  /// **'heute'**
  String get activityToday;

  /// No description provided for @livePlainTitle.
  ///
  /// In de, this message translates to:
  /// **'Klartext in Live'**
  String get livePlainTitle;

  /// No description provided for @livePlainHint.
  ///
  /// In de, this message translates to:
  /// **'Sätze statt Adressen'**
  String get livePlainHint;

  /// Tooltip on the activity range label
  ///
  /// In de, this message translates to:
  /// **'Tippen wechselt den Zeitraum'**
  String get activityRangeHint;

  /// Sektion der Übersicht: Heizungsventile, Stellantriebe, Stellgrößen
  ///
  /// In de, this message translates to:
  /// **'Ventile & Stellgrößen'**
  String get boardValves;

  /// Linienscan: eigene Tunneladresse
  ///
  /// In de, this message translates to:
  /// **'Tunnel dieser App'**
  String get diagOwnTunnel;

  /// Linienscan: nicht im Projekt, aber wahrscheinlich weitere Tunneladresse des Gateways
  ///
  /// In de, this message translates to:
  /// **'vermutlich Tunnel von {name}'**
  String diagGatewayTunnel(String name);

  /// Topologie: Kennzahl/Liste der Tunneladressen von IP-Schnittstellen
  ///
  /// In de, this message translates to:
  /// **'Tunnel'**
  String get topoTunnels;

  /// Kommunikationskarte: zurück zur Liste aller Adressen und Geräte
  ///
  /// In de, this message translates to:
  /// **'Übersicht'**
  String get mapOverview;

  /// Kommunikationskarte, Übersicht: Liste der Gruppenadressen
  ///
  /// In de, this message translates to:
  /// **'Gruppenadressen'**
  String get mapGroups;

  /// Kommunikationskarte, Übersicht: Liste der Geräte
  ///
  /// In de, this message translates to:
  /// **'Geräte'**
  String get mapDevices;

  /// Werkzeug: Inbetriebnahme-Checkliste
  ///
  /// In de, this message translates to:
  /// **'Inbetriebnahme'**
  String get commTitle;

  /// Werkzeugliste: Untertitel Inbetriebnahme
  ///
  /// In de, this message translates to:
  /// **'Status-Adressen lesen, abhaken, Protokoll als PDF'**
  String get commTool;

  /// Inbetriebnahme: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Liest Status- und Rückmeldeadressen nacheinander (5 pro Sekunde). Antworten werden automatisch abgehakt; Punkte ohne Antwort oder vor Ort geprüfte Funktionen bewertest du von Hand. Die Liste bleibt gespeichert, bis du neu beginnst.'**
  String get commExplain;

  /// Inbetriebnahme: Gerät hat geantwortet
  ///
  /// In de, this message translates to:
  /// **'Beantwortet'**
  String get commAnswered;

  /// Inbetriebnahme: von Hand abgehakt
  ///
  /// In de, this message translates to:
  /// **'In Ordnung'**
  String get commOk;

  /// Inbetriebnahme: keine Antwort auf Leseanfrage
  ///
  /// In de, this message translates to:
  /// **'Keine Antwort'**
  String get commNoAnswer;

  /// Inbetriebnahme: von Hand als Problem markiert
  ///
  /// In de, this message translates to:
  /// **'Problem'**
  String get commIssue;

  /// Inbetriebnahme: noch nicht geprüft
  ///
  /// In de, this message translates to:
  /// **'Offen'**
  String get commOpen;

  /// Inbetriebnahme-Filter: beantwortet oder in Ordnung
  ///
  /// In de, this message translates to:
  /// **'Erledigt'**
  String get commDone;

  /// Inbetriebnahme-Filter: alle Prüfpunkte
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get commFilterAll;

  /// Inbetriebnahme: Anzahl geprüfter Punkte
  ///
  /// In de, this message translates to:
  /// **'Geprüft'**
  String get commChecked;

  /// Inbetriebnahme-PDF: Beginn der Prüfung
  ///
  /// In de, this message translates to:
  /// **'Begonnen'**
  String get commStarted;

  /// Titel des Inbetriebnahme-PDFs
  ///
  /// In de, this message translates to:
  /// **'Inbetriebnahme-Protokoll'**
  String get commPdfTitle;

  /// PDF-Unterschriftsfeld
  ///
  /// In de, this message translates to:
  /// **'Geprüft von'**
  String get commSignedBy;

  /// PDF-Unterschriftsfeld
  ///
  /// In de, this message translates to:
  /// **'Datum'**
  String get commDate;

  /// PDF-Unterschriftsfeld
  ///
  /// In de, this message translates to:
  /// **'Unterschrift'**
  String get commSignature;

  /// Inbetriebnahme: Start
  ///
  /// In de, this message translates to:
  /// **'Anlegen und lesen ({count})'**
  String commStart(int count);

  /// Inbetriebnahme: offene und unbeantwortete erneut lesen
  ///
  /// In de, this message translates to:
  /// **'Offene lesen ({count})'**
  String commReadOpen(int count);

  /// Inbetriebnahme: alle erneut lesen
  ///
  /// In de, this message translates to:
  /// **'Alle erneut lesen'**
  String get commReadAll;

  /// Inbetriebnahme: einzelne Adresse lesen
  ///
  /// In de, this message translates to:
  /// **'Erneut lesen'**
  String get commReadOne;

  /// Inbetriebnahme: Prüfpunkt wieder offen
  ///
  /// In de, this message translates to:
  /// **'Zurücksetzen'**
  String get commReset;

  /// Inbetriebnahme: Notiz zum Prüfpunkt
  ///
  /// In de, this message translates to:
  /// **'Notiz'**
  String get commNote;

  /// Inbetriebnahme: alles verwerfen
  ///
  /// In de, this message translates to:
  /// **'Neu beginnen'**
  String get commRestart;

  /// Inbetriebnahme: Rückfrage Neu beginnen
  ///
  /// In de, this message translates to:
  /// **'Alle Ergebnisse und Notizen verwerfen und eine neue Checkliste anlegen?'**
  String get commRestartConfirm;

  /// Inbetriebnahme ohne Projekt
  ///
  /// In de, this message translates to:
  /// **'Für die Checkliste braucht es ein ETS-Projekt mit Gruppenadressen.'**
  String get commNoProject;

  /// Werkzeug: Gesundheitsprüfung
  ///
  /// In de, this message translates to:
  /// **'Gesundheit'**
  String get healthTitle;

  /// Werkzeugliste: Untertitel Gesundheit
  ///
  /// In de, this message translates to:
  /// **'Bekannte Adressen lesen, Zyklen, Werte und Datentypen prüfen'**
  String get healthTool;

  /// Gesundheit: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Liest Status-Adressen und alles, was schon einmal geantwortet hat. Dazu: Wer sendet sonst regelmäßig und ist jetzt still? Sind Messwerte plausibel? Passen Länge und Wert zum DPT? Wie ist die Busqualität? Neue Befunde seit dem letzten Lauf stehen oben.'**
  String get healthExplain;

  /// Gesundheit: Start
  ///
  /// In de, this message translates to:
  /// **'Jetzt prüfen ({count} Adressen)'**
  String healthRunNow(int count);

  /// Gesundheit: ohne Leseanfragen
  ///
  /// In de, this message translates to:
  /// **'Nur auswerten'**
  String get healthPassive;

  /// Gesundheit: Einstellung Automatik
  ///
  /// In de, this message translates to:
  /// **'Automatisch nach dem Verbinden (höchstens 1× pro Tag)'**
  String get healthAuto;

  /// Gesundheit: Zeitpunkt
  ///
  /// In de, this message translates to:
  /// **'Letzter Lauf {time}'**
  String healthLastRun(String time);

  /// Gesundheit: noch nie geprüft
  ///
  /// In de, this message translates to:
  /// **'Noch kein Lauf'**
  String get healthNever;

  /// Gesundheit: Stand während des Lesetests
  ///
  /// In de, this message translates to:
  /// **'Läuft … {sent} von {total} gelesen'**
  String healthRunning(int sent, int total);

  /// Gesundheit: Bereich
  ///
  /// In de, this message translates to:
  /// **'Lesetest'**
  String get healthAreaRead;

  /// Gesundheit: Bereich
  ///
  /// In de, this message translates to:
  /// **'Zyklen'**
  String get healthAreaCycle;

  /// Gesundheit: Bereich
  ///
  /// In de, this message translates to:
  /// **'Werte'**
  String get healthAreaValues;

  /// Gesundheit: Bereich
  ///
  /// In de, this message translates to:
  /// **'Datentypen'**
  String get healthAreaDpt;

  /// Gesundheit: Bereich
  ///
  /// In de, this message translates to:
  /// **'Bus'**
  String get healthAreaBus;

  /// Gesundheit: alles in Ordnung
  ///
  /// In de, this message translates to:
  /// **'Keine Befunde'**
  String get healthAllGood;

  /// Gesundheit: Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Neu seit letztem Lauf'**
  String get healthNewSection;

  /// Gesundheit: Lesetest-Ergebnis
  ///
  /// In de, this message translates to:
  /// **'{answered} von {asked} antworten'**
  String healthAnswered(int answered, int asked);

  /// Gesundheit: frühere Läufe
  ///
  /// In de, this message translates to:
  /// **'Verlauf'**
  String get healthHistory;

  /// Gesundheit: Problemadressen in die Checkliste
  ///
  /// In de, this message translates to:
  /// **'In Inbetriebnahme übernehmen'**
  String get healthToCommissioning;

  /// Gesundheit: Bestätigung
  ///
  /// In de, this message translates to:
  /// **'{count} Adressen in die Inbetriebnahme übernommen'**
  String healthAddedToCommissioning(int count);

  /// Titel des Gesundheits-PDFs
  ///
  /// In de, this message translates to:
  /// **'Gesundheitsprüfung'**
  String get healthPdfTitle;

  /// Mitteilung nach Gesundheitsprüfung
  ///
  /// In de, this message translates to:
  /// **'KNX: {count, plural, =1{1 neuer Befund} other{{count} neue Befunde}}'**
  String healthNotifyTitle(int count);

  /// Letzte Zeile der Befund-Mitteilung: wie viele Befunde nicht aufgeführt sind und wo die Einzelheiten stehen
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{Einzelheiten in Busclear unter „Gesundheit“} =1{… und 1 weiterer. Einzelheiten in Busclear unter „Gesundheit“} other{… und {count} weitere. Einzelheiten in Busclear unter „Gesundheit“}}'**
  String healthNotifyMore(int count);

  /// Gesundheit: Kennzeichen neuer Befund
  ///
  /// In de, this message translates to:
  /// **'neu'**
  String get healthNew;

  /// Gesundheit: Nutzdaten im APCI
  ///
  /// In de, this message translates to:
  /// **'≤ 6 Bit'**
  String get healthBits;

  /// Gesundheit: Nutzdatenlänge
  ///
  /// In de, this message translates to:
  /// **'{count} Byte'**
  String healthBytes(int count);

  /// Befund: neu stumm
  ///
  /// In de, this message translates to:
  /// **'Antwortet nicht mehr – zuletzt {time}'**
  String healthNewSilent(String time);

  /// Befund: immer stumm
  ///
  /// In de, this message translates to:
  /// **'Hat noch nie auf Lesen geantwortet – Lese-Flag prüfen'**
  String get healthAlwaysSilent;

  /// Befund: überfällig
  ///
  /// In de, this message translates to:
  /// **'Sendet sonst alle {interval}, zuletzt {time}'**
  String healthOverdue(String interval, String time);

  /// Befund: Wert außerhalb
  ///
  /// In de, this message translates to:
  /// **'Unplausibler Wert {value} von {sender}'**
  String healthOutOfRange(String value, String sender);

  /// Befund: hängender Messwert
  ///
  /// In de, this message translates to:
  /// **'Seit {time} unverändert {value}'**
  String healthStuck(String value, String time);

  /// Befund: Länge passt nicht zum DPT
  ///
  /// In de, this message translates to:
  /// **'{sender} sendet {actual}, DPT {dpt} erwartet {expected} ({count}×)'**
  String healthDptSize(String sender, String actual, String dpt, String expected, int count);

  /// Befund: ungültiger Wert
  ///
  /// In de, this message translates to:
  /// **'{sender} sendet ungültigen Wert {raw} ({count}×)'**
  String healthDptValue(String sender, String raw, int count);

  /// Befund: uneinheitliche Länge
  ///
  /// In de, this message translates to:
  /// **'Ohne DPT im Projekt – Sender schicken {count} verschiedene Längen'**
  String healthMixedSizes(int count);

  /// Befund: viele Wiederholungen
  ///
  /// In de, this message translates to:
  /// **'Wiederholt {rate} % von {count} Telegrammen – Quittungen prüfen'**
  String healthRepeats(String rate, int count);

  /// Befund: unbeantwortete fremde Leseanfragen
  ///
  /// In de, this message translates to:
  /// **'{count} Leseanfragen anderer Geräte ohne Antwort'**
  String healthUnansweredReads(int count);

  /// Befund: Status-Adresse ohne Verknüpfung
  ///
  /// In de, this message translates to:
  /// **'Kein Gerät im Projekt verknüpft – kann nicht antworten (Platzhalter oder Altlast?)'**
  String get healthUnlinked;

  /// Befund: immer stumm, mit Sender laut Projekt
  ///
  /// In de, this message translates to:
  /// **'Hat noch nie geantwortet – Lese-Flag am sendenden Objekt prüfen: {sender}'**
  String healthAlwaysSilentAt(String sender);

  /// DALI: Titel der Ansicht Beleuchtung (DALI-Gateways)
  ///
  /// In de, this message translates to:
  /// **'DALI-Beleuchtung'**
  String get daliTitle;

  /// DALI: Untertitel des Werkzeugs im Menü
  ///
  /// In de, this message translates to:
  /// **'DALI-Gateways: Leuchten, Fehler, Notlicht'**
  String get daliTool;

  /// DALI: Erklärung der Ansicht hinter dem Info-Symbol
  ///
  /// In de, this message translates to:
  /// **'Zeigt, was deine KNX-DALI-Gateways auf den Bus melden: Lampen- und EVG-Fehler je Leuchte und den Zustand der Notleuchten. Busclear sieht nur, was das Gateway auf KNX sendet. Kurzadressen und Gruppen vergibst du weiter im Werkzeug des Gateways.'**
  String get daliExplain;

  /// DALI: Bezeichnung eines Gateways ohne Namen
  ///
  /// In de, this message translates to:
  /// **'DALI-Gateway'**
  String get daliGateway;

  /// DALI: Gateway mit physikalischer Adresse
  ///
  /// In de, this message translates to:
  /// **'Gateway {address}'**
  String daliGatewayAt(String address);

  /// DALI: Leuchte ohne Namen, mit Kurzadresse (EVG = Vorschaltgerät)
  ///
  /// In de, this message translates to:
  /// **'EVG {address}'**
  String daliGearN(int address);

  /// DALI: Gruppe ohne Namen
  ///
  /// In de, this message translates to:
  /// **'Gruppe {group}'**
  String daliGroupN(int group);

  /// DALI: Notleuchte ohne Namen, mit Kurzadresse
  ///
  /// In de, this message translates to:
  /// **'Notlicht {address}'**
  String daliEmergencyN(int address);

  /// DALI: Notleuchte ohne bekannte Kurzadresse, mit Gruppenadresse ihres Objekts
  ///
  /// In de, this message translates to:
  /// **'Notleuchte an {group}'**
  String daliEmergencyAt(String group);

  /// DALI: Kennzeichen Notleuchte
  ///
  /// In de, this message translates to:
  /// **'Notleuchte'**
  String get daliEmergencyLuminaire;

  /// DALI: Überschrift Notleuchten
  ///
  /// In de, this message translates to:
  /// **'Notleuchten'**
  String get daliEmergencyLuminaires;

  /// DALI: Buchstabe, der eine Notleuchte kennzeichnet
  ///
  /// In de, this message translates to:
  /// **'N'**
  String get daliEmergencyLetter;

  /// DALI: Anzahl Notleuchten einer Gruppe
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Notleuchte} other{{count} Notleuchten}}'**
  String daliEmergencyCount(int count);

  /// DALI: Zustand ohne Fehler
  ///
  /// In de, this message translates to:
  /// **'in Ordnung'**
  String get daliOk;

  /// DALI: Merker Lampenfehler
  ///
  /// In de, this message translates to:
  /// **'Lampenfehler'**
  String get daliLampFault;

  /// DALI: Merker Fehler des Vorschaltgeräts
  ///
  /// In de, this message translates to:
  /// **'EVG-Fehler'**
  String get daliGearFault;

  /// DALI: Merker Konverterfehler (Notlicht)
  ///
  /// In de, this message translates to:
  /// **'Konverterfehler'**
  String get daliConverterFault;

  /// DALI: Zustand einer Leuchte, die noch nichts gemeldet hat
  ///
  /// In de, this message translates to:
  /// **'noch keine Meldung'**
  String get daliNoReport;

  /// DALI: Wert unbekannt
  ///
  /// In de, this message translates to:
  /// **'unbekannt'**
  String get daliUnknown;

  /// DALI: Telegramm ist eine Abfrage an das Gateway (Lese-Merker gesetzt)
  ///
  /// In de, this message translates to:
  /// **'Abfrage'**
  String get daliQuery;

  /// DALI: Merker gesetzt
  ///
  /// In de, this message translates to:
  /// **'gesetzt'**
  String get daliFlagSet;

  /// DALI: Merker nicht gesetzt
  ///
  /// In de, this message translates to:
  /// **'nicht gesetzt'**
  String get daliFlagClear;

  /// DALI: Beschriftung des Rohwerts in Hex
  ///
  /// In de, this message translates to:
  /// **'Rohwert'**
  String get daliRaw;

  /// DALI: Datenpunkttyp in der Abschnittsüberschrift
  ///
  /// In de, this message translates to:
  /// **'DPT {dpt}'**
  String daliDptShort(String dpt);

  /// DALI: Name der Typen 237.600 und 238.600 in der Typauswahl
  ///
  /// In de, this message translates to:
  /// **'DALI-Diagnose'**
  String get daliDptDiagnostic;

  /// DALI: Name des Typs 244.600 in der Typauswahl
  ///
  /// In de, this message translates to:
  /// **'DALI-Notlicht Status'**
  String get daliDptConverterStatus;

  /// DALI: Name des Typs 245.600 in der Typauswahl
  ///
  /// In de, this message translates to:
  /// **'DALI-Notlicht Testergebnis'**
  String get daliDptTestResult;

  /// DALI-Details: Zeile, ob die Adresse ein Gerät oder eine Gruppe ist
  ///
  /// In de, this message translates to:
  /// **'Adresse meint'**
  String get daliRowAddressKind;

  /// DALI-Details: Adresse ist ein Gerät
  ///
  /// In de, this message translates to:
  /// **'Gerät'**
  String get daliRowKindDevice;

  /// DALI-Details: Adresse ist eine Gruppe
  ///
  /// In de, this message translates to:
  /// **'Gruppe'**
  String get daliRowKindGroup;

  /// DALI-Details: Zeile DALI-Adresse
  ///
  /// In de, this message translates to:
  /// **'DALI-Adresse'**
  String get daliRowAddress;

  /// DALI-Details: Zeile Lese-Merker
  ///
  /// In de, this message translates to:
  /// **'Abfrage an das Gateway'**
  String get daliRowQuery;

  /// DALI-Details: Zeile Betriebsart des Konverters
  ///
  /// In de, this message translates to:
  /// **'Betriebsart'**
  String get daliRowMode;

  /// DALI-Details: Zeile Konverterfehler
  ///
  /// In de, this message translates to:
  /// **'Konverterfehler'**
  String get daliRowFailure;

  /// DALI-Details: Zeile, ob ein Test ansteht
  ///
  /// In de, this message translates to:
  /// **'{test} steht an'**
  String daliRowPending(String test);

  /// DALI-Details: Zeile festverdrahteter Schalteingang
  ///
  /// In de, this message translates to:
  /// **'Schalteingang aktiv'**
  String get daliRowHardwiredSwitch;

  /// DALI-Details: Zeile festverdrahteter Sperreingang
  ///
  /// In de, this message translates to:
  /// **'Sperreingang aktiv'**
  String get daliRowHardwiredInhibit;

  /// DALI-Details: Zeile Ergebnis des letzten Tests
  ///
  /// In de, this message translates to:
  /// **'Letzter {test}'**
  String daliRowLast(String test);

  /// DALI-Details: Zeile Startart des letzten Tests
  ///
  /// In de, this message translates to:
  /// **'{test} gestartet'**
  String daliRowStarted(String test);

  /// DALI-Details: Zeile Entladedauer
  ///
  /// In de, this message translates to:
  /// **'Entladedauer im letzten Dauertest'**
  String get daliRowDischarge;

  /// DALI-Details: Zeile Akkuladung
  ///
  /// In de, this message translates to:
  /// **'Akkuladung nach Teil-Dauertest'**
  String get daliRowCharge;

  /// DALI: Betriebsart des Konverters unbekannt
  ///
  /// In de, this message translates to:
  /// **'Betriebsart unbekannt'**
  String get daliModeUnknown;

  /// DALI: Betriebsart Normalbetrieb
  ///
  /// In de, this message translates to:
  /// **'Normalbetrieb'**
  String get daliModeNormal;

  /// DALI: Betriebsart Sperrbetrieb (Inhibit)
  ///
  /// In de, this message translates to:
  /// **'gesperrt'**
  String get daliModeInhibit;

  /// DALI: Betriebsart Sperre über festverdrahteten Eingang
  ///
  /// In de, this message translates to:
  /// **'über Eingang gesperrt'**
  String get daliModeHardwiredInhibit;

  /// DALI: Betriebsart Ruhebetrieb (Rest Mode)
  ///
  /// In de, this message translates to:
  /// **'Ruhebetrieb'**
  String get daliModeRest;

  /// DALI: Betriebsart Notbetrieb
  ///
  /// In de, this message translates to:
  /// **'Notbetrieb'**
  String get daliModeEmergency;

  /// DALI: Betriebsart verlängerter Notbetrieb
  ///
  /// In de, this message translates to:
  /// **'verlängerter Notbetrieb'**
  String get daliModeExtendedEmergency;

  /// DALI: Betriebsart Funktionstest läuft
  ///
  /// In de, this message translates to:
  /// **'Funktionstest läuft'**
  String get daliModeFunctionTest;

  /// DALI: Betriebsart Dauertest läuft
  ///
  /// In de, this message translates to:
  /// **'Dauertest läuft'**
  String get daliModeDurationTest;

  /// DALI: Betriebsart Teil-Dauertest läuft
  ///
  /// In de, this message translates to:
  /// **'Teil-Dauertest läuft'**
  String get daliModePartialTest;

  /// DALI: Testart Funktionstest
  ///
  /// In de, this message translates to:
  /// **'Funktionstest'**
  String get daliTestFunction;

  /// DALI: Testart Dauertest
  ///
  /// In de, this message translates to:
  /// **'Dauertest'**
  String get daliTestDuration;

  /// DALI: Testart Teil-Dauertest
  ///
  /// In de, this message translates to:
  /// **'Teil-Dauertest'**
  String get daliTestPartial;

  /// DALI: Testergebnis bestanden
  ///
  /// In de, this message translates to:
  /// **'bestanden'**
  String get daliOutcomePassed;

  /// DALI: Testergebnis bestanden, aber nach der zulässigen Verzögerung
  ///
  /// In de, this message translates to:
  /// **'bestanden (verspätet)'**
  String get daliOutcomePassedLate;

  /// DALI: Testergebnis durchgefallen
  ///
  /// In de, this message translates to:
  /// **'durchgefallen'**
  String get daliOutcomeFailed;

  /// DALI: Testergebnis durchgefallen und verspätet
  ///
  /// In de, this message translates to:
  /// **'durchgefallen (verspätet)'**
  String get daliOutcomeFailedLate;

  /// DALI: Test von Hand abgebrochen
  ///
  /// In de, this message translates to:
  /// **'abgebrochen'**
  String get daliOutcomeStopped;

  /// DALI: Testergebnis-Telegramm ohne bekanntes Ergebnis
  ///
  /// In de, this message translates to:
  /// **'kein Testergebnis'**
  String get daliNoTestResult;

  /// DALI: Test automatisch gestartet
  ///
  /// In de, this message translates to:
  /// **'automatisch'**
  String get daliStartAutomatic;

  /// DALI: Test vom Gateway gestartet
  ///
  /// In de, this message translates to:
  /// **'vom Gateway'**
  String get daliStartGateway;

  /// DALI: Grund, Test nach der zulässigen Verzögerung
  ///
  /// In de, this message translates to:
  /// **'verspätet'**
  String get daliReasonLate;

  /// DALI: Grund Akku
  ///
  /// In de, this message translates to:
  /// **'Akku'**
  String get daliReasonBattery;

  /// DALI: Grund Lampe
  ///
  /// In de, this message translates to:
  /// **'Lampe'**
  String get daliReasonLamp;

  /// DALI: Grund Dauer zu kurz
  ///
  /// In de, this message translates to:
  /// **'Dauer zu kurz'**
  String get daliReasonDuration;

  /// DALI: Dauer in Minuten
  ///
  /// In de, this message translates to:
  /// **'{minutes} min'**
  String daliMinutes(int minutes);

  /// DALI: größter meldbarer Wert der Entladedauer
  ///
  /// In de, this message translates to:
  /// **'510 min oder länger'**
  String get daliMinutesMax;

  /// DALI: Wert passt nicht, falsche Länge
  ///
  /// In de, this message translates to:
  /// **'DPT {dpt} erwartet {expected} Byte, empfangen {actual}.'**
  String daliMismatchLength(String dpt, int expected, int actual);

  /// DALI: Wert passt nicht, reservierte Werte
  ///
  /// In de, this message translates to:
  /// **'Der Wert enthält für DPT {dpt} reservierte Bits oder Werte.'**
  String daliMismatchReserved(String dpt);

  /// DALI: Hinweis zu einem Wert, der nicht zum Typ passt
  ///
  /// In de, this message translates to:
  /// **'Busclear zeigt darum den Rohwert. Gehört das Objekt zu einem herstellereigenen Format, hilft ein Auszug im Issue auf GitHub.'**
  String get daliMismatchHint;

  /// DALI-Details: Knopf öffnet die Beleuchtungs-Ansicht bei der Leuchte
  ///
  /// In de, this message translates to:
  /// **'Zur Leuchte'**
  String get daliOpenLuminaire;

  /// DALI-Details: Knopf öffnet die Beleuchtungs-Ansicht
  ///
  /// In de, this message translates to:
  /// **'Zur Beleuchtung'**
  String get daliOpenView;

  /// DALI: seit wie vielen Tagen ein Fehler ansteht
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{seit 1 Tag} other{seit {count} Tagen}}'**
  String daliSinceDays(int count);

  /// DALI: seit wie vielen Stunden
  ///
  /// In de, this message translates to:
  /// **'seit {count} Std.'**
  String daliSinceHours(int count);

  /// DALI: seit wie vielen Minuten
  ///
  /// In de, this message translates to:
  /// **'seit {count} Min.'**
  String daliSinceMinutes(int count);

  /// DALI: Fehler seit weniger als einer Minute
  ///
  /// In de, this message translates to:
  /// **'gerade eben'**
  String get daliSinceNow;

  /// DALI: Testergebnis von heute
  ///
  /// In de, this message translates to:
  /// **'heute'**
  String get daliAgoToday;

  /// DALI: Testergebnis vor Tagen
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{vor 1 Tag} other{vor {count} Tagen}}'**
  String daliAgoDays(int count);

  /// DALI: Testergebnis vor Monaten
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{vor 1 Monat} other{vor {count} Monaten}}'**
  String daliAgoMonths(int count);

  /// DALI-Mitteilung: Titel bei einem Fehler, z. B. Lampenfehler: Flur EG Leuchte 2
  ///
  /// In de, this message translates to:
  /// **'{fault}: {name}'**
  String daliNotifyFault(String fault, String name);

  /// DALI-Mitteilung: Titel, wenn der Fehler zurückgenommen wurde
  ///
  /// In de, this message translates to:
  /// **'Wieder in Ordnung: {name}'**
  String daliNotifyOk(String name);

  /// Gesundheit Beleuchtung: Lampenfehler hinter einem Gateway
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Leuchte meldet Lampenfehler} other{{count} Leuchten melden Lampenfehler}}'**
  String daliHealthLampFault(int count);

  /// Gesundheit Beleuchtung: EVG- oder Konverterfehler hinter einem Gateway
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 EVG meldet einen Fehler} other{{count} EVG melden Fehler}}'**
  String daliHealthGearFault(int count);

  /// Gesundheit Beleuchtung: Gateway sendet nicht mehr
  ///
  /// In de, this message translates to:
  /// **'Gateway hat sich seit {when} nicht gemeldet'**
  String daliHealthSilent(String when);

  /// Gesundheit Beleuchtung: Notleuchten ohne Testergebnis im Prüfabstand
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Notleuchte überfällig} other{{count} Notleuchten überfällig}}'**
  String daliHealthTestOverdue(int count);

  /// Gesundheit Beleuchtung: Notleuchten mit durchgefallenem Test
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Notleuchte mit durchgefallenem Test} other{{count} Notleuchten mit durchgefallenem Test}}'**
  String daliHealthTestFailed(int count);

  /// Gesundheit: Bereich Beleuchtung (DALI)
  ///
  /// In de, this message translates to:
  /// **'Beleuchtung'**
  String get daliHealthArea;

  /// Wochenbericht: Beleuchtungs-Befund mit Gateway
  ///
  /// In de, this message translates to:
  /// **'{finding} ({gateway})'**
  String daliPlainFinding(String finding, String gateway);

  /// DALI: leerer Zustand der Ansicht
  ///
  /// In de, this message translates to:
  /// **'Kein DALI-Gateway erkannt.'**
  String get daliEmptyTitle;

  /// DALI: leerer Zustand, was zu tun ist
  ///
  /// In de, this message translates to:
  /// **'Importiere dein ETS-Projekt oder lass die App mithören, während das Gateway Status sendet. Ohne Projekt wählst du in den Details der Diagnose-Adresse den Typ „DALI-Diagnose“.'**
  String get daliEmptyDetail;

  /// DALI: Knopf ETS-Projekt importieren
  ///
  /// In de, this message translates to:
  /// **'ETS-Projekt'**
  String get daliEmptyProject;

  /// DALI: Knopf Anlernen durch Mithören
  ///
  /// In de, this message translates to:
  /// **'Mithören'**
  String get daliEmptyListen;

  /// DALI: Anzahl Leuchten eines Gateways
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Leuchte} other{{count} Leuchten}}'**
  String daliLuminaires(int count);

  /// DALI: Zeile, die die fehlerfreien Leuchten aufklappt
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Leuchte ohne Fehler} other{{count} Leuchten ohne Fehler}}'**
  String daliOtherLuminaires(int count);

  /// DALI: letzte Meldung des Gateways
  ///
  /// In de, this message translates to:
  /// **'zuletzt {when}'**
  String daliLastAt(String when);

  /// DALI: letzte Meldung einer Leuchte
  ///
  /// In de, this message translates to:
  /// **'Letzte Meldung {when}'**
  String daliLastReport(String when);

  /// DALI: Kennzeichen Anzahl fehlerhafter Leuchten
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Fehler} other{{count} Fehler}}'**
  String daliFaultCount(int count);

  /// DALI: Hinweis auf ein ungeprüftes Herstellerprofil
  ///
  /// In de, this message translates to:
  /// **'Profil {name}: aus der Herstellerdokumentation, noch nicht an echten Telegrammen geprüft'**
  String daliProfileDocumented(String name);

  /// DALI: Hinweis auf ein geprüftes Herstellerprofil
  ///
  /// In de, this message translates to:
  /// **'Profil {name}'**
  String daliProfileVerified(String name);

  /// DALI: Gateway erkannt, aber noch nichts empfangen
  ///
  /// In de, this message translates to:
  /// **'Noch keine Meldung empfangen.'**
  String get daliNoReportYet;

  /// DALI: Knopf liest die Diagnose-Adressen
  ///
  /// In de, this message translates to:
  /// **'Diagnose jetzt lesen'**
  String get daliReadNow;

  /// DALI: Hinweis zum Lesen der Diagnose
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Liest 1 Diagnose-Adresse.} other{Liest {count} Diagnose-Adressen, 5 pro Sekunde.}} Das sendet Leseanforderungen auf den Bus.'**
  String daliReadHint(int count);

  /// DALI: Lesen ist im Nur-lesen-Modus gesperrt
  ///
  /// In de, this message translates to:
  /// **'Im Nur-lesen-Modus des Servers nicht möglich.'**
  String get daliReadOnlyHint;

  /// DALI: Fortschritt beim Lesen
  ///
  /// In de, this message translates to:
  /// **'Liest {sent} von {total}'**
  String daliReading(int sent, int total);

  /// DALI: Ergebnis des Lesens
  ///
  /// In de, this message translates to:
  /// **'{answered} von {total} Adressen haben geantwortet'**
  String daliReadDone(int answered, int total);

  /// DALI: Überschrift Gruppen
  ///
  /// In de, this message translates to:
  /// **'Gruppen'**
  String get daliGroups;

  /// DALI: keine Gruppen bekannt
  ///
  /// In de, this message translates to:
  /// **'Das Projekt nennt keine DALI-Gruppen dieses Gateways.'**
  String get daliNoGroups;

  /// DALI: Leuchten einer Gruppe ohne Fehler
  ///
  /// In de, this message translates to:
  /// **'{ok} von {total} in Ordnung'**
  String daliGroupOk(int ok, int total);

  /// DALI: Gruppe ohne eingetragene Leuchten
  ///
  /// In de, this message translates to:
  /// **'keine Leuchten zugeordnet'**
  String get daliGroupNoMembers;

  /// DALI: Gruppe umbenennen
  ///
  /// In de, this message translates to:
  /// **'Namen ändern'**
  String get daliRenameGroup;

  /// DALI: Hinweis unter den Gruppen
  ///
  /// In de, this message translates to:
  /// **'Namen, Räume und Gruppen der Leuchten meldet das Gateway nicht auf KNX. Fehlende trägst du hier ein.'**
  String get daliNamesHint;

  /// DALI: Überschrift des Rasters
  ///
  /// In de, this message translates to:
  /// **'Kurzadressen 0 bis 63'**
  String get daliGridTitle;

  /// DALI: belegte Kurzadressen
  ///
  /// In de, this message translates to:
  /// **'{count} belegt'**
  String daliGridUsed(int count);

  /// DALI: Kurzadresse einer Zelle im Raster
  ///
  /// In de, this message translates to:
  /// **'Adresse {address}'**
  String daliCellAddress(int address);

  /// DALI: freie Kurzadresse (Screenreader)
  ///
  /// In de, this message translates to:
  /// **'Adresse {address}, frei'**
  String daliCellFree(int address);

  /// DALI: Kurzadresse, abgekürzt
  ///
  /// In de, this message translates to:
  /// **'Adr. {address}'**
  String daliAddressShort(int address);

  /// DALI: Konverter, deren Objekte keine Kurzadresse nennen
  ///
  /// In de, this message translates to:
  /// **'Notleuchten ohne Kurzadresse'**
  String get daliUnaddressed;

  /// DALI: Hinweis im leeren Detailbereich
  ///
  /// In de, this message translates to:
  /// **'Tippe eine Adresse an, um Namen, Raum, Gruppen und Verlauf der Leuchte zu sehen.'**
  String get daliSelectHint;

  /// DALI: Raum einer Leuchte
  ///
  /// In de, this message translates to:
  /// **'Raum {room}'**
  String daliRoomIs(String room);

  /// DALI: Verlauf der Meldungen einer Leuchte
  ///
  /// In de, this message translates to:
  /// **'Verlauf'**
  String get daliHistory;

  /// DALI: Betriebsstunden einer Leuchte
  ///
  /// In de, this message translates to:
  /// **'Betriebsstunden'**
  String get daliBurnHours;

  /// DALI: Stunden
  ///
  /// In de, this message translates to:
  /// **'{count} h'**
  String daliHours(int count);

  /// DALI: Leuchte bearbeiten (Name, Raum, Gruppen)
  ///
  /// In de, this message translates to:
  /// **'Namen ändern'**
  String get daliEdit;

  /// DALI: Wächter nur für diese Leuchte anlegen
  ///
  /// In de, this message translates to:
  /// **'Nur diese Leuchte melden'**
  String get daliWatchThis;

  /// DALI: Feld Name
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get daliFieldName;

  /// DALI: Feld Raum
  ///
  /// In de, this message translates to:
  /// **'Raum'**
  String get daliFieldRoom;

  /// DALI: Feld Gruppen einer Leuchte
  ///
  /// In de, this message translates to:
  /// **'DALI-Gruppen'**
  String get daliFieldGroups;

  /// DALI: Hinweis zum Feld Gruppen
  ///
  /// In de, this message translates to:
  /// **'Wie im Werkzeug des Gateways vergeben.'**
  String get daliFieldGroupsHint;

  /// DALI: Einstellungen der Ansicht
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get daliSettings;

  /// DALI: Schalter zyklisches Lesen
  ///
  /// In de, this message translates to:
  /// **'Diagnose regelmäßig lesen'**
  String get daliPoll;

  /// DALI: Erklärung zum zyklischen Lesen
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{Für Gateways, die Fehler nur auf Anfrage melden. Das Projekt nennt keine lesbare Diagnose-Adresse.} =1{Für Gateways, die Fehler nur auf Anfrage melden. Sendet 1 Leseanforderung je Runde, solange die App verbunden ist.} other{Für Gateways, die Fehler nur auf Anfrage melden. Sendet {count} Leseanforderungen je Runde, solange die App verbunden ist.}}'**
  String daliPollHint(int count);

  /// DALI: Abstand des zyklischen Lesens
  ///
  /// In de, this message translates to:
  /// **'Abstand'**
  String get daliPollEvery;

  /// DALI: Überschrift Prüfabstände des Prüfbuchs
  ///
  /// In de, this message translates to:
  /// **'Prüfabstände'**
  String get daliIntervals;

  /// DALI: Prüfabstand Funktionstest
  ///
  /// In de, this message translates to:
  /// **'Funktionstest alle'**
  String get daliIntervalFunction;

  /// DALI: Prüfabstand Dauertest
  ///
  /// In de, this message translates to:
  /// **'Dauertest alle'**
  String get daliIntervalDuration;

  /// DALI: Abstand in Tagen
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Tag} other{{count} Tage}}'**
  String daliDays(int count);

  /// DALI: Abstand oder Zeitraum in Monaten
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Monat} other{{count} Monate}}'**
  String daliMonths(int count);

  /// DALI: Abstand in Jahren
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Jahr} other{{count} Jahre}}'**
  String daliYears(int count);

  /// DALI: einmal am Tag lesen
  ///
  /// In de, this message translates to:
  /// **'täglich'**
  String get daliDaily;

  /// DALI: Abstand des Lesens in Stunden
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{stündlich} other{alle {count} Std.}}'**
  String daliHoursChoice(int count);

  /// DALI: Abstand des Lesens in Minuten
  ///
  /// In de, this message translates to:
  /// **'alle {count} Min.'**
  String daliMinutesChoice(int count);

  /// DALI: Wächter-Vorlage
  ///
  /// In de, this message translates to:
  /// **'DALI-Fehler melden'**
  String get daliWatchTemplate;

  /// DALI-Wächter: alle Leuchten des Gateways
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get daliWatchAll;

  /// DALI-Wächter: nur eine Gruppe
  ///
  /// In de, this message translates to:
  /// **'Gruppe'**
  String get daliWatchGroup;

  /// DALI-Wächter: nur eine Leuchte
  ///
  /// In de, this message translates to:
  /// **'Leuchte'**
  String get daliWatchGear;

  /// DALI-Wächter: Erklärung im Dialog
  ///
  /// In de, this message translates to:
  /// **'Der Wächter meldet jede Fehlermeldung des Gateways, mit Ton, wenn du willst. Den Wechsel in den Fehler und zurück meldet Busclear zusätzlich als Alarm-Mitteilung.'**
  String get daliWatchHint;

  /// DALI-Wächter: keine Regel möglich
  ///
  /// In de, this message translates to:
  /// **'Dafür gibt es keine passende Diagnose-Adresse: DPT 238.600 kennt keine Gruppen, und ohne Diagnose-Adresse meldet das Gateway nichts je Leuchte.'**
  String get daliWatchNone;

  /// No description provided for @daliWatchUntrusted.
  ///
  /// In de, this message translates to:
  /// **'Wächter gibt es erst für ein übernommenes Gateway. Ein beim Mithören gefundenes zählt noch nicht, weil sich jedes Gerät am Bus als Gateway ausgeben kann.'**
  String get daliWatchUntrusted;

  /// DALI-Wächter: Knopf
  ///
  /// In de, this message translates to:
  /// **'Wächter anlegen'**
  String get daliWatchCreate;

  /// DALI-Wächter: Beschreibung der Regel
  ///
  /// In de, this message translates to:
  /// **'DALI-Fehler · {scope}'**
  String daliWatchRuleTitle(String scope);

  /// DALI: Titel des Prüfbuchs
  ///
  /// In de, this message translates to:
  /// **'Notlicht-Prüfbuch'**
  String get daliLogTitle;

  /// DALI-Prüfbuch: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Sammelt, was selbsttestende Notleuchten über ihr Gateway melden: Funktions- und Dauertests je Leuchte. Auf Add-on und Box schreibt der Server mit, auch nachts; sonst die App, solange sie verbunden ist.'**
  String get daliLogExplain;

  /// DALI-Prüfbuch: Grenze des Prüfbuchs
  ///
  /// In de, this message translates to:
  /// **'Das Prüfbuch dokumentiert, was die Leuchten melden. Ob es eine vorgeschriebene Prüfung ersetzt, entscheiden Betreiber oder Prüfer.'**
  String get daliLogLimit;

  /// DALI-Prüfbuch: leer
  ///
  /// In de, this message translates to:
  /// **'Noch keine Testergebnisse.'**
  String get daliLogEmpty;

  /// DALI-Prüfbuch: leer, Erklärung
  ///
  /// In de, this message translates to:
  /// **'Ergebnisse erscheinen, sobald ein Gateway das Testergebnis einer Notleuchte sendet (DPT 245.600).'**
  String get daliLogEmptyDetail;

  /// DALI-Prüfbuch: Filter ohne Treffer
  ///
  /// In de, this message translates to:
  /// **'Keine Leuchte in dieser Auswahl.'**
  String get daliLogNothingHere;

  /// DALI-Prüfbuch: Leuchte ohne Ergebnis
  ///
  /// In de, this message translates to:
  /// **'noch kein Ergebnis'**
  String get daliLogNoResult;

  /// DALI-Prüfbuch: Überschrift aller Einträge
  ///
  /// In de, this message translates to:
  /// **'Einträge'**
  String get daliLogEntries;

  /// DALI-Prüfbuch: Hinweis am ersten Eintrag einer Leuchte
  ///
  /// In de, this message translates to:
  /// **'erstes gesehenes Ergebnis, der Test kann älter sein'**
  String get daliLogFirstSeen;

  /// DALI-Prüfbuch: Lücke in der Aufzeichnung
  ///
  /// In de, this message translates to:
  /// **'Zwischen {from} und {to} gibt es keine Aufzeichnung, Ergebnisse aus dieser Zeit fehlen.'**
  String daliLogGap(String from, String to);

  /// DALI-Prüfbuch: weitere Lücken
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{und 1 weitere Lücke} other{und {count} weitere Lücken}}'**
  String daliLogMoreGaps(int count);

  /// DALI-Prüfbuch: Hinweis ohne Tagesverlauf
  ///
  /// In de, this message translates to:
  /// **'Ohne Tagesverlauf zeichnet die App nur auf, solange sie verbunden ist. Tests, die in der Zwischenzeit liefen, können fehlen.'**
  String get daliLogNoHistory;

  /// DALI-Prüfbuch: Aktion Nachbau
  ///
  /// In de, this message translates to:
  /// **'Aus dem Tagesverlauf nachbauen'**
  String get daliLogRebuild;

  /// DALI-Prüfbuch: Ergebnis des Nachbaus
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{Keine neuen Einträge im Tagesverlauf gefunden} =1{1 Eintrag aus dem Tagesverlauf ergänzt} other{{count} Einträge aus dem Tagesverlauf ergänzt}}'**
  String daliLogRebuilt(int count);

  /// DALI-Prüfbuch: Filter alle
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get daliFilterAll;

  /// DALI-Prüfbuch: Filter offen (überfällig, durchgefallen, ohne Ergebnis)
  ///
  /// In de, this message translates to:
  /// **'Offen'**
  String get daliFilterOpen;

  /// DALI-Prüfbuch: Filter durchgefallen
  ///
  /// In de, this message translates to:
  /// **'Durchgefallen'**
  String get daliFilterFailed;

  /// DALI-Prüfbuch: Kennzeichen durchgefallen
  ///
  /// In de, this message translates to:
  /// **'durchgefallen'**
  String get daliTestFailedChip;

  /// DALI-Prüfbuch: Kennzeichen überfällig
  ///
  /// In de, this message translates to:
  /// **'überfällig'**
  String get daliOverdueChip;

  /// DALI-Prüfbuch: Knopf PDF exportieren
  ///
  /// In de, this message translates to:
  /// **'PDF'**
  String get daliExportPdf;

  /// DALI-Prüfbuch: Knopf CSV exportieren
  ///
  /// In de, this message translates to:
  /// **'CSV'**
  String get daliExportCsv;

  /// DALI-Prüfbuch: Zeitraum ohne Grenze
  ///
  /// In de, this message translates to:
  /// **'Alles'**
  String get daliPeriodAll;

  /// DALI-Prüfbuch: Zeitraum ohne Anfang
  ///
  /// In de, this message translates to:
  /// **'bis {date}'**
  String daliPeriodUntil(String date);

  /// DALI-Prüfbuch PDF: Feld Prüfer
  ///
  /// In de, this message translates to:
  /// **'Prüfer'**
  String get daliInspector;

  /// DALI-Prüfbuch PDF: Feld Unterschrift
  ///
  /// In de, this message translates to:
  /// **'Datum, Unterschrift'**
  String get daliSignature;

  /// DALI-Prüfbuch: Spalte Zeit
  ///
  /// In de, this message translates to:
  /// **'Zeit'**
  String get daliColTime;

  /// DALI-Prüfbuch: Spalte Leuchte
  ///
  /// In de, this message translates to:
  /// **'Leuchte'**
  String get daliColLuminaire;

  /// DALI-Prüfbuch: Spalte Gruppenadresse
  ///
  /// In de, this message translates to:
  /// **'Gruppenadresse'**
  String get daliColGroupAddress;

  /// DALI-Prüfbuch: Spalte Testart
  ///
  /// In de, this message translates to:
  /// **'Test'**
  String get daliColTest;

  /// DALI-Prüfbuch: Spalte Startart
  ///
  /// In de, this message translates to:
  /// **'Start'**
  String get daliColStart;

  /// DALI-Prüfbuch: Spalte Ergebnis
  ///
  /// In de, this message translates to:
  /// **'Ergebnis'**
  String get daliColResult;

  /// DALI-Prüfbuch: Spalte Gründe
  ///
  /// In de, this message translates to:
  /// **'Gründe'**
  String get daliColReasons;

  /// DALI-Prüfbuch: Spalte gemessene Dauer
  ///
  /// In de, this message translates to:
  /// **'Dauer (min)'**
  String get daliColMinutes;

  /// DALI-Prüfbuch: Spalte Akkuladung
  ///
  /// In de, this message translates to:
  /// **'Akkuladung'**
  String get daliColCharge;

  /// DALI-Inbetriebnahme: Titel
  ///
  /// In de, this message translates to:
  /// **'DALI-Gruppen prüfen'**
  String get daliCommTitle;

  /// DALI-Inbetriebnahme: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Schalte eine Gruppe nach der anderen und sieh nach, welche Leuchten reagieren. Kommt die Rückmeldung von der Status-Adresse einer anderen Gruppe, passt die Gruppenzuordnung im Gateway nicht zum Projekt. Die Ergebnisse stehen in der Inbetriebnahme-Checkliste und ihrem Protokoll.'**
  String get daliCommExplain;

  /// DALI-Inbetriebnahme: leer
  ///
  /// In de, this message translates to:
  /// **'Keine DALI-Gruppe zum Schalten.'**
  String get daliCommEmpty;

  /// DALI-Inbetriebnahme: leer, Erklärung
  ///
  /// In de, this message translates to:
  /// **'Das Projekt nennt für keine Gruppe ein Schaltobjekt des Gateways.'**
  String get daliCommEmptyDetail;

  /// DALI-Inbetriebnahme: Nur-lesen-Modus
  ///
  /// In de, this message translates to:
  /// **'Der Server läuft im Nur-lesen-Modus: Schalten ist hier nicht möglich.'**
  String get daliCommReadOnly;

  /// DALI-Inbetriebnahme: Knopf Gruppe schalten
  ///
  /// In de, this message translates to:
  /// **'Schalten'**
  String get daliCommSwitch;

  /// DALI-Inbetriebnahme: Gruppe noch nicht geschaltet, mit Schaltadresse
  ///
  /// In de, this message translates to:
  /// **'noch nicht geschaltet · {address}'**
  String daliCommNotSwitched(String address);

  /// DALI-Inbetriebnahme: Gruppe geschaltet, mit Wert
  ///
  /// In de, this message translates to:
  /// **'geschaltet · {value}'**
  String daliCommSwitched(String value);

  /// DALI-Inbetriebnahme: wartet auf Rückmeldung
  ///
  /// In de, this message translates to:
  /// **'wartet auf Rückmeldung …'**
  String get daliCommWaiting;

  /// DALI-Inbetriebnahme: Rückmeldung mit Wert
  ///
  /// In de, this message translates to:
  /// **'Rückmeldung {value}'**
  String daliCommFeedback(String value);

  /// DALI-Inbetriebnahme: keine Rückmeldung vom Gateway
  ///
  /// In de, this message translates to:
  /// **'keine Rückmeldung'**
  String get daliCommNoFeedback;

  /// DALI-Inbetriebnahme: Gruppe ohne Statusobjekt
  ///
  /// In de, this message translates to:
  /// **'kein Statusobjekt im Projekt'**
  String get daliCommNoStatusObject;

  /// DALI-Inbetriebnahme: falsche Gruppenzuordnung
  ///
  /// In de, this message translates to:
  /// **'Rückmeldung kam von Gruppe {from}, geschaltet wurde Gruppe {switched}.'**
  String daliCommForeign(int from, int switched);

  /// DALI-Inbetriebnahme: Bewertung in Ordnung
  ///
  /// In de, this message translates to:
  /// **'OK'**
  String get daliCommOk;

  /// DALI-Inbetriebnahme: Bewertung falsche Leuchte
  ///
  /// In de, this message translates to:
  /// **'Falsche Leuchte'**
  String get daliCommWrong;

  /// DALI-Inbetriebnahme: Bewertung keine Reaktion
  ///
  /// In de, this message translates to:
  /// **'Keine Reaktion'**
  String get daliCommNoReaction;

  /// DALI-Inbetriebnahme: Gruppe bewertet
  ///
  /// In de, this message translates to:
  /// **'als in Ordnung bewertet'**
  String get daliCommRatedOk;

  /// DALI-Inbetriebnahme: Gruppe als Problem bewertet
  ///
  /// In de, this message translates to:
  /// **'als Problem bewertet'**
  String get daliCommRatedIssue;

  /// Inbetriebnahme: Menüeintrag zur DALI-Gruppenprüfung
  ///
  /// In de, this message translates to:
  /// **'DALI-Gruppen'**
  String get daliCommOpen;

  /// Servicebericht: offener DALI-Fehler einer Leuchte
  ///
  /// In de, this message translates to:
  /// **'{fault}: {name}'**
  String daliServiceFault(String fault, String name);

  /// Servicebericht: Einzelheiten zu einem DALI-Fehler
  ///
  /// In de, this message translates to:
  /// **'{address} · Gateway {gateway} · seit {since}'**
  String daliServiceFaultDetail(String address, String gateway, String since);

  /// Servicebericht: durchgefallener Notlichttest
  ///
  /// In de, this message translates to:
  /// **'Notlichttest durchgefallen: {name}'**
  String daliServiceTestFailed(String name);

  /// Servicebericht: Einzelheiten zu einem durchgefallenen Test
  ///
  /// In de, this message translates to:
  /// **'{test} am {date}'**
  String daliServiceTestDetail(String test, String date);

  /// Servicebericht: überfälliger Notlichttest
  ///
  /// In de, this message translates to:
  /// **'Notlichttest überfällig: {name}'**
  String daliServiceOverdue(String name);

  /// Demo-Haus: Name des DALI-Gateways
  ///
  /// In de, this message translates to:
  /// **'DALI-Gateway'**
  String get daliDemoGateway;

  /// DALI: Zustand einer Notleuchte, deren letzter Test durchgefallen ist
  ///
  /// In de, this message translates to:
  /// **'Test durchgefallen'**
  String get daliStateTestFailed;

  /// DALI: Zustandskasten einer Notleuchte mit durchgefallenem Test
  ///
  /// In de, this message translates to:
  /// **'{test} durchgefallen · {ago}'**
  String daliTestFailedAgo(String test, String ago);

  /// DALI: Gruppe mit durchgefallenen Notlichttests
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Test durchgefallen} other{{count} Tests durchgefallen}}'**
  String daliTestsFailed(int count);

  /// DALI: erstes gesehenes Testergebnis, der Test kann älter sein
  ///
  /// In de, this message translates to:
  /// **'Alter unbekannt'**
  String get daliAgeUnknown;

  /// DALI-Prüfbuch: Kennzeichen eines erstmals gesehenen Ergebnisses
  ///
  /// In de, this message translates to:
  /// **'erstmals gesehen, Testzeitpunkt unbekannt'**
  String get daliFirstSeen;

  /// DALI: Legende freie Kurzadresse
  ///
  /// In de, this message translates to:
  /// **'frei'**
  String get daliFree;

  /// DALI: Zeitpunkt gestern
  ///
  /// In de, this message translates to:
  /// **'gestern, {time}'**
  String daliYesterdayAt(String time);

  /// DALI: Zeitpunkt in der letzten Woche
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{vor 1 Tag, {time}} other{vor {count} Tagen, {time}}}'**
  String daliDaysAgoAt(int count, String time);

  /// DALI: Objekttext aus dem Projekt bei einer Notleuchte
  ///
  /// In de, this message translates to:
  /// **'ETS-Objekt: {text}'**
  String daliObjectText(String text);

  /// DALI: Kennzeichen Gateway ohne Meldung
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{still seit 1 Tag} other{still seit {count} Tagen}}'**
  String daliSilentFor(int count);

  /// DALI: zyklisches Lesen ist eingeschaltet
  ///
  /// In de, this message translates to:
  /// **'Liest die Diagnose {interval}'**
  String daliPollActive(String interval);

  /// DALI: Hinweis unter dem Knopf Diagnose lesen
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Liest 1 Adresse und sendet dafür eine Leseanforderung auf den Bus.} other{Liest {count} Adressen und sendet dafür Leseanforderungen auf den Bus.}}'**
  String daliReadSends(int count);

  /// DALI: Gateway aufklappen (Screenreader)
  ///
  /// In de, this message translates to:
  /// **'aufklappen'**
  String get daliExpand;

  /// DALI: Gateway zuklappen (Screenreader)
  ///
  /// In de, this message translates to:
  /// **'zuklappen'**
  String get daliCollapse;

  /// DALI: beim Mithören gefundenes Gateway
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Beim Mithören gefunden, noch nicht übernommen (1 Leuchte). Seine Meldungen zählen erst nach dem Übernehmen: Jedes Gerät am Bus kann sich als Gateway ausgeben.} other{Beim Mithören gefunden, noch nicht übernommen ({count} Leuchten). Seine Meldungen zählen erst nach dem Übernehmen: Jedes Gerät am Bus kann sich als Gateway ausgeben.}}'**
  String daliSuggestion(int count);

  /// DALI: gefundenes Gateway übernehmen
  ///
  /// In de, this message translates to:
  /// **'Übernehmen'**
  String get daliConfirm;

  /// DALI: gefundenes Gateway verwerfen
  ///
  /// In de, this message translates to:
  /// **'Verwerfen'**
  String get daliDismiss;

  /// DALI-Mitteilung: Sammelmitteilung, wenn viele Leuchten zugleich melden
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{DALI: 1 weitere Leuchte meldet eine Änderung} other{DALI: {count} weitere Leuchten melden Fehler oder Änderungen}}'**
  String daliNotifySummary(int count);

  /// DALI-Details: Link auf das Issue für Gateway-Auszüge
  ///
  /// In de, this message translates to:
  /// **'Issue #6 öffnen'**
  String get daliIssueLink;

  /// DALI-Inbetriebnahme: Gruppe einschalten
  ///
  /// In de, this message translates to:
  /// **'Einschalten'**
  String get daliCommOn;

  /// DALI-Inbetriebnahme: Gruppe ausschalten
  ///
  /// In de, this message translates to:
  /// **'Ausschalten'**
  String get daliCommOff;

  /// DALI-Prüfbuch: überfällig mit Bezug
  ///
  /// In de, this message translates to:
  /// **'{days, plural, =0{{test} überfällig: noch kein Ergebnis} =1{{test} überfällig: kein neues Ergebnis seit 1 Tag} other{{test} überfällig: kein neues Ergebnis seit {days} Tagen}}'**
  String daliOverdueReason(String test, int days);

  /// DALI-Prüfbuch: Ergebnisse fremder Absender
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Ergebnis von einem anderen Absender als dem Gateway, zählt nicht} other{{count} Ergebnisse von einem anderen Absender als dem Gateway, zählen nicht}}'**
  String daliForeignCount(int count);

  /// DALI-Prüfbuch: Eintrag von einem anderen Absender als dem Gateway
  ///
  /// In de, this message translates to:
  /// **'fremder Absender {address}'**
  String daliForeignSender(String address);

  /// DALI-Prüfbuch: Ergebnis kam gesichert an
  ///
  /// In de, this message translates to:
  /// **'verschlüsselt empfangen (KNX Data Secure)'**
  String get daliDataSecure;

  /// DALI-Prüfbuch: Spalte Absender
  ///
  /// In de, this message translates to:
  /// **'Absender'**
  String get daliColSource;

  /// DALI-Prüfbuch: Spalte Hinweis
  ///
  /// In de, this message translates to:
  /// **'Hinweis'**
  String get daliColNote;

  /// DALI-Prüfbuch PDF: Prüfabstände
  ///
  /// In de, this message translates to:
  /// **'Funktionstest {function} · Dauertest {duration}'**
  String daliIntervalsText(String function, String duration);

  /// DALI-Prüfbuch: Hinweis zur Fälschbarkeit
  ///
  /// In de, this message translates to:
  /// **'Die Ergebnisse stammen aus Bustelegrammen. Ohne KNX Data Secure kann jedes Gerät am Bus sie fälschen; Ergebnisse von einem anderen Absender als dem Gateway sind gekennzeichnet und zählen nicht.'**
  String get daliLogTrust;

  /// DALI-Prüfbuch: gleiche Meldungen zählen nicht als neuer Test
  ///
  /// In de, this message translates to:
  /// **'Nach einem bestandenen Test meldet ein Gateway oft dieselben Bytes wie zuvor. Busclear zählt das nur als neuen Test, wenn der Konverterstatus (DPT 244.600) den Test als laufend oder anstehend gemeldet hat; sonst erscheint die Leuchte als überfällig, obwohl sie getestet hat. Je Leuchte und Testart zählt höchstens ein Ergebnis pro Stunde.'**
  String get daliLogRepeats;

  /// DALI-Prüfbuch: Jahr unvollständig
  ///
  /// In de, this message translates to:
  /// **'Prüfbuch {year} unvollständig: Die Datei hat ihre Grenze erreicht oder wurde nur zum Teil gelesen. Ungewöhnlich viele Ergebnisse deuten auf ein fehlerhaftes oder fremdes Gerät am Bus.'**
  String daliLogLimited(String year);

  /// DALI-Prüfbuch: Nachbau nicht nötig
  ///
  /// In de, this message translates to:
  /// **'Das Prüfbuch führt der Server (Add-on oder Box) ohne Lücken; ein Nachbau ist nicht nötig.'**
  String get daliLogServerKeeps;

  /// DALI-Prüfbuch PDF: Fußnote zur Zeitspalte
  ///
  /// In de, this message translates to:
  /// **'Zeit = Eingang der Meldung, nicht der Zeitpunkt des Tests. Ein erstmals gesehenes Ergebnis kann älter sein.'**
  String get daliTimeFootnote;

  /// Verbinden: Demo-Modus mit Musterhaus starten
  ///
  /// In de, this message translates to:
  /// **'Demo ohne Anlage ansehen'**
  String get connectDemo;

  /// Name des simulierten Gateways im Demo-Modus
  ///
  /// In de, this message translates to:
  /// **'Demo-Haus'**
  String get demoGateway;

  /// Busmonitor im Demo-Modus
  ///
  /// In de, this message translates to:
  /// **'Der Busmonitor braucht ein echtes Gateway – im Demo-Modus nicht verfügbar.'**
  String get demoNoBusmonitor;

  /// Menü-Gruppe: Gesundheit, Inbetriebnahme, Diagnose
  ///
  /// In de, this message translates to:
  /// **'Prüfen'**
  String get menuGroupCheck;

  /// Menü-Gruppe: Busmonitor, Topologie, Kommunikationskarte
  ///
  /// In de, this message translates to:
  /// **'Bus & Netz'**
  String get menuGroupBus;

  /// Menü-Gruppe: Statistik, Projekt-Abgleich
  ///
  /// In de, this message translates to:
  /// **'Auswerten'**
  String get menuGroupAnalyze;

  /// Menü-Gruppe: Aufnahmen, Trigger-Aufnahme
  ///
  /// In de, this message translates to:
  /// **'Aufzeichnen'**
  String get menuGroupRecord;

  /// Menü-Gruppe: Export, ETS-Projekt
  ///
  /// In de, this message translates to:
  /// **'Daten'**
  String get menuGroupData;

  /// Menü-Gruppe: Schalter
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get menuGroupSettings;

  /// Startbildschirm: Abschnitt Demo und Aufnahmen
  ///
  /// In de, this message translates to:
  /// **'Ohne Verbindung'**
  String get connectWithout;

  /// Startbildschirm: Demo-Modus (kurz)
  ///
  /// In de, this message translates to:
  /// **'Demo ansehen'**
  String get connectDemoShort;

  /// Startbildschirm: Abschnitt Projekt
  ///
  /// In de, this message translates to:
  /// **'ETS-Projekt'**
  String get connectProject;

  /// Connect status 0x25/0x2E.
  ///
  /// In de, this message translates to:
  /// **'Die gewünschte Tunneladresse ist belegt.'**
  String get errorTunnelAddressInUse;

  /// Connect status 0x28/0x2D.
  ///
  /// In de, this message translates to:
  /// **'Gateway lehnt die gewünschte Tunneladresse ab.'**
  String get errorTunnelAddressRejected;

  /// Connect status 0x29.
  ///
  /// In de, this message translates to:
  /// **'Gateway unterstützt diese Tunnelart nicht (Link Layer/Busmonitor).'**
  String get errorLayerUnsupported;

  /// Connection mode: UDP tunnel.
  ///
  /// In de, this message translates to:
  /// **'UDP'**
  String get connectModeUdp;

  /// Connection mode: TCP tunnel.
  ///
  /// In de, this message translates to:
  /// **'TCP'**
  String get connectModeTcp;

  /// Connection mode: KNXnet/IP routing.
  ///
  /// In de, this message translates to:
  /// **'Routing'**
  String get connectModeRouting;

  /// Connection mode: KNX IP Secure tunnel.
  ///
  /// In de, this message translates to:
  /// **'Secure'**
  String get connectModeSecure;

  /// Hint for UDP mode.
  ///
  /// In de, this message translates to:
  /// **'Tunnel über UDP – geht mit jedem IP-Interface.'**
  String get connectModeUdpHint;

  /// Hint for TCP mode.
  ///
  /// In de, this message translates to:
  /// **'Tunnel über TCP (KNXnet/IP 2.0) – übersteht WLAN-Aussetzer besser.'**
  String get connectModeTcpHint;

  /// Hint for routing mode.
  ///
  /// In de, this message translates to:
  /// **'Multicast 224.0.23.12 über einen IP-Router – belegt keinen Tunnelplatz. Filtertabellen des Routers beachten.'**
  String get connectModeRoutingHint;

  /// Hint for secure mode.
  ///
  /// In de, this message translates to:
  /// **'Verschlüsselter Tunnel (KNX IP Secure). Benutzer und Passwort stehen in der ETS beim Tunnel der Schnittstelle.'**
  String get connectModeSecureHint;

  /// Field: requested tunnel individual address.
  ///
  /// In de, this message translates to:
  /// **'Tunneladresse (optional)'**
  String get connectTunnelAddress;

  /// Helper text for tunnel address.
  ///
  /// In de, this message translates to:
  /// **'Feste Adresse statt beliebigem freien Platz; ist sie belegt, wird ein freier genommen.'**
  String get connectTunnelAddressHelp;

  /// Field: individual address used when sending via routing.
  ///
  /// In de, this message translates to:
  /// **'Eigene Adresse'**
  String get connectRoutingAddress;

  /// Validation error for individual address fields.
  ///
  /// In de, this message translates to:
  /// **'Physikalische Adresse wie 1.1.240'**
  String get connectAddressInvalid;

  /// Field: IP Secure user id.
  ///
  /// In de, this message translates to:
  /// **'Benutzer'**
  String get connectSecureUser;

  /// Field: IP Secure user password.
  ///
  /// In de, this message translates to:
  /// **'Passwort'**
  String get connectSecurePassword;

  /// Field: IP Secure device authentication code.
  ///
  /// In de, this message translates to:
  /// **'Geräte-Authentifizierungscode (optional)'**
  String get connectSecureDeviceAuth;

  /// Helper for device authentication code.
  ///
  /// In de, this message translates to:
  /// **'Prüft, dass wirklich die eigene Schnittstelle antwortet.'**
  String get connectSecureDeviceAuthHelp;

  /// Error when joining the multicast group fails.
  ///
  /// In de, this message translates to:
  /// **'Routing nicht möglich: {reason}'**
  String routingUnavailable(String reason);

  /// Title of the add-on bus card.
  ///
  /// In de, this message translates to:
  /// **'Daueraufzeichnung im Add-on'**
  String get addonTitle;

  /// Add-on recording paused.
  ///
  /// In de, this message translates to:
  /// **'Angehalten – der Tunnel ist frei, z. B. für die ETS.'**
  String get addonPaused;

  /// Add-on recording status line.
  ///
  /// In de, this message translates to:
  /// **'Verbunden mit {target} seit {time} · {count} Telegramme heute'**
  String addonConnectedSince(String target, String time, int count);

  /// Add-on not yet connected.
  ///
  /// In de, this message translates to:
  /// **'Add-on verbindet mit dem Bus …'**
  String get addonConnecting;

  /// WebSocket to add-on closed.
  ///
  /// In de, this message translates to:
  /// **'Verbindung zum Add-on getrennt.'**
  String get addonConnectionLost;

  /// Loading while attaching to the box server.
  ///
  /// In de, this message translates to:
  /// **'Verbinde mit der Box …'**
  String get boxAttaching;

  /// Box server is connecting to the bus.
  ///
  /// In de, this message translates to:
  /// **'Box verbindet mit dem Bus …'**
  String get boxConnecting;

  /// Connection to the box server lost.
  ///
  /// In de, this message translates to:
  /// **'Verbindung zur Box getrennt.'**
  String get boxConnectionLost;

  /// Device session locked by another browser tab.
  ///
  /// In de, this message translates to:
  /// **'Gerät wird gerade in einer anderen Ansicht geprüft.'**
  String get addonDeviceBusy;

  /// Button: pause add-on recording.
  ///
  /// In de, this message translates to:
  /// **'Anhalten'**
  String get addonPause;

  /// Button: resume add-on recording.
  ///
  /// In de, this message translates to:
  /// **'Fortsetzen'**
  String get addonResume;

  /// Button: open monitor on add-on tunnel.
  ///
  /// In de, this message translates to:
  /// **'Monitor öffnen'**
  String get addonOpen;

  /// Section label: Raspberry Pi box that records the bus.
  ///
  /// In de, this message translates to:
  /// **'Busclear Box'**
  String get boxSection;

  /// Button: pair with a Busclear Box.
  ///
  /// In de, this message translates to:
  /// **'Mit Busclear Box koppeln'**
  String get boxPair;

  /// Pairing dialog: how to pair.
  ///
  /// In de, this message translates to:
  /// **'QR-Code der Box mit der Kamera scannen, oder Kopplungslink bzw. IP-Adresse der Box hier einfügen. Den Link findest du auch als knx-box-link.txt auf der SD-Karte.'**
  String get boxPairHint;

  /// Pairing dialog: text field label.
  ///
  /// In de, this message translates to:
  /// **'Kopplungslink oder IP-Adresse der Box'**
  String get boxPairField;

  /// Pairing dialog: input is no pairing link.
  ///
  /// In de, this message translates to:
  /// **'Kein gültiger Kopplungslink.'**
  String get boxLinkInvalid;

  /// Dialog title when a pairing link was opened.
  ///
  /// In de, this message translates to:
  /// **'Mit Busclear Box verbinden?'**
  String get boxPairTitle;

  /// Dialog body when a pairing link was opened; the box address is shown above it.
  ///
  /// In de, this message translates to:
  /// **'Die App zeigt den Bus dann über diese Box. Nur bestätigen, wenn du den QR-Code selbst gescannt hast und die Adresse zu deiner Box passt.'**
  String get boxPairBody;

  /// Banner: app runs through a Busclear Box.
  ///
  /// In de, this message translates to:
  /// **'Über Busclear Box {name}'**
  String boxVia(String name);

  /// Banner: gateway field configures the box.
  ///
  /// In de, this message translates to:
  /// **'Das Gateway unten wird auf der Box eingestellt; die Box bleibt damit verbunden.'**
  String get boxGatewayHint;

  /// Button: stop using the box, connect to a gateway directly.
  ///
  /// In de, this message translates to:
  /// **'Gateway direkt'**
  String get boxLeave;

  /// Tooltip: remove the paired box.
  ///
  /// In de, this message translates to:
  /// **'Kopplung löschen'**
  String get boxForget;

  /// Error: no box paired.
  ///
  /// In de, this message translates to:
  /// **'Keine Busclear Box gekoppelt.'**
  String get boxNone;

  /// Error: box rejected the access key.
  ///
  /// In de, this message translates to:
  /// **'Die Box hat den Zugang abgelehnt. QR-Code der Box neu scannen.'**
  String get boxUnauthorized;

  /// Error when pairing: the box rejected the one-time pairing code from its pairing page (wrong, already used or expired).
  ///
  /// In de, this message translates to:
  /// **'Der Kopplungscode gilt nicht mehr: Er läuft nach 10 Minuten ab und gilt nur einmal. Auf der Seite der Box einen neuen QR-Code erzeugen und scannen.'**
  String get boxCodeInvalid;

  /// Error: box not reachable.
  ///
  /// In de, this message translates to:
  /// **'Busclear Box {address} nicht erreichbar. Ist das Gerät im WLAN der Box?'**
  String boxUnreachable(String address);

  /// Label: history size limit (add-on).
  ///
  /// In de, this message translates to:
  /// **'Höchstens'**
  String get historyMaxSize;

  /// Label: history write interval (add-on).
  ///
  /// In de, this message translates to:
  /// **'Schreiben'**
  String get historyWriteInterval;

  /// Write interval option: immediately.
  ///
  /// In de, this message translates to:
  /// **'sofort'**
  String get historyWriteNow;

  /// Hint for write interval.
  ///
  /// In de, this message translates to:
  /// **'Seltener schreiben schont die SD-Karte; bei Stromausfall fehlt dann der letzte Block.'**
  String get historyWriteHint;

  /// Confirm deleting one history day.
  ///
  /// In de, this message translates to:
  /// **'Verlauf vom {date} löschen?'**
  String historyDeleteDayConfirm(String date);

  /// History gap: add-on was not running.
  ///
  /// In de, this message translates to:
  /// **'Add-on lief {duration} nicht'**
  String outageOffline(String duration);

  /// History gap: bus link was down.
  ///
  /// In de, this message translates to:
  /// **'Bus {duration} getrennt'**
  String outageDisconnected(String duration);

  /// Secure session authentication failed.
  ///
  /// In de, this message translates to:
  /// **'IP Secure: Benutzer oder Passwort abgelehnt.'**
  String get secureAuthFailed;

  /// Secure session response MAC mismatch.
  ///
  /// In de, this message translates to:
  /// **'IP Secure: Geräte-Authentifizierungscode passt nicht – antwortet wirklich die eigene Schnittstelle?'**
  String get secureDeviceAuthFailed;

  /// Secure session closed by server.
  ///
  /// In de, this message translates to:
  /// **'Gateway hat die gesicherte Sitzung beendet.'**
  String get secureSessionClosed;

  /// Secure mode without credentials.
  ///
  /// In de, this message translates to:
  /// **'Für IP Secure Passwort eingeben oder Keyring importieren.'**
  String get secureNoCredentials;

  /// Title for keyring section.
  ///
  /// In de, this message translates to:
  /// **'KNX Secure (Keyring)'**
  String get keyringTitle;

  /// Button: import .knxkeys file.
  ///
  /// In de, this message translates to:
  /// **'Keyring importieren'**
  String get keyringImport;

  /// Dialog field: keyring password.
  ///
  /// In de, this message translates to:
  /// **'Keyring-Passwort'**
  String get keyringPassword;

  /// Hint for keyring password.
  ///
  /// In de, this message translates to:
  /// **'Das Passwort, das beim Export aus der ETS vergeben wurde.'**
  String get keyringPasswordHint;

  /// Keyring decryption failed.
  ///
  /// In de, this message translates to:
  /// **'Falsches Passwort.'**
  String get keyringWrongPassword;

  /// Keyring parse failed.
  ///
  /// In de, this message translates to:
  /// **'Keine gültige Keyring-Datei (.knxkeys).'**
  String get keyringInvalid;

  /// Keyring summary.
  ///
  /// In de, this message translates to:
  /// **'{project}: {keys} gesicherte Gruppenadressen, {tunnels} Secure-Tunnel'**
  String keyringLoaded(String project, int keys, int tunnels);

  /// No keyring loaded.
  ///
  /// In de, this message translates to:
  /// **'Kein Keyring – Data-Secure-Telegramme bleiben verschlüsselt.'**
  String get keyringNone;

  /// Kurzfassung von keyringNone für schmale Bildschirme (Telefon).
  ///
  /// In de, this message translates to:
  /// **'Nicht geladen'**
  String get keyringNoneShort;

  /// Button: remove keyring.
  ///
  /// In de, this message translates to:
  /// **'Keyring entfernen'**
  String get keyringRemove;

  /// Keyring import explanation.
  ///
  /// In de, this message translates to:
  /// **'Die Schlüssel bleiben auf diesem Gerät bzw. im Add-on. In der ETS: Projekt → Exportieren → Keyring.'**
  String get keyringExplain;

  /// Banner: secure telegrams received without keys.
  ///
  /// In de, this message translates to:
  /// **'{count} Data-Secure-Telegramme ohne Schlüssel – Keyring importieren, um sie zu lesen.'**
  String secureWithoutKeys(int count);

  /// Banner: secure telegrams rejected.
  ///
  /// In de, this message translates to:
  /// **'{count} Data-Secure-Telegramme verworfen (MAC oder Sequenznummer ungültig).'**
  String secureRejected(int count);

  /// Connection mode: use telegrams of the HA KNX integration.
  ///
  /// In de, this message translates to:
  /// **'Home Assistant'**
  String get connectModeHa;

  /// Hint for HA mode.
  ///
  /// In de, this message translates to:
  /// **'Kein eigener Tunnel: das Add-on liest, was die KNX-Integration von Home Assistant empfängt, und sendet über sie. Gerätezugriffe (Programmiermodus, Adresse prüfen, Busmonitor) gehen so nicht.'**
  String get connectModeHaHint;

  /// HA mode outside add-on.
  ///
  /// In de, this message translates to:
  /// **'Nur im Home-Assistant-Add-on möglich.'**
  String get connectModeHaAddonOnly;

  /// Connection mode: KNX HAT on the box.
  ///
  /// In de, this message translates to:
  /// **'KNX-HAT (kBerry)'**
  String get connectModeHat;

  /// Hint for HAT mode.
  ///
  /// In de, this message translates to:
  /// **'Ohne Gateway: Die Box hängt über den aufgesteckten KNX-HAT (Weinzierl kBerry) direkt an der Busleitung.'**
  String get connectModeHatHint;

  /// HAT mode without box.
  ///
  /// In de, this message translates to:
  /// **'Nur über die Busclear Box mit aufgestecktem KNX-HAT möglich.'**
  String get connectModeHatBoxOnly;

  /// Field: individual address of the HAT.
  ///
  /// In de, this message translates to:
  /// **'Eigene Adresse (optional)'**
  String get connectHatAddress;

  /// Help for the HAT address.
  ///
  /// In de, this message translates to:
  /// **'Leer lassen, um die Adresse des Moduls zu behalten (ab Werk 15.15.255). Eine eingetragene Adresse schreibt die Box ins Modul.'**
  String get connectHatAddressHelp;

  /// Switch: HAT in bus monitor mode.
  ///
  /// In de, this message translates to:
  /// **'Busmonitor'**
  String get connectHatBusmonitor;

  /// Help for the HAT bus monitor switch.
  ///
  /// In de, this message translates to:
  /// **'Alle Frames mit Quittungen (ACK/NAK/BUSY) für den Busmonitor. Die Box hört dann nur: kein Lesen oder Schreiben aus der App. Der kBerry gibt dabei etwa jeden zweiten Datenrahmen nicht aus; zum vollständigen Aufzeichnen Link Layer verwenden.'**
  String get connectHatBusmonitorHelp;

  /// Tooltip: re-enable filter.
  ///
  /// In de, this message translates to:
  /// **'Filter einschalten'**
  String get filterOn;

  /// Tooltip: disable filter without clearing.
  ///
  /// In de, this message translates to:
  /// **'Filter vorübergehend aus'**
  String get filterOff;

  /// Chip: show telegrams around matches.
  ///
  /// In de, this message translates to:
  /// **'Kontext'**
  String get filterContext;

  /// Chip label with context window.
  ///
  /// In de, this message translates to:
  /// **'Kontext ±{seconds} s'**
  String filterContextActive(int seconds);

  /// Context menu option.
  ///
  /// In de, this message translates to:
  /// **'±{seconds} s um jeden Treffer'**
  String filterContextSeconds(int seconds);

  /// Context menu option: off.
  ///
  /// In de, this message translates to:
  /// **'Nur Treffer'**
  String get filterContextOff;

  /// Tooltip for context chip.
  ///
  /// In de, this message translates to:
  /// **'Telegramme kurz vor und nach jedem Treffer mit anzeigen'**
  String get filterContextTooltip;

  /// Write format: time of day.
  ///
  /// In de, this message translates to:
  /// **'Uhrzeit'**
  String get writeFormatTime;

  /// Write format: date.
  ///
  /// In de, this message translates to:
  /// **'Datum'**
  String get writeFormatDate;

  /// Write format: HVAC mode.
  ///
  /// In de, this message translates to:
  /// **'HVAC-Modus'**
  String get writeFormatHvac;

  /// Write format: RGB colour.
  ///
  /// In de, this message translates to:
  /// **'Farbe (RGB)'**
  String get writeFormatColor;

  /// Fill current time/date.
  ///
  /// In de, this message translates to:
  /// **'Jetzt'**
  String get writeNow;

  /// Send option: delay.
  ///
  /// In de, this message translates to:
  /// **'Verzögerung'**
  String get sendDelay;

  /// Send option: cyclic repeat.
  ///
  /// In de, this message translates to:
  /// **'Wiederholen'**
  String get sendRepeat;

  /// Delay option: none.
  ///
  /// In de, this message translates to:
  /// **'sofort'**
  String get sendNow;

  /// Repeat option: send once.
  ///
  /// In de, this message translates to:
  /// **'einmal'**
  String get sendOnce;

  /// Cyclic interval in seconds.
  ///
  /// In de, this message translates to:
  /// **'alle {seconds} s'**
  String sendEverySeconds(int seconds);

  /// Cyclic interval in minutes.
  ///
  /// In de, this message translates to:
  /// **'alle {minutes} min'**
  String sendEveryMinutes(int minutes);

  /// Title of scheduled jobs list.
  ///
  /// In de, this message translates to:
  /// **'Geplante Sendungen'**
  String get sendScheduled;

  /// Stop all scheduled sends.
  ///
  /// In de, this message translates to:
  /// **'Alle stoppen'**
  String get sendStopAll;

  /// Stop one scheduled send.
  ///
  /// In de, this message translates to:
  /// **'Stoppen'**
  String get sendStop;

  /// Number of sends of a job.
  ///
  /// In de, this message translates to:
  /// **'{count}× gesendet'**
  String sendCount(int count);

  /// Next send time.
  ///
  /// In de, this message translates to:
  /// **'nächste {time}'**
  String sendNext(String time);

  /// Button: choose DPT for an address.
  ///
  /// In de, this message translates to:
  /// **'Datentyp festlegen'**
  String get dptChoose;

  /// Button when a DPT override exists.
  ///
  /// In de, this message translates to:
  /// **'Datentyp selbst festgelegt – ändern'**
  String get dptOverridden;

  /// DPT picker title.
  ///
  /// In de, this message translates to:
  /// **'Datentyp für {address}'**
  String dptChooseTitle(String address);

  /// Reset DPT to project value.
  ///
  /// In de, this message translates to:
  /// **'Wie im Projekt ({dpt})'**
  String dptFromProject(String dpt);

  /// Reset DPT, none in project.
  ///
  /// In de, this message translates to:
  /// **'Kein Datentyp (raten)'**
  String get dptNone;

  /// Label for device objects without channel (short).
  ///
  /// In de, this message translates to:
  /// **'Allgemein'**
  String get deviceGeneral;

  /// Channel state on.
  ///
  /// In de, this message translates to:
  /// **'Ein'**
  String get deviceOn;

  /// Channel state off.
  ///
  /// In de, this message translates to:
  /// **'Aus'**
  String get deviceOff;

  /// Screen reader label for a channel module.
  ///
  /// In de, this message translates to:
  /// **'Kanal {channel}: {state}'**
  String deviceChannelSemantics(String channel, String state);

  /// Heatmap card title.
  ///
  /// In de, this message translates to:
  /// **'Aktivität nach Wochentag und Stunde'**
  String get heatmapTitle;

  /// Heatmap empty (screen reader).
  ///
  /// In de, this message translates to:
  /// **'Noch keine Telegramme'**
  String get heatmapEmpty;

  /// Heatmap summary for screen readers.
  ///
  /// In de, this message translates to:
  /// **'Meiste Telegramme: {day} {hour} Uhr ({count})'**
  String heatmapPeak(String day, int hour, int count);

  /// Long-term stats card title.
  ///
  /// In de, this message translates to:
  /// **'Langzeit (Daueraufzeichnung)'**
  String get statsLongTerm;

  /// Long-term total.
  ///
  /// In de, this message translates to:
  /// **'{count} Telegramme im Zeitraum'**
  String statsLongTermTotal(String count);

  /// Long-term stats failed.
  ///
  /// In de, this message translates to:
  /// **'Auswertung nicht verfügbar (Add-on aktualisieren?).'**
  String get statsLongTermUnavailable;

  /// Multi-series chart screen title.
  ///
  /// In de, this message translates to:
  /// **'Diagramme'**
  String get chartsTitle;

  /// Tool menu subtitle for charts.
  ///
  /// In de, this message translates to:
  /// **'Mehrere Werte über der Zeit vergleichen'**
  String get toolCharts;

  /// Charts: pick addresses.
  ///
  /// In de, this message translates to:
  /// **'Adressen wählen'**
  String get chartsAdd;

  /// Charts overflow menu tooltip.
  ///
  /// In de, this message translates to:
  /// **'Mehr'**
  String get chartsMore;

  /// Charts empty state.
  ///
  /// In de, this message translates to:
  /// **'Gruppenadressen mit Zahlenwerten auswählen – bis zu 8, eine Achse je Einheit.'**
  String get chartsEmpty;

  /// Charts: save current selection.
  ///
  /// In de, this message translates to:
  /// **'Als Diagramm speichern'**
  String get chartsSaveSelection;

  /// Charts: name for a saved selection.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get chartsSelectionName;

  /// Charts: export PNG.
  ///
  /// In de, this message translates to:
  /// **'Als Bild (PNG)'**
  String get chartsExportPng;

  /// Charts: export CSV.
  ///
  /// In de, this message translates to:
  /// **'Als Tabelle (CSV)'**
  String get chartsExportCsv;

  /// Charts: clear selection.
  ///
  /// In de, this message translates to:
  /// **'Alle entfernen'**
  String get chartsClear;

  /// Semantics for resize handle.
  ///
  /// In de, this message translates to:
  /// **'Diagrammhöhe ziehen'**
  String get chartsResize;

  /// Menu: save diagnostics zip (no passwords, names or telegram contents).
  ///
  /// In de, this message translates to:
  /// **'Diagnose-Paket für Fehlerbericht'**
  String get diagnosticsBundle;

  /// Menu: open the about page with the third-party licenses.
  ///
  /// In de, this message translates to:
  /// **'Über Busclear und Lizenzen'**
  String get aboutLicenses;

  /// Copyright line on the about/licenses page.
  ///
  /// In de, this message translates to:
  /// **'© 2026 regetskcob. Alle Rechte vorbehalten.'**
  String get aboutLegalese;

  /// Sender line with the regetskcob mark at the end of the menu and on the about page. Keep the name regetskcob lower case.
  ///
  /// In de, this message translates to:
  /// **'ein Projekt von regetskcob'**
  String get aboutSender;

  /// Health severity word: no finding.
  ///
  /// In de, this message translates to:
  /// **'In Ordnung'**
  String get hzCSeverityOk;

  /// Health severity word: informational finding.
  ///
  /// In de, this message translates to:
  /// **'Hinweis'**
  String get hzCSeverityInfo;

  /// Health severity word: warning.
  ///
  /// In de, this message translates to:
  /// **'Warnung'**
  String get hzCSeverityWarning;

  /// Health severity word: error.
  ///
  /// In de, this message translates to:
  /// **'Fehler'**
  String get hzCSeverityError;

  /// Record button while recording: word before duration and count.
  ///
  /// In de, this message translates to:
  /// **'Aufnahme'**
  String get hzCRecordingLive;

  /// Tooltip of the toolbar button that shows the menu sidebar (from 600 pt).
  ///
  /// In de, this message translates to:
  /// **'Seitenleiste einblenden'**
  String get sidebarShow;

  /// Tooltip of the toolbar button that hides the menu sidebar.
  ///
  /// In de, this message translates to:
  /// **'Seitenleiste ausblenden'**
  String get sidebarHide;

  /// Kennung der Legende unter der Objektansicht
  ///
  /// In de, this message translates to:
  /// **'Legende'**
  String get hzFLegend;

  /// Legende Objektansicht: durchgezogene Linie
  ///
  /// In de, this message translates to:
  /// **'Wert empfangen'**
  String get hzFReceived;

  /// Legende Objektansicht: gestrichelte Linie bzw. kein Wert
  ///
  /// In de, this message translates to:
  /// **'Noch kein Telegramm'**
  String get hzFNoTelegram;

  /// Legende Objektansicht: wie die Adressen zum Objekt gefunden wurden
  ///
  /// In de, this message translates to:
  /// **'Erkannt am gemeinsamen Namensanfang'**
  String get hzFDetected;

  /// Koppler-Kachel in der Topologie: Semantik und Tooltip
  ///
  /// In de, this message translates to:
  /// **'Koppler {address}, Verkehr anzeigen'**
  String hzHCouplerOpen(String address);

  /// Kennung im Koppler-Blatt: die beiden Linien am Koppler
  ///
  /// In de, this message translates to:
  /// **'Linie {a} ↔ {b}'**
  String hzHLinePair(String a, String b);

  /// Richtung durch einen Koppler (Herkunfts- und Ziellinie)
  ///
  /// In de, this message translates to:
  /// **'Linie {from} → {to}'**
  String hzHFlow(String from, String to);

  /// Ruhiger Hinweis im Koppler-Blatt: wie Richtungen bestimmt werden
  ///
  /// In de, this message translates to:
  /// **'Von einer Linie heißt: die Quelladresse liegt dort. Nach einer Linie heißt: laut Projekt hören dort Geräte zu. Ob der Koppler wirklich weiterleitet, sieht das Gateway nur bei Telegrammen, die bei ihm ankommen.'**
  String get hzHFlowHint;

  /// Kennzahl im Koppler-Blatt: Telegramme aus der Linie, die das Gateway außerhalb erreicht haben
  ///
  /// In de, this message translates to:
  /// **'Am Gateway gesehen'**
  String get hzHSeenAtGateway;

  /// Kennzahl im Koppler-Blatt: davon auf Adressen ohne Empfänger außerhalb der Linie
  ///
  /// In de, this message translates to:
  /// **'davon ohne Empfänger'**
  String get hzHWithoutReceiver;

  /// Koppler-Blatt ohne Richtungen
  ///
  /// In de, this message translates to:
  /// **'Laut Projekt läuft keine Gruppenadresse über diesen Koppler.'**
  String get hzHFlowEmpty;

  /// Knopf im Koppler-Blatt: Auswahl einer Richtung aufheben
  ///
  /// In de, this message translates to:
  /// **'Alle Richtungen'**
  String get hzHAllDirections;

  /// Semantik-Hinweis einer Adresszeile im Koppler-Blatt
  ///
  /// In de, this message translates to:
  /// **'im Monitor filtern'**
  String get hzHFilterHint;

  /// Koppler-Blatt, wenn x.y.0 nicht im ETS-Projekt steht
  ///
  /// In de, this message translates to:
  /// **'Koppler nicht im Projekt'**
  String get hzHCouplerUnknown;

  /// Kennung im Koppler-Blatt: Koppleradresse und die Linien daran
  ///
  /// In de, this message translates to:
  /// **'Koppler {address} · {lines}'**
  String hzHCouplerKennung(String address, String lines);

  /// Column header for the hop count in the wide telegram table.
  ///
  /// In de, this message translates to:
  /// **'Hop'**
  String get columnHop;

  /// Title and tooltip of the app menu (tools, data, settings).
  ///
  /// In de, this message translates to:
  /// **'Menü'**
  String get menuTitle;

  /// Button that opens the quick filter menu next to the activity strip.
  ///
  /// In de, this message translates to:
  /// **'Filter'**
  String get quickFilterButton;

  /// Metric label: telegrams that crossed a coupler in one direction.
  ///
  /// In de, this message translates to:
  /// **'Telegramme {from} → {to}'**
  String hzHFlowTelegrams(String from, String to);

  /// Title of the activity heatmap; followed by its resolution.
  ///
  /// In de, this message translates to:
  /// **'Aktivität'**
  String get heatmapActivity;

  /// Heatmap resolution: one cell per minute.
  ///
  /// In de, this message translates to:
  /// **'je Minute'**
  String get heatmapPerMinute;

  /// Heatmap resolution: one cell per five minutes.
  ///
  /// In de, this message translates to:
  /// **'je 5 Minuten'**
  String get heatmapPerFiveMinutes;

  /// Heatmap resolution: one row per day, one cell per hour.
  ///
  /// In de, this message translates to:
  /// **'je Stunde'**
  String get heatmapPerHour;

  /// Heatmap resolution: weekday by hour over all weeks.
  ///
  /// In de, this message translates to:
  /// **'nach Wochentag und Stunde'**
  String get heatmapWeekly;

  /// Heatmap summary for screen readers.
  ///
  /// In de, this message translates to:
  /// **'Meiste Telegramme: {time} ({count})'**
  String heatmapPeakAt(String time, int count);

  /// Tooltip of the record button; long press starts with pre-roll.
  ///
  /// In de, this message translates to:
  /// **'Aufnahme starten – lang drücken: mit {seconds} s Vorlauf'**
  String recordingStartHint(int seconds);

  /// Screen reader hint for long press on the record button.
  ///
  /// In de, this message translates to:
  /// **'Mit {seconds} s Vorlauf aufnehmen'**
  String recordingPreRoll(int seconds);

  /// Snackbar after a long press started a recording with pre-roll.
  ///
  /// In de, this message translates to:
  /// **'Aufnahme läuft – enthält die letzten {seconds} s'**
  String recordingPreRollStarted(int seconds);

  /// Expert menu entry: replay recording onto the KNX bus.
  ///
  /// In de, this message translates to:
  /// **'Auf den Bus senden …'**
  String get replayMenu;

  /// Title of the replay sheet.
  ///
  /// In de, this message translates to:
  /// **'Auf den Bus senden'**
  String get replayTitle;

  /// Warning in the replay sheet.
  ///
  /// In de, this message translates to:
  /// **'Die Schreibtelegramme werden wirklich gesendet: Aktoren schalten, Jalousien fahren. Nur mit Blick auf die Anlage.'**
  String get replayWarning;

  /// Info when recording gateway differs.
  ///
  /// In de, this message translates to:
  /// **'Aufgenommen an {recorded}, gesendet wird an {current}.'**
  String replayOtherGateway(String recorded, String current);

  /// Replay sheet: nothing to send.
  ///
  /// In de, this message translates to:
  /// **'Die Aufnahme enthält keine Schreibtelegramme.'**
  String get replayNoWrites;

  /// Switch: cap gaps between telegrams.
  ///
  /// In de, this message translates to:
  /// **'Pausen auf {seconds} s kürzen'**
  String replayShorten(int seconds);

  /// Hint under the shorten switch.
  ///
  /// In de, this message translates to:
  /// **'Aus: im Originaltakt der Aufnahme'**
  String get replayShortenHint;

  /// Destructive button sending the replay.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Telegramm senden} other{{count} Telegramme senden}}'**
  String replaySend(int count);

  /// Confirmation dialog title.
  ///
  /// In de, this message translates to:
  /// **'Wirklich auf den Bus senden?'**
  String get replayConfirmTitle;

  /// Confirmation dialog text.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Schreibtelegramm} other{{count} Schreibtelegramme}} an {addresses, plural, =1{1 Gruppenadresse} other{{addresses} Gruppenadressen}} über {gateway}. Das lässt sich nicht rückgängig machen.'**
  String replayConfirmText(int count, int addresses, String gateway);

  /// Replay status running.
  ///
  /// In de, this message translates to:
  /// **'Sendet …'**
  String get replayRunning;

  /// Replay status done.
  ///
  /// In de, this message translates to:
  /// **'Fertig gesendet'**
  String get replayDone;

  /// Replay status stopped.
  ///
  /// In de, this message translates to:
  /// **'Angehalten'**
  String get replayStopped;

  /// Replay status error.
  ///
  /// In de, this message translates to:
  /// **'Abgebrochen: {message}'**
  String replayFailed(String message);

  /// Metric label.
  ///
  /// In de, this message translates to:
  /// **'Gesendet'**
  String get replaySent;

  /// Metric label.
  ///
  /// In de, this message translates to:
  /// **'Nicht quittiert'**
  String get replayUnconfirmed;

  /// Metric label.
  ///
  /// In de, this message translates to:
  /// **'Gesamt'**
  String get replayTotal;

  /// Stop replay button.
  ///
  /// In de, this message translates to:
  /// **'Stopp'**
  String get replayStop;

  /// Section label of telegrams to replay.
  ///
  /// In de, this message translates to:
  /// **'Telegramme'**
  String get replayTelegrams;

  /// Hint above the editable telegram list.
  ///
  /// In de, this message translates to:
  /// **'Tippen ändert den Wert, × entfernt das Telegramm. Das Original bleibt unverändert.'**
  String get replayEditHint;

  /// Discard edits in the replay sheet.
  ///
  /// In de, this message translates to:
  /// **'Zurücksetzen'**
  String get replayReset;

  /// Save the edited recording as a new one.
  ///
  /// In de, this message translates to:
  /// **'Als Kopie speichern'**
  String get replaySaveCopy;

  /// Name of an edited copy.
  ///
  /// In de, this message translates to:
  /// **'{name} · bearbeitet'**
  String replayCopyName(String name);

  /// Screen reader label for an edited value.
  ///
  /// In de, this message translates to:
  /// **'Geändert'**
  String get replayEdited;

  /// Tooltip removing a telegram.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get replayRemove;

  /// Error in the value dialog.
  ///
  /// In de, this message translates to:
  /// **'Ungültiger Wert'**
  String get replayInvalidValue;

  /// Hint when no DPT is known.
  ///
  /// In de, this message translates to:
  /// **'Bytes hex, z. B. 0C 1A'**
  String get replayHexHint;

  /// Snackbar when no numeric addresses exist.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Zahlenwerte für ein Diagramm.'**
  String get chartNoValues;

  /// Dialog title naming a chart.
  ///
  /// In de, this message translates to:
  /// **'Name des Diagramms'**
  String get chartName;

  /// Chart menu: rename.
  ///
  /// In de, this message translates to:
  /// **'Umbenennen'**
  String get chartRename;

  /// Chart menu: delete.
  ///
  /// In de, this message translates to:
  /// **'Diagramm löschen'**
  String get chartDelete;

  /// Delete chart dialog title.
  ///
  /// In de, this message translates to:
  /// **'Diagramm löschen?'**
  String get chartDeleteTitle;

  /// Delete chart dialog text.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ wird entfernt. Die Daten bleiben erhalten.'**
  String chartDeleteText(String name);

  /// Apply button of the address picker.
  ///
  /// In de, this message translates to:
  /// **'Übernehmen · {count}'**
  String pickerApply(int count);

  /// Address picker: filter matches nothing.
  ///
  /// In de, this message translates to:
  /// **'Nichts passt zum Filter.'**
  String get pickerEmpty;

  /// Title of the address picker for replay.
  ///
  /// In de, this message translates to:
  /// **'Adressen zum Senden'**
  String get replayPickTitle;

  /// Replay sheet: all addresses selected.
  ///
  /// In de, this message translates to:
  /// **'Alle {count} Adressen · auswählen'**
  String replayAddressesAll(int count);

  /// Replay sheet: some addresses selected.
  ///
  /// In de, this message translates to:
  /// **'{count} von {total} Adressen · ändern'**
  String replayAddressesSome(int count, int total);

  /// New chart (button and picker title).
  ///
  /// In de, this message translates to:
  /// **'Neues Diagramm'**
  String get chartNew;

  /// Default name of a new chart.
  ///
  /// In de, this message translates to:
  /// **'Diagramm'**
  String get chartDefaultName;

  /// Inbetriebnahme-Filter, kurz (fünf Segmente in einer Zeile am Telefon): keine Antwort auf Leseanfrage
  ///
  /// In de, this message translates to:
  /// **'Stumm'**
  String get commFilterNoAnswer;

  /// Section label above saved charts in the charts overview.
  ///
  /// In de, this message translates to:
  /// **'Gespeichert'**
  String get chartsSaved;

  /// Charts overview without saved charts.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Diagramme'**
  String get chartsOverviewEmpty;

  /// Explanation in the empty charts overview.
  ///
  /// In de, this message translates to:
  /// **'Mit „Neues Diagramm“ Adressen aus allen Sektionen wählen und unter einem Namen speichern. Es erscheint dann auch in der Übersicht.'**
  String get chartsOverviewEmptyDetail;

  /// Section label above chart templates (library) in the charts overview.
  ///
  /// In de, this message translates to:
  /// **'Vorlagen'**
  String get chartTemplates;

  /// Explanation above the chart templates.
  ///
  /// In de, this message translates to:
  /// **'Aus deinem Projekt erkannt. „Übernehmen“ macht daraus ein eigenes Diagramm, das du ändern kannst.'**
  String get chartTemplatesIntro;

  /// Explanation above traffic-based chart templates (no ETS project).
  ///
  /// In de, this message translates to:
  /// **'Aus dem laufenden Verkehr. Mit einem ETS-Projekt kommen Vorlagen je Raum dazu.'**
  String get chartTemplatesTrafficIntro;

  /// Button: turn a chart template into an own chart.
  ///
  /// In de, this message translates to:
  /// **'Übernehmen'**
  String get chartTemplateAdopt;

  /// Label on a template that is already among the own charts.
  ///
  /// In de, this message translates to:
  /// **'Übernommen'**
  String get chartTemplateAdopted;

  /// Button in a template group: adopt all templates of the group.
  ///
  /// In de, this message translates to:
  /// **'Alle übernehmen'**
  String get chartTemplatesAdoptAll;

  /// Snackbar after adopting one template.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ übernommen'**
  String chartTemplateAdoptedSnack(String name);

  /// Snackbar after adopting several templates.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Diagramm übernommen} other{{count} Diagramme übernommen}}'**
  String chartTemplatesAdoptedSnack(int count);

  /// Chart template: room temperature, setpoint, valve.
  ///
  /// In de, this message translates to:
  /// **'Raumklima'**
  String get chartRecipeClimate;

  /// Chart template: CO2 and humidity.
  ///
  /// In de, this message translates to:
  /// **'Luft'**
  String get chartRecipeAir;

  /// Chart template: presence, brightness, light status.
  ///
  /// In de, this message translates to:
  /// **'Licht & Präsenz'**
  String get chartRecipeLight;

  /// Chart template: blind positions with wind and rain.
  ///
  /// In de, this message translates to:
  /// **'Beschattung'**
  String get chartRecipeShading;

  /// Chart template: weather station.
  ///
  /// In de, this message translates to:
  /// **'Wetter'**
  String get chartRecipeWeather;

  /// Chart template: power and meters.
  ///
  /// In de, this message translates to:
  /// **'Energie'**
  String get chartRecipeEnergy;

  /// Chart template group built from bus traffic without an ETS project.
  ///
  /// In de, this message translates to:
  /// **'Aus dem Verkehr'**
  String get chartRecipeTraffic;

  /// Chart series: telegrams per minute on the bus.
  ///
  /// In de, this message translates to:
  /// **'Telegramme/min'**
  String get busMetricTelegrams;

  /// Chart series: repeated telegrams per minute.
  ///
  /// In de, this message translates to:
  /// **'Wiederholungen/min'**
  String get busMetricRepeats;

  /// Chart series: telegrams per minute sent from one line, e.g. Linie 1.1.
  ///
  /// In de, this message translates to:
  /// **'Linie {line}'**
  String busMetricLine(String line);

  /// Chart template group: bus load, repeats and load per line.
  ///
  /// In de, this message translates to:
  /// **'Bus'**
  String get chartRecipeBus;

  /// Chart template name: telegrams and repeats per minute.
  ///
  /// In de, this message translates to:
  /// **'Gesamt'**
  String get chartBusOverall;

  /// Chart template name: load per line.
  ///
  /// In de, this message translates to:
  /// **'Linien'**
  String get chartBusLines;

  /// Chart menu: export the chart as a reusable template file (roles instead of addresses).
  ///
  /// In de, this message translates to:
  /// **'Als Vorlage teilen'**
  String get chartShareTemplate;

  /// Snackbar when a chart cannot become a template.
  ///
  /// In de, this message translates to:
  /// **'Keine Reihe mit erkennbarer Rolle – die Vorlage wäre leer.'**
  String get chartShareTemplateEmpty;

  /// Snackbar after sharing a template with skipped series.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Reihe ohne erkennbare Rolle ist nicht in der Vorlage.} other{{count} Reihen ohne erkennbare Rolle sind nicht in der Vorlage.}}'**
  String chartShareTemplateDropped(int count);

  /// Charts overview action: import a shared chart template file.
  ///
  /// In de, this message translates to:
  /// **'Vorlage importieren'**
  String get chartTemplateImport;

  /// Snackbar after importing a template.
  ///
  /// In de, this message translates to:
  /// **'Vorlage „{name}“ importiert'**
  String chartTemplateImported(String name);

  /// Snackbar after importing a template that matches nothing.
  ///
  /// In de, this message translates to:
  /// **'Vorlage „{name}“ importiert – passt in dieser Anlage noch zu keiner Adresse.'**
  String chartTemplateImportedNoMatch(String name);

  /// Snackbar when the picked file is not a chart template.
  ///
  /// In de, this message translates to:
  /// **'Keine gültige Diagramm-Vorlage.'**
  String get chartTemplateImportFailed;

  /// Tooltip: remove an imported template from the library.
  ///
  /// In de, this message translates to:
  /// **'Vorlage entfernen'**
  String get chartTemplateRemove;

  /// Placeholder card for an imported template without matches.
  ///
  /// In de, this message translates to:
  /// **'Passt in dieser Anlage noch zu keiner Adresse.'**
  String get chartTemplateNoMatch;

  /// Button: set up a box by scanning its QR code
  ///
  /// In de, this message translates to:
  /// **'Busclear Box hinzufügen'**
  String get boxAdd;

  /// Scanner title
  ///
  /// In de, this message translates to:
  /// **'QR-Code der Box'**
  String get boxScanTitle;

  /// Scanner hint
  ///
  /// In de, this message translates to:
  /// **'Den QR-Code vom Aufkleber der Box in den Rahmen halten.'**
  String get boxScanHint;

  /// Scanner fallback button
  ///
  /// In de, this message translates to:
  /// **'Link einfügen oder Adresse eingeben'**
  String get boxScanManual;

  /// Scanner error
  ///
  /// In de, this message translates to:
  /// **'Keine Kamera verfügbar.'**
  String get boxScanNoCamera;

  /// Setup screen title
  ///
  /// In de, this message translates to:
  /// **'Busclear Box einrichten'**
  String get boxSetupTitle;

  /// Setup step
  ///
  /// In de, this message translates to:
  /// **'WLAN {ssid} beitreten'**
  String boxStepWifi(String ssid);

  /// Setup step: manual Wi-Fi
  ///
  /// In de, this message translates to:
  /// **'In den Einstellungen dem WLAN {ssid} beitreten und zurückkommen.'**
  String boxStepWifiManual(String ssid);

  /// Setup error
  ///
  /// In de, this message translates to:
  /// **'Beitritt zum WLAN abgelehnt.'**
  String get boxStepWifiDenied;

  /// Setup step
  ///
  /// In de, this message translates to:
  /// **'Box erreichen'**
  String get boxStepReach;

  /// Setup error
  ///
  /// In de, this message translates to:
  /// **'Die Box antwortet nicht. Ist sie eingeschaltet und das Gerät in ihrem WLAN?'**
  String get boxStepReachFailed;

  /// Setup step
  ///
  /// In de, this message translates to:
  /// **'Mit der Box koppeln'**
  String get boxStepPair;

  /// Setup step
  ///
  /// In de, this message translates to:
  /// **'Uhr der Box stellen'**
  String get boxStepTime;

  /// Setup step result
  ///
  /// In de, this message translates to:
  /// **'Uhr der Box weicht ab; in den Box-Einstellungen prüfen.'**
  String get boxStepTimeDiffers;

  /// Setup step
  ///
  /// In de, this message translates to:
  /// **'Gateway am Kabel der Box finden'**
  String get boxStepGateway;

  /// Setup step result
  ///
  /// In de, this message translates to:
  /// **'Gateway {host} eingestellt'**
  String boxStepGatewayFound(String host);

  /// Setup step result
  ///
  /// In de, this message translates to:
  /// **'Gateway im Verbinden-Bildschirm wählen'**
  String get boxStepGatewayChoose;

  /// Setup button
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get boxSetupRetry;

  /// Setup button
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get boxSetupDone;

  /// Box settings page title and button
  ///
  /// In de, this message translates to:
  /// **'Box-Einstellungen'**
  String get boxSettings;

  /// Box settings section
  ///
  /// In de, this message translates to:
  /// **'Uhr'**
  String get boxClock;

  /// Clock source
  ///
  /// In de, this message translates to:
  /// **'Keine gesicherte Zeit'**
  String get boxClockNone;

  /// Clock source
  ///
  /// In de, this message translates to:
  /// **'Akku-Uhr der Box (RTC)'**
  String get boxClockRtc;

  /// Clock source
  ///
  /// In de, this message translates to:
  /// **'KNX-Zeitgeber auf der Linie'**
  String get boxClockKnx;

  /// Clock source
  ///
  /// In de, this message translates to:
  /// **'Von einem iPhone oder iPad gestellt'**
  String get boxClockClient;

  /// Clock source
  ///
  /// In de, this message translates to:
  /// **'Internet (NTP)'**
  String get boxClockNtp;

  /// Clock offset report
  ///
  /// In de, this message translates to:
  /// **'{source} weicht um {offset} ab.'**
  String boxClockOffset(String source, String offset);

  /// Button
  ///
  /// In de, this message translates to:
  /// **'Mit diesem Gerät stellen'**
  String get boxClockSetNow;

  /// Box settings section: temperature and power supply
  ///
  /// In de, this message translates to:
  /// **'Raspberry Pi'**
  String get boxHealth;

  /// Current and highest SoC temperature
  ///
  /// In de, this message translates to:
  /// **'SoC {temp} °C, höchstens {max} °C seit dem Start'**
  String boxHealthTemp(String temp, String max);

  /// Power and throttling fine
  ///
  /// In de, this message translates to:
  /// **'Keine Unterspannung, keine Drosselung'**
  String get boxHealthOk;

  /// Under-voltage right now
  ///
  /// In de, this message translates to:
  /// **'Unterspannung: Das Netzteil liefert zu wenig. Ein Netzteil mit 5,1 V und 3 A verwenden, beim Pi 5 mit 5 A.'**
  String get boxHealthUnderVoltage;

  /// Thermal throttling right now
  ///
  /// In de, this message translates to:
  /// **'Der Pi drosselt gerade wegen Hitze. Das Gehäuse braucht mehr Luft oder einen Kühlkörper.'**
  String get boxHealthThrottled;

  /// Throttling seen since boot
  ///
  /// In de, this message translates to:
  /// **'Seit dem Einschalten: {list}'**
  String boxHealthBefore(String list);

  /// Throttling seen since the server started (hwmon fallback)
  ///
  /// In de, this message translates to:
  /// **'Seit dem Serverstart: {list}'**
  String boxHealthBeforeServer(String list);

  /// Throttle flag
  ///
  /// In de, this message translates to:
  /// **'Unterspannung'**
  String get boxHealthFlagUnderVoltage;

  /// Throttle flag
  ///
  /// In de, this message translates to:
  /// **'Takt begrenzt'**
  String get boxHealthFlagFreqCapped;

  /// Throttle flag
  ///
  /// In de, this message translates to:
  /// **'Gedrosselt'**
  String get boxHealthFlagThrottled;

  /// Throttle flag
  ///
  /// In de, this message translates to:
  /// **'Temperaturgrenze erreicht'**
  String get boxHealthFlagSoftTempLimit;

  /// Switch
  ///
  /// In de, this message translates to:
  /// **'Uhr nach KNX-Zeitgeber stellen'**
  String get boxClockFromKnx;

  /// Switch hint
  ///
  /// In de, this message translates to:
  /// **'Datum und Uhrzeit von der Linie (DPT 19.001 oder 10.001 + 11.001), wenn keine sicherere Quelle da ist.'**
  String get boxClockFromKnxHint;

  /// Switch
  ///
  /// In de, this message translates to:
  /// **'Erst aufzeichnen, wenn die Zeit stimmt'**
  String get boxRecordOnlyWithTime;

  /// Switch hint
  ///
  /// In de, this message translates to:
  /// **'Sonst zeichnet die Box sofort auf und ordnet die Zeit nachträglich zu.'**
  String get boxRecordOnlyWithTimeHint;

  /// Counter
  ///
  /// In de, this message translates to:
  /// **'{count} Telegramme ohne Zeit nicht aufgezeichnet'**
  String boxWaiting(int count);

  /// Dialog title
  ///
  /// In de, this message translates to:
  /// **'Uhr der Box weicht ab'**
  String get boxTimeAskTitle;

  /// Dialog body
  ///
  /// In de, this message translates to:
  /// **'Die Uhr der Box weicht um {offset} von diesem Gerät ab. Nach diesem Gerät stellen?'**
  String boxTimeAskBody(String offset);

  /// Box settings section
  ///
  /// In de, this message translates to:
  /// **'Gekoppelte Geräte'**
  String get boxDevices;

  /// Device list marker
  ///
  /// In de, this message translates to:
  /// **'dieses Gerät'**
  String get boxDeviceSelf;

  /// Gerät in der Liste: schickt nichts auf den Bus
  ///
  /// In de, this message translates to:
  /// **'nur ansehen'**
  String get boxDeviceViewOnly;

  /// Hinweis beim Senden auf einem Betrachter-Gerät
  ///
  /// In de, this message translates to:
  /// **'Dieses Gerät ist nur zum Ansehen mit der Box gekoppelt und schickt nichts auf den Bus. Zum Schalten neu koppeln, ohne „Nur ansehen“.'**
  String get boxViewOnlyHint;

  /// Device list marker
  ///
  /// In de, this message translates to:
  /// **'verwaltet die Box'**
  String get boxDeviceAdmin;

  /// Button
  ///
  /// In de, this message translates to:
  /// **'Sperren'**
  String get boxDeviceRevoke;

  /// No description provided for @boxClaimTitle.
  ///
  /// In de, this message translates to:
  /// **'Anlage mit dieser Box verbinden?'**
  String get boxClaimTitle;

  /// No description provided for @boxClaimBody.
  ///
  /// In de, this message translates to:
  /// **'„{box}“ führt eine Anlage mit der Kennung deiner Anlage „{name}“. Das kommt vor, wenn die Box beim Bauherrn steht und du die Anlage per Übergabe bekommen hast.\n\nVerbinde nur, wenn du diese Box kennst: Danach gehen Projekt, Schlüsselbund und Einstellungen dieser Anlage an die Box, und ihr Verlauf erscheint hier. Die Kennung allein beweist nichts, sie steht auch in Übergabepaketen.'**
  String boxClaimBody(String box, String name);

  /// No description provided for @boxClaimConnect.
  ///
  /// In de, this message translates to:
  /// **'Verbinden'**
  String get boxClaimConnect;

  /// No description provided for @boxClaimNotNow.
  ///
  /// In de, this message translates to:
  /// **'Nicht jetzt'**
  String get boxClaimNotNow;

  /// No description provided for @boxClaimThisBox.
  ///
  /// In de, this message translates to:
  /// **'Diese Box'**
  String get boxClaimThisBox;

  /// No description provided for @boxClaimSection.
  ///
  /// In de, this message translates to:
  /// **'Anlagen, die die Box kennt'**
  String get boxClaimSection;

  /// No description provided for @boxClaimSectionHint.
  ///
  /// In de, this message translates to:
  /// **'Die Box führt diese Anlagen, sie sind hier aber noch nicht mit ihr verbunden. Bis dahin geht nichts von ihnen an die Box.'**
  String get boxClaimSectionHint;

  /// No description provided for @boxDeviceThisApp.
  ///
  /// In de, this message translates to:
  /// **'diese App, früherer Zugang'**
  String get boxDeviceThisApp;

  /// No description provided for @boxDeviceApp.
  ///
  /// In de, this message translates to:
  /// **'App {key}'**
  String boxDeviceApp(String key);

  /// Box settings section
  ///
  /// In de, this message translates to:
  /// **'Box-Passwort ändern'**
  String get boxPasswordChange;

  /// Feld: bisheriges Box-Passwort
  ///
  /// In de, this message translates to:
  /// **'Aktuelles Passwort'**
  String get boxPasswordCurrent;

  /// Fehler: aktuelles Box-Passwort falsch oder leer
  ///
  /// In de, this message translates to:
  /// **'Das aktuelle Passwort stimmt nicht.'**
  String get boxPasswordCurrentWrong;

  /// Field hint
  ///
  /// In de, this message translates to:
  /// **'Mindestens 8 Zeichen. Der QR-Code des Aufklebers koppelt danach keine neuen Geräte mehr.'**
  String get boxPasswordHint;

  /// Confirmation
  ///
  /// In de, this message translates to:
  /// **'Passwort geändert.'**
  String get boxPasswordChanged;

  /// Hint
  ///
  /// In de, this message translates to:
  /// **'Verwalten geht nur mit dem Box-Passwort: QR-Code des Aufklebers scannen.'**
  String get boxNotAdmin;

  /// Abschnitt im Verbinden-Bildschirm (Expertenmodus): Anlagen mit eigenem Gateway, Projekt und Aufnahmen
  ///
  /// In de, this message translates to:
  /// **'Installationen'**
  String get installationsTitle;

  /// Knopf: Installation anlegen
  ///
  /// In de, this message translates to:
  /// **'Neue Installation'**
  String get installationNew;

  /// Eingabefeld beim Anlegen/Umbenennen
  ///
  /// In de, this message translates to:
  /// **'Name der Installation'**
  String get installationName;

  /// Hinweis im Namensfeld
  ///
  /// In de, this message translates to:
  /// **'z. B. Kunde Müller, Büro, Zuhause'**
  String get installationNameHint;

  /// Menüeintrag einer Installation
  ///
  /// In de, this message translates to:
  /// **'Umbenennen'**
  String get installationRename;

  /// Rückfrage beim Löschen
  ///
  /// In de, this message translates to:
  /// **'„{name}“ löschen?'**
  String installationDeleteTitle(String name);

  /// Rückfrage beim Löschen, Erklärung
  ///
  /// In de, this message translates to:
  /// **'ETS-Projekt, Keyring, Gesundheit, Inbetriebnahme, Abnahmeprotokolle, Serviceberichte, Kundendaten, Langzeitverlauf und Einstellungen dieser Installation werden entfernt. Aufnahmen bleiben erhalten.'**
  String get installationDeleteBody;

  /// Untertitel einer Installation ohne bekanntes Gateway
  ///
  /// In de, this message translates to:
  /// **'Noch kein Gateway'**
  String get installationNoGateway;

  /// Kennzeichen der gerade aktiven Installation
  ///
  /// In de, this message translates to:
  /// **'Aktiv'**
  String get installationActive;

  /// Hinweis nach automatischem Wechsel der Installation
  ///
  /// In de, this message translates to:
  /// **'Installation „{name}“'**
  String installationSwitched(String name);

  /// Hinweis im Monitor: Seriennummer passt zu einer anderen Installation
  ///
  /// In de, this message translates to:
  /// **'Dieses Gateway gehört zu „{name}“.'**
  String installationGatewayElsewhere(String name);

  /// Aktion: zur passenden Installation wechseln
  ///
  /// In de, this message translates to:
  /// **'Wechseln'**
  String get installationSwitch;

  /// Aufnahmen ohne bekannte Installation
  ///
  /// In de, this message translates to:
  /// **'Ohne Zuordnung'**
  String get installationUnassigned;

  /// Filter: Aufnahmen aller Installationen
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get installationAll;

  /// Untertitel der Installation, in der die gekoppelte Box gerade aufzeichnet
  ///
  /// In de, this message translates to:
  /// **'Busclear Box zeichnet hier auf'**
  String get installationBoxRecording;

  /// Auswahl im Langzeitverlauf: welche Installation
  ///
  /// In de, this message translates to:
  /// **'Verlauf von'**
  String get installationHistoryOf;

  /// Zusatz in der Lösch-Rückfrage, wenn die Box die Installation führt
  ///
  /// In de, this message translates to:
  /// **'Auch auf der Busclear Box, mit ihrem Langzeitverlauf.'**
  String get installationDeleteOnBox;

  /// Titel der Aufzeichnungs-Karte im Verbinden-Bildschirm über die Busclear Box (im Add-on: addonTitle)
  ///
  /// In de, this message translates to:
  /// **'Daueraufzeichnung auf der Busclear Box'**
  String get boxRecordingTitle;

  /// Titel der Bezahlseite und Menüeintrag
  ///
  /// In de, this message translates to:
  /// **'Plus und Pro'**
  String get planTitle;

  /// Grund oben auf der Bezahlseite, wenn ein gesperrtes Werkzeug geöffnet wurde
  ///
  /// In de, this message translates to:
  /// **'„{feature}“ gehört zu {tier}.'**
  String planFeatureLocked(String feature, String tier);

  /// Aktuelle Stufe oben auf der Bezahlseite
  ///
  /// In de, this message translates to:
  /// **'Aktuell: {tier}'**
  String planCurrent(String tier);

  /// Kennzeichen an der Stufe, die man schon hat
  ///
  /// In de, this message translates to:
  /// **'Aktiv'**
  String get planActive;

  /// Kurzbeschreibung der Stufe Plus
  ///
  /// In de, this message translates to:
  /// **'Für die eigene Anlage: Wächter mit Ton, Verlauf, Diagramme, Statistik, Alarme und Export.'**
  String get planPlusPitch;

  /// Kurzbeschreibung der Stufe Pro
  ///
  /// In de, this message translates to:
  /// **'Für Inbetriebnahme und Fehlersuche: alle Werkzeuge für Fachleute, ohne Grenzen.'**
  String get planProPitch;

  /// Punkt in der Liste von Plus
  ///
  /// In de, this message translates to:
  /// **'Beliebig viele Aufnahmen'**
  String get planUnlimitedRecordings;

  /// Punkt in der Liste von Plus
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Installation} other{bis zu {count} Installationen}}'**
  String planInstallations(int count);

  /// Punkt in der Liste von Pro
  ///
  /// In de, this message translates to:
  /// **'Beliebig viele Installationen'**
  String get planUnlimitedInstallations;

  /// Knopf: Jahresabo
  ///
  /// In de, this message translates to:
  /// **'{price} pro Jahr'**
  String planPerYear(String price);

  /// Knopf: Monatsabo
  ///
  /// In de, this message translates to:
  /// **'{price} pro Monat'**
  String planPerMonth(String price);

  /// Knopf: Einmalkauf
  ///
  /// In de, this message translates to:
  /// **'{price} einmalig'**
  String planOnce(String price);

  /// Knopf am Ende der Bezahlseite
  ///
  /// In de, this message translates to:
  /// **'Käufe wiederherstellen'**
  String get planRestore;

  /// Meldung nach dem Wiederherstellen
  ///
  /// In de, this message translates to:
  /// **'Käufe wiederhergestellt: {tier}.'**
  String planRestored(String tier);

  /// Meldung, wenn nichts wiederhergestellt wurde
  ///
  /// In de, this message translates to:
  /// **'Keine früheren Käufe gefunden.'**
  String get planNothingRestored;

  /// Fehler beim Laden der Preise
  ///
  /// In de, this message translates to:
  /// **'Die Angebote sind gerade nicht erreichbar. Bitte die Internetverbindung prüfen.'**
  String get planNoOffers;

  /// Fehler beim Kauf
  ///
  /// In de, this message translates to:
  /// **'Der Kauf hat nicht geklappt: {error}'**
  String planBuyFailed(String error);

  /// Meldung nach erfolgreichem Kauf
  ///
  /// In de, this message translates to:
  /// **'Danke! {tier} ist freigeschaltet.'**
  String planThanks(String tier);

  /// Pflichthinweis unter den Kaufknöpfen
  ///
  /// In de, this message translates to:
  /// **'Abos verlängern sich automatisch und lassen sich jederzeit in den Einstellungen des Stores kündigen.'**
  String get planLegal;

  /// Link unter den Kaufknöpfen
  ///
  /// In de, this message translates to:
  /// **'Nutzungsbedingungen'**
  String get planTerms;

  /// Link unter den Kaufknöpfen
  ///
  /// In de, this message translates to:
  /// **'Datenschutz'**
  String get planPrivacy;

  /// Grund auf der Bezahlseite, wenn das Limit an Installationen erreicht ist
  ///
  /// In de, this message translates to:
  /// **'Mit {tier} gibt es hier nur {count, plural, =1{eine Installation} other{{count} Installationen}}.'**
  String planMoreInstallations(String tier, int count);

  /// Grund auf der Bezahlseite, wenn schon eine Aufnahme gespeichert ist
  ///
  /// In de, this message translates to:
  /// **'Free speichert eine Aufnahme. Mit Plus sind es beliebig viele.'**
  String get planMoreRecordings;

  /// Grund auf der Bezahlseite bei längerem Verlauf
  ///
  /// In de, this message translates to:
  /// **'Den Langzeitverlauf gibt es ab Plus. Free zeigt im Monitor die letzte Stunde.'**
  String get planLongHistory;

  /// Letzter Punkt der Pro-Karte, wenn Plus darunter steht
  ///
  /// In de, this message translates to:
  /// **'Dazu alles aus Plus'**
  String get planAllOfPlus;

  /// Menüeintrag in TestFlight-Builds
  ///
  /// In de, this message translates to:
  /// **'Beta: Pro freigeschaltet'**
  String get planBetaTitle;

  /// Erklärung der Beta-Freischaltung; der Titel hat einen versteckten langen Druck
  ///
  /// In de, this message translates to:
  /// **'Danke fürs Testen! In der Beta ist alles freigeschaltet. Erscheint Busclear im App Store, gibt es auf diesem Gerät {months} Monate Pro als Dankeschön.'**
  String planBetaBody(int months);

  /// Meldung nach dem versteckten Schalter: Käufe testen
  ///
  /// In de, this message translates to:
  /// **'Bezahlseite wie im Store (Sandbox)'**
  String get planBetaStoreOn;

  /// Meldung nach dem versteckten Schalter: zurück zur Beta
  ///
  /// In de, this message translates to:
  /// **'Beta-Freischaltung wieder aktiv'**
  String get planBetaStoreOff;

  /// Bezahlseite: Freischaltung übers Konto ist ohne Abgleich abgelaufen.
  ///
  /// In de, this message translates to:
  /// **'{tier} gilt ohne Internet 30 Tage. Diese Frist ist abgelaufen – verbinde das Gerät einmal mit dem Internet, dann ist {tier} sofort wieder da.'**
  String planLapsed(String tier);

  /// Hinweis auf der Bezahlseite, solange das Dankeschön läuft
  ///
  /// In de, this message translates to:
  /// **'Beta-Dankeschön: Pro bis {date}'**
  String planBetaReward(String date);

  /// Link auf der Bezahlseite zur Abo-Verwaltung des Stores
  ///
  /// In de, this message translates to:
  /// **'Abo verwalten oder kündigen'**
  String get planManage;

  /// Kaufknopf mit Probezeit; price ist z. B. „99,00 € pro Jahr“
  ///
  /// In de, this message translates to:
  /// **'{days} Tage gratis, dann {price}'**
  String planTrial(int days, String price);

  /// Name der Pro-Funktion Wiedergabe auf den Bus
  ///
  /// In de, this message translates to:
  /// **'Aufnahmen auf den Bus spielen'**
  String get planFeatureReplay;

  /// Name der Pro-Funktion geplantes Senden
  ///
  /// In de, this message translates to:
  /// **'Verzögert und zyklisch senden'**
  String get planFeatureScheduled;

  /// Aufklappen der reinen Hinweise in einem Gesundheitsbereich
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Hinweis einblenden} other{{count} Hinweise einblenden}}'**
  String healthShowNotes(int count);

  /// Zuklappen der reinen Hinweise
  ///
  /// In de, this message translates to:
  /// **'Hinweise ausblenden'**
  String get healthHideNotes;

  /// Knopf in den Objektdetails: alle Rückmeldeadressen am Bus lesen
  ///
  /// In de, this message translates to:
  /// **'Rückmeldungen lesen'**
  String get objectReadFeedbacks;

  /// Meldung nach „Rückmeldungen lesen“
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Leseanfrage gesendet} other{{count} Leseanfragen gesendet}}'**
  String objectReadSent(int count);

  /// Unter „Noch nichts auf der Leitung“, solange der Busmonitor wartet
  ///
  /// In de, this message translates to:
  /// **'Lauscht auf der Leitung …'**
  String get busmonListening;

  /// Hinweis, wenn der Busmonitor 15 s nichts empfängt
  ///
  /// In de, this message translates to:
  /// **'Seit 15 Sekunden kein Frame. Ist die Linie gerade still, löst ein Taster oder „Lesen“ Verkehr aus. Manche IP-Schnittstellen liefern im Busmonitor-Modus nichts; dann hilft der Live-Monitor.'**
  String get busmonQuietHint;

  /// Busmonitor: ACKs ohne vorausgehenden Datenrahmen (Gateway)
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Quittung} other{{count} Quittungen}} ohne Datenrahmen davor: Die Schnittstelle hat im Busmonitor nicht jeden Datenrahmen ausgegeben. Für die Aufzeichnung zählt der Live-Monitor.'**
  String busmonOrphanAcks(int count);

  /// Busmonitor über den KNX-HAT der Box: ACKs ohne vorausgehenden Datenrahmen
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Quittung} other{{count} Quittungen}} ohne Datenrahmen davor: Der KNX-HAT (kBerry) gibt im Busmonitor etwa jeden zweiten Datenrahmen nicht aus. Vollständig zeichnet die Box im Link Layer auf, der Busmonitor zeigt Quittungen und Busfehler.'**
  String busmonOrphanAcksHat(int count);

  /// Zeile im Menü ohne Expertenmodus; Tippen schaltet ihn ein
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 weiteres Werkzeug im Expertenmodus} other{{count} weitere Werkzeuge im Expertenmodus}}'**
  String menuMoreTools(int count);

  /// Untertitel zur Zeile menuMoreTools
  ///
  /// In de, this message translates to:
  /// **'Busmonitor, Diagnose, Inbetriebnahme, Topologie und mehr'**
  String get menuMoreToolsHint;

  /// Untertitel des Menüeintrags „Objekte“ im Splitview
  ///
  /// In de, this message translates to:
  /// **'Räume und Objekte aus dem ETS-Projekt, Befehle neben Rückmeldungen'**
  String get toolObjects;

  /// Topologie: Geräte einer Linie als Frontgrafiken auf der Hutschiene
  ///
  /// In de, this message translates to:
  /// **'Verteiler · Linie {line}'**
  String topoRail(String line);

  /// Topologie: Telegramme je Richtung über die Koppler
  ///
  /// In de, this message translates to:
  /// **'Verkehr zwischen den Linien'**
  String get topoFlows;

  /// Topologie: Erklärung zu Verkehr zwischen den Linien
  ///
  /// In de, this message translates to:
  /// **'Telegramme je Richtung: Absender in der einen Linie, Empfänger laut Projekt in der anderen.'**
  String get topoFlowsHint;

  /// Topologie: Kennzahlen einer Richtung über den Koppler
  ///
  /// In de, this message translates to:
  /// **'{telegrams} Telegramme · {groups} Adressen'**
  String topoFlowRow(String telegrams, int groups);

  /// Topologie: keine linienübergreifenden Telegramme
  ///
  /// In de, this message translates to:
  /// **'Noch kein Verkehr über die Koppler.'**
  String get topoFlowsNone;

  /// Topologie: letzte Telegramme, die eine Linie verlassen
  ///
  /// In de, this message translates to:
  /// **'Über die Koppler, live'**
  String get topoLive;

  /// Topologie: leere Live-Liste linienübergreifender Telegramme
  ///
  /// In de, this message translates to:
  /// **'Noch keine Telegramme über die Koppler.'**
  String get topoLiveNone;

  /// Topologie: zugeklappte Geräte ohne Frontgrafik im Verteiler
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 weiteres Gerät} other{{count} weitere Geräte}}'**
  String topoRailMore(int count);

  /// Topologie: Geräte ohne Frontgrafik wieder zuklappen
  ///
  /// In de, this message translates to:
  /// **'Weniger zeigen'**
  String get topoRailLess;

  /// Topologie, Adressansicht: aktueller Wert
  ///
  /// In de, this message translates to:
  /// **'Wert'**
  String get topoGroupValue;

  /// Topologie, Adressansicht: Zahl der betroffenen Linien
  ///
  /// In de, this message translates to:
  /// **'Linien'**
  String get topoGroupLines;

  /// Topologie, Adressansicht: Detailblatt mit Werteverlauf und Schreiben öffnen
  ///
  /// In de, this message translates to:
  /// **'Verlauf & Schreiben'**
  String get topoGroupDetails;

  /// Topologie, Adressansicht: Absender ohne Verknüpfung (Visualisierung, Tunnel)
  ///
  /// In de, this message translates to:
  /// **'Gehört, nicht im Projekt verknüpft'**
  String get topoGroupUnlinked;

  /// Topologie, Adressansicht: letzte Telegramme der Adresse
  ///
  /// In de, this message translates to:
  /// **'Letzte Telegramme'**
  String get topoGroupRecent;

  /// Topologie, Adressansicht: Kanal des Objekts, z. B. „Kanal A“
  ///
  /// In de, this message translates to:
  /// **'Kanal'**
  String get topoGroupChannel;

  /// Topologie, Adressansicht: so oft als Absender gehört, z. B. „3× gehört“
  ///
  /// In de, this message translates to:
  /// **'gehört'**
  String get topoGroupHeard;

  /// Topologie, Adressansicht: Gerät sendet auf die Adresse
  ///
  /// In de, this message translates to:
  /// **'sendet'**
  String get topoGroupSends;

  /// Topologie, Adressansicht: Gerät hört auf die Adresse
  ///
  /// In de, this message translates to:
  /// **'hört'**
  String get topoGroupListens;

  /// Topologie, Adressansicht: mehrere Kanäle eines Geräts, z. B. „Kanäle A, B, C“
  ///
  /// In de, this message translates to:
  /// **'Kanäle'**
  String get topoGroupChannels;

  /// Screen reader label for a push button key.
  ///
  /// In de, this message translates to:
  /// **'Taste {key}: {state}'**
  String buttonKeySemantics(String key, String state);

  /// Last key press of a push button: key, sent value, time.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt gedrückt: {key} → {value} · {time}'**
  String buttonLastPress(String key, String value, String time);

  /// Push button: no key press seen yet.
  ///
  /// In de, this message translates to:
  /// **'Noch kein Tastendruck seit dem Verbinden'**
  String get buttonNoPress;

  /// Push button display: level (page) of the keys; tap to switch.
  ///
  /// In de, this message translates to:
  /// **'Ebene {page} von {count}'**
  String buttonPage(String page, String count);

  /// Werkzeug: Ton und Mitteilung, wenn eine Gruppenadresse gesendet wird
  ///
  /// In de, this message translates to:
  /// **'Wächter'**
  String get watchTitle;

  /// Hinweis in der App, wenn ein Wächter auslöst
  ///
  /// In de, this message translates to:
  /// **'Wächter: {what}'**
  String watchHit(String what);

  /// Glocke im Detailblatt: Wächter anlegen
  ///
  /// In de, this message translates to:
  /// **'Wächter auf diese Adresse'**
  String get watchAdd;

  /// Glocke im Detailblatt: Wächter entfernen
  ///
  /// In de, this message translates to:
  /// **'Wächter entfernen'**
  String get watchRemove;

  /// Meldung nach dem Anlegen
  ///
  /// In de, this message translates to:
  /// **'Wächter scharf: {what}'**
  String watchAdded(String what);

  /// Untertitel im Menü
  ///
  /// In de, this message translates to:
  /// **'Ton und Mitteilung, sobald eine Adresse gesendet wird'**
  String get watchTool;

  /// Erklärung oben auf der Wächter-Seite
  ///
  /// In de, this message translates to:
  /// **'Ein Wächter meldet sich mit Ton und Mitteilung, sobald seine Gruppenadresse gesendet wird – optional nur bei einem bestimmten Wert. Er hört mit, solange der Monitor verbunden ist; auf iPhone und iPad bleibt dafür der Bildschirm an.'**
  String get watchExplain;

  /// Leerer Zustand der Wächter-Seite
  ///
  /// In de, this message translates to:
  /// **'Noch keine Wächter. Lege einen an oder tippe in den Details einer Adresse auf die Glocke.'**
  String get watchEmpty;

  /// Titel des Dialogs und Knopf
  ///
  /// In de, this message translates to:
  /// **'Neuer Wächter'**
  String get watchNew;

  /// Schalter im Dialog und in der Liste
  ///
  /// In de, this message translates to:
  /// **'Mit Ton'**
  String get watchSound;

  /// Fehler im Dialog
  ///
  /// In de, this message translates to:
  /// **'Bitte eine Gruppenadresse wie 1/2/3 eingeben.'**
  String get watchInvalid;

  /// Eintrag auf der Bezahlseite, abgemeldet
  ///
  /// In de, this message translates to:
  /// **'Auf weiteren Geräten nutzen'**
  String get accountUseEverywhere;

  /// Eintrag auf der Bezahlseite, angemeldet
  ///
  /// In de, this message translates to:
  /// **'Angemeldet als {email}'**
  String accountSignedInAs(String email);

  /// Windows: nach dem Öffnen der Kaufseite
  ///
  /// In de, this message translates to:
  /// **'Die Kaufseite ist im Browser offen. Nach dem Kauf hier „Käufe wiederherstellen“ tippen.'**
  String get planCheckoutOpened;

  /// Kauf wartet auf Freigabe (Ask to Buy, verzögerte Zahlung)
  ///
  /// In de, this message translates to:
  /// **'Der Kauf wartet noch auf Freigabe, etwa durch „Kaufen anfragen“ oder die Zahlungsart. Sobald er bestätigt ist, wird die Stufe freigeschaltet.'**
  String get planPendingApproval;

  /// Bezahlseite: Es gibt noch keine Angebote
  ///
  /// In de, this message translates to:
  /// **'Plus und Pro sind hier noch nicht verfügbar.'**
  String get planNotYetAvailable;

  /// Bestandsnutzer in der ersten Bezahlversion
  ///
  /// In de, this message translates to:
  /// **'Bisher war alles frei. Jetzt gibt es Free, Plus und Pro: Du behältst Pro noch bis {date}, danach gilt Free. Deine Daten bleiben erhalten.'**
  String planOpenNotice(String date);

  /// Einmalig nach dem Ende der Übergangszeit
  ///
  /// In de, this message translates to:
  /// **'Die Übergangszeit ist vorbei, jetzt gilt Free. Deine Daten bleiben erhalten. Mit Plus oder Pro sind die Werkzeuge wieder da.'**
  String get planOpenEnded;

  /// Windows: Hinweis vor dem Kauf
  ///
  /// In de, this message translates to:
  /// **'Zum Kaufen anmelden'**
  String get planSignInToBuy;

  /// Titel: Diagnosepaket für den Support
  ///
  /// In de, this message translates to:
  /// **'Diagnosepaket'**
  String get diagTitle;

  /// Untertitel im Werkzeugmenü
  ///
  /// In de, this message translates to:
  /// **'Fehler mit Aufzeichnung und Projekt an den Support schicken'**
  String get diagTool;

  /// Einleitung Diagnosepaket
  ///
  /// In de, this message translates to:
  /// **'Das Paket hilft dem Support, deinen Fehler nachzustellen: Busaufzeichnung, Projekt, deine Beschreibung und technische Eckdaten in einer ZIP-Datei. Es kann Personenbezug haben: Prüfe vor dem Senden, was drin ist.'**
  String get diagIntro;

  /// Feld: Fehlerbeschreibung
  ///
  /// In de, this message translates to:
  /// **'Was ist passiert?'**
  String get diagProblemLabel;

  /// Platzhalter Fehlerbeschreibung
  ///
  /// In de, this message translates to:
  /// **'z. B. Licht Küche reagiert nicht auf den Taster'**
  String get diagProblemHint;

  /// Feld: erwartetes Verhalten
  ///
  /// In de, this message translates to:
  /// **'Was hast du erwartet? (optional)'**
  String get diagExpectedLabel;

  /// Zeitpunkt des Fehlers
  ///
  /// In de, this message translates to:
  /// **'Zeitpunkt des Fehlers: {time}'**
  String diagOccurred(String time);

  /// Abschnitt: Quelle der Telegramme
  ///
  /// In de, this message translates to:
  /// **'Busaufzeichnung'**
  String get diagSourceLabel;

  /// Quelle: Telegramme der laufenden Sitzung
  ///
  /// In de, this message translates to:
  /// **'Laufende Sitzung · {count} Telegramme'**
  String diagSourceSession(int count);

  /// Abschnitt: Zeitraum
  ///
  /// In de, this message translates to:
  /// **'Zeitraum um den Fehler'**
  String get diagRangeLabel;

  /// Zeitraum: ganze Aufzeichnung
  ///
  /// In de, this message translates to:
  /// **'Alles'**
  String get diagRangeAll;

  /// Zeitraum: Minuten vor dem Fehler
  ///
  /// In de, this message translates to:
  /// **'{minutes} min'**
  String diagRangeMinutes(int minutes);

  /// Erklärung Zeitraum
  ///
  /// In de, this message translates to:
  /// **'Minuten vor dem Fehler (bei einer Aufnahme vor ihrem Ende).'**
  String get diagRangeHint;

  /// Schalter: Namen von Gruppenadressen und Geräten
  ///
  /// In de, this message translates to:
  /// **'Namen mitsenden'**
  String get diagNamesTitle;

  /// Erklärung Namen mit Beispielen
  ///
  /// In de, this message translates to:
  /// **'Namen von Gruppenadressen und Geräten, z. B. {examples}. Sie helfen bei der Auswertung; ohne sie stehen dort nur Adressen und Produkte.'**
  String diagNamesHint(String examples);

  /// Erklärung Namen ohne Beispiele
  ///
  /// In de, this message translates to:
  /// **'Namen von Gruppenadressen und Geräten helfen bei der Auswertung; ohne sie stehen dort nur Adressen und Produkte.'**
  String get diagNamesHintEmpty;

  /// Kennung: Inhalt des Pakets
  ///
  /// In de, this message translates to:
  /// **'Inhalt'**
  String get diagContents;

  /// Inhalt: Aufzeichnung
  ///
  /// In de, this message translates to:
  /// **'Busaufzeichnung: {count} Telegramme, {from} – {to}'**
  String diagContentRecording(int count, String from, String to);

  /// Inhalt: gesicherte Telegramme
  ///
  /// In de, this message translates to:
  /// **'Data Secure: {count} Telegramme nur mit Zeit und Adressen, ohne Inhalt'**
  String diagContentSecure(int count);

  /// Inhalt: Projekt
  ///
  /// In de, this message translates to:
  /// **'Projekt: {groups} Gruppenadressen, {devices} Geräte, Datenpunkttypen und Verknüpfungen'**
  String diagContentProject(int groups, int devices);

  /// Inhalt: Namen enthalten
  ///
  /// In de, this message translates to:
  /// **'Namen von Gruppenadressen und Geräten: enthalten'**
  String get diagContentNamesIn;

  /// Inhalt: Namen entfernt
  ///
  /// In de, this message translates to:
  /// **'Namen von Gruppenadressen und Geräten: entfernt'**
  String get diagContentNamesOut;

  /// Inhalt: Technik
  ///
  /// In de, this message translates to:
  /// **'Technik: App-Version, Plattform und Betriebssystem, Verbindungsart, Gateway-Typ und -Name, Plan, Expertenmodus, Sprache, Einstellungen'**
  String get diagContentTechnical;

  /// Inhalt: Log
  ///
  /// In de, this message translates to:
  /// **'Meldungen der App: {count} Zeilen'**
  String diagContentLog(int count);

  /// Was nicht im Paket ist
  ///
  /// In de, this message translates to:
  /// **'Nicht enthalten: Passwörter, Keyring und Schlüssel, ETS-Projektdatei. Aus Texten herausgefiltert, soweit erkennbar: IP-Adressen, Hostnamen, MAC- und Seriennummern, E-Mail, bekannte Namen von Projekt, Installation, Kunde und Betrieb.'**
  String get diagExcluded;

  /// Knopf: diagnostics.json anzeigen
  ///
  /// In de, this message translates to:
  /// **'Dateiinhalt ansehen'**
  String get diagShowFile;

  /// Knopf: teilen (iOS, Android)
  ///
  /// In de, this message translates to:
  /// **'Paket teilen'**
  String get diagShare;

  /// Knopf: speichern (Desktop)
  ///
  /// In de, this message translates to:
  /// **'Paket speichern'**
  String get diagSave;

  /// Knopf: herunterladen (Add-on)
  ///
  /// In de, this message translates to:
  /// **'Paket herunterladen'**
  String get diagDownload;

  /// Fehler beim Öffnen
  ///
  /// In de, this message translates to:
  /// **'Kein Diagnosepaket von Busclear.'**
  String get diagPackageInvalid;

  /// Fehler: neueres Format
  ///
  /// In de, this message translates to:
  /// **'Das Diagnosepaket stammt aus einer neueren App-Version.'**
  String get diagPackageNewer;

  /// Hinweis beim Import mit Verbindung
  ///
  /// In de, this message translates to:
  /// **'Zum Öffnen eines Diagnosepakets zuerst die Verbindung trennen.'**
  String get diagImportDisconnect;

  /// Import erfolgreich
  ///
  /// In de, this message translates to:
  /// **'Diagnosepaket als Installation „{name}“ geöffnet.'**
  String diagImported(String name);

  /// Import im Add-on
  ///
  /// In de, this message translates to:
  /// **'Aufnahme übernommen. Das Projekt aus dem Paket lässt sich nur in den Apps laden.'**
  String get diagImportedRecordingOnly;

  /// Notiz der importierten Aufnahme
  ///
  /// In de, this message translates to:
  /// **'Was ist passiert: {text}'**
  String diagNoteProblem(String text);

  /// Notiz der importierten Aufnahme
  ///
  /// In de, this message translates to:
  /// **'Erwartet: {text}'**
  String diagNoteExpected(String text);

  /// Name der Installation aus einem Paket
  ///
  /// In de, this message translates to:
  /// **'Diagnose {date}'**
  String diagInstallationName(String date);

  /// Tooltip Import in Aufnahmen
  ///
  /// In de, this message translates to:
  /// **'Importieren: Aufnahme, Telegramm-CSV, ETS-Telegrammdatei (.xml) oder Diagnosepaket (.zip)'**
  String get diagImportHint;

  /// Monitor: Beschriftung vor den Chips der aktiven Filter
  ///
  /// In de, this message translates to:
  /// **'Gefiltert'**
  String get filterActive;

  /// Wächter: Vergleich „Wert enthält …“
  ///
  /// In de, this message translates to:
  /// **'enthält'**
  String get watchContains;

  /// Wächter-Dialog: Beschriftung für Vergleich und Wert
  ///
  /// In de, this message translates to:
  /// **'Bedingung'**
  String get watchCondition;

  /// Wächter-Dialog: ohne Vergleich, jedes Telegramm meldet sich
  ///
  /// In de, this message translates to:
  /// **'beliebiger Wert'**
  String get watchAnyValue;

  /// Wächter-Dialog: Platzhalter im Wertfeld
  ///
  /// In de, this message translates to:
  /// **'z. B. Ein oder 20'**
  String get watchValueExample;

  /// Wächter-Dialog: Platzhalter im Adressfeld, Vorschläge aus dem Projekt
  ///
  /// In de, this message translates to:
  /// **'1/2/3 oder Name'**
  String get watchAddressHint;

  /// Wächter-Dialog: Knopf zum Anlegen
  ///
  /// In de, this message translates to:
  /// **'Anlegen'**
  String get watchCreate;

  /// Verbinden: Beschriftung der Auswahl UDP/TCP/Routing/Secure
  ///
  /// In de, this message translates to:
  /// **'Verbindungsart'**
  String get connectModeLabel;

  /// Inbetriebnahme, Detailspalte: zum nächsten offenen Prüfpunkt springen
  ///
  /// In de, this message translates to:
  /// **'Nächster offener Punkt'**
  String get commNextOpen;

  /// Inbetriebnahme, Detailspalte: Geräte mit Objekten an der Adresse
  ///
  /// In de, this message translates to:
  /// **'Verknüpfte Geräte'**
  String get commLinked;

  /// Objektliste eines Geräts: Knopf, der 0 oder 1 an die Schalt-Adresse schreibt
  ///
  /// In de, this message translates to:
  /// **'{value} an {address} senden'**
  String deviceSendValue(String value, String address);

  /// Projekt-Abgleich: Ergebnis einer Prüfung mit Befunden
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Abweichung} other{{n} Abweichungen}}'**
  String checkFindings(int n);

  /// Topologie-Übersicht: Abschnitt einer Linie mit den Reiheneinbaugeräten (Aktoren)
  ///
  /// In de, this message translates to:
  /// **'Verteiler'**
  String get topoRailActuators;

  /// Topologie-Übersicht: Abschnitt einer Linie mit Tastern, Binäreingängen, Meldern, Wetterstation
  ///
  /// In de, this message translates to:
  /// **'Sensoren'**
  String get topoRailSensors;

  /// Rückfrage beim Verlassen des Monitors mit Zurück
  ///
  /// In de, this message translates to:
  /// **'Verbindung trennen?'**
  String get monitorLeaveTitle;

  /// Rückfrage beim Verlassen des Monitors mit Zurück: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Zurück zur Startseite trennt die Verbindung zum Gateway. Aufnahmen und Wächter laufen dann nicht weiter.'**
  String get monitorLeaveText;

  /// Projekt-Abgleich: Kennung der Box mit den Prüfungen am beobachteten Verkehr
  ///
  /// In de, this message translates to:
  /// **'Busverkehr'**
  String get checkSectionTraffic;

  /// Projekt-Abgleich: Kennung der Box mit den Prüfungen am ETS-Projekt selbst (ohne Busverkehr)
  ///
  /// In de, this message translates to:
  /// **'Projekt'**
  String get checkSectionProject;

  /// Prüfung: Rückmeldeadresse, an der kein Objekt mit Übertragen-Flag sendet
  ///
  /// In de, this message translates to:
  /// **'Rückmeldung ohne Ü-Flag'**
  String get checkStatusNoTransmit;

  /// Erklärung zu checkStatusNoTransmit
  ///
  /// In de, this message translates to:
  /// **'An dieser Rückmeldeadresse sendet kein Objekt mit Ü-Flag – der Status kommt nie auf den Bus.'**
  String get checkStatusNoTransmitHint;

  /// Prüfung: Adresse, auf die mehrere Objekte mit Ü-Flag senden
  ///
  /// In de, this message translates to:
  /// **'Mehrere Sender'**
  String get checkMultipleSenders;

  /// Erklärung zu checkMultipleSenders
  ///
  /// In de, this message translates to:
  /// **'Mehrere Objekte senden auf dieselbe Adresse. Bei Tastern, Meldern und Visualisierung gewollt, bei Aktorkanälen meist ein Versehen.'**
  String get checkMultipleSendersHint;

  /// Prüfung: Rückmeldeadresse, die gelesen wird, aber an der kein Objekt das Lesen-Flag hat
  ///
  /// In de, this message translates to:
  /// **'Gelesen ohne L-Flag'**
  String get checkReadNoReadFlag;

  /// Erklärung zu checkReadNoReadFlag
  ///
  /// In de, this message translates to:
  /// **'Status lesen und Inbetriebnahme fragen diese Adressen ab. Ohne Objekt mit L-Flag bleibt die Anfrage unbeantwortet.'**
  String get checkReadNoReadFlagHint;

  /// Prüfung: Gerät im Projekt ohne verknüpfte Gruppenadresse
  ///
  /// In de, this message translates to:
  /// **'Geräte ohne Verknüpfung'**
  String get checkDevicesNoLinks;

  /// Erklärung zu checkDevicesNoLinks
  ///
  /// In de, this message translates to:
  /// **'Kein Objekt dieser Geräte hat eine Gruppenadresse – nicht fertig projektiert oder überzählig. Koppler und Tunnel zählen nicht.'**
  String get checkDevicesNoLinksHint;

  /// Prüfung: Kommunikationsobjekt mit Gruppenadresse, aber ohne Kommunikation-Flag
  ///
  /// In de, this message translates to:
  /// **'Objekte ohne K-Flag'**
  String get checkObjectsNoComm;

  /// Erklärung zu checkObjectsNoComm
  ///
  /// In de, this message translates to:
  /// **'Das Objekt hat eine Adresse, aber kein K-Flag – es nimmt am Busverkehr nicht teil.'**
  String get checkObjectsNoCommHint;

  /// Projekt-Abgleich: Adressen ohne gepflegten Namen oder ohne Datenpunkttyp
  ///
  /// In de, this message translates to:
  /// **'Ohne Namen oder Datentyp'**
  String get checkIncomplete;

  /// Erklärung zu checkIncomplete
  ///
  /// In de, this message translates to:
  /// **'Ohne Namen und Datentyp zeigen Monitor, Diagnose und der Gruppenmonitor der ETS nur Adresse und Rohwert. Beides in der ETS nachtragen.'**
  String get checkIncompleteHint;

  /// Projekt-Abgleich: Adresse hat nur den Vorgabenamen der ETS
  ///
  /// In de, this message translates to:
  /// **'ohne Namen'**
  String get checkNoName;

  /// Prüfung: mehrere Objekte einer Adresse antworten auf Leseanfragen
  ///
  /// In de, this message translates to:
  /// **'L-Flag mehrfach'**
  String get checkMultipleReadAnswers;

  /// Erklärung zu checkMultipleReadAnswers
  ///
  /// In de, this message translates to:
  /// **'Mehrere Objekte mit L-Flag antworten alle auf eine Leseanfrage, womöglich mit verschiedenen Werten. Das L-Flag gehört nur an das Objekt, das den Zustand führt.'**
  String get checkMultipleReadAnswersHint;

  /// Prüfung: Befehlsadresse, auf die im Projekt kein Objekt sendet
  ///
  /// In de, this message translates to:
  /// **'Ohne Sender'**
  String get checkWithoutSender;

  /// Erklärung zu checkWithoutSender
  ///
  /// In de, this message translates to:
  /// **'Im Projekt sendet kein Objekt auf diese Adresse. Meist Visualisierung, Logik oder Panel ohne Platzhalter im Projekt – dann bleiben ihre Telegramme im Monitor namenlos –, sonst eine vergessene Verknüpfung.'**
  String get checkWithoutSenderHint;

  /// Prüfung: Befehlsadresse ohne Objekt mit K- und S-Flag
  ///
  /// In de, this message translates to:
  /// **'Ohne Empfänger'**
  String get checkWithoutReceiver;

  /// Erklärung zu checkWithoutReceiver
  ///
  /// In de, this message translates to:
  /// **'Kein Objekt mit K- und S-Flag hört auf diese Adresse – Telegramme darauf bewirken nichts.'**
  String get checkWithoutReceiverHint;

  /// Prüfung: Linien mit sehr vielen Geräten
  ///
  /// In de, this message translates to:
  /// **'Volle Linien'**
  String get checkCrowdedLines;

  /// Erklärung zu checkCrowdedLines
  ///
  /// In de, this message translates to:
  /// **'Mehr als {limit} Geräte: Die Linie hat kaum Reserve für Erweiterungen und Busstrom. Ein Liniensegment trägt höchstens 64 Teilnehmer.'**
  String checkCrowdedLinesHint(int limit);

  /// Projekt-Abgleich: Geräte auf einer Linie
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Gerät} other{{count} Geräte}}'**
  String checkLineDevices(int count);

  /// Prüfung: Adressen in Hauptgruppe 14 oder 15 bei mehreren Linien
  ///
  /// In de, this message translates to:
  /// **'Hauptgruppe 14 oder 15'**
  String get checkMainGroup1415;

  /// Erklärung zu checkMainGroup1415
  ///
  /// In de, this message translates to:
  /// **'Ältere Linienkoppler führen diese Hauptgruppen nicht in der Filtertabelle und sperren sie oder leiten sie immer weiter. Für linienübergreifende Adressen besser die Hauptgruppen 0–13.'**
  String get checkMainGroup1415Hint;

  /// Prüfung: Adresse heißt Zentral-Aus, bekommt aber den Wert 1
  ///
  /// In de, this message translates to:
  /// **'Zentral-Aus mit Ein'**
  String get checkCentralOffOn;

  /// Projekt-Abgleich: Katalog ohne Flags der Kommunikationsobjekte (älterer Import)
  ///
  /// In de, this message translates to:
  /// **'ETS-Projekt neu importieren, um die Flags zu lesen'**
  String get checkReimport;

  /// Kürzel der Objekt-Flags in dieser Reihenfolge: Kommunikation, Lesen, Schreiben, Übertragen, Aktualisieren – genau 5 Zeichen wie in der ETS
  ///
  /// In de, this message translates to:
  /// **'KLSÜA'**
  String get flagLetters;

  /// Kommunikationsobjekt ohne gesetzte Flags
  ///
  /// In de, this message translates to:
  /// **'keine Flags'**
  String get flagsNone;

  /// Gesundheit: Hinweis statt Leseknopf, wenn es keine Adresse zum Lesen gibt
  ///
  /// In de, this message translates to:
  /// **'Noch keine Adresse zum Lesen: Ohne ETS-Projekt prüft Gesundheit den mitgehörten Verkehr. Mit Projekt liest sie auch alle Status-Adressen.'**
  String get healthNothingToRead;

  /// Inbetriebnahme-Kennzahl: von Hand als in Ordnung abgehakt (neben „Beantwortet“, das automatisch zählt)
  ///
  /// In de, this message translates to:
  /// **'Von Hand OK'**
  String get commOkManual;

  /// Import-Fortschritt: Datei laden
  ///
  /// In de, this message translates to:
  /// **'Datei wird eingelesen …'**
  String get importReading;

  /// Import-Fortschritt: Archiv öffnen und auslesen
  ///
  /// In de, this message translates to:
  /// **'Projekt wird geöffnet …'**
  String get importOpening;

  /// Import-Fortschritt: geschütztes Projekt
  ///
  /// In de, this message translates to:
  /// **'Projekt wird entschlüsselt und ausgelesen …'**
  String get importDecrypting;

  /// Import-Fortschritt: Katalog speichern
  ///
  /// In de, this message translates to:
  /// **'Projekt wird gespeichert …'**
  String get importSaving;

  /// Hinweis im Import-Fortschritt
  ///
  /// In de, this message translates to:
  /// **'Große Projekte brauchen im Browser bis zu einer Minute.'**
  String get importSlowHint;

  /// Start im Home-Assistant-Panel: App dockt an die Busverbindung des Add-ons an
  ///
  /// In de, this message translates to:
  /// **'Verbinde mit dem Add-on …'**
  String get addonAttaching;

  /// Wächter-Liste: Regel spielt einen Ton
  ///
  /// In de, this message translates to:
  /// **'mit Ton'**
  String get watchWithSound;

  /// Wächter-Liste: Regel ohne Ton
  ///
  /// In de, this message translates to:
  /// **'ohne Ton'**
  String get watchSilent;

  /// Tooltip am Schalter einer Wächter-Regel
  ///
  /// In de, this message translates to:
  /// **'Wächter aktiv'**
  String get watchActive;

  /// Erklärtext der Wächter im Add-on bzw. an der Box (serverseitig)
  ///
  /// In de, this message translates to:
  /// **'Ein Wächter meldet sich, sobald seine Gruppenadresse gesendet wird – optional nur bei einem bestimmten Wert. Das Add-on prüft ihn auch ohne offene App und schickt eine Home-Assistant-Mitteilung; ein offener Monitor spielt dazu den Ton.'**
  String get watchExplainServer;

  /// Adresswahl: Projektadresse, die noch nicht gesendet hat
  ///
  /// In de, this message translates to:
  /// **'Noch kein Telegramm'**
  String get boardNoTelegramYet;

  /// Diagramm-Legende: gewählte Adresse ohne Telegramm
  ///
  /// In de, this message translates to:
  /// **'noch keine Werte'**
  String get chartsNoValuesYet;

  /// Diagramm mit Adressen, aber noch ohne Werte
  ///
  /// In de, this message translates to:
  /// **'Wartet auf die ersten Telegramme – die Reihen erscheinen, sobald die Adressen senden.'**
  String get chartsWaiting;

  /// Projekt-Abgleich: Grundlage der Busverkehr-Prüfungen
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Telegramm ausgewertet} other{{count} Telegramme ausgewertet}}'**
  String checkEvaluatedTelegrams(int count);

  /// Quelle: ein Tag aus dem Langzeitverlauf
  ///
  /// In de, this message translates to:
  /// **'Langzeitverlauf {date}'**
  String diagSourceHistory(String date);

  /// Titel des Dialogs für einen neuen Kommentar
  ///
  /// In de, this message translates to:
  /// **'Kommentar'**
  String get annotationTitle;

  /// Titel beim Bearbeiten eines Kommentars
  ///
  /// In de, this message translates to:
  /// **'Kommentar bearbeiten'**
  String get annotationEditTitle;

  /// Feld für den Kommentartext
  ///
  /// In de, this message translates to:
  /// **'Was ist passiert?'**
  String get annotationNoteLabel;

  /// Beispiel im Kommentarfeld
  ///
  /// In de, this message translates to:
  /// **'Drittes Mal gedrückt: Licht bleibt aus'**
  String get annotationNoteHint;

  /// Fehler bei leerem Kommentar
  ///
  /// In de, this message translates to:
  /// **'Schreib kurz, was passiert ist, oder füg einen Screenshot hinzu.'**
  String get annotationEmpty;

  /// Kommentar entfernen
  ///
  /// In de, this message translates to:
  /// **'Kommentar löschen'**
  String get annotationDelete;

  /// Knopf im Telegramm-Detail
  ///
  /// In de, this message translates to:
  /// **'Kommentieren'**
  String get annotationAdd;

  /// Bezug eines Kommentars ohne Telegramm
  ///
  /// In de, this message translates to:
  /// **'Zeitpunkt {time}'**
  String annotationAboutTime(String time);

  /// Bezug eines Kommentars im Diagramm
  ///
  /// In de, this message translates to:
  /// **'Diagramm {names}'**
  String annotationAboutChart(String names);

  /// Überschrift über Kommentaren
  ///
  /// In de, this message translates to:
  /// **'Kommentare'**
  String get annotationsLabel;

  /// Übersicht aller Kommentare
  ///
  /// In de, this message translates to:
  /// **'Kommentare'**
  String get annotationsTitle;

  /// Untertitel im Menü
  ///
  /// In de, this message translates to:
  /// **'Was dir an Telegrammen und im Verlauf aufgefallen ist'**
  String get annotationsTool;

  /// Leere Übersicht
  ///
  /// In de, this message translates to:
  /// **'Noch keine Kommentare. Tippe ein Telegramm an und wähle „Kommentieren“, oder setz im Diagramm einen Kommentar am Fadenkreuz.'**
  String get annotationsEmpty;

  /// Überschrift der Bildauswahl
  ///
  /// In de, this message translates to:
  /// **'Screenshots'**
  String get shotsLabel;

  /// Knopf zum Auswählen eines Bildes
  ///
  /// In de, this message translates to:
  /// **'Screenshot hinzufügen'**
  String get shotsAdd;

  /// Hinweis unter der Bildauswahl
  ///
  /// In de, this message translates to:
  /// **'Bis zu {max}, verkleinert. Prüf vorher, ob darauf Adressen, Namen oder Passwörter zu sehen sind, die nicht weitergegeben werden sollen.'**
  String shotsHint(int max);

  /// Bild nicht lesbar
  ///
  /// In de, this message translates to:
  /// **'{name} ist kein lesbares Bild.'**
  String shotsInvalid(String name);

  /// Obergrenze für Screenshots erreicht
  ///
  /// In de, this message translates to:
  /// **'Der Platz für Screenshots ist voll. Lösch ältere Kommentare mit Bildern, um neue hinzuzufügen.'**
  String get shotsQuota;

  /// Vorschaubild antippen
  ///
  /// In de, this message translates to:
  /// **'Screenshot groß zeigen'**
  String get shotsOpen;

  /// Bild entfernen
  ///
  /// In de, this message translates to:
  /// **'Screenshot entfernen'**
  String get shotsRemove;

  /// Zeitleiste einer Aufnahme
  ///
  /// In de, this message translates to:
  /// **'Zeitleiste'**
  String get timelineTitle;

  /// Bedienhinweis über der Zeitleiste
  ///
  /// In de, this message translates to:
  /// **'Ziehen verschiebt, Strg bzw. Cmd mit Mausrad oder zwei Finger zoomen. Zeiger auf ein Telegramm zeigt es, Tippen kommentiert es. Tippen auf die Zeitachse springt mit der Wiedergabe dorthin.'**
  String get timelineHint;

  /// Leere Aufnahme
  ///
  /// In de, this message translates to:
  /// **'Diese Aufnahme enthält keine Telegramme.'**
  String get timelineEmpty;

  /// Keine Kommentare in der Zeitleiste
  ///
  /// In de, this message translates to:
  /// **'Noch keine Kommentare in diesem Zeitraum. Tippe auf ein Telegramm oder eine Stelle in der Zeitleiste.'**
  String get timelineNoAnnotations;

  /// Telegramm wurde wiederholt
  ///
  /// In de, this message translates to:
  /// **'Wiederholung'**
  String get timelineRepeated;

  /// Screenreader
  ///
  /// In de, this message translates to:
  /// **'Zeitleiste mit {telegrams} Telegrammen und {notes} Kommentaren'**
  String timelineSemantics(int telegrams, int notes);

  /// Kommentar am Fadenkreuz
  ///
  /// In de, this message translates to:
  /// **'Kommentar bei {time}'**
  String chartsAnnotate(String time);

  /// Ohne Fadenkreuz
  ///
  /// In de, this message translates to:
  /// **'Zum Kommentieren eine Stelle im Diagramm wählen'**
  String get chartsAnnotateHint;

  /// Kommentare im Paket
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{Keine Kommentare im Zeitraum} =1{1 Kommentar im Zeitraum kommt mit} other{{count} Kommentare im Zeitraum kommen mit}}'**
  String diagAnnotationsInRange(int count);

  /// Schalter für ältere Kommentare
  ///
  /// In de, this message translates to:
  /// **'Ältere Kommentare mitschicken ({count})'**
  String diagOlderAnnotations(int count);

  /// Erklärung zum Schalter
  ///
  /// In de, this message translates to:
  /// **'Aus den letzten {days} Tagen, außerhalb der Aufnahme, mit dem Telegramm dazu'**
  String diagOlderAnnotationsHint(int days);

  /// Inhalt des Pakets
  ///
  /// In de, this message translates to:
  /// **'{notes, plural, =0{Keine Kommentare} =1{1 Kommentar} other{{notes} Kommentare}}, {shots, plural, =0{keine Screenshots} =1{1 Screenshot} other{{shots} Screenshots}}'**
  String diagContentAnnotations(int notes, int shots);

  /// Großes Paket
  ///
  /// In de, this message translates to:
  /// **'Das Paket ist {mb} MB groß und passt vielleicht nicht als E-Mail-Anhang.'**
  String diagLarge(int mb);

  /// Zeitraum aus Fehler melden
  ///
  /// In de, this message translates to:
  /// **'Zeitraum: seit dem Start um {time}'**
  String diagRangeSince(String time);

  /// Befund eines Diagnosepakets
  ///
  /// In de, this message translates to:
  /// **'Befund'**
  String get findingsTitle;

  /// Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Fehlerbild'**
  String get findingsProblem;

  /// Ohne Fehlerbild
  ///
  /// In de, this message translates to:
  /// **'Keine Beschreibung'**
  String get findingsNoProblem;

  /// Erwartetes Verhalten
  ///
  /// In de, this message translates to:
  /// **'Erwartet: {text}'**
  String findingsExpected(String text);

  /// Zeitpunkt
  ///
  /// In de, this message translates to:
  /// **'Aufgetreten {time}'**
  String findingsOccurred(String time);

  /// Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Hinweise'**
  String get findingsHints;

  /// Keine Hinweise
  ///
  /// In de, this message translates to:
  /// **'Nichts Auffälliges in Technik und Verkehr.'**
  String get findingsNoHints;

  /// Keine Kommentare
  ///
  /// In de, this message translates to:
  /// **'Keine Kommentare im Paket.'**
  String get findingsNoAnnotations;

  /// Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Häufigste Adressen'**
  String get findingsBusiest;

  /// Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Technik'**
  String get findingsTechnical;

  /// Abschnitt mit Zeilenzahl
  ///
  /// In de, this message translates to:
  /// **'Log ({count})'**
  String findingsLog(int count);

  /// Filter
  ///
  /// In de, this message translates to:
  /// **'Nur Fehler'**
  String get findingsOnlyErrors;

  /// Leeres Log
  ///
  /// In de, this message translates to:
  /// **'Kein Log im Paket.'**
  String get findingsNoLog;

  /// Keine Fehlerzeilen
  ///
  /// In de, this message translates to:
  /// **'Keine Fehler im Log.'**
  String get findingsNoLogErrors;

  /// Stufe
  ///
  /// In de, this message translates to:
  /// **'Fehler'**
  String get findingLevelCritical;

  /// Stufe
  ///
  /// In de, this message translates to:
  /// **'Prüfen'**
  String get findingLevelWarning;

  /// Stufe
  ///
  /// In de, this message translates to:
  /// **'Info'**
  String get findingLevelInfo;

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Verbindungsfehler: {error}'**
  String findingConnectionError(String error);

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Verbindung war nicht aufgebaut ({state}).'**
  String findingConnectionState(String state);

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Secure-Telegramm abgelehnt} other{{count} Secure-Telegramme abgelehnt}}: Schlüssel oder Zähler passen nicht.'**
  String findingSecureRejected(int count);

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Secure-Telegramm} other{{count} Secure-Telegramme}} ohne Schlüssel: Keyring fehlt oder ist unvollständig.'**
  String findingSecureWithoutKey(int count);

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Wiederholung} other{{count} Wiederholungen}} ({percent} %): Hinweis auf Störungen oder fehlende Quittungen.'**
  String findingRepeated(int count, int percent);

  /// Hinweis: sehr viele Telegramme in einer Sekunde
  ///
  /// In de, this message translates to:
  /// **'Lastspitze: {count} Telegramme in einer Sekunde. Häufig melden nach Busspannungswiederkehr oder einem Zentralbefehl viele Aktoren gleichzeitig zurück – Sendeverzögerung der Aktoren staffeln.'**
  String findingPeakLoad(int count);

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Leseanfrage} other{{count} Leseanfragen}} ohne Antwort: L-Flag oder Gerät prüfen.'**
  String findingUnansweredReads(int count);

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Telegramm} other{{count} Telegramme}} ohne Bestätigung der Schnittstelle.'**
  String findingConfirmErrors(int count);

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Ausfall} other{{count} Ausfälle}} in den letzten 7 Tagen: {summary}'**
  String findingOutages(int count, String summary);

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Fehlerzeile} other{{count} Fehlerzeilen}} im Log der App.'**
  String findingLogErrors(int count);

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Ältere App-Version {version} (aktuell {current}).'**
  String findingOldVersion(String version, String current);

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Kein Release-Build ({mode}).'**
  String findingBuildMode(String mode);

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Die Aufnahme enthält keine Telegramme.'**
  String get findingNoTelegrams;

  /// Technik
  ///
  /// In de, this message translates to:
  /// **'App'**
  String get factApp;

  /// Technik
  ///
  /// In de, this message translates to:
  /// **'Plattform'**
  String get factPlatform;

  /// Technik
  ///
  /// In de, this message translates to:
  /// **'Add-on'**
  String get factAddon;

  /// Technik
  ///
  /// In de, this message translates to:
  /// **'Verbindung'**
  String get factConnection;

  /// Technik
  ///
  /// In de, this message translates to:
  /// **'Tunnel'**
  String get factTunnel;

  /// Technik
  ///
  /// In de, this message translates to:
  /// **'Gateway'**
  String get factGateway;

  /// Technik
  ///
  /// In de, this message translates to:
  /// **'{count} Tunnel'**
  String factTunnelSlots(int count);

  /// Technik
  ///
  /// In de, this message translates to:
  /// **'Secure'**
  String get factSecure;

  /// Technik
  ///
  /// In de, this message translates to:
  /// **'Keyring geladen, {count} Gruppenschlüssel'**
  String factSecureLoaded(int count);

  /// Technik
  ///
  /// In de, this message translates to:
  /// **'Kein Keyring'**
  String get factSecureNone;

  /// Technik
  ///
  /// In de, this message translates to:
  /// **'Verkehr'**
  String get factTraffic;

  /// Technik
  ///
  /// In de, this message translates to:
  /// **'{telegrams} Telegramme · {repeated} Wiederholungen · {unanswered} unbeantwortet'**
  String factTrafficValue(int telegrams, int repeated, int unanswered);

  /// Technik
  ///
  /// In de, this message translates to:
  /// **'Stufe'**
  String get factPlan;

  /// Technik
  ///
  /// In de, this message translates to:
  /// **'Expertenmodus'**
  String get factExpert;

  /// Geführter Ablauf
  ///
  /// In de, this message translates to:
  /// **'Fehler melden'**
  String get reportTitle;

  /// Untertitel im Menü
  ///
  /// In de, this message translates to:
  /// **'Fehler nachstellen und dem Elektriker schicken'**
  String get reportTool;

  /// Einleitung
  ///
  /// In de, this message translates to:
  /// **'Etwas funktioniert nicht wie gedacht? Nimm den Fehler hier auf, dann sieht dein Elektriker genau, was auf dem Bus passiert ist, ohne vorbeikommen zu müssen.'**
  String get reportIntro;

  /// Schritt
  ///
  /// In de, this message translates to:
  /// **'Starte die Aufnahme.'**
  String get reportStep1;

  /// Schritt
  ///
  /// In de, this message translates to:
  /// **'Stell den Fehler nach, z. B. den Taster drücken. Tippe jedes Mal auf „Jetzt ist es passiert“, wenn der Fehler auftritt.'**
  String get reportStep2;

  /// Schritt
  ///
  /// In de, this message translates to:
  /// **'Beschreib kurz, was passiert ist, und schick das Paket an deinen Elektriker.'**
  String get reportStep3;

  /// Hinweis ohne Verbindung
  ///
  /// In de, this message translates to:
  /// **'Die App ist gerade nicht mit dem Bus verbunden. Es wird nur aufgenommen, was nach dem Verbinden ankommt.'**
  String get reportNotConnected;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Aufnahme starten'**
  String get reportStart;

  /// Status
  ///
  /// In de, this message translates to:
  /// **'Aufnahme läuft seit {time} · {count, plural, =1{1 Telegramm} other{{count} Telegramme}}'**
  String reportRunning(String time, int count);

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Stell den Fehler jetzt nach. Sobald er auftritt:'**
  String get reportNowHint;

  /// Großer Knopf
  ///
  /// In de, this message translates to:
  /// **'Jetzt ist es passiert'**
  String get reportNow;

  /// Text einer Marke
  ///
  /// In de, this message translates to:
  /// **'Fehler aufgetreten ({n})'**
  String reportMarkNote(int n);

  /// Keine Marken
  ///
  /// In de, this message translates to:
  /// **'Noch nicht markiert.'**
  String get reportNoMarks;

  /// Anzahl Marken
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Mal markiert} other{{count} Mal markiert}}'**
  String reportMarks(int count);

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Antippen, um zu beschreiben, was genau passiert ist, oder einen Screenshot dazuzulegen.'**
  String get reportMarksHint;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Fertig, Paket erstellen'**
  String get reportFinish;

  /// Kommentare je Gerät
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Kommentar} other{{count} Kommentare}}'**
  String annotationsCount(int count);

  /// Kommentare je Gerät
  ///
  /// In de, this message translates to:
  /// **'Alle {count} Kommentare'**
  String annotationsAll(int count);

  /// Abfrage vor dem Kommentar
  ///
  /// In de, this message translates to:
  /// **'Kommentieren'**
  String get annotationChoiceTitle;

  /// Abfrage vor dem Kommentar
  ///
  /// In de, this message translates to:
  /// **'Die App kann zusätzlich eine Aufnahme ab {time} starten, kurz vor diesem Telegramm, damit es sich später nachvollziehen lässt.'**
  String annotationChoiceText(String time);

  /// Abfrage vor dem Kommentar
  ///
  /// In de, this message translates to:
  /// **'Nur kommentieren'**
  String get annotationChoiceOnly;

  /// Abfrage vor dem Kommentar
  ///
  /// In de, this message translates to:
  /// **'Auch aufnehmen'**
  String get annotationChoiceRecord;

  /// Chip für Objekte ohne Kanal am Gerät
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Objekt ohne Kanal} other{{count} Objekte ohne Kanal}}'**
  String deviceGeneralObjects(int count);

  /// Aufnahme nach Kommentar nicht gestartet
  ///
  /// In de, this message translates to:
  /// **'Aufnahme nicht gestartet. Der Kommentar wird trotzdem gespeichert.'**
  String get annotationRecordFailed;

  /// Details: Knopf, wenn der Datentyp aus der ETS bekannt ist
  ///
  /// In de, this message translates to:
  /// **'Datentyp ändern'**
  String get dptChange;

  /// Details: Knopf, wenn der Datentyp in der App vom ETS-Projekt abweicht
  ///
  /// In de, this message translates to:
  /// **'Datentyp geändert, ETS: DPT {dpt}'**
  String dptChangedFromEts(String dpt);

  /// Projekt-Abgleich: Abschnitt mit Adressen, deren Datentyp in der App geändert wurde
  ///
  /// In de, this message translates to:
  /// **'In der App geänderte Datentypen'**
  String get checkDptChanged;

  /// Projekt-Abgleich: Erklärung zu geänderten Datentypen
  ///
  /// In de, this message translates to:
  /// **'In der ETS nachziehen, sonst gilt nach dem nächsten Projekt-Import dort weiter der alte Datentyp.'**
  String get checkDptChangedHint;

  /// Projekt-Abgleich: Datentyp in der ETS und in der App
  ///
  /// In de, this message translates to:
  /// **'ETS: {ets} → App: DPT {app}'**
  String checkDptChangedRow(String ets, String app);

  /// Projekt-Abgleich: Adresse hat in der ETS keinen Datentyp
  ///
  /// In de, this message translates to:
  /// **'ohne Datentyp'**
  String get checkDptNone;

  /// Details: Filterknopf, wenn der Monitor schon auf diese Adresse gefiltert ist
  ///
  /// In de, this message translates to:
  /// **'Filter aus'**
  String get detailsFilterOff;

  /// Fortschrittsanzeige, solange ein PDF im Hintergrund entsteht
  ///
  /// In de, this message translates to:
  /// **'PDF wird erstellt …'**
  String get pdfBuilding;

  /// Titel der Export-Seite
  ///
  /// In de, this message translates to:
  /// **'Exporte'**
  String get exportsTitle;

  /// Export-Seite: Abschnitt mit PDF-Berichten der Werkzeuge
  ///
  /// In de, this message translates to:
  /// **'Berichte'**
  String get exportsReports;

  /// Export-Seite: Bericht ohne Inhalt, nicht exportierbar
  ///
  /// In de, this message translates to:
  /// **'Noch keine Daten'**
  String get exportsNoData;

  /// Export-Seite: Stand des letzten Gesundheitslaufs
  ///
  /// In de, this message translates to:
  /// **'Lauf {time} · {count, plural, =0{keine Befunde} =1{1 Befund} other{{count} Befunde}}'**
  String exportsHealthRun(String time, int count);

  /// Export-Seite: Stand der Inbetriebnahme
  ///
  /// In de, this message translates to:
  /// **'{checked} von {total} geprüft'**
  String exportsCommState(int checked, int total);

  /// Export-Seite: Abschnitt für mehrere Dateien in einem ZIP
  ///
  /// In de, this message translates to:
  /// **'Gesamtexport'**
  String get exportsBundle;

  /// Export-Seite: Erklärung zum Gesamtexport
  ///
  /// In de, this message translates to:
  /// **'Wähle aus, was in eine ZIP-Datei soll. Sie entsteht im Hintergrund.'**
  String get exportsBundleHint;

  /// Export-Seite: Knopf des Gesamtexports
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{Nichts ausgewählt} =1{1 Datei als ZIP exportieren} other{{count} Dateien als ZIP exportieren}}'**
  String exportsBundleButton(int count);

  /// Fortschrittsanzeige des Gesamtexports
  ///
  /// In de, this message translates to:
  /// **'Export wird erstellt …'**
  String get exportsBuilding;

  /// Export-Seite: Liste der zuletzt erzeugten Dateien
  ///
  /// In de, this message translates to:
  /// **'Letzte Exporte'**
  String get exportsRecent;

  /// Export-Seite: leere Liste der letzten Exporte
  ///
  /// In de, this message translates to:
  /// **'Noch keine Exporte. Die letzten {keep} Dateien dieser Installation erscheinen hier und lassen sich erneut teilen.'**
  String exportsRecentEmpty(int keep);

  /// Export-Seite: Datei aus den letzten Exporten löschen
  ///
  /// In de, this message translates to:
  /// **'Aus der Liste entfernen'**
  String get exportsRemove;

  /// Export-Seite: gemerkte Datei lässt sich nicht lesen
  ///
  /// In de, this message translates to:
  /// **'Datei nicht mehr vorhanden'**
  String get exportsGone;

  /// Export-Seite: Gesundheitsprüfung bzw. Inbetriebnahme jetzt starten
  ///
  /// In de, this message translates to:
  /// **'Prüfen'**
  String get exportsCheck;

  /// Export-Seite: Prüfung erneut laufen lassen
  ///
  /// In de, this message translates to:
  /// **'Erneut prüfen'**
  String get exportsRecheck;

  /// Export-Seite: Prüfung läuft gerade
  ///
  /// In de, this message translates to:
  /// **'Läuft …'**
  String get exportsChecking;

  /// Export-Seite: Prüfen geht nur verbunden
  ///
  /// In de, this message translates to:
  /// **'Zum Prüfen mit dem Bus verbinden'**
  String get exportsCheckOffline;

  /// Export-Seite: offene Prüfpunkte der Inbetriebnahme lesen
  ///
  /// In de, this message translates to:
  /// **'Offene prüfen'**
  String get exportsCheckOpen;

  /// Objektdetails: Hinweis unter dem gekürzten Verlauf
  ///
  /// In de, this message translates to:
  /// **'Die letzten {shown} von {total} Werten – alle im Vollbild'**
  String detailsHistoryLatest(int shown, int total);

  /// Pairing dialog: label of the box password field.
  ///
  /// In de, this message translates to:
  /// **'Box-Passwort'**
  String get boxPairPassword;

  /// Pairing dialog: where to find the box password.
  ///
  /// In de, this message translates to:
  /// **'Nur bei IP-Adresse nötig. Steht als BOX_PASSWORD in knx-box.txt auf der SD-Karte.'**
  String get boxPairPasswordHint;

  /// Box settings: section heading for network access.
  ///
  /// In de, this message translates to:
  /// **'Netz'**
  String get boxNetwork;

  /// Box settings: switch allowing access from the wired network.
  ///
  /// In de, this message translates to:
  /// **'Zugriff über das Kabel'**
  String get boxLanAccess;

  /// Box settings: explanation of the cable access switch.
  ///
  /// In de, this message translates to:
  /// **'Aus: Die Box ist nur in ihrem eigenen WLAN erreichbar, beim Kunden kommt niemand aus dessen Netz an sie heran. An: für die eigene Box im eigenen Netz, dann reicht dort das Box-Passwort.'**
  String get boxLanAccessHint;

  /// Settings of Busclear in a Docker container: whether other devices on the network may reach it.
  ///
  /// In de, this message translates to:
  /// **'Zugriff aus dem Netzwerk'**
  String get boxContainerLanAccess;

  /// Docker settings: the network access switch is read-only, it comes from the container's LAN_ACCESS setting.
  ///
  /// In de, this message translates to:
  /// **'Festgelegt im Container mit LAN_ACCESS (yes oder no). Zum Ändern dort umstellen und den Container neu starten. Aus: nur am Rechner mit dem Container erreichbar.'**
  String get boxContainerLanAccessHint;

  /// Dialog title before turning cable access off.
  ///
  /// In de, this message translates to:
  /// **'Zugriff über das Kabel sperren?'**
  String get boxLanAccessOffTitle;

  /// Dialog body before turning cable access off.
  ///
  /// In de, this message translates to:
  /// **'Geräte, die die Box über das Netz am Kabel erreichen, verlieren den Zugriff, auch dieses, wenn es gerade nicht im WLAN der Box ist. Danach geht es nur noch im WLAN der Box.'**
  String get boxLanAccessOffBody;

  /// Dialog button: turn cable access off.
  ///
  /// In de, this message translates to:
  /// **'Sperren'**
  String get boxLanAccessOff;

  /// Dialog title after pairing with the sticker password.
  ///
  /// In de, this message translates to:
  /// **'Eigenes Box-Passwort setzen?'**
  String get boxPasswordAskTitle;

  /// Dialog body after pairing with the sticker password.
  ///
  /// In de, this message translates to:
  /// **'Das bisherige Passwort steht auf dem Aufkleber und auf der SD-Karte. Wer es hat, kann sich mit der Box koppeln. Mit einem eigenen Passwort geht das nicht mehr; dieses Gerät bleibt gekoppelt.'**
  String get boxPasswordAskBody;

  /// Dialog button: skip changing the box password for now.
  ///
  /// In de, this message translates to:
  /// **'Später'**
  String get boxPasswordAskLater;

  /// Add-on connect screen: Home Assistant has a KNX integration.
  ///
  /// In de, this message translates to:
  /// **'KNX-Integration gefunden'**
  String get haKnxHintTitle;

  /// Add-on connect screen: why to use the HA KNX integration.
  ///
  /// In de, this message translates to:
  /// **'Home Assistant ist schon mit dem Bus verbunden. Das Add-on kann diese Verbindung mitnutzen, statt einen eigenen Tunnelplatz am Gateway zu belegen. Für Programmiermodus, Adresse prüfen und den Busmonitor braucht es weiter einen eigenen Tunnel.'**
  String get haKnxHintBody;

  /// Button: switch to HA mode and connect.
  ///
  /// In de, this message translates to:
  /// **'Ohne eigenen Tunnel verbinden'**
  String get haKnxHintUse;

  /// Button: hide the HA KNX hint.
  ///
  /// In de, this message translates to:
  /// **'Eigenen Tunnel behalten'**
  String get haKnxHintDismiss;

  /// Version line in the menu: app version.
  ///
  /// In de, this message translates to:
  /// **'Busclear {version}'**
  String versionApp(String version);

  /// Version line in the menu: add-on server version.
  ///
  /// In de, this message translates to:
  /// **'Add-on {version}'**
  String versionAddon(String version);

  /// Version line in the menu: Busclear Box server version.
  ///
  /// In de, this message translates to:
  /// **'Box {version}'**
  String versionBox(String version);

  /// Box settings: section for testing the kBerry plug-on module.
  ///
  /// In de, this message translates to:
  /// **'KNX-HAT (Test)'**
  String get boxHat;

  /// Box settings: explanation of the KNX HAT test.
  ///
  /// In de, this message translates to:
  /// **'Prüft das Aufsteckmodul kBerry am seriellen Anschluss der Box: Antwort, Betriebsarten, Telegramme und Busmonitor mit Quittungen.'**
  String get boxHatHint;

  /// Title of the KNX HAT test screen.
  ///
  /// In de, this message translates to:
  /// **'KNX-HAT prüfen'**
  String get boxHatTitle;

  /// KNX HAT test: introduction.
  ///
  /// In de, this message translates to:
  /// **'Vorschau für den direkten Busanschluss. Busleitung an das Modul, Busspannung an. Während der Prüfung ein paar Taster drücken, damit Telegramme und Quittungen kommen. Die Aufzeichnung über IP läuft weiter.'**
  String get boxHatIntro;

  /// KNX HAT test: heading for the Raspberry Pi setup check.
  ///
  /// In de, this message translates to:
  /// **'System'**
  String get boxHatSystem;

  /// KNX HAT test: serial device present and accessible.
  ///
  /// In de, this message translates to:
  /// **'{device} ist bereit.'**
  String boxHatSystemOk(String device);

  /// KNX HAT test: serial device not present.
  ///
  /// In de, this message translates to:
  /// **'{device} fehlt. UART-Einstellung in config.txt prüfen und die Box neu starten.'**
  String boxHatDeviceMissing(String device);

  /// KNX HAT test: serial device not accessible.
  ///
  /// In de, this message translates to:
  /// **'Kein Zugriff auf {device}: {error}'**
  String boxHatDeviceNoAccess(String device, String error);

  /// KNX HAT test: serial console still enabled.
  ///
  /// In de, this message translates to:
  /// **'Die Linux-Konsole liegt noch auf dem seriellen Anschluss (cmdline.txt).'**
  String get boxHatSerialConsole;

  /// KNX HAT test: label of the listening duration choice.
  ///
  /// In de, this message translates to:
  /// **'Mithören je Schritt'**
  String get boxHatSeconds;

  /// KNX HAT test: start button.
  ///
  /// In de, this message translates to:
  /// **'Prüfung starten'**
  String get boxHatStart;

  /// KNX HAT test: progress line with the current step.
  ///
  /// In de, this message translates to:
  /// **'Läuft: {step}'**
  String boxHatRunning(String step);

  /// KNX HAT test: no report yet.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Prüfung gelaufen.'**
  String get boxHatNoReport;

  /// KNX HAT test: heading of the report.
  ///
  /// In de, this message translates to:
  /// **'Ergebnis'**
  String get boxHatResult;

  /// KNX HAT test: copy the report as JSON.
  ///
  /// In de, this message translates to:
  /// **'Bericht kopieren'**
  String get boxHatCopy;

  /// KNX HAT test: snackbar after copying.
  ///
  /// In de, this message translates to:
  /// **'Bericht kopiert'**
  String get boxHatCopied;

  /// KNX HAT test step: FT1.2 reset.
  ///
  /// In de, this message translates to:
  /// **'Verbindung'**
  String get boxHatStepReset;

  /// KNX HAT test step: PEI identify.
  ///
  /// In de, this message translates to:
  /// **'Kennung'**
  String get boxHatStepIdentify;

  /// KNX HAT test step: serial number.
  ///
  /// In de, this message translates to:
  /// **'Seriennummer'**
  String get boxHatStepSerial;

  /// KNX HAT test step: supported cEMI communication modes.
  ///
  /// In de, this message translates to:
  /// **'Betriebsarten'**
  String get boxHatStepModes;

  /// KNX HAT test step: current communication mode.
  ///
  /// In de, this message translates to:
  /// **'Betriebsart beim Start'**
  String get boxHatStepCommMode;

  /// KNX HAT test step: listening in link layer mode.
  ///
  /// In de, this message translates to:
  /// **'Telegramme (Link Layer)'**
  String get boxHatStepLinkLayer;

  /// KNX HAT test step: listening in bus monitor mode.
  ///
  /// In de, this message translates to:
  /// **'Busmonitor mit Quittungen'**
  String get boxHatStepBusmonitor;

  /// KNX HAT test step: restore BAOS mode.
  ///
  /// In de, this message translates to:
  /// **'Zurück in den BAOS-Modus'**
  String get boxHatStepRestore;

  /// KNX HAT test: detected baud rate.
  ///
  /// In de, this message translates to:
  /// **'{baud} Baud'**
  String boxHatBaud(int baud);

  /// KNX HAT test: step got no answer.
  ///
  /// In de, this message translates to:
  /// **'keine Antwort'**
  String get boxHatNoAnswer;

  /// KNX HAT test: step skipped.
  ///
  /// In de, this message translates to:
  /// **'übersprungen'**
  String get boxHatSkipped;

  /// KNX HAT test: module reports no bus monitor mode.
  ///
  /// In de, this message translates to:
  /// **'kein Busmonitor'**
  String get boxHatNoBusmonitor;

  /// KNX HAT test: link layer result.
  ///
  /// In de, this message translates to:
  /// **'{count} Telegramme in {seconds} s'**
  String boxHatFrames(int count, int seconds);

  /// KNX HAT test: bus monitor result.
  ///
  /// In de, this message translates to:
  /// **'{frames} Frames: {ack} ACK, {nak} NAK, {busy} BUSY, {repeated} Wiederholungen, {errors} mit Fehlern'**
  String boxHatBusmonCounts(int frames, int ack, int nak, int busy, int repeated, int errors);

  /// KNX HAT test: frames the module saw but did not pass on.
  ///
  /// In de, this message translates to:
  /// **'{missing} Datenrahmen nicht ausgegeben (Folgenummer), {orphans} ACK ohne Rahmen. Bekannt beim kBerry: zum Aufzeichnen Link Layer wählen.'**
  String boxHatBusmonGaps(int missing, int orphans);

  /// KNX HAT test: no frames received while listening.
  ///
  /// In de, this message translates to:
  /// **'Nichts empfangen. Taster drücken und erneut prüfen.'**
  String get boxHatNothing;

  /// KNX HAT test: cEMI communication mode link layer.
  ///
  /// In de, this message translates to:
  /// **'Link Layer'**
  String get boxHatModeLinkLayer;

  /// KNX HAT test: cEMI communication mode bus monitor.
  ///
  /// In de, this message translates to:
  /// **'Busmonitor'**
  String get boxHatModeBusmonitor;

  /// KNX HAT test: cEMI communication mode local transport layer.
  ///
  /// In de, this message translates to:
  /// **'Transport Layer'**
  String get boxHatModeTransportLayer;

  /// Box settings: title of the backup screen and its entry.
  ///
  /// In de, this message translates to:
  /// **'Sicherung der Box'**
  String get boxBackupTitle;

  /// Box settings: subtitle of the backup entry.
  ///
  /// In de, this message translates to:
  /// **'Alle Anlagen mit Verlauf, Projekt, Wächtern und Prüfbuch in einer Datei, und zurück auf eine neue Box.'**
  String get boxBackupHint;

  /// Box backup: introduction.
  ///
  /// In de, this message translates to:
  /// **'Die Sicherung enthält alle Anlagen der Box: Verlauf, Projekt, Einstellungen, Wächter, Prüfbuch, Hausplan und Busansicht. Box-Passwort, gekoppelte Geräte und Zertifikat sind nie darin: Auf einer neuen Box die Geräte danach neu koppeln.'**
  String get boxBackupIntro;

  /// Box backup: section and button.
  ///
  /// In de, this message translates to:
  /// **'Sicherung erstellen'**
  String get boxBackupCreate;

  /// Box backup: switch.
  ///
  /// In de, this message translates to:
  /// **'KNX-Secure-Schlüssel und Zugangsdaten einschließen'**
  String get boxBackupWithKeys;

  /// Box backup: hint below the switch.
  ///
  /// In de, this message translates to:
  /// **'Keyring, IP-Secure-Passwörter und Zugangsdaten für Mitteilungen und Datenexport, verschlüsselt mit einem eigenen Passwort. Ohne Passwort bleiben sie draußen.'**
  String get boxBackupWithKeysHint;

  /// Box backup: password field.
  ///
  /// In de, this message translates to:
  /// **'Passwort der Sicherung'**
  String get boxBackupPassword;

  /// Box backup: second password field.
  ///
  /// In de, this message translates to:
  /// **'Passwort wiederholen'**
  String get boxBackupPasswordRepeat;

  /// Box backup: password too short.
  ///
  /// In de, this message translates to:
  /// **'Mindestens {count} Zeichen.'**
  String boxBackupPasswordShort(int count);

  /// Box backup: passwords differ.
  ///
  /// In de, this message translates to:
  /// **'Die Passwörter stimmen nicht überein.'**
  String get boxBackupPasswordMismatch;

  /// Box backup: progress while the box derives the key.
  ///
  /// In de, this message translates to:
  /// **'Die Box bereitet die Sicherung vor …'**
  String get boxBackupPreparing;

  /// Box backup: download progress.
  ///
  /// In de, this message translates to:
  /// **'Lade {size} …'**
  String boxBackupDownloading(String size);

  /// Box backup: upload progress.
  ///
  /// In de, this message translates to:
  /// **'Sende {size} an die Box …'**
  String boxBackupUploading(String size);

  /// Box backup: progress while restoring.
  ///
  /// In de, this message translates to:
  /// **'Die Box wird wiederhergestellt …'**
  String get boxBackupRestoring;

  /// Box backup: saved.
  ///
  /// In de, this message translates to:
  /// **'Sicherung gespeichert.'**
  String get boxBackupSaved;

  /// Box backup: saved on the desktop.
  ///
  /// In de, this message translates to:
  /// **'Gespeichert unter {path}'**
  String boxBackupSavedTo(String path);

  /// Box backup: backup made without a password.
  ///
  /// In de, this message translates to:
  /// **'Ohne Schlüssel gesichert: Keyring und Zugangsdaten nach dem Wiederherstellen neu eingeben.'**
  String get boxBackupWithheld;

  /// Box backup: handling note.
  ///
  /// In de, this message translates to:
  /// **'Die Datei enthält den Verlauf im Klartext. Sicher aufbewahren.'**
  String get boxBackupPlain;

  /// Box backup: download broken off.
  ///
  /// In de, this message translates to:
  /// **'Die Sicherung kam nicht vollständig an. Bitte noch einmal versuchen.'**
  String get boxBackupIncomplete;

  /// Box backup: title of the folder dialog on the desktop.
  ///
  /// In de, this message translates to:
  /// **'Ordner für die Sicherung'**
  String get boxBackupChooseFolder;

  /// Box backup: section title.
  ///
  /// In de, this message translates to:
  /// **'Wiederherstellen'**
  String get boxBackupRestore;

  /// Box backup: explanation of restoring.
  ///
  /// In de, this message translates to:
  /// **'Ersetzt alle Anlagen dieser Box durch die aus der Sicherung, auch auf einer frisch eingerichteten Box. Der bisherige Stand bleibt als früherer Stand auf der Box.'**
  String get boxBackupRestoreHint;

  /// Box backup: button that opens the file picker.
  ///
  /// In de, this message translates to:
  /// **'Sicherung auswählen …'**
  String get boxBackupPick;

  /// Box backup: summary of the uploaded backup.
  ///
  /// In de, this message translates to:
  /// **'Sicherung vom {date}: {count, plural, =1{1 Anlage} other{{count} Anlagen}}, {size}'**
  String boxBackupSummary(String date, int count, String size);

  /// Box backup: the backup has secrets.
  ///
  /// In de, this message translates to:
  /// **'Enthält verschlüsselte Schlüssel und Zugangsdaten.'**
  String get boxBackupHasKeys;

  /// Box backup: the backup has no secrets.
  ///
  /// In de, this message translates to:
  /// **'Ohne Schlüssel gesichert: Keyring danach aus der ETS neu einlesen.'**
  String get boxBackupNoKeys;

  /// Box backup: button.
  ///
  /// In de, this message translates to:
  /// **'Box wiederherstellen'**
  String get boxBackupApply;

  /// Box backup: confirmation title.
  ///
  /// In de, this message translates to:
  /// **'Box wiederherstellen?'**
  String get boxBackupConfirmTitle;

  /// Box backup: confirmation text.
  ///
  /// In de, this message translates to:
  /// **'Alle Anlagen dieser Box werden durch {count, plural, =1{die Anlage} other{die {count} Anlagen}} aus der Sicherung vom {date} ersetzt. Der bisherige Stand bleibt als früherer Stand auf der Box und lässt sich herunterladen.'**
  String boxBackupConfirmBody(int count, String date);

  /// Box backup: dialog when the backup password is missing.
  ///
  /// In de, this message translates to:
  /// **'Ohne Schlüssel wiederherstellen?'**
  String get boxBackupWithoutKeysTitle;

  /// Box backup: explanation in that dialog.
  ///
  /// In de, this message translates to:
  /// **'Ohne das Passwort der Sicherung kommen Verlauf, Projekt und Einstellungen zurück, KNX-Secure-Schlüssel und Zugangsdaten nicht. Den Keyring danach aus der ETS neu einlesen und IP-Secure-Passwörter neu eingeben.'**
  String get boxBackupWithoutKeysBody;

  /// Box backup: button in that dialog.
  ///
  /// In de, this message translates to:
  /// **'Ohne Schlüssel'**
  String get boxBackupWithoutKeys;

  /// Box backup: success.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Anlage wiederhergestellt.} other{{count} Anlagen wiederhergestellt.}} Die Box hat offene Verbindungen getrennt, der Monitor verbindet sich von selbst neu.'**
  String boxBackupRestored(int count);

  /// Box backup: restored without secrets.
  ///
  /// In de, this message translates to:
  /// **'Schlüssel nicht wiederhergestellt: Keyring aus der ETS neu einlesen und IP-Secure-Passwörter neu eingeben.'**
  String get boxBackupKeysSkipped;

  /// Box backup: wrong backup password.
  ///
  /// In de, this message translates to:
  /// **'Das Passwort der Sicherung stimmt nicht.'**
  String get boxBackupWrongPassword;

  /// Box backup: read-only mode.
  ///
  /// In de, this message translates to:
  /// **'Nur-Lesen ist an: Wiederherstellen ist gesperrt, Sichern geht.'**
  String get boxBackupReadOnly;

  /// Box backup: not enough space.
  ///
  /// In de, this message translates to:
  /// **'Auf der Box ist nicht genug Platz für diese Sicherung.'**
  String get boxBackupNoSpace;

  /// Box backup: too large.
  ///
  /// In de, this message translates to:
  /// **'Die Sicherung ist zu groß (höchstens 4 GB).'**
  String get boxBackupTooLarge;

  /// Box backup: newer format.
  ///
  /// In de, this message translates to:
  /// **'Die Sicherung stammt von einer neueren Version. Erst die Box aktualisieren.'**
  String get boxBackupNewer;

  /// Box backup: busy.
  ///
  /// In de, this message translates to:
  /// **'Es läuft schon eine Sicherung.'**
  String get boxBackupBusy;

  /// Box backup: staged backup missing.
  ///
  /// In de, this message translates to:
  /// **'Die hochgeladene Sicherung ist nicht mehr da. Bitte die Datei noch einmal wählen.'**
  String get boxBackupStageGone;

  /// Box backup: discard the uploaded backup.
  ///
  /// In de, this message translates to:
  /// **'Verwerfen'**
  String get boxBackupDiscard;

  /// Box backup: section of states set aside by a restore.
  ///
  /// In de, this message translates to:
  /// **'Frühere Stände'**
  String get boxBackupPrevious;

  /// Box backup: explanation of earlier states.
  ///
  /// In de, this message translates to:
  /// **'Vor jedem Wiederherstellen legt die Box den bisherigen Stand hier ab. Löschen gibt den Platz frei.'**
  String get boxBackupPreviousHint;

  /// Box backup: no earlier states.
  ///
  /// In de, this message translates to:
  /// **'Keine.'**
  String get boxBackupPreviousNone;

  /// Box backup: delete confirmation title.
  ///
  /// In de, this message translates to:
  /// **'Früheren Stand löschen?'**
  String get boxBackupPreviousDeleteTitle;

  /// Box backup: delete confirmation text.
  ///
  /// In de, this message translates to:
  /// **'Der Stand vom {date} wird von der Box gelöscht. Das lässt sich nicht rückgängig machen.'**
  String boxBackupPreviousDeleteBody(String date);

  /// Box backup: download an earlier state.
  ///
  /// In de, this message translates to:
  /// **'Herunterladen'**
  String get boxBackupDownload;

  /// Box backup: help below the password field.
  ///
  /// In de, this message translates to:
  /// **'Mindestens {count} Zeichen. Getrennt notieren: Ohne dieses Passwort kommt beim Wiederherstellen alles außer den Schlüsseln zurück, der Keyring dann neu aus der ETS.'**
  String boxBackupPasswordHelp(int count);

  /// Box backup: field for the current box password when restoring.
  ///
  /// In de, this message translates to:
  /// **'Box-Passwort (zur Bestätigung)'**
  String get boxBackupCurrent;

  /// Box backup: help below that field.
  ///
  /// In de, this message translates to:
  /// **'Wiederherstellen ersetzt alle Anlagen der Box, deshalb fragt sie nach ihrem Passwort.'**
  String get boxBackupCurrentHint;

  /// Box backup: box password field left empty.
  ///
  /// In de, this message translates to:
  /// **'Box-Passwort eingeben.'**
  String get boxBackupCurrentMissing;

  /// Box backup: download progress with expected size.
  ///
  /// In de, this message translates to:
  /// **'Lade {done} von etwa {total} …'**
  String boxBackupDownloadingOf(String done, String total);

  /// Box backup: download cancelled.
  ///
  /// In de, this message translates to:
  /// **'Abgebrochen.'**
  String get boxBackupCancelled;

  /// Box backup: the box software is too old.
  ///
  /// In de, this message translates to:
  /// **'Diese Box kann noch keine Sicherungen. Bitte erst aktualisieren.'**
  String get boxBackupTooOld;

  /// Box backup: invalid file.
  ///
  /// In de, this message translates to:
  /// **'Die Datei ist beschädigt oder keine Busclear-Sicherung.'**
  String get boxBackupInvalid;

  /// Box backup: password missing.
  ///
  /// In de, this message translates to:
  /// **'Die Sicherung enthält verschlüsselte Schlüssel: Passwort angeben oder ohne Schlüssel wiederherstellen.'**
  String get boxBackupPasswordMissing;

  /// Box backup: ticket expired.
  ///
  /// In de, this message translates to:
  /// **'Der Download ist abgelaufen. Bitte noch einmal starten.'**
  String get boxBackupTicket;

  /// Box backup: integrity check failed.
  ///
  /// In de, this message translates to:
  /// **'Die Sicherung wurde nach dem Sichern verändert und wird nicht wiederhergestellt.'**
  String get boxBackupTampered;

  /// Box: password locked out for a while.
  ///
  /// In de, this message translates to:
  /// **'Zu viele Fehlversuche. Bitte kurz warten.'**
  String get boxTooManyAttempts;

  /// Box backup: warning on plain HTTP.
  ///
  /// In de, this message translates to:
  /// **'Unverschlüsselte Verbindung: Passwörter und Sicherung gehen im Klartext durch dieses Netz.'**
  String get boxBackupPlainNetwork;

  /// Box backup: dialog title on plain HTTP.
  ///
  /// In de, this message translates to:
  /// **'Ohne Verschlüsselung weiter?'**
  String get boxBackupPlainTitle;

  /// Box backup: dialog text on plain HTTP.
  ///
  /// In de, this message translates to:
  /// **'Die Verbindung zur Box ist nicht verschlüsselt. Passwort der Sicherung, Box-Passwort und die Datei mit den Schlüsseln gehen im Klartext durchs Netz. Sicherer im WLAN der Box, über HTTPS oder am Rechner selbst.'**
  String get boxBackupPlainBody;

  /// Box backup: continue on plain HTTP.
  ///
  /// In de, this message translates to:
  /// **'Trotzdem'**
  String get boxBackupPlainGo;

  /// Box backup: not available in the browser.
  ///
  /// In de, this message translates to:
  /// **'Nur in der App.'**
  String get boxBackupAppOnly;

  /// Box backup: dialog title for an earlier state.
  ///
  /// In de, this message translates to:
  /// **'Früheren Stand herunterladen'**
  String get boxBackupPreviousTitle;

  /// Box backup: dialog text for an earlier state.
  ///
  /// In de, this message translates to:
  /// **'Mit Passwort kommen die Schlüssel dieses Stands verschlüsselt mit, ohne bleiben sie draußen.'**
  String get boxBackupPreviousBody;

  /// Connect screen: button that opens the introduction to the app.
  ///
  /// In de, this message translates to:
  /// **'Einführung'**
  String get tourButton;

  /// Introduction: next card.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get tourNext;

  /// Introduction: previous card.
  ///
  /// In de, this message translates to:
  /// **'Zurück'**
  String get tourBack;

  /// Introduction: close button tooltip.
  ///
  /// In de, this message translates to:
  /// **'Einführung schließen'**
  String get tourClose;

  /// Introduction: position, e.g. "3 of 22".
  ///
  /// In de, this message translates to:
  /// **'{current} von {total}'**
  String tourProgress(int current, int total);

  /// Introduction: title of the demo installation shown in the scenes.
  ///
  /// In de, this message translates to:
  /// **'Demo-Haus'**
  String get tourDemoHouse;

  /// Introduction: chapter with the functions of every tier.
  ///
  /// In de, this message translates to:
  /// **'Grundlagen'**
  String get tourChapterBasics;

  /// Introduction: chapter with history, charts, statistics, watchers, export (Plus).
  ///
  /// In de, this message translates to:
  /// **'Auswertung'**
  String get tourChapterAnalysis;

  /// Introduction: chapter with the expert tools (Pro).
  ///
  /// In de, this message translates to:
  /// **'Expertenmodus'**
  String get tourChapterExpert;

  /// Introduction, first card: title.
  ///
  /// In de, this message translates to:
  /// **'Sieh, was auf deinem Bus passiert.'**
  String get tourWelcomeTitle;

  /// Introduction, first card: text.
  ///
  /// In de, this message translates to:
  /// **'Busclear hört am KNX-IP-Gateway mit und zeigt jedes Telegramm: wer sendet, an welche Gruppenadresse, mit welchem Wert. Diese Einführung führt durch die wichtigsten Stellen, mit dem Demo-Haus als Beispiel.'**
  String get tourWelcomeText;

  /// Introduction: connecting, title.
  ///
  /// In de, this message translates to:
  /// **'Verbinden in einem Schritt.'**
  String get tourConnectTitle;

  /// Introduction: connecting, text.
  ///
  /// In de, this message translates to:
  /// **'Gateway suchen oder die Adresse eintragen, dann Verbinden. UDP passt zu jeder Schnittstelle; TCP, Routing und KNX IP Secure stehen unter Verbindungsart. Jede Anlage hat ihre Installation mit Gateway, Projekt und Einstellungen.'**
  String get tourConnectText;

  /// Introduction chip: search for gateways.
  ///
  /// In de, this message translates to:
  /// **'Gateway suchen'**
  String get tourChipSearch;

  /// Introduction chip: one installation per site.
  ///
  /// In de, this message translates to:
  /// **'Installationen'**
  String get tourChipInstallations;

  /// Introduction: ETS project, title.
  ///
  /// In de, this message translates to:
  /// **'Mit dem ETS-Projekt bekommt jeder Wert einen Namen.'**
  String get tourProjectTitle;

  /// Introduction: ETS project, text.
  ///
  /// In de, this message translates to:
  /// **'Importiere die .knxproj-Datei, auch mit Passwort, oder eine Gruppenadressen-CSV. Dann stehen Namen, Räume, Datentypen und Geräte da statt 1/2/3 und Rohbytes. Für KNX Secure kommt der Keyring dazu. Alles bleibt auf dem Gerät.'**
  String get tourProjectText;

  /// Introduction chip: import a group address CSV.
  ///
  /// In de, this message translates to:
  /// **'Gruppenadressen-CSV'**
  String get tourChipCsv;

  /// Introduction chip: no cloud.
  ///
  /// In de, this message translates to:
  /// **'Bleibt auf dem Gerät'**
  String get tourChipLocal;

  /// Introduction: overview, title.
  ///
  /// In de, this message translates to:
  /// **'Übersicht: jede Adresse als Karte.'**
  String get tourOverviewTitle;

  /// Introduction: overview, text.
  ///
  /// In de, this message translates to:
  /// **'Aktueller Wert, Anzahl und ein Mini-Verlauf, sortiert nach Räumen und Funktionen. Der Stern merkt Favoriten, die Nadel holt eine Sektion nach oben. Die Leiste oben zählt die Telegramme der letzten 60 Sekunden, der Stunde oder des Tages.'**
  String get tourOverviewText;

  /// Introduction: objects, title.
  ///
  /// In de, this message translates to:
  /// **'Objekte: was zusammengehört, steht zusammen.'**
  String get tourObjectsTitle;

  /// Introduction: objects, text.
  ///
  /// In de, this message translates to:
  /// **'Befehl und Rückmeldung eines Lichts, alle Werte eines Raumthermostats: in einer Karte. Aktoren erscheinen als Hutschienengeräte mit leuchtenden Kanal-LEDs.'**
  String get tourObjectsText;

  /// Introduction: live list, title.
  ///
  /// In de, this message translates to:
  /// **'Live: jedes Telegramm der Reihe nach.'**
  String get tourLiveTitle;

  /// Introduction: live list, text.
  ///
  /// In de, this message translates to:
  /// **'Zeit, Art (Schreiben, Lesen, Antwort), Absender, Ziel, Name und Wert. Auffälliges ist markiert, etwa eine falsche Länge oder ein ungewöhnlicher Routingzähler. Pause hält die Liste an, ohne etwas zu verlieren.'**
  String get tourLiveText;

  /// Introduction: filter, title.
  ///
  /// In de, this message translates to:
  /// **'Filtern statt suchen.'**
  String get tourFilterTitle;

  /// Introduction: filter, text.
  ///
  /// In de, this message translates to:
  /// **'Das Feld oben versteht Namen, Adressen, Geräte und Zeiten, auch zusammen. Gespeicherte Filter liegen hinter dem Lesezeichen im Feld.'**
  String get tourFilterText;

  /// Introduction chip: example filter by name; must match something in the demo house (its weather station).
  ///
  /// In de, this message translates to:
  /// **'Wetter'**
  String get tourChipFilterName;

  /// Introduction chip: example filter by sender; must match the filter syntax of the language.
  ///
  /// In de, this message translates to:
  /// **'von:1.1.10'**
  String get tourChipFilterSender;

  /// Introduction chip: example filter by time; must match the filter syntax of the language.
  ///
  /// In de, this message translates to:
  /// **'zeit:14:05-14:10'**
  String get tourChipFilterTime;

  /// Introduction: details, title.
  ///
  /// In de, this message translates to:
  /// **'Details: lesen, schreiben, kommentieren.'**
  String get tourDetailsTitle;

  /// Introduction: details, text.
  ///
  /// In de, this message translates to:
  /// **'Ein Tipp auf eine Karte oder Zeile öffnet die Details: letzter Wert, Verlauf, Absender und verknüpfte Geräte. Von dort liest du den Wert neu, schreibst einen eigenen oder hängst einen Kommentar an.'**
  String get tourDetailsText;

  /// Introduction: health check, title.
  ///
  /// In de, this message translates to:
  /// **'Gesundheit: Ist die Anlage in Ordnung?'**
  String get tourHealthTitle;

  /// Introduction: health check, text.
  ///
  /// In de, this message translates to:
  /// **'Ein Knopf liest alle Status-Adressen und wertet aus, was schon da ist: stumme Geräte, falsche Datentypen, auffällige Zyklen, Wiederholungen und Busqualität. Jeder Befund führt zur Adresse oder zum Gerät.'**
  String get tourHealthText;

  /// Introduction chip: health finding.
  ///
  /// In de, this message translates to:
  /// **'Stumme Adressen'**
  String get tourChipSilent;

  /// Introduction chip: health finding.
  ///
  /// In de, this message translates to:
  /// **'Datentypen'**
  String get tourChipTypes;

  /// Introduction chip: health finding.
  ///
  /// In de, this message translates to:
  /// **'Zyklen'**
  String get tourChipCycles;

  /// Introduction chip: health finding.
  ///
  /// In de, this message translates to:
  /// **'Busqualität'**
  String get tourChipBusQuality;

  /// Introduction: recording and comments, title.
  ///
  /// In de, this message translates to:
  /// **'Aufnehmen, kommentieren, melden.'**
  String get tourRecordTitle;

  /// Introduction: recording and comments, text.
  ///
  /// In de, this message translates to:
  /// **'Der rote Punkt nimmt auf, mit Name und Notiz. Kommentare hängen an Telegrammen und Aufnahmen, mit Bildschirmfotos. „Fehler melden“ hält fest, wann etwas schiefging, und packt alles für deinen Elektriker zusammen.'**
  String get tourRecordText;

  /// Introduction: long-term history, title.
  ///
  /// In de, this message translates to:
  /// **'Verlauf über Tage.'**
  String get tourHistoryTitle;

  /// Introduction: long-term history, text.
  ///
  /// In de, this message translates to:
  /// **'Der Langzeitverlauf hebt ganze Tage auf, im Add-on und auf der Busclear Box rund um die Uhr. Du spulst zurück, was nachts passiert ist, mit Zeitleiste je Gruppenadresse und Wiedergabe in 1- bis 60-facher Geschwindigkeit.'**
  String get tourHistoryText;

  /// Introduction chip: timeline per group address.
  ///
  /// In de, this message translates to:
  /// **'Zeitleiste'**
  String get tourChipTimeline;

  /// Introduction chip: playback speed.
  ///
  /// In de, this message translates to:
  /// **'Wiedergabe 1–60×'**
  String get tourChipPlayback;

  /// Introduction: charts, title.
  ///
  /// In de, this message translates to:
  /// **'Diagramme: mehrere Werte, eine Zeitachse.'**
  String get tourChartsTitle;

  /// Introduction: charts, text.
  ///
  /// In de, this message translates to:
  /// **'Bis zu acht Adressen zusammen, eine Achse je Einheit, Schaltwerte als eigene Zeilen. Gespeicherte Diagramme stehen als eigener Abschnitt in der Übersicht.'**
  String get tourChartsText;

  /// Introduction: statistics, title.
  ///
  /// In de, this message translates to:
  /// **'Statistik: Wer redet am meisten?'**
  String get tourStatsTitle;

  /// Introduction: statistics, text.
  ///
  /// In de, this message translates to:
  /// **'Aktivste Adressen und Absender, Lastspitzen und eine Heatmap über Tage. Ein Tipp auf eine Spitze oder Zelle filtert den Monitor auf diese Zeit.'**
  String get tourStatsText;

  /// Introduction: watchers and alarms, title.
  ///
  /// In de, this message translates to:
  /// **'Wächter und Alarme.'**
  String get tourWatchTitle;

  /// Introduction: watchers and alarms, text.
  ///
  /// In de, this message translates to:
  /// **'Ein Wächter meldet sich mit Ton, sobald eine bestimmte Adresse sendet oder einen Wert erreicht. Alarm- und Störobjekte stehen oben in der Übersicht und schicken auf Wunsch Mitteilungen.'**
  String get tourWatchText;

  /// Introduction chip: watcher with sound.
  ///
  /// In de, this message translates to:
  /// **'Mit Ton'**
  String get tourChipSound;

  /// Introduction: export, title.
  ///
  /// In de, this message translates to:
  /// **'Export in jedem Format.'**
  String get tourExportTitle;

  /// Introduction: export, text.
  ///
  /// In de, this message translates to:
  /// **'Telegramme als PDF, CSV oder für die ETS, Berichte von Gesundheit und Inbetriebnahme und ein ZIP mit allem. Die Export-Seite sammelt die letzten Dateien je Installation.'**
  String get tourExportText;

  /// Introduction: expert mode switch, title.
  ///
  /// In de, this message translates to:
  /// **'Ein Schalter, und die Werkstatt ist da.'**
  String get tourExpertTitle;

  /// Introduction: expert mode switch, text.
  ///
  /// In de, this message translates to:
  /// **'Der Expertenmodus auf dem Verbindungsbildschirm oder unten im Menü schaltet die Werkzeuge für Inbetriebnahme und Fehlersuche ein, dazu Port, Tunneladresse und Verbindungsoptionen. Ohne ihn bleibt die App schlank, verloren geht nichts.'**
  String get tourExpertText;

  /// Introduction chip: connection options in expert mode.
  ///
  /// In de, this message translates to:
  /// **'Port und Tunneladresse'**
  String get tourChipPort;

  /// Introduction: bus monitor, title.
  ///
  /// In de, this message translates to:
  /// **'Busmonitor: jedes Frame.'**
  String get tourBusmonTitle;

  /// Introduction: bus monitor, text.
  ///
  /// In de, this message translates to:
  /// **'Rohframes mit Quittungen (ACK, NAK, BUSY), Wiederholungen und gestörten Telegrammen, die Absender in einer eigenen Spalte. Dafür muss die Schnittstelle den Busmonitor-Modus können.'**
  String get tourBusmonText;

  /// Introduction chip: acknowledgements in the bus monitor.
  ///
  /// In de, this message translates to:
  /// **'ACK · NAK · BUSY'**
  String get tourChipAck;

  /// Introduction chip: repeated telegrams.
  ///
  /// In de, this message translates to:
  /// **'Wiederholungen'**
  String get tourChipRepeats;

  /// Introduction: topology, title.
  ///
  /// In de, this message translates to:
  /// **'Topologie: Linien und Koppler.'**
  String get tourTopoTitle;

  /// Introduction: topology, text.
  ///
  /// In de, this message translates to:
  /// **'Geräte nach Linien, Routingzähler, Tunnel und Verkehr über Koppler. Ein Gerät öffnet sein Blatt mit Kanälen, Tastern und Adressen.'**
  String get tourTopoText;

  /// Introduction: communication map, title.
  ///
  /// In de, this message translates to:
  /// **'Kommunikationskarte: wer mit wem.'**
  String get tourMapTitle;

  /// Introduction: communication map, text.
  ///
  /// In de, this message translates to:
  /// **'Für jede Adresse, wer sendet und wer laut Projekt empfängt. Durchgezogen ist beobachtet, gestrichelt steht nur im Projekt.'**
  String get tourMapText;

  /// Introduction: project check, title.
  ///
  /// In de, this message translates to:
  /// **'Projekt-Abgleich.'**
  String get tourCheckTitle;

  /// Introduction: project check, text.
  ///
  /// In de, this message translates to:
  /// **'Busverkehr gegen das ETS-Projekt: was fehlt, was unbekannt ist, was nie sendet, dazu die Flags der Objekte schon ohne Busverkehr.'**
  String get tourCheckText;

  /// Introduction: commissioning and diagnostics, title.
  ///
  /// In de, this message translates to:
  /// **'Inbetriebnahme und Diagnose.'**
  String get tourCommTitle;

  /// Introduction: commissioning and diagnostics, text.
  ///
  /// In de, this message translates to:
  /// **'Die Checkliste liest alle Status-Adressen nacheinander und hakt Antworten ab; was offen bleibt, prüfst du vor Ort und bekommst ein PDF-Protokoll. Die Diagnose findet Geräte im Programmiermodus, prüft Adressen und scannt Linien.'**
  String get tourCommText;

  /// Introduction chip: diagnostics finds devices in programming mode.
  ///
  /// In de, this message translates to:
  /// **'Programmiermodus'**
  String get tourChipProgMode;

  /// Introduction chip: diagnostics scans a line.
  ///
  /// In de, this message translates to:
  /// **'Linienscan'**
  String get tourChipLineScan;

  /// Introduction: send, trigger, replay, title.
  ///
  /// In de, this message translates to:
  /// **'Senden, auslösen, wiedergeben.'**
  String get tourSendTitle;

  /// Introduction: send, trigger, replay, text.
  ///
  /// In de, this message translates to:
  /// **'Senden wie im ETS-Gruppenmonitor, auch verzögert oder zyklisch. Trigger-Aufnahmen starten bei einem Wert, einer Störung oder einer Wiederholung, mit Vorlauf. Eine Aufnahme lässt sich auf den Bus zurückspielen, nach ausdrücklicher Bestätigung.'**
  String get tourSendText;

  /// Introduction: Busclear Box, title.
  ///
  /// In de, this message translates to:
  /// **'Busclear Box für die Baustelle.'**
  String get tourBoxTitle;

  /// Introduction: Busclear Box, text.
  ///
  /// In de, this message translates to:
  /// **'Ein Raspberry Pi, der rund um die Uhr mitschreibt und ein eigenes WLAN aufspannt. Gekoppelt wird per Aufkleber, den Verlauf holt die App direkt von der Box. Noch eine Vorschau.'**
  String get tourBoxText;

  /// Introduction chip: the box opens its own Wi-Fi.
  ///
  /// In de, this message translates to:
  /// **'Eigenes WLAN'**
  String get tourChipWifi;

  /// Introduction chip: pairing with the sticker.
  ///
  /// In de, this message translates to:
  /// **'Koppeln per Aufkleber'**
  String get tourChipSticker;

  /// Introduction: card about higher tiers, title.
  ///
  /// In de, this message translates to:
  /// **'Mehr mit Plus und Pro.'**
  String get tourMoreTitle;

  /// Introduction: card about higher tiers, text.
  ///
  /// In de, this message translates to:
  /// **'Plus hebt den Verlauf über Tage auf, bringt Diagramme, Statistik, Wächter und Export. Pro schaltet den Expertenmodus mit Busmonitor, Topologie, Inbetriebnahme und Diagnose frei. Im Demo-Haus kannst du alles ausprobieren.'**
  String get tourMoreText;

  /// Introduction: button to the plan screen.
  ///
  /// In de, this message translates to:
  /// **'Stufen ansehen'**
  String get tourMorePlans;

  /// Introduction, last card: title.
  ///
  /// In de, this message translates to:
  /// **'Bereit.'**
  String get tourReadyTitle;

  /// Introduction, last card: text.
  ///
  /// In de, this message translates to:
  /// **'Im Demo-Haus probierst du alles gefahrlos aus, ganz ohne Anlage. Die Einführung findest du jederzeit wieder auf dem Verbindungsbildschirm.'**
  String get tourReadyText;

  /// Introduction, last card: button that opens the demo house.
  ///
  /// In de, this message translates to:
  /// **'Demo-Haus öffnen'**
  String get tourOpenDemo;

  /// Introduction, last card: close button.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get tourDone;

  /// Inbetriebnahme: beim Durchklingeln auf dem Bus gesehen
  ///
  /// In de, this message translates to:
  /// **'Gesehen'**
  String get commSeen;

  /// Inbetriebnahme: Absender ist nicht das Gerät aus dem Projekt
  ///
  /// In de, this message translates to:
  /// **'fremder Absender'**
  String get commForeign;

  /// Inbetriebnahme: Schalter Durchklingeln
  ///
  /// In de, this message translates to:
  /// **'Abhaken, sobald gesendet'**
  String get commRollCall;

  /// Inbetriebnahme: Erklärung Durchklingeln
  ///
  /// In de, this message translates to:
  /// **'Durchklingeln: Taster drücken, Fenster öffnen – jede Adresse der Liste, die auf dem Bus sendet, hakt sich selbst ab. Sendet ein anderes Gerät als im Projekt, wird es markiert.'**
  String get commRollCallExplain;

  /// Inbetriebnahme: Klangquittung für die Liste einschalten
  ///
  /// In de, this message translates to:
  /// **'Mit Ton (Klangquittung)'**
  String get commToneOn;

  /// Inbetriebnahme: Klangquittung für die Liste ausschalten
  ///
  /// In de, this message translates to:
  /// **'Ton aus'**
  String get commToneOff;

  /// Werkzeug: Ton je Telegramm
  ///
  /// In de, this message translates to:
  /// **'Klangquittung'**
  String get ackTitle;

  /// Werkzeugliste: Untertitel Klangquittung
  ///
  /// In de, this message translates to:
  /// **'Ton bei jedem Telegramm – allein in Betrieb nehmen'**
  String get ackTool;

  /// Klangquittung: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Spielt einen kurzen Ton bei jedem Telegramm einer Linie, eines Geräts, einer Gruppenadresse oder der Inbetriebnahme-Liste. So hörst du am Taster, ob er auf dem Bus ankommt – ohne zweite Person am Tablet.'**
  String get ackExplain;

  /// Klangquittung: Ziel ist die Checkliste
  ///
  /// In de, this message translates to:
  /// **'Inbetriebnahme-Liste'**
  String get ackTargetChecklist;

  /// Klangquittung: Ziel Linie
  ///
  /// In de, this message translates to:
  /// **'Linie {line}'**
  String ackLine(String line);

  /// Klangquittung: Eingabe ungültig
  ///
  /// In de, this message translates to:
  /// **'Adresse nicht erkannt'**
  String get ackInvalid;

  /// Klangquittung: Hinweis Desktop/Web
  ///
  /// In de, this message translates to:
  /// **'Die Quittung läuft, solange die App im Vordergrund ist.'**
  String get ackForegroundOnly;

  /// Klangquittung: Hinweis Android
  ///
  /// In de, this message translates to:
  /// **'Auf Android läuft die Quittung auch bei gesperrtem Bildschirm weiter (Mitteilung „Klangquittung“). Das Telefon kann in die Tasche.'**
  String get ackAndroidBackground;

  /// Klangquittung: Hinweis iOS
  ///
  /// In de, this message translates to:
  /// **'iPhone und iPad: nur mit offener App, der Bildschirm bleibt dafür an. Im Hintergrund erlaubt iOS das Mithören nicht. Stummschalter aus, sonst bleibt es leise.'**
  String get ackIosForeground;

  /// Klangquittung: läuft gerade
  ///
  /// In de, this message translates to:
  /// **'Läuft'**
  String get ackRunning;

  /// Klangquittung: Zähler
  ///
  /// In de, this message translates to:
  /// **'{count} Telegramme'**
  String ackCount(int count);

  /// Klangquittung beenden
  ///
  /// In de, this message translates to:
  /// **'Beenden'**
  String get ackStop;

  /// Klangquittung: Auswahl Ziel
  ///
  /// In de, this message translates to:
  /// **'Wessen Telegramme?'**
  String get ackTarget;

  /// Klangquittung: Segment Inbetriebnahme-Liste
  ///
  /// In de, this message translates to:
  /// **'Liste'**
  String get ackKindChecklist;

  /// Klangquittung: Segment Linie
  ///
  /// In de, this message translates to:
  /// **'Linie'**
  String get ackKindLine;

  /// Klangquittung: Segment Gerät
  ///
  /// In de, this message translates to:
  /// **'Gerät'**
  String get ackKindDevice;

  /// Klangquittung: Segment Gruppenadresse
  ///
  /// In de, this message translates to:
  /// **'Adresse'**
  String get ackKindGroup;

  /// Klangquittung: Eingabefeld
  ///
  /// In de, this message translates to:
  /// **'Adresse'**
  String get ackAddress;

  /// Klangquittung starten
  ///
  /// In de, this message translates to:
  /// **'Starten'**
  String get ackStart;

  /// Klangquittung: Abschnitt Töne
  ///
  /// In de, this message translates to:
  /// **'Töne'**
  String get ackSounds;

  /// Klangquittung: Erklärung der Töne
  ///
  /// In de, this message translates to:
  /// **'Kurzer Ton: Schreiben. Heller Doppelton: Antwort. Tiefer Ton: Absender, der laut Projekt nicht an diese Adresse sendet oder unbekannt ist. Bei sehr vielen Telegrammen fallen Töne aus.'**
  String get ackSoundsExplain;

  /// Abnahmeprotokoll: Titel und Bezahlseite
  ///
  /// In de, this message translates to:
  /// **'Abnahmeprotokoll'**
  String get acceptTitle;

  /// Abnahmeprotokoll: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Hält den Stand der Inbetriebnahme fest: was geprüft ist, was offen ist, wer es gemacht hat. Kunde und Techniker unterschreiben auf dem Gerät; danach ist das Protokoll eingefroren und bei der Installation gespeichert.'**
  String get acceptExplain;

  /// Titel des Abnahme-PDFs
  ///
  /// In de, this message translates to:
  /// **'Abnahmeprotokoll'**
  String get acceptPdfTitle;

  /// Abnahmeprotokoll: Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Kunde und Baustelle'**
  String get acceptCustomerSection;

  /// Abnahmeprotokoll: Feld Kunde
  ///
  /// In de, this message translates to:
  /// **'Kunde'**
  String get acceptCustomer;

  /// Abnahmeprotokoll: Feld Baustelle
  ///
  /// In de, this message translates to:
  /// **'Baustelle (Anschrift)'**
  String get acceptSite;

  /// Abnahmeprotokoll: Feld Techniker
  ///
  /// In de, this message translates to:
  /// **'Techniker'**
  String get acceptTechnician;

  /// Abnahmeprotokoll: Abschnitt Nacharbeiten und Bemerkungen
  ///
  /// In de, this message translates to:
  /// **'Vereinbarungen'**
  String get acceptNotesSection;

  /// Abnahmeprotokoll: Feld Nacharbeiten
  ///
  /// In de, this message translates to:
  /// **'Vereinbarte Nacharbeiten'**
  String get acceptFollowUps;

  /// Abnahmeprotokoll: Feld Bemerkungen
  ///
  /// In de, this message translates to:
  /// **'Bemerkungen'**
  String get acceptRemarks;

  /// Abnahmeprotokoll: Beispiel Bemerkung
  ///
  /// In de, this message translates to:
  /// **'z. B. Kunde in die Bedienung eingewiesen'**
  String get acceptRemarksHint;

  /// Abnahmeprotokoll: Abschnitt mit freiwilligen Angaben
  ///
  /// In de, this message translates to:
  /// **'Angaben zum Auftrag (optional)'**
  String get acceptDetailsSection;

  /// Abnahmeprotokoll: Feld und Zelle im PDF
  ///
  /// In de, this message translates to:
  /// **'Bezug auf Norm'**
  String get acceptStandard;

  /// Abnahmeprotokoll: Beispiel Norm
  ///
  /// In de, this message translates to:
  /// **'z. B. DIN VDE 0100-600'**
  String get acceptStandardHint;

  /// Abnahmeprotokoll: Feld und Zelle im PDF
  ///
  /// In de, this message translates to:
  /// **'Projektnummer'**
  String get acceptProjectNumber;

  /// Abnahmeprotokoll: Feld und Zelle im PDF
  ///
  /// In de, this message translates to:
  /// **'Beginn der Gewährleistung'**
  String get acceptWarrantyStart;

  /// Abnahmeprotokoll: Knopf, solange kein Datum gewählt ist
  ///
  /// In de, this message translates to:
  /// **'Datum wählen'**
  String get acceptWarrantyPick;

  /// Abnahmeprotokoll: Tooltip
  ///
  /// In de, this message translates to:
  /// **'Datum entfernen'**
  String get acceptWarrantyClear;

  /// Abnahmeprotokoll: Abschnitt im Formular und im PDF
  ///
  /// In de, this message translates to:
  /// **'Fotos zu den Mängeln'**
  String get acceptDefects;

  /// Abnahmeprotokoll: Erklärung über den Mängeln
  ///
  /// In de, this message translates to:
  /// **'Zu jedem Punkt mit „Problem“ kannst du ein Foto oder einen Screenshot anhängen. Es erscheint im Protokoll.'**
  String get acceptDefectsHint;

  /// Abnahmeprotokoll: Knopf je Mangel
  ///
  /// In de, this message translates to:
  /// **'Foto hinzufügen'**
  String get acceptDefectPhotoAdd;

  /// Abnahmeprotokoll: Tooltip je Mangel
  ///
  /// In de, this message translates to:
  /// **'Foto entfernen'**
  String get acceptDefectPhotoRemove;

  /// Abnahme-PDF: statt eines fehlenden oder veränderten Fotos
  ///
  /// In de, this message translates to:
  /// **'Foto liegt auf diesem Gerät nicht vor'**
  String get acceptDefectPhotoMissing;

  /// Bildunterschrift des Mangelfotos in der Fotodokumentation
  ///
  /// In de, this message translates to:
  /// **'Mangel {address} {name}'**
  String acceptDefectCaption(String address, String name);

  /// Abnahmeprotokoll: Sprache wählen
  ///
  /// In de, this message translates to:
  /// **'Sprache des Protokolls'**
  String get acceptLanguage;

  /// Abnahmeprotokoll: Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Unterschriften'**
  String get acceptSignatures;

  /// Abnahmeprotokoll: unterschreibende Person
  ///
  /// In de, this message translates to:
  /// **'Name des Kunden (Druckbuchstaben)'**
  String get acceptSigner;

  /// Abnahmeprotokoll: Unterschriftsfeld
  ///
  /// In de, this message translates to:
  /// **'Unterschrift Kunde'**
  String get acceptSignCustomer;

  /// Abnahmeprotokoll: Unterschriftsfeld
  ///
  /// In de, this message translates to:
  /// **'Unterschrift Techniker'**
  String get acceptSignTechnician;

  /// Abnahmeprotokoll: erstellen und teilen
  ///
  /// In de, this message translates to:
  /// **'Protokoll erstellen'**
  String get acceptCreate;

  /// Abnahmeprotokoll: was noch fehlt
  ///
  /// In de, this message translates to:
  /// **'Dafür braucht es Kunde, Techniker und beide Unterschriften.'**
  String get acceptMissing;

  /// Abnahmeprotokoll: Liste
  ///
  /// In de, this message translates to:
  /// **'Frühere Protokolle'**
  String get acceptEarlier;

  /// Abnahme-PDF: Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Probleme'**
  String get acceptIssues;

  /// Abnahme-PDF: Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Offene Punkte'**
  String get acceptOpenPoints;

  /// Abnahme-PDF: Satz über den Unterschriften
  ///
  /// In de, this message translates to:
  /// **'Die Anlage wurde im oben beschriebenen Stand übergeben und abgenommen.'**
  String get acceptConfirmation;

  /// Abnahme-PDF: Unterschrift
  ///
  /// In de, this message translates to:
  /// **'Kunde'**
  String get acceptRoleCustomer;

  /// Abnahme-PDF: Unterschrift
  ///
  /// In de, this message translates to:
  /// **'Techniker'**
  String get acceptRoleTechnician;

  /// Abnahme-PDF: Prüfsumme
  ///
  /// In de, this message translates to:
  /// **'Prüfsumme (SHA-256): {checksum}'**
  String acceptChecksum(String checksum);

  /// Abnahme-PDF: Hinweis zur Unterschrift
  ///
  /// In de, this message translates to:
  /// **'Einfache elektronische Unterschrift auf dem Gerät, erstellt mit Busclear.'**
  String get acceptSignatureNote;

  /// Unterschrift: rückgängig
  ///
  /// In de, this message translates to:
  /// **'Letzten Strich zurücknehmen'**
  String get signUndo;

  /// Unterschrift: alles löschen
  ///
  /// In de, this message translates to:
  /// **'Leeren'**
  String get signClear;

  /// Unterschrift: übernehmen
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get signDone;

  /// Unterschrift: Hinweis
  ///
  /// In de, this message translates to:
  /// **'Mit Finger, Stift oder Maus im Feld unterschreiben.'**
  String get signHint;

  /// Unterschrift: Bedienungshilfe
  ///
  /// In de, this message translates to:
  /// **'Unterschriftsfeld'**
  String get signArea;

  /// Werkzeug: sporadische Fehler mit der Box fangen
  ///
  /// In de, this message translates to:
  /// **'Fehlerjagd'**
  String get huntTitle;

  /// Werkzeugliste: Untertitel Fehlerjagd
  ///
  /// In de, this message translates to:
  /// **'Sporadische Fehler über Tage fangen – mit der Busclear Box'**
  String get huntTool;

  /// Fehlerjagd: neu laden
  ///
  /// In de, this message translates to:
  /// **'Aktualisieren'**
  String get huntRefresh;

  /// Fehlerjagd: ohne Box oder Add-on
  ///
  /// In de, this message translates to:
  /// **'Die Fehlerjagd läuft auf der Busclear Box oder im Home-Assistant-Add-on, rund um die Uhr. Koppel die App mit einer Box, um sie einzurichten.'**
  String get huntNeedsBox;

  /// Fehlerjagd: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Für Fehler, die nur manchmal auftreten: Box beim Kunden lassen, die Jagd fängt jeden Treffer eines Wächters mit zwei Minuten davor und einer danach. Am Ende siehst du, wer gesendet hat – oft ist es immer derselbe.'**
  String get huntExplain;

  /// Fehlerjagd: Zustand
  ///
  /// In de, this message translates to:
  /// **'Läuft'**
  String get huntRunning;

  /// Fehlerjagd: Zustand
  ///
  /// In de, this message translates to:
  /// **'Beendet'**
  String get huntEnded;

  /// Fehlerjagd: Ende der Laufzeit
  ///
  /// In de, this message translates to:
  /// **'bis {date}'**
  String huntUntil(String date);

  /// Fehlerjagd: Zeitfenster
  ///
  /// In de, this message translates to:
  /// **'nur {from}–{to} Uhr'**
  String huntWindow(String from, String to);

  /// Fehlerjagd: kein Zeitfenster
  ///
  /// In de, this message translates to:
  /// **'rund um die Uhr'**
  String get huntAllDay;

  /// Fehlerjagd: Anzahl Treffer
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Treffer} other{{count} Treffer}}'**
  String huntHits(int count);

  /// Fehlerjagd beenden
  ///
  /// In de, this message translates to:
  /// **'Jagd beenden'**
  String get huntStop;

  /// Fehlerjagd: Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Neue Jagd'**
  String get huntNew;

  /// Fehlerjagd: keine passenden Wächter
  ///
  /// In de, this message translates to:
  /// **'Die Jagd nutzt Wächter als Regeln. Lege zuerst einen an, z. B. „Rollladen Wohnzimmer Auf = 1“.'**
  String get huntNoWatchers;

  /// Fehlerjagd: Regeln wählen
  ///
  /// In de, this message translates to:
  /// **'Was soll gefangen werden?'**
  String get huntChooseRules;

  /// Fehlerjagd: Feld Name
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get huntName;

  /// Fehlerjagd: Beispiel Name
  ///
  /// In de, this message translates to:
  /// **'z. B. Rollladen fährt nachts hoch'**
  String get huntNameHint;

  /// Fehlerjagd: Laufzeit wählen
  ///
  /// In de, this message translates to:
  /// **'Laufzeit'**
  String get huntDuration;

  /// Fehlerjagd: Laufzeit
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Tag} other{{count} Tage}}'**
  String huntDays(int count);

  /// Fehlerjagd: Schalter Zeitfenster
  ///
  /// In de, this message translates to:
  /// **'Nur in einem Zeitfenster'**
  String get huntOnlyWindow;

  /// Fehlerjagd: Erklärung Zeitfenster
  ///
  /// In de, this message translates to:
  /// **'z. B. nachts von 22 bis 6 Uhr (Uhrzeit der Box)'**
  String get huntOnlyWindowExplain;

  /// Fehlerjagd starten
  ///
  /// In de, this message translates to:
  /// **'Jagd starten'**
  String get huntStart;

  /// Fehlerjagd: Absender aller Treffer
  ///
  /// In de, this message translates to:
  /// **'Wer hat gesendet?'**
  String get huntSenders;

  /// Fehlerjagd: Liste
  ///
  /// In de, this message translates to:
  /// **'Treffer'**
  String get huntResults;

  /// Fehlerjagd: Absender
  ///
  /// In de, this message translates to:
  /// **'von {sender}'**
  String huntFrom(String sender);

  /// Fehlerjagd: Treffer als Aufnahme öffnen
  ///
  /// In de, this message translates to:
  /// **'Öffnen'**
  String get huntOpen;

  /// Fehlerjagd: Fehler
  ///
  /// In de, this message translates to:
  /// **'Treffer nicht geladen. Ist die Box erreichbar?'**
  String get huntSaveFailed;

  /// Plain sentence: sender when the telegram was sent from this app.
  ///
  /// In de, this message translates to:
  /// **'Diese App'**
  String get plainThisApp;

  /// Plain sentence: unnamed sending device.
  ///
  /// In de, this message translates to:
  /// **'Gerät {address}'**
  String plainDevice(String address);

  /// Plain sentence: unnamed group address.
  ///
  /// In de, this message translates to:
  /// **'Adresse {address}'**
  String plainAddress(String address);

  /// Plain sentence for a read request.
  ///
  /// In de, this message translates to:
  /// **'{sender} fragt {target} ab'**
  String plainRead(String sender, String target);

  /// Plain sentence for a response or status telegram.
  ///
  /// In de, this message translates to:
  /// **'{sender} meldet {target}: {value}'**
  String plainReport(String sender, String target, String value);

  /// Plain sentence for a write with a value.
  ///
  /// In de, this message translates to:
  /// **'{sender} hat {target} auf {value} gesetzt'**
  String plainSet(String sender, String target, String value);

  /// Plain sentence for a switching command; action is a participle like 'eingeschaltet' / 'switched on'.
  ///
  /// In de, this message translates to:
  /// **'{sender} hat {target} {action}'**
  String plainAction(String sender, String target, String action);

  /// Plain sentence action: on.
  ///
  /// In de, this message translates to:
  /// **'eingeschaltet'**
  String get plainSwitchedOn;

  /// Plain sentence action: off.
  ///
  /// In de, this message translates to:
  /// **'ausgeschaltet'**
  String get plainSwitchedOff;

  /// Plain sentence action: blind up.
  ///
  /// In de, this message translates to:
  /// **'hochgefahren'**
  String get plainMovedUp;

  /// Plain sentence action: blind down.
  ///
  /// In de, this message translates to:
  /// **'heruntergefahren'**
  String get plainMovedDown;

  /// Plain sentence action: open.
  ///
  /// In de, this message translates to:
  /// **'geöffnet'**
  String get plainOpened;

  /// Plain sentence action: close.
  ///
  /// In de, this message translates to:
  /// **'geschlossen'**
  String get plainClosed;

  /// Plain sentence action: start.
  ///
  /// In de, this message translates to:
  /// **'gestartet'**
  String get plainStarted;

  /// Plain sentence action: stop.
  ///
  /// In de, this message translates to:
  /// **'gestoppt'**
  String get plainStopped;

  /// Plain sentence action: enable.
  ///
  /// In de, this message translates to:
  /// **'freigegeben'**
  String get plainEnabled;

  /// Plain sentence action: disable.
  ///
  /// In de, this message translates to:
  /// **'gesperrt'**
  String get plainDisabled;

  /// Plain sentence action: trigger.
  ///
  /// In de, this message translates to:
  /// **'ausgelöst'**
  String get plainTriggered;

  /// Live table column header for the plain sentence (outside expert mode).
  ///
  /// In de, this message translates to:
  /// **'Was passiert'**
  String get plainColumnEvent;

  /// Teach-in tool title: build names without an ETS project.
  ///
  /// In de, this message translates to:
  /// **'Anlage anlernen'**
  String get learnTitle;

  /// Teach-in tool subtitle in the menu.
  ///
  /// In de, this message translates to:
  /// **'Ohne ETS-Projekt: Taster drücken, benennen, fertig'**
  String get learnTool;

  /// Teach-in explanation.
  ///
  /// In de, this message translates to:
  /// **'Kein ETS-Projekt zur Hand? Drück einen Taster oder schalte ein Licht. Die App hört mit, fängt die Gruppenadressen samt Rückmeldung und fragt, was das war. Daraus entsteht dein eigenes Projekt – Übersicht, Objekte und Diagramme funktionieren sofort. Ein später importiertes ETS-Projekt hat Vorrang; deine Namen bleiben für Adressen, die dort fehlen.'**
  String get learnExplain;

  /// Teach-in: waiting for an event.
  ///
  /// In de, this message translates to:
  /// **'Ich höre mit …'**
  String get learnListening;

  /// Teach-in: instruction while listening.
  ///
  /// In de, this message translates to:
  /// **'Drück jetzt einen Taster oder schalte etwas – am besten nur eine Sache auf einmal.'**
  String get learnPressNow;

  /// Teach-in button in demo mode: simulate a button press.
  ///
  /// In de, this message translates to:
  /// **'Im Demo-Haus einen Taster drücken'**
  String get learnDemoPress;

  /// Teach-in switch: let 2-byte and longer values start an event (sensors).
  ///
  /// In de, this message translates to:
  /// **'Auch Messwerte fangen'**
  String get learnMeasurements;

  /// Teach-in switch explanation.
  ///
  /// In de, this message translates to:
  /// **'Aus: Temperatur & Co. stören nicht beim Taster-Drücken.'**
  String get learnMeasurementsHint;

  /// Teach-in: header of a captured event.
  ///
  /// In de, this message translates to:
  /// **'Gefangen um {time}'**
  String learnCaught(String time);

  /// Teach-in: role of a group address that the button wrote.
  ///
  /// In de, this message translates to:
  /// **'Befehl'**
  String get learnRoleCommand;

  /// Teach-in: role of a group address that followed (status).
  ///
  /// In de, this message translates to:
  /// **'Rückmeldung'**
  String get learnRoleFeedback;

  /// Teach-in: data point type was guessed.
  ///
  /// In de, this message translates to:
  /// **'geraten'**
  String get learnGuessed;

  /// Teach-in: the address is already named in the ETS project.
  ///
  /// In de, this message translates to:
  /// **'Im Projekt: {name}'**
  String learnInProject(String name);

  /// Teach-in question.
  ///
  /// In de, this message translates to:
  /// **'Was hast du gerade gedrückt?'**
  String get learnQuestion;

  /// Teach-in field: room.
  ///
  /// In de, this message translates to:
  /// **'Raum'**
  String get learnRoom;

  /// Teach-in field: name of the function, e.g. ceiling light.
  ///
  /// In de, this message translates to:
  /// **'Was ist es?'**
  String get learnName;

  /// Teach-in field: name of the sending device.
  ///
  /// In de, this message translates to:
  /// **'Gerät (Absender)'**
  String get learnDevice;

  /// Teach-in: default device name.
  ///
  /// In de, this message translates to:
  /// **'Taster {room}'**
  String learnDeviceDefault(String room);

  /// Teach-in: suffix for feedback addresses, e.g. 'Ceiling light status'.
  ///
  /// In de, this message translates to:
  /// **'Status'**
  String get learnStatusSuffix;

  /// Teach-in button: save names.
  ///
  /// In de, this message translates to:
  /// **'Anlernen'**
  String get learnSave;

  /// Teach-in button: discard the captured event.
  ///
  /// In de, this message translates to:
  /// **'Verwerfen'**
  String get learnSkip;

  /// Teach-in button: ignore the starting group address(es) of the caught event for this session.
  ///
  /// In de, this message translates to:
  /// **'{address} nicht mehr fangen'**
  String learnIgnore(String address);

  /// Snackbar after teach-in.
  ///
  /// In de, this message translates to:
  /// **'Angelernt: {name}'**
  String learnSaved(String name);

  /// Teach-in: section header of learned addresses.
  ///
  /// In de, this message translates to:
  /// **'Angelernt ({count})'**
  String learnLearned(int count);

  /// Teach-in: empty list.
  ///
  /// In de, this message translates to:
  /// **'Noch nichts angelernt.'**
  String get learnNothingYet;

  /// Teach-in tooltip: remove a learned address.
  ///
  /// In de, this message translates to:
  /// **'Vergessen'**
  String get learnForget;

  /// Teach-in action: remove all learned addresses.
  ///
  /// In de, this message translates to:
  /// **'Alles Angelernte vergessen'**
  String get learnClearAll;

  /// Teach-in: confirm clearing learned addresses.
  ///
  /// In de, this message translates to:
  /// **'Alle angelernten Namen löschen? Ein importiertes Projekt bleibt.'**
  String get learnClearConfirm;

  /// Teach-in: note in demo mode.
  ///
  /// In de, this message translates to:
  /// **'Demo-Haus: Angelerntes bleibt nur bis zum Verlassen der Demo.'**
  String get learnDemoNote;

  /// Comma-separated room suggestions for teach-in. Keep commas.
  ///
  /// In de, this message translates to:
  /// **'Wohnzimmer,Küche,Flur,Bad,Schlafzimmer,Kinderzimmer,Büro,Esszimmer,Garten,Keller'**
  String get learnRoomSuggestions;

  /// Comma-separated name suggestions for switching (1 bit).
  ///
  /// In de, this message translates to:
  /// **'Licht,Deckenlicht,Spots,Stehlampe,Steckdose,Außenlicht'**
  String get learnNamesSwitch;

  /// Comma-separated name suggestions for blinds.
  ///
  /// In de, this message translates to:
  /// **'Rollladen,Jalousie,Markise'**
  String get learnNamesBlind;

  /// Comma-separated name suggestions for 1-byte values.
  ///
  /// In de, this message translates to:
  /// **'Dimmer,Helligkeit,Rollladen Position,Ventil'**
  String get learnNamesPercent;

  /// Comma-separated name suggestions for measurements.
  ///
  /// In de, this message translates to:
  /// **'Temperatur,Luftfeuchte,Helligkeit,Wind,Leistung'**
  String get learnNamesMeasure;

  /// Comma-separated generic name suggestions.
  ///
  /// In de, this message translates to:
  /// **'Szene,Fensterkontakt,Bewegungsmelder,Dimmen'**
  String get learnNamesOther;

  /// Call to action where no project is loaded.
  ///
  /// In de, this message translates to:
  /// **'Kein ETS-Projekt? Anlage anlernen'**
  String get learnNoProjectCta;

  /// Label for the learned (taught-in) part of the catalog, e.g. in the project menu.
  ///
  /// In de, this message translates to:
  /// **'Angelernt'**
  String get learnSource;

  /// Number of learned group addresses.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 angelernte Adresse} other{{count} angelernte Adressen}}'**
  String learnCount(int count);

  /// Connect help: header above next steps.
  ///
  /// In de, this message translates to:
  /// **'So geht es weiter'**
  String get helpNextSteps;

  /// Connect help title: timeout.
  ///
  /// In de, this message translates to:
  /// **'Das Gateway antwortet nicht'**
  String get helpNoResponseTitle;

  /// Connect help: non-standard port.
  ///
  /// In de, this message translates to:
  /// **'Port {port} ist ungewöhnlich – KNX-IP-Gateways nutzen fast immer 3671.'**
  String helpOddPort(int port);

  /// Connect help: check IP.
  ///
  /// In de, this message translates to:
  /// **'Stimmt die IP-Adresse? „Gateways suchen“ findet Geräte im selben Netz; sonst steht sie im Router oder in der ETS.'**
  String get helpCheckIp;

  /// Connect help: same network.
  ///
  /// In de, this message translates to:
  /// **'Ist dieses Gerät im selben Netz wie das Gateway? Gast-WLAN, VPN oder ein zweiter Router trennen die Netze.'**
  String get helpSameNetwork;

  /// Connect help: bus power.
  ///
  /// In de, this message translates to:
  /// **'Hat das Gateway Strom und hängt am Bus? Ohne Busspannung antworten manche gar nicht.'**
  String get helpBusPower;

  /// Connect help title: network error.
  ///
  /// In de, this message translates to:
  /// **'Das Netzwerk ist nicht erreichbar'**
  String get helpNetworkTitle;

  /// Connect help: Wi-Fi on.
  ///
  /// In de, this message translates to:
  /// **'Ist WLAN bzw. LAN verbunden – mit dem Heimnetz, nicht dem Mobilfunk?'**
  String get helpWifiOn;

  /// Connect help: Apple local network permission.
  ///
  /// In de, this message translates to:
  /// **'iPhone, iPad und Mac fragen einmal nach dem „lokalen Netzwerk“. Abgelehnt? In den Einstellungen unter Datenschutz › Lokales Netzwerk erlauben.'**
  String get helpLocalNetworkPermission;

  /// Connect help: TCP port.
  ///
  /// In de, this message translates to:
  /// **'TCP und IP Secure brauchen Port {port} offen am Gateway. Kann das Gateway kein TCP, die Verbindungsart UDP wählen.'**
  String helpTcpPort(int port);

  /// Connect help title: no free tunnel.
  ///
  /// In de, this message translates to:
  /// **'Alle Tunnel sind belegt'**
  String get helpNoTunnelTitle;

  /// Connect help: who holds tunnels.
  ///
  /// In de, this message translates to:
  /// **'Ein IP-Gateway hat nur wenige Tunnel (oft 1 bis 8). Die ETS, eine Visualisierung (z. B. Home Assistant, Gira X1) oder ein Logikmodul hält sie dauerhaft.'**
  String get helpTunnelsHeld;

  /// Connect help: close ETS.
  ///
  /// In de, this message translates to:
  /// **'ETS-Busmonitor bzw. ETS-Verbindung schließen und hier erneut verbinden.'**
  String get helpCloseEts;

  /// Connect help: scan shows slots.
  ///
  /// In de, this message translates to:
  /// **'„Gateways suchen“ zeigt bei vielen Geräten, wie viele Tunnel gerade frei sind.'**
  String get helpScanShowsSlots;

  /// Connect help: use routing.
  ///
  /// In de, this message translates to:
  /// **'Gibt es einen IP-Router? Routing belegt keinen Tunnel (Verbindungsart im Expertenmodus).'**
  String get helpUseRouting;

  /// Connect help title: tunnel address.
  ///
  /// In de, this message translates to:
  /// **'Die feste Tunneladresse geht nicht'**
  String get helpTunnelAddressTitle;

  /// Connect help: clear fixed address.
  ///
  /// In de, this message translates to:
  /// **'In den Verbindungseinstellungen (Expertenmodus) die feste Tunneladresse leeren – das Gateway vergibt dann eine freie.'**
  String get helpNoFixedAddress;

  /// Connect help title: unsupported.
  ///
  /// In de, this message translates to:
  /// **'Das Gerät bietet keinen passenden Tunnel'**
  String get helpUnsupportedTitle;

  /// Connect help: not an interface.
  ///
  /// In de, this message translates to:
  /// **'Manche Geräte sind reine IP-Router, Visualisierungen oder Server. Die IP-Schnittstelle der Anlage wählen.'**
  String get helpNotAnInterface;

  /// Connect help title: secure auth.
  ///
  /// In de, this message translates to:
  /// **'IP Secure: Zugang abgelehnt'**
  String get helpSecureAuthTitle;

  /// Connect help: load keyring.
  ///
  /// In de, this message translates to:
  /// **'Am einfachsten: den Keyring (.knxkeys) aus der ETS laden – dann stimmen Benutzer, Passwort und Gerätecode von selbst.'**
  String get helpSecureKeyring;

  /// Connect help: password in ETS.
  ///
  /// In de, this message translates to:
  /// **'Von Hand: Benutzer und Passwort des Tunnels stehen in der ETS beim Gateway (Eigenschaften › IP › Tunnel).'**
  String get helpSecurePasswordInEts;

  /// Connect help: not the project password.
  ///
  /// In de, this message translates to:
  /// **'Gemeint ist das Tunnel-Passwort, nicht das Projektpasswort der .knxproj.'**
  String get helpSecureNotProjectPassword;

  /// Connect help title: secure device.
  ///
  /// In de, this message translates to:
  /// **'IP Secure: Gerätecode passt nicht'**
  String get helpSecureDeviceTitle;

  /// Connect help: device code.
  ///
  /// In de, this message translates to:
  /// **'Der Geräte-Authentifizierungscode steht in der ETS beim Gateway (Eigenschaften › IP); mit dem Keyring kommt er mit.'**
  String get helpSecureDeviceCode;

  /// Connect help: right device.
  ///
  /// In de, this message translates to:
  /// **'Antwortet wirklich die eigene Schnittstelle? Zwei Geräte mit derselben IP prüfen.'**
  String get helpSecureRightDevice;

  /// Connect help title: secure missing.
  ///
  /// In de, this message translates to:
  /// **'IP Secure braucht Zugangsdaten'**
  String get helpSecureMissingTitle;

  /// Connect help: ask the electrician.
  ///
  /// In de, this message translates to:
  /// **'Keinen Keyring? Den bekommst du vom Elektriker, zusammen mit der Projektdatei.'**
  String get helpAskElectrician;

  /// Connect help title: routing.
  ///
  /// In de, this message translates to:
  /// **'Routing klappt hier nicht'**
  String get helpRoutingTitle;

  /// Connect help: multicast.
  ///
  /// In de, this message translates to:
  /// **'Routing nutzt Multicast (224.0.23.12). Viele WLAN-Router und Mesh-Systeme leiten das nicht weiter.'**
  String get helpRoutingMulticast;

  /// Connect help: try tunnel.
  ///
  /// In de, this message translates to:
  /// **'Tunnel (UDP) mit der IP-Adresse des Gateways probieren.'**
  String get helpTryTunnel;

  /// Connect help title: scan found nothing.
  ///
  /// In de, this message translates to:
  /// **'Kein Gateway gefunden'**
  String get helpNoGatewayTitle;

  /// Connect help: search silent.
  ///
  /// In de, this message translates to:
  /// **'Manche Gateways antworten nicht auf die Suche. Die IP-Adresse dann direkt eintragen – sie steht im Router oder in der ETS.'**
  String get helpSearchSilent;

  /// Connect help: search finds both.
  ///
  /// In de, this message translates to:
  /// **'Gefunden werden IP-Schnittstellen (Tunnel) und IP-Router (Routing) gleichermaßen.'**
  String get helpRoutingSearch;

  /// Connect help: try demo.
  ///
  /// In de, this message translates to:
  /// **'Ohne Anlage ausprobieren: das Demo-Haus.'**
  String get helpTryDemo;

  /// Gateway search result: free tunnel slots.
  ///
  /// In de, this message translates to:
  /// **'{free} von {total} Tunneln frei'**
  String helpFreeTunnels(int free, int total);

  /// Connect help button: scan.
  ///
  /// In de, this message translates to:
  /// **'Gateways suchen'**
  String get helpActionScan;

  /// Connect help button: keyring.
  ///
  /// In de, this message translates to:
  /// **'Keyring laden'**
  String get helpActionKeyring;

  /// Connect help button: project file help.
  ///
  /// In de, this message translates to:
  /// **'Hilfe zur Projektdatei'**
  String get helpActionProject;

  /// Connect help button: demo.
  ///
  /// In de, this message translates to:
  /// **'Demo-Haus öffnen'**
  String get helpActionDemo;

  /// Project file help: title.
  ///
  /// In de, this message translates to:
  /// **'Die ETS-Projektdatei'**
  String get projectHelpTitle;

  /// Project file help: section.
  ///
  /// In de, this message translates to:
  /// **'Was ist die .knxproj?'**
  String get projectHelpWhatTitle;

  /// Project file help: what it is.
  ///
  /// In de, this message translates to:
  /// **'Dein Elektriker hat die Anlage mit der Planungssoftware ETS eingerichtet. Die Projektdatei (Endung .knxproj) enthält alle Namen: welche Gruppenadresse das Küchenlicht schaltet, welches Gerät wo sitzt, welche Werte es gibt. Mit ihr zeigt Busclear Namen statt Zahlen.'**
  String get projectHelpWhat;

  /// Project file help: section.
  ///
  /// In de, this message translates to:
  /// **'Projektpasswort'**
  String get projectHelpPasswordTitle;

  /// Project file help: password.
  ///
  /// In de, this message translates to:
  /// **'Die Datei kann mit einem Passwort geschützt sein. Die App fragt beim Import danach und braucht es nur zum Öffnen – Datei und Passwort bleiben auf deinem Gerät.'**
  String get projectHelpPassword;

  /// Project file help: section.
  ///
  /// In de, this message translates to:
  /// **'Keyring (.knxkeys)'**
  String get projectHelpKeyringTitle;

  /// Project file help: keyring.
  ///
  /// In de, this message translates to:
  /// **'Nutzt deine Anlage KNX Secure (IP Secure oder Data Secure), gibt es zusätzlich den Keyring mit eigenem Passwort. Ohne ihn kann sich die App nicht mit einem sicheren Gateway verbinden oder verschlüsselte Werte nicht lesen. Ohne Secure brauchst du ihn nicht.'**
  String get projectHelpKeyring;

  /// Project file help: section.
  ///
  /// In de, this message translates to:
  /// **'Wie bekomme ich sie?'**
  String get projectHelpGetTitle;

  /// Project file help: how to get it.
  ///
  /// In de, this message translates to:
  /// **'Frag den Betrieb, der die Anlage gebaut hat. Viele geben die Datei ohne Weiteres heraus, manche gegen eine kleine Gebühr. Für die Namen reicht auch ein CSV-Export der Gruppenadressen aus der ETS.'**
  String get projectHelpGet;

  /// Project file help: section.
  ///
  /// In de, this message translates to:
  /// **'Musteranfrage zum Kopieren'**
  String get projectHelpTemplateTitle;

  /// Project file help: copyable sample request to the electrician. Keep the line breaks.
  ///
  /// In de, this message translates to:
  /// **'Betreff: ETS-Projektdatei für unsere KNX-Anlage\n\nHallo [Name],\n\nSie haben die KNX-Anlage in [Adresse] eingerichtet. Für Wartung und Fehlersuche möchten wir gern selbst einen Überblick behalten. Könnten Sie uns bitte die aktuelle ETS-Projektdatei (.knxproj) mit dem Projektpasswort schicken – und, falls KNX Secure genutzt wird, auch den Keyring (.knxkeys) mit seinem Passwort?\n\nEin CSV-Export der Gruppenadressen würde uns auch schon helfen. Falls dafür Kosten anfallen, sagen Sie uns bitte vorher Bescheid.\n\nVielen Dank und viele Grüße\n[Ihr Name]'**
  String get projectHelpTemplate;

  /// Project file help: copy button.
  ///
  /// In de, this message translates to:
  /// **'Text kopieren'**
  String get projectHelpCopy;

  /// Snackbar after copying the sample request.
  ///
  /// In de, this message translates to:
  /// **'Text kopiert'**
  String get projectHelpCopied;

  /// Project file help: section.
  ///
  /// In de, this message translates to:
  /// **'Keine Datei zu bekommen?'**
  String get projectHelpNoneTitle;

  /// Project file help: alternative teach-in.
  ///
  /// In de, this message translates to:
  /// **'Dann lern die Anlage selbst an: Taster drücken, benennen, fertig. Das geht im Monitor unter „Anlage anlernen“. Ein später importiertes Projekt hat Vorrang, deine Namen bleiben für den Rest.'**
  String get projectHelpNone;

  /// Project file help: disclaimer.
  ///
  /// In de, this message translates to:
  /// **'Das ist keine Rechtsberatung. Ob und wie du die Datei bekommst, regelt dein Vertrag mit dem Betrieb.'**
  String get projectHelpDisclaimer;

  /// Project file help: subtitle in menus.
  ///
  /// In de, this message translates to:
  /// **'Was ist die .knxproj, wie bekomme ich sie?'**
  String get projectHelpTool;

  /// Glossary term.
  ///
  /// In de, this message translates to:
  /// **'Gruppenadresse'**
  String get termGroupAddress;

  /// Glossary term.
  ///
  /// In de, this message translates to:
  /// **'Physikalische Adresse'**
  String get termIndividualAddress;

  /// Glossary term.
  ///
  /// In de, this message translates to:
  /// **'Rückmeldung (Status)'**
  String get termStatus;

  /// Glossary term.
  ///
  /// In de, this message translates to:
  /// **'Datenpunkttyp (DPT)'**
  String get termDpt;

  /// Glossary term.
  ///
  /// In de, this message translates to:
  /// **'Flags'**
  String get termFlags;

  /// Glossary term.
  ///
  /// In de, this message translates to:
  /// **'Linie'**
  String get termLine;

  /// Glossary term.
  ///
  /// In de, this message translates to:
  /// **'Tunnel'**
  String get termTunnel;

  /// Glossary: group address in one sentence.
  ///
  /// In de, this message translates to:
  /// **'Eine Gruppenadresse (z. B. 1/0/1) ist wie ein Kanal: Ein Taster sendet darauf „Ein“, und jeder Aktor, der auf diesem Kanal zuhört, schaltet.'**
  String get termGroupAddressText;

  /// Glossary: individual address.
  ///
  /// In de, this message translates to:
  /// **'Die physikalische Adresse (z. B. 1.1.30) ist die Hausnummer eines Geräts – Bereich, Linie, Gerät – und verrät, wer ein Telegramm gesendet hat.'**
  String get termIndividualAddressText;

  /// Glossary: status.
  ///
  /// In de, this message translates to:
  /// **'Eine Rückmeldung ist die Antwort des Aktors: Sie sagt, ob das Licht wirklich an ist – nicht nur, dass jemand gedrückt hat.'**
  String get termStatusText;

  /// Glossary: DPT.
  ///
  /// In de, this message translates to:
  /// **'Der Datenpunkttyp sagt, wie die Bytes zu lesen sind: 1.001 heißt Ein/Aus, 5.001 Prozent, 9.001 Temperatur in °C.'**
  String get termDptText;

  /// Glossary: flags.
  ///
  /// In de, this message translates to:
  /// **'Flags legen fest, was ein Objekt eines Geräts darf: K kommunizieren, L auf Lesen antworten, S Schreiben annehmen, Ü selbst senden, A Antworten übernehmen.'**
  String get termFlagsText;

  /// Glossary: line.
  ///
  /// In de, this message translates to:
  /// **'Eine Linie ist ein Strang Busleitung mit bis zu 64 Geräten; Linienkoppler verbinden mehrere Linien zu einem Bereich.'**
  String get termLineText;

  /// Glossary: tunnel.
  ///
  /// In de, this message translates to:
  /// **'Ein Tunnel ist ein Zugang übers Netzwerk zum Bus. Ein IP-Gateway hat nur wenige, und jede App, ETS oder Visualisierung belegt einen.'**
  String get termTunnelText;

  /// Glossary example: group address.
  ///
  /// In de, this message translates to:
  /// **'Hier: {address} heißt „{name}“.'**
  String termExampleGroup(String address, String name);

  /// Glossary example: device.
  ///
  /// In de, this message translates to:
  /// **'Hier: {address} ist „{name}“ auf Linie {line}.'**
  String termExampleDevice(String address, String name, String line);

  /// Glossary example: status.
  ///
  /// In de, this message translates to:
  /// **'Hier: {address} „{name}“ meldet den echten Zustand.'**
  String termExampleStatus(String address, String name);

  /// Glossary example: DPT.
  ///
  /// In de, this message translates to:
  /// **'Hier: „{name}“ hat den Typ {dpt}.'**
  String termExampleDpt(String name, String dpt);

  /// Glossary example: flags.
  ///
  /// In de, this message translates to:
  /// **'Hier: „{name}“ am Gerät {device} hat die Flags {flags}.'**
  String termExampleFlags(String name, String device, String flags);

  /// Glossary example: line.
  ///
  /// In de, this message translates to:
  /// **'Hier: Linie {line} hat {count} Geräte.'**
  String termExampleLine(String line, int count);

  /// Glossary example: tunnel.
  ///
  /// In de, this message translates to:
  /// **'Hier: {address} ist ein Tunnel von „{gateway}“.'**
  String termExampleTunnel(String address, String gateway);

  /// Glossary: no example in the current catalog.
  ///
  /// In de, this message translates to:
  /// **'Im eigenen Projekt gibt es dafür noch kein Beispiel – im Demo-Haus schon.'**
  String get termExampleNone;

  /// Header: glossary terms.
  ///
  /// In de, this message translates to:
  /// **'Begriffe'**
  String get glossaryTitle;

  /// Glossary sheet: link to the learn screen.
  ///
  /// In de, this message translates to:
  /// **'Lektionen und Quiz'**
  String get glossaryMore;

  /// Learn screen title.
  ///
  /// In de, this message translates to:
  /// **'KNX lernen'**
  String get lessonsTitle;

  /// Learn tool subtitle.
  ///
  /// In de, this message translates to:
  /// **'Begriffe, kurze Lektionen und ein Mini-Quiz'**
  String get lessonsTool;

  /// Learn screen intro.
  ///
  /// In de, this message translates to:
  /// **'Fünf kurze Lektionen an der eigenen Anlage – oder im Demo-Haus. Tipp einen Begriff an, um ihn mit Beispiel zu sehen.'**
  String get lessonsIntro;

  /// Lesson: try-it line.
  ///
  /// In de, this message translates to:
  /// **'Ausprobieren: {text}'**
  String lessonsTry(String text);

  /// Lesson title.
  ///
  /// In de, this message translates to:
  /// **'1 · Wie KNX schaltet'**
  String get lessonSwitchTitle;

  /// Lesson text.
  ///
  /// In de, this message translates to:
  /// **'Ein Taster weiß nicht, welches Licht er schaltet. Er sendet nur „Ein“ an eine Gruppenadresse. Der Aktor, der auf dieser Adresse hört, schaltet – und meldet über eine zweite Adresse zurück, was er getan hat.'**
  String get lessonSwitchText;

  /// Lesson try.
  ///
  /// In de, this message translates to:
  /// **'Im Live-Monitor zusehen, wie auf ein „Ein“ eine Rückmeldung folgt.'**
  String get lessonSwitchTry;

  /// Lesson title.
  ///
  /// In de, this message translates to:
  /// **'2 · Wer ist wer'**
  String get lessonWhoTitle;

  /// Lesson text.
  ///
  /// In de, this message translates to:
  /// **'Jedes Gerät hat eine physikalische Adresse wie 1.1.30: Bereich 1, Linie 1, Gerät 30. So sieht man in jedem Telegramm, wer es gesendet hat – auch ohne Projekt.'**
  String get lessonWhoText;

  /// Lesson try.
  ///
  /// In de, this message translates to:
  /// **'Ein Telegramm antippen und beim Absender nachsehen.'**
  String get lessonWhoTry;

  /// Lesson title.
  ///
  /// In de, this message translates to:
  /// **'3 · Werte lesen'**
  String get lessonValuesTitle;

  /// Lesson text.
  ///
  /// In de, this message translates to:
  /// **'Auf dem Bus stehen nur Bytes. Erst der Datenpunkttyp macht daraus „21,5 °C“ oder „50 %“. Fehlt er, rät die App aus der Länge – 1 Bit ist meist Schalten, 2 Byte meist ein Messwert.'**
  String get lessonValuesText;

  /// Lesson try.
  ///
  /// In de, this message translates to:
  /// **'In der Übersicht die Temperaturen ansehen.'**
  String get lessonValuesTry;

  /// Lesson title.
  ///
  /// In de, this message translates to:
  /// **'4 · Fragen und Antworten'**
  String get lessonReadTitle;

  /// Lesson text.
  ///
  /// In de, this message translates to:
  /// **'Die App kann eine Adresse „lesen“: Sie fragt, und das Gerät mit dem Lese-Flag antwortet mit dem aktuellen Wert. Antwortet niemand, fehlt oft nur dieses Flag.'**
  String get lessonReadText;

  /// Lesson try.
  ///
  /// In de, this message translates to:
  /// **'Die Gesundheitsprüfung fragt alle Rückmeldungen ab.'**
  String get lessonReadTry;

  /// Lesson title.
  ///
  /// In de, this message translates to:
  /// **'5 · Wie die App verbunden ist'**
  String get lessonConnectTitle;

  /// Lesson text.
  ///
  /// In de, this message translates to:
  /// **'Die App spricht übers Netzwerk mit einem IP-Gateway, das auf dem Bus sitzt. Dafür belegt sie einen Tunnel; sind alle belegt, wartet sie, bis die ETS oder eine Visualisierung einen freigibt.'**
  String get lessonConnectText;

  /// Lesson try.
  ///
  /// In de, this message translates to:
  /// **'Oben auf den Gateway-Namen tippen.'**
  String get lessonConnectTry;

  /// Learn screen: quiz section.
  ///
  /// In de, this message translates to:
  /// **'Mini-Quiz'**
  String get quizTitle;

  /// Quiz button.
  ///
  /// In de, this message translates to:
  /// **'Quiz starten'**
  String get quizStart;

  /// Quiz button: restart.
  ///
  /// In de, this message translates to:
  /// **'Noch einmal'**
  String get quizAgain;

  /// Quiz progress.
  ///
  /// In de, this message translates to:
  /// **'Frage {current} von {total}'**
  String quizProgress(int current, int total);

  /// Quiz feedback.
  ///
  /// In de, this message translates to:
  /// **'Richtig!'**
  String get quizRight;

  /// Quiz feedback.
  ///
  /// In de, this message translates to:
  /// **'Nicht ganz.'**
  String get quizWrong;

  /// Quiz button.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get quizNext;

  /// Quiz result.
  ///
  /// In de, this message translates to:
  /// **'{score} von {total} richtig'**
  String quizResult(int score, int total);

  /// Quiz: questions use the demo catalog.
  ///
  /// In de, this message translates to:
  /// **'Die Fragen kommen aus dem Demo-Haus.'**
  String get quizDemoNote;

  /// Quiz question.
  ///
  /// In de, this message translates to:
  /// **'Welche davon ist eine Gruppenadresse?'**
  String get quizWhichGroup;

  /// Quiz question.
  ///
  /// In de, this message translates to:
  /// **'Auf welcher Linie sitzt das Gerät {address}?'**
  String quizWhichLine(String address);

  /// Quiz question.
  ///
  /// In de, this message translates to:
  /// **'Was für ein Wert ist „{name}“?'**
  String quizWhichDpt(String name);

  /// Quiz answer.
  ///
  /// In de, this message translates to:
  /// **'Ein/Aus (1 Bit)'**
  String get quizDptSwitch;

  /// Quiz answer.
  ///
  /// In de, this message translates to:
  /// **'Prozent (1 Byte)'**
  String get quizDptPercent;

  /// Quiz answer.
  ///
  /// In de, this message translates to:
  /// **'Messwert wie Temperatur (2 Byte)'**
  String get quizDptFloat;

  /// Quiz question.
  ///
  /// In de, this message translates to:
  /// **'Was meldet „{name}“?'**
  String quizWhatStatus(String name);

  /// Quiz answer.
  ///
  /// In de, this message translates to:
  /// **'Was der Aktor wirklich getan hat'**
  String get quizStatusRight;

  /// Quiz answer.
  ///
  /// In de, this message translates to:
  /// **'Wer den Taster gedrückt hat'**
  String get quizStatusWho;

  /// Quiz answer.
  ///
  /// In de, this message translates to:
  /// **'Die Uhrzeit des Tastendrucks'**
  String get quizStatusTime;

  /// Quiz question.
  ///
  /// In de, this message translates to:
  /// **'Das Gateway antwortet, die App bekommt aber keine Verbindung. Woran liegt es am ehesten?'**
  String get quizTunnelBusy;

  /// Quiz answer.
  ///
  /// In de, this message translates to:
  /// **'Alle Tunnel sind belegt'**
  String get quizTunnelRight;

  /// Quiz answer.
  ///
  /// In de, this message translates to:
  /// **'Eine Gruppenadresse ist falsch'**
  String get quizTunnelWrongGa;

  /// Quiz answer.
  ///
  /// In de, this message translates to:
  /// **'Ein Datenpunkttyp fehlt'**
  String get quizTunnelWrongDpt;

  /// Quiz question.
  ///
  /// In de, this message translates to:
  /// **'Eine Adresse antwortet nie auf Lesen. Welches Flag fehlt wahrscheinlich?'**
  String get quizFlagRead;

  /// Quiz answer.
  ///
  /// In de, this message translates to:
  /// **'L (Lesen)'**
  String get quizFlagReadRight;

  /// Quiz answer.
  ///
  /// In de, this message translates to:
  /// **'Ü (Übertragen)'**
  String get quizFlagTransmit;

  /// Quiz answer.
  ///
  /// In de, this message translates to:
  /// **'S (Schreiben)'**
  String get quizFlagWrite;

  /// Short button label on the connect screen: help about the ETS project file.
  ///
  /// In de, this message translates to:
  /// **'Projektdatei?'**
  String get projectHelpShort;

  /// Health light: no recent check.
  ///
  /// In de, this message translates to:
  /// **'Noch nicht geprüft'**
  String get lightUnknown;

  /// Health light: green.
  ///
  /// In de, this message translates to:
  /// **'Alles in Ordnung'**
  String get lightGreen;

  /// Health light: yellow.
  ///
  /// In de, this message translates to:
  /// **'Etwas ist auffällig'**
  String get lightYellow;

  /// Health light: red.
  ///
  /// In de, this message translates to:
  /// **'Bitte nachsehen'**
  String get lightRed;

  /// Weekly report title.
  ///
  /// In de, this message translates to:
  /// **'Wochenbericht'**
  String get weekTitle;

  /// Weekly summary: no run.
  ///
  /// In de, this message translates to:
  /// **'Diese Woche wurde noch nicht geprüft.'**
  String get weekNotChecked;

  /// Weekly summary: nothing open.
  ///
  /// In de, this message translates to:
  /// **'Diese Woche alles in Ordnung.'**
  String get weekAllGood;

  /// Weekly summary: one finding.
  ///
  /// In de, this message translates to:
  /// **'Diese Woche alles in Ordnung bis auf eins: {issue}.'**
  String weekOneIssue(String issue);

  /// Weekly summary: several findings.
  ///
  /// In de, this message translates to:
  /// **'Diese Woche {count} Auffälligkeiten, zuerst: {issue}.'**
  String weekIssues(int count, String issue);

  /// Weekly summary: resolved findings.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Eine hat sich inzwischen erledigt.} other{{count} haben sich inzwischen erledigt.}}'**
  String weekResolved(int count);

  /// Weekly report: number of checks.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{keine Prüfung} =1{1 Prüfung} other{{count} Prüfungen}}'**
  String weekChecks(int count);

  /// Weekly report basis with continuous recording.
  ///
  /// In de, this message translates to:
  /// **'Grundlage: Die {server} hört rund um die Uhr mit; dazu {checks} diese Woche.'**
  String weekBasisContinuous(String server, String checks);

  /// Weekly report basis when the app runs only part-time.
  ///
  /// In de, this message translates to:
  /// **'Grundlage: Die App hat diese Woche etwa {time} an {days, plural, =1{1 Tag} other{{days} Tagen}} mitgehört ({checks}). Was dazwischen passiert, sieht der Bericht nicht – rund um die Uhr hört nur eine Busclear Box oder das Home-Assistant-Add-on mit.'**
  String weekBasisPartial(String time, int days, String checks);

  /// Weekly report basis without listening time.
  ///
  /// In de, this message translates to:
  /// **'Grundlage: {checks}; die App hat diese Woche sonst kaum mitgehört.'**
  String weekBasisNone(String checks);

  /// Duration hours and minutes.
  ///
  /// In de, this message translates to:
  /// **'{hours} h {minutes} min'**
  String weekHours(int hours, int minutes);

  /// Duration minutes.
  ///
  /// In de, this message translates to:
  /// **'{minutes} min'**
  String weekMinutes(int minutes);

  /// Weekly report section: open findings.
  ///
  /// In de, this message translates to:
  /// **'Offen'**
  String get weekOpen;

  /// Weekly report section: resolved.
  ///
  /// In de, this message translates to:
  /// **'Erledigt diese Woche'**
  String get weekDone;

  /// Button: run the health check.
  ///
  /// In de, this message translates to:
  /// **'Jetzt prüfen'**
  String get weekCheckNow;

  /// Button: open the health check screen.
  ///
  /// In de, this message translates to:
  /// **'Zur Gesundheitsprüfung'**
  String get weekOpenHealth;

  /// Weekly report: last run time.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt geprüft: {when}'**
  String weekLastCheck(String when);

  /// Server name in weekly basis.
  ///
  /// In de, this message translates to:
  /// **'Busclear Box'**
  String get weekServerBox;

  /// Server name in weekly basis.
  ///
  /// In de, this message translates to:
  /// **'Home-Assistant-Add-on'**
  String get weekServerAddon;

  /// Plain finding: stopped answering.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ meldet sich nicht mehr'**
  String plainFindingSilent(String name);

  /// Plain finding: never answers.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ antwortet nicht auf Fragen'**
  String plainFindingNoAnswer(String name);

  /// Plain finding: overdue.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ ist ungewöhnlich lange still'**
  String plainFindingOverdue(String name);

  /// Plain finding: out of range.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ zeigt einen unmöglichen Wert'**
  String plainFindingImpossible(String name);

  /// Plain finding: stuck.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ hängt seit Stunden beim selben Wert'**
  String plainFindingStuck(String name);

  /// Plain finding: DPT problems.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ sendet Werte im falschen Format'**
  String plainFindingFormat(String name);

  /// Plain finding: repeats.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ muss oft wiederholen – Leitung oder Gerät prüfen lassen'**
  String plainFindingRepeats(String name);

  /// Teach-in badge: the address is already named in the imported project (which takes precedence).
  ///
  /// In de, this message translates to:
  /// **'im Projekt'**
  String get learnKnown;

  /// Weekly report: the latest run was passive; when the last full run with read requests was.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt mit Lesetest: {when} – Lese-Befunde gelten von dort.'**
  String weekLastFullCheck(String when);

  /// HA-Konfiguration: Titel
  ///
  /// In de, this message translates to:
  /// **'Home Assistant'**
  String get haTitle;

  /// Menü: Untertitel HA-Konfiguration
  ///
  /// In de, this message translates to:
  /// **'Konfiguration für die KNX-Integration aus dem Projekt'**
  String get haTool;

  /// HA-Konfiguration: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Busclear leitet aus dem ETS-Projekt Leuchten, Behänge, Raumregler, Schalter und Sensoren für die KNX-Integration von Home Assistant ab. Wähle aus, was du übernehmen willst. Markierte Einträge bitte prüfen – dort war die Zuordnung nicht eindeutig.'**
  String get haExplain;

  /// HA-Konfiguration: ohne Projekt
  ///
  /// In de, this message translates to:
  /// **'Für die Konfiguration braucht es ein ETS-Projekt mit Gruppenadressen und Datenpunkttypen. Importiere es zuerst.'**
  String get haEmpty;

  /// HA-Konfiguration: wohin die Datei gehört
  ///
  /// In de, this message translates to:
  /// **'In Home Assistant als knx.yaml in den Konfigurationsordner legen (neben configuration.yaml) und dort einbinden:'**
  String get haWhere;

  /// HA-Konfiguration: Hinweis im Add-on
  ///
  /// In de, this message translates to:
  /// **'Im Add-on: Datei als /homeassistant/knx.yaml speichern (im File-Editor bzw. Studio Code Server unter „config“), in configuration.yaml einbinden und Home Assistant neu starten. Steht dort schon ein Abschnitt „knx:“, die Einträge dort einfügen statt einzubinden.'**
  String get haWhereAddon;

  /// HA-Konfiguration: Kennzahl
  ///
  /// In de, this message translates to:
  /// **'Entitäten'**
  String get haEntities;

  /// HA-Konfiguration: Kennzahl unsichere
  ///
  /// In de, this message translates to:
  /// **'Prüfen'**
  String get haUncertain;

  /// HA-Konfiguration: Filter Typen
  ///
  /// In de, this message translates to:
  /// **'Typen'**
  String get haTypes;

  /// HA-Konfiguration: Filter Räume
  ///
  /// In de, this message translates to:
  /// **'Räume'**
  String get haRooms;

  /// HA-Konfiguration: alle Räume
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get haAllRooms;

  /// HA-Konfiguration: Entität ohne Raum
  ///
  /// In de, this message translates to:
  /// **'Ohne Raum'**
  String get haNoRoom;

  /// HA-Konfiguration: Filter
  ///
  /// In de, this message translates to:
  /// **'Nur zu prüfende'**
  String get haOnlyUncertain;

  /// HA-Konfiguration: Vorschau
  ///
  /// In de, this message translates to:
  /// **'Vorschau der Datei'**
  String get haPreview;

  /// HA-Konfiguration: Kopieren
  ///
  /// In de, this message translates to:
  /// **'YAML kopieren'**
  String get haCopy;

  /// HA-Konfiguration: kopiert
  ///
  /// In de, this message translates to:
  /// **'Konfiguration kopiert'**
  String get haCopied;

  /// HA-YAML: Kopfkommentar, wenn Geräte enthalten sind
  ///
  /// In de, this message translates to:
  /// **'Geräte (device): den Bereich weist du in Home Assistant unter Einstellungen › Geräte zu.'**
  String get haYamlDevices;

  /// HA-Konfiguration: Abschnitt Gerätevorschläge
  ///
  /// In de, this message translates to:
  /// **'Geräte'**
  String get haDevices;

  /// HA-Konfiguration: Erklärung Gerätevorschläge
  ///
  /// In de, this message translates to:
  /// **'Diese Entitäten gehören erkennbar zusammen. Übernimmst du einen Vorschlag, fasst Home Assistant sie zu einem Gerät zusammen – etwa für Dashboards nach Geräten. Ohne dein Zutun bleibt alles einzeln.'**
  String get haDevicesExplain;

  /// HA-Konfiguration: alle Gerätevorschläge übernehmen
  ///
  /// In de, this message translates to:
  /// **'Alle übernehmen'**
  String get haDevicesAll;

  /// HA-Konfiguration: keine Gerätevorschläge übernehmen
  ///
  /// In de, this message translates to:
  /// **'Keine'**
  String get haDevicesNone;

  /// HA-Konfiguration: Gerät aus dem Namensschema
  ///
  /// In de, this message translates to:
  /// **'erkannt am Namen'**
  String get haDeviceFromNames;

  /// HA-Konfiguration: Gerät aus der ETS-Topologie
  ///
  /// In de, this message translates to:
  /// **'sendet alles: {device} ({address})'**
  String haDeviceFromBus(String device, String address);

  /// HA-Konfiguration: Entität gehört zu übernommenem Gerät
  ///
  /// In de, this message translates to:
  /// **'Gerät: {device}'**
  String haDeviceOf(String device);

  /// HA-Konfiguration: Teilen
  ///
  /// In de, this message translates to:
  /// **'knx.yaml teilen'**
  String get haShare;

  /// HA-Plattform
  ///
  /// In de, this message translates to:
  /// **'Licht'**
  String get haPlatformLight;

  /// HA-Plattform
  ///
  /// In de, this message translates to:
  /// **'Behang'**
  String get haPlatformCover;

  /// HA-Plattform
  ///
  /// In de, this message translates to:
  /// **'Raumregler'**
  String get haPlatformClimate;

  /// HA-Plattform
  ///
  /// In de, this message translates to:
  /// **'Schalter'**
  String get haPlatformSwitch;

  /// HA-Plattform binary_sensor
  ///
  /// In de, this message translates to:
  /// **'Meldung'**
  String get haPlatformBinarySensor;

  /// HA-Plattform sensor
  ///
  /// In de, this message translates to:
  /// **'Messwert'**
  String get haPlatformSensor;

  /// HA: Grund zum Prüfen
  ///
  /// In de, this message translates to:
  /// **'ohne Datenpunkttyp, nach Namen zugeordnet'**
  String get haDoubtNoDpt;

  /// HA: Grund zum Prüfen
  ///
  /// In de, this message translates to:
  /// **'keine Rückmeldung gefunden'**
  String get haDoubtNoState;

  /// HA: Grund zum Prüfen
  ///
  /// In de, this message translates to:
  /// **'Licht oder Verbraucher? Als Schalter angelegt'**
  String get haDoubtLightOrSwitch;

  /// HA: Grund zum Prüfen
  ///
  /// In de, this message translates to:
  /// **'mehrere Adressen passen, die erste ist eingetragen'**
  String get haDoubtAmbiguous;

  /// HA: Grund zum Prüfen
  ///
  /// In de, this message translates to:
  /// **'Sollwert ohne eigene Rückmeldung'**
  String get haDoubtTargetFromCommand;

  /// HA: Grund zum Prüfen
  ///
  /// In de, this message translates to:
  /// **'nur Haupttyp des DPT bekannt'**
  String get haDoubtTypeGuessed;

  /// HA-YAML: Kopfzeile (Kommentar)
  ///
  /// In de, this message translates to:
  /// **'Busclear {version} – KNX-Integration für Home Assistant, Projekt „{project}“, {date}'**
  String haYamlHeader(String version, String project, String date);

  /// HA-YAML: Kommentar
  ///
  /// In de, this message translates to:
  /// **'Einbinden in configuration.yaml mit:  knx: !include knx.yaml'**
  String get haYamlInclude;

  /// HA-YAML: Kommentar
  ///
  /// In de, this message translates to:
  /// **'Schlüssel nach home-assistant.io/integrations/knx – Einträge mit „Prüfen“ vor dem Einsatz ansehen.'**
  String get haYamlSchema;

  /// HA-YAML: Kommentar über unsicheren Einträgen
  ///
  /// In de, this message translates to:
  /// **'Prüfen: {reasons}'**
  String haYamlCheck(String reasons);

  /// HA: Grund zum Prüfen
  ///
  /// In de, this message translates to:
  /// **'nur Helligkeit, kein Schaltobjekt – Home Assistant braucht „address“, Eintrag auskommentiert'**
  String get haDoubtNoSwitch;

  /// Ursachenkette: Titel
  ///
  /// In de, this message translates to:
  /// **'Ursachenkette'**
  String get chainTitle;

  /// Ursachenkette gesperrt: Knopf öffnet die Bezahlseite
  ///
  /// In de, this message translates to:
  /// **'Ursachenkette zeigen'**
  String get chainLocked;

  /// Ursachenkette: Szene
  ///
  /// In de, this message translates to:
  /// **'Szene „{name}“'**
  String chainKindScene(String name);

  /// Ursachenkette: Zentralfunktion
  ///
  /// In de, this message translates to:
  /// **'Zentralbefehl „{name}“'**
  String chainKindCentral(String name);

  /// Ursachenkette: Satzanfang
  ///
  /// In de, this message translates to:
  /// **'{what} kam von {sender}'**
  String chainFrom(String what, String sender);

  /// Ursachenkette: mit Auslöser
  ///
  /// In de, this message translates to:
  /// **'{sentence} – {time} nach „{cause}“'**
  String chainAfterCause(String sentence, String time, String cause);

  /// Ursachenkette: Reaktionen
  ///
  /// In de, this message translates to:
  /// **'{time} später {count, plural, =1{meldete 1 Gerät zurück} other{meldeten {count} Geräte zurück}}'**
  String chainReactions(String time, int count);

  /// Ursachenkette: keine Reaktion
  ///
  /// In de, this message translates to:
  /// **'binnen {time} reagierte kein Gerät'**
  String chainNoReaction(String time);

  /// Ursachenkette: nichts im Umfeld
  ///
  /// In de, this message translates to:
  /// **'Davor und danach war es ruhig auf dem Bus.'**
  String get chainQuiet;

  /// Ursachenkette: Zeile des betrachteten Telegramms
  ///
  /// In de, this message translates to:
  /// **'dieses'**
  String get chainThis;

  /// Ursachenkette: Rolle
  ///
  /// In de, this message translates to:
  /// **'Auslöser'**
  String get chainRoleCause;

  /// Ursachenkette: Rolle
  ///
  /// In de, this message translates to:
  /// **'Rückmeldung'**
  String get chainRoleFeedback;

  /// Ursachenkette: Rolle (Logik, Szene)
  ///
  /// In de, this message translates to:
  /// **'Folge'**
  String get chainRoleFollowUp;

  /// Ursachenkette: Rolle ohne Zusammenhang (innerhalb 1,5 s davor bis 2 s danach; der Abstand steht daneben)
  ///
  /// In de, this message translates to:
  /// **'Zeitnah, ohne Bezug'**
  String get chainRoleCoincident;

  /// Reaktionszeiten: Titel
  ///
  /// In de, this message translates to:
  /// **'Reaktionszeiten'**
  String get reactTitle;

  /// Menü: Untertitel Reaktionszeiten
  ///
  /// In de, this message translates to:
  /// **'Wie schnell melden Aktoren nach einem Befehl zurück?'**
  String get reactTool;

  /// Reaktionszeiten: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Je Kanal die Zeit vom Schreibbefehl bis zur ersten Rückmeldung (bis 3 s), aus dem aktuellen Mitschnitt. Üblich sind 50–300 ms; deutlich mehr deutet auf einen ausgelasteten Bus, Koppler mit Filtern oder eine träge Logik hin.'**
  String get reactExplain;

  /// Reaktionszeiten: leer
  ///
  /// In de, this message translates to:
  /// **'Noch keine Messung: Schalte oder fahre etwas, dessen Rückmeldung im Projekt steht.'**
  String get reactEmpty;

  /// Reaktionszeiten: ohne Projekt
  ///
  /// In de, this message translates to:
  /// **'Ohne ETS-Projekt lässt sich Befehl und Rückmeldung nicht zuordnen.'**
  String get reactNoProject;

  /// Reaktionszeiten: Kennung
  ///
  /// In de, this message translates to:
  /// **'Kanäle'**
  String get reactChannels;

  /// Reaktionszeiten: Zeile
  ///
  /// In de, this message translates to:
  /// **'Median {median} · 90 % {p90} · max. {max} · {count}×'**
  String reactLine(String median, String p90, String max, int count);

  /// Reaktionszeiten: fehlende Rückmeldungen
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Befehl ohne Rückmeldung} other{{count} Befehle ohne Rückmeldung}}'**
  String reactMissing(int count);

  /// Inventar: Titel
  ///
  /// In de, this message translates to:
  /// **'Geräteinventar'**
  String get invTitle;

  /// Inventar: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Fragt Adresse für Adresse ab, welche Geräte auf der Linie antworten, und liest Hersteller, Bestellnummer, Seriennummer, Firmware und Applikation – ohne ETS und nur lesend, mit Pausen, damit der Bus frei bleibt. Mit Projekt: Abgleich, was fehlt oder getauscht wurde. Dauert je nach Bereich einige Minuten.'**
  String get invExplain;

  /// Inventar: Knopf
  ///
  /// In de, this message translates to:
  /// **'Inventar starten'**
  String get invStart;

  /// Inventar: Kennzahl
  ///
  /// In de, this message translates to:
  /// **'Gefunden'**
  String get invFound;

  /// Inventar: Status
  ///
  /// In de, this message translates to:
  /// **'Passt zum Projekt'**
  String get invMatch;

  /// Inventar: Status
  ///
  /// In de, this message translates to:
  /// **'Seriennummer anders'**
  String get invSerialMismatch;

  /// Inventar: Status
  ///
  /// In de, this message translates to:
  /// **'Nicht im Projekt'**
  String get invNotInProject;

  /// Inventar: Status
  ///
  /// In de, this message translates to:
  /// **'Tunneladresse'**
  String get invTunnel;

  /// Inventar: Status (im Projekt, am Bus nicht gefunden)
  ///
  /// In de, this message translates to:
  /// **'Antwortet nicht'**
  String get invMissing;

  /// Inventar: Status
  ///
  /// In de, this message translates to:
  /// **'Unklar (Gateway bestätigt nicht)'**
  String get invUnknown;

  /// Inventar: CSV teilen
  ///
  /// In de, this message translates to:
  /// **'Als Tabelle teilen'**
  String get invShare;

  /// Inventar: Dateiname
  ///
  /// In de, this message translates to:
  /// **'KNX-Geräteinventar'**
  String get invFileName;

  /// Sicherheits-Check: Titel
  ///
  /// In de, this message translates to:
  /// **'Sicherheits-Check'**
  String get secTitle;

  /// Menü: Untertitel Sicherheits-Check
  ///
  /// In de, this message translates to:
  /// **'Secure-Nutzung und fremde Absender prüfen'**
  String get secTool;

  /// Sicherheits-Check: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Ein ruhiger Blick auf die Sicherheit der Anlage: Wie verbindet sich die App, wie viel ist mit Data Secure geschützt, und senden Geräte, die nicht im Projekt stehen? Die Hinweise sind Empfehlungen – viele Anlagen laufen jahrelang ohne Secure, solange der Bus nicht von außen erreichbar ist.'**
  String get secExplain;

  /// Sicherheits-Check: Kennzahl
  ///
  /// In de, this message translates to:
  /// **'Verbindung'**
  String get secMetricLink;

  /// Sicherheits-Check: Kennzahl
  ///
  /// In de, this message translates to:
  /// **'Gateway'**
  String get secMetricGateway;

  /// Sicherheits-Check: Kennzahl
  ///
  /// In de, this message translates to:
  /// **'Secure im Projekt'**
  String get secMetricProject;

  /// Sicherheits-Check: Kennzahl
  ///
  /// In de, this message translates to:
  /// **'Secure im Verkehr'**
  String get secMetricSeen;

  /// Sicherheits-Check: Gateway
  ///
  /// In de, this message translates to:
  /// **'kann Secure'**
  String get secGatewaySecure;

  /// Sicherheits-Check: Gateway
  ///
  /// In de, this message translates to:
  /// **'ohne Secure'**
  String get secGatewayPlain;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Verbindung verschlüsselt'**
  String get secLinkSecureTitle;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Die App spricht über KNX IP Secure mit dem Gateway. Wer im Netz mitliest, sieht keine Telegramme und kann keine einschleusen.'**
  String get secLinkSecureText;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Direkt am Bus'**
  String get secLinkDirectTitle;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Die Box hängt mit dem KNX-HAT direkt am Bus; zwischen App und Bus liegt kein KNX-IP-Weg.'**
  String get secLinkDirectText;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Gateway kann Secure – genutzt wird es nicht'**
  String get secLinkPlainCouldTitle;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Routing ohne Secure, obwohl das Gerät es kann'**
  String get secLinkRoutingCouldTitle;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Die Verbindung läuft unverschlüsselt. Im Heimnetz ist das üblich; wer das Netz mit Gästen, Kameras oder IoT-Geräten teilt, sollte IP Secure in der ETS aktivieren und mit dem Keyring in der App verbinden.'**
  String get secLinkPlainCouldText;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Tunnel ohne Verschlüsselung'**
  String get secLinkPlainTitle;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Routing ohne Verschlüsselung'**
  String get secLinkRoutingTitle;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Ob das Gateway Secure kann, hat es (noch) nicht mitgeteilt. Unverschlüsselt ist im eigenen Netz in Ordnung, solange Port 3671 nicht aus dem Internet erreichbar ist.'**
  String get secLinkPlainText;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Das Gateway bietet kein IP Secure an. Halte es in einem Netz, in dem nur vertrauenswürdige Geräte hängen, und gib Port 3671 nie ins Internet frei.'**
  String get secLinkPlainNoSecureText;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Verbindungsweg nicht bekannt'**
  String get secLinkUnknownTitle;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Die App hängt an Home Assistant; wie dort mit dem Bus verbunden wird, sieht sie nicht.'**
  String get secLinkUnknownText;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Kein Keyring geladen'**
  String get secDataNoKeyringTitle;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Ohne Keyring lässt sich nicht sagen, welche Gruppenadressen mit Data Secure geschützt sind. Bisher kam kein gesichertes Telegramm vorbei.'**
  String get secDataNoKeyringText;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Telegramm war mit Data Secure gesichert} other{{count} Telegramme waren mit Data Secure gesichert}} – lade den Keyring aus der ETS, um sie zu lesen.'**
  String secDataNoKeyringSeen(int count);

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Keine Data-Secure-Adressen'**
  String get secDataNoneTitle;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Der Keyring enthält keine Schlüssel für Gruppenadressen. Für Türöffner, Alarm oder Zutritt lohnt Data Secure – für Licht und Jalousien ist es selten nötig.'**
  String get secDataNoneText;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Data Secure in Gebrauch'**
  String get secDataTitle;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'{project} von {groups} Gruppenadressen im Projekt sind gesichert; im Verkehr waren es bisher {seen} von {seenAll}.'**
  String secDataText(int project, int groups, int seen, int seenAll);

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Gesicherte Telegramme ohne Schlüssel'**
  String get secWithoutKeyTitle;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Telegramm} other{{count} Telegramme}} ließen sich nicht entschlüsseln. Meist ist der Keyring älter als das Projekt – neu aus der ETS exportieren.'**
  String secWithoutKeyText(int count);

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Ungültige gesicherte Telegramme'**
  String get secRejectedTitle;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Telegramm} other{{count} Telegramme}} hatten eine falsche Prüfsumme oder einen alten Zähler. Einzelne kommen nach einem Neustart vor; häufen sie sich, lohnt ein Blick, wer sie sendet.'**
  String secRejectedText(int count);

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Absender nicht prüfbar'**
  String get secForeignNoProjectTitle;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Für den Abgleich der Absender braucht es ein .knxproj mit Topologie.'**
  String get secForeignNoProjectText;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Alle Absender stehen im Projekt'**
  String get secForeignNoneTitle;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Jedes Telegramm im Mitschnitt kam von einem Gerät, das die ETS kennt.'**
  String get secForeignNoneText;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Absender nicht im Projekt} other{{count} Absender nicht im Projekt}}'**
  String secForeignTitle(int count);

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Meist harmlos: Visualisierungen, Logikmodule oder Tunnel anderer Apps. Unbekannte Adressen lassen sich in der Diagnose prüfen; ein Gerät, das niemand kennt, sollte man finden.'**
  String get secForeignText;

  /// Sicherheits-Check: Liste
  ///
  /// In de, this message translates to:
  /// **'Fremde Absender'**
  String get secForeignList;

  /// Sicherheits-Check: Zeile fremder Absender
  ///
  /// In de, this message translates to:
  /// **'{count}× · {groups}'**
  String secForeignRow(int count, String groups);

  /// Forenpaket: Titel
  ///
  /// In de, this message translates to:
  /// **'Für das Forum'**
  String get forumTitle;

  /// Forenpaket: Erklärung
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Telegramm} other{{count} Telegramme}} als Text zum Einfügen ins KNX-User-Forum. IP-Adressen, Hostnamen, Seriennummern, Passwörter und Schlüssel sind nie dabei.'**
  String forumExplain(int count);

  /// Forenpaket: Schalter
  ///
  /// In de, this message translates to:
  /// **'Namen ersetzen'**
  String get forumPseudonymize;

  /// Forenpaket: Schalter-Erklärung
  ///
  /// In de, this message translates to:
  /// **'Gruppenadressen heißen „GA 1“, Geräte tragen nur den Produktnamen.'**
  String get forumPseudonymizeHint;

  /// Forenpaket: Kopieren
  ///
  /// In de, this message translates to:
  /// **'In die Zwischenablage'**
  String get forumCopy;

  /// Forenpaket: kopiert
  ///
  /// In de, this message translates to:
  /// **'Text fürs Forum kopiert'**
  String get forumCopied;

  /// Forenpaket: Vorschau
  ///
  /// In de, this message translates to:
  /// **'Vorschau'**
  String get forumPreview;

  /// Forenpaket: Überschrift im Text
  ///
  /// In de, this message translates to:
  /// **'Mitschnitt aus Busclear'**
  String get forumHeading;

  /// Forenpaket: Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Telegramme'**
  String get forumTelegrams;

  /// Forenpaket: Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Gruppenadressen'**
  String get forumGroups;

  /// Forenpaket: Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Geräte'**
  String get forumDevices;

  /// Forenpaket: Spalte Gruppenadresse
  ///
  /// In de, this message translates to:
  /// **'GA'**
  String get forumColumnGroup;

  /// Forenpaket: eigener Tunnel
  ///
  /// In de, this message translates to:
  /// **'diese App'**
  String get forumOwn;

  /// Forenpaket: DPT unbekannt
  ///
  /// In de, this message translates to:
  /// **'DPT ?'**
  String get forumNoDpt;

  /// Forenpaket: Ersatzname
  ///
  /// In de, this message translates to:
  /// **'GA {n}'**
  String forumPseudoGroup(int n);

  /// Forenpaket: Ersatzname
  ///
  /// In de, this message translates to:
  /// **'Gerät {n}'**
  String forumPseudoDevice(int n);

  /// Forenpaket: Version
  ///
  /// In de, this message translates to:
  /// **'Busclear {version}'**
  String forumMetaApp(String version);

  /// Forenpaket: Verbindungsart
  ///
  /// In de, this message translates to:
  /// **'Verbindung: {kind}'**
  String forumMetaConnection(String kind);

  /// Forenpaket: Zeitraum
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Telegramm} other{{count} Telegramme}} am {date}, {from}–{to}'**
  String forumMetaRange(int count, String date, String from, String to);

  /// Forenpaket: gekürzt
  ///
  /// In de, this message translates to:
  /// **'gekürzt auf die ersten {count}'**
  String forumMetaShortened(int count);

  /// Export/PDF title: tasks to do in the ETS project.
  ///
  /// In de, this message translates to:
  /// **'Aufgaben für die ETS'**
  String get etsTasks;

  /// Project check: explanation of the ETS tasks export.
  ///
  /// In de, this message translates to:
  /// **'Je Gerät eine Seite mit Zeichnung, Kanälen und Aufgaben zum Abhaken; geänderte Datentypen als ETS-Import.'**
  String get etsTasksHint;

  /// ETS tasks export: nothing to do.
  ///
  /// In de, this message translates to:
  /// **'Keine Aufgaben: Das Projekt passt zu allen Prüfungen.'**
  String get etsTasksNone;

  /// Progress while the ETS tasks export is built.
  ///
  /// In de, this message translates to:
  /// **'Aufgaben werden erstellt …'**
  String get etsTasksBuilding;

  /// Progress: rendering the drawing of a device.
  ///
  /// In de, this message translates to:
  /// **'Zeichne {device} …'**
  String etsTasksDrawing(String device);

  /// ETS tasks PDF: how to use it.
  ///
  /// In de, this message translates to:
  /// **'Je Gerät eine Seite: die Zeichnung mit den Kanälen, die Aufgaben zum Abhaken und die Kanalzuordnung aus dem Projekt. Danach das Projekt neu in Busclear importieren; der Projekt-Abgleich zeigt, was erledigt ist.'**
  String get etsHowTo;

  /// ETS tasks PDF: summary label, devices with tasks.
  ///
  /// In de, this message translates to:
  /// **'Geräte'**
  String get etsSummaryDevices;

  /// ETS tasks PDF: summary label.
  ///
  /// In de, this message translates to:
  /// **'Aufgaben'**
  String get etsSummaryTasks;

  /// ETS tasks PDF: summary label for hints (often intended).
  ///
  /// In de, this message translates to:
  /// **'Hinweise'**
  String get etsSummaryHints;

  /// ETS tasks PDF: heading of the device overview table.
  ///
  /// In de, this message translates to:
  /// **'Übersicht'**
  String get etsOverview;

  /// ETS tasks PDF: column, data type in the project.
  ///
  /// In de, this message translates to:
  /// **'Im Projekt'**
  String get etsInProject;

  /// ETS tasks PDF: column, new data type.
  ///
  /// In de, this message translates to:
  /// **'Neu'**
  String get etsNew;

  /// ETS tasks PDF: note about the attached XML import file.
  ///
  /// In de, this message translates to:
  /// **'Liegt als Datei für den Gruppenadress-Import der ETS bei (Gruppenadressen › Importieren): Datentypen, Namen und neue Adressen. Vorschau: erst an einer Kopie des Projekts testen.'**
  String get etsImportNote;

  /// ETS tasks PDF: label above a device page.
  ///
  /// In de, this message translates to:
  /// **'Gerät {address}'**
  String etsDevice(String address);

  /// ETS tasks PDF: heading of the task list on a device page.
  ///
  /// In de, this message translates to:
  /// **'Aufgaben'**
  String get etsTasksOnPage;

  /// ETS tasks PDF: heading of the channel table.
  ///
  /// In de, this message translates to:
  /// **'Kanalzuordnung'**
  String get etsChannels;

  /// ETS tasks PDF: table column.
  ///
  /// In de, this message translates to:
  /// **'Kanal'**
  String get etsColumnChannel;

  /// ETS tasks PDF: table column.
  ///
  /// In de, this message translates to:
  /// **'Objekt'**
  String get etsColumnObject;

  /// ETS tasks PDF: table column.
  ///
  /// In de, this message translates to:
  /// **'Gruppenadresse'**
  String get etsColumnGroup;

  /// ETS tasks PDF: table column.
  ///
  /// In de, this message translates to:
  /// **'Flags'**
  String get etsColumnFlags;

  /// ETS tasks PDF: communication object with its number.
  ///
  /// In de, this message translates to:
  /// **'Objekt {number}'**
  String etsObject(int number);

  /// ETS tasks PDF: other devices sending on the same address.
  ///
  /// In de, this message translates to:
  /// **'sendet auch: {devices}'**
  String etsAlsoSends(String devices);

  /// ETS tasks PDF: device without linked objects.
  ///
  /// In de, this message translates to:
  /// **'Keine verknüpften Objekte'**
  String get etsNoChannels;

  /// ETS task: what to do for a changed data type.
  ///
  /// In de, this message translates to:
  /// **'Datentyp der Gruppenadresse auf {dpt} setzen.'**
  String etsTodoDpt(String dpt);

  /// ETS task: what to do for a status address without transmit flag.
  ///
  /// In de, this message translates to:
  /// **'Ü-Flag am Objekt setzen, das den Status liefert (meist der Aktorkanal).'**
  String get etsTodoStatusNoTransmit;

  /// ETS task: what to do for a status address without read flag.
  ///
  /// In de, this message translates to:
  /// **'L-Flag am Objekt setzen, das den Status liefert.'**
  String get etsTodoReadNoReadFlag;

  /// ETS task: what to do for an object without communication flag.
  ///
  /// In de, this message translates to:
  /// **'K-Flag setzen oder die Gruppenadresse vom Objekt lösen.'**
  String get etsTodoNoComm;

  /// ETS task: what to do for several senders on one address.
  ///
  /// In de, this message translates to:
  /// **'Prüfen, ob gewollt; sonst nur ein Objekt senden lassen oder eine eigene Adresse vergeben.'**
  String get etsTodoMultipleSenders;

  /// ETS task: what to do for a device without links.
  ///
  /// In de, this message translates to:
  /// **'Gruppenadressen verknüpfen oder das Gerät aus dem Projekt nehmen.'**
  String get etsTodoNoLinks;

  /// File name of the attached ETS group address import.
  ///
  /// In de, this message translates to:
  /// **'Gruppenadressen ETS-Import (Vorschau)'**
  String get etsImportFile;

  /// ETS tasks PDF: tag for a hint (often intended).
  ///
  /// In de, this message translates to:
  /// **'Hinweis'**
  String get etsHint;

  /// ETS task title (singular).
  ///
  /// In de, this message translates to:
  /// **'Objekt ohne K-Flag'**
  String get etsTitleNoComm;

  /// ETS task title (singular).
  ///
  /// In de, this message translates to:
  /// **'Gerät ohne Verknüpfung'**
  String get etsTitleNoLinks;

  /// ETS tasks PDF: number of tasks of a device.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Aufgabe} other{{count} Aufgaben}}'**
  String etsTaskCount(int count);

  /// ETS tasks PDF: number of hints of a device.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Hinweis} other{{count} Hinweise}}'**
  String etsHintCount(int count);

  /// ETS-Aufgaben: Zahl der Adressen im Gruppenadress-Import
  ///
  /// In de, this message translates to:
  /// **'Für den Import'**
  String get etsSummaryImport;

  /// ETS-Aufgaben: Abschnitt mit Namen, Datentypen und neuen Adressen für den Import
  ///
  /// In de, this message translates to:
  /// **'Gruppenadress-Import'**
  String get etsImportSection;

  /// ETS-Aufgaben: Abschnitt mit Aufgaben an Gruppenadressen, von Hand
  ///
  /// In de, this message translates to:
  /// **'Gruppenadressen'**
  String get etsGroupsSection;

  /// ETS-Aufgaben: Abschnitt mit Aufgaben am Projekt (Linien)
  ///
  /// In de, this message translates to:
  /// **'Projekt'**
  String get etsProjectSection;

  /// ETS-Aufgabe: angelernter Name für eine unbenannte Adresse
  ///
  /// In de, this message translates to:
  /// **'Name aus dem Anlernen'**
  String get etsTitleLearnedName;

  /// ETS-Aufgabe: angelernte Adresse fehlt im Projekt
  ///
  /// In de, this message translates to:
  /// **'Neue Adresse aus dem Anlernen'**
  String get etsTitleLearnedNew;

  /// ETS-Aufgabe: Adresse ohne Namen
  ///
  /// In de, this message translates to:
  /// **'Ohne Namen'**
  String get etsTitleNoName;

  /// ETS-Aufgabe: Adresse ohne Datentyp
  ///
  /// In de, this message translates to:
  /// **'Ohne Datentyp'**
  String get etsTitleNoDpt;

  /// ETS-Aufgabe aus dem Inventar: Gerät fehlt im Projekt
  ///
  /// In de, this message translates to:
  /// **'Am Bus, nicht im Projekt'**
  String get etsTitleNotInProject;

  /// ETS-Aufgabe aus dem Inventar: Seriennummer anders als im Projekt
  ///
  /// In de, this message translates to:
  /// **'Seriennummer weicht ab'**
  String get etsTitleSerial;

  /// ETS-Hinweis aus dem Inventar: Projektgerät hat nicht geantwortet
  ///
  /// In de, this message translates to:
  /// **'Antwortet nicht'**
  String get etsTitleMissing;

  /// ETS-Aufgabe: angelernten Namen übernehmen
  ///
  /// In de, this message translates to:
  /// **'Namen „{name}“ übernehmen – erledigt der Gruppenadress-Import.'**
  String etsTodoLearnedName(String name);

  /// ETS-Aufgabe: angelernte Adresse anlegen
  ///
  /// In de, this message translates to:
  /// **'Adresse „{name}“ anlegen – erledigt der Gruppenadress-Import; danach mit den Objekten verknüpfen.'**
  String etsTodoLearnedNew(String name);

  /// ETS-Aufgabe: Namen vergeben
  ///
  /// In de, this message translates to:
  /// **'Sprechenden Namen vergeben: Etage, Raum, Objekt, Funktion.'**
  String get etsTodoNoName;

  /// ETS-Aufgabe: Datentyp setzen
  ///
  /// In de, this message translates to:
  /// **'Datentyp passend zum verknüpften Objekt setzen – oder in der App festlegen, dann geht er mit dem Import.'**
  String get etsTodoNoDpt;

  /// ETS-Aufgabe: Adresse ohne Sender
  ///
  /// In de, this message translates to:
  /// **'Sender verknüpfen oder Visualisierung, Logik bzw. Panel als Platzhalter-Gerät mit dieser Adresse anlegen.'**
  String get etsTodoWithoutSender;

  /// ETS-Aufgabe: Adresse ohne Empfänger
  ///
  /// In de, this message translates to:
  /// **'Empfangendes Objekt (K- und S-Flag) verknüpfen oder die Adresse löschen, wenn sie nicht gebraucht wird.'**
  String get etsTodoWithoutReceiver;

  /// ETS-Aufgabe: Hauptgruppe 14/15
  ///
  /// In de, this message translates to:
  /// **'Für linienübergreifende Adressen in Hauptgruppe 0–13 verschieben oder die Filtertabellen der Koppler prüfen.'**
  String get etsTodoMainGroup1415;

  /// ETS-Aufgabe: L-Flag mehrfach
  ///
  /// In de, this message translates to:
  /// **'L-Flag nur an dem Objekt lassen, das den Zustand führt, an den übrigen entfernen.'**
  String get etsTodoMultipleReadAnswers;

  /// ETS-Aufgabe: Gerät aus dem Inventar fehlt im Projekt
  ///
  /// In de, this message translates to:
  /// **'Gerät im Projekt anlegen (Topologie, physikalische Adresse) oder klären, woher es stammt.'**
  String get etsTodoNotInProject;

  /// ETS-Aufgabe: Seriennummer weicht ab
  ///
  /// In de, this message translates to:
  /// **'Gerät wurde vermutlich getauscht: Seriennummer {serial} im Projekt eintragen und Applikation neu laden.'**
  String etsTodoSerial(String serial);

  /// ETS-Hinweis: Gerät antwortet nicht
  ///
  /// In de, this message translates to:
  /// **'Prüfen, ob das Gerät angeschlossen und programmiert ist – beim Inventar hat es nicht geantwortet.'**
  String get etsTodoMissing;

  /// ETS-Hinweis: volle Linie
  ///
  /// In de, this message translates to:
  /// **'Linie {line} hat {count} Geräte: Reserve einplanen, bei Erweiterung neue Linie oder Linienverstärker.'**
  String etsTodoCrowdedLine(String line, int count);

  /// ETS-Aufgabe: Datentyp einer Adresse ändern
  ///
  /// In de, this message translates to:
  /// **'Datentyp'**
  String get etsTitleDpt;

  /// Titel, wenn Add-on oder Linux keine weitere Anlage erlauben
  ///
  /// In de, this message translates to:
  /// **'Eine Anlage'**
  String get planOneInstallationTitle;

  /// Erklärung im Home-Assistant-Add-on, auf der Box und unter Linux beim Anlegen einer zweiten Anlage
  ///
  /// In de, this message translates to:
  /// **'Hier gibt es eine Anlage. Mehrere Anlagen nebeneinander gehen in der App für iPhone, iPad, Android und Mac (Plus oder Pro).'**
  String get planOneInstallationHere;

  /// Tool subtitle for the fault hunt when the app runs in the Home Assistant add-on.
  ///
  /// In de, this message translates to:
  /// **'Sporadische Fehler über Tage fangen – im Add-on'**
  String get huntToolAddon;

  /// Fault hunt explanation in the Home Assistant add-on (no box).
  ///
  /// In de, this message translates to:
  /// **'Für Fehler, die nur manchmal auftreten: Das Add-on läuft rund um die Uhr, die Jagd fängt jeden Treffer eines Wächters mit zwei Minuten davor und einer danach. Am Ende siehst du, wer gesendet hat – oft ist es immer derselbe.'**
  String get huntExplainAddon;

  /// Fault hunt time window hint in the Home Assistant add-on.
  ///
  /// In de, this message translates to:
  /// **'z. B. nachts von 22 bis 6 Uhr (Uhrzeit von Home Assistant)'**
  String get huntOnlyWindowExplainAddon;

  /// Befund: security check in the demo house (no real connection).
  ///
  /// In de, this message translates to:
  /// **'Demo-Haus'**
  String get secLinkDemoTitle;

  /// Befund: security check in the demo house.
  ///
  /// In de, this message translates to:
  /// **'Im Demo-Haus gibt es keinen echten Bus. An deiner Anlage prüft der Check hier, wie die App mit dem Gateway verbunden ist – verschlüsselt oder nicht.'**
  String get secLinkDemoText;

  /// Add-on/box status line when server.json was unreadable and no backup helped; recording is stopped until the user connects again.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen der Daueraufzeichnung waren beschädigt – bitte einmal neu verbinden.'**
  String get addonConfigLost;

  /// Teach-in: address that sent in the same moment but is probably not the feedback of the pressed button; offered unchecked.
  ///
  /// In de, this message translates to:
  /// **'Auch gesehen'**
  String get learnRoleAlsoSeen;

  /// Project check in the demo house instead of the re-import hint (the demo project cannot be imported).
  ///
  /// In de, this message translates to:
  /// **'Das Demo-Haus hat keine Flags – an deiner Anlage liest der Abgleich sie aus dem ETS-Projekt'**
  String get checkDemoNoFlags;

  /// Teach-in: first ~15 s, background traffic is learned so it does not start events; shown with a progress bar.
  ///
  /// In de, this message translates to:
  /// **'Höre kurz mit, damit ich deinen Bus kenne … Bitte noch nichts drücken.'**
  String get learnWarmUp;

  /// Inventory status without a loaded project: device answered, nothing to compare against.
  ///
  /// In de, this message translates to:
  /// **'Gefunden'**
  String get invPresent;

  /// Inventory: manufacturer whose name is unknown (no project), e.g. „Hersteller 0x0083“.
  ///
  /// In de, this message translates to:
  /// **'Hersteller {id}'**
  String invManufacturerId(String id);

  /// Titel des Testtons vor der ersten Klangquittung
  ///
  /// In de, this message translates to:
  /// **'Gehört?'**
  String get ackTestTitle;

  /// Text des Testtons
  ///
  /// In de, this message translates to:
  /// **'Die App hat eben den Quittungston gespielt. Gehört? Dann kann’s losgehen.'**
  String get ackTestText;

  /// Hinweis, wenn der Testton nicht zu hören war
  ///
  /// In de, this message translates to:
  /// **'Nichts gehört? Lautstärke hochdrehen, Stummmodus ausschalten (iPhone: Schalter oder Kontrollzentrum) und Bluetooth-Kopfhörer prüfen. Dann noch einmal.'**
  String get ackTestNotHeard;

  /// Knopf: Testton war nicht zu hören
  ///
  /// In de, this message translates to:
  /// **'Nicht gehört'**
  String get ackTestNo;

  /// Knopf: Testton erneut spielen
  ///
  /// In de, this message translates to:
  /// **'Noch einmal'**
  String get ackTestAgain;

  /// Knopf: Testton gehört, Klangquittung starten
  ///
  /// In de, this message translates to:
  /// **'Gehört, los'**
  String get ackTestYes;

  /// Titel der Einstellungsseite für den Briefkopf
  ///
  /// In de, this message translates to:
  /// **'Firma'**
  String get companyTitle;

  /// Pro-Funktion in der Liste der Bezahlseite
  ///
  /// In de, this message translates to:
  /// **'Firmenbriefkopf auf allen PDFs'**
  String get companyFeature;

  /// Untertitel im Menü
  ///
  /// In de, this message translates to:
  /// **'Logo und Adresse für den Briefkopf der PDFs'**
  String get companyTool;

  /// Erklärung auf der Seite Firma
  ///
  /// In de, this message translates to:
  /// **'Diese Angaben stehen als Briefkopf auf allen PDFs. Sie gelten für alle Anlagen und bleiben auf diesem Gerät.'**
  String get companyExplain;

  /// Kennung über der Vorschau
  ///
  /// In de, this message translates to:
  /// **'Vorschau des Briefkopfs'**
  String get companyPreview;

  /// Platzhalter in der Vorschau
  ///
  /// In de, this message translates to:
  /// **'Ihr Firmenname'**
  String get companyPreviewEmpty;

  /// Kennung Logo
  ///
  /// In de, this message translates to:
  /// **'Logo'**
  String get companyLogo;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Logo wählen'**
  String get companyLogoPick;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Logo ersetzen'**
  String get companyLogoReplace;

  /// Hinweis unter dem Logo-Knopf
  ///
  /// In de, this message translates to:
  /// **'PNG, JPEG oder SVG. Das Bild wird automatisch verkleinert.'**
  String get companyLogoHint;

  /// Fehlermeldung beim Logo
  ///
  /// In de, this message translates to:
  /// **'Dieses Bild lässt sich nicht lesen. Bitte ein PNG oder JPEG versuchen.'**
  String get companyLogoFailed;

  /// Kennung über den Feldern
  ///
  /// In de, this message translates to:
  /// **'Angaben'**
  String get companyDetails;

  /// Abschnitt der Seite Firma über USt-IdNr., Eintragung und Techniker
  ///
  /// In de, this message translates to:
  /// **'Weitere Angaben'**
  String get companyMore;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Firmenname'**
  String get companyName;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Anschrift'**
  String get companyAddress;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Telefon'**
  String get companyPhone;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'E-Mail'**
  String get companyEmail;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Website'**
  String get companyWebsite;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'USt-IdNr. (optional)'**
  String get companyVatId;

  /// Feld, z. B. Handwerksrolle
  ///
  /// In de, this message translates to:
  /// **'Eintragung (optional)'**
  String get companyRegistration;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Techniker auf diesem Gerät'**
  String get companyTechnician;

  /// Bestätigung
  ///
  /// In de, this message translates to:
  /// **'Gespeichert.'**
  String get companySaved;

  /// Zeile im Briefkopf
  ///
  /// In de, this message translates to:
  /// **'Techniker: {name}'**
  String pdfTechnicianLine(String name);

  /// Gruppe im Menü
  ///
  /// In de, this message translates to:
  /// **'Dokumente & Kunden'**
  String get menuGroupDocuments;

  /// Titel
  ///
  /// In de, this message translates to:
  /// **'Servicebericht'**
  String get srTitle;

  /// Untertitel im Menü
  ///
  /// In de, this message translates to:
  /// **'Bericht für den Kunden aus Aufnahme, Kommentaren und Gesundheit'**
  String get srTool;

  /// Pro-Funktion auf der Bezahlseite
  ///
  /// In de, this message translates to:
  /// **'Servicebericht für den Kunden'**
  String get srFeature;

  /// Erklärung
  ///
  /// In de, this message translates to:
  /// **'Schreibe in einfachen Worten, was los war und was du getan hast. Aufnahme und Gesundheitsprüfung kommen als Beleg dazu. Nach dem Erstellen bleibt der Bericht unverändert gespeichert.'**
  String get srExplain;

  /// Titel im PDF
  ///
  /// In de, this message translates to:
  /// **'Servicebericht'**
  String get srPdfTitle;

  /// Kennung
  ///
  /// In de, this message translates to:
  /// **'Der Besuch'**
  String get srVisitSection;

  /// Feld und Abschnitt im PDF
  ///
  /// In de, this message translates to:
  /// **'Anlass des Besuchs'**
  String get srOccasion;

  /// Beispiel
  ///
  /// In de, this message translates to:
  /// **'z. B. Licht im Flur ging nachts von selbst an'**
  String get srOccasionHint;

  /// Feld und Abschnitt im PDF
  ///
  /// In de, this message translates to:
  /// **'Was wir beobachtet haben'**
  String get srObserved;

  /// Beispiel
  ///
  /// In de, this message translates to:
  /// **'Was war zu sehen, wann ist es passiert?'**
  String get srObservedHint;

  /// Feld und Abschnitt im PDF
  ///
  /// In de, this message translates to:
  /// **'Was wir getan haben'**
  String get srDone;

  /// Beispiel
  ///
  /// In de, this message translates to:
  /// **'z. B. Bewegungsmelder neu eingestellt'**
  String get srDoneHint;

  /// Feld und Abschnitt im PDF
  ///
  /// In de, this message translates to:
  /// **'Unsere Empfehlung'**
  String get srRecommendation;

  /// Beispiel
  ///
  /// In de, this message translates to:
  /// **'Was sollte als Nächstes passieren?'**
  String get srRecommendationHint;

  /// Kennung
  ///
  /// In de, this message translates to:
  /// **'Belege'**
  String get srEvidenceSection;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Aufnahme'**
  String get srRecording;

  /// Auswahl
  ///
  /// In de, this message translates to:
  /// **'Keine Aufnahme'**
  String get srRecordingNone;

  /// Schalter
  ///
  /// In de, this message translates to:
  /// **'Letzte Gesundheitsprüfung mitnehmen'**
  String get srUseHealth;

  /// Kennung
  ///
  /// In de, this message translates to:
  /// **'Unterschrift (optional)'**
  String get srSignatureOptional;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Unterschrieben – ändern'**
  String get srSigned;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Bericht erstellen und teilen'**
  String get srCreate;

  /// Kennung
  ///
  /// In de, this message translates to:
  /// **'Frühere Berichte'**
  String get srEarlier;

  /// Servicebericht: Art, Umschalter
  ///
  /// In de, this message translates to:
  /// **'Einsatz'**
  String get srKindVisit;

  /// Servicebericht: Art, Umschalter und Liste
  ///
  /// In de, this message translates to:
  /// **'Wartung'**
  String get srKindMaintenance;

  /// Servicebericht: Art in der Liste früherer Berichte
  ///
  /// In de, this message translates to:
  /// **'Rückmeldung'**
  String get srKindReply;

  /// Titel des PDFs einer Wartung
  ///
  /// In de, this message translates to:
  /// **'Wartungsbericht'**
  String get srMaintPdfTitle;

  /// Vorbelegung „Anlass“ bei einer Wartung
  ///
  /// In de, this message translates to:
  /// **'Regelmäßige Wartung der Anlage'**
  String get srMaintOccasionDefault;

  /// Wartung: Abschnitt im Formular und im PDF
  ///
  /// In de, this message translates to:
  /// **'Bei diesem Besuch geprüft'**
  String get srMaintChecklist;

  /// Wartung: fester Prüfpunkt
  ///
  /// In de, this message translates to:
  /// **'Verteiler und Geräte: Sichtprüfung'**
  String get srMaintCheckVisual;

  /// Wartung: fester Prüfpunkt
  ///
  /// In de, this message translates to:
  /// **'Spannungsversorgung der Anlage'**
  String get srMaintCheckSupply;

  /// Wartung: fester Prüfpunkt
  ///
  /// In de, this message translates to:
  /// **'Gesundheitsprüfung am Bus'**
  String get srMaintCheckHealth;

  /// Wartung: fester Prüfpunkt
  ///
  /// In de, this message translates to:
  /// **'Funktionen stichprobenartig getestet'**
  String get srMaintCheckFunctions;

  /// Wartung: fester Prüfpunkt
  ///
  /// In de, this message translates to:
  /// **'Projektstand und Sicherung aktuell'**
  String get srMaintCheckBackup;

  /// Servicebericht, Wartung: startet die Gesundheitsprüfung der App am Prüfpunkt
  ///
  /// In de, this message translates to:
  /// **'Jetzt prüfen'**
  String get srHealthRun;

  /// Servicebericht, Wartung: Gesundheitsprüfung läuft
  ///
  /// In de, this message translates to:
  /// **'Prüfung läuft …'**
  String get srHealthRunning;

  /// Servicebericht, Wartung: letzte Gesundheitsprüfung mit Zahl der Befunde
  ///
  /// In de, this message translates to:
  /// **'Zuletzt geprüft {when}: {count, plural, =0{keine Befunde} =1{1 Befund} other{{count} Befunde}}'**
  String srHealthLast(String when, int count);

  /// Servicebericht, Wartung: noch keine Gesundheitsprüfung
  ///
  /// In de, this message translates to:
  /// **'Noch nicht geprüft. Die Prüfung liest die Rückmeldungen wie im Werkzeug „Gesundheit“.'**
  String get srHealthNever;

  /// Servicebericht, Wartung: ohne Verbindung keine Gesundheitsprüfung
  ///
  /// In de, this message translates to:
  /// **'Zum Prüfen die Anlage verbinden und den Bericht aus dem Monitor öffnen.'**
  String get srHealthNeedsBus;

  /// Wartung: Ergebnis eines Prüfpunkts
  ///
  /// In de, this message translates to:
  /// **'In Ordnung'**
  String get srCheckOk;

  /// Wartung: Ergebnis eines Prüfpunkts
  ///
  /// In de, this message translates to:
  /// **'Auffällig'**
  String get srCheckAttention;

  /// Wartung: Ergebnis eines Prüfpunkts
  ///
  /// In de, this message translates to:
  /// **'Nicht geprüft'**
  String get srCheckUnchecked;

  /// Wartung: Hinweis im Formular, wenn es einen Vorgänger gibt
  ///
  /// In de, this message translates to:
  /// **'Aufbau und Vergleich: Wartungsbericht vom {date}.'**
  String srMaintPrevious(String date);

  /// Wartung: Hinweis im Formular ohne Vorgänger
  ///
  /// In de, this message translates to:
  /// **'Erster Wartungsbericht dieser Anlage: noch kein Vergleich.'**
  String get srMaintFirst;

  /// Wartungs-PDF: Abschnitt mit dem Vergleich
  ///
  /// In de, this message translates to:
  /// **'Seit dem letzten Besuch'**
  String get srSinceTitle;

  /// Wartungs-PDF: Einleitung des Vergleichs
  ///
  /// In de, this message translates to:
  /// **'Vergleich mit dem Wartungsbericht vom {date}. Verglichen wird nur, was in beiden Berichten enthalten ist.'**
  String srSinceIntro(String date);

  /// Wartungs-PDF: Hinweise, die es beim letzten Besuch nicht gab
  ///
  /// In de, this message translates to:
  /// **'Neu'**
  String get srSinceNew;

  /// Wartungs-PDF: Hinweise, die es nicht mehr gibt
  ///
  /// In de, this message translates to:
  /// **'Nicht mehr vorhanden'**
  String get srSinceGone;

  /// Wartungs-PDF: Hinweise, die es weiter gibt
  ///
  /// In de, this message translates to:
  /// **'Weiterhin vorhanden'**
  String get srSinceStill;

  /// Wartungs-PDF: Vergleich ohne Hinweise
  ///
  /// In de, this message translates to:
  /// **'Bei beiden Besuchen gab es keine Auffälligkeiten.'**
  String get srSinceNoFindings;

  /// Wartungs-PDF: ehrlicher Hinweis, wenn nichts vergleichbar ist
  ///
  /// In de, this message translates to:
  /// **'Die Hinweise der beiden Berichte lassen sich nicht vergleichen: Sie haben keine gemeinsame Grundlage (Messung, Gesundheitsprüfung, Sprache).'**
  String get srSinceNotComparable;

  /// Wartungs-PDF: Unterabschnitt
  ///
  /// In de, this message translates to:
  /// **'Gesundheitsprüfung damals und heute'**
  String get srSinceHealth;

  /// Wartungs-PDF: Zahl der Befunde je Einstufung
  ///
  /// In de, this message translates to:
  /// **'{fix} zu beheben, {watch} im Auge zu behalten'**
  String srSinceHealthCounts(int fix, int watch);

  /// Wartungs-PDF: Spalte des letzten Besuchs
  ///
  /// In de, this message translates to:
  /// **'Damals ({date})'**
  String srSinceThen(String date);

  /// Wartungs-PDF: Spalte dieses Besuchs
  ///
  /// In de, this message translates to:
  /// **'Heute'**
  String get srSinceNow;

  /// Titel der Seite und Art im Verlauf
  ///
  /// In de, this message translates to:
  /// **'Rückmeldung an den Kunden'**
  String get replyTitle;

  /// Rückmeldung: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Ein kurzer Stand für den Kunden nach seiner Störungsmeldung, in einfachen Worten und mit deinem Briefkopf. Adressen und Messwerte stehen nur drin, wenn du sie selbst hineinschreibst. Die Rückmeldung wird bei den Serviceberichten gespeichert.'**
  String get replyExplain;

  /// Titel des PDFs
  ///
  /// In de, this message translates to:
  /// **'Rückmeldung zu Ihrer Störungsmeldung'**
  String get replyPdfTitle;

  /// Rückmeldung: Feld im Formular
  ///
  /// In de, this message translates to:
  /// **'Was gemeldet wurde'**
  String get replyReportedLabel;

  /// Rückmeldung: Abschnitt im PDF
  ///
  /// In de, this message translates to:
  /// **'Was Sie gemeldet haben'**
  String get replyReported;

  /// Rückmeldung: Zeitpunkt der Meldung, Formular und PDF
  ///
  /// In de, this message translates to:
  /// **'Gemeldet am {date}'**
  String replyReportedOn(String date);

  /// Rückmeldung: Feld im Formular
  ///
  /// In de, this message translates to:
  /// **'Was festgestellt wurde'**
  String get replyFoundLabel;

  /// Rückmeldung: Abschnitt im PDF
  ///
  /// In de, this message translates to:
  /// **'Was wir festgestellt haben'**
  String get replyFound;

  /// Rückmeldung: Beispiel
  ///
  /// In de, this message translates to:
  /// **'z. B. Der Bewegungsmelder im Flur reagiert auf die warme Luft der Heizung.'**
  String get replyFoundHint;

  /// Rückmeldung: Feld und Abschnitt im PDF
  ///
  /// In de, this message translates to:
  /// **'Wie es weitergeht'**
  String get replyNext;

  /// Rückmeldung: Beispiel
  ///
  /// In de, this message translates to:
  /// **'z. B. Wir stellen den Melder am Donnerstag neu ein.'**
  String get replyNextHint;

  /// Rückmeldungs-PDF: Techniker
  ///
  /// In de, this message translates to:
  /// **'Ihr Ansprechpartner: {name}'**
  String replyContact(String name);

  /// Rückmeldungs-PDF: Schlusssatz
  ///
  /// In de, this message translates to:
  /// **'Bei Fragen melden Sie sich gern bei uns.'**
  String get replyClosing;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Rückmeldung erstellen und teilen'**
  String get replyCreate;

  /// Rückmeldung: Hinweis, solange beide Felder leer sind
  ///
  /// In de, this message translates to:
  /// **'Schreibe, was festgestellt wurde oder wie es weitergeht.'**
  String get replyMissing;

  /// Verlauf: Rückmeldung wurde gelöscht
  ///
  /// In de, this message translates to:
  /// **'Diese Rückmeldung ist nicht mehr gespeichert.'**
  String get replyGone;

  /// Ergebniszeile im PDF
  ///
  /// In de, this message translates to:
  /// **'Ergebnis: Es gibt keine offenen Auffälligkeiten.'**
  String get srResultGood;

  /// Ergebniszeile im PDF
  ///
  /// In de, this message translates to:
  /// **'Ergebnis: {count} Punkte sollten Sie im Blick behalten (siehe unten).'**
  String srResultAttention(int count);

  /// Abschnitt im PDF
  ///
  /// In de, this message translates to:
  /// **'Unsere Messung'**
  String get srMeasurement;

  /// Erklärung für Laien
  ///
  /// In de, this message translates to:
  /// **'Ab {start} haben wir {minutes} Minuten lang mitgeschrieben, was die Geräte Ihrer Anlage untereinander senden. Dabei waren es {count} Nachrichten.'**
  String srMeasurementText(String start, int minutes, int count);

  /// Abschnitt im PDF
  ///
  /// In de, this message translates to:
  /// **'Notizen zum Besuch'**
  String get srComments;

  /// Abschnitt im PDF
  ///
  /// In de, this message translates to:
  /// **'Was die Auswertung zeigt'**
  String get srFindings;

  /// Abschnitt im PDF
  ///
  /// In de, this message translates to:
  /// **'Gesundheitsprüfung vom {date}'**
  String srHealth(String date);

  /// Einstufung für Laien
  ///
  /// In de, this message translates to:
  /// **'Beheben'**
  String get srLevelFix;

  /// Einstufung für Laien
  ///
  /// In de, this message translates to:
  /// **'Beobachten'**
  String get srLevelWatch;

  /// Einstufung für Laien
  ///
  /// In de, this message translates to:
  /// **'Zur Info'**
  String get srLevelInfo;

  /// Satz über der Unterschrift
  ///
  /// In de, this message translates to:
  /// **'Der Kunde hat den Bericht erhalten und den Besuch bestätigt.'**
  String get srConfirmation;

  /// Titel
  ///
  /// In de, this message translates to:
  /// **'Kundenakte'**
  String get customerTitle;

  /// Untertitel im Menü
  ///
  /// In de, this message translates to:
  /// **'Anlagen, Kunden, Wartung und Besuche'**
  String get customerTool;

  /// Pro-Funktion auf der Bezahlseite
  ///
  /// In de, this message translates to:
  /// **'Anlagen als Kundenakte mit Besuchsverlauf'**
  String get customerFeature;

  /// Suchfeld
  ///
  /// In de, this message translates to:
  /// **'Kunde, Anschrift, Auftrag suchen'**
  String get customerSearch;

  /// Sortierung
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get customerSortName;

  /// Sortierung
  ///
  /// In de, this message translates to:
  /// **'Letzter Besuch'**
  String get customerSortVisit;

  /// Sortierung
  ///
  /// In de, this message translates to:
  /// **'Wartung'**
  String get customerSortMaintenance;

  /// Leere Liste
  ///
  /// In de, this message translates to:
  /// **'Keine passende Anlage.'**
  String get customerNone;

  /// In der Liste
  ///
  /// In de, this message translates to:
  /// **'Zuletzt {date}'**
  String customerLastVisit(String date);

  /// Plakette
  ///
  /// In de, this message translates to:
  /// **'Wartung fällig'**
  String get customerDue;

  /// Zeile in der Akte
  ///
  /// In de, this message translates to:
  /// **'Nächste Wartung: {date}'**
  String customerNextMaintenance(String date);

  /// Fehlermeldung
  ///
  /// In de, this message translates to:
  /// **'Das ließ sich auf diesem Gerät nicht öffnen.'**
  String get customerLinkFailed;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get customerEdit;

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Noch keine Kundendaten. Sie bleiben nur auf diesem Gerät und sind nie Teil eines Diagnosepakets.'**
  String get customerEmpty;

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Kundendaten bleiben auf diesem Gerät und sind nie Teil eines Diagnosepakets oder Übergabepakets.'**
  String get customerPrivate;

  /// Menü in der Akte
  ///
  /// In de, this message translates to:
  /// **'Akte exportieren'**
  String get customerExport;

  /// Menü der Liste
  ///
  /// In de, this message translates to:
  /// **'Alle Akten exportieren'**
  String get customerExportAll;

  /// Menü der Liste
  ///
  /// In de, this message translates to:
  /// **'Akten-Datei öffnen'**
  String get customerOpenFile;

  /// Titel
  ///
  /// In de, this message translates to:
  /// **'Akten für ein zweites Gerät'**
  String get customerExportTitle;

  /// Erklärung oben
  ///
  /// In de, this message translates to:
  /// **'Eine passwortgeschützte Datei mit Kundendaten, Besuchen, Protokollen und Serviceberichten. Öffne sie auf deinem zweiten Gerät: Busclear ordnet sie dort den Anlagen zu und ergänzt, was fehlt. Ohne Cloud.'**
  String get customerExportShort;

  /// Zeile: Umfang
  ///
  /// In de, this message translates to:
  /// **'Alle Akten'**
  String get customerExportScopeAll;

  /// Zeile: Umfang
  ///
  /// In de, this message translates to:
  /// **'Anlagen mit Akte: {count}'**
  String customerExportCount(int count);

  /// Schalter
  ///
  /// In de, this message translates to:
  /// **'Fotos mitnehmen'**
  String get customerExportPhotos;

  /// Schalter, Hinweis
  ///
  /// In de, this message translates to:
  /// **'Fotodokumentation: {count} Fotos. Die Datei wird größer.'**
  String customerExportPhotosHint(int count);

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Datei erstellen und teilen'**
  String get customerExportCreate;

  /// Hinweis unter dem Knopf
  ///
  /// In de, this message translates to:
  /// **'Nur für deine eigenen Geräte: Die Datei enthält Kundendaten und gehört nicht zum Übergabepaket für den Kunden.'**
  String get customerExportOwn;

  /// Hinweis, wenn nichts da ist
  ///
  /// In de, this message translates to:
  /// **'Noch keine Akte zum Exportieren.'**
  String get customerExportNothing;

  /// Fehler
  ///
  /// In de, this message translates to:
  /// **'Die Datei würde zu groß. Exportiere ohne Fotos oder einzelne Akten.'**
  String get customerExportTooLarge;

  /// Dateiname
  ///
  /// In de, this message translates to:
  /// **'Kundenakten'**
  String get customerFilePrefix;

  /// Titel
  ///
  /// In de, this message translates to:
  /// **'Akten übernehmen'**
  String get customerImportTitle;

  /// Erste Zeile
  ///
  /// In de, this message translates to:
  /// **'Datei von {company}, erstellt am {date}.'**
  String customerImportFrom(String company, String date);

  /// Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Auf diesem Gerät'**
  String get customerImportHere;

  /// Zeile: was dazukommt
  ///
  /// In de, this message translates to:
  /// **'Neu: Besuche {visits}, Dokumente {documents}, Fotos {photos}'**
  String customerImportNew(int visits, int documents, int photos);

  /// Zeile
  ///
  /// In de, this message translates to:
  /// **'Kundendaten kommen dazu'**
  String get customerImportRecordNew;

  /// Zeile
  ///
  /// In de, this message translates to:
  /// **'Schon auf dem Stand'**
  String get customerImportUpToDate;

  /// Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Kundendaten weichen ab'**
  String get customerImportConflicts;

  /// Erklärung
  ///
  /// In de, this message translates to:
  /// **'Auf beiden Geräten stehen Kundendaten, aber nicht dieselben. Ohne Auswahl bleiben die von diesem Gerät.'**
  String get customerImportConflictHint;

  /// Schalter, nennt die abweichenden Felder
  ///
  /// In de, this message translates to:
  /// **'Aus der Datei übernehmen: {fields}'**
  String customerImportTakeRecord(String fields);

  /// Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Nicht auf diesem Gerät'**
  String get customerImportMissing;

  /// Erklärung
  ///
  /// In de, this message translates to:
  /// **'Diese Anlagen gibt es hier noch nicht. Hole sie zuerst auf dieses Gerät, zum Beispiel aus einer Sicherung, und öffne die Datei dann noch einmal.'**
  String get customerImportMissingHint;

  /// Schalter
  ///
  /// In de, this message translates to:
  /// **'Als leere Anlagen anlegen'**
  String get customerImportCreate;

  /// Schalter, Hinweis
  ///
  /// In de, this message translates to:
  /// **'Mit Akte, ohne Projekt. Das Projekt lädst du später in die Anlage.'**
  String get customerImportCreateHint;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Übernehmen'**
  String get customerImportApply;

  /// Bestätigung
  ///
  /// In de, this message translates to:
  /// **'Akten übernommen: Anlagen {installations}, Besuche {visits}, Dokumente {documents}.'**
  String customerImportDone(int installations, int visits, int documents);

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Nicht übernommene Fotos: {count} (Fotodokumentation voll oder Bild unlesbar).'**
  String customerImportPhotosSkipped(int count);

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Die Datei enthält nichts, was hier fehlt.'**
  String get customerImportNothing;

  /// Fortschritt
  ///
  /// In de, this message translates to:
  /// **'Datei wird geöffnet …'**
  String get customerImportOpening;

  /// Breite Ansicht ohne Auswahl
  ///
  /// In de, this message translates to:
  /// **'Wähle links eine Anlage.'**
  String get customerSelectHint;

  /// Screenreader: Liste links
  ///
  /// In de, this message translates to:
  /// **'Anlagen'**
  String get customerListLabel;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Kunde'**
  String get customerName;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Anschrift der Anlage'**
  String get customerAddress;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Ansprechpartner'**
  String get customerContact;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Telefon'**
  String get customerPhone;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'E-Mail'**
  String get customerEmail;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Kunden- oder Auftragsnummer'**
  String get customerOrder;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Notizen'**
  String get customerNotes;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Wartungsintervall in Monaten'**
  String get customerInterval;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Anrufen'**
  String get customerCall;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'E-Mail schreiben'**
  String get customerMail;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'In Karten öffnen'**
  String get customerMap;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Zu dieser Anlage wechseln'**
  String get customerSwitch;

  /// Kennung
  ///
  /// In de, this message translates to:
  /// **'Besuchsverlauf'**
  String get customerHistory;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Eintrag'**
  String get visitAdd;

  /// Leerer Verlauf
  ///
  /// In de, this message translates to:
  /// **'Noch keine Einträge.'**
  String get visitNone;

  /// Art im Verlauf
  ///
  /// In de, this message translates to:
  /// **'Verbunden'**
  String get visitConnection;

  /// Art im Verlauf
  ///
  /// In de, this message translates to:
  /// **'Inbetriebnahme'**
  String get visitCommissioning;

  /// Art im Verlauf
  ///
  /// In de, this message translates to:
  /// **'Abnahmeprotokoll'**
  String get visitAcceptance;

  /// Art im Verlauf
  ///
  /// In de, this message translates to:
  /// **'Servicebericht'**
  String get visitServiceReport;

  /// Art im Verlauf
  ///
  /// In de, this message translates to:
  /// **'Störungsmeldung'**
  String get visitFaultReport;

  /// Art im Verlauf
  ///
  /// In de, this message translates to:
  /// **'Übergabepaket erstellt'**
  String get visitHandover;

  /// Art im Verlauf
  ///
  /// In de, this message translates to:
  /// **'Eigener Eintrag'**
  String get visitManual;

  /// Dauer
  ///
  /// In de, this message translates to:
  /// **'{minutes} min'**
  String visitMinutes(int minutes);

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Dauer in Minuten'**
  String get visitDuration;

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Text'**
  String get visitText;

  /// Eintrag im Menü der Installation
  ///
  /// In de, this message translates to:
  /// **'Kundenakte'**
  String get installationCustomers;

  /// Titel
  ///
  /// In de, this message translates to:
  /// **'Übergabepaket'**
  String get handoverTitle;

  /// Untertitel im Menü
  ///
  /// In de, this message translates to:
  /// **'Anlage an die App des Kunden übergeben'**
  String get handoverTool;

  /// Pro-Funktion auf der Bezahlseite
  ///
  /// In de, this message translates to:
  /// **'Übergabepaket für die App des Kunden'**
  String get handoverFeature;

  /// Plus-Funktion auf der Bezahlseite
  ///
  /// In de, this message translates to:
  /// **'Übergabepaket vom Elektriker öffnen'**
  String get handoverReceiveFeature;

  /// Erklärung
  ///
  /// In de, this message translates to:
  /// **'Eine Datei für die App deines Kunden: Namen der Gruppenadressen und Geräte, Struktur und Gateway. Keine Cloud, kein Konto: Sie geht per Mail, AirDrop oder USB-Stick. Kundendaten bleiben hier.'**
  String get handoverExplain;

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Trage zuerst deine Firma ein. Der Kunde sieht sie als „eingerichtet von“.'**
  String get handoverNeedsCompany;

  /// Kennung
  ///
  /// In de, this message translates to:
  /// **'Inhalt'**
  String get handoverContents;

  /// Inhalt
  ///
  /// In de, this message translates to:
  /// **'kein Gateway gespeichert'**
  String get handoverNoGateway;

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Diese Anlage hat noch kein Projekt.'**
  String get handoverNoProject;

  /// Schalter
  ///
  /// In de, this message translates to:
  /// **'KNX-Secure-Schlüssel mitgeben'**
  String get handoverIncludeKeys;

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Nur wenn der Kunde sie braucht. Die Datei ist dann immer passwortgeschützt.'**
  String get handoverIncludeKeysHint;

  /// Schalter
  ///
  /// In de, this message translates to:
  /// **'Mit Passwort schützen'**
  String get handoverProtect;

  /// Feld und Kennung
  ///
  /// In de, this message translates to:
  /// **'Passwort'**
  String get handoverPassword;

  /// Für Screenreader
  ///
  /// In de, this message translates to:
  /// **'QR-Code mit dem Passwort'**
  String get handoverQrLabel;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Kopieren'**
  String get handoverCopyPassword;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Neues Passwort'**
  String get handoverNewPassword;

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Gib das Passwort getrennt von der Datei weiter, am besten scannt der Kunde den QR-Code vor Ort. Es wird nirgends gespeichert.'**
  String get handoverPasswordHint;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Paket erstellen und teilen'**
  String get handoverCreate;

  /// Dateiname
  ///
  /// In de, this message translates to:
  /// **'Übergabe {name}'**
  String handoverFilePrefix(String name);

  /// Titel und Knopf
  ///
  /// In de, this message translates to:
  /// **'QR-Code scannen'**
  String get handoverScanTitle;

  /// Fehlermeldung
  ///
  /// In de, this message translates to:
  /// **'Das Passwort stimmt nicht oder die Datei wurde verändert.'**
  String get handoverWrongPassword;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Öffnen'**
  String get handoverOpen;

  /// Fortschritt
  ///
  /// In de, this message translates to:
  /// **'Paket wird geöffnet …'**
  String get handoverOpening;

  /// Ersatz, wenn das Paket keinen Firmennamen hat
  ///
  /// In de, this message translates to:
  /// **'Elektrofachbetrieb'**
  String get handoverUnknownCompany;

  /// Dialogtitel
  ///
  /// In de, this message translates to:
  /// **'Anlage von {company} einrichten?'**
  String handoverImportTitle(String company);

  /// Dialog
  ///
  /// In de, this message translates to:
  /// **'Enthält KNX-Secure-Schlüssel.'**
  String get handoverImportKeys;

  /// Dialog, Add-on
  ///
  /// In de, this message translates to:
  /// **'Das bisherige Projekt wird ersetzt.'**
  String get handoverImportReplaces;

  /// Dialog: Paket gehört zu einer vorhandenen Anlage
  ///
  /// In de, this message translates to:
  /// **'„{name}“ aktualisieren?'**
  String handoverUpdateTitle(String name);

  /// Dialog, erster Satz
  ///
  /// In de, this message translates to:
  /// **'Dieses Paket von {company} gehört zu einer Anlage, die schon auf diesem Gerät ist.'**
  String handoverUpdateIntro(String company);

  /// Dialog: was sich ändert
  ///
  /// In de, this message translates to:
  /// **'Gruppenadressen: {added} neu, {removed} entfernt, {renamed} umbenannt.'**
  String handoverUpdateGroups(int added, int removed, int renamed);

  /// Dialog: was sich ändert
  ///
  /// In de, this message translates to:
  /// **'Geräte: {added} neu, {removed} entfernt, {renamed} umbenannt.'**
  String handoverUpdateDevices(int added, int removed, int renamed);

  /// Dialog: nichts ändert sich am Projekt
  ///
  /// In de, this message translates to:
  /// **'Adressen und Geräte sind unverändert.'**
  String get handoverUpdateNoChanges;

  /// Dialog: Paket mit Schlüsseln
  ///
  /// In de, this message translates to:
  /// **'Die KNX-Secure-Schlüssel werden durch die aus dem Paket ersetzt.'**
  String get handoverUpdateKeysReplaced;

  /// Dialog: Paket ohne Schlüssel
  ///
  /// In de, this message translates to:
  /// **'Das Paket enthält keine KNX-Secure-Schlüssel. Hier gespeicherte Schlüssel dieser Anlage werden entfernt.'**
  String get handoverUpdateKeysRemoved;

  /// Dialog: was bleibt
  ///
  /// In de, this message translates to:
  /// **'Dein Verlauf, deine Diagramme, Wächter, Kommentare und Aufnahmen bleiben erhalten.'**
  String get handoverUpdateKeeps;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Diese Anlage aktualisieren'**
  String get handoverUpdateConfirm;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Als neue Anlage einrichten'**
  String get handoverUpdateAsNew;

  /// Bestätigung
  ///
  /// In de, this message translates to:
  /// **'{name} ist eingerichtet, von {company}.'**
  String handoverImported(String name, String company);

  /// Kopf in der Karte der Anlage
  ///
  /// In de, this message translates to:
  /// **'Eingerichtet von {company}'**
  String handoverSetUpBy(String company);

  /// Fehlermeldung
  ///
  /// In de, this message translates to:
  /// **'Diese Datei lässt sich nicht lesen. Sie ist beschädigt oder kein Paket von Busclear.'**
  String get packageCorrupt;

  /// Fehlermeldung
  ///
  /// In de, this message translates to:
  /// **'Diese Datei stammt aus einer neueren Version. Bitte die App aktualisieren.'**
  String get packageNewer;

  /// Fehlermeldung
  ///
  /// In de, this message translates to:
  /// **'Diese Datei ist zu groß, um sie direkt zu öffnen. Bitte in der App über „Paket oder Meldung öffnen“ wählen.'**
  String get packageTooLarge;

  /// Fehlermeldung
  ///
  /// In de, this message translates to:
  /// **'Diese Datei ließ sich nicht lesen. Bitte noch einmal öffnen oder in der App über „Paket oder Meldung öffnen“ wählen.'**
  String get packageUnreadable;

  /// Eintrag im Menü der Installation
  ///
  /// In de, this message translates to:
  /// **'Paket oder Meldung öffnen'**
  String get packageOpenMenu;

  /// Titel und Menü
  ///
  /// In de, this message translates to:
  /// **'An {company} melden'**
  String faultReportTo(String company);

  /// Untertitel im Menü
  ///
  /// In de, this message translates to:
  /// **'Störung mit echten Daten an deinen Elektriker melden'**
  String get faultReportTool;

  /// Erklärung
  ///
  /// In de, this message translates to:
  /// **'Beschreibe kurz, was passiert ist. Daraus entsteht eine Datei für {company}, mit der Aufnahme, deinen Markierungen und Screenshots.'**
  String faultExplain(String company);

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Was ist passiert?'**
  String get faultProblem;

  /// Beispiel
  ///
  /// In de, this message translates to:
  /// **'z. B. Licht im Bad geht nicht mehr aus'**
  String get faultProblemHint;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Datei erstellen und schicken'**
  String get faultSend;

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Schicke die Datei per Mail oder Nachricht an {company}.'**
  String faultSentHint(String company);

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Die Datei enthält keine Schlüssel und keine Passwörter. Sie enthält die Telegramme dieser Sitzung, deine Kommentare und das Protokoll der App, auf Wunsch auch Namen und Screenshots. Sie geht nur an die Firma, der du sie schickst: Es gibt keine Cloud und kein Konto.'**
  String get faultPrivacy;

  /// Dateiname
  ///
  /// In de, this message translates to:
  /// **'Stoerungsmeldung'**
  String get faultFilePrefix;

  /// Dialog
  ///
  /// In de, this message translates to:
  /// **'Zu welcher Anlage gehört die Meldung von „{name}“?'**
  String faultPickInstallation(String name);

  /// Bestätigung
  ///
  /// In de, this message translates to:
  /// **'Meldung liegt jetzt im Verlauf von {name}.'**
  String faultReceived(String name);

  /// Titel
  ///
  /// In de, this message translates to:
  /// **'Bewohner-Handbuch'**
  String get manualTitle;

  /// Untertitel im Menü
  ///
  /// In de, this message translates to:
  /// **'Heft für die Bewohner aus Projekt und angelernten Namen'**
  String get manualTool;

  /// Pro-Funktion auf der Bezahlseite
  ///
  /// In de, this message translates to:
  /// **'Bewohner-Handbuch als PDF'**
  String get manualFeature;

  /// Erklärung
  ///
  /// In de, this message translates to:
  /// **'Ein Heft für die Menschen, die in der Anlage wohnen: nach Räumen, ohne Adressen und Fachbegriffe. Rückmeldungen und Technisches bleiben draußen.'**
  String get manualExplain;

  /// Zusammenfassung
  ///
  /// In de, this message translates to:
  /// **'{rooms} Bereiche, {count} Funktionen'**
  String manualSummary(int rooms, int count);

  /// Feld
  ///
  /// In de, this message translates to:
  /// **'Eigene Hinweise'**
  String get manualNote;

  /// Beispiel
  ///
  /// In de, this message translates to:
  /// **'z. B. Hauptschalter und Sicherungen sind im Keller'**
  String get manualNoteHint;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Handbuch erstellen und teilen'**
  String get manualCreate;

  /// Hinweis
  ///
  /// In de, this message translates to:
  /// **'Für ein Handbuch braucht es ein Projekt oder angelernte Namen.'**
  String get manualEmpty;

  /// Titel im PDF
  ///
  /// In de, this message translates to:
  /// **'Handbuch für Ihre Anlage'**
  String get manualPdfTitle;

  /// Einleitung
  ///
  /// In de, this message translates to:
  /// **'In diesem Heft steht, was Ihre Elektroanlage in jedem Raum kann. Die Taster an der Wand funktionieren wie gewohnt; alles andere läuft im Hintergrund.'**
  String get manualIntro;

  /// Bereich ohne Raum
  ///
  /// In de, this message translates to:
  /// **'Weitere Funktionen'**
  String get manualOther;

  /// Abschnitt im PDF
  ///
  /// In de, this message translates to:
  /// **'Hinweise von uns'**
  String get manualNoteLabel;

  /// Abschnitt im PDF
  ///
  /// In de, this message translates to:
  /// **'Wenn etwas nicht funktioniert'**
  String get manualTroubleTitle;

  /// Schritt
  ///
  /// In de, this message translates to:
  /// **'Taster noch einmal drücken und kurz warten.'**
  String get manualTrouble1;

  /// Schritt
  ///
  /// In de, this message translates to:
  /// **'Prüfen, ob auch andere Dinge im Raum betroffen sind, und das notieren.'**
  String get manualTrouble2;

  /// Schritt
  ///
  /// In de, this message translates to:
  /// **'Sicherungen nicht selbst tauschen, sondern uns anrufen.'**
  String get manualTrouble3;

  /// Abschnitt im PDF
  ///
  /// In de, this message translates to:
  /// **'So erreichen Sie uns'**
  String get manualContact;

  /// Bedienung
  ///
  /// In de, this message translates to:
  /// **'Ein- und ausschalten'**
  String get manualKindOnOff;

  /// Bedienung
  ///
  /// In de, this message translates to:
  /// **'Heller und dunkler'**
  String get manualKindDim;

  /// Bedienung
  ///
  /// In de, this message translates to:
  /// **'Stufenlos einstellen'**
  String get manualKindPercent;

  /// Bedienung
  ///
  /// In de, this message translates to:
  /// **'Auf und ab fahren'**
  String get manualKindBlinds;

  /// Bedienung
  ///
  /// In de, this message translates to:
  /// **'Öffnen und schließen'**
  String get manualKindOpenClose;

  /// Bedienung
  ///
  /// In de, this message translates to:
  /// **'Lichtstimmung abrufen'**
  String get manualKindScene;

  /// Bedienung
  ///
  /// In de, this message translates to:
  /// **'Zeigt die Raumtemperatur'**
  String get manualKindTemperature;

  /// Bedienung
  ///
  /// In de, this message translates to:
  /// **'Wunschtemperatur einstellen'**
  String get manualKindSetpoint;

  /// Bedienung
  ///
  /// In de, this message translates to:
  /// **'Zeigt einen Messwert'**
  String get manualKindMeasure;

  /// Bedienung
  ///
  /// In de, this message translates to:
  /// **'Funktion der Anlage'**
  String get manualKindOther;

  /// Betriebslösung
  ///
  /// In de, this message translates to:
  /// **'Betriebsstandard'**
  String get bizStandardTitle;

  /// Betriebslösung
  ///
  /// In de, this message translates to:
  /// **'GA-Assistent'**
  String get bizAssistantTitle;

  /// Betriebslösung
  ///
  /// In de, this message translates to:
  /// **'Prüfung gegen den Standard'**
  String get bizCheckTitle;

  /// Betriebslösung
  ///
  /// In de, this message translates to:
  /// **'Anlagenhinweise'**
  String get bizNotesTitle;

  /// Betriebslösung
  ///
  /// In de, this message translates to:
  /// **'Abweichung vom Standard'**
  String get etsTitleStandard;

  /// Betriebslösung
  ///
  /// In de, this message translates to:
  /// **'Nicht gesendet.'**
  String get bizSendCancelled;

  /// Betriebslösung
  ///
  /// In de, this message translates to:
  /// **'Bestandsaufnahme'**
  String get bizSurveyTitle;

  /// Galerie geteilter Vorlagen
  ///
  /// In de, this message translates to:
  /// **'Galerie der Vorlagen'**
  String get galleryTitle;

  /// Galerie geteilter Vorlagen
  ///
  /// In de, this message translates to:
  /// **'Fertige Diagramm-Vorlagen mit Rollen statt Adressen. Sie gehören zur App, nichts wird aus dem Netz geladen. Übernehmen legt die Vorlage in deine Bibliothek und wendet sie auf das Projekt dieser Anlage an.'**
  String get galleryIntro;

  /// Galerie geteilter Vorlagen
  ///
  /// In de, this message translates to:
  /// **'Suchen'**
  String get gallerySearch;

  /// Galerie geteilter Vorlagen
  ///
  /// In de, this message translates to:
  /// **'Keine Vorlage passt zur Suche.'**
  String get galleryNoMatch;

  /// Galerie geteilter Vorlagen
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Passt einmal auf dieses Projekt} other{Passt {count}-mal auf dieses Projekt}}'**
  String galleryFits(int count);

  /// Galerie geteilter Vorlagen
  ///
  /// In de, this message translates to:
  /// **'Findet in diesem Projekt noch keine passenden Adressen'**
  String get galleryFitsNothing;

  /// Galerie geteilter Vorlagen
  ///
  /// In de, this message translates to:
  /// **'„{name}“ liegt jetzt in deiner Bibliothek'**
  String galleryAdopted(String name);

  /// Galerie geteilter Vorlagen
  ///
  /// In de, this message translates to:
  /// **'Eigene Vorlage einreichen'**
  String get gallerySubmit;

  /// Galerie geteilter Vorlagen
  ///
  /// In de, this message translates to:
  /// **'Wähle ein Diagramm. Die App erstellt daraus eine Datei mit Namen und Rollen, ohne Adressen und Räume. Teile sie selbst, zum Beispiel per Mail an support@busclear.de; hochgeladen wird nichts.'**
  String get gallerySubmitHint;

  /// Galerie geteilter Vorlagen
  ///
  /// In de, this message translates to:
  /// **'Noch kein gespeichertes Diagramm mit erkennbaren Rollen.'**
  String get gallerySubmitNone;

  /// Fotodoku des Verteilers und QR-Etiketten
  ///
  /// In de, this message translates to:
  /// **'Fotodoku und Etiketten'**
  String get siteDocsTitle;

  /// Fotodoku
  ///
  /// In de, this message translates to:
  /// **'Fotos des Verteilers, Etiketten mit QR-Code'**
  String get siteDocsTool;

  /// Fotodoku
  ///
  /// In de, this message translates to:
  /// **'Fotos'**
  String get siteDocsPhotos;

  /// Fotodoku
  ///
  /// In de, this message translates to:
  /// **'Fotos bleiben auf diesem Gerät im Ordner der Anlage und gehen beim Löschen der Anlage mit. Sie stehen nicht im Diagnose- und nicht im Übergabepaket; in einen Servicebericht kommen sie nur, wenn du sie dort auswählst. Ort und Gerätedaten werden aus dem Bild entfernt.'**
  String get siteDocsPhotosHint;

  /// Fotodoku
  ///
  /// In de, this message translates to:
  /// **'Foto aufnehmen'**
  String get siteDocsTakePhoto;

  /// Fotodoku
  ///
  /// In de, this message translates to:
  /// **'Bild wählen'**
  String get siteDocsPickPhoto;

  /// Fotodoku
  ///
  /// In de, this message translates to:
  /// **'Beschriftung'**
  String get siteDocsCaption;

  /// Fotodoku
  ///
  /// In de, this message translates to:
  /// **'z. B. Verteiler Keller, Reihe 2'**
  String get siteDocsCaptionHint;

  /// Fotodoku
  ///
  /// In de, this message translates to:
  /// **'Ohne Beschriftung'**
  String get siteDocsNoCaption;

  /// Fotodoku
  ///
  /// In de, this message translates to:
  /// **'Foto löschen'**
  String get siteDocsDelete;

  /// Fotodoku
  ///
  /// In de, this message translates to:
  /// **'Kein Platz mehr für Fotos dieser Anlage. Lösche zuerst ältere.'**
  String get siteDocsQuota;

  /// Fotodoku
  ///
  /// In de, this message translates to:
  /// **'Das Bild ließ sich nicht lesen.'**
  String get siteDocsUnreadable;

  /// Etiketten
  ///
  /// In de, this message translates to:
  /// **'Etiketten'**
  String get siteDocsLabels;

  /// Etiketten
  ///
  /// In de, this message translates to:
  /// **'Bogen A4 mit 70 × 37 mm: physikalische Adresse, Funktion, Einbauort und QR-Code. Der Code öffnet das Gerät nur in dieser App und enthält keine Web-Adresse und keine Zugangsdaten.'**
  String get siteDocsLabelsHint;

  /// Etiketten
  ///
  /// In de, this message translates to:
  /// **'Etiketten brauchen Geräte aus einem ETS-Projekt.'**
  String get siteDocsLabelsNoProject;

  /// Etiketten
  ///
  /// In de, this message translates to:
  /// **'Etiketten erstellen'**
  String get siteDocsLabelsCreate;

  /// Etiketten
  ///
  /// In de, this message translates to:
  /// **'Etiketten'**
  String get siteDocsLabelsPdf;

  /// Etiketten
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Etikett erstellen} other{{count} Etiketten erstellen}}'**
  String siteDocsLabelsCount(int count);

  /// Etiketten
  ///
  /// In de, this message translates to:
  /// **'Alle wählen'**
  String get siteDocsLabelsAll;

  /// Etiketten
  ///
  /// In de, this message translates to:
  /// **'Keine wählen'**
  String get siteDocsLabelsNone;

  /// Etiketten
  ///
  /// In de, this message translates to:
  /// **'Etikett scannen'**
  String get siteDocsScan;

  /// Etiketten
  ///
  /// In de, this message translates to:
  /// **'Gerät {device} gehört zur Anlage „{name}“. Wechsle zuerst dorthin.'**
  String siteDocsScanOther(String device, String name);

  /// Etiketten
  ///
  /// In de, this message translates to:
  /// **'Gerät {device} gehört zu einer Anlage, die nicht auf diesem Gerät liegt.'**
  String siteDocsScanUnknown(String device);

  /// Etiketten
  ///
  /// In de, this message translates to:
  /// **'Das ist kein Etikett von Busclear.'**
  String get siteDocsScanForeign;

  /// Servicebericht
  ///
  /// In de, this message translates to:
  /// **'Fotos'**
  String get srPhotos;

  /// Servicebericht
  ///
  /// In de, this message translates to:
  /// **'Nur die angehakten Fotos kommen in den Bericht.'**
  String get srPhotosHint;

  /// Strom-/Lastwerte aus Aktoren mit Strommessung
  ///
  /// In de, this message translates to:
  /// **'Strom und Last'**
  String get loadTitle;

  /// Lastwerte
  ///
  /// In de, this message translates to:
  /// **'Stromwerte und Leistung je Kanal, Maximum, Abweichungen'**
  String get loadTool;

  /// Lastwerte
  ///
  /// In de, this message translates to:
  /// **'Werte aus Aktoren mit Strommessung, nur aus Telegrammen, die ohnehin auf dem Bus laufen. Die App fragt nichts ab; wie aktuell ein Wert ist, hängt davon ab, wie der Aktor sendet.'**
  String get loadExplain;

  /// Lastwerte
  ///
  /// In de, this message translates to:
  /// **'Keine Strom- oder Leistungswerte erkannt'**
  String get loadNone;

  /// Lastwerte
  ///
  /// In de, this message translates to:
  /// **'Erkannt werden Adressen mit Datentyp 7.012, 9.021, 14.019, 9.024 oder 14.056 und Zahlenadressen mit Namen wie „Strom“ oder „Leistung“.'**
  String get loadNoneDetail;

  /// Lastwerte
  ///
  /// In de, this message translates to:
  /// **'Noch kein Messwert mitgehört'**
  String get loadNoValues;

  /// Lastwerte
  ///
  /// In de, this message translates to:
  /// **'Maximum {value} am {when} · {count} Messwerte'**
  String loadPeak(String value, String when, int count);

  /// Lastwerte
  ///
  /// In de, this message translates to:
  /// **'Hinweise erst ab {samples} Messwerten über mindestens {hours} Stunden. Abweichung: alle letzten {recent} Werte mehr als {percent} % neben dem Üblichen (Median), ein Ausreißer zählt nicht. Verbraucher, die oft aus sind, melden keinen Ausfall.'**
  String loadRulesExplain(int samples, int hours, int percent, int recent);

  /// Lastwerte
  ///
  /// In de, this message translates to:
  /// **'Sendet vermutlich nicht mehr: sonst etwa alle {minutes} min, zuletzt um {time}. Üblich waren {typical}.'**
  String loadHintSilent(String typical, int minutes, String time);

  /// Lastwerte
  ///
  /// In de, this message translates to:
  /// **'Vermutlich ausgefallen oder abgeschaltet: üblich {typical}, zuletzt {latest}.'**
  String loadHintDropped(String typical, String latest);

  /// Lastwerte
  ///
  /// In de, this message translates to:
  /// **'Weicht ab: üblich {typical}, zuletzt {latest} ({percent} %). Vermutlich hat sich am Verbraucher etwas geändert.'**
  String loadHintDeviation(String typical, String latest, String percent);

  /// Prüfung der Koppler-Filtertabellen
  ///
  /// In de, this message translates to:
  /// **'Koppler: Filtertabellen'**
  String get checkFilterTitle;

  /// Filterprüfung
  ///
  /// In de, this message translates to:
  /// **'Die Filtertabellen werden nicht gelesen und nicht beschrieben. Das Ergebnis stammt aus dem Projekt und dem Mitgehörten und ist deshalb nur eine Vermutung.'**
  String get checkFilterHint;

  /// Filterprüfung
  ///
  /// In de, this message translates to:
  /// **'Laufender Mitschnitt'**
  String get checkFilterLive;

  /// Filterprüfung
  ///
  /// In de, this message translates to:
  /// **'Sender auf {senders}, Empfänger auf {receivers}: kommt vermutlich nur an, wenn die Filtertabelle des Kopplers sie kennt'**
  String checkFilterCrossRow(String senders, String receivers);

  /// Filterprüfung
  ///
  /// In de, this message translates to:
  /// **'Auf {lines} von einer anderen Linie gesehen, der Übergang funktioniert vermutlich'**
  String checkFilterConfirmedRow(String lines);

  /// Filterprüfung
  ///
  /// In de, this message translates to:
  /// **'Auf {seen} gesehen ({count}×), auf {missing} nicht, obwohl dort ein Empfänger sitzt. Vermutlich fehlt die Adresse in der Filtertabelle oder sie wurde nicht neu geladen.'**
  String checkFilterMissingRow(String seen, int count, String missing);

  /// Filterprüfung
  ///
  /// In de, this message translates to:
  /// **'Ein Vergleich am Bus braucht zwei gleichzeitige Mitschnitte auf verschiedenen Linien. Bisher stammt das Ergebnis nur aus dem Projekt.'**
  String get checkFilterNoPoints;

  /// Aufgaben für die ETS
  ///
  /// In de, this message translates to:
  /// **'Linienübergreifende Adressen'**
  String get etsTitleFilterCrossLine;

  /// Aufgaben für die ETS
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Adresse läuft} other{{count} Adressen laufen}} zu Linie {line}. Prüfe, ob der Koppler dorthin nach der letzten Änderung geladen wurde (Filtertabelle); die App kann das nicht sehen.'**
  String etsTodoFilterCrossLine(String line, int count);

  /// Aufgaben für die ETS
  ///
  /// In de, this message translates to:
  /// **'Vermutlich vom Koppler gefiltert'**
  String get etsTitleFilterNotForwarded;

  /// Aufgaben für die ETS
  ///
  /// In de, this message translates to:
  /// **'Kam auf Linie {line} nicht an, obwohl dort ein Empfänger sitzt. Filtertabelle des Kopplers in der ETS prüfen und neu laden.'**
  String etsTodoFilterNotForwarded(String line);

  /// Anlagenbericht: Titel
  ///
  /// In de, this message translates to:
  /// **'Anlagenbericht'**
  String get plantTitle;

  /// Anlagenbericht: Werkzeugliste
  ///
  /// In de, this message translates to:
  /// **'Monats- oder Quartalsbericht von Box und Add-on, als PDF'**
  String get plantTool;

  /// Anlagenbericht: Einleitung
  ///
  /// In de, this message translates to:
  /// **'Box und Add-on verdichten den Betrieb der Anlage zu einem Bericht: Verfügbarkeit, Verkehr, Buslast, verstummte Geräte, Rauchmelder und Batterien. Die Daten bleiben auf dem Server.'**
  String get plantIntro;

  /// Anlagenbericht: Schalter
  ///
  /// In de, this message translates to:
  /// **'Bericht erstellen'**
  String get plantEnabled;

  /// Anlagenbericht: Schalter
  ///
  /// In de, this message translates to:
  /// **'Standard aus. Der erste Bericht entsteht nach Ende des laufenden Zeitraums.'**
  String get plantEnabledHint;

  /// Anlagenbericht: Hinweis
  ///
  /// In de, this message translates to:
  /// **'Der letzte Lauf ist fehlgeschlagen; die Aufzeichnung läuft weiter.'**
  String get plantLastError;

  /// Anlagenbericht: Feld
  ///
  /// In de, this message translates to:
  /// **'Zeitraum'**
  String get plantPeriod;

  /// Anlagenbericht: Auswahl
  ///
  /// In de, this message translates to:
  /// **'Monatlich'**
  String get plantPeriodMonthly;

  /// Anlagenbericht: Auswahl
  ///
  /// In de, this message translates to:
  /// **'Quartalsweise'**
  String get plantPeriodQuarterly;

  /// Anlagenbericht: Kennung
  ///
  /// In de, this message translates to:
  /// **'Wartung'**
  String get plantMaintenance;

  /// Anlagenbericht: Text
  ///
  /// In de, this message translates to:
  /// **'Kein Wartungsintervall in der Kundenakte.'**
  String get plantMaintenanceNone;

  /// Anlagenbericht: Kennung
  ///
  /// In de, this message translates to:
  /// **'Mitteilungen'**
  String get plantNotify;

  /// Anlagenbericht: Hinweis
  ///
  /// In de, this message translates to:
  /// **'Standard aus. Nur eine Zusammenfassung wie „Bericht bereit: 2 Befunde“, nie Adressen, Namen oder Werte. Das Ziel wählst du.'**
  String get plantNotifyHint;

  /// Anlagenbericht: Feld
  ///
  /// In de, this message translates to:
  /// **'Ziel'**
  String get plantNotifyTarget;

  /// Anlagenbericht: Auswahl
  ///
  /// In de, this message translates to:
  /// **'Keine Mitteilungen'**
  String get plantNotifyOff;

  /// Anlagenbericht: Auswahl
  ///
  /// In de, this message translates to:
  /// **'Webhook'**
  String get plantNotifyWebhook;

  /// Anlagenbericht: Auswahl
  ///
  /// In de, this message translates to:
  /// **'Home Assistant'**
  String get plantNotifyHa;

  /// Anlagenbericht: Feld
  ///
  /// In de, this message translates to:
  /// **'Adresse'**
  String get plantNotifyUrl;

  /// Anlagenbericht: Feld
  ///
  /// In de, this message translates to:
  /// **'Topic'**
  String get plantNotifyTopic;

  /// Anlagenbericht: Feld
  ///
  /// In de, this message translates to:
  /// **'Zugangstoken'**
  String get plantNotifyToken;

  /// Anlagenbericht: Feld
  ///
  /// In de, this message translates to:
  /// **'Gespeichert; leer lassen, um es zu behalten'**
  String get plantNotifyTokenSet;

  /// Anlagenbericht: Feld
  ///
  /// In de, this message translates to:
  /// **'Optional'**
  String get plantNotifyTokenOptional;

  /// Anlagenbericht: Auswahl
  ///
  /// In de, this message translates to:
  /// **'Wenn ein Bericht bereit ist'**
  String get plantNotifyReady;

  /// Anlagenbericht: Auswahl
  ///
  /// In de, this message translates to:
  /// **'Bei dringenden Befunden und fälliger Wartung'**
  String get plantNotifyUrgent;

  /// Anlagenbericht: Knopf
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get plantNotifySave;

  /// Anlagenbericht: Knopf
  ///
  /// In de, this message translates to:
  /// **'Test senden'**
  String get plantNotifyTest;

  /// Anlagenbericht: Meldung
  ///
  /// In de, this message translates to:
  /// **'Testmitteilung zugestellt.'**
  String get plantTestSent;

  /// Anlagenbericht: Grund
  ///
  /// In de, this message translates to:
  /// **'kein Ziel gewählt'**
  String get plantNotifyErrorOff;

  /// Anlagenbericht: Grund
  ///
  /// In de, this message translates to:
  /// **'das Ziel antwortet nicht'**
  String get plantNotifyErrorTimeout;

  /// Anlagenbericht: Grund
  ///
  /// In de, this message translates to:
  /// **'die Adresse oder das Topic ist ungültig'**
  String get plantNotifyErrorInvalid;

  /// Anlagenbericht: Grund
  ///
  /// In de, this message translates to:
  /// **'keine Verbindung zum Ziel'**
  String get plantNotifyErrorNetwork;

  /// Anlagenbericht: Kennung
  ///
  /// In de, this message translates to:
  /// **'Berichte'**
  String get plantReports;

  /// Anlagenbericht: Text
  ///
  /// In de, this message translates to:
  /// **'Noch kein Bericht.'**
  String get plantNoReports;

  /// Anlagenbericht: Knopf
  ///
  /// In de, this message translates to:
  /// **'Zwischenstand erstellen'**
  String get plantGenerateNow;

  /// Anlagenbericht: Fortschritt
  ///
  /// In de, this message translates to:
  /// **'Bericht entsteht …'**
  String get plantGenerating;

  /// Anlagenbericht: Kennzeichen
  ///
  /// In de, this message translates to:
  /// **'Zwischenstand'**
  String get plantPartial;

  /// Anlagenbericht: Ergebnis
  ///
  /// In de, this message translates to:
  /// **'Keine Auffälligkeiten im Zeitraum.'**
  String get plantResultGood;

  /// Anlagenbericht: Vergleich
  ///
  /// In de, this message translates to:
  /// **'neu'**
  String get plantStatusNew;

  /// Anlagenbericht: Vergleich
  ///
  /// In de, this message translates to:
  /// **'unverändert'**
  String get plantStatusUnchanged;

  /// Anlagenbericht: Vergleich
  ///
  /// In de, this message translates to:
  /// **'behoben'**
  String get plantStatusResolved;

  /// Anlagenbericht: Kennung
  ///
  /// In de, this message translates to:
  /// **'Befunde'**
  String get plantFindings;

  /// Anlagenbericht: Text
  ///
  /// In de, this message translates to:
  /// **'Keine Befunde.'**
  String get plantFindingsNone;

  /// Anlagenbericht: Kennung
  ///
  /// In de, this message translates to:
  /// **'Seit dem letzten Bericht behoben'**
  String get plantResolved;

  /// Anlagenbericht: Kennung
  ///
  /// In de, this message translates to:
  /// **'Rauchmelder, Störungen, Batterien'**
  String get plantSafety;

  /// Anlagenbericht: Hinweis
  ///
  /// In de, this message translates to:
  /// **'Letzter Stand, erkannt an Name und Datentyp im Projekt. Ersetzt keine Prüfung der Melder.'**
  String get plantSafetyHint;

  /// Anlagenbericht: Stand
  ///
  /// In de, this message translates to:
  /// **'aktiv'**
  String get plantSafetyActive;

  /// Anlagenbericht: Stand
  ///
  /// In de, this message translates to:
  /// **'in Ordnung'**
  String get plantSafetyOk;

  /// Anlagenbericht: Stand
  ///
  /// In de, this message translates to:
  /// **'unbekannt'**
  String get plantSafetyUnknown;

  /// Anlagenbericht: Kennung
  ///
  /// In de, this message translates to:
  /// **'Ausfälle'**
  String get plantOutageList;

  /// Anlagenbericht: Art
  ///
  /// In de, this message translates to:
  /// **'Server lief nicht'**
  String get plantOutageOffline;

  /// Anlagenbericht: Art
  ///
  /// In de, this message translates to:
  /// **'Bus nicht verbunden'**
  String get plantOutageDisconnected;

  /// Anlagenbericht: Kennung
  ///
  /// In de, this message translates to:
  /// **'Aktivste Geräte'**
  String get plantTopSenders;

  /// Anlagenbericht: Kennung
  ///
  /// In de, this message translates to:
  /// **'Buslast je Linie (Mittel / Spitzenstunde)'**
  String get plantLines;

  /// Anlagenbericht: Kennung
  ///
  /// In de, this message translates to:
  /// **'Wiederholungen je Gerät'**
  String get plantRepeatList;

  /// Anlagenbericht: Knopf
  ///
  /// In de, this message translates to:
  /// **'Als PDF'**
  String get plantPdf;

  /// Anlagenbericht: Dateiname
  ///
  /// In de, this message translates to:
  /// **'Anlagenbericht'**
  String get plantPdfName;

  /// Anlagenbericht: PDF
  ///
  /// In de, this message translates to:
  /// **'Anlagenbericht'**
  String get plantPdfTitle;

  /// Anlagenbericht: PDF
  ///
  /// In de, this message translates to:
  /// **'Erstellt aus den Daten der Daueraufzeichnung. Die Buslast ist eine Schätzung aus den mitgehörten Telegrammen; Geräte hinter Linienkopplern sind nur sichtbar, soweit die Filter sie durchlassen.'**
  String get plantPdfNote;

  /// Anlagenbericht: PDF
  ///
  /// In de, this message translates to:
  /// **'Verfügbarkeit'**
  String get plantAvailabilityLabel;

  /// Anlagenbericht: PDF
  ///
  /// In de, this message translates to:
  /// **'Telegramme'**
  String get plantTelegramsLabel;

  /// Anlagenbericht: PDF
  ///
  /// In de, this message translates to:
  /// **'Buslast Mittel / Spitze'**
  String get plantLoadLabel;

  /// Anlagenbericht: PDF
  ///
  /// In de, this message translates to:
  /// **'Tage mit Daten'**
  String get plantCoverageLabel;

  /// Anlagenbericht: Besuchsverlauf
  ///
  /// In de, this message translates to:
  /// **'Anlagenbericht erstellt'**
  String get visitReport;

  /// Anlagenbericht: Befund
  ///
  /// In de, this message translates to:
  /// **'Gerät {label} antwortet nicht mehr seit {since}'**
  String plantDeviceSilent(String label, String since);

  /// Anlagenbericht: Befund
  ///
  /// In de, this message translates to:
  /// **'{label} sendet sonst regelmäßig, zuletzt am {since}'**
  String plantCyclicSilent(String label, String since);

  /// Anlagenbericht: Befund
  ///
  /// In de, this message translates to:
  /// **'{label}: Messwert ändert sich nicht mehr seit {since}'**
  String plantStuck(String label, String since);

  /// Anlagenbericht: Befund
  ///
  /// In de, this message translates to:
  /// **'Gerät {label} wiederholt {rate} % seiner Telegramme'**
  String plantRepeats(String label, String rate);

  /// Anlagenbericht: Befund
  ///
  /// In de, this message translates to:
  /// **'Buslast bis {rate} % in der Spitzenstunde'**
  String plantBusLoad(String rate);

  /// Anlagenbericht: Befund
  ///
  /// In de, this message translates to:
  /// **'Verfügbarkeit nur {rate} %'**
  String plantOutages(String rate);

  /// Anlagenbericht: Befund
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 unerwarteter Neustart des Servers} other{{n} unerwartete Neustarts des Servers}}'**
  String plantRestarts(int n);

  /// Anlagenbericht: Befund
  ///
  /// In de, this message translates to:
  /// **'{label}: Alarm aktiv seit {since}'**
  String plantAlarmActive(String label, String since);

  /// Anlagenbericht: Befund
  ///
  /// In de, this message translates to:
  /// **'{label}: Störung aktiv seit {since}'**
  String plantFaultActive(String label, String since);

  /// Anlagenbericht: Befund
  ///
  /// In de, this message translates to:
  /// **'{label}: Batterie schwach, gemeldet am {since}'**
  String plantBatteryLow(String label, String since);

  /// Anlagenbericht: Grund
  ///
  /// In de, this message translates to:
  /// **'das Ziel meldet HTTP {code}'**
  String plantNotifyErrorHttp(String code);

  /// Anlagenbericht: Meldung
  ///
  /// In de, this message translates to:
  /// **'Nicht zugestellt: {reason}'**
  String plantTestFailed(String reason);

  /// Anlagenbericht: Ergebnis
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Punkt braucht Aufmerksamkeit.} other{{n} Punkte brauchen Aufmerksamkeit.}}'**
  String plantResultAttention(int n);

  /// Anlagenbericht: Liste
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =0{Keine Befunde} =1{1 Befund} other{{n} Befunde}}'**
  String plantEntryFindings(int n);

  /// Anlagenbericht: Liste
  ///
  /// In de, this message translates to:
  /// **'{n} neu'**
  String plantEntryNew(int n);

  /// Anlagenbericht: Liste
  ///
  /// In de, this message translates to:
  /// **'{n} behoben'**
  String plantEntryResolved(int n);

  /// Anlagenbericht: Kennzahl
  ///
  /// In de, this message translates to:
  /// **'Daten für {days} von {total} Tagen'**
  String plantCoverage(int days, int total);

  /// Anlagenbericht: Kennzahl
  ///
  /// In de, this message translates to:
  /// **'Verfügbarkeit {rate} %'**
  String plantAvailability(String rate);

  /// Anlagenbericht: Kennzahl
  ///
  /// In de, this message translates to:
  /// **'{n} Telegramme'**
  String plantTelegrams(int n);

  /// Anlagenbericht: Kennzahl
  ///
  /// In de, this message translates to:
  /// **'Buslast {average} % / Spitze {peak} %'**
  String plantLoad(String average, String peak);

  /// Absturzerkennung: Hinweis nach Absturz
  ///
  /// In de, this message translates to:
  /// **'Busclear wurde unerwartet beendet'**
  String get crashTitle;

  /// Absturzerkennung: Knopf: öffnet das Diagnosepaket
  ///
  /// In de, this message translates to:
  /// **'Bericht erstellen'**
  String get crashReport;

  /// Absturzerkennung: Knopf
  ///
  /// In de, this message translates to:
  /// **'Ausblenden'**
  String get crashDismiss;

  /// Absturzerkennung: Grund
  ///
  /// In de, this message translates to:
  /// **'Fehler im Server'**
  String get restartReasonError;

  /// Absturzerkennung: Grund
  ///
  /// In de, this message translates to:
  /// **'Gerät neu gestartet oder Stromausfall'**
  String get restartReasonHost;

  /// Absturzerkennung: Grund
  ///
  /// In de, this message translates to:
  /// **'Grund unbekannt'**
  String get restartReasonUnknown;

  /// Absturzerkennung: Hinweis
  ///
  /// In de, this message translates to:
  /// **'Zuletzt im Vordergrund: {time}. Nichts wird automatisch gesendet. Mit dem Bericht siehst du das bereinigte Protokoll im Diagnosepaket und entscheidest selbst, ob du es teilst.'**
  String crashBody(String time);

  /// Absturzerkennung: Status des Servers
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 unerwarteter Neustart} other{{count} unerwartete Neustarts}} in 30 Tagen, zuletzt {time} ({reason})'**
  String serverRestarts(int count, String time, String reason);

  /// Absturzerkennung: Befund im Diagnosepaket
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 unerwarteter Neustart des Servers} other{{count} unerwartete Neustarts des Servers}} in den letzten 30 Tagen'**
  String findingRestarts(int count);

  /// Anlagenbericht: Befund, nur mit KNX-HAT im Busmonitor
  ///
  /// In de, this message translates to:
  /// **'{rate} % der Telegramme abgelehnt oder gestört (Busmonitor)'**
  String plantBusErrors(String rate);

  /// Datenexport: Titel
  ///
  /// In de, this message translates to:
  /// **'Datenexport'**
  String get dataExportTitle;

  /// Datenexport: Werkzeugliste
  ///
  /// In de, this message translates to:
  /// **'Zähler und Werte nach InfluxDB oder Prometheus, mit Grafana-Vorlage'**
  String get dataExportTool;

  /// Datenexport: Einleitung
  ///
  /// In de, this message translates to:
  /// **'Für den eigenen Grafana-Server. Standard aus. Es geht nur etwas hinaus, wenn du unten ein Ziel einträgst; Prometheus ruft nur aus dem lokalen Netz und mit Token ab.'**
  String get dataExportIntro;

  /// Abschnitt des Datenexports über den Schaltern für Prometheus und InfluxDB
  ///
  /// In de, this message translates to:
  /// **'Zähler und Werte'**
  String get dataExportMetrics;

  /// Datenexport: Schalter
  ///
  /// In de, this message translates to:
  /// **'Auch Adressen, Namen und Werte'**
  String get dataExportValues;

  /// Datenexport: Hinweis
  ///
  /// In de, this message translates to:
  /// **'Sonst nur Zähler des Busses. Mit diesem Schalter landen Namen und Messwerte der Anlage in der Datenbank.'**
  String get dataExportValuesHint;

  /// Datenexport: Schalter
  ///
  /// In de, this message translates to:
  /// **'Prometheus (Abruf)'**
  String get dataExportPrometheus;

  /// Datenexport: Feld
  ///
  /// In de, this message translates to:
  /// **'Port'**
  String get dataExportPort;

  /// Datenexport: Hinweis
  ///
  /// In de, this message translates to:
  /// **'Zugangstoken gespeichert; es wird nicht noch einmal angezeigt.'**
  String get dataExportTokenSet;

  /// Datenexport: Dialog
  ///
  /// In de, this message translates to:
  /// **'Token für Prometheus'**
  String get dataExportTokenTitle;

  /// Datenexport: Dialog
  ///
  /// In de, this message translates to:
  /// **'Einmalig angezeigt. In Prometheus unter „authorization: credentials“ eintragen.'**
  String get dataExportTokenBody;

  /// Datenexport: Knopf
  ///
  /// In de, this message translates to:
  /// **'Kopieren'**
  String get dataExportCopy;

  /// Datenexport: Knopf
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get dataExportClose;

  /// Datenexport: Schalter
  ///
  /// In de, this message translates to:
  /// **'InfluxDB (Senden)'**
  String get dataExportInflux;

  /// Datenexport: Feld
  ///
  /// In de, this message translates to:
  /// **'Adresse'**
  String get dataExportInfluxUrl;

  /// Datenexport: Feld
  ///
  /// In de, this message translates to:
  /// **'Organisation (InfluxDB 2)'**
  String get dataExportInfluxOrg;

  /// Datenexport: Feld
  ///
  /// In de, this message translates to:
  /// **'Bucket (InfluxDB 2)'**
  String get dataExportInfluxBucket;

  /// Datenexport: Feld
  ///
  /// In de, this message translates to:
  /// **'Datenbank (InfluxDB 1)'**
  String get dataExportInfluxDatabase;

  /// Datenexport: Feld
  ///
  /// In de, this message translates to:
  /// **'Zugangstoken'**
  String get dataExportInfluxToken;

  /// Datenexport: Hinweis, wenn das InfluxDB-Token über http:// gesendet wird
  ///
  /// In de, this message translates to:
  /// **'Über http:// geht das Token unverschlüsselt durchs Netz. Im eigenen Heimnetz ist das üblich; führt der Weg nach draußen, eine https://-Adresse verwenden.'**
  String get dataExportInfluxPlain;

  /// Datenexport: Feld
  ///
  /// In de, this message translates to:
  /// **'Sendetakt in Sekunden'**
  String get dataExportInterval;

  /// Datenexport: Knopf
  ///
  /// In de, this message translates to:
  /// **'Verbindung testen'**
  String get dataExportTest;

  /// Datenexport: Meldung
  ///
  /// In de, this message translates to:
  /// **'Testzeile angekommen.'**
  String get dataExportTestOk;

  /// Datenexport: Knopf
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get dataExportSave;

  /// Datenexport: Kennung
  ///
  /// In de, this message translates to:
  /// **'Grafana-Vorlage'**
  String get dataExportGrafana;

  /// Datenexport: Hinweis
  ///
  /// In de, this message translates to:
  /// **'In Grafana unter Dashboards › Importieren laden und die Datenquelle wählen.'**
  String get dataExportGrafanaHint;

  /// Datenexport: Knopf
  ///
  /// In de, this message translates to:
  /// **'Für Prometheus speichern'**
  String get dataExportGrafanaPrometheus;

  /// Datenexport: Knopf
  ///
  /// In de, this message translates to:
  /// **'Für InfluxDB speichern'**
  String get dataExportGrafanaInflux;

  /// Datenexport: Fehler
  ///
  /// In de, this message translates to:
  /// **'Der Port ist belegt. Bitte einen anderen wählen.'**
  String get dataExportBindError;

  /// Datenexport: Hinweis
  ///
  /// In de, this message translates to:
  /// **'Erreichbar unter http://<Adresse>:{port}/metrics'**
  String dataExportPortHint(String port);

  /// Pro Team (hinter BETRIEB)
  ///
  /// In de, this message translates to:
  /// **'Betrieb'**
  String get teamTitle;

  /// Pro Team (hinter BETRIEB)
  ///
  /// In de, this message translates to:
  /// **'Meister fragen'**
  String get teamAskTitle;

  /// Pro Team (hinter BETRIEB)
  ///
  /// In de, this message translates to:
  /// **'Geprüft von: {name}, {date}'**
  String teamPdfChecked(String name, String date);

  /// Pro Team (hinter BETRIEB)
  ///
  /// In de, this message translates to:
  /// **'Abgenommen von: {name}, {date}'**
  String teamPdfApproved(String name, String date);

  /// Zweite Rückfrage
  ///
  /// In de, this message translates to:
  /// **'„{name}“ wirklich endgültig löschen?'**
  String installationDeleteSureTitle(String name);

  /// Zweite Rückfrage
  ///
  /// In de, this message translates to:
  /// **'Das lässt sich nicht rückgängig machen. Unterschriebene Abnahmeprotokolle und Serviceberichte, Kundendaten, Besuchsverlauf, Fotos, ETS-Projekt, Keyring und Langzeitverlauf sind danach auf diesem Gerät unwiederbringlich weg. Sichere vorher, was du als Nachweis brauchst.'**
  String get installationDeleteSureBody;

  /// Knopf
  ///
  /// In de, this message translates to:
  /// **'Endgültig löschen'**
  String get installationDeleteSureConfirm;

  /// No description provided for @appLockSettings.
  ///
  /// In de, this message translates to:
  /// **'App-Sperre'**
  String get appLockSettings;

  /// No description provided for @appLockExplain.
  ///
  /// In de, this message translates to:
  /// **'Schützt die App, falls das Gerät verloren geht oder gestohlen wird: Beim Start und nach der gewählten Zeit im Hintergrund muss sich jemand ausweisen. Der Bus läuft währenddessen weiter.'**
  String get appLockExplain;

  /// No description provided for @appLockTitle.
  ///
  /// In de, this message translates to:
  /// **'Busclear ist gesperrt'**
  String get appLockTitle;

  /// No description provided for @appLockReason.
  ///
  /// In de, this message translates to:
  /// **'Busclear entsperren'**
  String get appLockReason;

  /// No description provided for @appLockSystemHint.
  ///
  /// In de, this message translates to:
  /// **'Mit Face ID, Fingerabdruck, Windows Hello oder dem Gerätecode entsperren.'**
  String get appLockSystemHint;

  /// No description provided for @appLockPasswordHint.
  ///
  /// In de, this message translates to:
  /// **'Mit dem App-Passwort entsperren.'**
  String get appLockPasswordHint;

  /// No description provided for @appLockPassword.
  ///
  /// In de, this message translates to:
  /// **'App-Passwort'**
  String get appLockPassword;

  /// No description provided for @appLockUnlock.
  ///
  /// In de, this message translates to:
  /// **'Entsperren'**
  String get appLockUnlock;

  /// No description provided for @appLockWrong.
  ///
  /// In de, this message translates to:
  /// **'Das hat nicht geklappt. Nach mehreren Fehlversuchen musst du warten.'**
  String get appLockWrong;

  /// No description provided for @appLockForgot.
  ///
  /// In de, this message translates to:
  /// **'Passwort vergessen'**
  String get appLockForgot;

  /// No description provided for @appLockForgotTitle.
  ///
  /// In de, this message translates to:
  /// **'Passwort vergessen?'**
  String get appLockForgotTitle;

  /// No description provided for @appLockForgotBody.
  ///
  /// In de, this message translates to:
  /// **'Das App-Passwort lässt sich nicht zurücksetzen, sonst wäre die Sperre wertlos. Du kannst nur alle Daten der App auf diesem Gerät löschen: Projekte, Aufnahmen, Kundendaten und Schlüssel.'**
  String get appLockForgotBody;

  /// No description provided for @appLockForgotBodyTeam.
  ///
  /// In de, this message translates to:
  /// **'Das App-Passwort lässt sich nicht zurücksetzen, sonst wäre die Sperre wertlos. Du kannst nur alle Daten der App auf diesem Gerät löschen: Projekte, Aufnahmen, Kundendaten, Schlüssel und die Anmeldung.'**
  String get appLockForgotBodyTeam;

  /// No description provided for @appLockForgotContinue.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get appLockForgotContinue;

  /// No description provided for @appLockForgotSureTitle.
  ///
  /// In de, this message translates to:
  /// **'Wirklich alles löschen?'**
  String get appLockForgotSureTitle;

  /// No description provided for @appLockForgotSureBody.
  ///
  /// In de, this message translates to:
  /// **'Das lässt sich nicht rückgängig machen. Zurück kommt nur, was in einer eigenen Sicherung liegt. Die App beendet sich danach.'**
  String get appLockForgotSureBody;

  /// No description provided for @appLockForgotSureBodyTeam.
  ///
  /// In de, this message translates to:
  /// **'Das lässt sich nicht rückgängig machen. Zurück kommt nur, was in deinem Konto, deinem Betrieb oder einer eigenen Sicherung liegt. Die App beendet sich danach.'**
  String get appLockForgotSureBodyTeam;

  /// No description provided for @appLockForgotConfirm.
  ///
  /// In de, this message translates to:
  /// **'Alles löschen'**
  String get appLockForgotConfirm;

  /// No description provided for @appLockRequiredTitle.
  ///
  /// In de, this message translates to:
  /// **'Sperre einrichten'**
  String get appLockRequiredTitle;

  /// No description provided for @appLockRequiredBody.
  ///
  /// In de, this message translates to:
  /// **'Du arbeitest in einem Betrieb und hast Kundendaten auf dem Gerät. Darum braucht die App eine Sperre.'**
  String get appLockRequiredBody;

  /// No description provided for @appLockRequiredNote.
  ///
  /// In de, this message translates to:
  /// **'Dein Betrieb verlangt die Sperre, solange du Mitglied bist.'**
  String get appLockRequiredNote;

  /// No description provided for @appLockUseSystem.
  ///
  /// In de, this message translates to:
  /// **'Gerätesperre nutzen'**
  String get appLockUseSystem;

  /// No description provided for @appLockSystemFailed.
  ///
  /// In de, this message translates to:
  /// **'Die Gerätesperre hat nicht bestätigt. Versuch es erneut oder nimm ein App-Passwort.'**
  String get appLockSystemFailed;

  /// No description provided for @appLockNewPassword.
  ///
  /// In de, this message translates to:
  /// **'Neues App-Passwort'**
  String get appLockNewPassword;

  /// No description provided for @appLockRepeatPassword.
  ///
  /// In de, this message translates to:
  /// **'App-Passwort wiederholen'**
  String get appLockRepeatPassword;

  /// No description provided for @appLockUsePassword.
  ///
  /// In de, this message translates to:
  /// **'App-Passwort nutzen'**
  String get appLockUsePassword;

  /// No description provided for @appLockPasswordWarning.
  ///
  /// In de, this message translates to:
  /// **'Das App-Passwort kann niemand zurücksetzen. Dafür bekommst du gleich einen Notfallschlüssel. Fehlen beide, bleibt nur, die Daten der App auf diesem Gerät zu löschen.'**
  String get appLockPasswordWarning;

  /// No description provided for @appLockActiveSystem.
  ///
  /// In de, this message translates to:
  /// **'Eingeschaltet, mit der Gerätesperre.'**
  String get appLockActiveSystem;

  /// No description provided for @appLockActivePassword.
  ///
  /// In de, this message translates to:
  /// **'Eingeschaltet, mit dem App-Passwort.'**
  String get appLockActivePassword;

  /// No description provided for @appLockTimeout.
  ///
  /// In de, this message translates to:
  /// **'Sperren nach'**
  String get appLockTimeout;

  /// No description provided for @appLockTimeoutNow.
  ///
  /// In de, this message translates to:
  /// **'Sofort'**
  String get appLockTimeoutNow;

  /// No description provided for @appLockOff.
  ///
  /// In de, this message translates to:
  /// **'Sperre ausschalten'**
  String get appLockOff;

  /// No description provided for @appLockMismatch.
  ///
  /// In de, this message translates to:
  /// **'Die beiden Passwörter stimmen nicht überein.'**
  String get appLockMismatch;

  /// No description provided for @appLockTooShort.
  ///
  /// In de, this message translates to:
  /// **'Mindestens {count} Zeichen.'**
  String appLockTooShort(int count);

  /// No description provided for @appLockTimeoutMinutes.
  ///
  /// In de, this message translates to:
  /// **'{count} Min.'**
  String appLockTimeoutMinutes(int count);

  /// No description provided for @backupTitle.
  ///
  /// In de, this message translates to:
  /// **'Sicherung'**
  String get backupTitle;

  /// No description provided for @backupExplain.
  ///
  /// In de, this message translates to:
  /// **'Speichert alles von diesem Gerät in eine Datei mit eigenem Passwort: Anlagen, Projekte, Keyrings, Kundenakte, Kommentare, Aufnahmen und Verlauf. Das Format ist offen beschrieben. Ohne das Passwort kommt niemand an die Datei, auch wir nicht. Bitte regelmäßig sichern und an einem anderen Ort aufbewahren.'**
  String get backupExplain;

  /// No description provided for @backupCreate.
  ///
  /// In de, this message translates to:
  /// **'Sicherung erstellen'**
  String get backupCreate;

  /// No description provided for @backupRestore.
  ///
  /// In de, this message translates to:
  /// **'Sicherung einspielen'**
  String get backupRestore;

  /// No description provided for @backupPassword.
  ///
  /// In de, this message translates to:
  /// **'Passwort der Sicherung'**
  String get backupPassword;

  /// No description provided for @backupRepeat.
  ///
  /// In de, this message translates to:
  /// **'Passwort wiederholen'**
  String get backupRepeat;

  /// No description provided for @backupTooShort.
  ///
  /// In de, this message translates to:
  /// **'Mindestens {count} Zeichen.'**
  String backupTooShort(int count);

  /// No description provided for @backupMismatch.
  ///
  /// In de, this message translates to:
  /// **'Die beiden Passwörter stimmen nicht überein.'**
  String get backupMismatch;

  /// No description provided for @backupSaved.
  ///
  /// In de, this message translates to:
  /// **'Sicherung gespeichert.'**
  String get backupSaved;

  /// No description provided for @backupRestoreTitle.
  ///
  /// In de, this message translates to:
  /// **'Sicherung einspielen?'**
  String get backupRestoreTitle;

  /// No description provided for @backupRestoreBody.
  ///
  /// In de, this message translates to:
  /// **'Dateien mit demselben Namen werden ersetzt. Die App beendet sich danach und ist beim nächsten Start auf dem Stand der Sicherung.'**
  String get backupRestoreBody;

  /// No description provided for @backupOpenFailed.
  ///
  /// In de, this message translates to:
  /// **'Das hat nicht geklappt: falsches Passwort oder keine gültige Sicherung.'**
  String get backupOpenFailed;

  /// No description provided for @backupNewer.
  ///
  /// In de, this message translates to:
  /// **'Diese Sicherung stammt aus einer neueren Version. Bitte zuerst die App aktualisieren.'**
  String get backupNewer;

  /// No description provided for @backupNotIncluded.
  ///
  /// In de, this message translates to:
  /// **'Nicht enthalten: die App-Sperre und der Verlauf auf einer Box.'**
  String get backupNotIncluded;

  /// No description provided for @backupNotIncludedTeam.
  ///
  /// In de, this message translates to:
  /// **'Nicht enthalten: die Anmeldung, die App-Sperre, die Schlüssel eines Betriebs und der Verlauf auf einer Box.'**
  String get backupNotIncludedTeam;

  /// No description provided for @recoveryTitle.
  ///
  /// In de, this message translates to:
  /// **'Notfallschlüssel'**
  String get recoveryTitle;

  /// No description provided for @recoveryUse.
  ///
  /// In de, this message translates to:
  /// **'Notfallschlüssel eingeben'**
  String get recoveryUse;

  /// No description provided for @recoveryExplain.
  ///
  /// In de, this message translates to:
  /// **'Damit kommst du in die App, falls du das App-Passwort vergisst. Bitte außerhalb dieses Geräts aufbewahren, zum Beispiel ausgedruckt oder im Passwortmanager.'**
  String get recoveryExplain;

  /// No description provided for @recoverySavePdf.
  ///
  /// In de, this message translates to:
  /// **'Als PDF speichern'**
  String get recoverySavePdf;

  /// No description provided for @recoveryNoted.
  ///
  /// In de, this message translates to:
  /// **'Sicher notiert'**
  String get recoveryNoted;

  /// No description provided for @recoveryRenew.
  ///
  /// In de, this message translates to:
  /// **'Neuen Notfallschlüssel erstellen'**
  String get recoveryRenew;

  /// No description provided for @recoveryResetBody.
  ///
  /// In de, this message translates to:
  /// **'Der Notfallschlüssel hat die App geöffnet und gilt nun nicht mehr. Lege eine neue Sperre fest.'**
  String get recoveryResetBody;

  /// No description provided for @recoveryPdfIntro.
  ///
  /// In de, this message translates to:
  /// **'Dieser Schlüssel öffnet die App-Sperre von Busclear, wenn das App-Passwort vergessen wurde.'**
  String get recoveryPdfIntro;

  /// No description provided for @recoveryPdfAccount.
  ///
  /// In de, this message translates to:
  /// **'Konto: {email}'**
  String recoveryPdfAccount(String email);

  /// No description provided for @recoveryPdfUse.
  ///
  /// In de, this message translates to:
  /// **'So geht es: Auf dem Sperrbildschirm „Notfallschlüssel eingeben“ wählen, den Schlüssel eintippen und ein neues Passwort festlegen. Danach gilt dieser Schlüssel nicht mehr; die App erstellt einen neuen.'**
  String get recoveryPdfUse;

  /// No description provided for @recoveryPdfLimits.
  ///
  /// In de, this message translates to:
  /// **'Der Schlüssel gilt nur für dieses Gerät. Er öffnet keine Sicherungsdatei und ersetzt keine Sicherung, falls das Gerät verloren geht.'**
  String get recoveryPdfLimits;

  /// No description provided for @recoveryPdfLimitsTeam.
  ///
  /// In de, this message translates to:
  /// **'Der Schlüssel gilt nur für dieses Gerät. Er öffnet weder dein Konto noch eine Sicherungsdatei und ersetzt keine Sicherung, falls das Gerät verloren geht.'**
  String get recoveryPdfLimitsTeam;

  /// No description provided for @recoveryPdfKeep.
  ///
  /// In de, this message translates to:
  /// **'Wer dieses Blatt und das Gerät zusammen hat, kommt in die App. Bewahre es getrennt vom Gerät auf.'**
  String get recoveryPdfKeep;

  /// No description provided for @appLockWait.
  ///
  /// In de, this message translates to:
  /// **'Zu viele Fehlversuche. Noch {seconds} Sekunden warten, dann geht es weiter.'**
  String appLockWait(int seconds);

  /// No description provided for @customerPdf.
  ///
  /// In de, this message translates to:
  /// **'Akte als PDF'**
  String get customerPdf;

  /// Inhalt des Pakets: was nicht gefiltert wird
  ///
  /// In de, this message translates to:
  /// **'Nicht gefiltert: Telegrammwerte (können verraten, wann jemand zu Hause ist), Namen von Gruppenadressen und Geräten, solange der Schalter an ist, sowie Namen, die du selbst in Beschreibung oder Kommentare tippst.'**
  String get diagNotFiltered;

  /// Schalter: Screenshots ins Diagnosepaket
  ///
  /// In de, this message translates to:
  /// **'Screenshots mitsenden'**
  String get diagShotsTitle;

  /// Hinweis zum Schalter
  ///
  /// In de, this message translates to:
  /// **'Bilder werden nicht gefiltert: Alles, was darauf zu sehen ist, geht an den Empfänger, auch Namen, Adressen und Kundendaten. Sieh sie dir vorher an.'**
  String get diagShotsHint;

  /// Inhalt des Pakets
  ///
  /// In de, this message translates to:
  /// **'Screenshots: {count} vorhanden, nicht enthalten'**
  String diagContentShotsOut(int count);

  /// No description provided for @historyWithoutTime.
  ///
  /// In de, this message translates to:
  /// **'Ohne Uhrzeit'**
  String get historyWithoutTime;

  /// No description provided for @historyWithoutTimeHint.
  ///
  /// In de, this message translates to:
  /// **'Die Box kannte die Uhrzeit nicht und ist neu gestartet. Reihenfolge und Abstände stimmen, Datum und Uhrzeit nicht.'**
  String get historyWithoutTimeHint;

  /// No description provided for @installationRecovered.
  ///
  /// In de, this message translates to:
  /// **'Anlage wiederhergestellt'**
  String get installationRecovered;

  /// No description provided for @errorNetworkGone.
  ///
  /// In de, this message translates to:
  /// **'Das Netzwerk ist weg oder hat gewechselt.'**
  String get errorNetworkGone;

  /// No description provided for @boxShareDiffersTitle.
  ///
  /// In de, this message translates to:
  /// **'Andere Daten auf der Box'**
  String get boxShareDiffersTitle;

  /// No description provided for @boxShareDiffersBody.
  ///
  /// In de, this message translates to:
  /// **'Projekt oder Keyring auf der Box unterscheiden sich von diesem Gerät, und wir wissen nicht, welcher Stand neuer ist. Solange sie sich unterscheiden, entschlüsselt und benennt die Box mit ihrem eigenen Stand.'**
  String get boxShareDiffersBody;

  /// No description provided for @boxShareKeep.
  ///
  /// In de, this message translates to:
  /// **'Box behalten'**
  String get boxShareKeep;

  /// No description provided for @boxShareReplace.
  ///
  /// In de, this message translates to:
  /// **'Von diesem Gerät übernehmen'**
  String get boxShareReplace;

  /// No description provided for @backupEstimate.
  ///
  /// In de, this message translates to:
  /// **'Daten dieses Geräts: etwa {size}.'**
  String backupEstimate(String size);

  /// No description provided for @backupTooLarge.
  ///
  /// In de, this message translates to:
  /// **'Die Daten sind mit {size} zu groß für eine Sicherung am Stück (höchstens {limit}). Es wurde nichts gespeichert. Bitte alte Aufnahmen oder Verlaufstage löschen oder die Aufbewahrung verkürzen.'**
  String backupTooLarge(String size, String limit);

  /// Pro Team, Konto oder Sicherung
  ///
  /// In de, this message translates to:
  /// **'Anmeldeschlüssel für die Authenticator-App'**
  String get accountMfaPdfTitle;

  /// Pro Team, Konto oder Sicherung
  ///
  /// In de, this message translates to:
  /// **'Mit diesem Blatt bekommst du die Anmeldecodes für dein Busclear-Konto zurück, wenn dein Telefon weg ist.'**
  String get accountMfaPdfIntro;

  /// Pro Team, Konto oder Sicherung
  ///
  /// In de, this message translates to:
  /// **'So geht es: Neue Authenticator-App installieren, Konto hinzufügen, den QR-Code scannen oder den Schlüssel eintippen. Die App zeigt dann wieder die sechsstelligen Codes.'**
  String get accountMfaPdfUse;

  /// Pro Team, Konto oder Sicherung
  ///
  /// In de, this message translates to:
  /// **'Wer dieses Blatt hat, kann sich die Codes selbst erzeugen. Wegschließen wie einen Hausschlüssel, nicht fotografieren und nicht in die Cloud legen. Hast du den Zugang neu eingerichtet, entferne im Konto die alte App: Dann ist dieses Blatt wertlos.'**
  String get accountMfaPdfWarning;

  /// Pro Team, Konto oder Sicherung
  ///
  /// In de, this message translates to:
  /// **'Deine letzte Sicherung ist über 30 Tage her oder fehlt noch. Kundenakten und Anlagen liegen nur auf diesem Gerät.'**
  String get backupReminder;

  /// Pro Team, Konto oder Sicherung
  ///
  /// In de, this message translates to:
  /// **'Jetzt sichern'**
  String get backupReminderOpen;

  /// Pro Team, Konto oder Sicherung
  ///
  /// In de, this message translates to:
  /// **'Später'**
  String get backupReminderDismiss;

  /// Pro Team, Konto oder Sicherung
  ///
  /// In de, this message translates to:
  /// **'Letzte Sicherung auf diesem Gerät: {date}'**
  String backupLast(String date);

  /// Pro Team, Konto oder Sicherung
  ///
  /// In de, this message translates to:
  /// **'Von diesem Gerät gibt es noch keine Sicherung.'**
  String get backupNever;

  /// No description provided for @backupSlow.
  ///
  /// In de, this message translates to:
  /// **'Das Verschlüsseln kann auf älteren Geräten bis zu einer Minute dauern.'**
  String get backupSlow;

  /// No description provided for @zipTooLarge.
  ///
  /// In de, this message translates to:
  /// **'Die Datei ist ausgepackt zu groß und wurde nicht geöffnet.'**
  String get zipTooLarge;

  /// No description provided for @installationsNewerTitle.
  ///
  /// In de, this message translates to:
  /// **'Neuere Daten'**
  String get installationsNewerTitle;

  /// No description provided for @installationsNewerBody.
  ///
  /// In de, this message translates to:
  /// **'Diese Daten stammen aus einer neueren Version von Busclear. Bitte aktualisiere die App. Deine Daten bleiben unverändert.'**
  String get installationsNewerBody;

  /// No description provided for @quarantineTitle.
  ///
  /// In de, this message translates to:
  /// **'Alte Daten nicht lesbar'**
  String get quarantineTitle;

  /// No description provided for @quarantineBody.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Eine Datei ({size}) lässt} other{{count} Dateien ({size}) lassen}} sich nicht öffnen, weil der Schlüssel auf diesem Gerät fehlt, zum Beispiel nach einem Gerätewechsel. Es bleibt alles auf dem Gerät. Mit einer Sicherung holst du die Daten zurück.'**
  String quarantineBody(int count, String size);

  /// No description provided for @quarantineRestore.
  ///
  /// In de, this message translates to:
  /// **'Aus Sicherung wiederherstellen'**
  String get quarantineRestore;

  /// No description provided for @quarantineDelete.
  ///
  /// In de, this message translates to:
  /// **'Dateien löschen'**
  String get quarantineDelete;

  /// No description provided for @quarantineDeleteBody.
  ///
  /// In de, this message translates to:
  /// **'Diese Dateien lassen sich danach nie wieder öffnen.'**
  String get quarantineDeleteBody;

  /// No description provided for @boxForeignTitle.
  ///
  /// In de, this message translates to:
  /// **'Diese Box ist nicht im lokalen Netz'**
  String get boxForeignTitle;

  /// No description provided for @boxForeignBody.
  ///
  /// In de, this message translates to:
  /// **'Der Link führt zu {address}. Das ist keine Adresse im lokalen Netz. Wer diesen Server betreibt, bekommt dein ETS-Projekt mit allen Adressen und Namen. Verbinde dich nur, wenn du ihn selbst betreibst.'**
  String boxForeignBody(String address);

  /// No description provided for @boxForeignConfirm.
  ///
  /// In de, this message translates to:
  /// **'Trotzdem verbinden'**
  String get boxForeignConfirm;

  /// No description provided for @boxKeyringTitle.
  ///
  /// In de, this message translates to:
  /// **'KNX-Secure-Schlüssel auf diese Box geben?'**
  String get boxKeyringTitle;

  /// No description provided for @boxKeyringBody.
  ///
  /// In de, this message translates to:
  /// **'Die Box unter {address} bekäme die Schlüssel und Passwörter deiner KNX-Secure-Anlage (Keyring, IP-Secure-Zugang zum Gateway), damit sie sich verbindet und gesicherte Telegramme lesbar aufzeichnet. Wer Zugriff auf die Box hat, kommt an diese Schlüssel. Stimme nur zu, wenn es deine Box ist.'**
  String boxKeyringBody(String address);

  /// No description provided for @boxKeyringAllow.
  ///
  /// In de, this message translates to:
  /// **'Schlüssel geben'**
  String get boxKeyringAllow;

  /// No description provided for @boxKeyringDeny.
  ///
  /// In de, this message translates to:
  /// **'Nicht geben'**
  String get boxKeyringDeny;

  /// No description provided for @historyPausedPlan.
  ///
  /// In de, this message translates to:
  /// **'Der Verlauf ist pausiert: Langzeitverlauf gehört zu Plus. Neue Telegramme werden nicht gespeichert, vorhandene Tage bleiben erhalten.'**
  String get historyPausedPlan;

  /// No description provided for @backupSideFiles.
  ///
  /// In de, this message translates to:
  /// **'Ältere und beschädigte Fassungen belegen zusätzlich {size}.'**
  String backupSideFiles(String size);

  /// No description provided for @appLockHideTitle.
  ///
  /// In de, this message translates to:
  /// **'Im App-Umschalter verbergen'**
  String get appLockHideTitle;

  /// No description provided for @appLockHideHint.
  ///
  /// In de, this message translates to:
  /// **'Android zeigt dann im App-Umschalter ein leeres Bild, und Screenshots der App gehen nicht mehr.'**
  String get appLockHideHint;

  /// No description provided for @faultShotsLeftOut.
  ///
  /// In de, this message translates to:
  /// **'Screenshots an Kommentaren ({count}) bleiben ohne den Schalter draußen.'**
  String faultShotsLeftOut(int count);

  /// Titel, wenn die Box vor allem anderen ein eigenes Passwort verlangt
  ///
  /// In de, this message translates to:
  /// **'Eigenes Box-Passwort setzen'**
  String get boxPasswordMustTitle;

  /// Die Box lässt nichts zu, solange das Passwort vom Aufkleber gilt
  ///
  /// In de, this message translates to:
  /// **'Erst ein eigenes Box-Passwort setzen. Das vom Aufkleber kann jeder lesen, der die Box sieht.'**
  String get boxPasswordRequired;

  /// Hinweis in den Box-Einstellungen
  ///
  /// In de, this message translates to:
  /// **'Es gilt noch das Passwort vom Aufkleber. Wer es hat, kann die Box steuern und den Keyring lesen. Setze unten ein eigenes; es verschwindet dann von der SD-Karte.'**
  String get boxPasswordStillSticker;

  /// Warnung bei HTTP außerhalb des Box-WLANs, Box ohne Zertifikat
  ///
  /// In de, this message translates to:
  /// **'Unverschlüsselt: Diese Verbindung läuft über dein Netz im Klartext, auch der Gerätezugang und die Telegramme. Am besten im WLAN der Box bleiben.'**
  String get boxPlainWarning;

  /// Warnung bei HTTP außerhalb des Box-WLANs, Box hat ein Zertifikat
  ///
  /// In de, this message translates to:
  /// **'Unverschlüsselt: Diese Verbindung läuft über dein Netz im Klartext. Die Box kann HTTPS: Auf ihrer Seite /pair einen neuen QR-Code erzeugen und scannen, dann ist die Verbindung verschlüsselt.'**
  String get boxPlainWarningTls;

  /// Abschnitt und Knopf in den Box-Einstellungen
  ///
  /// In de, this message translates to:
  /// **'WLAN-Passwort ändern'**
  String get boxWifiChange;

  /// Hilfetext zum WLAN-Passwort
  ///
  /// In de, this message translates to:
  /// **'8 bis 63 Zeichen ohne Leerzeichen und ohne \" \' \\ \$ `. Der WLAN-Code des Aufklebers gilt danach nicht mehr.'**
  String get boxWifiHint;

  /// Rückfrage vor dem Ändern des WLAN-Passworts
  ///
  /// In de, this message translates to:
  /// **'Alle Geräte fliegen aus dem WLAN der Box und müssen mit dem neuen Passwort wieder beitreten. Dieses Gerät macht das selbst, soweit das System es erlaubt.'**
  String get boxWifiConfirm;

  /// Bestätigung
  ///
  /// In de, this message translates to:
  /// **'WLAN-Passwort geändert. Die Box startet ihr WLAN gleich neu.'**
  String get boxWifiChanged;

  /// Warnung, wenn die Aufzeichnung wegen wenig Platz angehalten ist
  ///
  /// In de, this message translates to:
  /// **'Speicher voll: Die Box zeichnet gerade nicht auf. Ältere Tage sind schon gelöscht. Platz schaffen oder Aufbewahrung verkürzen, dann läuft es von selbst weiter.'**
  String get boxLowSpace;

  /// Cloud sync between own devices.
  ///
  /// In de, this message translates to:
  /// **'Abgleich zwischen deinen Geräten'**
  String get cloudSyncFeature;

  /// Cloud sync between own devices.
  ///
  /// In de, this message translates to:
  /// **'Geräte abgleichen'**
  String get cloudSyncTitle;

  /// Hausplan
  ///
  /// In de, this message translates to:
  /// **'Hausplan'**
  String get hpTitle;

  /// Hausplan
  ///
  /// In de, this message translates to:
  /// **'Haus planen'**
  String get hpEntry;

  /// Hinweis vor dem Schreiben
  ///
  /// In de, this message translates to:
  /// **'Eingriff in die Anlage'**
  String get writeNoticeTitle;

  /// Hinweis vor dem Schreiben, Entwurf, rechtlich nicht geprüft
  ///
  /// In de, this message translates to:
  /// **'Dieser Wert geht auf den Bus und kann echte Geräte schalten. Für den Schaltvorgang und seine Folgen bist du verantwortlich. Wir übernehmen dafür keine Haftung, außer wo das Gesetz sie zwingend vorschreibt.'**
  String get writeNoticeBody;

  /// Hinweis vor dem Schreiben
  ///
  /// In de, this message translates to:
  /// **'Nicht mehr anzeigen'**
  String get writeNoticeHide;

  /// Hinweis vor dem Schreiben
  ///
  /// In de, this message translates to:
  /// **'Das Ausblenden steht mit Datum in Diagnosepaketen und Fehlerberichten.'**
  String get writeNoticeHideHint;

  /// Hinweis vor dem Schreiben
  ///
  /// In de, this message translates to:
  /// **'Schreiben'**
  String get writeNoticeConfirm;

  /// Startseite, nur wenn ausgeblendet
  ///
  /// In de, this message translates to:
  /// **'Hinweis vor dem Schreiben wieder anzeigen'**
  String get writeNoticeRestore;

  /// Diagnosepaket
  ///
  /// In de, this message translates to:
  /// **'Hinweis vor dem Schreiben: ausgeblendet am {date}'**
  String diagContentWriteNotice(String date);

  /// Rechtsklick-Menü auf einem Telegramm
  ///
  /// In de, this message translates to:
  /// **'Details öffnen'**
  String get telegramMenuDetails;

  /// Rechtsklick-Menü auf einem Telegramm: Auswahl beginnen
  ///
  /// In de, this message translates to:
  /// **'Auswählen'**
  String get telegramMenuSelect;

  /// QR-Scanner: Kamerazugriff abgelehnt
  ///
  /// In de, this message translates to:
  /// **'Kamera nicht freigegeben. Erlaube sie in den Einstellungen des Geräts, oder gib die Angaben von Hand ein.'**
  String get scanCameraDenied;

  /// No description provided for @backupShort.
  ///
  /// In de, this message translates to:
  /// **'Alles von diesem Gerät in einer Datei mit eigenem Passwort.'**
  String get backupShort;

  /// No description provided for @backupAppStorage.
  ///
  /// In de, this message translates to:
  /// **'Speicher der App'**
  String get backupAppStorage;

  /// No description provided for @backupPrevious.
  ///
  /// In de, this message translates to:
  /// **'Vorige Fassungen'**
  String get backupPrevious;

  /// No description provided for @backupLastRow.
  ///
  /// In de, this message translates to:
  /// **'Letzte Sicherung'**
  String get backupLastRow;

  /// No description provided for @backupNoneYet.
  ///
  /// In de, this message translates to:
  /// **'Noch keine'**
  String get backupNoneYet;

  /// Sicherung im breiten Fenster: Abschnitt mit Passwort, Erstellen und Einspielen
  ///
  /// In de, this message translates to:
  /// **'Sicherungsdatei'**
  String get backupFileHead;

  /// Sicherung im breiten Fenster: Abschnitt mit Speicher und letzter Sicherung
  ///
  /// In de, this message translates to:
  /// **'Auf diesem Gerät'**
  String get backupDeviceHead;

  /// No description provided for @appLockMethodSystem.
  ///
  /// In de, this message translates to:
  /// **'Face ID, Fingerabdruck oder Gerätecode'**
  String get appLockMethodSystem;

  /// No description provided for @appLockMethodPassword.
  ///
  /// In de, this message translates to:
  /// **'Mit dem App-Passwort'**
  String get appLockMethodPassword;

  /// No description provided for @lessonsLessons.
  ///
  /// In de, this message translates to:
  /// **'Lektionen'**
  String get lessonsLessons;

  /// No description provided for @lessonsKind.
  ///
  /// In de, this message translates to:
  /// **'Kurz erklärt'**
  String get lessonsKind;

  /// No description provided for @lessonsPractice.
  ///
  /// In de, this message translates to:
  /// **'Üben'**
  String get lessonsPractice;

  /// No description provided for @lessonsTermCount.
  ///
  /// In de, this message translates to:
  /// **'{count} Begriffe'**
  String lessonsTermCount(int count);

  /// No description provided for @quizMeta.
  ///
  /// In de, this message translates to:
  /// **'Fragen aus deiner Anlage'**
  String get quizMeta;

  /// No description provided for @handoverShort.
  ///
  /// In de, this message translates to:
  /// **'Alles für die App des Kunden in einer Datei.'**
  String get handoverShort;

  /// No description provided for @handoverProject.
  ///
  /// In de, this message translates to:
  /// **'Projekt'**
  String get handoverProject;

  /// No description provided for @customerMaintenance.
  ///
  /// In de, this message translates to:
  /// **'Wartung'**
  String get customerMaintenance;

  /// Kundenakte bearbeiten: Abschnitt mit Wartungsintervall und Notizen
  ///
  /// In de, this message translates to:
  /// **'Wartung und Notizen'**
  String get customerMaintenanceNotes;

  /// No description provided for @customerMaintEvery.
  ///
  /// In de, this message translates to:
  /// **'Alle {count} Monate'**
  String customerMaintEvery(int count);

  /// No description provided for @customerMaintIn.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{In diesem Monat} =1{In 1 Monat} other{In {count} Monaten}}'**
  String customerMaintIn(int count);

  /// No description provided for @customerVisitAdd.
  ///
  /// In de, this message translates to:
  /// **'Besuch eintragen'**
  String get customerVisitAdd;

  /// No description provided for @customerVisits.
  ///
  /// In de, this message translates to:
  /// **'Besuche'**
  String get customerVisits;

  /// No description provided for @customerDocuments.
  ///
  /// In de, this message translates to:
  /// **'Dokumente'**
  String get customerDocuments;

  /// No description provided for @srIncludes.
  ///
  /// In de, this message translates to:
  /// **'Enthält'**
  String get srIncludes;

  /// No description provided for @reactMedian.
  ///
  /// In de, this message translates to:
  /// **'Median'**
  String get reactMedian;

  /// No description provided for @reactSlowest.
  ///
  /// In de, this message translates to:
  /// **'Langsamste'**
  String get reactSlowest;

  /// No description provided for @reactPairs.
  ///
  /// In de, this message translates to:
  /// **'Befehl und Rückmeldung'**
  String get reactPairs;

  /// No description provided for @loadChannelsLabel.
  ///
  /// In de, this message translates to:
  /// **'Kanäle'**
  String get loadChannelsLabel;

  /// No description provided for @loadHighest.
  ///
  /// In de, this message translates to:
  /// **'Höchster Wert'**
  String get loadHighest;

  /// No description provided for @loadConsumers.
  ///
  /// In de, this message translates to:
  /// **'Größte Verbraucher'**
  String get loadConsumers;

  /// No description provided for @hpRoomsOf.
  ///
  /// In de, this message translates to:
  /// **'{shown} von {total}'**
  String hpRoomsOf(int shown, int total);

  /// No description provided for @floorTitle.
  ///
  /// In de, this message translates to:
  /// **'Bus auf dem Grundriss'**
  String get floorTitle;

  /// No description provided for @floorTool.
  ///
  /// In de, this message translates to:
  /// **'Telegramme lassen Punkte auf deinem Grundriss aufleuchten, stumme fallen auf'**
  String get floorTool;

  /// No description provided for @floorPlanTool.
  ///
  /// In de, this message translates to:
  /// **'Geräte im Hausplan mit Gruppenadressen verbinden, Rundgang, Bus auf dem Plan'**
  String get floorPlanTool;

  /// No description provided for @floorEmptyTitle.
  ///
  /// In de, this message translates to:
  /// **'Noch kein Grundriss'**
  String get floorEmptyTitle;

  /// No description provided for @floorEmptyBody.
  ///
  /// In de, this message translates to:
  /// **'Lege eine Ebene an, wähle ein Bild deines Grundrisses und setze Punkte für Leuchten, Taster oder Fühler. Jeder Punkt bekommt seine Gruppenadressen und leuchtet auf, sobald dort ein Telegramm läuft. Die erste Ebene ist in jeder Stufe enthalten.'**
  String get floorEmptyBody;

  /// No description provided for @floorAddLevel.
  ///
  /// In de, this message translates to:
  /// **'Ebene anlegen'**
  String get floorAddLevel;

  /// No description provided for @floorDeleteLevel.
  ///
  /// In de, this message translates to:
  /// **'Ebene löschen'**
  String get floorDeleteLevel;

  /// No description provided for @floorLevelName.
  ///
  /// In de, this message translates to:
  /// **'Name der Ebene'**
  String get floorLevelName;

  /// No description provided for @floorLevelDefault.
  ///
  /// In de, this message translates to:
  /// **'Erdgeschoss'**
  String get floorLevelDefault;

  /// No description provided for @floorPickImage.
  ///
  /// In de, this message translates to:
  /// **'Bild wählen'**
  String get floorPickImage;

  /// No description provided for @floorImageUnreadable.
  ///
  /// In de, this message translates to:
  /// **'Das Bild lässt sich nicht lesen.'**
  String get floorImageUnreadable;

  /// No description provided for @floorEdit.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get floorEdit;

  /// No description provided for @floorEditDone.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get floorEditDone;

  /// No description provided for @floorEditHint.
  ///
  /// In de, this message translates to:
  /// **'Tippe auf den Plan, um einen Punkt zu setzen. Tippe auf einen Punkt, um ihn zu ändern, oder ziehe ihn an seinen Platz.'**
  String get floorEditHint;

  /// No description provided for @floorFromPlan.
  ///
  /// In de, this message translates to:
  /// **'Diese Ansicht stammt aus dem Hausplan. Änderungen machst du dort unter „Nach dem Einzug“.'**
  String get floorFromPlan;

  /// No description provided for @floorTooNew.
  ///
  /// In de, this message translates to:
  /// **'Diese Busansicht stammt aus einer neueren App-Version. Aktualisiere die App, um sie zu öffnen. Die Datei bleibt, wie sie ist.'**
  String get floorTooNew;

  /// No description provided for @floorNoPoints.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Punkte auf dieser Ebene.'**
  String get floorNoPoints;

  /// No description provided for @floorPointName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get floorPointName;

  /// No description provided for @floorPointAddresses.
  ///
  /// In de, this message translates to:
  /// **'Gruppenadressen wählen'**
  String get floorPointAddresses;

  /// No description provided for @floorPickSearch.
  ///
  /// In de, this message translates to:
  /// **'Name oder Adresse'**
  String get floorPickSearch;

  /// No description provided for @floorPickSuggested.
  ///
  /// In de, this message translates to:
  /// **'Vorschlag'**
  String get floorPickSuggested;

  /// No description provided for @floorPickNoCatalog.
  ///
  /// In de, this message translates to:
  /// **'Kein Projekt und keine angelernten Namen. Gib die Adresse oben ein, zum Beispiel 1/2/3.'**
  String get floorPickNoCatalog;

  /// No description provided for @floorStateActive.
  ///
  /// In de, this message translates to:
  /// **'gerade aktiv'**
  String get floorStateActive;

  /// No description provided for @floorStateHeard.
  ///
  /// In de, this message translates to:
  /// **'gehört'**
  String get floorStateHeard;

  /// No description provided for @floorStateSilent.
  ///
  /// In de, this message translates to:
  /// **'lange still'**
  String get floorStateSilent;

  /// No description provided for @floorStateUnlinked.
  ///
  /// In de, this message translates to:
  /// **'ohne Adresse'**
  String get floorStateUnlinked;

  /// No description provided for @floorSilentTitle.
  ///
  /// In de, this message translates to:
  /// **'Lange still'**
  String get floorSilentTitle;

  /// No description provided for @floorSilentSince.
  ///
  /// In de, this message translates to:
  /// **'Seit {since} beobachtet und nichts gehört. Manche Geräte senden nur, wenn man sie bedient.'**
  String floorSilentSince(String since);

  /// No description provided for @floorHeardTitle.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt gehört'**
  String get floorHeardTitle;

  /// No description provided for @floorUnlinkedTitle.
  ///
  /// In de, this message translates to:
  /// **'Ohne Gruppenadresse'**
  String get floorUnlinkedTitle;

  /// No description provided for @floorKindLight.
  ///
  /// In de, this message translates to:
  /// **'Leuchte'**
  String get floorKindLight;

  /// No description provided for @floorKindButton.
  ///
  /// In de, this message translates to:
  /// **'Taster'**
  String get floorKindButton;

  /// No description provided for @floorKindBlind.
  ///
  /// In de, this message translates to:
  /// **'Rollladen'**
  String get floorKindBlind;

  /// No description provided for @floorKindSocket.
  ///
  /// In de, this message translates to:
  /// **'Steckdose'**
  String get floorKindSocket;

  /// No description provided for @floorKindHeating.
  ///
  /// In de, this message translates to:
  /// **'Heizung'**
  String get floorKindHeating;

  /// No description provided for @floorKindSensor.
  ///
  /// In de, this message translates to:
  /// **'Melder, Fühler'**
  String get floorKindSensor;

  /// No description provided for @floorKindContact.
  ///
  /// In de, this message translates to:
  /// **'Kontakt'**
  String get floorKindContact;

  /// No description provided for @floorKindOther.
  ///
  /// In de, this message translates to:
  /// **'Sonstiges'**
  String get floorKindOther;

  /// No description provided for @floorStateUnheard.
  ///
  /// In de, this message translates to:
  /// **'noch nichts gehört'**
  String get floorStateUnheard;

  /// No description provided for @floorUnheardTitle.
  ///
  /// In de, this message translates to:
  /// **'Noch nichts gehört'**
  String get floorUnheardTitle;

  /// No description provided for @floorUnheardSince.
  ///
  /// In de, this message translates to:
  /// **'Beobachtet seit {since}. Das ist kein Fehler: Viele Geräte senden nur, wenn man sie bedient.'**
  String floorUnheardSince(String since);

  /// No description provided for @floorDeleteLevelAsk.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ löschen?'**
  String floorDeleteLevelAsk(String name);

  /// No description provided for @floorDeleteLevelBody.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{Die Ebene wird mit ihrem Bild gelöscht.} =1{Die Ebene wird mit ihrem Bild und 1 Punkt gelöscht.} other{Die Ebene wird mit ihrem Bild und {count} Punkten gelöscht.}} Das lässt sich nicht zurückholen.'**
  String floorDeleteLevelBody(int count);

  /// No description provided for @floorPointTitle.
  ///
  /// In de, this message translates to:
  /// **'Punkt'**
  String get floorPointTitle;

  /// No description provided for @floorPointDeleted.
  ///
  /// In de, this message translates to:
  /// **'Punkt gelöscht'**
  String get floorPointDeleted;

  /// No description provided for @floorDetailLast.
  ///
  /// In de, this message translates to:
  /// **'zuletzt {time}'**
  String floorDetailLast(String time);

  /// No description provided for @floorPickTitle.
  ///
  /// In de, this message translates to:
  /// **'Gruppenadressen'**
  String get floorPickTitle;

  /// No description provided for @floorPickCount.
  ///
  /// In de, this message translates to:
  /// **'{count} von {max} gewählt'**
  String floorPickCount(int count, int max);

  /// No description provided for @floorPickMax.
  ///
  /// In de, this message translates to:
  /// **'Höchstzahl erreicht. Wähle eine Adresse ab, um eine andere zu nehmen.'**
  String get floorPickMax;

  /// No description provided for @floorPickDiscardTitle.
  ///
  /// In de, this message translates to:
  /// **'Geänderte Auswahl verwerfen?'**
  String get floorPickDiscardTitle;

  /// No description provided for @floorPickDiscard.
  ///
  /// In de, this message translates to:
  /// **'Verwerfen'**
  String get floorPickDiscard;

  /// No description provided for @hpaTab.
  ///
  /// In de, this message translates to:
  /// **'Nach dem Einzug'**
  String get hpaTab;

  /// No description provided for @exportsData.
  ///
  /// In de, this message translates to:
  /// **'Daten'**
  String get exportsData;

  /// No description provided for @exportsPermanent.
  ///
  /// In de, this message translates to:
  /// **'Dauerhaft'**
  String get exportsPermanent;

  /// No description provided for @ackLast.
  ///
  /// In de, this message translates to:
  /// **'Letzte'**
  String get ackLast;

  /// No description provided for @ackHeard.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt gehört'**
  String get ackHeard;

  /// No description provided for @learnNamed.
  ///
  /// In de, this message translates to:
  /// **'Benannt'**
  String get learnNamed;

  /// No description provided for @learnOpenCount.
  ///
  /// In de, this message translates to:
  /// **'Offen'**
  String get learnOpenCount;

  /// No description provided for @learnPressTitle.
  ///
  /// In de, this message translates to:
  /// **'Drück einen Taster'**
  String get learnPressTitle;

  /// No description provided for @chartsAddresses.
  ///
  /// In de, this message translates to:
  /// **'Adressen'**
  String get chartsAddresses;

  /// Knopf und Dialogtitel: Lizenz aus der Kaufmail eingeben (Windows)
  ///
  /// In de, this message translates to:
  /// **'Lizenz eingeben'**
  String get planLicenseEnter;

  /// Eingabefeld für die Lizenz
  ///
  /// In de, this message translates to:
  /// **'Lizenz'**
  String get planLicenseField;

  /// Hilfetext zur Lizenz-Eingabe
  ///
  /// In de, this message translates to:
  /// **'Die ganze Zeile aus der Mail einfügen, sie beginnt mit KNX1. Sie gilt auf deinen eigenen Windows-Geräten.'**
  String get planLicenseHelp;

  /// Lizenz übernehmen
  ///
  /// In de, this message translates to:
  /// **'Freischalten'**
  String get planLicenseApply;

  /// Lizenz abgelehnt
  ///
  /// In de, this message translates to:
  /// **'Diese Lizenz stimmt nicht. Bitte die ganze Zeile aus der Mail einfügen.'**
  String get planLicenseInvalid;

  /// Lizenz echt, aber nicht mehr gültig
  ///
  /// In de, this message translates to:
  /// **'Diese Lizenz gilt nicht mehr: Das Abo ist beendet oder der Kauf wurde erstattet.'**
  String get planLicenseEnded;

  /// Nach dem Öffnen der Kaufseite (Windows ohne Konto)
  ///
  /// In de, this message translates to:
  /// **'Die Kaufseite ist im Browser offen. Nach dem Kauf kommt deine Lizenz per Mail, die gibst du hier unter „Lizenz eingeben“ ein.'**
  String get planLicenseCheckoutOpened;

  /// Lizenz angenommen
  ///
  /// In de, this message translates to:
  /// **'{tier} ist freigeschaltet.'**
  String planLicenseActive(String tier);

  /// Shown in the send sheet and as send error when the add-on or box server runs read-only
  ///
  /// In de, this message translates to:
  /// **'Nur-Lesen ist an: Der Server sendet nichts auf den Bus. Im Add-on unter Konfiguration „Nur lesen“ ausschalten, auf Box und Docker READ_ONLY entfernen.'**
  String get addonReadOnly;

  /// Exporte: dauerhafte Aufzeichnung des Servers als ETS-Gruppenmonitor-Datei
  ///
  /// In de, this message translates to:
  /// **'Verlauf als ETS-Datei (für Home Assistant und SpectrumKNX)'**
  String get exportsEtsHistory;

  /// Exporte: Unterzeile zum ETS-Verlauf
  ///
  /// In de, this message translates to:
  /// **'Dauerhafte Aufzeichnung, einzelne Tage oder alles'**
  String get exportsEtsHistoryMeta;

  /// Dialog ETS-Verlauf: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Lädt die Telegramme der dauerhaften Aufzeichnung als Gruppenmonitor-Datei der ETS. SpectrumKNX, die ETS und Busclear öffnen sie direkt.'**
  String get exportsEtsHistoryHint;

  /// Dialog ETS-Verlauf: Knopf
  ///
  /// In de, this message translates to:
  /// **'Herunterladen'**
  String get exportsEtsHistoryDownload;

  /// Dialog ETS-Verlauf: abbrechen
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get exportsEtsHistoryCancel;

  /// Fortschritt beim Laden des ETS-Verlaufs von der Box
  ///
  /// In de, this message translates to:
  /// **'Verlauf wird geladen …'**
  String get exportsEtsHistoryLoading;

  /// Diagramme: Zeitraum = was die App gerade im Speicher hat
  ///
  /// In de, this message translates to:
  /// **'Geladen'**
  String get chartsPeriodLoaded;

  /// Diagramme: Zeitraum heute ab Mitternacht (aus dem Verlauf des Servers)
  ///
  /// In de, this message translates to:
  /// **'Heute'**
  String get chartsPeriodToday;

  /// Diagramme: Erklärung der Zeitraum-Auswahl (Tooltip)
  ///
  /// In de, this message translates to:
  /// **'Geladen zeigt die letzten 5.000 Telegramme, die die App gerade im Speicher hat. Heute, 7 und 30 Tage kommen aus dem Verlauf von Add-on oder Box.'**
  String get chartsPeriodLoadedHint;

  /// Diagramme: Laden des Zeitraums vom Server fehlgeschlagen
  ///
  /// In de, this message translates to:
  /// **'Verlauf nicht geladen: {error}'**
  String chartsPeriodFailed(String error);

  /// Diagramme: Hinweis, wenn ein längerer Zeitraum gewählt ist und Kennzahlen im Diagramm sind
  ///
  /// In de, this message translates to:
  /// **'Bus-Kennzahlen zeigen nur den geladenen Zeitraum.'**
  String get chartsPeriodMetrics;

  /// Diagramme: Legende für gestrichelte Linienenden
  ///
  /// In de, this message translates to:
  /// **'Gestrichelt: Der letzte Wert gilt weiter, seitdem kam kein neues Telegramm.'**
  String get chartsDashedHint;

  /// Diagramme: Server nicht erreichbar beim Laden eines Zeitraums
  ///
  /// In de, this message translates to:
  /// **'Add-on oder Box antwortet nicht.'**
  String get chartsPeriodUnreachable;

  /// Diagramme: Knopf nach einem Fehler beim Laden des Zeitraums
  ///
  /// In de, this message translates to:
  /// **'Erneut laden'**
  String get chartsPeriodRetry;

  /// Dialog ETS-Verlauf: Auswahl ganzer Verlauf
  ///
  /// In de, this message translates to:
  /// **'Alles'**
  String get exportsEtsHistoryAll;

  /// Dialog ETS-Verlauf: Hinweis, wenn 'Alles' gewählt ist
  ///
  /// In de, this message translates to:
  /// **'Der ganze Verlauf als ZIP mit einer Datei pro Tag. SpectrumKNX importiert sie in einem Rutsch, etwa für einen Umzug. Bei vielen Wochen kann das einige Minuten dauern.'**
  String get exportsEtsHistoryAllHint;

  /// Diagramme: Knopf neben dem angeklickten Fadenkreuz
  ///
  /// In de, this message translates to:
  /// **'Hier kommentieren'**
  String get chartsAnnotateHere;

  /// Kommentar-Dialog: Überschrift der Diagrammwerte (vorher → zu diesem Zeitpunkt)
  ///
  /// In de, this message translates to:
  /// **'Werte'**
  String get annotationValuesLabel;

  /// Knopf im Detailblatt: Namen einer Gruppenadresse aus dem Projekt korrigieren (z. B. Tippfehler)
  ///
  /// In de, this message translates to:
  /// **'Namen korrigieren'**
  String get groupRename;

  /// Knopf im Detailblatt, wenn der Name schon in der App korrigiert wurde
  ///
  /// In de, this message translates to:
  /// **'Name selbst korrigiert – ändern'**
  String get groupRenamed;

  /// Titel des Umbenennen-Dialogs
  ///
  /// In de, this message translates to:
  /// **'Name für {address}'**
  String groupRenameTitle(String address);

  /// Eingabefeld im Umbenennen-Dialog
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get groupRenameField;

  /// Hilfetext im Umbenennen-Dialog mit dem Namen aus dem Projekt
  ///
  /// In de, this message translates to:
  /// **'Im Projekt: „{name}“. Die Korrektur gilt in der App und geht mit den Aufgaben für die ETS als Gruppenadress-Import zurück.'**
  String groupRenameHelp(String name);

  /// Knopf im Umbenennen-Dialog: Korrektur zurücknehmen
  ///
  /// In de, this message translates to:
  /// **'Wie im Projekt'**
  String get groupRenameRevert;

  /// Titel/Tooltip: Text in allen Gruppenadress-Namen des Projekts ersetzen
  ///
  /// In de, this message translates to:
  /// **'Namen suchen und ersetzen'**
  String get groupReplaceTitle;

  /// Eingabefeld: zu ersetzender Text
  ///
  /// In de, this message translates to:
  /// **'Suchen'**
  String get groupReplaceFind;

  /// Eingabefeld: neuer Text
  ///
  /// In de, this message translates to:
  /// **'Ersetzen durch'**
  String get groupReplaceWith;

  /// Hinweis im Ersetzen-Dialog, solange das Suchfeld leer ist
  ///
  /// In de, this message translates to:
  /// **'Zum Beispiel einen Tippfehler, der in vielen Namen vorkommt. Groß- und Kleinschreibung zählt.'**
  String get groupReplaceHint;

  /// Vorschau im Ersetzen-Dialog
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{Kein Name enthält diesen Text.} =1{1 Name wird geändert:} other{{count} Namen werden geändert, zum Beispiel:}}'**
  String groupReplaceCount(int count);

  /// Knopf im Ersetzen-Dialog
  ///
  /// In de, this message translates to:
  /// **'Ersetzen'**
  String get groupReplaceApply;

  /// Meldung nach dem Ersetzen
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Name korrigiert. Er geht mit den Aufgaben für die ETS zurück.} other{{count} Namen korrigiert. Sie gehen mit den Aufgaben für die ETS zurück.}}'**
  String groupReplaceDone(int count);

  /// ETS-Aufgabe: Name in der App korrigiert
  ///
  /// In de, this message translates to:
  /// **'Name korrigiert'**
  String get etsTitleRename;

  /// ETS-Aufgabe: korrigierten Namen übernehmen
  ///
  /// In de, this message translates to:
  /// **'Namen in „{name}“ ändern – erledigt der Gruppenadress-Import.'**
  String etsTodoRename(String name);

  /// Snackbar: Export failed (details only in the log)
  ///
  /// In de, this message translates to:
  /// **'Export hat nicht geklappt. Versuch es noch einmal.'**
  String get exportFailedGeneric;

  /// Snackbar: PDF could not be created or shared (details only in the log)
  ///
  /// In de, this message translates to:
  /// **'PDF hat nicht geklappt. Versuch es noch einmal.'**
  String get pdfExportFailedGeneric;

  /// Snackbar: sending data to the box failed
  ///
  /// In de, this message translates to:
  /// **'Die Box hat die Daten nicht angenommen.'**
  String get boxShareFailed;

  /// Snackbar: fault hunt could not be loaded from the box
  ///
  /// In de, this message translates to:
  /// **'Fehlerjagd nicht geladen. Ist die Box erreichbar?'**
  String get huntLoadFailed;

  /// Generic error message for an action that failed (details only in the log)
  ///
  /// In de, this message translates to:
  /// **'Das hat nicht geklappt. Versuch es noch einmal.'**
  String get actionFailed;

  /// Generic undo action, e.g. in a snackbar after removing something
  ///
  /// In de, this message translates to:
  /// **'Rückgängig'**
  String get commonUndo;

  /// Customer visits: confirmation before deleting a manual entry
  ///
  /// In de, this message translates to:
  /// **'Eintrag löschen?'**
  String get visitDeleteTitle;

  /// Snackbar after removing a watcher, with an undo action
  ///
  /// In de, this message translates to:
  /// **'Wächter entfernt: {what}'**
  String watchRemoved(String what);

  /// Teach-in: snackbar after forgetting a learned group address, with an undo action
  ///
  /// In de, this message translates to:
  /// **'Vergessen: {name}'**
  String learnForgotten(String name);

  /// Pairing dialog: the box name as the link states it (anyone can choose it).
  ///
  /// In de, this message translates to:
  /// **'Name im Link: {name}'**
  String boxPairNamed(String name);

  /// Pairing dialog: warning for a box link without certificate fingerprint (plain HTTP).
  ///
  /// In de, this message translates to:
  /// **'Unverschlüsselt (HTTP): Wer im selben Netz mitliest, sieht alles, was die App an diese Box schickt. Verbinde dich nur in deinem eigenen Netz.'**
  String get boxPairUnencrypted;

  /// Dialog title: the app refuses a box link that would send the access key over plain HTTP to a host on the internet.
  ///
  /// In de, this message translates to:
  /// **'Nicht ohne Verschlüsselung'**
  String get boxPlainRefusedTitle;

  /// Error and dialog body: the app sent nothing, because access key, box password or pairing code would go over unencrypted HTTP to a host outside the local network.
  ///
  /// In de, this message translates to:
  /// **'{address} liegt nicht im lokalen Netz und ist nur unverschlüsselt (HTTP) erreichbar. Die App schickt den Zugang dorthin nicht: Er wäre unterwegs für jeden lesbar. Auf der Seite der Box unter HTTPS einen neuen QR-Code erzeugen und scannen, oder die Box im eigenen Netz verbinden.'**
  String boxPlainRefused(String address);

  /// Dialog title: a pairing link would replace the box that is already paired.
  ///
  /// In de, this message translates to:
  /// **'Gekoppelte Box ersetzen?'**
  String get boxReplaceTitle;

  /// Dialog body before replacing the paired box; both as „name (address)“.
  ///
  /// In de, this message translates to:
  /// **'Gekoppelt ist {current}. Der Link würde sie durch {next} ersetzen, die bisherige Kopplung geht dabei verloren.'**
  String boxReplaceBody(String current, String next);

  /// Button: replace the paired box.
  ///
  /// In de, this message translates to:
  /// **'Ersetzen'**
  String get boxReplaceConfirm;

  /// Dialog title: a box paired via a link from outside asks for the project.
  ///
  /// In de, this message translates to:
  /// **'Projekt an diese Box geben?'**
  String get boxProjectTitle;

  /// Dialog body before the project goes to a box paired via an external link; box as „name (address)“.
  ///
  /// In de, this message translates to:
  /// **'Die Box {box} wurde über einen Link aus einer anderen App oder Webseite gekoppelt. Gibst du ihr dein Projekt, bekommt sie das ETS-Projekt mit allen Adressen und Namen, den Namen der Anlage und die Gateway-Adresse. Bis dahin bekommt sie nichts davon.'**
  String boxProjectBody(String box);

  /// Button: give the project to the box.
  ///
  /// In de, this message translates to:
  /// **'Projekt geben'**
  String get boxProjectAllow;

  /// Button: do not give the project to the box for now.
  ///
  /// In de, this message translates to:
  /// **'Noch nicht'**
  String get boxProjectDeny;

  /// App lock: after many failed attempts only a restart of the app allows further attempts.
  ///
  /// In de, this message translates to:
  /// **'Zu viele Fehlversuche. Beende die App und öffne sie neu, dann kannst du es noch einmal versuchen.'**
  String get appLockRestart;

  /// Absturzerkennung: Grund (Server vom System wegen Speichermangel beendet)
  ///
  /// In de, this message translates to:
  /// **'Speicher voll'**
  String get restartReasonOom;

  /// Absturzerkennung: Grund (Signal)
  ///
  /// In de, this message translates to:
  /// **'vom System beendet'**
  String get restartReasonSignal;

  /// Absturzerkennung: Grund mit Signalname, z. B. SIGSEGV
  ///
  /// In de, this message translates to:
  /// **'vom System beendet ({signal})'**
  String restartReasonSignalNamed(String signal);

  /// Absturzerkennung: Grund (systemd-Watchdog)
  ///
  /// In de, this message translates to:
  /// **'Watchdog'**
  String get restartReasonWatchdog;

  /// Absturzerkennung: Titel der Liste
  ///
  /// In de, this message translates to:
  /// **'Neustarts des Servers'**
  String get restartsTitle;

  /// Absturzerkennung: Bedienhilfe der Statuszeile
  ///
  /// In de, this message translates to:
  /// **'Neustarts anzeigen'**
  String get restartsShow;

  /// Absturzerkennung: Erklärung auf der Busclear Box
  ///
  /// In de, this message translates to:
  /// **'Letzte 30 Tage. systemd startet den Server nach 3 s neu, die Aufzeichnung läuft dann weiter.'**
  String get restartsIntroBox;

  /// Absturzerkennung: Erklärung im Add-on oder Docker
  ///
  /// In de, this message translates to:
  /// **'Letzte 30 Tage. Nach einem unerwarteten Ende läuft die Aufzeichnung weiter, sobald der Server wieder gestartet ist.'**
  String get restartsIntro;

  /// Absturzerkennung: Eintrag
  ///
  /// In de, this message translates to:
  /// **'zuletzt am Leben {time}'**
  String restartsLastSeen(String time);

  /// Absturzerkennung: Eintrag
  ///
  /// In de, this message translates to:
  /// **'Version {version}'**
  String restartsVersion(String version);

  /// Absturzerkennung: Eintrag, Dauer ohne Server
  ///
  /// In de, this message translates to:
  /// **'Lücke {duration}'**
  String restartsGap(String duration);

  /// Absturzerkennung: Eintrag mit falscher Uhr beim Start
  ///
  /// In de, this message translates to:
  /// **'Lücke unbekannt'**
  String get restartsGapUnknown;

  /// Absturzerkennung: Eintrag
  ///
  /// In de, this message translates to:
  /// **'Fehlertext nur für Admins sichtbar'**
  String get restartsErrorAdminOnly;

  /// Absturzerkennung: Kennung der Legende
  ///
  /// In de, this message translates to:
  /// **'Mögliche Gründe'**
  String get restartsReasons;

  /// Absturzerkennung: Legende
  ///
  /// In de, this message translates to:
  /// **'Die Gründe kommen von systemd. Ohne diese Angabe, etwa im Add-on, steht „Grund unbekannt“.'**
  String get restartsLegend;

  /// Absturzerkennung: Knopf
  ///
  /// In de, this message translates to:
  /// **'Im Verlauf zeigen'**
  String get restartsShowHistory;

  /// Absturzerkennung: leere Liste
  ///
  /// In de, this message translates to:
  /// **'Keine unerwarteten Neustarts in den letzten 30 Tagen.'**
  String get restartsEmpty;

  /// Absturzerkennung: Fehler beim Laden
  ///
  /// In de, this message translates to:
  /// **'Die Liste ist gerade nicht abrufbar.'**
  String get restartsUnavailable;

  /// Absturzerkennung: mehrere Abstürze in Folge
  ///
  /// In de, this message translates to:
  /// **'{count}. unerwartetes Ende in Folge'**
  String crashStreak(int count);

  /// Absturzerkennung: mehrere Abstürze in Folge
  ///
  /// In de, this message translates to:
  /// **'{count}. unerwartetes Ende in Folge, jedes Mal kurz nach dem Verbinden'**
  String crashStreakAfterConnect(int count);

  /// Absturzerkennung: mehrere Abstürze in Folge
  ///
  /// In de, this message translates to:
  /// **'Vorschlag: einmal ohne automatisches Verbinden starten, um den Fehler einzugrenzen.'**
  String get crashStreakHint;

  /// Absturzerkennung: Knopf, startet diesmal ohne automatisches Verbinden
  ///
  /// In de, this message translates to:
  /// **'Ohne Verbinden'**
  String get crashWithoutConnect;

  /// Absturzerkennung: Banner in anderen Ansichten
  ///
  /// In de, this message translates to:
  /// **'Unerwartet beendet am {time}. Bericht?'**
  String crashBanner(String time);

  /// Absturzerkennung: Banner, öffnet das Diagnosepaket
  ///
  /// In de, this message translates to:
  /// **'Ansehen'**
  String get crashBannerView;

  /// Diagnosepaket: Karte für das öffentliche Issue
  ///
  /// In de, this message translates to:
  /// **'Öffentlich melden'**
  String get diagIssueTitle;

  /// Diagnosepaket: Karte für das öffentliche Issue
  ///
  /// In de, this message translates to:
  /// **'Im Issue stehen nur diese Angaben, kein Protokoll:'**
  String get diagIssueIntro;

  /// Diagnosepaket: Feld
  ///
  /// In de, this message translates to:
  /// **'Version'**
  String get diagIssueVersion;

  /// Diagnosepaket: Feld
  ///
  /// In de, this message translates to:
  /// **'Plattform'**
  String get diagIssuePlatform;

  /// Diagnosepaket: Feld
  ///
  /// In de, this message translates to:
  /// **'Zeitpunkt'**
  String get diagIssueTime;

  /// Diagnosepaket: Feld
  ///
  /// In de, this message translates to:
  /// **'Grund'**
  String get diagIssueReason;

  /// Diagnosepaket: Grund ohne Bericht des Systems
  ///
  /// In de, this message translates to:
  /// **'unerwartet beendet'**
  String get diagIssueReasonCrash;

  /// Diagnosepaket: Knopf, öffnet GitHub
  ///
  /// In de, this message translates to:
  /// **'Als Issue melden'**
  String get diagIssueButton;

  /// Diagnosepaket: Hinweis zum Knopf
  ///
  /// In de, this message translates to:
  /// **'Öffnet GitHub im Browser. Das Paket hängst du selbst an.'**
  String get diagIssueHint;

  /// Diagnosepaket: Fehler
  ///
  /// In de, this message translates to:
  /// **'GitHub ließ sich nicht öffnen.'**
  String get diagIssueFailed;

  /// Diagnosepaket: Bericht des Betriebssystems, z. B. macOS
  ///
  /// In de, this message translates to:
  /// **'Absturzbericht von {system} gefunden'**
  String diagSystemCrashTitle(String system);

  /// Diagnosepaket: Bericht des Betriebssystems
  ///
  /// In de, this message translates to:
  /// **'Ein Bericht des Systems passt zum Zeitpunkt ({time}). Übernommen werden nur Art des Fehlers und Modul, kein Pfad und kein Benutzername.'**
  String diagSystemCrashBody(String time);

  /// Diagnosepaket: Bericht des Betriebssystems, Feld
  ///
  /// In de, this message translates to:
  /// **'Art'**
  String get diagSystemCrashKind;

  /// Diagnosepaket: Bericht des Betriebssystems, Feld
  ///
  /// In de, this message translates to:
  /// **'Modul'**
  String get diagSystemCrashModule;

  /// Diagnosepaket: Bericht des Betriebssystems, Auswahl
  ///
  /// In de, this message translates to:
  /// **'Ins Paket übernehmen'**
  String get diagSystemCrashInclude;

  /// Diagnosepaket: Inhalt
  ///
  /// In de, this message translates to:
  /// **'Absturzbericht des Systems: Art und Modul'**
  String get diagContentSystemCrash;

  /// Datenexport: Abschnitt
  ///
  /// In de, this message translates to:
  /// **'MQTT: jedes Telegramm (Vorschau)'**
  String get dataExportMqtt;

  /// Datenexport: MQTT-Strom aus
  ///
  /// In de, this message translates to:
  /// **'Aus. Einschalten im Add-on mit der Option „Jedes Telegramm an MQTT“, in Docker und auf der Box mit MQTT_TELEGRAMS=true.'**
  String get dataExportMqttOff;

  /// Datenexport: MQTT-Strom an
  ///
  /// In de, this message translates to:
  /// **'An: {sent} gesendet, {dropped} verworfen (seit dem Start)'**
  String dataExportMqttOn(int sent, int dropped);

  /// Datenexport: Broker getrennt
  ///
  /// In de, this message translates to:
  /// **'Broker nicht verbunden. Telegramme werden verworfen, bis er wieder erreichbar ist; der Verlauf hat sie.'**
  String get dataExportMqttDisconnected;

  /// Datenexport: Secure-Telegramme ausgelassen
  ///
  /// In de, this message translates to:
  /// **'{count} KNX-Secure-Telegramme nicht gesendet. Sie gehen nur mit der Option „Auch KNX-Secure-Telegramme an MQTT“ (MQTT_SECURE_TELEGRAMS=true) hinaus, auf dem Broker sind sie Klartext.'**
  String dataExportMqttSecureSkipped(int count);

  /// Datenexport: Secure-Telegramme nicht entschlüsselt
  ///
  /// In de, this message translates to:
  /// **'{count} KNX-Secure-Telegramme nicht gesendet, weil der Server sie nicht entschlüsseln konnte (kein Keyring, Schlüssel fehlt oder ungültig). Keyring aus der ETS unter Projekt › KNX Secure importieren.'**
  String dataExportMqttUndecrypted(int count);

  /// Datenexport: Secure-Telegramme an
  ///
  /// In de, this message translates to:
  /// **'Auch KNX-Secure-Telegramme gehen entschlüsselt hinaus. Jeder, der den Broker lesen kann, sieht ihre Werte.'**
  String get dataExportMqttSecureOn;

  /// Datenexport: Option „Letzten Wert je Adresse behalten“ an
  ///
  /// In de, this message translates to:
  /// **'Letzter Wert je Adresse unter knx_monitor/value/… mit retain, {count} Werte gesendet.'**
  String dataExportMqttRetain(int count);

  /// Data export, MQTT telegram stream: raw data mode, group address filter and running number of the last telegram
  ///
  /// In de, this message translates to:
  /// **'{mode, select, raw{Mit Rohdaten} rawOnly{Nur Rohdaten} other{Ohne Rohdaten}} · Gruppenadressen: {filter} · letzte Nr. (seq) {seq}'**
  String dataExportMqttDetails(String mode, String filter, int seq);

  /// Data export, MQTT telegram stream: no group address filter set
  ///
  /// In de, this message translates to:
  /// **'alle'**
  String get dataExportMqttFilterAll;

  /// Datenexport, MQTT: Schalter
  ///
  /// In de, this message translates to:
  /// **'Jedes Telegramm an MQTT'**
  String get dataExportMqttSwitch;

  /// Datenexport, MQTT: Erklärung zum Schalter
  ///
  /// In de, this message translates to:
  /// **'Unter knx_monitor/telegram/…, mit Name, Datentyp und Wert aus dem ETS-Projekt.'**
  String get dataExportMqttSwitchHint;

  /// Datenexport, MQTT: Rückfrage beim Einschalten, Titel
  ///
  /// In de, this message translates to:
  /// **'Telegramme an den Broker senden?'**
  String get dataExportMqttConfirmTitle;

  /// Datenexport, MQTT: Rückfrage beim Einschalten, Text
  ///
  /// In de, this message translates to:
  /// **'Damit gehen Adressen, Namen und Werte der Anlage an den MQTT-Broker. Jeder, der den Broker lesen kann, sieht sie.'**
  String get dataExportMqttConfirmBody;

  /// Datenexport, MQTT: Rückfrage bestätigen
  ///
  /// In de, this message translates to:
  /// **'Einschalten'**
  String get dataExportMqttConfirm;

  /// Datenexport, MQTT: Schalter
  ///
  /// In de, this message translates to:
  /// **'Rohdaten mitsenden'**
  String get dataExportMqttRaw;

  /// Datenexport, MQTT: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Der ganze cEMI-Rahmen, Priorität und ein Schlüssel, an dem eine Datenbank Dubletten erkennt.'**
  String get dataExportMqttRawHint;

  /// Datenexport, MQTT: Schalter
  ///
  /// In de, this message translates to:
  /// **'Nur Rohdaten'**
  String get dataExportMqttRawOnly;

  /// Datenexport, MQTT: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Ohne Name, Datentyp, Wert und Einheit aus dem ETS-Projekt.'**
  String get dataExportMqttRawOnlyHint;

  /// Datenexport, MQTT: Schalter
  ///
  /// In de, this message translates to:
  /// **'Letzten Wert je Adresse behalten'**
  String get dataExportMqttRetainSwitch;

  /// Datenexport, MQTT: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Zusätzlich unter knx_monitor/value/… mit retain. Wer später abonniert, hat sofort den aktuellen Wert.'**
  String get dataExportMqttRetainHint;

  /// Datenexport, MQTT: Schalter
  ///
  /// In de, this message translates to:
  /// **'Wiederholungen mitsenden'**
  String get dataExportMqttRepeats;

  /// Datenexport, MQTT: Schalter
  ///
  /// In de, this message translates to:
  /// **'Auch KNX-Secure-Telegramme'**
  String get dataExportMqttSecureSwitch;

  /// Datenexport, MQTT: Erklärung
  ///
  /// In de, this message translates to:
  /// **'Entschlüsselt. Auf dem Broker sind sie Klartext.'**
  String get dataExportMqttSecureHint;

  /// Datenexport, MQTT: Rückfrage, Titel
  ///
  /// In de, this message translates to:
  /// **'KNX-Secure-Telegramme im Klartext senden?'**
  String get dataExportMqttSecureConfirmTitle;

  /// Datenexport, MQTT: Rückfrage, Text
  ///
  /// In de, this message translates to:
  /// **'Der Server entschlüsselt sie und schickt die Werte offen an den Broker. Der Schutz von KNX Data Secure gilt dort nicht mehr.'**
  String get dataExportMqttSecureConfirmBody;

  /// Datenexport, MQTT: Feld für den Filter
  ///
  /// In de, this message translates to:
  /// **'Nur diese Gruppenadressen'**
  String get dataExportMqttFilter;

  /// Datenexport, MQTT: Hinweis zum Filter
  ///
  /// In de, this message translates to:
  /// **'Leer = alle. Beispiel: 1/#,3/2/#,4/1/7'**
  String get dataExportMqttFilterHint;

  /// Datenexport, MQTT: Knopf
  ///
  /// In de, this message translates to:
  /// **'MQTT übernehmen'**
  String get dataExportMqttSave;

  /// Datenexport, MQTT: Knopf, verwirft die Einstellungen der App
  ///
  /// In de, this message translates to:
  /// **'Zurück zur Vorgabe'**
  String get dataExportMqttReset;

  /// Datenexport, MQTT: woher die Einstellungen kommen
  ///
  /// In de, this message translates to:
  /// **'In der App eingestellt. Die Add-on-Optionen bzw. Umgebungsvariablen gelten erst wieder nach „Zurück zur Vorgabe“.'**
  String get dataExportMqttSourceApp;

  /// Datenexport, MQTT: woher die Einstellungen kommen
  ///
  /// In de, this message translates to:
  /// **'Vorgabe aus den Add-on-Optionen bzw. Umgebungsvariablen. Eine Änderung hier gilt sofort und bleibt nach einem Neustart.'**
  String get dataExportMqttSourceDefault;

  /// Datenexport, MQTT: Strom pausiert
  ///
  /// In de, this message translates to:
  /// **'Pausiert über den Schalter „Telegramme an MQTT“ in Home Assistant.'**
  String get dataExportMqttPaused;

  /// Datenexport, MQTT: ungespeicherte Änderung
  ///
  /// In de, this message translates to:
  /// **'Geändert, noch nicht übernommen.'**
  String get dataExportMqttUnsaved;

  /// Datenexport: Abschnitt
  ///
  /// In de, this message translates to:
  /// **'Home Assistant'**
  String get dataExportHa;

  /// Datenexport, Home Assistant: Integration aktiv
  ///
  /// In de, this message translates to:
  /// **'Busclear Integration eingerichtet. Sie liefert die Entitäten, das MQTT-Gerät ist pausiert.'**
  String get dataExportHaIntegration;

  /// Datenexport, Home Assistant: MQTT-Gerät aktiv
  ///
  /// In de, this message translates to:
  /// **'MQTT-Gerät „Busclear“ aktiv. Home Assistant legt die Entitäten über MQTT an.'**
  String get dataExportHaMqttDevice;

  /// Datenexport, Home Assistant: Discovery aus
  ///
  /// In de, this message translates to:
  /// **'Ankündigung an Home Assistant aus (MQTT_DISCOVERY=false). Zustand und Ereignisse gehen weiter an den Broker.'**
  String get dataExportHaNoDiscovery;

  /// Datenexport, Home Assistant: Broker getrennt
  ///
  /// In de, this message translates to:
  /// **'MQTT-Broker nicht verbunden.'**
  String get dataExportHaDisconnected;

  /// Datenexport, Home Assistant: Gesundheitsprüfung des Servers (Issue 12) ist aus, mit dem Weg zum Einschalten
  ///
  /// In de, this message translates to:
  /// **'Gesundheitsprüfung am Server aus. Einschalten: im Add-on die Option „Gesundheitsprüfung für Home Assistant“, bei Docker und Box HEALTH_CHECK=true.'**
  String get dataExportHaHealthOff;

  /// Datenexport, Home Assistant: Gesundheitsprüfung des Servers ist an, aber noch nie gelaufen
  ///
  /// In de, this message translates to:
  /// **'Gesundheitsprüfung am Server an, noch kein Lauf. Der erste folgt in wenigen Minuten.'**
  String get dataExportHaHealthNever;

  /// Datenexport, Home Assistant: Gesundheitsprüfung des Servers ist an; Zeit des letzten Laufs und Zahl der Befunde
  ///
  /// In de, this message translates to:
  /// **'Gesundheitsprüfung am Server an. Letzter Lauf {when}: {count, plural, =0{keine Befunde} =1{1 Befund} other{{count} Befunde}}. Details in Home Assistant.'**
  String dataExportHaHealthRun(String when, int count);

  /// Verbinden: Abschnitt weitere Messpunkte (#8)
  ///
  /// In de, this message translates to:
  /// **'Messpunkte'**
  String get tapPointsTitle;

  /// Verbinden: Erklärung Messpunkte
  ///
  /// In de, this message translates to:
  /// **'Weitere Verbindungen zur selben Anlage, etwa ein Interface je Linie. Die App führt alles in einem Verlauf zusammen. Jeder Tunnel-Messpunkt belegt einen Tunnel an seinem Interface.'**
  String get tapPointsHint;

  /// Verbinden: erster Messpunkt
  ///
  /// In de, this message translates to:
  /// **'Messpunkt 1 ist die Verbindung oben.'**
  String get tapPointFirst;

  /// Knopf und Titel: Messpunkt hinzufügen
  ///
  /// In de, this message translates to:
  /// **'Messpunkt hinzufügen'**
  String get tapPointAdd;

  /// Messpunkt: Feld Name
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get tapPointName;

  /// Messpunkt: Beispiel für den Namen
  ///
  /// In de, this message translates to:
  /// **'Linie 1.2 · MDT IP-Interface'**
  String get tapPointNameHint;

  /// Messpunkt: Feld IP-Adresse
  ///
  /// In de, this message translates to:
  /// **'Adresse'**
  String get tapPointHost;

  /// Messpunkt: Feld Verbindungsart
  ///
  /// In de, this message translates to:
  /// **'Verbindungsart'**
  String get tapPointMode;

  /// Messpunkt: Feld Zeitfenster
  ///
  /// In de, this message translates to:
  /// **'Zeitfenster in ms'**
  String get tapPointWindow;

  /// Messpunkt: Hilfe zum Zeitfenster
  ///
  /// In de, this message translates to:
  /// **'Leer = 100 ms. Über VPN größer wählen, etwa 250.'**
  String get tapPointWindowHelp;

  /// Messpunkt: Hinweis Adresse außerhalb des Netzes
  ///
  /// In de, this message translates to:
  /// **'Die Adresse liegt nicht im eigenen Netz. Über VPN ist TCP robuster als UDP, Routing kommt meist nicht durch.'**
  String get tapPointRemote;

  /// Messpunkt: Zustand pausiert
  ///
  /// In de, this message translates to:
  /// **'pausiert, Tunnel frei'**
  String get tapPointPaused;

  /// Messpunkt: Grenze erreicht
  ///
  /// In de, this message translates to:
  /// **'Höchstens 8 Messpunkte je Anlage.'**
  String get tapPointMax;

  /// Messpunkt: Dialog bestätigen
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get tapPointSave;

  /// Monitor: Banner, ein Messpunkt ist getrennt
  ///
  /// In de, this message translates to:
  /// **'Messpunkt nicht erreichbar: {name} · {live} von {total} Messpunkten aktiv'**
  String tapDown(String name, int live, int total);

  /// Monitor: Banner Messpunkt getrennt, zweite Zeile
  ///
  /// In de, this message translates to:
  /// **'Kein Busfehler: Die anderen laufen weiter, er verbindet sich von selbst neu. Was in der Lücke dort fehlt, gilt nicht als gefiltert.'**
  String get tapDownHint;

  /// Monitor: Hinweis, ein Messpunkt ist verbunden, sieht aber nichts
  ///
  /// In de, this message translates to:
  /// **'Verbunden, aber hier kommt nichts an: {name}'**
  String tapSilent(String name);

  /// Monitor: Hinweis stiller Messpunkt, zweiter Teil
  ///
  /// In de, this message translates to:
  /// **'Bei Routing gibt es im Netz oft keinen IP-Router (Tunnel-Schnittstellen leiten kein Routing weiter). Sonst Linie und Filtertabelle des Kopplers prüfen.'**
  String get tapSilentHint;

  /// Telegramm-Details: Abschnitt Messpunkte
  ///
  /// In de, this message translates to:
  /// **'Weg durch die Anlage'**
  String get detailsPath;

  /// Telegramm-Details: Sichtung an einem Messpunkt
  ///
  /// In de, this message translates to:
  /// **'+{ms} ms · Routingzähler {hop}'**
  String detailsPathSeen(String ms, int hop);

  /// Telegramm-Details: Messpunkt auf der Linie des Senders (höchster Hop)
  ///
  /// In de, this message translates to:
  /// **'Ursprung · Routingzähler {hop}'**
  String detailsPathFirst(int hop);

  /// Telegramm-Details: an diesem Messpunkt nicht gesehen
  ///
  /// In de, this message translates to:
  /// **'nicht gesehen, gefiltert oder nur lokal'**
  String get detailsPathMissing;

  /// Telegramm-Details: Messpunkt war zu der Zeit nicht erreichbar (Lücke)
  ///
  /// In de, this message translates to:
  /// **'nicht erreichbar zu dieser Zeit · keine Aussage, ob gefiltert'**
  String get tapPathAway;

  /// Telegramm-Details: Messpunkt war zu der Zeit pausiert
  ///
  /// In de, this message translates to:
  /// **'pausiert zu dieser Zeit · keine Aussage, ob gefiltert'**
  String get tapPathPaused;

  /// Telegramm-Details: Anzahl Koppler zwischen Ursprung und Messpunkt (aus dem Hop-Count)
  ///
  /// In de, this message translates to:
  /// **'{count} Koppler dazwischen'**
  String tapPathCouplers(int count);

  /// Monitor: Sammelzeichen in der Zeile, Messpunkte waren zu der Zeit nicht erreichbar (Tooltip, Bedienhilfe)
  ///
  /// In de, this message translates to:
  /// **'Zu dieser Zeit nicht erreichbar: {labels}'**
  String tapRowAway(String labels);

  /// Monitor: Trennzeile in der Live-Liste, ab hier war ein Messpunkt nicht erreichbar (Lücke beginnt). label: „Messpunkt 1.2“ live, „1.2 (Name)“ in einer Aufnahme
  ///
  /// In de, this message translates to:
  /// **'{label} nicht erreichbar · {time}'**
  String tapListGapStart(String label, String time);

  /// Monitor: Trennzeile in der Live-Liste, ab hier war der Messpunkt wieder erreichbar (Lücke endet). label wie bei tapListGapStart
  ///
  /// In de, this message translates to:
  /// **'{label} wieder erreichbar · {time}'**
  String tapListGapEnd(String label, String time);

  /// Verbinden: Meldung nach dem Entfernen eines Messpunkts
  ///
  /// In de, this message translates to:
  /// **'Messpunkt entfernt: {name}'**
  String tapPointRemoved(String name);

  /// Verbinden: Entfernen eines Messpunkts zurücknehmen
  ///
  /// In de, this message translates to:
  /// **'Rückgängig'**
  String get tapPointUndo;

  /// Messpunkt: Schalter aktiv/pausiert mit Namen (Bedienhilfe)
  ///
  /// In de, this message translates to:
  /// **'Messpunkt aktiv: {name}'**
  String tapPointActiveNamed(String name);

  /// Messpunkt: entfernen mit Namen (Bedienhilfe)
  ///
  /// In de, this message translates to:
  /// **'Messpunkt entfernen: {name}'**
  String tapPointRemoveNamed(String name);

  /// Suche nach Interfaces: Fehler, davor der Grund
  ///
  /// In de, this message translates to:
  /// **'Die Suche hat nicht geklappt.'**
  String get tapSearchFailed;

  /// Suche nach Interfaces: noch einmal
  ///
  /// In de, this message translates to:
  /// **'Erneut suchen'**
  String get tapSearchAgain;

  /// Suche nach Interfaces: zur Handeingabe
  ///
  /// In de, this message translates to:
  /// **'Adresse eingeben'**
  String get tapSearchByHand;

  /// Suche nach Interfaces: Hinweis auf die Handeingabe
  ///
  /// In de, this message translates to:
  /// **'Die Suche findet nur Interfaces im eigenen Netz. Eines in einem anderen Netz oder hinter einem VPN lässt sich mit seiner Adresse hinzufügen.'**
  String get tapSearchByHandHint;

  /// Messpunkt: Fehler in Klartext, Netz nicht erreichbar
  ///
  /// In de, this message translates to:
  /// **'Das Netz ist nicht erreichbar. WLAN oder VPN prüfen.'**
  String get tapErrorNetwork;

  /// Messpunkt: Fehler in Klartext, Verbindung abgelehnt
  ///
  /// In de, this message translates to:
  /// **'Die Gegenstelle nimmt die Verbindung nicht an. Adresse und Port prüfen.'**
  String get tapErrorRefused;

  /// Messpunkt: Fehler in Klartext, keine Antwort
  ///
  /// In de, this message translates to:
  /// **'Keine Antwort vom Interface.'**
  String get tapErrorNoAnswer;

  /// Messpunkt: Fehler in Klartext, sonstiger Grund
  ///
  /// In de, this message translates to:
  /// **'Die Verbindung kam nicht zustande.'**
  String get tapErrorOther;

  /// Monitor, breite Tabelle: Spalte mit den Messpunkten, an denen ein Telegramm gesehen wurde
  ///
  /// In de, this message translates to:
  /// **'Gesehen an'**
  String get tapColumnSeen;

  /// Messpunkt mit seinem Kurzzeichen (Linie), z. B. im Filter
  ///
  /// In de, this message translates to:
  /// **'Messpunkt {label}'**
  String tapNamed(String label);

  /// Monitor: Filter, nur an einem Messpunkt gesehen
  ///
  /// In de, this message translates to:
  /// **'Nur an einem Messpunkt'**
  String get tapQuickSingle;

  /// Monitor: Erklärung zum Filter Nur an einem Messpunkt
  ///
  /// In de, this message translates to:
  /// **'Lokal in seiner Linie geblieben oder vom Koppler gefiltert. Telegramme aus einer Lücke zählen nicht.'**
  String get tapQuickSingleHint;

  /// Projektprüfung: Name eines Beobachtungspunkts aus einem Messpunkt
  ///
  /// In de, this message translates to:
  /// **'Messpunkt {label}'**
  String tapObservation(String label);

  /// Monitor: Überschrift der Messpunkt-Karten
  ///
  /// In de, this message translates to:
  /// **'{count} Messpunkte · {live} verbunden'**
  String tapStripTitle(int count, int live);

  /// Messpunkt-Karte: Zustand
  ///
  /// In de, this message translates to:
  /// **'verbunden'**
  String get tapStateConnected;

  /// Messpunkt-Karte: Zustand nicht erreichbar
  ///
  /// In de, this message translates to:
  /// **'nicht erreichbar · kein Busfehler'**
  String get tapStateAway;

  /// Messpunkt-Karte: Zustand pausiert
  ///
  /// In de, this message translates to:
  /// **'pausiert'**
  String get tapStatePaused;

  /// Messpunkt-Karte: verbunden, es kommt nichts an
  ///
  /// In de, this message translates to:
  /// **'verbunden, aber still'**
  String get tapStateSilent;

  /// Messpunkt-Karte: Zustand verbindet
  ///
  /// In de, this message translates to:
  /// **'verbindet'**
  String get tapStateConnecting;

  /// Messpunkt-Karte: Telegramme pro Minute
  ///
  /// In de, this message translates to:
  /// **'{rate}/min'**
  String tapLoadRate(int rate);

  /// Messpunkt-Karte: Buslast an diesem Messpunkt
  ///
  /// In de, this message translates to:
  /// **'Buslast {percent} %'**
  String tapLoadPercent(String percent);

  /// Messpunkt-Karte: Wiederholungen an diesem Messpunkt
  ///
  /// In de, this message translates to:
  /// **'{count} wiederholt'**
  String tapLoadRepeats(int count);

  /// Messpunkt-Karte: gemessener Zeitversatz
  ///
  /// In de, this message translates to:
  /// **'Versatz bis {ms} ms'**
  String tapLag(String ms);

  /// Messpunkt-Karte: Zeitfenster, das sich selbst erweitert hat
  ///
  /// In de, this message translates to:
  /// **'Fenster {ms} ms (gemessen)'**
  String tapWindowAuto(int ms);

  /// Monitor: laufende Lücke eines Messpunkts
  ///
  /// In de, this message translates to:
  /// **'seit {from} · Lücke an {label}'**
  String tapGapOpen(String from, String label);

  /// Monitor: Lücke eines Messpunkts mit Anfang und Ende
  ///
  /// In de, this message translates to:
  /// **'{from} – {to} · Lücke an {label}'**
  String tapGapClosed(String from, String to, String label);

  /// Topologie: Abzeichen an einer Linie ohne Messpunkt
  ///
  /// In de, this message translates to:
  /// **'nur indirekt sichtbar'**
  String get tapLineIndirect;

  /// Topologie: Hinweis an einer Linie ohne Messpunkt
  ///
  /// In de, this message translates to:
  /// **'Kein Messpunkt in dieser Linie: Lokale Telegramme bleiben hier unsichtbar. Unter Verbinden einen Messpunkt hinzufügen.'**
  String get tapLineIndirectHint;

  /// Verbinden: wie viele Messpunkte verbunden werden
  ///
  /// In de, this message translates to:
  /// **'Verbinden öffnet {count} Verbindungen.'**
  String tapConnectCount(int count);

  /// Verbinden: über welchen Messpunkt gesendet wird
  ///
  /// In de, this message translates to:
  /// **'Gruppentelegramme sendet Messpunkt 1, Gerätezugriffe gehen über den Messpunkt in der Linie des Geräts.'**
  String get tapSendVia;

  /// Verbinden: Knopf, Interfaces für Messpunkte suchen
  ///
  /// In de, this message translates to:
  /// **'Im Netz suchen'**
  String get tapSearchRun;

  /// Dialogtitel: gefundene Interfaces ankreuzen
  ///
  /// In de, this message translates to:
  /// **'Interfaces als Messpunkte'**
  String get tapSearchTitle;

  /// Suche nach Interfaces: nichts gefunden
  ///
  /// In de, this message translates to:
  /// **'Kein Interface gefunden.'**
  String get tapSearchNone;

  /// Suche: angekreuzte Interfaces als Messpunkte hinzufügen
  ///
  /// In de, this message translates to:
  /// **'{count} hinzufügen'**
  String tapSearchAdd(int count);

  /// Suche: Interface ist schon Messpunkt
  ///
  /// In de, this message translates to:
  /// **'schon Messpunkt'**
  String get tapSearchAlready;

  /// Suche: Gerät bietet keinen Tunnel
  ///
  /// In de, this message translates to:
  /// **'kann nur Routing, über „Messpunkt hinzufügen“ wählen'**
  String get tapSearchRoutingOnly;

  /// Suche: Interface hat keinen freien Tunnel
  ///
  /// In de, this message translates to:
  /// **'alle {total} Tunnel belegt'**
  String tapSearchNoTunnel(int total);

  /// Suche: Interface bringt keine neue Linie
  ///
  /// In de, this message translates to:
  /// **'gleiche Linie wie ein anderer Messpunkt, nur zur Gegenprobe'**
  String get tapSearchSameLine;

  /// Suche: Interface in einer Linie ohne Messpunkt
  ///
  /// In de, this message translates to:
  /// **'neue Linie'**
  String get tapSearchNewLine;

  /// Suche: Hinweis vor dem Hinzufügen, letzter freier Tunnel
  ///
  /// In de, this message translates to:
  /// **'Der letzte freie Tunnel wird belegt: {names}. Brauchen ETS oder Visualisierung ihn, den Messpunkt pausieren.'**
  String tapSearchLastTunnel(String names);

  /// Vorgeschlagener Name eines Messpunkts aus Linie und Gerät
  ///
  /// In de, this message translates to:
  /// **'Linie {line} · {name}'**
  String tapSearchName(String line, String name);

  /// Messpunkt hinzufügen: dieselbe Verbindung gibt es schon
  ///
  /// In de, this message translates to:
  /// **'Diese Verbindung ist schon ein Messpunkt.'**
  String get tapDuplicate;

  /// Verbinden: Demo mit zwei Messpunkten starten
  ///
  /// In de, this message translates to:
  /// **'Im Demo-Haus ausprobieren'**
  String get tapDemo;

  /// Verbinden: Erklärung zur Demo mit Messpunkten
  ///
  /// In de, this message translates to:
  /// **'Zwei Linien, zwei Messpunkte: weitergeleitet, gefiltert, und ein Messpunkt fällt zeitweise aus.'**
  String get tapDemoHint;

  /// Demo: Name des zweiten Messpunkts
  ///
  /// In de, this message translates to:
  /// **'Linie 1.2 · Demo-Interface'**
  String get tapDemoName;

  /// Demo: Fehlertext, wenn der zweite Messpunkt ausfällt
  ///
  /// In de, this message translates to:
  /// **'Demo: Interface antwortet nicht'**
  String get tapDemoDown;

  /// Import error: .xknx file cannot be read
  ///
  /// In de, this message translates to:
  /// **'Keine lesbare Projektdatei des XKNX Editors (.xknx).'**
  String get projectXknxInvalid;

  /// Project check section: devices without any download
  ///
  /// In de, this message translates to:
  /// **'Geräte nie programmiert'**
  String get checkDevicesNeverProgrammed;

  /// Explanation for checkDevicesNeverProgrammed
  ///
  /// In de, this message translates to:
  /// **'Laut Projekt wurde auf diese Geräte noch nie ein Download gemacht: noch nicht in Betrieb genommen oder gar nicht verbaut. Prüfen, ob sie antworten, dann programmieren oder aus dem Projekt löschen.'**
  String get checkDevicesNeverProgrammedHint;

  /// Project check section: devices changed since the last download
  ///
  /// In de, this message translates to:
  /// **'Download ausstehend'**
  String get checkDevicesPendingDownload;

  /// Explanation for checkDevicesPendingDownload
  ///
  /// In de, this message translates to:
  /// **'Im Projekt nach dem letzten Download geändert, aber noch nicht ins Gerät geladen (wie Adr/Prg/Par/Grp/Kfg in der ETS). Bis zum Programmieren arbeitet das Gerät mit dem alten Stand.'**
  String get checkDevicesPendingDownloadHint;

  /// Part of a device download: individual address
  ///
  /// In de, this message translates to:
  /// **'Adresse'**
  String get downloadPartAddress;

  /// Part of a device download: application program
  ///
  /// In de, this message translates to:
  /// **'Applikation'**
  String get downloadPartApplication;

  /// Part of a device download: parameters
  ///
  /// In de, this message translates to:
  /// **'Parameter'**
  String get downloadPartParameters;

  /// Part of a device download: group communication
  ///
  /// In de, this message translates to:
  /// **'Gruppenadressen'**
  String get downloadPartGroups;

  /// Part of a device download: medium configuration
  ///
  /// In de, this message translates to:
  /// **'Medium'**
  String get downloadPartMedium;

  /// Title of the handover to the XKNX Editor
  ///
  /// In de, this message translates to:
  /// **'An XKNX Editor übergeben'**
  String get xknxEditorTitle;

  /// Explanation of the handover to the XKNX Editor
  ///
  /// In de, this message translates to:
  /// **'Busclear übergibt Korrekturen (Datentypen, Namen, neue Adressen, K- und L-Flags) und schreibt die übrigen Befunde als Kommentar an Adressen und Geräte. Programmiert wird nichts; im Editor lässt sich alles rückgängig machen.'**
  String get xknxEditorText;

  /// Size of the handover
  ///
  /// In de, this message translates to:
  /// **'{corrections} Korrekturen, {notes} Notizen'**
  String xknxEditorSummary(int corrections, int notes);

  /// Handover without content
  ///
  /// In de, this message translates to:
  /// **'Nichts zu übergeben: keine Aufgaben aus der Projektprüfung.'**
  String get xknxEditorNothing;

  /// Field: address of the editor's MCP server
  ///
  /// In de, this message translates to:
  /// **'Adresse des MCP-Servers'**
  String get xknxEditorEndpoint;

  /// Field: token of the editor's MCP server
  ///
  /// In de, this message translates to:
  /// **'Bearer-Token (optional)'**
  String get xknxEditorToken;

  /// Hint where to find the MCP settings
  ///
  /// In de, this message translates to:
  /// **'Im XKNX Editor unter Einstellungen › KI/MCP den Server starten; Adresse und Token stehen dort.'**
  String get xknxEditorConnectionHint;

  /// Button: hand over to the editor
  ///
  /// In de, this message translates to:
  /// **'Übergeben'**
  String get xknxEditorSend;

  /// Button: save the handover as JSON
  ///
  /// In de, this message translates to:
  /// **'Als Datei speichern'**
  String get xknxEditorSaveFile;

  /// File name prefix of the handover file
  ///
  /// In de, this message translates to:
  /// **'XKNX-Editor-Aufgaben'**
  String get xknxEditorFile;

  /// Handover error: no project open
  ///
  /// In de, this message translates to:
  /// **'Im XKNX Editor ist kein Projekt geöffnet.'**
  String get xknxEditorNoProject;

  /// Warning: different projects
  ///
  /// In de, this message translates to:
  /// **'Im Editor ist „{editor}“ geöffnet, in Busclear „{busclear}“. Trotzdem übergeben?'**
  String xknxEditorOtherProject(String editor, String busclear);

  /// Handover error: connection
  ///
  /// In de, this message translates to:
  /// **'XKNX Editor nicht erreichbar: {error}'**
  String xknxEditorUnreachable(String error);

  /// Handover error: token missing or wrong
  ///
  /// In de, this message translates to:
  /// **'Der Editor verlangt ein Token (Einstellungen › KI/MCP).'**
  String get xknxEditorUnauthorized;

  /// Handover result
  ///
  /// In de, this message translates to:
  /// **'{corrections} Korrekturen übernommen, {notes} Notizen geschrieben. Geänderte Geräte im Editor programmieren.'**
  String xknxEditorDone(int corrections, int notes);

  /// Heading of the failed handover steps
  ///
  /// In de, this message translates to:
  /// **'Nicht übernommen:'**
  String get xknxEditorFailed;

  /// Button: download preview through the editor
  ///
  /// In de, this message translates to:
  /// **'Mit Projekt vergleichen (XKNX Editor)'**
  String get xknxEditorPreview;

  /// Download preview: no difference
  ///
  /// In de, this message translates to:
  /// **'Gerät entspricht dem Projekt im Editor.'**
  String get xknxEditorPreviewSame;

  /// Download preview: difference
  ///
  /// In de, this message translates to:
  /// **'Ein Download würde {bytes} Byte der Konfiguration ändern: Gerät und Projekt weichen ab.'**
  String xknxEditorPreviewDiff(int bytes);

  /// Explanation of the download preview
  ///
  /// In de, this message translates to:
  /// **'Liest das Gerät über die Busverbindung des Editors und schreibt nichts. Kann je nach Gerät einige Minuten dauern.'**
  String get xknxEditorPreviewHint;

  /// Note in the XKNX Editor for a never programmed device
  ///
  /// In de, this message translates to:
  /// **'Nie programmiert: laut Projekt noch kein Download auf dieses Gerät.'**
  String get xknxNoteNeverProgrammed;

  /// Button: take over the project of Home Assistant's KNX integration
  ///
  /// In de, this message translates to:
  /// **'Aus Home Assistant'**
  String get catalogFromHomeAssistant;

  /// Tooltip of catalogFromHomeAssistant
  ///
  /// In de, this message translates to:
  /// **'Projekt der KNX-Integration übernehmen (dort hochgeladen oder vom XKNX Editor gesendet)'**
  String get catalogFromHomeAssistantTooltip;

  /// Import from Home Assistant: no project there
  ///
  /// In de, this message translates to:
  /// **'Die KNX-Integration von Home Assistant hat kein Projekt. Im KNX-Panel ein Projekt hochladen oder es aus dem XKNX Editor senden.'**
  String get catalogHaNoProject;

  /// Import from Home Assistant failed
  ///
  /// In de, this message translates to:
  /// **'Projekt aus Home Assistant nicht abrufbar: {error}'**
  String catalogHaFailed(String error);

  /// Error: token would be sent over plain HTTP on the network
  ///
  /// In de, this message translates to:
  /// **'Den Token schickt Busclear nur über HTTPS oder an diesen Rechner. Für einen anderen Rechner im Netz den Editor mit HTTPS betreiben.'**
  String get xknxEditorInsecure;

  /// Title of the AI access settings
  ///
  /// In de, this message translates to:
  /// **'KI-Zugriff (MCP)'**
  String get aiAccessTitle;

  /// Subtitle of the AI access row
  ///
  /// In de, this message translates to:
  /// **'Verlauf, Befunde und Projektprüfung für KI-Werkzeuge'**
  String get aiAccessMeta;

  /// Explanation of the AI access
  ///
  /// In de, this message translates to:
  /// **'KI-Werkzeuge wie Claude lesen über das Model Context Protocol den aufgezeichneten Bus, die Befunde und die Projektprüfung und können zusammen mit dem XKNX Editor Korrekturen vorschlagen. Busclear sendet dabei nichts auf den Bus und ändert nichts.'**
  String get aiAccessText;

  /// Switch for the MCP server
  ///
  /// In de, this message translates to:
  /// **'KI-Zugriff erlauben'**
  String get aiAccessEnable;

  /// Subtitle of the switch
  ///
  /// In de, this message translates to:
  /// **'Nur lesen, mit Token'**
  String get aiAccessReadOnly;

  /// Privacy notice of the AI access
  ///
  /// In de, this message translates to:
  /// **'Wer den Token hat, liest den ganzen Verlauf, aus dem sich Anwesenheit ablesen lässt. Token nur in eigenen Werkzeugen eintragen und bei Verdacht erneuern. Im Add-on geht die Verbindung im Heimnetz unverschlüsselt (HTTP); die Box nutzt HTTPS.'**
  String get aiAccessPrivacy;

  /// Label: MCP endpoint
  ///
  /// In de, this message translates to:
  /// **'Adresse'**
  String get aiAccessEndpoint;

  /// Label: MCP bearer token
  ///
  /// In de, this message translates to:
  /// **'Token'**
  String get aiAccessToken;

  /// Heading of the setup command
  ///
  /// In de, this message translates to:
  /// **'Für Claude Code'**
  String get aiAccessCommand;

  /// Button: copy the setup command
  ///
  /// In de, this message translates to:
  /// **'Befehl kopieren'**
  String get aiAccessCopyCommand;

  /// Button: renew the MCP token
  ///
  /// In de, this message translates to:
  /// **'Neuen Token erzeugen'**
  String get aiAccessRenew;

  /// Message after copying
  ///
  /// In de, this message translates to:
  /// **'Kopiert'**
  String get aiAccessCopied;

  /// Section of the project check: evaluation of the recorded history
  ///
  /// In de, this message translates to:
  /// **'Projekt gegen Bus ({days} Tage)'**
  String checkSectionEvidence(int days);

  /// Finding: device sends where the project says it cannot
  ///
  /// In de, this message translates to:
  /// **'Gerät sendet anders als im Projekt'**
  String get checkUnexpectedSenders;

  /// Explanation of checkUnexpectedSenders
  ///
  /// In de, this message translates to:
  /// **'Diese Geräte senden auf Adressen, auf denen sie laut Projekt nicht senden. Das Gerät trägt dann nicht den Projektstand: nach dem letzten Download geändert, getauscht oder das Projekt ist veraltet. Mit dem XKNX Editor vergleichen (Diagnose › Mit Projekt vergleichen).'**
  String get checkUnexpectedSendersHint;

  /// Row of an unexpected sender
  ///
  /// In de, this message translates to:
  /// **'sendet auf {group}'**
  String checkUnexpectedSenderRow(String group);

  /// Finding: actuator status does not answer commands
  ///
  /// In de, this message translates to:
  /// **'Befehl ohne Rückmeldung'**
  String get checkNoFeedback;

  /// Explanation of checkNoFeedback
  ///
  /// In de, this message translates to:
  /// **'Auf Befehle antwortet der Status desselben Kanals selten oder nie innerhalb von 5 Sekunden. Mögliche Ursachen: Aktor führt nicht aus, Filtertabelle, ausstehender Download, oder der Aktor meldet nur bei einer Änderung.'**
  String get checkNoFeedbackHint;

  /// Row of a command without feedback
  ///
  /// In de, this message translates to:
  /// **'Status {status} von {device}: {answered} von {commands} beantwortet'**
  String checkNoFeedbackRow(String status, String device, int answered, int commands);

  /// Finding: several project senders really heard
  ///
  /// In de, this message translates to:
  /// **'Mehrere Sender, im Verlauf bestätigt'**
  String get checkSendersConfirmed;

  /// Explanation of checkSendersConfirmed
  ///
  /// In de, this message translates to:
  /// **'Von den Adressen mit mehreren Sendern im Projekt haben hier wirklich mehrere gesendet. Bei Reglern oder Stellwerten überschreiben sie sich gegenseitig.'**
  String get checkSendersConfirmedHint;

  /// Finding: status addresses without R that were read
  ///
  /// In de, this message translates to:
  /// **'Leseanfragen ohne Antwort'**
  String get checkReadsUnanswered;

  /// Explanation of checkReadsUnanswered
  ///
  /// In de, this message translates to:
  /// **'Statusadressen ohne L-Flag, die im Verlauf gelesen wurden: so oft blieb die Antwort aus.'**
  String get checkReadsUnansweredHint;

  /// Row of reads without answer
  ///
  /// In de, this message translates to:
  /// **'{reads} Leseanfragen, {answered} beantwortet'**
  String checkReadsRow(int reads, int answered);

  /// Finding: DPT suggestions for addresses without one
  ///
  /// In de, this message translates to:
  /// **'Datentyp aus dem Verlauf'**
  String get checkDptSuggestions;

  /// Explanation of checkDptSuggestions
  ///
  /// In de, this message translates to:
  /// **'Für Adressen ohne Datentyp schlägt Busclear einen vor, aus Länge und Werten der Telegramme und dem Namen. „Sicher“ heißt: eindeutige Länge und passender Name. Über „An XKNX Editor übergeben“ oder in der ETS eintragen.'**
  String get checkDptSuggestionsHint;

  /// Certainty of a DPT suggestion: high
  ///
  /// In de, this message translates to:
  /// **'sicher'**
  String get checkDptSure;

  /// Certainty of a DPT suggestion: medium
  ///
  /// In de, this message translates to:
  /// **'wahrscheinlich'**
  String get checkDptLikely;

  /// Finding: contact or alarm stuck on 1
  ///
  /// In de, this message translates to:
  /// **'Zustand ungewöhnlich lange gleich'**
  String get checkLongStates;

  /// Explanation of checkLongStates
  ///
  /// In de, this message translates to:
  /// **'Kontakt- oder Alarmadressen, die über Tage immer wieder 1 senden, ohne je zu wechseln, etwa „gekippt“ bei geschlossenem Fenster. Kontakt klemmt oder die Polarität ist falsch eingestellt.'**
  String get checkLongStatesHint;

  /// Row of a long state
  ///
  /// In de, this message translates to:
  /// **'seit {days} Tagen 1, {count} Telegramme'**
  String checkLongStateRow(String days, int count);

  /// Finding: presence at night
  ///
  /// In de, this message translates to:
  /// **'Auslösungen in der Nacht'**
  String get checkNightActivity;

  /// Explanation of checkNightActivity
  ///
  /// In de, this message translates to:
  /// **'Präsenz- oder Bewegungsmelder, die in den meisten Nächten zwischen 0 und 5 Uhr auslösen. Sieht der Melder in ein Schlafzimmer, reagiert er auf ein Haustier, oder ist er zu empfindlich?'**
  String get checkNightActivityHint;

  /// Row of night activity
  ///
  /// In de, this message translates to:
  /// **'in {nights} von {recorded} Nächten, {per} Auslösungen je Nacht'**
  String checkNightRow(int nights, int recorded, String per);

  /// Button: download preview for all devices through the editor
  ///
  /// In de, this message translates to:
  /// **'Alle Geräte vergleichen'**
  String get xknxEditorCompareAll;

  /// Explanation of the comparison of all devices
  ///
  /// In de, this message translates to:
  /// **'Der Editor liest jedes programmierte Gerät über seine Busverbindung und vergleicht es mit dem Projekt. Schreibt nichts, belastet aber den Bus und dauert je Gerät bis zu einigen Minuten: am besten abends oder nachts laufen lassen.'**
  String get xknxEditorCompareAllHint;

  /// Progress of the comparison
  ///
  /// In de, this message translates to:
  /// **'{done} von {total}: {device}'**
  String xknxEditorCompareProgress(int done, int total, String device);

  /// Result of the comparison
  ///
  /// In de, this message translates to:
  /// **'{differ} von {total} Geräten weichen vom Projekt ab, {failed} nicht erreichbar.'**
  String xknxEditorCompareResult(int differ, int total, int failed);

  /// Button: stop the comparison after the current device
  ///
  /// In de, this message translates to:
  /// **'Anhalten'**
  String get xknxEditorCompareStop;

  /// Note in the XKNX Editor for a likely DPT
  ///
  /// In de, this message translates to:
  /// **'Datentyp laut Verlauf wahrscheinlich {dpt}: prüfen und setzen.'**
  String xknxNoteDptLikely(String dpt);

  /// Mac: Auswahl beim Teilen einer Datei, im Finder speichern
  ///
  /// In de, this message translates to:
  /// **'Sichern unter …'**
  String get shareSaveAs;

  /// Mac: Auswahl beim Teilen einer Datei, Teilen-Menü des Systems
  ///
  /// In de, this message translates to:
  /// **'Teilen …'**
  String get shareShare;

  /// Verlauf: Lücke, ein weiterer Messpunkt war nicht erreichbar (kein Busfehler)
  ///
  /// In de, this message translates to:
  /// **'Messpunkt {name} {duration} nicht erreichbar'**
  String outageTap(String name, String duration);

  /// Topologie: Abzeichen an einer Linie mit Messpunkt
  ///
  /// In de, this message translates to:
  /// **'Messpunkt'**
  String get topoTapPoint;

  /// Topologie: Messpunkte zeigen, dass ein Koppler eine benötigte Gruppenadresse sperrt
  ///
  /// In de, this message translates to:
  /// **'{ga} {name} kommt von Linie {from} nicht in Linie {to} an ({count} Telegramme), obwohl dort Geräte darauf hören. Filtertabelle des Kopplers prüfen.'**
  String topoFilterBlocked(String ga, String name, String from, String to, int count);

  /// Topologie: Messpunkte zeigen unnötig durchgelassene Telegramme
  ///
  /// In de, this message translates to:
  /// **'{ga} {name} kommt von Linie {from} in Linie {to} an ({count} Telegramme), obwohl dort niemand darauf hört.'**
  String topoFilterLeaked(String ga, String name, String from, String to, int count);

  /// Diagramm: Kennzahl Belegung der Leitung in Prozent
  ///
  /// In de, this message translates to:
  /// **'Buslast'**
  String get busMetricLoad;

  /// Monitor: Überschrift der Wochenübersicht aus der Daueraufzeichnung
  ///
  /// In de, this message translates to:
  /// **'Letzte {days} Tage'**
  String weekSumTitle(int days);

  /// Wochenübersicht: keine Befunde
  ///
  /// In de, this message translates to:
  /// **'Der Bus lief unauffällig.'**
  String get weekSumAllGood;

  /// Wochenübersicht: nur Hinweise
  ///
  /// In de, this message translates to:
  /// **'Der Bus lief stabil, {count, plural, =1{ein Hinweis} other{{count} Hinweise}} für die Anlage.'**
  String weekSumHints(int count);

  /// Wochenübersicht: mindestens eine Warnung
  ///
  /// In de, this message translates to:
  /// **'Es gab Auffälligkeiten, die du dir ansehen solltest.'**
  String get weekSumWarn;

  /// Wochenübersicht: Kennzahl
  ///
  /// In de, this message translates to:
  /// **'Telegramme/Tag'**
  String get weekSumPerDay;

  /// Wochenübersicht: Kennzahl
  ///
  /// In de, this message translates to:
  /// **'Buslast Ø / max'**
  String get weekSumLoad;

  /// Wochenübersicht: Anteil der Zeit mit Aufzeichnung
  ///
  /// In de, this message translates to:
  /// **'Aufzeichnung'**
  String get weekSumAvailability;

  /// Wochenübersicht: Kennzahl
  ///
  /// In de, this message translates to:
  /// **'Wiederholungen'**
  String get weekSumRepeatsLabel;

  /// Wochenübersicht: weitere Befunde aufklappen
  ///
  /// In de, this message translates to:
  /// **'{count} weitere'**
  String weekSumMore(int count);

  /// Wochenübersicht: Befunde zuklappen
  ///
  /// In de, this message translates to:
  /// **'Weniger'**
  String get weekSumLess;

  /// Topologie: Kennzeichen einer KNX-RF-Linie (kurz, als Plakette)
  ///
  /// In de, this message translates to:
  /// **'Funk'**
  String get topoRf;

  /// Topologie: Hinweis über der Seite, wenn das Projekt eine Funklinie hat
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{Linie {lines} ist eine Funklinie} other{Die Linien {lines} sind Funklinien}} (KNX RF). Busclear sieht ihre Telegramme über den Medienkoppler, aber weder Signalstärke noch Batteriezustand der Funkgeräte.'**
  String topoRfHint(String lines, int count);

  /// Topologie: Knopf im Funk-Hinweis, öffnet das öffentliche Issue zur Funk-Diagnose
  ///
  /// In de, this message translates to:
  /// **'Mehr zu Funk? Abstimmen'**
  String get topoRfVote;

  /// Wochenübersicht: Karte auf Titel und Kernsatz verkleinern (Tooltip)
  ///
  /// In de, this message translates to:
  /// **'Einklappen'**
  String get weekSumCollapse;

  /// Wochenübersicht: eingeklappte Karte wieder ganz zeigen (Tooltip)
  ///
  /// In de, this message translates to:
  /// **'Aufklappen'**
  String get weekSumExpand;

  /// Wochenübersicht: Menüeintrag, blendet die Karte bis zum nächsten Montag aus
  ///
  /// In de, this message translates to:
  /// **'Diese Woche nicht mehr anzeigen'**
  String get weekSumHideWeek;

  /// Wochenübersicht: Menüeintrag, schaltet die Karte ab (wieder an im Menü „Mehr“)
  ///
  /// In de, this message translates to:
  /// **'Nicht mehr anzeigen'**
  String get weekSumHideAlways;

  /// Menü „Mehr“: Schalter, ob die Karte „Letzte 7 Tage“ in der Übersicht erscheint
  ///
  /// In de, this message translates to:
  /// **'Wochenüberblick in der Übersicht'**
  String get weekSumToggle;

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Mehrere Zeitgeber: {senders} senden Datum/Uhrzeit auf {groups}, zusammen {share} des Verkehrs. Einer, alle 10 bis 60 Minuten, reicht.'**
  String weekSumClocks(String senders, String groups, String share);

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Auf Leseanfragen antworten mehrere Geräte: {groups}{count, plural, =1{} other{ ({count} Adressen)}}. Das L-Flag gehört nur an den Sender.'**
  String weekSumMultiResponders(String groups, int count);

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'{sender} liest viele Adressen auf einmal, bis {perMinute} Leseanfragen je Minute (z. B. Statusabgleich von Home Assistant).'**
  String weekSumReadStorms(String sender, int perMinute);

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Sehr häufig gesendet: {groups}. Eine höhere Sendeschwelle entlastet den Bus.'**
  String weekSumChatty(String groups);

  /// Befund: Projektgeräte, die nichts gesendet haben
  ///
  /// In de, this message translates to:
  /// **'Ohne Telegramm: {devices}{count, plural, =1{} other{ ({count} Geräte)}}.'**
  String weekSumSilent(String devices, int count);

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Absender nicht im Projekt: {senders}.'**
  String weekSumUnknown(String senders);

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'{count} Wiederholungen ({share}): Quittungen fehlen, Leitung oder Gerät prüfen.'**
  String weekSumRepeats(int count, String share);

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Buslast zeitweise hoch, bis {max} in einer Minute.'**
  String weekSumLoadHigh(String max);

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Die Busverbindung brach {count, plural, =1{einmal} other{{count}-mal}} ab, zusammen {minutes} min.'**
  String weekSumDisconnected(int count, int minutes);

  /// Befund
  ///
  /// In de, this message translates to:
  /// **'Messpunkt {taps} war zeitweise nicht erreichbar, zusammen {minutes} min.'**
  String weekSumTapGaps(String taps, int minutes);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
