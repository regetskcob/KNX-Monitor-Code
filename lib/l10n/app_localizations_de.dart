// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get splashSubtitle => 'Gruppenmonitor für KNXnet/IP';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String groupAddressCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Gruppenadressen',
      one: '1 Gruppenadresse',
    );
    return '$_temp0';
  }

  @override
  String deviceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Geräte',
      one: '1 Gerät',
    );
    return '$_temp0';
  }

  @override
  String get connectSubtitle => 'Mit KNX/IP-Gateway verbinden';

  @override
  String get connectGateway => 'Gateway';

  @override
  String get connectPort => 'Port';

  @override
  String get connectHostEmpty => 'IP-Adresse eingeben';

  @override
  String get connectHostIpv4Only => 'Nur IPv4';

  @override
  String get connectHostInvalid => 'Ungültige Adresse';

  @override
  String get connectButton => 'Verbinden';

  @override
  String get connectRecent => 'Zuletzt verwendet';

  @override
  String get connectViewRecordings => 'Aufnahmen ansehen';

  @override
  String get catalogNone => 'Keine Gruppenadressen';

  @override
  String get catalogImported => 'importiert';

  @override
  String get catalogHint =>
      'ETS-Projekt (.knxproj) oder Gruppenadressen-CSV für Namen, Datentypen & Geräte';

  @override
  String get catalogReplace => 'Ersetzen';

  @override
  String get catalogImport => 'Importieren';

  @override
  String catalogImportedSnack(String summary) {
    return '$summary importiert';
  }

  @override
  String catalogImportFailed(String error) {
    return 'Import fehlgeschlagen: $error';
  }

  @override
  String get catalogPickFile => 'Bitte eine .knxproj- oder .csv-Datei wählen.';

  @override
  String get passwordTitle => 'Projektpasswort';

  @override
  String get passwordWrong =>
      'Das Passwort war falsch. Bitte erneut versuchen.';

  @override
  String get passwordPrompt =>
      'Das ETS-Projekt ist geschützt. Das Passwort wird nur zum Öffnen verwendet und nicht gespeichert.';

  @override
  String get passwordLabel => 'Passwort';

  @override
  String get passwordShow => 'Anzeigen';

  @override
  String get passwordHide => 'Verbergen';

  @override
  String get passwordOpen => 'Öffnen';

  @override
  String get activityLast60s => 'letzte 60 s';

  @override
  String get activityOverRecording => 'über die Aufnahme';

  @override
  String get typeWrite => 'Schreiben';

  @override
  String get typeRead => 'Lesen';

  @override
  String get typeResponse => 'Antwort';

  @override
  String get issueRepeatedLabel => 'Wiederholt';

  @override
  String get issueRepeatedHint =>
      'Erster Versuch nicht quittiert – Teilnehmer fehlt oder Linie gestört.';

  @override
  String get issueNotConfirmedLabel => 'Nicht quittiert';

  @override
  String get issueNotConfirmedHint =>
      'Kein Empfänger hat das Telegramm bestätigt.';

  @override
  String get issueUnansweredLabel => 'Keine Antwort';

  @override
  String get issueUnansweredHint =>
      'Kein Gerät hat geantwortet – Lese-Flag oder Status-Sender fehlt?';

  @override
  String get issueSizeMismatchLabel => 'Länge ≠ DPT';

  @override
  String get issueSizeMismatchHint =>
      'Die Datenlänge passt nicht zum Datenpunkttyp aus dem Projekt.';

  @override
  String get issueUnknownAddressLabel => 'Nicht im Projekt';

  @override
  String get issueUnknownAddressHint =>
      'Diese Gruppenadresse ist im ETS-Projekt nicht angelegt.';

  @override
  String get issueUnknownDeviceLabel => 'Gerät unbekannt';

  @override
  String get issueUnknownDeviceHint =>
      'Die physikalische Adresse ist im ETS-Projekt keinem Gerät zugeordnet.';

  @override
  String get issueUnusualHopLabel => 'Hop';

  @override
  String get issueUnusualHopHint =>
      'Routingzähler ≠ 6: Telegramm lief über Koppler (oder 7 = unbegrenzt).';

  @override
  String get issueCentralOffOnLabel => 'Zentral-Aus mit Ein';

  @override
  String get issueCentralOffOnHint =>
      'Laut Name eine Zentral-Aus-Adresse, aber der Wert ist 1 – je nach Aktor schaltet das alles ein. Zentral-Aus sollte nur 0 senden.';

  @override
  String errorSocket(String error) {
    return 'Socket-Fehler: $error';
  }

  @override
  String get errorGatewayNoResponse => 'Gateway antwortet nicht.';

  @override
  String errorNetwork(String error) {
    return 'Netzwerkfehler: $error';
  }

  @override
  String get errorNotConnected => 'Nicht verbunden.';

  @override
  String errorTelegramRejected(String status) {
    return 'Gateway hat Telegramm abgelehnt (0x$status).';
  }

  @override
  String get errorNoAck => 'Keine Bestätigung vom Gateway.';

  @override
  String get errorClosedByGateway => 'Verbindung vom Gateway beendet.';

  @override
  String get errorGatewayStoppedResponding => 'Gateway antwortet nicht mehr.';

  @override
  String get errorNoFreeTunnel => 'Gateway meldet: keine freien Tunnel.';

  @override
  String get errorTunnelUnsupported =>
      'Gateway unterstützt keinen Tunnelbetrieb.';

  @override
  String get errorOptionUnsupported =>
      'Gateway unterstützt die Verbindungsoption nicht.';

  @override
  String errorConnectionRejected(String status) {
    return 'Verbindung abgelehnt (Status 0x$status).';
  }

  @override
  String get projectPasswordWrong => 'Falsches Projektpasswort.';

  @override
  String get projectPasswordRequired => 'Projekt ist passwortgeschützt.';

  @override
  String get projectInvalidFile => 'Keine gültige .knxproj-Datei.';

  @override
  String get projectDefaultDevice => 'Gerät';

  @override
  String get projectDefaultGroup => 'Gruppenadresse';

  @override
  String get projectNoGroups => 'Projekt enthält keine Gruppenadressen.';

  @override
  String get projectNoData => 'Keine Projektdaten in der Datei gefunden.';

  @override
  String get projectMissing0xml => '0.xml fehlt im Projekt.';

  @override
  String projectUnreadable(String error) {
    return 'Projekt nicht lesbar: $error';
  }

  @override
  String get csvEmpty => 'Datei ist leer.';

  @override
  String get csvNoAddressColumn => 'Keine Adressspalte gefunden.';

  @override
  String get csvNoGroups => 'Keine Gruppenadressen gefunden.';

  @override
  String get dpt1Off => 'Aus';

  @override
  String get dpt1On => 'Ein';

  @override
  String get dpt1False => 'Falsch';

  @override
  String get dpt1True => 'Wahr';

  @override
  String get dpt1Disable => 'Gesperrt';

  @override
  String get dpt1Enable => 'Freigegeben';

  @override
  String get dpt1NoAlarm => 'Kein Alarm';

  @override
  String get dpt1Alarm => 'Alarm';

  @override
  String get dpt1Decrease => 'Verringern';

  @override
  String get dpt1Increase => 'Erhöhen';

  @override
  String get dpt1Up => 'Auf';

  @override
  String get dpt1Down => 'Ab';

  @override
  String get dpt1Open => 'Offen';

  @override
  String get dpt1Close => 'Geschlossen';

  @override
  String get dpt1Stop => 'Stopp';

  @override
  String get dpt1Start => 'Start';

  @override
  String get dpt1Inactive => 'Inaktiv';

  @override
  String get dpt1Active => 'Aktiv';

  @override
  String get dpt1Trigger => 'Trigger';

  @override
  String get dpt1NotOccupied => 'Nicht belegt';

  @override
  String get dpt1Occupied => 'Belegt';

  @override
  String get dpt1Closed => 'Geschlossen';

  @override
  String get dpt1Opened => 'Offen';

  @override
  String get dpt1Day => 'Tag';

  @override
  String get dpt1Night => 'Nacht';

  @override
  String get dpt2Forced => 'Zwang';

  @override
  String get dpt2Free => 'Frei';

  @override
  String get dpt3Brighter => 'Heller';

  @override
  String get dpt3Darker => 'Dunkler';

  @override
  String dptSceneNumber(int number) {
    return 'Szene $number';
  }

  @override
  String dptSceneStore(int number) {
    return 'Szene $number speichern';
  }

  @override
  String dptSceneRecall(int number) {
    return 'Szene $number abrufen';
  }

  @override
  String get dptSceneLearn => 'lernen';

  @override
  String get hvacAuto => 'Auto';

  @override
  String get hvacComfort => 'Komfort';

  @override
  String get hvacStandby => 'Standby';

  @override
  String get hvacEconomy => 'Nacht';

  @override
  String get hvacProtection => 'Frostschutz';

  @override
  String get dptNameSwitch => 'Schalten';

  @override
  String get dptNameUpDown => 'Auf/Ab';

  @override
  String get dptNamePercent => 'Prozent';

  @override
  String get dptNameCounter => 'Zähler';

  @override
  String get dptNameSigned => 'Vorzeichen';

  @override
  String get dptNameScene => 'Szene';

  @override
  String get dptNameFloat => 'Gleitkomma';

  @override
  String get dptNameTime => 'Uhrzeit';

  @override
  String get dptNameDate => 'Datum';

  @override
  String get dptNameDateTime => 'Datum/Zeit';

  @override
  String get dptNameText => 'Text';

  @override
  String get weekdayMon => 'Mo';

  @override
  String get weekdayTue => 'Di';

  @override
  String get weekdayWed => 'Mi';

  @override
  String get weekdayThu => 'Do';

  @override
  String get weekdayFri => 'Fr';

  @override
  String get weekdaySat => 'Sa';

  @override
  String get weekdaySun => 'So';

  @override
  String get writeFormatSwitch => 'Ein/Aus';

  @override
  String get writeFormatNumber => 'Zahl 0–255';

  @override
  String get writeFormatDecimal => 'Kommazahl';

  @override
  String get writeFormatScene => 'Szene 1–64';

  @override
  String get writeFormatHex => 'Hex-Rohdaten';

  @override
  String get writeFormatLabel => 'Format';

  @override
  String get writeValueLabel => 'Wert';

  @override
  String get writeButton => 'Schreiben';

  @override
  String writeDone(String value) {
    return 'Geschrieben: $value';
  }

  @override
  String writeInvalidValue(String format) {
    return 'Ungültiger Wert für $format.';
  }

  @override
  String get confirmAcknowledged => 'vom Bus bestätigt';

  @override
  String get confirmNotAcknowledged => 'nicht quittiert – kein Empfänger?';

  @override
  String get confirmNoConfirmation => 'keine Bestätigung vom Gateway';

  @override
  String get sendInvalidAddress => 'Ungültige Gruppenadresse.';

  @override
  String sendReadSent(String confirmation) {
    return 'Leseanfrage gesendet$confirmation. Die Antwort erscheint im Monitor.';
  }

  @override
  String get sendTitle => 'Gruppenadresse lesen / schreiben';

  @override
  String get sendReadValue => 'Wert lesen';

  @override
  String get sendGroupAddress => 'Gruppenadresse';

  @override
  String get sendGroupAddressHint => '1/2/3 oder Name';

  @override
  String activitySemantics(String period) {
    return 'Busaktivität $period';
  }

  @override
  String get activityRate => 'Tel./min jetzt';

  @override
  String get activityTotal => 'Gesamt';

  @override
  String get healthRepeated => 'Wiederholt';

  @override
  String get healthRepeatedTooltip =>
      'Wiederholte Telegramme – Hinweis auf fehlende Quittungen';

  @override
  String get healthUnanswered => 'Ohne Antwort';

  @override
  String get healthUnansweredTooltip =>
      'Leseanfragen ohne Antwort innerhalb von 3 s';

  @override
  String get rowSent => 'Gesendet';

  @override
  String get rowThisTunnel => 'dieser Tunnel';

  @override
  String get columnTime => 'Zeit';

  @override
  String get columnType => 'Art';

  @override
  String get columnAddress => 'Adresse';

  @override
  String get columnName => 'Name';

  @override
  String get columnSender => 'Absender';

  @override
  String get columnValue => 'Wert';

  @override
  String badgeSentTooltip(String type) {
    return '$type (gesendet)';
  }

  @override
  String badgeSentSemantics(String type) {
    return '$type, gesendet';
  }

  @override
  String get legendOutlinedSent => 'umrandet: selbst gesendet';

  @override
  String get liveWaiting => 'Warte auf Telegramme …';

  @override
  String get liveNewest => 'Neueste';

  @override
  String get commonSave => 'Speichern';

  @override
  String get monitorExportTitle => 'KNX-Telegramme';

  @override
  String get monitorClear => 'Monitor leeren';

  @override
  String get monitorImport => 'ETS-Projekt oder CSV importieren …';

  @override
  String get monitorRemoveProject => 'Projektdaten entfernen';

  @override
  String get monitorDisconnect => 'Trennen';

  @override
  String get monitorConnecting => 'Verbinde …';

  @override
  String get monitorDisconnected => 'Getrennt';

  @override
  String get monitorConnected => 'Verbunden';

  @override
  String get monitorResume => 'Fortsetzen';

  @override
  String get monitorPause => 'Anzeige pausieren';

  @override
  String get monitorConnectionLost => 'Verbindung getrennt.';

  @override
  String get monitorReconnect => 'Neu verbinden';

  @override
  String recordingDefaultName(String date, String time) {
    return 'Aufnahme $date $time';
  }

  @override
  String recordingSaved(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Telegramme',
      one: '1 Telegramm',
    );
    return '„$name“ gespeichert · $_temp0';
  }

  @override
  String get recordingView => 'Ansehen';

  @override
  String get recordingStart => 'Aufnahme starten';

  @override
  String get recordingEdit => 'Aufnahme bearbeiten';

  @override
  String get recordingSave => 'Aufnahme speichern';

  @override
  String recordingCaptured(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Telegramme aufgenommen.',
      one: '1 Telegramm aufgenommen.',
    );
    return '$_temp0';
  }

  @override
  String get recordingName => 'Name';

  @override
  String get recordingNoteLabel => 'Notiz (optional)';

  @override
  String get recordingNoteHint => 'Was wurde geprüft? Befund?';

  @override
  String get recordingContinue => 'Weiter aufnehmen';

  @override
  String get recordingStopAndSave => 'Beenden & speichern';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get labelTelegrams => 'Telegramme';

  @override
  String telegramCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Telegramme',
      one: '1 Telegramm',
    );
    return '$_temp0';
  }

  @override
  String get recordingsTitle => 'Aufnahmen';

  @override
  String get recordingsEmpty =>
      'Noch keine Aufnahmen – im Monitor auf „Aufnehmen“ tippen.';

  @override
  String get recordingsStart => 'Beginn';

  @override
  String get recordingsDuration => 'Dauer';

  @override
  String get recordingDeleteTitle => 'Aufnahme löschen?';

  @override
  String recordingDeleteText(String name) {
    return '„$name“ wird endgültig entfernt.';
  }

  @override
  String get recordingPdf => 'Aufnahme als PDF';

  @override
  String get recordingEditMenu => 'Name & Notiz bearbeiten';

  @override
  String get recordingDeleteMenu => 'Aufnahme löschen';

  @override
  String get playerPause => 'Wiedergabe anhalten';

  @override
  String get playerPlay => 'Aufnahme abspielen';

  @override
  String get playerRestart => 'Zum Anfang';

  @override
  String get playerSpeed => 'Geschwindigkeit';

  @override
  String get commonMore => 'Mehr';

  @override
  String get tabOverview => 'Über­sicht';

  @override
  String get tabLive => 'Live';

  @override
  String get filterHint => 'Filter: 1/2/3, 1.1.5, Wert …';

  @override
  String get filterHintProject => 'Filter: Name, Gerät, 1/2/3, Wert …';

  @override
  String get filterClear => 'Filter löschen';

  @override
  String get selectForPdfTooltip => 'Telegramme auswählen für PDF';

  @override
  String get selectForPdf => 'Auswählen für PDF';

  @override
  String get exportAllPdf => 'Alles als PDF';

  @override
  String get selectEnd => 'Auswahl beenden';

  @override
  String get selectTitle => 'Telegramme auswählen';

  @override
  String selectCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String get selectNone => 'Keine';

  @override
  String get selectAll => 'Alle';

  @override
  String selectExport(int count) {
    return 'Als PDF ($count)';
  }

  @override
  String get commonClose => 'Schließen';

  @override
  String get commonNo => 'Nein';

  @override
  String detailsHistoryPdfName(String name) {
    return 'Verlauf $name';
  }

  @override
  String detailsSummaryLine(String type, String sender, String time) {
    return '$type von $sender um $time';
  }

  @override
  String get detailsIssues => 'Hinweise';

  @override
  String get detailsHistory => 'Verlauf';

  @override
  String get detailsChart => 'Diagramm';

  @override
  String get detailsList => 'Liste';

  @override
  String get detailsHistoryPdf => 'Verlauf als PDF exportieren';

  @override
  String get detailsWriteValue => 'Wert schreiben';

  @override
  String detailsReadSent(String confirmation) {
    return 'Leseanfrage gesendet$confirmation';
  }

  @override
  String get detailsCurrent => 'Aktuell';

  @override
  String get detailsComment => 'Kommentar';

  @override
  String get detailsRemember => 'Merken';

  @override
  String get detailsFilter => 'Filtern';

  @override
  String get detailsCopied => 'In die Zwischenablage kopiert';

  @override
  String get detailsCopy => 'Kopieren';

  @override
  String get detailsTelegram => 'Telegramm';

  @override
  String get detailsDescription => 'Beschreibung';

  @override
  String get detailsPriority => 'Priorität';

  @override
  String get prioritySystem => 'System';

  @override
  String get priorityNormal => 'Normal';

  @override
  String get priorityUrgent => 'Dringend';

  @override
  String get priorityLow => 'Niedrig';

  @override
  String get detailsRepeatedYes => 'Ja – erster Versuch nicht quittiert';

  @override
  String get detailsHopCount => 'Routingzähler';

  @override
  String get detailsHopDirect => 'direkt';

  @override
  String get detailsHopUnlimited => 'unbegrenzt';

  @override
  String detailsHopCouplers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'über $count Koppler',
      one: 'über 1 Koppler',
    );
    return '$_temp0';
  }

  @override
  String get detailsConfirmation => 'Bestätigung';

  @override
  String get detailsAcknowledged =>
      'Vom Bus quittiert – empfangen; ob ausgeführt, zeigt die Rückmeldung';

  @override
  String get detailsData => 'Daten';

  @override
  String detailsLinkedDevices(int count) {
    return 'Verknüpfte Geräte ($count)';
  }

  @override
  String get detailsInterpretations => 'Mögliche Deutungen';

  @override
  String get detailsMoreInterpretations => 'Weitere Deutungen';

  @override
  String get detailsSentLower => 'gesendet';

  @override
  String detailsOlder(int count) {
    return '… und $count ältere';
  }

  @override
  String detailsObject(int number) {
    return 'KO $number';
  }

  @override
  String get detailsSends => 'sendet';

  @override
  String get detailsReceives => 'empfängt';

  @override
  String chartSemantics(int count, String last) {
    return 'Verlaufsdiagramm mit $count Werten, zuletzt $last';
  }

  @override
  String get boardBrightness => 'Helligkeit';

  @override
  String boardMainGroup(int number) {
    return 'Hauptgruppe $number';
  }

  @override
  String get boardEmpty => 'Noch keine Werte empfangen';

  @override
  String boardSectionSemantics(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Adressen',
      one: '1 Adresse',
    );
    return '$title, $_temp0';
  }

  @override
  String get diagnosticsTitle => 'Diagnose';

  @override
  String get diagNotInProject => 'nicht im Projekt';

  @override
  String get diagScopeStatus => 'Rückmeldungen';

  @override
  String get diagProgTitle => 'Programmiermodus';

  @override
  String get diagProgText =>
      'Findet Geräte, deren Programmier-LED leuchtet – z. B. wenn die ETS „mehrere Geräte im Programmiermodus“ meldet.';

  @override
  String get diagSearching => 'Suche läuft …';

  @override
  String get diagSearch => 'Suchen';

  @override
  String get diagProgNone => 'Kein Gerät im Programmiermodus.';

  @override
  String get diagAddressInvalid =>
      'Bitte eine physikalische Adresse wie 1.1.18 eingeben.';

  @override
  String get diagAddressTitle => 'Physikalische Adresse prüfen';

  @override
  String get diagAddressText =>
      'Prüft wie die ETS, ob eine Adresse belegt ist, und liest die Maskenversion des Geräts.';

  @override
  String get diagCheck => 'Prüfen';

  @override
  String get diagAddressPresent => 'belegt';

  @override
  String get diagAddressFree => 'frei – kein Gerät hat quittiert';

  @override
  String get diagAddressUnknown => 'unklar – keine Bestätigung vom Gateway';

  @override
  String diagMaskVersion(String mask) {
    return 'Maskenversion $mask';
  }

  @override
  String get pdfPeriod => 'Zeitraum';

  @override
  String get pdfValues => 'Werte';

  @override
  String get pdfMinimum => 'Minimum';

  @override
  String get pdfMaximum => 'Maximum';

  @override
  String get pdfAverage => 'Mittelwert';

  @override
  String pdfFooterCreated(String date, String time) {
    return 'Erstellt mit KNX Monitor · $date $time Uhr';
  }

  @override
  String pdfPage(int page, int total) {
    return 'Seite $page von $total';
  }

  @override
  String get pdfNote => 'Notiz';

  @override
  String get pdfThisDevice => 'dieses Gerät';

  @override
  String get boardWeather => 'Wetter';

  @override
  String get boardEnergy => 'Energie & Leistung';

  @override
  String get boardDateTime => 'Datum & Zeit';

  @override
  String get activitySent => 'Gesendet';

  @override
  String get boardAlarms => 'Alarme & Störungen';

  @override
  String get alarmLabel => 'Alarm';

  @override
  String get faultLabel => 'Störung';

  @override
  String get activityAlarms => 'Alarme aktiv';

  @override
  String get detailsAlarmTitle => 'Aktive Meldung';

  @override
  String get detailsAlarmAlarm => 'Diese Adresse meldet einen Alarm.';

  @override
  String get detailsAlarmFault =>
      'Diese Adresse meldet eine Störung bzw. einen Defekt.';

  @override
  String get quickAlarm => 'Alarme';

  @override
  String get quickRepeated => 'Wiederholt';

  @override
  String get quickUnanswered => 'Ohne Antwort';

  @override
  String get quickUnknown => 'Nicht im Projekt';

  @override
  String get savedFilters => 'Gespeicherte Filter';

  @override
  String get saveCurrentFilter => 'Aktuellen Filter speichern';

  @override
  String get noSavedFilters => 'Noch keine gespeicherten Filter';

  @override
  String get deleteFilter => 'Gespeicherten Filter löschen';

  @override
  String get filterHelp => 'Filter-Hilfe';

  @override
  String get filterHelpBody =>
      'Leerzeichen = UND · Komma = ODER · -begriff = NICHT\n\n1/2/3 exakt · 1/2 Bereich · 1/*/3 oder 1/2/1* mit Platzhalter\n1.1.5 Absender · 1.1.* Linie · von:1.1.5\n\ntyp:w|r|a (Schreiben, Lesen, Antwort)\ndpt:9 oder dpt:9.001\nzeit:14:05 · zeit:14:05-14:10 (Uhrzeit, ohne das Ende)\nist:alarm · ist:wiederholt · ist:antwort · ist:projekt\nist:eigen · ist:fremd (selbst gesendet bzw. vom Bus)\n\nAlles andere sucht in Name, Bereich, Gerät und Wert – Umlaute egal (kuche findet Küche).\n\nMehrere ODER-Gruppen bekommen in der Liste je eine Farbe. „Kontext“ zeigt die Sekunden vor und nach jedem Treffer.\n\nBeispiele:\n1/*/* ist:antwort – unbeantwortete Leseanfragen in Hauptgruppe 1\nküche, bad -schalten – Küche oder Bad, ohne Schalten';

  @override
  String get checkTitle => 'Projekt-Abgleich';

  @override
  String get checkNoProject =>
      'Importiere ein ETS-Projekt oder eine Gruppenadressen-CSV, um den Busverkehr damit abzugleichen.';

  @override
  String get checkUnknownAddresses => 'Gruppenadressen nicht im Projekt';

  @override
  String get checkUnknownDevices => 'Absender nicht im Projekt';

  @override
  String get checkSizeMismatch => 'Datenlänge passt nicht zum DPT';

  @override
  String get checkNeverSeen => 'Nie auf dem Bus gesehen';

  @override
  String get checkAllGood => 'Keine Abweichungen';

  @override
  String checkSenders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Absender',
      one: '1 Absender',
    );
    return '$_temp0';
  }

  @override
  String checkGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Gruppenadressen',
      one: '1 Gruppenadresse',
    );
    return '$_temp0';
  }

  @override
  String checkExpected(String expected, String seen) {
    return 'erwartet $expected, gesehen $seen';
  }

  @override
  String checkBytes(int count) {
    return '$count Byte';
  }

  @override
  String get checkSmall => '≤ 6 bit';

  @override
  String checkMore(int count) {
    return '… und $count weitere';
  }

  @override
  String get checkNeverSeenHint =>
      'Hängt vom Beobachtungszeitraum ab – selten genutzte Adressen tauchen erst später auf.';

  @override
  String get gatewayTitle => 'Gateway';

  @override
  String get gatewayAddress => 'Adresse';

  @override
  String get gatewayMedium => 'Medium';

  @override
  String get gatewayIndividual => 'Physikalische Adresse';

  @override
  String get gatewaySerial => 'Seriennummer';

  @override
  String get gatewayMac => 'MAC-Adresse';

  @override
  String get gatewayMulticast => 'Routing-Multicast';

  @override
  String get gatewayProgMode => 'Programmiermodus';

  @override
  String get gatewayTunnel => 'Dieser Tunnel';

  @override
  String gatewayTunnelValue(String address, int channel) {
    return '$address · Kanal $channel';
  }

  @override
  String get gatewayServices => 'Unterstützte Dienste';

  @override
  String get gatewaySlots => 'Tunnelplätze';

  @override
  String get gatewaySlotFree => 'frei';

  @override
  String get gatewaySlotBusy => 'belegt';

  @override
  String get gatewayUnknown =>
      'Das Gateway hat noch keine Selbstbeschreibung geliefert.';

  @override
  String get yes => 'Ja';

  @override
  String get no => 'Nein';

  @override
  String get scanGateways => 'Gateways suchen';

  @override
  String get scanRunning => 'Suche im lokalen Netz …';

  @override
  String get scanNone => 'Kein KNXnet/IP-Gerät gefunden.';

  @override
  String get scanFound => 'Gefunden';

  @override
  String get statsTitle => 'Statistik';

  @override
  String get statsSpan => 'Zeitraum';

  @override
  String get statsPerMinute => 'Ø Tel./min';

  @override
  String get monitorPauseShort => 'Pause';

  @override
  String get statsPerMinuteShort => 'Tel./Min';

  @override
  String get statsSendersShort => 'Sender';

  @override
  String get statsGroupsShort => 'Adressen';

  @override
  String get statsSenders => 'Top-Sender';

  @override
  String get statsGroups => 'Top-Gruppenadressen';

  @override
  String get statsFlappers => 'Sendet auffällig oft';

  @override
  String get statsFlappersHint =>
      'Im Mittel öfter als alle 10 s – zu kurze Sendezyklen oder Messwerte ohne Hysterese?';

  @override
  String get statsPeaks => 'Lastspitzen';

  @override
  String statsRepeatRate(String rate) {
    return '$rate wiederholt';
  }

  @override
  String statsEvery(String interval) {
    return 'alle $interval';
  }

  @override
  String statsPerSecond(int count) {
    return '$count Tel./s';
  }

  @override
  String get statsEmpty => 'Noch keine Telegramme für eine Statistik.';

  @override
  String get statsPdfTitle => 'Bus-Statistik';

  @override
  String get triggerTitle => 'Trigger-Aufnahme';

  @override
  String get triggerExplain =>
      'Nimmt automatisch auf, sobald die Bedingung eintritt – inklusive der Telegramme davor. Ideal für sporadische Fehler.';

  @override
  String get triggerCondition => 'Bedingung';

  @override
  String get triggerKindAddress => 'Gruppenadresse';

  @override
  String get triggerKindAlarm => 'Alarm oder Störung';

  @override
  String get triggerKindRepeated => 'Wiederholtes Telegramm';

  @override
  String get triggerKindUnanswered => 'Leseanfrage ohne Antwort';

  @override
  String get triggerKindUnknown => 'Adresse nicht im Projekt';

  @override
  String get triggerValue => 'Wert enthält (optional)';

  @override
  String triggerPre(int count) {
    return 'Vorlauf: $count Telegramme';
  }

  @override
  String triggerPost(int count) {
    return 'Nachlauf: $count Telegramme';
  }

  @override
  String get triggerRearm => 'Danach erneut scharf schalten';

  @override
  String get triggerArm => 'Scharf schalten';

  @override
  String get triggerDisarm => 'Trigger aus';

  @override
  String get triggerArmed => 'Trigger scharf';

  @override
  String get triggerRecording => 'Trigger nimmt auf';

  @override
  String triggerFired(String name) {
    return 'Trigger ausgelöst: „$name“ gespeichert';
  }

  @override
  String triggerRecordingName(String condition) {
    return 'Trigger: $condition';
  }

  @override
  String triggerNote(String condition, String time, int pre, int post) {
    return 'Automatisch aufgenommen. Bedingung: $condition. Ausgelöst um $time, $pre Telegramme Vorlauf, $post Nachlauf.';
  }

  @override
  String get triggerInvalidAddress =>
      'Bitte eine Gruppenadresse wie 1/2/3 eingeben.';

  @override
  String get exportAllCsv => 'Alles als CSV';

  @override
  String get exportAllEts => 'Alles als ETS-Telegrammdatei';

  @override
  String get exportCsv => 'Als CSV';

  @override
  String get exportEts => 'Als ETS-Telegrammdatei';

  @override
  String exportSaved(String name) {
    return 'Gespeichert: $name';
  }

  @override
  String exportFailed(String error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String get recordingsImport => 'ETS-Telegrammdatei importieren';

  @override
  String recordingsImported(String name, int count) {
    return '„$name“ importiert · $count Telegramme';
  }

  @override
  String recordingsImportFailed(String error) {
    return 'Import fehlgeschlagen: $error';
  }

  @override
  String get scanTitle => 'Linienscan';

  @override
  String get scanExplain =>
      'Prüft alle Adressen einer Linie wie die ETS und gleicht sie mit dem Projekt ab. Ein voller Scan dauert einige Minuten.';

  @override
  String get scanLine => 'Linie';

  @override
  String scanRange(int from, int to) {
    return 'Teilnehmer $from–$to';
  }

  @override
  String get scanStart => 'Scan starten';

  @override
  String get scanInvalidLine => 'Bitte eine Linie wie 1.1 eingeben.';

  @override
  String get scanPresent => 'Belegt';

  @override
  String get scanMissing => 'Im Projekt, antwortet nicht';

  @override
  String get scanUnexpected => 'Antwortet, nicht im Projekt';

  @override
  String get scanChecked => 'Geprüft';

  @override
  String get mapGraphSelected => 'Verbindungen';

  @override
  String get mapGraphHint =>
      'Zoomen zeigt mehr Details. Tippe auf ein Gerät für seine Verbindungen.';

  @override
  String get mapGraphAll => 'Alle Geräte';

  @override
  String get mapGraphUnlinked => 'Geräte ohne Verbindung';

  @override
  String get mapTitle => 'Kommunikationskarte';

  @override
  String get mapSenders => 'Sender';

  @override
  String get mapReceivers => 'Empfänger (Projekt)';

  @override
  String get mapListens => 'Hört auf';

  @override
  String get mapSends => 'Sendet auf';

  @override
  String get mapNone => 'Keine';

  @override
  String mapObserved(int count) {
    return '$count× beobachtet';
  }

  @override
  String get mapProjectOnly => 'nur im Projekt';

  @override
  String get mapNotInProject => 'nicht im Projekt verknüpft';

  @override
  String get mapSearch => 'Adresse oder Gerät suchen …';

  @override
  String get mapEmpty => 'Noch kein Busverkehr für eine Karte.';

  @override
  String get mapHint =>
      'Antippen rückt einen Knoten in die Mitte. Linien: durchgezogen = beobachtet, gestrichelt = nur im Projekt.';

  @override
  String get historyTitle => 'Langzeitverlauf';

  @override
  String get historyExplain =>
      'Speichert jeden Tag allen Busverkehr, solange der Monitor verbunden ist – zum nachträglichen Ansehen, Abspielen und Exportieren.';

  @override
  String get historyOff => 'Aus';

  @override
  String historyDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage',
      one: '1 Tag',
    );
    return '$_temp0';
  }

  @override
  String historyUsage(String size) {
    return 'Belegt: $size';
  }

  @override
  String historyDayName(String date) {
    return 'Verlauf $date';
  }

  @override
  String get historyDeleteAll => 'Verlauf löschen';

  @override
  String get historyEmpty => 'Noch keine Tage gespeichert.';

  @override
  String get historyOffConfirmTitle => 'Verlauf ausschalten?';

  @override
  String get historyOffConfirm => 'Ausschalten und löschen';

  @override
  String recordingsImportTooLarge(int mb) {
    return 'Die Datei ist mit $mb MB zu groß für eine Aufnahme. Exportiere einen kürzeren Zeitraum (höchstens 100 MB).';
  }

  @override
  String get backupRestorePartialTitle =>
      'Sicherung nur teilweise zurückgespielt';

  @override
  String backupRestorePartial(int count) {
    return '$count Dateien sind schon aus der Sicherung, danach ist ein Fehler aufgetreten (zum Beispiel voller Speicher). Die App startet jetzt neu. Spiel die Sicherung danach noch einmal ein.';
  }

  @override
  String get historyOffHint => 'Ausschalten löscht den gespeicherten Verlauf.';

  @override
  String get tabObjects => 'Ob­jekte';

  @override
  String get objectsEmpty =>
      'Noch keine Objekte erkannt – dafür braucht es Gruppenadressen mit Namensschema (z. B. „EG FL F01 Auf/Ab“) und Busverkehr.';

  @override
  String get objectsOther => 'Weitere';

  @override
  String get objectCommands => 'Befehle';

  @override
  String get objectFeedback => 'Rückmeldungen';

  @override
  String get objectFilter => 'Monitor auf dieses Objekt filtern';

  @override
  String get objectHint =>
      'Erkannt am gemeinsamen Namensanfang. Durchgezogen = Wert empfangen, gestrichelt = noch kein Telegramm.';

  @override
  String objectMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Adressen',
      one: '1 Adresse',
    );
    return '$_temp0';
  }

  @override
  String get diagDeviceInfo => 'Geräteinfo lesen';

  @override
  String get diagDeviceInfoFailed => 'Gerät hat keine Verbindung angenommen.';

  @override
  String get devManufacturer => 'Hersteller';

  @override
  String get devSerial => 'Seriennummer';

  @override
  String get devSerialMatch => 'stimmt mit Projekt überein';

  @override
  String devSerialMismatch(String serial) {
    return 'weicht vom Projekt ab ($serial)';
  }

  @override
  String get devOrder => 'Bestellnummer';

  @override
  String get devHardware => 'Hardware-Typ';

  @override
  String get devFirmware => 'Firmware';

  @override
  String get devProgMode => 'Programmiermodus';

  @override
  String get devApplication => 'Applikation';

  @override
  String get devMask => 'Maskenversion';

  @override
  String get devOn => 'an';

  @override
  String get devOff => 'aus';

  @override
  String get devUnsupported => 'nicht unterstützt';

  @override
  String get expertMode => 'Expertenmodus';

  @override
  String get expertModeHint =>
      'Werkzeuge, Exporte und alle Kennzahlen direkt anzeigen';

  @override
  String get toolsTitle => 'Werkzeuge';

  @override
  String get toolDiagnostics =>
      'Programmiermodus, Adressen prüfen, Geräteinfo, Linienscan';

  @override
  String get toolCheck => 'Busverkehr mit dem ETS-Projekt abgleichen';

  @override
  String get toolStats => 'Häufigste Adressen und Absender, Ausreißer';

  @override
  String get toolMap => 'Wer spricht mit wem';

  @override
  String get toolTrigger => 'Aufnahme automatisch bei einem Ereignis starten';

  @override
  String get toolRecordings => 'Gespeicherte Aufnahmen und Langzeitverlauf';

  @override
  String get exportMenu => 'Exportieren';

  @override
  String get planFeatureFullExport =>
      'Volle Exporte: ETS-Datei, ZIP, Diagramme';

  @override
  String get exportSelect => 'Telegramme auswählen …';

  @override
  String get exportSelectHint =>
      'Nur bestimmte Telegramme als PDF, CSV oder ETS-Datei';

  @override
  String get projectMenu => 'ETS-Projekt';

  @override
  String get projectRemove => 'Entfernen';

  @override
  String get projectHintRaw =>
      'Ohne ETS-Projekt siehst du nur Rohwerte. Mit Projekt erscheinen Namen, Einheiten und Geräte.';

  @override
  String get commonDismiss => 'Ausblenden';

  @override
  String monitorRetryIn(int seconds) {
    return 'Neuer Versuch in $seconds s';
  }

  @override
  String get sectionPin => 'Oben anheften';

  @override
  String get sectionUnpin => 'Nicht mehr anheften';

  @override
  String get sectionPinHint => 'Lange drücken zum Anheften';

  @override
  String get busmonTitle => 'Busmonitor';

  @override
  String get busmonTool =>
      'Alle Frames auf der Leitung: Quittungen, Wiederholungen, gestörte Telegramme';

  @override
  String get busmonHint =>
      'Zeigt alles auf der Leitung, auch Quittungen und gestörte Telegramme. Der Live-Monitor pausiert so lange und verbindet sich danach wieder.';

  @override
  String get busmonConnecting => 'Busmonitor wird gestartet …';

  @override
  String busmonFailed(String error) {
    return 'Busmonitor nicht möglich: $error';
  }

  @override
  String get busmonRetry => 'Erneut versuchen';

  @override
  String get busmonFrames => 'Frames';

  @override
  String get busmonTelegrams => 'Telegramme';

  @override
  String get busmonAck => 'ACK';

  @override
  String get busmonNegative => 'NAK/BUSY';

  @override
  String get busmonErrors => 'Fehler';

  @override
  String get busmonRepeated => 'Wiederholt';

  @override
  String get busmonUnacked => 'Ohne ACK';

  @override
  String get busmonHideAcks => 'Quittungen ausblenden';

  @override
  String get busmonOnlyProblems => 'Nur Auffälligkeiten';

  @override
  String get busmonEmpty => 'Noch nichts auf der Leitung';

  @override
  String get busmonChecksum => 'Prüfsumme falsch';

  @override
  String get busmonStatusError => 'Übertragungsfehler';

  @override
  String get busmonIndividual => 'Einzeladressiert';

  @override
  String get busmonAckText => 'Quittung: angenommen';

  @override
  String get busmonNakText => 'Quittung: abgelehnt (NAK)';

  @override
  String get busmonBusyText => 'Quittung: beschäftigt (BUSY)';

  @override
  String get busmonNakBusyText => 'Quittung: NAK + BUSY';

  @override
  String get busmonUnknownText => 'Nicht lesbarer Frame';

  @override
  String get favorites => 'Favoriten';

  @override
  String get favoriteAdd => 'Als Favorit oben anheften';

  @override
  String get favoriteRemove => 'Aus den Favoriten entfernen';

  @override
  String get busmonLoad => 'Buslast';

  @override
  String get busmonLoadHint =>
      'Belegung der Leitung (TP, 9600 bit/s), Mittel der letzten 10 s. Dauerhaft über 50 % deutet auf Probleme hin.';

  @override
  String busmonLoadPeak(String value) {
    return 'Spitze $value %';
  }

  @override
  String get busmonSenders => 'Absender';

  @override
  String get busmonSendersHint =>
      'Geräte mit Wiederholungen oder fehlenden Quittungen zuerst. Tippen filtert die Liste.';

  @override
  String get busmonDetails => 'Frame-Details';

  @override
  String get busmonTapHint => 'Frame antippen für Details';

  @override
  String get busmonFieldControl => 'Steuerfeld';

  @override
  String get busmonFieldRepeat => 'Wiederholung';

  @override
  String get busmonFieldHops => 'Hop-Count';

  @override
  String get busmonFieldLength => 'Länge';

  @override
  String get busmonFieldPayload => 'Nutzdaten';

  @override
  String get busmonFieldChecksum => 'Prüfsumme';

  @override
  String get busmonFieldStatus => 'Status';

  @override
  String get busmonFieldTimestamp => 'Gateway-Zeit';

  @override
  String get busmonFieldAck => 'Quittung';

  @override
  String get busmonFieldSource => 'Quelle';

  @override
  String get busmonFieldTarget => 'Ziel';

  @override
  String get busmonFieldRaw => 'Rohdaten';

  @override
  String get busmonYes => 'ja';

  @override
  String get busmonNo => 'nein';

  @override
  String get busmonChecksumOk => 'korrekt';

  @override
  String busmonChecksumBad(String expected) {
    return 'falsch (erwartet $expected)';
  }

  @override
  String busmonStatusOk(int seq) {
    return 'fehlerfrei, Sequenz $seq';
  }

  @override
  String busmonSenderStats(int frames) {
    return '$frames Frames';
  }

  @override
  String notifyAlarmTitle(String name) {
    return 'Alarm: $name';
  }

  @override
  String notifyFaultTitle(String name) {
    return 'Störung: $name';
  }

  @override
  String get notifyMenu => 'Alarm-Mitteilungen';

  @override
  String get filterNoMatch => 'Nichts passt zum Filter';

  @override
  String get emptyMonitorHint =>
      'Viele Geräte senden nur bei Änderung. Den aktuellen Stand kannst du aktiv abfragen.';

  @override
  String get emptyReadStatus => 'Status lesen';

  @override
  String get topoTitle => 'Topologie';

  @override
  String get topoTool =>
      'Linien, Koppler und linienübergreifende Kommunikation';

  @override
  String get topoHint =>
      'Aus ETS-Projekt und beobachtetem Verkehr. Das Gateway sieht seine eigene Linie und nur das, was Koppler aus anderen Linien weiterleiten. Der Hop-Count zeigt, über wie viele Koppler ein Telegramm kam.';

  @override
  String topoLine(String line) {
    return 'Linie $line';
  }

  @override
  String get topoGatewayHere => 'Gateway';

  @override
  String get topoDevices => 'Geräte';

  @override
  String get topoActive => 'Aktiv';

  @override
  String get topoTelegrams => 'Telegramme';

  @override
  String get topoCouplers => 'Koppler bis Gateway';

  @override
  String topoCoupler(String address, String name) {
    return 'Koppler $address · $name';
  }

  @override
  String get topoNotInProject => 'nicht im Projekt (Tunnel/Visu?)';

  @override
  String get topoSilent => 'nicht gesehen';

  @override
  String get topoCross => 'Linienübergreifend';

  @override
  String get topoCrossHint =>
      'Adressen mit Geräten in mehreren Linien: welche Linien senden, welche zuhören, und wie viele Telegramme aus anderen Linien schon beobachtet wurden.';

  @override
  String get topoCheck => 'Koppler prüfen';

  @override
  String get topoCheckHint =>
      'Liest Adressen, deren sendendes Gerät hinter einem Koppler sitzt. Antwortet es, leitet der Koppler in beide Richtungen weiter. Nur Leseanfragen – es wird nichts geschaltet.';

  @override
  String topoCheckRunning(int done, int total) {
    return 'Prüfe $done / $total …';
  }

  @override
  String topoCheckPassed(String source) {
    return 'Antwort von $source';
  }

  @override
  String get topoCheckNoAnswer =>
      'keine Antwort – Filtertabelle oder Lesen-Flag';

  @override
  String get topoCheckNone =>
      'Keine Adresse mit sendendem Gerät hinter einem Koppler.';

  @override
  String get topoIssues => 'Auffälligkeiten';

  @override
  String get topoNoIssues => 'Keine Auffälligkeiten im bisherigen Verkehr.';

  @override
  String topoMismatch(String source, int observed, int expected) {
    return '$source kommt mit Hop-Count $observed statt $expected – sitzt wahrscheinlich in einer anderen Linie, als die Adresse sagt.';
  }

  @override
  String topoUnneeded(String address, String name, int count) {
    return '$address $name: $count× aus anderer Linie weitergeleitet, obwohl hier laut Projekt niemand zuhört. Für Visualisierungen (X1, Home Assistant) oft gewollt, sonst leitet der Koppler evtl. alles weiter.';
  }

  @override
  String get topoNoProject =>
      'Für die Topologie wird ein ETS-Projekt (.knxproj) mit Geräten benötigt; ohne Projekt zeigt die Ansicht nur beobachtete Absender.';

  @override
  String topoSends(String lines) {
    return 'sendet $lines';
  }

  @override
  String topoListens(String lines) {
    return 'hört $lines';
  }

  @override
  String get topoCheckNoReadFlag =>
      'keine Antwort, Telegramme kommen aber durch den Koppler – Lesen-Flag fehlt';

  @override
  String get devSent => 'Gesendet';

  @override
  String get devReceived => 'Empfangen';

  @override
  String get devGroups => 'Adressen';

  @override
  String get devReceivedHint =>
      'Telegramme an Gruppenadressen, mit denen das Gerät laut Projekt verknüpft ist.';

  @override
  String get devNoLinks =>
      'Nicht im Projekt – empfangene Telegramme lassen sich nicht zuordnen.';

  @override
  String get devNothing => 'Noch keine Telegramme';

  @override
  String get devFilterMonitor => 'Im Monitor filtern';

  @override
  String devLineHops(String line, String hops) {
    return 'Linie $line · Hop $hops';
  }

  @override
  String get projectTitle => 'ETS-Projekt';

  @override
  String get historyDeleteConfirm =>
      'Gesamten Langzeitverlauf löschen? Das lässt sich nicht rückgängig machen.';

  @override
  String get activityLastHour => 'letzte Stunde';

  @override
  String get activityToday => 'heute';

  @override
  String get livePlainTitle => 'Klartext in Live';

  @override
  String get livePlainHint => 'Sätze statt Adressen';

  @override
  String get activityRangeHint => 'Tippen wechselt den Zeitraum';

  @override
  String get boardValves => 'Ventile & Stellgrößen';

  @override
  String get diagOwnTunnel => 'Tunnel dieser App';

  @override
  String diagGatewayTunnel(String name) {
    return 'vermutlich Tunnel von $name';
  }

  @override
  String get topoTunnels => 'Tunnel';

  @override
  String get mapOverview => 'Übersicht';

  @override
  String get mapGroups => 'Gruppenadressen';

  @override
  String get mapDevices => 'Geräte';

  @override
  String get commTitle => 'Inbetriebnahme';

  @override
  String get commTool => 'Status-Adressen lesen, abhaken, Protokoll als PDF';

  @override
  String get commExplain =>
      'Liest Status- und Rückmeldeadressen nacheinander (5 pro Sekunde). Antworten werden automatisch abgehakt; Punkte ohne Antwort oder vor Ort geprüfte Funktionen bewertest du von Hand. Die Liste bleibt gespeichert, bis du neu beginnst.';

  @override
  String get commAnswered => 'Beantwortet';

  @override
  String get commOk => 'In Ordnung';

  @override
  String get commNoAnswer => 'Keine Antwort';

  @override
  String get commIssue => 'Problem';

  @override
  String get commOpen => 'Offen';

  @override
  String get commDone => 'Erledigt';

  @override
  String get commFilterAll => 'Alle';

  @override
  String get commChecked => 'Geprüft';

  @override
  String get commStarted => 'Begonnen';

  @override
  String get commPdfTitle => 'Inbetriebnahme-Protokoll';

  @override
  String get commSignedBy => 'Geprüft von';

  @override
  String get commDate => 'Datum';

  @override
  String get commSignature => 'Unterschrift';

  @override
  String commStart(int count) {
    return 'Anlegen und lesen ($count)';
  }

  @override
  String commReadOpen(int count) {
    return 'Offene lesen ($count)';
  }

  @override
  String get commReadAll => 'Alle erneut lesen';

  @override
  String get commReadOne => 'Erneut lesen';

  @override
  String get commReset => 'Zurücksetzen';

  @override
  String get commNote => 'Notiz';

  @override
  String get commRestart => 'Neu beginnen';

  @override
  String get commRestartConfirm =>
      'Alle Ergebnisse und Notizen verwerfen und eine neue Checkliste anlegen?';

  @override
  String get commNoProject =>
      'Für die Checkliste braucht es ein ETS-Projekt mit Gruppenadressen.';

  @override
  String get healthTitle => 'Gesundheit';

  @override
  String get healthTool =>
      'Bekannte Adressen lesen, Zyklen, Werte und Datentypen prüfen';

  @override
  String get healthExplain =>
      'Liest Status-Adressen und alles, was schon einmal geantwortet hat. Dazu: Wer sendet sonst regelmäßig und ist jetzt still? Sind Messwerte plausibel? Passen Länge und Wert zum DPT? Wie ist die Busqualität? Neue Befunde seit dem letzten Lauf stehen oben.';

  @override
  String healthRunNow(int count) {
    return 'Jetzt prüfen ($count Adressen)';
  }

  @override
  String get healthPassive => 'Nur auswerten';

  @override
  String get healthAuto =>
      'Automatisch nach dem Verbinden (höchstens 1× pro Tag)';

  @override
  String healthLastRun(String time) {
    return 'Letzter Lauf $time';
  }

  @override
  String get healthNever => 'Noch kein Lauf';

  @override
  String healthRunning(int sent, int total) {
    return 'Läuft … $sent von $total gelesen';
  }

  @override
  String get healthAreaRead => 'Lesetest';

  @override
  String get healthAreaCycle => 'Zyklen';

  @override
  String get healthAreaValues => 'Werte';

  @override
  String get healthAreaDpt => 'Datentypen';

  @override
  String get healthAreaBus => 'Bus';

  @override
  String get healthAllGood => 'Keine Befunde';

  @override
  String get healthNewSection => 'Neu seit letztem Lauf';

  @override
  String healthAnswered(int answered, int asked) {
    return '$answered von $asked antworten';
  }

  @override
  String get healthHistory => 'Verlauf';

  @override
  String get healthToCommissioning => 'In Inbetriebnahme übernehmen';

  @override
  String healthAddedToCommissioning(int count) {
    return '$count Adressen in die Inbetriebnahme übernommen';
  }

  @override
  String get healthPdfTitle => 'Gesundheitsprüfung';

  @override
  String healthNotifyTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count neue Befunde',
      one: '1 neuer Befund',
    );
    return 'KNX: $_temp0';
  }

  @override
  String get healthNew => 'neu';

  @override
  String get healthBits => '≤ 6 Bit';

  @override
  String healthBytes(int count) {
    return '$count Byte';
  }

  @override
  String healthNewSilent(String time) {
    return 'Antwortet nicht mehr – zuletzt $time';
  }

  @override
  String get healthAlwaysSilent =>
      'Hat noch nie auf Lesen geantwortet – Lese-Flag prüfen';

  @override
  String healthOverdue(String interval, String time) {
    return 'Sendet sonst alle $interval, zuletzt $time';
  }

  @override
  String healthOutOfRange(String value, String sender) {
    return 'Unplausibler Wert $value von $sender';
  }

  @override
  String healthStuck(String value, String time) {
    return 'Seit $time unverändert $value';
  }

  @override
  String healthDptSize(
    String sender,
    String actual,
    String dpt,
    String expected,
    int count,
  ) {
    return '$sender sendet $actual, DPT $dpt erwartet $expected ($count×)';
  }

  @override
  String healthDptValue(String sender, String raw, int count) {
    return '$sender sendet ungültigen Wert $raw ($count×)';
  }

  @override
  String healthMixedSizes(int count) {
    return 'Ohne DPT im Projekt – Sender schicken $count verschiedene Längen';
  }

  @override
  String healthRepeats(String rate, int count) {
    return 'Wiederholt $rate % von $count Telegrammen – Quittungen prüfen';
  }

  @override
  String healthUnansweredReads(int count) {
    return '$count Leseanfragen anderer Geräte ohne Antwort';
  }

  @override
  String get healthUnlinked =>
      'Kein Gerät im Projekt verknüpft – kann nicht antworten (Platzhalter oder Altlast?)';

  @override
  String healthAlwaysSilentAt(String sender) {
    return 'Hat noch nie geantwortet – Lese-Flag am sendenden Objekt prüfen: $sender';
  }

  @override
  String get connectDemo => 'Demo ohne Anlage ansehen';

  @override
  String get demoGateway => 'Demo-Haus';

  @override
  String get demoNoBusmonitor =>
      'Der Busmonitor braucht ein echtes Gateway – im Demo-Modus nicht verfügbar.';

  @override
  String get menuGroupCheck => 'Prüfen';

  @override
  String get menuGroupBus => 'Bus & Netz';

  @override
  String get menuGroupAnalyze => 'Auswerten';

  @override
  String get menuGroupRecord => 'Aufzeichnen';

  @override
  String get menuGroupData => 'Daten';

  @override
  String get menuGroupSettings => 'Einstellungen';

  @override
  String get connectWithout => 'Ohne Verbindung';

  @override
  String get connectDemoShort => 'Demo ansehen';

  @override
  String get connectProject => 'ETS-Projekt';

  @override
  String get errorTunnelAddressInUse =>
      'Die gewünschte Tunneladresse ist belegt.';

  @override
  String get errorTunnelAddressRejected =>
      'Gateway lehnt die gewünschte Tunneladresse ab.';

  @override
  String get errorLayerUnsupported =>
      'Gateway unterstützt diese Tunnelart nicht (Link Layer/Busmonitor).';

  @override
  String get connectModeUdp => 'UDP';

  @override
  String get connectModeTcp => 'TCP';

  @override
  String get connectModeRouting => 'Routing';

  @override
  String get connectModeSecure => 'Secure';

  @override
  String get connectModeUdpHint =>
      'Tunnel über UDP – geht mit jedem IP-Interface.';

  @override
  String get connectModeTcpHint =>
      'Tunnel über TCP (KNXnet/IP 2.0) – übersteht WLAN-Aussetzer besser.';

  @override
  String get connectModeRoutingHint =>
      'Multicast 224.0.23.12 über einen IP-Router – belegt keinen Tunnelplatz. Filtertabellen des Routers beachten.';

  @override
  String get connectModeSecureHint =>
      'Verschlüsselter Tunnel (KNX IP Secure). Benutzer und Passwort stehen in der ETS beim Tunnel der Schnittstelle.';

  @override
  String get connectTunnelAddress => 'Tunneladresse (optional)';

  @override
  String get connectTunnelAddressHelp =>
      'Feste Adresse statt beliebigem freien Platz; ist sie belegt, wird ein freier genommen.';

  @override
  String get connectRoutingAddress => 'Eigene Adresse';

  @override
  String get connectAddressInvalid => 'Physikalische Adresse wie 1.1.240';

  @override
  String get connectSecureUser => 'Benutzer';

  @override
  String get connectSecurePassword => 'Passwort';

  @override
  String get connectSecureDeviceAuth =>
      'Geräte-Authentifizierungscode (optional)';

  @override
  String get connectSecureDeviceAuthHelp =>
      'Prüft, dass wirklich die eigene Schnittstelle antwortet.';

  @override
  String routingUnavailable(String reason) {
    return 'Routing nicht möglich: $reason';
  }

  @override
  String get addonTitle => 'Daueraufzeichnung im Add-on';

  @override
  String get addonPaused =>
      'Angehalten – der Tunnel ist frei, z. B. für die ETS.';

  @override
  String addonConnectedSince(String target, String time, int count) {
    return 'Verbunden mit $target seit $time · $count Telegramme heute';
  }

  @override
  String get addonConnecting => 'Add-on verbindet mit dem Bus …';

  @override
  String get addonConnectionLost => 'Verbindung zum Add-on getrennt.';

  @override
  String get boxAttaching => 'Verbinde mit der Box …';

  @override
  String get boxConnecting => 'Box verbindet mit dem Bus …';

  @override
  String get boxConnectionLost => 'Verbindung zur Box getrennt.';

  @override
  String get addonDeviceBusy =>
      'Gerät wird gerade in einer anderen Ansicht geprüft.';

  @override
  String get addonPause => 'Anhalten';

  @override
  String get addonResume => 'Fortsetzen';

  @override
  String get addonOpen => 'Monitor öffnen';

  @override
  String get boxSection => 'KNX-Box';

  @override
  String get boxPair => 'Mit KNX-Box koppeln';

  @override
  String get boxPairHint =>
      'QR-Code der Box mit der Kamera scannen, oder Kopplungslink bzw. IP-Adresse der Box hier einfügen. Den Link findest du auch als knx-box-link.txt auf der SD-Karte.';

  @override
  String get boxPairField => 'Kopplungslink oder IP-Adresse der Box';

  @override
  String get boxLinkInvalid => 'Kein gültiger Kopplungslink.';

  @override
  String get boxPairTitle => 'Mit KNX-Box verbinden?';

  @override
  String get boxPairBody =>
      'Die App zeigt den Bus dann über diese Box. Nur bestätigen, wenn du den QR-Code selbst gescannt hast und die Adresse zu deiner Box passt.';

  @override
  String boxVia(String name) {
    return 'Über KNX-Box $name';
  }

  @override
  String get boxGatewayHint =>
      'Das Gateway unten wird auf der Box eingestellt; die Box bleibt damit verbunden.';

  @override
  String get boxLeave => 'Gateway direkt';

  @override
  String get boxForget => 'Kopplung löschen';

  @override
  String get boxNone => 'Keine KNX-Box gekoppelt.';

  @override
  String get boxUnauthorized =>
      'Die Box hat den Zugang abgelehnt. QR-Code der Box neu scannen.';

  @override
  String boxUnreachable(String address) {
    return 'KNX-Box $address nicht erreichbar. Ist das Gerät im WLAN der Box?';
  }

  @override
  String get historyMaxSize => 'Höchstens';

  @override
  String get historyWriteInterval => 'Schreiben';

  @override
  String get historyWriteNow => 'sofort';

  @override
  String get historyWriteHint =>
      'Seltener schreiben schont die SD-Karte; bei Stromausfall fehlt dann der letzte Block.';

  @override
  String historyDeleteDayConfirm(String date) {
    return 'Verlauf vom $date löschen?';
  }

  @override
  String outageOffline(String duration) {
    return 'Add-on lief $duration nicht';
  }

  @override
  String outageDisconnected(String duration) {
    return 'Bus $duration getrennt';
  }

  @override
  String get secureAuthFailed => 'IP Secure: Benutzer oder Passwort abgelehnt.';

  @override
  String get secureDeviceAuthFailed =>
      'IP Secure: Geräte-Authentifizierungscode passt nicht – antwortet wirklich die eigene Schnittstelle?';

  @override
  String get secureSessionClosed =>
      'Gateway hat die gesicherte Sitzung beendet.';

  @override
  String get secureNoCredentials =>
      'Für IP Secure Passwort eingeben oder Keyring importieren.';

  @override
  String get keyringTitle => 'KNX Secure (Keyring)';

  @override
  String get keyringImport => 'Keyring importieren';

  @override
  String get keyringPassword => 'Keyring-Passwort';

  @override
  String get keyringPasswordHint =>
      'Das Passwort, das beim Export aus der ETS vergeben wurde.';

  @override
  String get keyringWrongPassword => 'Falsches Passwort.';

  @override
  String get keyringInvalid => 'Keine gültige Keyring-Datei (.knxkeys).';

  @override
  String keyringLoaded(String project, int keys, int tunnels) {
    return '$project: $keys gesicherte Gruppenadressen, $tunnels Secure-Tunnel';
  }

  @override
  String get keyringNone =>
      'Kein Keyring – Data-Secure-Telegramme bleiben verschlüsselt.';

  @override
  String get keyringNoneShort => 'Nicht geladen';

  @override
  String get keyringRemove => 'Keyring entfernen';

  @override
  String get keyringExplain =>
      'Die Schlüssel bleiben auf diesem Gerät bzw. im Add-on. In der ETS: Projekt → Exportieren → Keyring.';

  @override
  String secureWithoutKeys(int count) {
    return '$count Data-Secure-Telegramme ohne Schlüssel – Keyring importieren, um sie zu lesen.';
  }

  @override
  String secureRejected(int count) {
    return '$count Data-Secure-Telegramme verworfen (MAC oder Sequenznummer ungültig).';
  }

  @override
  String get connectModeHa => 'Home Assistant';

  @override
  String get connectModeHaHint =>
      'Kein eigener Tunnel: das Add-on liest, was die KNX-Integration von Home Assistant empfängt, und sendet über sie. Gerätezugriffe (Programmiermodus, Adresse prüfen, Busmonitor) gehen so nicht.';

  @override
  String get connectModeHaAddonOnly => 'Nur im Home-Assistant-Add-on möglich.';

  @override
  String get connectModeHat => 'KNX-HAT (kBerry)';

  @override
  String get connectModeHatHint =>
      'Ohne Gateway: Die Box hängt über den aufgesteckten KNX-HAT (Weinzierl kBerry) direkt an der Busleitung.';

  @override
  String get connectModeHatBoxOnly =>
      'Nur über die KNX-Box mit aufgestecktem KNX-HAT möglich.';

  @override
  String get connectHatAddress => 'Eigene Adresse (optional)';

  @override
  String get connectHatAddressHelp =>
      'Leer lassen, um die Adresse des Moduls zu behalten (ab Werk 15.15.255). Eine eingetragene Adresse schreibt die Box ins Modul.';

  @override
  String get connectHatBusmonitor => 'Busmonitor';

  @override
  String get connectHatBusmonitorHelp =>
      'Alle Frames mit Quittungen (ACK/NAK/BUSY) für den Busmonitor. Die Box hört dann nur: kein Lesen oder Schreiben aus der App.';

  @override
  String get filterOn => 'Filter einschalten';

  @override
  String get filterOff => 'Filter vorübergehend aus';

  @override
  String get filterContext => 'Kontext';

  @override
  String filterContextActive(int seconds) {
    return 'Kontext ±$seconds s';
  }

  @override
  String filterContextSeconds(int seconds) {
    return '±$seconds s um jeden Treffer';
  }

  @override
  String get filterContextOff => 'Nur Treffer';

  @override
  String get filterContextTooltip =>
      'Telegramme kurz vor und nach jedem Treffer mit anzeigen';

  @override
  String get writeFormatTime => 'Uhrzeit';

  @override
  String get writeFormatDate => 'Datum';

  @override
  String get writeFormatHvac => 'HVAC-Modus';

  @override
  String get writeFormatColor => 'Farbe (RGB)';

  @override
  String get writeNow => 'Jetzt';

  @override
  String get sendDelay => 'Verzögerung';

  @override
  String get sendRepeat => 'Wiederholen';

  @override
  String get sendNow => 'sofort';

  @override
  String get sendOnce => 'einmal';

  @override
  String sendEverySeconds(int seconds) {
    return 'alle $seconds s';
  }

  @override
  String sendEveryMinutes(int minutes) {
    return 'alle $minutes min';
  }

  @override
  String get sendScheduled => 'Geplante Sendungen';

  @override
  String get sendStopAll => 'Alle stoppen';

  @override
  String get sendStop => 'Stoppen';

  @override
  String sendCount(int count) {
    return '$count× gesendet';
  }

  @override
  String sendNext(String time) {
    return 'nächste $time';
  }

  @override
  String get dptChoose => 'Datentyp festlegen';

  @override
  String get dptOverridden => 'Datentyp selbst festgelegt – ändern';

  @override
  String dptChooseTitle(String address) {
    return 'Datentyp für $address';
  }

  @override
  String dptFromProject(String dpt) {
    return 'Wie im Projekt ($dpt)';
  }

  @override
  String get dptNone => 'Kein Datentyp (raten)';

  @override
  String get deviceGeneral => 'Allgemein';

  @override
  String get deviceOn => 'Ein';

  @override
  String get deviceOff => 'Aus';

  @override
  String deviceChannelSemantics(String channel, String state) {
    return 'Kanal $channel: $state';
  }

  @override
  String get heatmapTitle => 'Aktivität nach Wochentag und Stunde';

  @override
  String get heatmapEmpty => 'Noch keine Telegramme';

  @override
  String heatmapPeak(String day, int hour, int count) {
    return 'Meiste Telegramme: $day $hour Uhr ($count)';
  }

  @override
  String get statsLongTerm => 'Langzeit (Daueraufzeichnung)';

  @override
  String statsLongTermTotal(String count) {
    return '$count Telegramme im Zeitraum';
  }

  @override
  String get statsLongTermUnavailable =>
      'Auswertung nicht verfügbar (Add-on aktualisieren?).';

  @override
  String get chartsTitle => 'Diagramme';

  @override
  String get toolCharts => 'Mehrere Werte über der Zeit vergleichen';

  @override
  String get chartsAdd => 'Adressen wählen';

  @override
  String get chartsMore => 'Mehr';

  @override
  String get chartsEmpty =>
      'Gruppenadressen mit Zahlenwerten auswählen – bis zu 8, eine Achse je Einheit.';

  @override
  String get chartsSaveSelection => 'Als Diagramm speichern';

  @override
  String get chartsSelectionName => 'Name';

  @override
  String get chartsExportPng => 'Als Bild (PNG)';

  @override
  String get chartsExportCsv => 'Als Tabelle (CSV)';

  @override
  String get chartsClear => 'Alle entfernen';

  @override
  String get chartsResize => 'Diagrammhöhe ziehen';

  @override
  String get diagnosticsBundle => 'Diagnose-Paket für Fehlerbericht';

  @override
  String get aboutLicenses => 'Über KNX Monitor und Lizenzen';

  @override
  String get aboutLegalese => '© 2026 regetskcob. Alle Rechte vorbehalten.';

  @override
  String get aboutSender => 'ein Projekt von regetskcob';

  @override
  String get hzCSeverityOk => 'In Ordnung';

  @override
  String get hzCSeverityInfo => 'Hinweis';

  @override
  String get hzCSeverityWarning => 'Warnung';

  @override
  String get hzCSeverityError => 'Fehler';

  @override
  String get hzCRecordingLive => 'Aufnahme';

  @override
  String get sidebarShow => 'Seitenleiste einblenden';

  @override
  String get sidebarHide => 'Seitenleiste ausblenden';

  @override
  String get hzFLegend => 'Legende';

  @override
  String get hzFReceived => 'Wert empfangen';

  @override
  String get hzFNoTelegram => 'Noch kein Telegramm';

  @override
  String get hzFDetected => 'Erkannt am gemeinsamen Namensanfang';

  @override
  String hzHCouplerOpen(String address) {
    return 'Koppler $address, Verkehr anzeigen';
  }

  @override
  String hzHLinePair(String a, String b) {
    return 'Linie $a ↔ $b';
  }

  @override
  String hzHFlow(String from, String to) {
    return 'Linie $from → $to';
  }

  @override
  String get hzHFlowHint =>
      'Von einer Linie heißt: die Quelladresse liegt dort. Nach einer Linie heißt: laut Projekt hören dort Geräte zu. Ob der Koppler wirklich weiterleitet, sieht das Gateway nur bei Telegrammen, die bei ihm ankommen.';

  @override
  String get hzHSeenAtGateway => 'Am Gateway gesehen';

  @override
  String get hzHWithoutReceiver => 'davon ohne Empfänger';

  @override
  String get hzHFlowEmpty =>
      'Laut Projekt läuft keine Gruppenadresse über diesen Koppler.';

  @override
  String get hzHAllDirections => 'Alle Richtungen';

  @override
  String get hzHFilterHint => 'im Monitor filtern';

  @override
  String get hzHCouplerUnknown => 'Koppler nicht im Projekt';

  @override
  String hzHCouplerKennung(String address, String lines) {
    return 'Koppler $address · $lines';
  }

  @override
  String get columnHop => 'Hop';

  @override
  String get menuTitle => 'Menü';

  @override
  String get quickFilterButton => 'Filter';

  @override
  String hzHFlowTelegrams(String from, String to) {
    return 'Telegramme $from → $to';
  }

  @override
  String get heatmapActivity => 'Aktivität';

  @override
  String get heatmapPerMinute => 'je Minute';

  @override
  String get heatmapPerFiveMinutes => 'je 5 Minuten';

  @override
  String get heatmapPerHour => 'je Stunde';

  @override
  String get heatmapWeekly => 'nach Wochentag und Stunde';

  @override
  String heatmapPeakAt(String time, int count) {
    return 'Meiste Telegramme: $time ($count)';
  }

  @override
  String recordingStartHint(int seconds) {
    return 'Aufnahme starten – lang drücken: mit $seconds s Vorlauf';
  }

  @override
  String recordingPreRoll(int seconds) {
    return 'Mit $seconds s Vorlauf aufnehmen';
  }

  @override
  String recordingPreRollStarted(int seconds) {
    return 'Aufnahme läuft – enthält die letzten $seconds s';
  }

  @override
  String get replayMenu => 'Auf den Bus senden …';

  @override
  String get replayTitle => 'Auf den Bus senden';

  @override
  String get replayWarning =>
      'Die Schreibtelegramme werden wirklich gesendet: Aktoren schalten, Jalousien fahren. Nur mit Blick auf die Anlage.';

  @override
  String replayOtherGateway(String recorded, String current) {
    return 'Aufgenommen an $recorded, gesendet wird an $current.';
  }

  @override
  String get replayNoWrites => 'Die Aufnahme enthält keine Schreibtelegramme.';

  @override
  String replayShorten(int seconds) {
    return 'Pausen auf $seconds s kürzen';
  }

  @override
  String get replayShortenHint => 'Aus: im Originaltakt der Aufnahme';

  @override
  String replaySend(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Telegramme senden',
      one: '1 Telegramm senden',
    );
    return '$_temp0';
  }

  @override
  String get replayConfirmTitle => 'Wirklich auf den Bus senden?';

  @override
  String replayConfirmText(int count, int addresses, String gateway) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Schreibtelegramme',
      one: '1 Schreibtelegramm',
    );
    String _temp1 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses Gruppenadressen',
      one: '1 Gruppenadresse',
    );
    return '$_temp0 an $_temp1 über $gateway. Das lässt sich nicht rückgängig machen.';
  }

  @override
  String get replayRunning => 'Sendet …';

  @override
  String get replayDone => 'Fertig gesendet';

  @override
  String get replayStopped => 'Angehalten';

  @override
  String replayFailed(String message) {
    return 'Abgebrochen: $message';
  }

  @override
  String get replaySent => 'Gesendet';

  @override
  String get replayUnconfirmed => 'Nicht quittiert';

  @override
  String get replayTotal => 'Gesamt';

  @override
  String get replayStop => 'Stopp';

  @override
  String get replayTelegrams => 'Telegramme';

  @override
  String get replayEditHint =>
      'Tippen ändert den Wert, × entfernt das Telegramm. Das Original bleibt unverändert.';

  @override
  String get replayReset => 'Zurücksetzen';

  @override
  String get replaySaveCopy => 'Als Kopie speichern';

  @override
  String replayCopyName(String name) {
    return '$name · bearbeitet';
  }

  @override
  String get replayEdited => 'Geändert';

  @override
  String get replayRemove => 'Entfernen';

  @override
  String get replayInvalidValue => 'Ungültiger Wert';

  @override
  String get replayHexHint => 'Bytes hex, z. B. 0C 1A';

  @override
  String get chartNoValues => 'Noch keine Zahlenwerte für ein Diagramm.';

  @override
  String get chartName => 'Name des Diagramms';

  @override
  String get chartRename => 'Umbenennen';

  @override
  String get chartDelete => 'Diagramm löschen';

  @override
  String get chartDeleteTitle => 'Diagramm löschen?';

  @override
  String chartDeleteText(String name) {
    return '„$name“ wird entfernt. Die Daten bleiben erhalten.';
  }

  @override
  String pickerApply(int count) {
    return 'Übernehmen · $count';
  }

  @override
  String get pickerEmpty => 'Nichts passt zum Filter.';

  @override
  String get replayPickTitle => 'Adressen zum Senden';

  @override
  String replayAddressesAll(int count) {
    return 'Alle $count Adressen · auswählen';
  }

  @override
  String replayAddressesSome(int count, int total) {
    return '$count von $total Adressen · ändern';
  }

  @override
  String get chartNew => 'Neues Diagramm';

  @override
  String get chartDefaultName => 'Diagramm';

  @override
  String get commFilterNoAnswer => 'Stumm';

  @override
  String get chartsSaved => 'Gespeichert';

  @override
  String get chartsOverviewEmpty => 'Noch keine Diagramme';

  @override
  String get chartsOverviewEmptyDetail =>
      'Mit „Neues Diagramm“ Adressen aus allen Sektionen wählen und unter einem Namen speichern. Es erscheint dann auch in der Übersicht.';

  @override
  String get chartTemplates => 'Vorlagen';

  @override
  String get chartTemplatesIntro =>
      'Aus deinem Projekt erkannt. „Übernehmen“ macht daraus ein eigenes Diagramm, das du ändern kannst.';

  @override
  String get chartTemplatesTrafficIntro =>
      'Aus dem laufenden Verkehr. Mit einem ETS-Projekt kommen Vorlagen je Raum dazu.';

  @override
  String get chartTemplateAdopt => 'Übernehmen';

  @override
  String get chartTemplateAdopted => 'Übernommen';

  @override
  String get chartTemplatesAdoptAll => 'Alle übernehmen';

  @override
  String chartTemplateAdoptedSnack(String name) {
    return '„$name“ übernommen';
  }

  @override
  String chartTemplatesAdoptedSnack(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Diagramme übernommen',
      one: '1 Diagramm übernommen',
    );
    return '$_temp0';
  }

  @override
  String get chartRecipeClimate => 'Raumklima';

  @override
  String get chartRecipeAir => 'Luft';

  @override
  String get chartRecipeLight => 'Licht & Präsenz';

  @override
  String get chartRecipeShading => 'Beschattung';

  @override
  String get chartRecipeWeather => 'Wetter';

  @override
  String get chartRecipeEnergy => 'Energie';

  @override
  String get chartRecipeTraffic => 'Aus dem Verkehr';

  @override
  String get busMetricTelegrams => 'Telegramme/min';

  @override
  String get busMetricRepeats => 'Wiederholungen/min';

  @override
  String busMetricLine(String line) {
    return 'Linie $line';
  }

  @override
  String get chartRecipeBus => 'Bus';

  @override
  String get chartBusOverall => 'Gesamt';

  @override
  String get chartBusLines => 'Linien';

  @override
  String get chartShareTemplate => 'Als Vorlage teilen';

  @override
  String get chartShareTemplateEmpty =>
      'Keine Reihe mit erkennbarer Rolle – die Vorlage wäre leer.';

  @override
  String chartShareTemplateDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Reihen ohne erkennbare Rolle sind nicht in der Vorlage.',
      one: '1 Reihe ohne erkennbare Rolle ist nicht in der Vorlage.',
    );
    return '$_temp0';
  }

  @override
  String get chartTemplateImport => 'Vorlage importieren';

  @override
  String chartTemplateImported(String name) {
    return 'Vorlage „$name“ importiert';
  }

  @override
  String chartTemplateImportedNoMatch(String name) {
    return 'Vorlage „$name“ importiert – passt in dieser Anlage noch zu keiner Adresse.';
  }

  @override
  String get chartTemplateImportFailed => 'Keine gültige Diagramm-Vorlage.';

  @override
  String get chartTemplateRemove => 'Vorlage entfernen';

  @override
  String get chartTemplateNoMatch =>
      'Passt in dieser Anlage noch zu keiner Adresse.';

  @override
  String get boxAdd => 'KNX-Box hinzufügen';

  @override
  String get boxScanTitle => 'QR-Code der Box';

  @override
  String get boxScanHint =>
      'Den QR-Code vom Aufkleber der Box in den Rahmen halten.';

  @override
  String get boxScanManual => 'Link einfügen oder Adresse eingeben';

  @override
  String get boxScanNoCamera => 'Keine Kamera verfügbar.';

  @override
  String get boxSetupTitle => 'KNX-Box einrichten';

  @override
  String boxStepWifi(String ssid) {
    return 'WLAN $ssid beitreten';
  }

  @override
  String boxStepWifiManual(String ssid) {
    return 'In den Einstellungen dem WLAN $ssid beitreten und zurückkommen.';
  }

  @override
  String get boxStepWifiDenied => 'Beitritt zum WLAN abgelehnt.';

  @override
  String get boxStepReach => 'Box erreichen';

  @override
  String get boxStepReachFailed =>
      'Die Box antwortet nicht. Ist sie eingeschaltet und das Gerät in ihrem WLAN?';

  @override
  String get boxStepPair => 'Mit der Box koppeln';

  @override
  String get boxStepTime => 'Uhr der Box stellen';

  @override
  String get boxStepTimeDiffers =>
      'Uhr der Box weicht ab; in den Box-Einstellungen prüfen.';

  @override
  String get boxStepGateway => 'Gateway am Kabel der Box finden';

  @override
  String boxStepGatewayFound(String host) {
    return 'Gateway $host eingestellt';
  }

  @override
  String get boxStepGatewayChoose => 'Gateway im Verbinden-Bildschirm wählen';

  @override
  String get boxSetupRetry => 'Erneut versuchen';

  @override
  String get boxSetupDone => 'Fertig';

  @override
  String get boxSettings => 'Box-Einstellungen';

  @override
  String get boxClock => 'Uhr';

  @override
  String get boxClockNone => 'Keine gesicherte Zeit';

  @override
  String get boxClockRtc => 'Akku-Uhr der Box (RTC)';

  @override
  String get boxClockKnx => 'KNX-Zeitgeber auf der Linie';

  @override
  String get boxClockClient => 'Von einem iPhone oder iPad gestellt';

  @override
  String get boxClockNtp => 'Internet (NTP)';

  @override
  String boxClockOffset(String source, String offset) {
    return '$source weicht um $offset ab.';
  }

  @override
  String get boxClockSetNow => 'Mit diesem Gerät stellen';

  @override
  String get boxClockFromKnx => 'Uhr nach KNX-Zeitgeber stellen';

  @override
  String get boxClockFromKnxHint =>
      'Datum und Uhrzeit von der Linie (DPT 19.001 oder 10.001 + 11.001), wenn keine sicherere Quelle da ist.';

  @override
  String get boxRecordOnlyWithTime => 'Erst aufzeichnen, wenn die Zeit stimmt';

  @override
  String get boxRecordOnlyWithTimeHint =>
      'Sonst zeichnet die Box sofort auf und ordnet die Zeit nachträglich zu.';

  @override
  String boxWaiting(int count) {
    return '$count Telegramme ohne Zeit nicht aufgezeichnet';
  }

  @override
  String get boxTimeAskTitle => 'Uhr der Box weicht ab';

  @override
  String boxTimeAskBody(String offset) {
    return 'Die Uhr der Box weicht um $offset von diesem Gerät ab. Nach diesem Gerät stellen?';
  }

  @override
  String get boxDevices => 'Gekoppelte Geräte';

  @override
  String get boxDeviceSelf => 'dieses Gerät';

  @override
  String get boxDeviceViewOnly => 'nur ansehen';

  @override
  String get boxViewOnlyHint =>
      'Dieses Gerät ist nur zum Ansehen mit der Box gekoppelt und schickt nichts auf den Bus. Zum Schalten neu koppeln, ohne „Nur ansehen“.';

  @override
  String get boxDeviceAdmin => 'verwaltet die Box';

  @override
  String get boxDeviceRevoke => 'Sperren';

  @override
  String get boxPasswordChange => 'Box-Passwort ändern';

  @override
  String get boxPasswordCurrent => 'Aktuelles Passwort';

  @override
  String get boxPasswordCurrentWrong => 'Das aktuelle Passwort stimmt nicht.';

  @override
  String get boxPasswordHint =>
      'Mindestens 8 Zeichen. Der QR-Code des Aufklebers koppelt danach keine neuen Geräte mehr.';

  @override
  String get boxPasswordChanged => 'Passwort geändert.';

  @override
  String get boxNotAdmin =>
      'Verwalten geht nur mit dem Box-Passwort: QR-Code des Aufklebers scannen.';

  @override
  String get installationsTitle => 'Installationen';

  @override
  String get installationNew => 'Neue Installation';

  @override
  String get installationName => 'Name der Installation';

  @override
  String get installationNameHint => 'z. B. Kunde Müller, Büro, Zuhause';

  @override
  String get installationRename => 'Umbenennen';

  @override
  String installationDeleteTitle(String name) {
    return '„$name“ löschen?';
  }

  @override
  String get installationDeleteBody =>
      'ETS-Projekt, Keyring, Gesundheit, Inbetriebnahme, Abnahmeprotokolle, Serviceberichte, Kundendaten, Langzeitverlauf und Einstellungen dieser Installation werden entfernt. Aufnahmen bleiben erhalten.';

  @override
  String get installationNoGateway => 'Noch kein Gateway';

  @override
  String get installationActive => 'Aktiv';

  @override
  String installationSwitched(String name) {
    return 'Installation „$name“';
  }

  @override
  String installationGatewayElsewhere(String name) {
    return 'Dieses Gateway gehört zu „$name“.';
  }

  @override
  String get installationSwitch => 'Wechseln';

  @override
  String get installationUnassigned => 'Ohne Zuordnung';

  @override
  String get installationAll => 'Alle';

  @override
  String get installationBoxRecording => 'KNX-Box zeichnet hier auf';

  @override
  String get installationHistoryOf => 'Verlauf von';

  @override
  String get installationDeleteOnBox =>
      'Auch auf der KNX-Box, mit ihrem Langzeitverlauf.';

  @override
  String get boxRecordingTitle => 'Daueraufzeichnung auf der KNX-Box';

  @override
  String get planTitle => 'Plus und Pro';

  @override
  String planFeatureLocked(String feature, String tier) {
    return '„$feature“ gehört zu $tier.';
  }

  @override
  String planCurrent(String tier) {
    return 'Aktuell: $tier';
  }

  @override
  String get planActive => 'Aktiv';

  @override
  String get planPlusPitch =>
      'Für die eigene Anlage: Wächter mit Ton, Verlauf, Diagramme, Statistik, Alarme und Export.';

  @override
  String get planProPitch =>
      'Für Inbetriebnahme und Fehlersuche: alle Werkzeuge für Fachleute, ohne Grenzen.';

  @override
  String get planUnlimitedRecordings => 'Beliebig viele Aufnahmen';

  @override
  String planInstallations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bis zu $count Installationen',
      one: '1 Installation',
    );
    return '$_temp0';
  }

  @override
  String get planUnlimitedInstallations => 'Beliebig viele Installationen';

  @override
  String planPerYear(String price) {
    return '$price pro Jahr';
  }

  @override
  String planPerMonth(String price) {
    return '$price pro Monat';
  }

  @override
  String planOnce(String price) {
    return '$price einmalig';
  }

  @override
  String get planRestore => 'Käufe wiederherstellen';

  @override
  String planRestored(String tier) {
    return 'Käufe wiederhergestellt: $tier.';
  }

  @override
  String get planNothingRestored => 'Keine früheren Käufe gefunden.';

  @override
  String get planNoOffers =>
      'Die Angebote sind gerade nicht erreichbar. Bitte die Internetverbindung prüfen.';

  @override
  String planBuyFailed(String error) {
    return 'Der Kauf hat nicht geklappt: $error';
  }

  @override
  String planThanks(String tier) {
    return 'Danke! $tier ist freigeschaltet.';
  }

  @override
  String get planLegal =>
      'Abos verlängern sich automatisch und lassen sich jederzeit in den Einstellungen des Stores kündigen.';

  @override
  String get planTerms => 'Nutzungsbedingungen';

  @override
  String get planPrivacy => 'Datenschutz';

  @override
  String planMoreInstallations(String tier, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Installationen',
      one: 'eine Installation',
    );
    return 'Mit $tier gibt es hier nur $_temp0.';
  }

  @override
  String get planMoreRecordings =>
      'Free speichert eine Aufnahme. Mit Plus sind es beliebig viele.';

  @override
  String get planLongHistory =>
      'Den Langzeitverlauf gibt es ab Plus. Free zeigt im Monitor die letzte Stunde.';

  @override
  String get planAllOfPlus => 'Dazu alles aus Plus';

  @override
  String get planBetaTitle => 'Beta: Pro freigeschaltet';

  @override
  String planBetaBody(int months) {
    return 'Danke fürs Testen! In der Beta ist alles freigeschaltet. Erscheint KNX Monitor im App Store, gibt es auf diesem Gerät $months Monate Pro als Dankeschön.';
  }

  @override
  String get planBetaStoreOn => 'Bezahlseite wie im Store (Sandbox)';

  @override
  String get planBetaStoreOff => 'Beta-Freischaltung wieder aktiv';

  @override
  String planLapsed(String tier) {
    return '$tier gilt ohne Internet 30 Tage. Diese Frist ist abgelaufen – verbinde das Gerät einmal mit dem Internet, dann ist $tier sofort wieder da.';
  }

  @override
  String planBetaReward(String date) {
    return 'Beta-Dankeschön: Pro bis $date';
  }

  @override
  String get planManage => 'Abo verwalten oder kündigen';

  @override
  String planTrial(int days, String price) {
    return '$days Tage gratis, dann $price';
  }

  @override
  String get planFeatureReplay => 'Aufnahmen auf den Bus spielen';

  @override
  String get planFeatureScheduled => 'Verzögert und zyklisch senden';

  @override
  String healthShowNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Hinweise einblenden',
      one: '1 Hinweis einblenden',
    );
    return '$_temp0';
  }

  @override
  String get healthHideNotes => 'Hinweise ausblenden';

  @override
  String get objectReadFeedbacks => 'Rückmeldungen lesen';

  @override
  String objectReadSent(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Leseanfragen gesendet',
      one: '1 Leseanfrage gesendet',
    );
    return '$_temp0';
  }

  @override
  String get busmonListening => 'Lauscht auf der Leitung …';

  @override
  String get busmonQuietHint =>
      'Seit 15 Sekunden kein Frame. Ist die Linie gerade still, löst ein Taster oder „Lesen“ Verkehr aus. Manche IP-Schnittstellen liefern im Busmonitor-Modus nichts; dann hilft der Live-Monitor.';

  @override
  String menuMoreTools(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weitere Werkzeuge im Expertenmodus',
      one: '1 weiteres Werkzeug im Expertenmodus',
    );
    return '$_temp0';
  }

  @override
  String get menuMoreToolsHint =>
      'Busmonitor, Diagnose, Inbetriebnahme, Topologie und mehr';

  @override
  String get toolObjects =>
      'Räume und Objekte aus dem ETS-Projekt, Befehle neben Rückmeldungen';

  @override
  String topoRail(String line) {
    return 'Verteiler · Linie $line';
  }

  @override
  String get topoFlows => 'Verkehr zwischen den Linien';

  @override
  String get topoFlowsHint =>
      'Telegramme je Richtung: Absender in der einen Linie, Empfänger laut Projekt in der anderen.';

  @override
  String topoFlowRow(String telegrams, int groups) {
    return '$telegrams Telegramme · $groups Adressen';
  }

  @override
  String get topoFlowsNone => 'Noch kein Verkehr über die Koppler.';

  @override
  String get topoLive => 'Über die Koppler, live';

  @override
  String get topoLiveNone => 'Noch keine Telegramme über die Koppler.';

  @override
  String topoRailMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weitere Geräte',
      one: '1 weiteres Gerät',
    );
    return '$_temp0';
  }

  @override
  String get topoRailLess => 'Weniger zeigen';

  @override
  String get topoGroupValue => 'Wert';

  @override
  String get topoGroupLines => 'Linien';

  @override
  String get topoGroupDetails => 'Verlauf & Schreiben';

  @override
  String get topoGroupUnlinked => 'Gehört, nicht im Projekt verknüpft';

  @override
  String get topoGroupRecent => 'Letzte Telegramme';

  @override
  String get topoGroupChannel => 'Kanal';

  @override
  String get topoGroupHeard => 'gehört';

  @override
  String get topoGroupSends => 'sendet';

  @override
  String get topoGroupListens => 'hört';

  @override
  String get topoGroupChannels => 'Kanäle';

  @override
  String buttonKeySemantics(String key, String state) {
    return 'Taste $key: $state';
  }

  @override
  String buttonLastPress(String key, String value, String time) {
    return 'Zuletzt gedrückt: $key → $value · $time';
  }

  @override
  String get buttonNoPress => 'Noch kein Tastendruck seit dem Verbinden';

  @override
  String buttonPage(String page, String count) {
    return 'Ebene $page von $count';
  }

  @override
  String get watchTitle => 'Wächter';

  @override
  String watchHit(String what) {
    return 'Wächter: $what';
  }

  @override
  String get watchAdd => 'Wächter auf diese Adresse';

  @override
  String get watchRemove => 'Wächter entfernen';

  @override
  String watchAdded(String what) {
    return 'Wächter scharf: $what';
  }

  @override
  String get watchTool =>
      'Ton und Mitteilung, sobald eine Adresse gesendet wird';

  @override
  String get watchExplain =>
      'Ein Wächter meldet sich mit Ton und Mitteilung, sobald seine Gruppenadresse gesendet wird – optional nur bei einem bestimmten Wert. Er hört mit, solange der Monitor verbunden ist; auf iPhone und iPad bleibt dafür der Bildschirm an.';

  @override
  String get watchEmpty =>
      'Noch keine Wächter. Lege einen an oder tippe in den Details einer Adresse auf die Glocke.';

  @override
  String get watchNew => 'Neuer Wächter';

  @override
  String get watchSound => 'Mit Ton';

  @override
  String get watchInvalid => 'Bitte eine Gruppenadresse wie 1/2/3 eingeben.';

  @override
  String get accountUseEverywhere => 'Auf weiteren Geräten nutzen';

  @override
  String accountSignedInAs(String email) {
    return 'Angemeldet als $email';
  }

  @override
  String get planCheckoutOpened =>
      'Die Kaufseite ist im Browser offen. Nach dem Kauf hier „Käufe wiederherstellen“ tippen.';

  @override
  String get planPendingApproval =>
      'Der Kauf wartet noch auf Freigabe, etwa durch „Kaufen anfragen“ oder die Zahlungsart. Sobald er bestätigt ist, wird die Stufe freigeschaltet.';

  @override
  String get planNotYetAvailable =>
      'Plus und Pro sind hier noch nicht verfügbar.';

  @override
  String planOpenNotice(String date) {
    return 'Bisher war alles frei. Jetzt gibt es Free, Plus und Pro: Du behältst Pro noch bis $date, danach gilt Free. Deine Daten bleiben erhalten.';
  }

  @override
  String get planOpenEnded =>
      'Die Übergangszeit ist vorbei, jetzt gilt Free. Deine Daten bleiben erhalten. Mit Plus oder Pro sind die Werkzeuge wieder da.';

  @override
  String get planSignInToBuy => 'Zum Kaufen anmelden';

  @override
  String get diagTitle => 'Diagnosepaket';

  @override
  String get diagTool =>
      'Fehler mit Aufzeichnung und Projekt an den Support schicken';

  @override
  String get diagIntro =>
      'Das Paket hilft dem Support, deinen Fehler nachzustellen: Busaufzeichnung, Projekt, deine Beschreibung und technische Eckdaten in einer ZIP-Datei. Es kann Personenbezug haben: Prüfe vor dem Senden, was drin ist.';

  @override
  String get diagProblemLabel => 'Was ist passiert?';

  @override
  String get diagProblemHint =>
      'z. B. Licht Küche reagiert nicht auf den Taster';

  @override
  String get diagExpectedLabel => 'Was hast du erwartet? (optional)';

  @override
  String diagOccurred(String time) {
    return 'Zeitpunkt des Fehlers: $time';
  }

  @override
  String get diagSourceLabel => 'Busaufzeichnung';

  @override
  String diagSourceSession(int count) {
    return 'Laufende Sitzung · $count Telegramme';
  }

  @override
  String get diagRangeLabel => 'Zeitraum um den Fehler';

  @override
  String get diagRangeAll => 'Alles';

  @override
  String diagRangeMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get diagRangeHint =>
      'Minuten vor dem Fehler (bei einer Aufnahme vor ihrem Ende).';

  @override
  String get diagNamesTitle => 'Namen mitsenden';

  @override
  String diagNamesHint(String examples) {
    return 'Namen von Gruppenadressen und Geräten, z. B. $examples. Sie helfen bei der Auswertung; ohne sie stehen dort nur Adressen und Produkte.';
  }

  @override
  String get diagNamesHintEmpty =>
      'Namen von Gruppenadressen und Geräten helfen bei der Auswertung; ohne sie stehen dort nur Adressen und Produkte.';

  @override
  String get diagContents => 'Inhalt';

  @override
  String diagContentRecording(int count, String from, String to) {
    return 'Busaufzeichnung: $count Telegramme, $from – $to';
  }

  @override
  String diagContentSecure(int count) {
    return 'Data Secure: $count Telegramme nur mit Zeit und Adressen, ohne Inhalt';
  }

  @override
  String diagContentProject(int groups, int devices) {
    return 'Projekt: $groups Gruppenadressen, $devices Geräte, Datenpunkttypen und Verknüpfungen';
  }

  @override
  String get diagContentNamesIn =>
      'Namen von Gruppenadressen und Geräten: enthalten';

  @override
  String get diagContentNamesOut =>
      'Namen von Gruppenadressen und Geräten: entfernt';

  @override
  String get diagContentTechnical =>
      'Technik: App-Version, Plattform und Betriebssystem, Verbindungsart, Gateway-Typ und -Name, Plan, Expertenmodus, Sprache, Einstellungen';

  @override
  String diagContentLog(int count) {
    return 'Meldungen der App: $count Zeilen';
  }

  @override
  String get diagExcluded =>
      'Nicht enthalten: Passwörter, Keyring und Schlüssel, ETS-Projektdatei. Aus Texten herausgefiltert, soweit erkennbar: IP-Adressen, Hostnamen, MAC- und Seriennummern, E-Mail, bekannte Namen von Projekt, Installation, Kunde und Betrieb.';

  @override
  String get diagShowFile => 'Dateiinhalt ansehen';

  @override
  String get diagShare => 'Paket teilen';

  @override
  String get diagSave => 'Paket speichern';

  @override
  String get diagDownload => 'Paket herunterladen';

  @override
  String get diagPackageInvalid => 'Kein Diagnosepaket von KNX Monitor.';

  @override
  String get diagPackageNewer =>
      'Das Diagnosepaket stammt aus einer neueren App-Version.';

  @override
  String get diagImportDisconnect =>
      'Zum Öffnen eines Diagnosepakets zuerst die Verbindung trennen.';

  @override
  String diagImported(String name) {
    return 'Diagnosepaket als Installation „$name“ geöffnet.';
  }

  @override
  String get diagImportedRecordingOnly =>
      'Aufnahme übernommen. Das Projekt aus dem Paket lässt sich nur in den Apps laden.';

  @override
  String diagNoteProblem(String text) {
    return 'Was ist passiert: $text';
  }

  @override
  String diagNoteExpected(String text) {
    return 'Erwartet: $text';
  }

  @override
  String diagInstallationName(String date) {
    return 'Diagnose $date';
  }

  @override
  String get diagImportHint =>
      'Importieren: ETS-Telegrammdatei (.xml) oder Diagnosepaket (.zip)';

  @override
  String get filterActive => 'Gefiltert';

  @override
  String get watchContains => 'enthält';

  @override
  String get watchCondition => 'Bedingung';

  @override
  String get watchAnyValue => 'beliebiger Wert';

  @override
  String get watchValueExample => 'z. B. Ein oder 20';

  @override
  String get watchAddressHint => '1/2/3 oder Name';

  @override
  String get watchCreate => 'Anlegen';

  @override
  String get connectModeLabel => 'Verbindungsart';

  @override
  String get commNextOpen => 'Nächster offener Punkt';

  @override
  String get commLinked => 'Verknüpfte Geräte';

  @override
  String deviceSendValue(String value, String address) {
    return '$value an $address senden';
  }

  @override
  String checkFindings(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Abweichungen',
      one: '1 Abweichung',
    );
    return '$_temp0';
  }

  @override
  String get topoRailActuators => 'Verteiler';

  @override
  String get topoRailSensors => 'Sensoren';

  @override
  String get monitorLeaveTitle => 'Verbindung trennen?';

  @override
  String get monitorLeaveText =>
      'Zurück zur Startseite trennt die Verbindung zum Gateway. Aufnahmen und Wächter laufen dann nicht weiter.';

  @override
  String get checkSectionTraffic => 'Busverkehr';

  @override
  String get checkSectionProject => 'Projekt';

  @override
  String get checkStatusNoTransmit => 'Rückmeldung ohne Ü-Flag';

  @override
  String get checkStatusNoTransmitHint =>
      'An dieser Rückmeldeadresse sendet kein Objekt mit Ü-Flag – der Status kommt nie auf den Bus.';

  @override
  String get checkMultipleSenders => 'Mehrere Sender';

  @override
  String get checkMultipleSendersHint =>
      'Mehrere Objekte senden auf dieselbe Adresse. Bei Tastern, Meldern und Visualisierung gewollt, bei Aktorkanälen meist ein Versehen.';

  @override
  String get checkReadNoReadFlag => 'Gelesen ohne L-Flag';

  @override
  String get checkReadNoReadFlagHint =>
      'Status lesen und Inbetriebnahme fragen diese Adressen ab. Ohne Objekt mit L-Flag bleibt die Anfrage unbeantwortet.';

  @override
  String get checkDevicesNoLinks => 'Geräte ohne Verknüpfung';

  @override
  String get checkDevicesNoLinksHint =>
      'Kein Objekt dieser Geräte hat eine Gruppenadresse – nicht fertig projektiert oder überzählig. Koppler und Tunnel zählen nicht.';

  @override
  String get checkObjectsNoComm => 'Objekte ohne K-Flag';

  @override
  String get checkObjectsNoCommHint =>
      'Das Objekt hat eine Adresse, aber kein K-Flag – es nimmt am Busverkehr nicht teil.';

  @override
  String get checkIncomplete => 'Ohne Namen oder Datentyp';

  @override
  String get checkIncompleteHint =>
      'Ohne Namen und Datentyp zeigen Monitor, Diagnose und der Gruppenmonitor der ETS nur Adresse und Rohwert. Beides in der ETS nachtragen.';

  @override
  String get checkNoName => 'ohne Namen';

  @override
  String get checkMultipleReadAnswers => 'L-Flag mehrfach';

  @override
  String get checkMultipleReadAnswersHint =>
      'Mehrere Objekte mit L-Flag antworten alle auf eine Leseanfrage, womöglich mit verschiedenen Werten. Das L-Flag gehört nur an das Objekt, das den Zustand führt.';

  @override
  String get checkWithoutSender => 'Ohne Sender';

  @override
  String get checkWithoutSenderHint =>
      'Im Projekt sendet kein Objekt auf diese Adresse. Meist Visualisierung, Logik oder Panel ohne Platzhalter im Projekt – dann bleiben ihre Telegramme im Monitor namenlos –, sonst eine vergessene Verknüpfung.';

  @override
  String get checkWithoutReceiver => 'Ohne Empfänger';

  @override
  String get checkWithoutReceiverHint =>
      'Kein Objekt mit K- und S-Flag hört auf diese Adresse – Telegramme darauf bewirken nichts.';

  @override
  String get checkCrowdedLines => 'Volle Linien';

  @override
  String checkCrowdedLinesHint(int limit) {
    return 'Mehr als $limit Geräte: Die Linie hat kaum Reserve für Erweiterungen und Busstrom. Ein Liniensegment trägt höchstens 64 Teilnehmer.';
  }

  @override
  String checkLineDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Geräte',
      one: '1 Gerät',
    );
    return '$_temp0';
  }

  @override
  String get checkMainGroup1415 => 'Hauptgruppe 14 oder 15';

  @override
  String get checkMainGroup1415Hint =>
      'Ältere Linienkoppler führen diese Hauptgruppen nicht in der Filtertabelle und sperren sie oder leiten sie immer weiter. Für linienübergreifende Adressen besser die Hauptgruppen 0–13.';

  @override
  String get checkCentralOffOn => 'Zentral-Aus mit Ein';

  @override
  String get checkReimport =>
      'ETS-Projekt neu importieren, um die Flags zu lesen';

  @override
  String get flagLetters => 'KLSÜA';

  @override
  String get flagsNone => 'keine Flags';

  @override
  String get healthNothingToRead =>
      'Noch keine Adresse zum Lesen: Ohne ETS-Projekt prüft Gesundheit den mitgehörten Verkehr. Mit Projekt liest sie auch alle Status-Adressen.';

  @override
  String get commOkManual => 'Von Hand OK';

  @override
  String get importReading => 'Datei wird eingelesen …';

  @override
  String get importOpening => 'Projekt wird geöffnet …';

  @override
  String get importDecrypting => 'Projekt wird entschlüsselt und ausgelesen …';

  @override
  String get importSaving => 'Projekt wird gespeichert …';

  @override
  String get importSlowHint =>
      'Große Projekte brauchen im Browser bis zu einer Minute.';

  @override
  String get addonAttaching => 'Verbinde mit dem Add-on …';

  @override
  String get watchWithSound => 'mit Ton';

  @override
  String get watchSilent => 'ohne Ton';

  @override
  String get watchActive => 'Wächter aktiv';

  @override
  String get watchExplainServer =>
      'Ein Wächter meldet sich, sobald seine Gruppenadresse gesendet wird – optional nur bei einem bestimmten Wert. Das Add-on prüft ihn auch ohne offene App und schickt eine Home-Assistant-Mitteilung; ein offener Monitor spielt dazu den Ton.';

  @override
  String get boardNoTelegramYet => 'Noch kein Telegramm';

  @override
  String get chartsNoValuesYet => 'noch keine Werte';

  @override
  String get chartsWaiting =>
      'Wartet auf die ersten Telegramme – die Reihen erscheinen, sobald die Adressen senden.';

  @override
  String checkEvaluatedTelegrams(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Telegramme ausgewertet',
      one: '1 Telegramm ausgewertet',
    );
    return '$_temp0';
  }

  @override
  String diagSourceHistory(String date) {
    return 'Langzeitverlauf $date';
  }

  @override
  String get annotationTitle => 'Kommentar';

  @override
  String get annotationEditTitle => 'Kommentar bearbeiten';

  @override
  String get annotationNoteLabel => 'Was ist passiert?';

  @override
  String get annotationNoteHint => 'Drittes Mal gedrückt: Licht bleibt aus';

  @override
  String get annotationEmpty =>
      'Schreib kurz, was passiert ist, oder füg einen Screenshot hinzu.';

  @override
  String get annotationDelete => 'Kommentar löschen';

  @override
  String get annotationAdd => 'Kommentieren';

  @override
  String annotationAboutTime(String time) {
    return 'Zeitpunkt $time';
  }

  @override
  String annotationAboutChart(String names) {
    return 'Diagramm $names';
  }

  @override
  String get annotationsLabel => 'Kommentare';

  @override
  String get annotationsTitle => 'Kommentare';

  @override
  String get annotationsTool =>
      'Was dir an Telegrammen und im Verlauf aufgefallen ist';

  @override
  String get annotationsEmpty =>
      'Noch keine Kommentare. Tippe ein Telegramm an und wähle „Kommentieren“, oder setz im Diagramm einen Kommentar am Fadenkreuz.';

  @override
  String get shotsLabel => 'Screenshots';

  @override
  String get shotsAdd => 'Screenshot hinzufügen';

  @override
  String shotsHint(int max) {
    return 'Bis zu $max, verkleinert. Prüf vorher, ob darauf Adressen, Namen oder Passwörter zu sehen sind, die nicht weitergegeben werden sollen.';
  }

  @override
  String shotsInvalid(String name) {
    return '$name ist kein lesbares Bild.';
  }

  @override
  String get shotsQuota =>
      'Der Platz für Screenshots ist voll. Lösch ältere Kommentare mit Bildern, um neue hinzuzufügen.';

  @override
  String get shotsOpen => 'Screenshot groß zeigen';

  @override
  String get shotsRemove => 'Screenshot entfernen';

  @override
  String get timelineTitle => 'Zeitleiste';

  @override
  String get timelineHint =>
      'Ziehen verschiebt, Strg bzw. Cmd mit Mausrad oder zwei Finger zoomen. Zeiger auf ein Telegramm zeigt es, Tippen kommentiert es. Tippen auf die Zeitachse springt mit der Wiedergabe dorthin.';

  @override
  String get timelineEmpty => 'Diese Aufnahme enthält keine Telegramme.';

  @override
  String get timelineNoAnnotations =>
      'Noch keine Kommentare in diesem Zeitraum. Tippe auf ein Telegramm oder eine Stelle in der Zeitleiste.';

  @override
  String get timelineRepeated => 'Wiederholung';

  @override
  String timelineSemantics(int telegrams, int notes) {
    return 'Zeitleiste mit $telegrams Telegrammen und $notes Kommentaren';
  }

  @override
  String chartsAnnotate(String time) {
    return 'Kommentar bei $time';
  }

  @override
  String get chartsAnnotateHint =>
      'Zum Kommentieren eine Stelle im Diagramm wählen';

  @override
  String diagAnnotationsInRange(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Kommentare im Zeitraum kommen mit',
      one: '1 Kommentar im Zeitraum kommt mit',
      zero: 'Keine Kommentare im Zeitraum',
    );
    return '$_temp0';
  }

  @override
  String diagOlderAnnotations(int count) {
    return 'Ältere Kommentare mitschicken ($count)';
  }

  @override
  String diagOlderAnnotationsHint(int days) {
    return 'Aus den letzten $days Tagen, außerhalb der Aufnahme, mit dem Telegramm dazu';
  }

  @override
  String diagContentAnnotations(int notes, int shots) {
    String _temp0 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes Kommentare',
      one: '1 Kommentar',
      zero: 'Keine Kommentare',
    );
    String _temp1 = intl.Intl.pluralLogic(
      shots,
      locale: localeName,
      other: '$shots Screenshots',
      one: '1 Screenshot',
      zero: 'keine Screenshots',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String diagLarge(int mb) {
    return 'Das Paket ist $mb MB groß und passt vielleicht nicht als E-Mail-Anhang.';
  }

  @override
  String diagRangeSince(String time) {
    return 'Zeitraum: seit dem Start um $time';
  }

  @override
  String get findingsTitle => 'Befund';

  @override
  String get findingsProblem => 'Fehlerbild';

  @override
  String get findingsNoProblem => 'Keine Beschreibung';

  @override
  String findingsExpected(String text) {
    return 'Erwartet: $text';
  }

  @override
  String findingsOccurred(String time) {
    return 'Aufgetreten $time';
  }

  @override
  String get findingsHints => 'Hinweise';

  @override
  String get findingsNoHints => 'Nichts Auffälliges in Technik und Verkehr.';

  @override
  String get findingsNoAnnotations => 'Keine Kommentare im Paket.';

  @override
  String get findingsBusiest => 'Häufigste Adressen';

  @override
  String get findingsTechnical => 'Technik';

  @override
  String findingsLog(int count) {
    return 'Log ($count)';
  }

  @override
  String get findingsOnlyErrors => 'Nur Fehler';

  @override
  String get findingsNoLog => 'Kein Log im Paket.';

  @override
  String get findingsNoLogErrors => 'Keine Fehler im Log.';

  @override
  String get findingLevelCritical => 'Fehler';

  @override
  String get findingLevelWarning => 'Prüfen';

  @override
  String get findingLevelInfo => 'Info';

  @override
  String findingConnectionError(String error) {
    return 'Verbindungsfehler: $error';
  }

  @override
  String findingConnectionState(String state) {
    return 'Verbindung war nicht aufgebaut ($state).';
  }

  @override
  String findingSecureRejected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Secure-Telegramme abgelehnt',
      one: '1 Secure-Telegramm abgelehnt',
    );
    return '$_temp0: Schlüssel oder Zähler passen nicht.';
  }

  @override
  String findingSecureWithoutKey(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Secure-Telegramme',
      one: '1 Secure-Telegramm',
    );
    return '$_temp0 ohne Schlüssel: Keyring fehlt oder ist unvollständig.';
  }

  @override
  String findingRepeated(int count, int percent) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Wiederholungen',
      one: '1 Wiederholung',
    );
    return '$_temp0 ($percent %): Hinweis auf Störungen oder fehlende Quittungen.';
  }

  @override
  String findingPeakLoad(int count) {
    return 'Lastspitze: $count Telegramme in einer Sekunde. Häufig melden nach Busspannungswiederkehr oder einem Zentralbefehl viele Aktoren gleichzeitig zurück – Sendeverzögerung der Aktoren staffeln.';
  }

  @override
  String findingUnansweredReads(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Leseanfragen',
      one: '1 Leseanfrage',
    );
    return '$_temp0 ohne Antwort: L-Flag oder Gerät prüfen.';
  }

  @override
  String findingConfirmErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Telegramme',
      one: '1 Telegramm',
    );
    return '$_temp0 ohne Bestätigung der Schnittstelle.';
  }

  @override
  String findingOutages(int count, String summary) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ausfälle',
      one: '1 Ausfall',
    );
    return '$_temp0 in den letzten 7 Tagen: $summary';
  }

  @override
  String findingLogErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Fehlerzeilen',
      one: '1 Fehlerzeile',
    );
    return '$_temp0 im Log der App.';
  }

  @override
  String findingOldVersion(String version, String current) {
    return 'Ältere App-Version $version (aktuell $current).';
  }

  @override
  String findingBuildMode(String mode) {
    return 'Kein Release-Build ($mode).';
  }

  @override
  String get findingNoTelegrams => 'Die Aufnahme enthält keine Telegramme.';

  @override
  String get factApp => 'App';

  @override
  String get factPlatform => 'Plattform';

  @override
  String get factAddon => 'Add-on';

  @override
  String get factConnection => 'Verbindung';

  @override
  String get factTunnel => 'Tunnel';

  @override
  String get factGateway => 'Gateway';

  @override
  String factTunnelSlots(int count) {
    return '$count Tunnel';
  }

  @override
  String get factSecure => 'Secure';

  @override
  String factSecureLoaded(int count) {
    return 'Keyring geladen, $count Gruppenschlüssel';
  }

  @override
  String get factSecureNone => 'Kein Keyring';

  @override
  String get factTraffic => 'Verkehr';

  @override
  String factTrafficValue(int telegrams, int repeated, int unanswered) {
    return '$telegrams Telegramme · $repeated Wiederholungen · $unanswered unbeantwortet';
  }

  @override
  String get factPlan => 'Stufe';

  @override
  String get factExpert => 'Expertenmodus';

  @override
  String get reportTitle => 'Fehler melden';

  @override
  String get reportTool => 'Fehler nachstellen und dem Elektriker schicken';

  @override
  String get reportIntro =>
      'Etwas funktioniert nicht wie gedacht? Nimm den Fehler hier auf, dann sieht dein Elektriker genau, was auf dem Bus passiert ist, ohne vorbeikommen zu müssen.';

  @override
  String get reportStep1 => 'Starte die Aufnahme.';

  @override
  String get reportStep2 =>
      'Stell den Fehler nach, z. B. den Taster drücken. Tippe jedes Mal auf „Jetzt ist es passiert“, wenn der Fehler auftritt.';

  @override
  String get reportStep3 =>
      'Beschreib kurz, was passiert ist, und schick das Paket an deinen Elektriker.';

  @override
  String get reportNotConnected =>
      'Die App ist gerade nicht mit dem Bus verbunden. Es wird nur aufgenommen, was nach dem Verbinden ankommt.';

  @override
  String get reportStart => 'Aufnahme starten';

  @override
  String reportRunning(String time, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Telegramme',
      one: '1 Telegramm',
    );
    return 'Aufnahme läuft seit $time · $_temp0';
  }

  @override
  String get reportNowHint =>
      'Stell den Fehler jetzt nach. Sobald er auftritt:';

  @override
  String get reportNow => 'Jetzt ist es passiert';

  @override
  String reportMarkNote(int n) {
    return 'Fehler aufgetreten ($n)';
  }

  @override
  String get reportNoMarks => 'Noch nicht markiert.';

  @override
  String reportMarks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Mal markiert',
      one: '1 Mal markiert',
    );
    return '$_temp0';
  }

  @override
  String get reportMarksHint =>
      'Antippen, um zu beschreiben, was genau passiert ist, oder einen Screenshot dazuzulegen.';

  @override
  String get reportFinish => 'Fertig, Paket erstellen';

  @override
  String annotationsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Kommentare',
      one: '1 Kommentar',
    );
    return '$_temp0';
  }

  @override
  String annotationsAll(int count) {
    return 'Alle $count Kommentare';
  }

  @override
  String get annotationChoiceTitle => 'Kommentieren';

  @override
  String annotationChoiceText(String time) {
    return 'Die App kann zusätzlich eine Aufnahme ab $time starten, kurz vor diesem Telegramm, damit es sich später nachvollziehen lässt.';
  }

  @override
  String get annotationChoiceOnly => 'Nur kommentieren';

  @override
  String get annotationChoiceRecord => 'Auch aufnehmen';

  @override
  String deviceGeneralObjects(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Objekte ohne Kanal',
      one: '1 Objekt ohne Kanal',
    );
    return '$_temp0';
  }

  @override
  String get annotationRecordFailed =>
      'Aufnahme nicht gestartet. Der Kommentar wird trotzdem gespeichert.';

  @override
  String get dptChange => 'Datentyp ändern';

  @override
  String dptChangedFromEts(String dpt) {
    return 'Datentyp geändert, ETS: DPT $dpt';
  }

  @override
  String get checkDptChanged => 'In der App geänderte Datentypen';

  @override
  String get checkDptChangedHint =>
      'In der ETS nachziehen, sonst gilt nach dem nächsten Projekt-Import dort weiter der alte Datentyp.';

  @override
  String checkDptChangedRow(String ets, String app) {
    return 'ETS: $ets → App: DPT $app';
  }

  @override
  String get checkDptNone => 'ohne Datentyp';

  @override
  String get detailsFilterOff => 'Filter aus';

  @override
  String get pdfBuilding => 'PDF wird erstellt …';

  @override
  String get exportsTitle => 'Exporte';

  @override
  String get exportsReports => 'Berichte';

  @override
  String get exportsNoData => 'Noch keine Daten';

  @override
  String exportsHealthRun(String time, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Befunde',
      one: '1 Befund',
      zero: 'keine Befunde',
    );
    return 'Lauf $time · $_temp0';
  }

  @override
  String exportsCommState(int checked, int total) {
    return '$checked von $total geprüft';
  }

  @override
  String get exportsBundle => 'Gesamtexport';

  @override
  String get exportsBundleHint =>
      'Wähle aus, was in eine ZIP-Datei soll. Sie entsteht im Hintergrund.';

  @override
  String exportsBundleButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien als ZIP exportieren',
      one: '1 Datei als ZIP exportieren',
      zero: 'Nichts ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String get exportsBuilding => 'Export wird erstellt …';

  @override
  String get exportsRecent => 'Letzte Exporte';

  @override
  String exportsRecentEmpty(int keep) {
    return 'Noch keine Exporte. Die letzten $keep Dateien dieser Installation erscheinen hier und lassen sich erneut teilen.';
  }

  @override
  String get exportsRemove => 'Aus der Liste entfernen';

  @override
  String get exportsGone => 'Datei nicht mehr vorhanden';

  @override
  String get exportsCheck => 'Prüfen';

  @override
  String get exportsRecheck => 'Erneut prüfen';

  @override
  String get exportsChecking => 'Läuft …';

  @override
  String get exportsCheckOffline => 'Zum Prüfen mit dem Bus verbinden';

  @override
  String get exportsCheckOpen => 'Offene prüfen';

  @override
  String detailsHistoryLatest(int shown, int total) {
    return 'Die letzten $shown von $total Werten – alle im Vollbild';
  }

  @override
  String get boxPairPassword => 'Box-Passwort';

  @override
  String get boxPairPasswordHint =>
      'Nur bei IP-Adresse nötig. Steht als BOX_PASSWORD in knx-box.txt auf der SD-Karte.';

  @override
  String get boxNetwork => 'Netz';

  @override
  String get boxLanAccess => 'Zugriff über das Kabel';

  @override
  String get boxLanAccessHint =>
      'Aus: Die Box ist nur in ihrem eigenen WLAN erreichbar, beim Kunden kommt niemand aus dessen Netz an sie heran. An: für die eigene Box im eigenen Netz, dann reicht dort das Box-Passwort.';

  @override
  String get boxLanAccessOffTitle => 'Zugriff über das Kabel sperren?';

  @override
  String get boxLanAccessOffBody =>
      'Geräte, die die Box über das Netz am Kabel erreichen, verlieren den Zugriff, auch dieses, wenn es gerade nicht im WLAN der Box ist. Danach geht es nur noch im WLAN der Box.';

  @override
  String get boxLanAccessOff => 'Sperren';

  @override
  String get boxPasswordAskTitle => 'Eigenes Box-Passwort setzen?';

  @override
  String get boxPasswordAskBody =>
      'Das bisherige Passwort steht auf dem Aufkleber und auf der SD-Karte. Wer es hat, kann sich mit der Box koppeln. Mit einem eigenen Passwort geht das nicht mehr; dieses Gerät bleibt gekoppelt.';

  @override
  String get boxPasswordAskLater => 'Später';

  @override
  String get haKnxHintTitle => 'KNX-Integration gefunden';

  @override
  String get haKnxHintBody =>
      'Home Assistant ist schon mit dem Bus verbunden. Das Add-on kann diese Verbindung mitnutzen, statt einen eigenen Tunnelplatz am Gateway zu belegen. Für Programmiermodus, Adresse prüfen und den Busmonitor braucht es weiter einen eigenen Tunnel.';

  @override
  String get haKnxHintUse => 'Ohne eigenen Tunnel verbinden';

  @override
  String get haKnxHintDismiss => 'Eigenen Tunnel behalten';

  @override
  String versionApp(String version) {
    return 'KNX Monitor $version';
  }

  @override
  String versionAddon(String version) {
    return 'Add-on $version';
  }

  @override
  String versionBox(String version) {
    return 'Box $version';
  }

  @override
  String get boxHat => 'KNX-HAT (Test)';

  @override
  String get boxHatHint =>
      'Prüft das Aufsteckmodul kBerry am seriellen Anschluss der Box: Antwort, Betriebsarten, Telegramme und Busmonitor mit Quittungen.';

  @override
  String get boxHatTitle => 'KNX-HAT prüfen';

  @override
  String get boxHatIntro =>
      'Vorschau für den direkten Busanschluss. Busleitung an das Modul, Busspannung an. Während der Prüfung ein paar Taster drücken, damit Telegramme und Quittungen kommen. Die Aufzeichnung über IP läuft weiter.';

  @override
  String get boxHatSystem => 'System';

  @override
  String boxHatSystemOk(String device) {
    return '$device ist bereit.';
  }

  @override
  String boxHatDeviceMissing(String device) {
    return '$device fehlt. UART-Einstellung in config.txt prüfen und die Box neu starten.';
  }

  @override
  String boxHatDeviceNoAccess(String device, String error) {
    return 'Kein Zugriff auf $device: $error';
  }

  @override
  String get boxHatSerialConsole =>
      'Die Linux-Konsole liegt noch auf dem seriellen Anschluss (cmdline.txt).';

  @override
  String get boxHatSeconds => 'Mithören je Schritt';

  @override
  String get boxHatStart => 'Prüfung starten';

  @override
  String boxHatRunning(String step) {
    return 'Läuft: $step';
  }

  @override
  String get boxHatNoReport => 'Noch keine Prüfung gelaufen.';

  @override
  String get boxHatResult => 'Ergebnis';

  @override
  String get boxHatCopy => 'Bericht kopieren';

  @override
  String get boxHatCopied => 'Bericht kopiert';

  @override
  String get boxHatStepReset => 'Verbindung';

  @override
  String get boxHatStepIdentify => 'Kennung';

  @override
  String get boxHatStepSerial => 'Seriennummer';

  @override
  String get boxHatStepModes => 'Betriebsarten';

  @override
  String get boxHatStepCommMode => 'Betriebsart beim Start';

  @override
  String get boxHatStepLinkLayer => 'Telegramme (Link Layer)';

  @override
  String get boxHatStepBusmonitor => 'Busmonitor mit Quittungen';

  @override
  String get boxHatStepRestore => 'Zurück in den BAOS-Modus';

  @override
  String boxHatBaud(int baud) {
    return '$baud Baud';
  }

  @override
  String get boxHatNoAnswer => 'keine Antwort';

  @override
  String get boxHatSkipped => 'übersprungen';

  @override
  String get boxHatNoBusmonitor => 'kein Busmonitor';

  @override
  String boxHatFrames(int count, int seconds) {
    return '$count Telegramme in $seconds s';
  }

  @override
  String boxHatBusmonCounts(
    int frames,
    int ack,
    int nak,
    int busy,
    int repeated,
    int errors,
  ) {
    return '$frames Frames: $ack ACK, $nak NAK, $busy BUSY, $repeated Wiederholungen, $errors mit Fehlern';
  }

  @override
  String get boxHatNothing =>
      'Nichts empfangen. Taster drücken und erneut prüfen.';

  @override
  String get boxHatModeLinkLayer => 'Link Layer';

  @override
  String get boxHatModeBusmonitor => 'Busmonitor';

  @override
  String get boxHatModeTransportLayer => 'Transport Layer';

  @override
  String get tourButton => 'Einführung';

  @override
  String get tourNext => 'Weiter';

  @override
  String get tourBack => 'Zurück';

  @override
  String get tourClose => 'Einführung schließen';

  @override
  String tourProgress(int current, int total) {
    return '$current von $total';
  }

  @override
  String get tourDemoHouse => 'Demo-Haus';

  @override
  String get tourChapterBasics => 'Grundlagen';

  @override
  String get tourChapterAnalysis => 'Auswertung';

  @override
  String get tourChapterExpert => 'Expertenmodus';

  @override
  String get tourWelcomeTitle => 'Sieh, was auf deinem Bus passiert.';

  @override
  String get tourWelcomeText =>
      'KNX Monitor hört am KNX-IP-Gateway mit und zeigt jedes Telegramm: wer sendet, an welche Gruppenadresse, mit welchem Wert. Diese Einführung führt durch die wichtigsten Stellen, mit dem Demo-Haus als Beispiel.';

  @override
  String get tourConnectTitle => 'Verbinden in einem Schritt.';

  @override
  String get tourConnectText =>
      'Gateway suchen oder die Adresse eintragen, dann Verbinden. UDP passt zu jeder Schnittstelle; TCP, Routing und KNX IP Secure stehen unter Verbindungsart. Jede Anlage hat ihre Installation mit Gateway, Projekt und Einstellungen.';

  @override
  String get tourChipSearch => 'Gateway suchen';

  @override
  String get tourChipInstallations => 'Installationen';

  @override
  String get tourProjectTitle =>
      'Mit dem ETS-Projekt bekommt jeder Wert einen Namen.';

  @override
  String get tourProjectText =>
      'Importiere die .knxproj-Datei, auch mit Passwort, oder eine Gruppenadressen-CSV. Dann stehen Namen, Räume, Datentypen und Geräte da statt 1/2/3 und Rohbytes. Für KNX Secure kommt der Keyring dazu. Alles bleibt auf dem Gerät.';

  @override
  String get tourChipCsv => 'Gruppenadressen-CSV';

  @override
  String get tourChipLocal => 'Bleibt auf dem Gerät';

  @override
  String get tourOverviewTitle => 'Übersicht: jede Adresse als Karte.';

  @override
  String get tourOverviewText =>
      'Aktueller Wert, Anzahl und ein Mini-Verlauf, sortiert nach Räumen und Funktionen. Der Stern merkt Favoriten, die Nadel holt eine Sektion nach oben. Die Leiste oben zählt die Telegramme der letzten 60 Sekunden, der Stunde oder des Tages.';

  @override
  String get tourObjectsTitle => 'Objekte: was zusammengehört, steht zusammen.';

  @override
  String get tourObjectsText =>
      'Befehl und Rückmeldung eines Lichts, alle Werte eines Raumthermostats: in einer Karte. Aktoren erscheinen als Hutschienengeräte mit leuchtenden Kanal-LEDs.';

  @override
  String get tourLiveTitle => 'Live: jedes Telegramm der Reihe nach.';

  @override
  String get tourLiveText =>
      'Zeit, Art (Schreiben, Lesen, Antwort), Absender, Ziel, Name und Wert. Auffälliges ist markiert, etwa eine falsche Länge oder ein ungewöhnlicher Routingzähler. Pause hält die Liste an, ohne etwas zu verlieren.';

  @override
  String get tourFilterTitle => 'Filtern statt suchen.';

  @override
  String get tourFilterText =>
      'Das Feld oben versteht Namen, Adressen, Geräte und Zeiten, auch zusammen. Gespeicherte Filter liegen hinter dem Lesezeichen im Feld.';

  @override
  String get tourChipFilterName => 'Wetter';

  @override
  String get tourChipFilterSender => 'von:1.1.10';

  @override
  String get tourChipFilterTime => 'zeit:14:05-14:10';

  @override
  String get tourDetailsTitle => 'Details: lesen, schreiben, kommentieren.';

  @override
  String get tourDetailsText =>
      'Ein Tipp auf eine Karte oder Zeile öffnet die Details: letzter Wert, Verlauf, Absender und verknüpfte Geräte. Von dort liest du den Wert neu, schreibst einen eigenen oder hängst einen Kommentar an.';

  @override
  String get tourHealthTitle => 'Gesundheit: Ist die Anlage in Ordnung?';

  @override
  String get tourHealthText =>
      'Ein Knopf liest alle Status-Adressen und wertet aus, was schon da ist: stumme Geräte, falsche Datentypen, auffällige Zyklen, Wiederholungen und Busqualität. Jeder Befund führt zur Adresse oder zum Gerät.';

  @override
  String get tourChipSilent => 'Stumme Adressen';

  @override
  String get tourChipTypes => 'Datentypen';

  @override
  String get tourChipCycles => 'Zyklen';

  @override
  String get tourChipBusQuality => 'Busqualität';

  @override
  String get tourRecordTitle => 'Aufnehmen, kommentieren, melden.';

  @override
  String get tourRecordText =>
      'Der rote Punkt nimmt auf, mit Name und Notiz. Kommentare hängen an Telegrammen und Aufnahmen, mit Bildschirmfotos. „Fehler melden“ hält fest, wann etwas schiefging, und packt alles für deinen Elektriker zusammen.';

  @override
  String get tourHistoryTitle => 'Verlauf über Tage.';

  @override
  String get tourHistoryText =>
      'Der Langzeitverlauf hebt ganze Tage auf, im Add-on und auf der KNX-Box rund um die Uhr. Du spulst zurück, was nachts passiert ist, mit Zeitleiste je Gruppenadresse und Wiedergabe in 1- bis 60-facher Geschwindigkeit.';

  @override
  String get tourChipTimeline => 'Zeitleiste';

  @override
  String get tourChipPlayback => 'Wiedergabe 1–60×';

  @override
  String get tourChartsTitle => 'Diagramme: mehrere Werte, eine Zeitachse.';

  @override
  String get tourChartsText =>
      'Bis zu acht Adressen zusammen, eine Achse je Einheit, Schaltwerte als eigene Zeilen. Gespeicherte Diagramme stehen als eigener Abschnitt in der Übersicht.';

  @override
  String get tourStatsTitle => 'Statistik: Wer redet am meisten?';

  @override
  String get tourStatsText =>
      'Aktivste Adressen und Absender, Lastspitzen und eine Heatmap über Tage. Ein Tipp auf eine Spitze oder Zelle filtert den Monitor auf diese Zeit.';

  @override
  String get tourWatchTitle => 'Wächter und Alarme.';

  @override
  String get tourWatchText =>
      'Ein Wächter meldet sich mit Ton, sobald eine bestimmte Adresse sendet oder einen Wert erreicht. Alarm- und Störobjekte stehen oben in der Übersicht und schicken auf Wunsch Mitteilungen.';

  @override
  String get tourChipSound => 'Mit Ton';

  @override
  String get tourExportTitle => 'Export in jedem Format.';

  @override
  String get tourExportText =>
      'Telegramme als PDF, CSV oder für die ETS, Berichte von Gesundheit und Inbetriebnahme und ein ZIP mit allem. Die Export-Seite sammelt die letzten Dateien je Installation.';

  @override
  String get tourExpertTitle => 'Ein Schalter, und die Werkstatt ist da.';

  @override
  String get tourExpertText =>
      'Der Expertenmodus auf dem Verbindungsbildschirm oder unten im Menü schaltet die Werkzeuge für Inbetriebnahme und Fehlersuche ein, dazu Port, Tunneladresse und Verbindungsoptionen. Ohne ihn bleibt die App schlank, verloren geht nichts.';

  @override
  String get tourChipPort => 'Port und Tunneladresse';

  @override
  String get tourBusmonTitle => 'Busmonitor: jedes Frame.';

  @override
  String get tourBusmonText =>
      'Rohframes mit Quittungen (ACK, NAK, BUSY), Wiederholungen und gestörten Telegrammen, die Absender in einer eigenen Spalte. Dafür muss die Schnittstelle den Busmonitor-Modus können.';

  @override
  String get tourChipAck => 'ACK · NAK · BUSY';

  @override
  String get tourChipRepeats => 'Wiederholungen';

  @override
  String get tourTopoTitle => 'Topologie: Linien und Koppler.';

  @override
  String get tourTopoText =>
      'Geräte nach Linien, Routingzähler, Tunnel und Verkehr über Koppler. Ein Gerät öffnet sein Blatt mit Kanälen, Tastern und Adressen.';

  @override
  String get tourMapTitle => 'Kommunikationskarte: wer mit wem.';

  @override
  String get tourMapText =>
      'Für jede Adresse, wer sendet und wer laut Projekt empfängt. Durchgezogen ist beobachtet, gestrichelt steht nur im Projekt.';

  @override
  String get tourCheckTitle => 'Projekt-Abgleich.';

  @override
  String get tourCheckText =>
      'Busverkehr gegen das ETS-Projekt: was fehlt, was unbekannt ist, was nie sendet, dazu die Flags der Objekte schon ohne Busverkehr.';

  @override
  String get tourCommTitle => 'Inbetriebnahme und Diagnose.';

  @override
  String get tourCommText =>
      'Die Checkliste liest alle Status-Adressen nacheinander und hakt Antworten ab; was offen bleibt, prüfst du vor Ort und bekommst ein PDF-Protokoll. Die Diagnose findet Geräte im Programmiermodus, prüft Adressen und scannt Linien.';

  @override
  String get tourChipProgMode => 'Programmiermodus';

  @override
  String get tourChipLineScan => 'Linienscan';

  @override
  String get tourSendTitle => 'Senden, auslösen, wiedergeben.';

  @override
  String get tourSendText =>
      'Senden wie im ETS-Gruppenmonitor, auch verzögert oder zyklisch. Trigger-Aufnahmen starten bei einem Wert, einer Störung oder einer Wiederholung, mit Vorlauf. Eine Aufnahme lässt sich auf den Bus zurückspielen, nach ausdrücklicher Bestätigung.';

  @override
  String get tourBoxTitle => 'KNX-Box für die Baustelle.';

  @override
  String get tourBoxText =>
      'Ein Raspberry Pi, der rund um die Uhr mitschreibt und ein eigenes WLAN aufspannt. Gekoppelt wird per Aufkleber, den Verlauf holt die App direkt von der Box. Noch eine Vorschau.';

  @override
  String get tourChipWifi => 'Eigenes WLAN';

  @override
  String get tourChipSticker => 'Koppeln per Aufkleber';

  @override
  String get tourMoreTitle => 'Mehr mit Plus und Pro.';

  @override
  String get tourMoreText =>
      'Plus hebt den Verlauf über Tage auf, bringt Diagramme, Statistik, Wächter und Export. Pro schaltet den Expertenmodus mit Busmonitor, Topologie, Inbetriebnahme und Diagnose frei. Im Demo-Haus kannst du alles ausprobieren.';

  @override
  String get tourMorePlans => 'Stufen ansehen';

  @override
  String get tourReadyTitle => 'Bereit.';

  @override
  String get tourReadyText =>
      'Im Demo-Haus probierst du alles gefahrlos aus, ganz ohne Anlage. Die Einführung findest du jederzeit wieder auf dem Verbindungsbildschirm.';

  @override
  String get tourOpenDemo => 'Demo-Haus öffnen';

  @override
  String get tourDone => 'Fertig';

  @override
  String get commSeen => 'Gesehen';

  @override
  String get commForeign => 'fremder Absender';

  @override
  String get commRollCall => 'Abhaken, sobald gesendet';

  @override
  String get commRollCallExplain =>
      'Durchklingeln: Taster drücken, Fenster öffnen – jede Adresse der Liste, die auf dem Bus sendet, hakt sich selbst ab. Sendet ein anderes Gerät als im Projekt, wird es markiert.';

  @override
  String get commToneOn => 'Mit Ton (Klangquittung)';

  @override
  String get commToneOff => 'Ton aus';

  @override
  String get ackTitle => 'Klangquittung';

  @override
  String get ackTool => 'Ton bei jedem Telegramm – allein in Betrieb nehmen';

  @override
  String get ackExplain =>
      'Spielt einen kurzen Ton bei jedem Telegramm einer Linie, eines Geräts, einer Gruppenadresse oder der Inbetriebnahme-Liste. So hörst du am Taster, ob er auf dem Bus ankommt – ohne zweite Person am Tablet.';

  @override
  String get ackTargetChecklist => 'Inbetriebnahme-Liste';

  @override
  String ackLine(String line) {
    return 'Linie $line';
  }

  @override
  String get ackInvalid => 'Adresse nicht erkannt';

  @override
  String get ackForegroundOnly =>
      'Die Quittung läuft, solange die App im Vordergrund ist.';

  @override
  String get ackAndroidBackground =>
      'Auf Android läuft die Quittung auch bei gesperrtem Bildschirm weiter (Mitteilung „Klangquittung“). Das Telefon kann in die Tasche.';

  @override
  String get ackIosForeground =>
      'iPhone und iPad: nur mit offener App, der Bildschirm bleibt dafür an. Im Hintergrund erlaubt iOS das Mithören nicht. Stummschalter aus, sonst bleibt es leise.';

  @override
  String get ackRunning => 'Läuft';

  @override
  String ackCount(int count) {
    return '$count Telegramme';
  }

  @override
  String get ackStop => 'Beenden';

  @override
  String get ackTarget => 'Wessen Telegramme?';

  @override
  String get ackKindChecklist => 'Liste';

  @override
  String get ackKindLine => 'Linie';

  @override
  String get ackKindDevice => 'Gerät';

  @override
  String get ackKindGroup => 'Adresse';

  @override
  String get ackAddress => 'Adresse';

  @override
  String get ackStart => 'Starten';

  @override
  String get ackSounds => 'Töne';

  @override
  String get ackSoundsExplain =>
      'Kurzer Ton: Schreiben. Heller Doppelton: Antwort. Tiefer Ton: Absender, der laut Projekt nicht an diese Adresse sendet oder unbekannt ist. Bei sehr vielen Telegrammen fallen Töne aus.';

  @override
  String get acceptTitle => 'Abnahmeprotokoll';

  @override
  String get acceptExplain =>
      'Hält den Stand der Inbetriebnahme fest: was geprüft ist, was offen ist, wer es gemacht hat. Kunde und Techniker unterschreiben auf dem Gerät; danach ist das Protokoll eingefroren und bei der Installation gespeichert.';

  @override
  String get acceptPdfTitle => 'Abnahmeprotokoll';

  @override
  String get acceptCustomerSection => 'Kunde und Baustelle';

  @override
  String get acceptCustomer => 'Kunde';

  @override
  String get acceptSite => 'Baustelle (Anschrift)';

  @override
  String get acceptTechnician => 'Techniker';

  @override
  String get acceptNotesSection => 'Vereinbarungen';

  @override
  String get acceptFollowUps => 'Vereinbarte Nacharbeiten';

  @override
  String get acceptRemarks => 'Bemerkungen';

  @override
  String get acceptRemarksHint => 'z. B. Kunde in die Bedienung eingewiesen';

  @override
  String get acceptLanguage => 'Sprache des Protokolls';

  @override
  String get acceptSignatures => 'Unterschriften';

  @override
  String get acceptSigner => 'Name des Kunden (Druckbuchstaben)';

  @override
  String get acceptSignCustomer => 'Unterschrift Kunde';

  @override
  String get acceptSignTechnician => 'Unterschrift Techniker';

  @override
  String get acceptCreate => 'Protokoll erstellen';

  @override
  String get acceptMissing =>
      'Dafür braucht es Kunde, Techniker und beide Unterschriften.';

  @override
  String get acceptEarlier => 'Frühere Protokolle';

  @override
  String get acceptIssues => 'Probleme';

  @override
  String get acceptOpenPoints => 'Offene Punkte';

  @override
  String get acceptConfirmation =>
      'Die Anlage wurde im oben beschriebenen Stand übergeben und abgenommen.';

  @override
  String get acceptRoleCustomer => 'Kunde';

  @override
  String get acceptRoleTechnician => 'Techniker';

  @override
  String acceptChecksum(String checksum) {
    return 'Prüfsumme (SHA-256): $checksum';
  }

  @override
  String get acceptSignatureNote =>
      'Einfache elektronische Unterschrift auf dem Gerät, erstellt mit KNX Monitor.';

  @override
  String get signUndo => 'Letzten Strich zurücknehmen';

  @override
  String get signClear => 'Leeren';

  @override
  String get signDone => 'Fertig';

  @override
  String get signHint => 'Mit Finger, Stift oder Maus im Feld unterschreiben.';

  @override
  String get signArea => 'Unterschriftsfeld';

  @override
  String get huntTitle => 'Fehlerjagd';

  @override
  String get huntTool =>
      'Sporadische Fehler über Tage fangen – mit der KNX-Box';

  @override
  String get huntRefresh => 'Aktualisieren';

  @override
  String get huntNeedsBox =>
      'Die Fehlerjagd läuft auf der KNX-Box oder im Home-Assistant-Add-on, rund um die Uhr. Koppel die App mit einer Box, um sie einzurichten.';

  @override
  String get huntExplain =>
      'Für Fehler, die nur manchmal auftreten: Box beim Kunden lassen, die Jagd fängt jeden Treffer eines Wächters mit zwei Minuten davor und einer danach. Am Ende siehst du, wer gesendet hat – oft ist es immer derselbe.';

  @override
  String get huntRunning => 'Läuft';

  @override
  String get huntEnded => 'Beendet';

  @override
  String huntUntil(String date) {
    return 'bis $date';
  }

  @override
  String huntWindow(String from, String to) {
    return 'nur $from–$to Uhr';
  }

  @override
  String get huntAllDay => 'rund um die Uhr';

  @override
  String huntHits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Treffer',
      one: '1 Treffer',
    );
    return '$_temp0';
  }

  @override
  String get huntStop => 'Jagd beenden';

  @override
  String get huntNew => 'Neue Jagd';

  @override
  String get huntNoWatchers =>
      'Die Jagd nutzt Wächter als Regeln. Lege zuerst einen an, z. B. „Rollladen Wohnzimmer Auf = 1“.';

  @override
  String get huntChooseRules => 'Was soll gefangen werden?';

  @override
  String get huntName => 'Name';

  @override
  String get huntNameHint => 'z. B. Rollladen fährt nachts hoch';

  @override
  String get huntDuration => 'Laufzeit';

  @override
  String huntDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage',
      one: '1 Tag',
    );
    return '$_temp0';
  }

  @override
  String get huntOnlyWindow => 'Nur in einem Zeitfenster';

  @override
  String get huntOnlyWindowExplain =>
      'z. B. nachts von 22 bis 6 Uhr (Uhrzeit der Box)';

  @override
  String get huntStart => 'Jagd starten';

  @override
  String get huntSenders => 'Wer hat gesendet?';

  @override
  String get huntResults => 'Treffer';

  @override
  String huntFrom(String sender) {
    return 'von $sender';
  }

  @override
  String get huntOpen => 'Öffnen';

  @override
  String get huntSaveFailed => 'Treffer nicht geladen. Ist die Box erreichbar?';

  @override
  String get plainThisApp => 'Diese App';

  @override
  String plainDevice(String address) {
    return 'Gerät $address';
  }

  @override
  String plainAddress(String address) {
    return 'Adresse $address';
  }

  @override
  String plainRead(String sender, String target) {
    return '$sender fragt $target ab';
  }

  @override
  String plainReport(String sender, String target, String value) {
    return '$sender meldet $target: $value';
  }

  @override
  String plainSet(String sender, String target, String value) {
    return '$sender hat $target auf $value gesetzt';
  }

  @override
  String plainAction(String sender, String target, String action) {
    return '$sender hat $target $action';
  }

  @override
  String get plainSwitchedOn => 'eingeschaltet';

  @override
  String get plainSwitchedOff => 'ausgeschaltet';

  @override
  String get plainMovedUp => 'hochgefahren';

  @override
  String get plainMovedDown => 'heruntergefahren';

  @override
  String get plainOpened => 'geöffnet';

  @override
  String get plainClosed => 'geschlossen';

  @override
  String get plainStarted => 'gestartet';

  @override
  String get plainStopped => 'gestoppt';

  @override
  String get plainEnabled => 'freigegeben';

  @override
  String get plainDisabled => 'gesperrt';

  @override
  String get plainTriggered => 'ausgelöst';

  @override
  String get plainColumnEvent => 'Was passiert';

  @override
  String get learnTitle => 'Anlage anlernen';

  @override
  String get learnTool => 'Ohne ETS-Projekt: Taster drücken, benennen, fertig';

  @override
  String get learnExplain =>
      'Kein ETS-Projekt zur Hand? Drück einen Taster oder schalte ein Licht. Die App hört mit, fängt die Gruppenadressen samt Rückmeldung und fragt, was das war. Daraus entsteht dein eigenes Projekt – Übersicht, Objekte und Diagramme funktionieren sofort. Ein später importiertes ETS-Projekt hat Vorrang; deine Namen bleiben für Adressen, die dort fehlen.';

  @override
  String get learnListening => 'Ich höre mit …';

  @override
  String get learnPressNow =>
      'Drück jetzt einen Taster oder schalte etwas – am besten nur eine Sache auf einmal.';

  @override
  String get learnDemoPress => 'Im Demo-Haus einen Taster drücken';

  @override
  String get learnMeasurements => 'Auch Messwerte fangen';

  @override
  String get learnMeasurementsHint =>
      'Aus: Temperatur & Co. stören nicht beim Taster-Drücken.';

  @override
  String learnCaught(String time) {
    return 'Gefangen um $time';
  }

  @override
  String get learnRoleCommand => 'Befehl';

  @override
  String get learnRoleFeedback => 'Rückmeldung';

  @override
  String get learnGuessed => 'geraten';

  @override
  String learnInProject(String name) {
    return 'Im Projekt: $name';
  }

  @override
  String get learnQuestion => 'Was hast du gerade gedrückt?';

  @override
  String get learnRoom => 'Raum';

  @override
  String get learnName => 'Was ist es?';

  @override
  String get learnDevice => 'Gerät (Absender)';

  @override
  String learnDeviceDefault(String room) {
    return 'Taster $room';
  }

  @override
  String get learnStatusSuffix => 'Status';

  @override
  String get learnSave => 'Anlernen';

  @override
  String get learnSkip => 'Verwerfen';

  @override
  String learnIgnore(String address) {
    return '$address nicht mehr fangen';
  }

  @override
  String learnSaved(String name) {
    return 'Angelernt: $name';
  }

  @override
  String learnLearned(int count) {
    return 'Angelernt ($count)';
  }

  @override
  String get learnNothingYet => 'Noch nichts angelernt.';

  @override
  String get learnForget => 'Vergessen';

  @override
  String get learnClearAll => 'Alles Angelernte vergessen';

  @override
  String get learnClearConfirm =>
      'Alle angelernten Namen löschen? Ein importiertes Projekt bleibt.';

  @override
  String get learnDemoNote =>
      'Demo-Haus: Angelerntes bleibt nur bis zum Verlassen der Demo.';

  @override
  String get learnRoomSuggestions =>
      'Wohnzimmer,Küche,Flur,Bad,Schlafzimmer,Kinderzimmer,Büro,Esszimmer,Garten,Keller';

  @override
  String get learnNamesSwitch =>
      'Licht,Deckenlicht,Spots,Stehlampe,Steckdose,Außenlicht';

  @override
  String get learnNamesBlind => 'Rollladen,Jalousie,Markise';

  @override
  String get learnNamesPercent => 'Dimmer,Helligkeit,Rollladen Position,Ventil';

  @override
  String get learnNamesMeasure =>
      'Temperatur,Luftfeuchte,Helligkeit,Wind,Leistung';

  @override
  String get learnNamesOther => 'Szene,Fensterkontakt,Bewegungsmelder,Dimmen';

  @override
  String get learnNoProjectCta => 'Kein ETS-Projekt? Anlage anlernen';

  @override
  String get learnSource => 'Angelernt';

  @override
  String learnCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count angelernte Adressen',
      one: '1 angelernte Adresse',
    );
    return '$_temp0';
  }

  @override
  String get helpNextSteps => 'So geht es weiter';

  @override
  String get helpNoResponseTitle => 'Das Gateway antwortet nicht';

  @override
  String helpOddPort(int port) {
    return 'Port $port ist ungewöhnlich – KNX-IP-Gateways nutzen fast immer 3671.';
  }

  @override
  String get helpCheckIp =>
      'Stimmt die IP-Adresse? „Gateways suchen“ findet Geräte im selben Netz; sonst steht sie im Router oder in der ETS.';

  @override
  String get helpSameNetwork =>
      'Ist dieses Gerät im selben Netz wie das Gateway? Gast-WLAN, VPN oder ein zweiter Router trennen die Netze.';

  @override
  String get helpBusPower =>
      'Hat das Gateway Strom und hängt am Bus? Ohne Busspannung antworten manche gar nicht.';

  @override
  String get helpNetworkTitle => 'Das Netzwerk ist nicht erreichbar';

  @override
  String get helpWifiOn =>
      'Ist WLAN bzw. LAN verbunden – mit dem Heimnetz, nicht dem Mobilfunk?';

  @override
  String get helpLocalNetworkPermission =>
      'iPhone, iPad und Mac fragen einmal nach dem „lokalen Netzwerk“. Abgelehnt? In den Einstellungen unter Datenschutz › Lokales Netzwerk erlauben.';

  @override
  String helpTcpPort(int port) {
    return 'TCP und IP Secure brauchen Port $port offen am Gateway. Kann das Gateway kein TCP, die Verbindungsart UDP wählen.';
  }

  @override
  String get helpNoTunnelTitle => 'Alle Tunnel sind belegt';

  @override
  String get helpTunnelsHeld =>
      'Ein IP-Gateway hat nur wenige Tunnel (oft 1 bis 8). Die ETS, eine Visualisierung (z. B. Home Assistant, Gira X1) oder ein Logikmodul hält sie dauerhaft.';

  @override
  String get helpCloseEts =>
      'ETS-Busmonitor bzw. ETS-Verbindung schließen und hier erneut verbinden.';

  @override
  String get helpScanShowsSlots =>
      '„Gateways suchen“ zeigt bei vielen Geräten, wie viele Tunnel gerade frei sind.';

  @override
  String get helpUseRouting =>
      'Gibt es einen IP-Router? Routing belegt keinen Tunnel (Verbindungsart im Expertenmodus).';

  @override
  String get helpTunnelAddressTitle => 'Die feste Tunneladresse geht nicht';

  @override
  String get helpNoFixedAddress =>
      'In den Verbindungseinstellungen (Expertenmodus) die feste Tunneladresse leeren – das Gateway vergibt dann eine freie.';

  @override
  String get helpUnsupportedTitle => 'Das Gerät bietet keinen passenden Tunnel';

  @override
  String get helpNotAnInterface =>
      'Manche Geräte sind reine IP-Router, Visualisierungen oder Server. Die IP-Schnittstelle der Anlage wählen.';

  @override
  String get helpSecureAuthTitle => 'IP Secure: Zugang abgelehnt';

  @override
  String get helpSecureKeyring =>
      'Am einfachsten: den Keyring (.knxkeys) aus der ETS laden – dann stimmen Benutzer, Passwort und Gerätecode von selbst.';

  @override
  String get helpSecurePasswordInEts =>
      'Von Hand: Benutzer und Passwort des Tunnels stehen in der ETS beim Gateway (Eigenschaften › IP › Tunnel).';

  @override
  String get helpSecureNotProjectPassword =>
      'Gemeint ist das Tunnel-Passwort, nicht das Projektpasswort der .knxproj.';

  @override
  String get helpSecureDeviceTitle => 'IP Secure: Gerätecode passt nicht';

  @override
  String get helpSecureDeviceCode =>
      'Der Geräte-Authentifizierungscode steht in der ETS beim Gateway (Eigenschaften › IP); mit dem Keyring kommt er mit.';

  @override
  String get helpSecureRightDevice =>
      'Antwortet wirklich die eigene Schnittstelle? Zwei Geräte mit derselben IP prüfen.';

  @override
  String get helpSecureMissingTitle => 'IP Secure braucht Zugangsdaten';

  @override
  String get helpAskElectrician =>
      'Keinen Keyring? Den bekommst du vom Elektriker, zusammen mit der Projektdatei.';

  @override
  String get helpRoutingTitle => 'Routing klappt hier nicht';

  @override
  String get helpRoutingMulticast =>
      'Routing nutzt Multicast (224.0.23.12). Viele WLAN-Router und Mesh-Systeme leiten das nicht weiter.';

  @override
  String get helpTryTunnel =>
      'Tunnel (UDP) mit der IP-Adresse des Gateways probieren.';

  @override
  String get helpNoGatewayTitle => 'Kein Gateway gefunden';

  @override
  String get helpSearchSilent =>
      'Manche Gateways antworten nicht auf die Suche. Die IP-Adresse dann direkt eintragen – sie steht im Router oder in der ETS.';

  @override
  String get helpRoutingSearch =>
      'Gefunden werden IP-Schnittstellen (Tunnel) und IP-Router (Routing) gleichermaßen.';

  @override
  String get helpTryDemo => 'Ohne Anlage ausprobieren: das Demo-Haus.';

  @override
  String helpFreeTunnels(int free, int total) {
    return '$free von $total Tunneln frei';
  }

  @override
  String get helpActionScan => 'Gateways suchen';

  @override
  String get helpActionKeyring => 'Keyring laden';

  @override
  String get helpActionProject => 'Hilfe zur Projektdatei';

  @override
  String get helpActionDemo => 'Demo-Haus öffnen';

  @override
  String get projectHelpTitle => 'Die ETS-Projektdatei';

  @override
  String get projectHelpWhatTitle => 'Was ist die .knxproj?';

  @override
  String get projectHelpWhat =>
      'Dein Elektriker hat die Anlage mit der Planungssoftware ETS eingerichtet. Die Projektdatei (Endung .knxproj) enthält alle Namen: welche Gruppenadresse das Küchenlicht schaltet, welches Gerät wo sitzt, welche Werte es gibt. Mit ihr zeigt KNX Monitor Namen statt Zahlen.';

  @override
  String get projectHelpPasswordTitle => 'Projektpasswort';

  @override
  String get projectHelpPassword =>
      'Die Datei kann mit einem Passwort geschützt sein. Die App fragt beim Import danach und braucht es nur zum Öffnen – Datei und Passwort bleiben auf deinem Gerät.';

  @override
  String get projectHelpKeyringTitle => 'Keyring (.knxkeys)';

  @override
  String get projectHelpKeyring =>
      'Nutzt deine Anlage KNX Secure (IP Secure oder Data Secure), gibt es zusätzlich den Keyring mit eigenem Passwort. Ohne ihn kann sich die App nicht mit einem sicheren Gateway verbinden oder verschlüsselte Werte nicht lesen. Ohne Secure brauchst du ihn nicht.';

  @override
  String get projectHelpGetTitle => 'Wie bekomme ich sie?';

  @override
  String get projectHelpGet =>
      'Frag den Betrieb, der die Anlage gebaut hat. Viele geben die Datei ohne Weiteres heraus, manche gegen eine kleine Gebühr. Für die Namen reicht auch ein CSV-Export der Gruppenadressen aus der ETS.';

  @override
  String get projectHelpTemplateTitle => 'Musteranfrage zum Kopieren';

  @override
  String get projectHelpTemplate =>
      'Betreff: ETS-Projektdatei für unsere KNX-Anlage\n\nHallo [Name],\n\nSie haben die KNX-Anlage in [Adresse] eingerichtet. Für Wartung und Fehlersuche möchten wir gern selbst einen Überblick behalten. Könnten Sie uns bitte die aktuelle ETS-Projektdatei (.knxproj) mit dem Projektpasswort schicken – und, falls KNX Secure genutzt wird, auch den Keyring (.knxkeys) mit seinem Passwort?\n\nEin CSV-Export der Gruppenadressen würde uns auch schon helfen. Falls dafür Kosten anfallen, sagen Sie uns bitte vorher Bescheid.\n\nVielen Dank und viele Grüße\n[Ihr Name]';

  @override
  String get projectHelpCopy => 'Text kopieren';

  @override
  String get projectHelpCopied => 'Text kopiert';

  @override
  String get projectHelpNoneTitle => 'Keine Datei zu bekommen?';

  @override
  String get projectHelpNone =>
      'Dann lern die Anlage selbst an: Taster drücken, benennen, fertig. Das geht im Monitor unter „Anlage anlernen“. Ein später importiertes Projekt hat Vorrang, deine Namen bleiben für den Rest.';

  @override
  String get projectHelpDisclaimer =>
      'Das ist keine Rechtsberatung. Ob und wie du die Datei bekommst, regelt dein Vertrag mit dem Betrieb.';

  @override
  String get projectHelpTool => 'Was ist die .knxproj, wie bekomme ich sie?';

  @override
  String get termGroupAddress => 'Gruppenadresse';

  @override
  String get termIndividualAddress => 'Physikalische Adresse';

  @override
  String get termStatus => 'Rückmeldung (Status)';

  @override
  String get termDpt => 'Datenpunkttyp (DPT)';

  @override
  String get termFlags => 'Flags';

  @override
  String get termLine => 'Linie';

  @override
  String get termTunnel => 'Tunnel';

  @override
  String get termGroupAddressText =>
      'Eine Gruppenadresse (z. B. 1/0/1) ist wie ein Kanal: Ein Taster sendet darauf „Ein“, und jeder Aktor, der auf diesem Kanal zuhört, schaltet.';

  @override
  String get termIndividualAddressText =>
      'Die physikalische Adresse (z. B. 1.1.30) ist die Hausnummer eines Geräts – Bereich, Linie, Gerät – und verrät, wer ein Telegramm gesendet hat.';

  @override
  String get termStatusText =>
      'Eine Rückmeldung ist die Antwort des Aktors: Sie sagt, ob das Licht wirklich an ist – nicht nur, dass jemand gedrückt hat.';

  @override
  String get termDptText =>
      'Der Datenpunkttyp sagt, wie die Bytes zu lesen sind: 1.001 heißt Ein/Aus, 5.001 Prozent, 9.001 Temperatur in °C.';

  @override
  String get termFlagsText =>
      'Flags legen fest, was ein Objekt eines Geräts darf: K kommunizieren, L auf Lesen antworten, S Schreiben annehmen, Ü selbst senden, A Antworten übernehmen.';

  @override
  String get termLineText =>
      'Eine Linie ist ein Strang Busleitung mit bis zu 64 Geräten; Linienkoppler verbinden mehrere Linien zu einem Bereich.';

  @override
  String get termTunnelText =>
      'Ein Tunnel ist ein Zugang übers Netzwerk zum Bus. Ein IP-Gateway hat nur wenige, und jede App, ETS oder Visualisierung belegt einen.';

  @override
  String termExampleGroup(String address, String name) {
    return 'Hier: $address heißt „$name“.';
  }

  @override
  String termExampleDevice(String address, String name, String line) {
    return 'Hier: $address ist „$name“ auf Linie $line.';
  }

  @override
  String termExampleStatus(String address, String name) {
    return 'Hier: $address „$name“ meldet den echten Zustand.';
  }

  @override
  String termExampleDpt(String name, String dpt) {
    return 'Hier: „$name“ hat den Typ $dpt.';
  }

  @override
  String termExampleFlags(String name, String device, String flags) {
    return 'Hier: „$name“ am Gerät $device hat die Flags $flags.';
  }

  @override
  String termExampleLine(String line, int count) {
    return 'Hier: Linie $line hat $count Geräte.';
  }

  @override
  String termExampleTunnel(String address, String gateway) {
    return 'Hier: $address ist ein Tunnel von „$gateway“.';
  }

  @override
  String get termExampleNone =>
      'Im eigenen Projekt gibt es dafür noch kein Beispiel – im Demo-Haus schon.';

  @override
  String get glossaryTitle => 'Begriffe';

  @override
  String get glossaryMore => 'Lektionen und Quiz';

  @override
  String get lessonsTitle => 'KNX lernen';

  @override
  String get lessonsTool => 'Begriffe, kurze Lektionen und ein Mini-Quiz';

  @override
  String get lessonsIntro =>
      'Fünf kurze Lektionen an der eigenen Anlage – oder im Demo-Haus. Tipp einen Begriff an, um ihn mit Beispiel zu sehen.';

  @override
  String lessonsTry(String text) {
    return 'Ausprobieren: $text';
  }

  @override
  String get lessonSwitchTitle => '1 · Wie KNX schaltet';

  @override
  String get lessonSwitchText =>
      'Ein Taster weiß nicht, welches Licht er schaltet. Er sendet nur „Ein“ an eine Gruppenadresse. Der Aktor, der auf dieser Adresse hört, schaltet – und meldet über eine zweite Adresse zurück, was er getan hat.';

  @override
  String get lessonSwitchTry =>
      'Im Live-Monitor zusehen, wie auf ein „Ein“ eine Rückmeldung folgt.';

  @override
  String get lessonWhoTitle => '2 · Wer ist wer';

  @override
  String get lessonWhoText =>
      'Jedes Gerät hat eine physikalische Adresse wie 1.1.30: Bereich 1, Linie 1, Gerät 30. So sieht man in jedem Telegramm, wer es gesendet hat – auch ohne Projekt.';

  @override
  String get lessonWhoTry =>
      'Ein Telegramm antippen und beim Absender nachsehen.';

  @override
  String get lessonValuesTitle => '3 · Werte lesen';

  @override
  String get lessonValuesText =>
      'Auf dem Bus stehen nur Bytes. Erst der Datenpunkttyp macht daraus „21,5 °C“ oder „50 %“. Fehlt er, rät die App aus der Länge – 1 Bit ist meist Schalten, 2 Byte meist ein Messwert.';

  @override
  String get lessonValuesTry => 'In der Übersicht die Temperaturen ansehen.';

  @override
  String get lessonReadTitle => '4 · Fragen und Antworten';

  @override
  String get lessonReadText =>
      'Die App kann eine Adresse „lesen“: Sie fragt, und das Gerät mit dem Lese-Flag antwortet mit dem aktuellen Wert. Antwortet niemand, fehlt oft nur dieses Flag.';

  @override
  String get lessonReadTry =>
      'Die Gesundheitsprüfung fragt alle Rückmeldungen ab.';

  @override
  String get lessonConnectTitle => '5 · Wie die App verbunden ist';

  @override
  String get lessonConnectText =>
      'Die App spricht übers Netzwerk mit einem IP-Gateway, das auf dem Bus sitzt. Dafür belegt sie einen Tunnel; sind alle belegt, wartet sie, bis die ETS oder eine Visualisierung einen freigibt.';

  @override
  String get lessonConnectTry => 'Oben auf den Gateway-Namen tippen.';

  @override
  String get quizTitle => 'Mini-Quiz';

  @override
  String get quizStart => 'Quiz starten';

  @override
  String get quizAgain => 'Noch einmal';

  @override
  String quizProgress(int current, int total) {
    return 'Frage $current von $total';
  }

  @override
  String get quizRight => 'Richtig!';

  @override
  String get quizWrong => 'Nicht ganz.';

  @override
  String get quizNext => 'Weiter';

  @override
  String quizResult(int score, int total) {
    return '$score von $total richtig';
  }

  @override
  String get quizDemoNote => 'Die Fragen kommen aus dem Demo-Haus.';

  @override
  String get quizWhichGroup => 'Welche davon ist eine Gruppenadresse?';

  @override
  String quizWhichLine(String address) {
    return 'Auf welcher Linie sitzt das Gerät $address?';
  }

  @override
  String quizWhichDpt(String name) {
    return 'Was für ein Wert ist „$name“?';
  }

  @override
  String get quizDptSwitch => 'Ein/Aus (1 Bit)';

  @override
  String get quizDptPercent => 'Prozent (1 Byte)';

  @override
  String get quizDptFloat => 'Messwert wie Temperatur (2 Byte)';

  @override
  String quizWhatStatus(String name) {
    return 'Was meldet „$name“?';
  }

  @override
  String get quizStatusRight => 'Was der Aktor wirklich getan hat';

  @override
  String get quizStatusWho => 'Wer den Taster gedrückt hat';

  @override
  String get quizStatusTime => 'Die Uhrzeit des Tastendrucks';

  @override
  String get quizTunnelBusy =>
      'Das Gateway antwortet, die App bekommt aber keine Verbindung. Woran liegt es am ehesten?';

  @override
  String get quizTunnelRight => 'Alle Tunnel sind belegt';

  @override
  String get quizTunnelWrongGa => 'Eine Gruppenadresse ist falsch';

  @override
  String get quizTunnelWrongDpt => 'Ein Datenpunkttyp fehlt';

  @override
  String get quizFlagRead =>
      'Eine Adresse antwortet nie auf Lesen. Welches Flag fehlt wahrscheinlich?';

  @override
  String get quizFlagReadRight => 'L (Lesen)';

  @override
  String get quizFlagTransmit => 'Ü (Übertragen)';

  @override
  String get quizFlagWrite => 'S (Schreiben)';

  @override
  String get projectHelpShort => 'Projektdatei?';

  @override
  String get lightUnknown => 'Noch nicht geprüft';

  @override
  String get lightGreen => 'Alles in Ordnung';

  @override
  String get lightYellow => 'Etwas ist auffällig';

  @override
  String get lightRed => 'Bitte nachsehen';

  @override
  String get weekTitle => 'Wochenbericht';

  @override
  String get weekNotChecked => 'Diese Woche wurde noch nicht geprüft.';

  @override
  String get weekAllGood => 'Diese Woche alles in Ordnung.';

  @override
  String weekOneIssue(String issue) {
    return 'Diese Woche alles in Ordnung bis auf eins: $issue.';
  }

  @override
  String weekIssues(int count, String issue) {
    return 'Diese Woche $count Auffälligkeiten, zuerst: $issue.';
  }

  @override
  String weekResolved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count haben sich inzwischen erledigt.',
      one: 'Eine hat sich inzwischen erledigt.',
    );
    return '$_temp0';
  }

  @override
  String weekChecks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Prüfungen',
      one: '1 Prüfung',
      zero: 'keine Prüfung',
    );
    return '$_temp0';
  }

  @override
  String weekBasisContinuous(String server, String checks) {
    return 'Grundlage: Die $server hört rund um die Uhr mit; dazu $checks diese Woche.';
  }

  @override
  String weekBasisPartial(String time, int days, String checks) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days Tagen',
      one: '1 Tag',
    );
    return 'Grundlage: Die App hat diese Woche etwa $time an $_temp0 mitgehört ($checks). Was dazwischen passiert, sieht der Bericht nicht – rund um die Uhr hört nur eine KNX-Box oder das Home-Assistant-Add-on mit.';
  }

  @override
  String weekBasisNone(String checks) {
    return 'Grundlage: $checks; die App hat diese Woche sonst kaum mitgehört.';
  }

  @override
  String weekHours(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String weekMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get weekOpen => 'Offen';

  @override
  String get weekDone => 'Erledigt diese Woche';

  @override
  String get weekCheckNow => 'Jetzt prüfen';

  @override
  String get weekOpenHealth => 'Zur Gesundheitsprüfung';

  @override
  String weekLastCheck(String when) {
    return 'Zuletzt geprüft: $when';
  }

  @override
  String get weekServerBox => 'KNX-Box';

  @override
  String get weekServerAddon => 'Home-Assistant-Add-on';

  @override
  String plainFindingSilent(String name) {
    return '„$name“ meldet sich nicht mehr';
  }

  @override
  String plainFindingNoAnswer(String name) {
    return '„$name“ antwortet nicht auf Fragen';
  }

  @override
  String plainFindingOverdue(String name) {
    return '„$name“ ist ungewöhnlich lange still';
  }

  @override
  String plainFindingImpossible(String name) {
    return '„$name“ zeigt einen unmöglichen Wert';
  }

  @override
  String plainFindingStuck(String name) {
    return '„$name“ hängt seit Stunden beim selben Wert';
  }

  @override
  String plainFindingFormat(String name) {
    return '„$name“ sendet Werte im falschen Format';
  }

  @override
  String plainFindingRepeats(String name) {
    return '„$name“ muss oft wiederholen – Leitung oder Gerät prüfen lassen';
  }

  @override
  String get learnKnown => 'im Projekt';

  @override
  String weekLastFullCheck(String when) {
    return 'Zuletzt mit Lesetest: $when – Lese-Befunde gelten von dort.';
  }

  @override
  String get haTitle => 'Home Assistant';

  @override
  String get haTool => 'Konfiguration für die KNX-Integration aus dem Projekt';

  @override
  String get haExplain =>
      'KNX Monitor leitet aus dem ETS-Projekt Leuchten, Behänge, Raumregler, Schalter und Sensoren für die KNX-Integration von Home Assistant ab. Wähle aus, was du übernehmen willst. Markierte Einträge bitte prüfen – dort war die Zuordnung nicht eindeutig.';

  @override
  String get haEmpty =>
      'Für die Konfiguration braucht es ein ETS-Projekt mit Gruppenadressen und Datenpunkttypen. Importiere es zuerst.';

  @override
  String get haWhere =>
      'In Home Assistant als knx.yaml in den Konfigurationsordner legen (neben configuration.yaml) und dort einbinden:';

  @override
  String get haWhereAddon =>
      'Im Add-on: Datei als /homeassistant/knx.yaml speichern (im File-Editor bzw. Studio Code Server unter „config“), in configuration.yaml einbinden und Home Assistant neu starten. Steht dort schon ein Abschnitt „knx:“, die Einträge dort einfügen statt einzubinden.';

  @override
  String get haEntities => 'Entitäten';

  @override
  String get haUncertain => 'Prüfen';

  @override
  String get haTypes => 'Typen';

  @override
  String get haRooms => 'Räume';

  @override
  String get haAllRooms => 'Alle';

  @override
  String get haNoRoom => 'Ohne Raum';

  @override
  String get haOnlyUncertain => 'Nur zu prüfende';

  @override
  String get haPreview => 'Vorschau der Datei';

  @override
  String get haCopy => 'YAML kopieren';

  @override
  String get haCopied => 'Konfiguration kopiert';

  @override
  String get haYamlDevices =>
      'Geräte (device): den Bereich weist du in Home Assistant unter Einstellungen › Geräte zu.';

  @override
  String get haDevices => 'Geräte';

  @override
  String get haDevicesExplain =>
      'Diese Entitäten gehören erkennbar zusammen. Übernimmst du einen Vorschlag, fasst Home Assistant sie zu einem Gerät zusammen – etwa für Dashboards nach Geräten. Ohne dein Zutun bleibt alles einzeln.';

  @override
  String get haDevicesAll => 'Alle übernehmen';

  @override
  String get haDevicesNone => 'Keine';

  @override
  String get haDeviceFromNames => 'erkannt am Namen';

  @override
  String haDeviceFromBus(String device, String address) {
    return 'sendet alles: $device ($address)';
  }

  @override
  String haDeviceOf(String device) {
    return 'Gerät: $device';
  }

  @override
  String get haShare => 'knx.yaml teilen';

  @override
  String get haPlatformLight => 'Licht';

  @override
  String get haPlatformCover => 'Behang';

  @override
  String get haPlatformClimate => 'Raumregler';

  @override
  String get haPlatformSwitch => 'Schalter';

  @override
  String get haPlatformBinarySensor => 'Meldung';

  @override
  String get haPlatformSensor => 'Messwert';

  @override
  String get haDoubtNoDpt => 'ohne Datenpunkttyp, nach Namen zugeordnet';

  @override
  String get haDoubtNoState => 'keine Rückmeldung gefunden';

  @override
  String get haDoubtLightOrSwitch =>
      'Licht oder Verbraucher? Als Schalter angelegt';

  @override
  String get haDoubtAmbiguous =>
      'mehrere Adressen passen, die erste ist eingetragen';

  @override
  String get haDoubtTargetFromCommand => 'Sollwert ohne eigene Rückmeldung';

  @override
  String get haDoubtTypeGuessed => 'nur Haupttyp des DPT bekannt';

  @override
  String haYamlHeader(String version, String project, String date) {
    return 'KNX Monitor $version – KNX-Integration für Home Assistant, Projekt „$project“, $date';
  }

  @override
  String get haYamlInclude =>
      'Einbinden in configuration.yaml mit:  knx: !include knx.yaml';

  @override
  String get haYamlSchema =>
      'Schlüssel nach home-assistant.io/integrations/knx – Einträge mit „Prüfen“ vor dem Einsatz ansehen.';

  @override
  String haYamlCheck(String reasons) {
    return 'Prüfen: $reasons';
  }

  @override
  String get haDoubtNoSwitch =>
      'nur Helligkeit, kein Schaltobjekt – Home Assistant braucht „address“, Eintrag auskommentiert';

  @override
  String get chainTitle => 'Ursachenkette';

  @override
  String get chainLocked => 'Ursachenkette zeigen';

  @override
  String chainKindScene(String name) {
    return 'Szene „$name“';
  }

  @override
  String chainKindCentral(String name) {
    return 'Zentralbefehl „$name“';
  }

  @override
  String chainFrom(String what, String sender) {
    return '$what kam von $sender';
  }

  @override
  String chainAfterCause(String sentence, String time, String cause) {
    return '$sentence – $time nach „$cause“';
  }

  @override
  String chainReactions(String time, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'meldeten $count Geräte zurück',
      one: 'meldete 1 Gerät zurück',
    );
    return '$time später $_temp0';
  }

  @override
  String chainNoReaction(String time) {
    return 'binnen $time reagierte kein Gerät';
  }

  @override
  String get chainQuiet => 'Davor und danach war es ruhig auf dem Bus.';

  @override
  String get chainThis => 'dieses';

  @override
  String get chainRoleCause => 'Auslöser';

  @override
  String get chainRoleFeedback => 'Rückmeldung';

  @override
  String get chainRoleFollowUp => 'Folge';

  @override
  String get chainRoleCoincident => 'Zeitnah, ohne Bezug';

  @override
  String get reactTitle => 'Reaktionszeiten';

  @override
  String get reactTool =>
      'Wie schnell melden Aktoren nach einem Befehl zurück?';

  @override
  String get reactExplain =>
      'Je Kanal die Zeit vom Schreibbefehl bis zur ersten Rückmeldung (bis 3 s), aus dem aktuellen Mitschnitt. Üblich sind 50–300 ms; deutlich mehr deutet auf einen ausgelasteten Bus, Koppler mit Filtern oder eine träge Logik hin.';

  @override
  String get reactEmpty =>
      'Noch keine Messung: Schalte oder fahre etwas, dessen Rückmeldung im Projekt steht.';

  @override
  String get reactNoProject =>
      'Ohne ETS-Projekt lässt sich Befehl und Rückmeldung nicht zuordnen.';

  @override
  String get reactChannels => 'Kanäle';

  @override
  String reactLine(String median, String p90, String max, int count) {
    return 'Median $median · 90 % $p90 · max. $max · $count×';
  }

  @override
  String reactMissing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Befehle ohne Rückmeldung',
      one: '1 Befehl ohne Rückmeldung',
    );
    return '$_temp0';
  }

  @override
  String get invTitle => 'Geräteinventar';

  @override
  String get invExplain =>
      'Fragt Adresse für Adresse ab, welche Geräte auf der Linie antworten, und liest Hersteller, Bestellnummer, Seriennummer, Firmware und Applikation – ohne ETS und nur lesend, mit Pausen, damit der Bus frei bleibt. Mit Projekt: Abgleich, was fehlt oder getauscht wurde. Dauert je nach Bereich einige Minuten.';

  @override
  String get invStart => 'Inventar starten';

  @override
  String get invFound => 'Gefunden';

  @override
  String get invMatch => 'Passt zum Projekt';

  @override
  String get invSerialMismatch => 'Seriennummer anders';

  @override
  String get invNotInProject => 'Nicht im Projekt';

  @override
  String get invTunnel => 'Tunneladresse';

  @override
  String get invMissing => 'Antwortet nicht';

  @override
  String get invUnknown => 'Unklar (Gateway bestätigt nicht)';

  @override
  String get invShare => 'Als Tabelle teilen';

  @override
  String get invFileName => 'KNX-Geräteinventar';

  @override
  String get secTitle => 'Sicherheits-Check';

  @override
  String get secTool => 'Secure-Nutzung und fremde Absender prüfen';

  @override
  String get secExplain =>
      'Ein ruhiger Blick auf die Sicherheit der Anlage: Wie verbindet sich die App, wie viel ist mit Data Secure geschützt, und senden Geräte, die nicht im Projekt stehen? Die Hinweise sind Empfehlungen – viele Anlagen laufen jahrelang ohne Secure, solange der Bus nicht von außen erreichbar ist.';

  @override
  String get secMetricLink => 'Verbindung';

  @override
  String get secMetricGateway => 'Gateway';

  @override
  String get secMetricProject => 'Secure im Projekt';

  @override
  String get secMetricSeen => 'Secure im Verkehr';

  @override
  String get secGatewaySecure => 'kann Secure';

  @override
  String get secGatewayPlain => 'ohne Secure';

  @override
  String get secLinkSecureTitle => 'Verbindung verschlüsselt';

  @override
  String get secLinkSecureText =>
      'Die App spricht über KNX IP Secure mit dem Gateway. Wer im Netz mitliest, sieht keine Telegramme und kann keine einschleusen.';

  @override
  String get secLinkDirectTitle => 'Direkt am Bus';

  @override
  String get secLinkDirectText =>
      'Die Box hängt mit dem KNX-HAT direkt am Bus; zwischen App und Bus liegt kein KNX-IP-Weg.';

  @override
  String get secLinkPlainCouldTitle =>
      'Gateway kann Secure – genutzt wird es nicht';

  @override
  String get secLinkRoutingCouldTitle =>
      'Routing ohne Secure, obwohl das Gerät es kann';

  @override
  String get secLinkPlainCouldText =>
      'Die Verbindung läuft unverschlüsselt. Im Heimnetz ist das üblich; wer das Netz mit Gästen, Kameras oder IoT-Geräten teilt, sollte IP Secure in der ETS aktivieren und mit dem Keyring in der App verbinden.';

  @override
  String get secLinkPlainTitle => 'Tunnel ohne Verschlüsselung';

  @override
  String get secLinkRoutingTitle => 'Routing ohne Verschlüsselung';

  @override
  String get secLinkPlainText =>
      'Ob das Gateway Secure kann, hat es (noch) nicht mitgeteilt. Unverschlüsselt ist im eigenen Netz in Ordnung, solange Port 3671 nicht aus dem Internet erreichbar ist.';

  @override
  String get secLinkPlainNoSecureText =>
      'Das Gateway bietet kein IP Secure an. Halte es in einem Netz, in dem nur vertrauenswürdige Geräte hängen, und gib Port 3671 nie ins Internet frei.';

  @override
  String get secLinkUnknownTitle => 'Verbindungsweg nicht bekannt';

  @override
  String get secLinkUnknownText =>
      'Die App hängt an Home Assistant; wie dort mit dem Bus verbunden wird, sieht sie nicht.';

  @override
  String get secDataNoKeyringTitle => 'Kein Keyring geladen';

  @override
  String get secDataNoKeyringText =>
      'Ohne Keyring lässt sich nicht sagen, welche Gruppenadressen mit Data Secure geschützt sind. Bisher kam kein gesichertes Telegramm vorbei.';

  @override
  String secDataNoKeyringSeen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Telegramme waren mit Data Secure gesichert',
      one: '1 Telegramm war mit Data Secure gesichert',
    );
    return '$_temp0 – lade den Keyring aus der ETS, um sie zu lesen.';
  }

  @override
  String get secDataNoneTitle => 'Keine Data-Secure-Adressen';

  @override
  String get secDataNoneText =>
      'Der Keyring enthält keine Schlüssel für Gruppenadressen. Für Türöffner, Alarm oder Zutritt lohnt Data Secure – für Licht und Jalousien ist es selten nötig.';

  @override
  String get secDataTitle => 'Data Secure in Gebrauch';

  @override
  String secDataText(int project, int groups, int seen, int seenAll) {
    return '$project von $groups Gruppenadressen im Projekt sind gesichert; im Verkehr waren es bisher $seen von $seenAll.';
  }

  @override
  String get secWithoutKeyTitle => 'Gesicherte Telegramme ohne Schlüssel';

  @override
  String secWithoutKeyText(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Telegramme',
      one: '1 Telegramm',
    );
    return '$_temp0 ließen sich nicht entschlüsseln. Meist ist der Keyring älter als das Projekt – neu aus der ETS exportieren.';
  }

  @override
  String get secRejectedTitle => 'Ungültige gesicherte Telegramme';

  @override
  String secRejectedText(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Telegramme',
      one: '1 Telegramm',
    );
    return '$_temp0 hatten eine falsche Prüfsumme oder einen alten Zähler. Einzelne kommen nach einem Neustart vor; häufen sie sich, lohnt ein Blick, wer sie sendet.';
  }

  @override
  String get secForeignNoProjectTitle => 'Absender nicht prüfbar';

  @override
  String get secForeignNoProjectText =>
      'Für den Abgleich der Absender braucht es ein .knxproj mit Topologie.';

  @override
  String get secForeignNoneTitle => 'Alle Absender stehen im Projekt';

  @override
  String get secForeignNoneText =>
      'Jedes Telegramm im Mitschnitt kam von einem Gerät, das die ETS kennt.';

  @override
  String secForeignTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Absender nicht im Projekt',
      one: '1 Absender nicht im Projekt',
    );
    return '$_temp0';
  }

  @override
  String get secForeignText =>
      'Meist harmlos: Visualisierungen, Logikmodule oder Tunnel anderer Apps. Unbekannte Adressen lassen sich in der Diagnose prüfen; ein Gerät, das niemand kennt, sollte man finden.';

  @override
  String get secForeignList => 'Fremde Absender';

  @override
  String secForeignRow(int count, String groups) {
    return '$count× · $groups';
  }

  @override
  String get forumTitle => 'Für das Forum';

  @override
  String forumExplain(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Telegramme',
      one: '1 Telegramm',
    );
    return '$_temp0 als Text zum Einfügen ins KNX-User-Forum. IP-Adressen, Hostnamen, Seriennummern, Passwörter und Schlüssel sind nie dabei.';
  }

  @override
  String get forumPseudonymize => 'Namen ersetzen';

  @override
  String get forumPseudonymizeHint =>
      'Gruppenadressen heißen „GA 1“, Geräte tragen nur den Produktnamen.';

  @override
  String get forumCopy => 'In die Zwischenablage';

  @override
  String get forumCopied => 'Text fürs Forum kopiert';

  @override
  String get forumPreview => 'Vorschau';

  @override
  String get forumHeading => 'Mitschnitt aus KNX Monitor';

  @override
  String get forumTelegrams => 'Telegramme';

  @override
  String get forumGroups => 'Gruppenadressen';

  @override
  String get forumDevices => 'Geräte';

  @override
  String get forumColumnGroup => 'GA';

  @override
  String get forumOwn => 'diese App';

  @override
  String get forumNoDpt => 'DPT ?';

  @override
  String forumPseudoGroup(int n) {
    return 'GA $n';
  }

  @override
  String forumPseudoDevice(int n) {
    return 'Gerät $n';
  }

  @override
  String forumMetaApp(String version) {
    return 'KNX Monitor $version';
  }

  @override
  String forumMetaConnection(String kind) {
    return 'Verbindung: $kind';
  }

  @override
  String forumMetaRange(int count, String date, String from, String to) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Telegramme',
      one: '1 Telegramm',
    );
    return '$_temp0 am $date, $from–$to';
  }

  @override
  String forumMetaShortened(int count) {
    return 'gekürzt auf die ersten $count';
  }

  @override
  String get etsTasks => 'Aufgaben für die ETS';

  @override
  String get etsTasksHint =>
      'Je Gerät eine Seite mit Zeichnung, Kanälen und Aufgaben zum Abhaken; geänderte Datentypen als ETS-Import.';

  @override
  String get etsTasksNone =>
      'Keine Aufgaben: Das Projekt passt zu allen Prüfungen.';

  @override
  String get etsTasksBuilding => 'Aufgaben werden erstellt …';

  @override
  String etsTasksDrawing(String device) {
    return 'Zeichne $device …';
  }

  @override
  String get etsHowTo =>
      'Je Gerät eine Seite: die Zeichnung mit den Kanälen, die Aufgaben zum Abhaken und die Kanalzuordnung aus dem Projekt. Danach das Projekt neu in KNX Monitor importieren; der Projekt-Abgleich zeigt, was erledigt ist.';

  @override
  String get etsSummaryDevices => 'Geräte';

  @override
  String get etsSummaryTasks => 'Aufgaben';

  @override
  String get etsSummaryHints => 'Hinweise';

  @override
  String get etsOverview => 'Übersicht';

  @override
  String get etsInProject => 'Im Projekt';

  @override
  String get etsNew => 'Neu';

  @override
  String get etsImportNote =>
      'Liegt als Datei für den Gruppenadress-Import der ETS bei (Gruppenadressen › Importieren): Datentypen, Namen und neue Adressen. Vorschau: erst an einer Kopie des Projekts testen.';

  @override
  String etsDevice(String address) {
    return 'Gerät $address';
  }

  @override
  String get etsTasksOnPage => 'Aufgaben';

  @override
  String get etsChannels => 'Kanalzuordnung';

  @override
  String get etsColumnChannel => 'Kanal';

  @override
  String get etsColumnObject => 'Objekt';

  @override
  String get etsColumnGroup => 'Gruppenadresse';

  @override
  String get etsColumnFlags => 'Flags';

  @override
  String etsObject(int number) {
    return 'Objekt $number';
  }

  @override
  String etsAlsoSends(String devices) {
    return 'sendet auch: $devices';
  }

  @override
  String get etsNoChannels => 'Keine verknüpften Objekte';

  @override
  String etsTodoDpt(String dpt) {
    return 'Datentyp der Gruppenadresse auf $dpt setzen.';
  }

  @override
  String get etsTodoStatusNoTransmit =>
      'Ü-Flag am Objekt setzen, das den Status liefert (meist der Aktorkanal).';

  @override
  String get etsTodoReadNoReadFlag =>
      'L-Flag am Objekt setzen, das den Status liefert.';

  @override
  String get etsTodoNoComm =>
      'K-Flag setzen oder die Gruppenadresse vom Objekt lösen.';

  @override
  String get etsTodoMultipleSenders =>
      'Prüfen, ob gewollt; sonst nur ein Objekt senden lassen oder eine eigene Adresse vergeben.';

  @override
  String get etsTodoNoLinks =>
      'Gruppenadressen verknüpfen oder das Gerät aus dem Projekt nehmen.';

  @override
  String get etsImportFile => 'Gruppenadressen ETS-Import (Vorschau)';

  @override
  String get etsHint => 'Hinweis';

  @override
  String get etsTitleNoComm => 'Objekt ohne K-Flag';

  @override
  String get etsTitleNoLinks => 'Gerät ohne Verknüpfung';

  @override
  String etsTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Aufgaben',
      one: '1 Aufgabe',
    );
    return '$_temp0';
  }

  @override
  String etsHintCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Hinweise',
      one: '1 Hinweis',
    );
    return '$_temp0';
  }

  @override
  String get etsSummaryImport => 'Für den Import';

  @override
  String get etsImportSection => 'Gruppenadress-Import';

  @override
  String get etsGroupsSection => 'Gruppenadressen';

  @override
  String get etsProjectSection => 'Projekt';

  @override
  String get etsTitleLearnedName => 'Name aus dem Anlernen';

  @override
  String get etsTitleLearnedNew => 'Neue Adresse aus dem Anlernen';

  @override
  String get etsTitleNoName => 'Ohne Namen';

  @override
  String get etsTitleNoDpt => 'Ohne Datentyp';

  @override
  String get etsTitleNotInProject => 'Am Bus, nicht im Projekt';

  @override
  String get etsTitleSerial => 'Seriennummer weicht ab';

  @override
  String get etsTitleMissing => 'Antwortet nicht';

  @override
  String etsTodoLearnedName(String name) {
    return 'Namen „$name“ übernehmen – erledigt der Gruppenadress-Import.';
  }

  @override
  String etsTodoLearnedNew(String name) {
    return 'Adresse „$name“ anlegen – erledigt der Gruppenadress-Import; danach mit den Objekten verknüpfen.';
  }

  @override
  String get etsTodoNoName =>
      'Sprechenden Namen vergeben: Etage, Raum, Objekt, Funktion.';

  @override
  String get etsTodoNoDpt =>
      'Datentyp passend zum verknüpften Objekt setzen – oder in der App festlegen, dann geht er mit dem Import.';

  @override
  String get etsTodoWithoutSender =>
      'Sender verknüpfen oder Visualisierung, Logik bzw. Panel als Platzhalter-Gerät mit dieser Adresse anlegen.';

  @override
  String get etsTodoWithoutReceiver =>
      'Empfangendes Objekt (K- und S-Flag) verknüpfen oder die Adresse löschen, wenn sie nicht gebraucht wird.';

  @override
  String get etsTodoMainGroup1415 =>
      'Für linienübergreifende Adressen in Hauptgruppe 0–13 verschieben oder die Filtertabellen der Koppler prüfen.';

  @override
  String get etsTodoMultipleReadAnswers =>
      'L-Flag nur an dem Objekt lassen, das den Zustand führt, an den übrigen entfernen.';

  @override
  String get etsTodoNotInProject =>
      'Gerät im Projekt anlegen (Topologie, physikalische Adresse) oder klären, woher es stammt.';

  @override
  String etsTodoSerial(String serial) {
    return 'Gerät wurde vermutlich getauscht: Seriennummer $serial im Projekt eintragen und Applikation neu laden.';
  }

  @override
  String get etsTodoMissing =>
      'Prüfen, ob das Gerät angeschlossen und programmiert ist – beim Inventar hat es nicht geantwortet.';

  @override
  String etsTodoCrowdedLine(String line, int count) {
    return 'Linie $line hat $count Geräte: Reserve einplanen, bei Erweiterung neue Linie oder Linienverstärker.';
  }

  @override
  String get etsTitleDpt => 'Datentyp';

  @override
  String get planOneInstallationTitle => 'Eine Anlage';

  @override
  String get planOneInstallationHere =>
      'Hier gibt es eine Anlage. Mehrere Anlagen nebeneinander gehen in der App für iPhone, iPad, Android und Mac (Plus oder Pro).';

  @override
  String get huntToolAddon => 'Sporadische Fehler über Tage fangen – im Add-on';

  @override
  String get huntExplainAddon =>
      'Für Fehler, die nur manchmal auftreten: Das Add-on läuft rund um die Uhr, die Jagd fängt jeden Treffer eines Wächters mit zwei Minuten davor und einer danach. Am Ende siehst du, wer gesendet hat – oft ist es immer derselbe.';

  @override
  String get huntOnlyWindowExplainAddon =>
      'z. B. nachts von 22 bis 6 Uhr (Uhrzeit von Home Assistant)';

  @override
  String get secLinkDemoTitle => 'Demo-Haus';

  @override
  String get secLinkDemoText =>
      'Im Demo-Haus gibt es keinen echten Bus. An deiner Anlage prüft der Check hier, wie die App mit dem Gateway verbunden ist – verschlüsselt oder nicht.';

  @override
  String get addonConfigLost =>
      'Einstellungen der Daueraufzeichnung waren beschädigt – bitte einmal neu verbinden.';

  @override
  String get learnRoleAlsoSeen => 'Auch gesehen';

  @override
  String get checkDemoNoFlags =>
      'Das Demo-Haus hat keine Flags – an deiner Anlage liest der Abgleich sie aus dem ETS-Projekt';

  @override
  String get learnWarmUp =>
      'Höre kurz mit, damit ich deinen Bus kenne … Bitte noch nichts drücken.';

  @override
  String get invPresent => 'Gefunden';

  @override
  String invManufacturerId(String id) {
    return 'Hersteller $id';
  }

  @override
  String get ackTestTitle => 'Gehört?';

  @override
  String get ackTestText =>
      'Die App hat eben den Quittungston gespielt. Gehört? Dann kann’s losgehen.';

  @override
  String get ackTestNotHeard =>
      'Nichts gehört? Lautstärke hochdrehen, Stummmodus ausschalten (iPhone: Schalter oder Kontrollzentrum) und Bluetooth-Kopfhörer prüfen. Dann noch einmal.';

  @override
  String get ackTestNo => 'Nicht gehört';

  @override
  String get ackTestAgain => 'Noch einmal';

  @override
  String get ackTestYes => 'Gehört, los';

  @override
  String get companyTitle => 'Firma';

  @override
  String get companyFeature => 'Firmenbriefkopf auf allen PDFs';

  @override
  String get companyTool => 'Logo und Adresse für den Briefkopf der PDFs';

  @override
  String get companyExplain =>
      'Diese Angaben stehen als Briefkopf auf allen PDFs. Sie gelten für alle Anlagen und bleiben auf diesem Gerät.';

  @override
  String get companyPreview => 'Vorschau des Briefkopfs';

  @override
  String get companyPreviewEmpty => 'Ihr Firmenname';

  @override
  String get companyLogo => 'Logo';

  @override
  String get companyLogoPick => 'Logo wählen';

  @override
  String get companyLogoReplace => 'Logo ersetzen';

  @override
  String get companyLogoHint =>
      'PNG, JPEG oder SVG. Das Bild wird automatisch verkleinert.';

  @override
  String get companyLogoFailed =>
      'Dieses Bild lässt sich nicht lesen. Bitte ein PNG oder JPEG versuchen.';

  @override
  String get companyDetails => 'Angaben';

  @override
  String get companyName => 'Firmenname';

  @override
  String get companyAddress => 'Anschrift';

  @override
  String get companyPhone => 'Telefon';

  @override
  String get companyEmail => 'E-Mail';

  @override
  String get companyWebsite => 'Website';

  @override
  String get companyVatId => 'USt-IdNr. (optional)';

  @override
  String get companyRegistration => 'Eintragung (optional)';

  @override
  String get companyTechnician => 'Techniker auf diesem Gerät';

  @override
  String get companySaved => 'Gespeichert.';

  @override
  String pdfTechnicianLine(String name) {
    return 'Techniker: $name';
  }

  @override
  String get menuGroupDocuments => 'Dokumente & Kunden';

  @override
  String get srTitle => 'Servicebericht';

  @override
  String get srTool =>
      'Bericht für den Kunden aus Aufnahme, Kommentaren und Gesundheit';

  @override
  String get srFeature => 'Servicebericht für den Kunden';

  @override
  String get srExplain =>
      'Schreibe in einfachen Worten, was los war und was du getan hast. Aufnahme und Gesundheitsprüfung kommen als Beleg dazu. Nach dem Erstellen bleibt der Bericht unverändert gespeichert.';

  @override
  String get srPdfTitle => 'Servicebericht';

  @override
  String get srVisitSection => 'Der Besuch';

  @override
  String get srOccasion => 'Anlass des Besuchs';

  @override
  String get srOccasionHint => 'z. B. Licht im Flur ging nachts von selbst an';

  @override
  String get srObserved => 'Was wir beobachtet haben';

  @override
  String get srObservedHint => 'Was war zu sehen, wann ist es passiert?';

  @override
  String get srDone => 'Was wir getan haben';

  @override
  String get srDoneHint => 'z. B. Bewegungsmelder neu eingestellt';

  @override
  String get srRecommendation => 'Unsere Empfehlung';

  @override
  String get srRecommendationHint => 'Was sollte als Nächstes passieren?';

  @override
  String get srEvidenceSection => 'Belege';

  @override
  String get srRecording => 'Aufnahme';

  @override
  String get srRecordingNone => 'Keine Aufnahme';

  @override
  String get srUseHealth => 'Letzte Gesundheitsprüfung mitnehmen';

  @override
  String get srSignatureOptional => 'Unterschrift (optional)';

  @override
  String get srSigned => 'Unterschrieben – ändern';

  @override
  String get srCreate => 'Bericht erstellen und teilen';

  @override
  String get srEarlier => 'Frühere Berichte';

  @override
  String get srResultGood => 'Ergebnis: Es gibt keine offenen Auffälligkeiten.';

  @override
  String srResultAttention(int count) {
    return 'Ergebnis: $count Punkte sollten Sie im Blick behalten (siehe unten).';
  }

  @override
  String get srMeasurement => 'Unsere Messung';

  @override
  String srMeasurementText(String start, int minutes, int count) {
    return 'Ab $start haben wir $minutes Minuten lang mitgeschrieben, was die Geräte Ihrer Anlage untereinander senden. Dabei waren es $count Nachrichten.';
  }

  @override
  String get srComments => 'Notizen zum Besuch';

  @override
  String get srFindings => 'Was die Auswertung zeigt';

  @override
  String srHealth(String date) {
    return 'Gesundheitsprüfung vom $date';
  }

  @override
  String get srLevelFix => 'Beheben';

  @override
  String get srLevelWatch => 'Beobachten';

  @override
  String get srLevelInfo => 'Zur Info';

  @override
  String get srConfirmation =>
      'Der Kunde hat den Bericht erhalten und den Besuch bestätigt.';

  @override
  String get customerTitle => 'Kundenakte';

  @override
  String get customerTool => 'Anlagen, Kunden, Wartung und Besuche';

  @override
  String get customerFeature => 'Anlagen als Kundenakte mit Besuchsverlauf';

  @override
  String get customerSearch => 'Kunde, Anschrift, Auftrag suchen';

  @override
  String get customerSortName => 'Name';

  @override
  String get customerSortVisit => 'Letzter Besuch';

  @override
  String get customerSortMaintenance => 'Wartung';

  @override
  String get customerNone => 'Keine passende Anlage.';

  @override
  String customerLastVisit(String date) {
    return 'Zuletzt $date';
  }

  @override
  String get customerDue => 'Wartung fällig';

  @override
  String customerNextMaintenance(String date) {
    return 'Nächste Wartung: $date';
  }

  @override
  String get customerLinkFailed =>
      'Das ließ sich auf diesem Gerät nicht öffnen.';

  @override
  String get customerEdit => 'Bearbeiten';

  @override
  String get customerEmpty =>
      'Noch keine Kundendaten. Sie bleiben nur auf diesem Gerät und sind nie Teil eines Diagnosepakets.';

  @override
  String get customerPrivate =>
      'Kundendaten bleiben auf diesem Gerät und sind nie Teil eines Diagnosepakets oder Übergabepakets.';

  @override
  String get customerName => 'Kunde';

  @override
  String get customerAddress => 'Anschrift der Anlage';

  @override
  String get customerContact => 'Ansprechpartner';

  @override
  String get customerPhone => 'Telefon';

  @override
  String get customerEmail => 'E-Mail';

  @override
  String get customerOrder => 'Kunden- oder Auftragsnummer';

  @override
  String get customerNotes => 'Notizen';

  @override
  String get customerInterval => 'Wartungsintervall in Monaten';

  @override
  String get customerCall => 'Anrufen';

  @override
  String get customerMail => 'E-Mail schreiben';

  @override
  String get customerMap => 'In Karten öffnen';

  @override
  String get customerSwitch => 'Zu dieser Anlage wechseln';

  @override
  String get customerHistory => 'Besuchsverlauf';

  @override
  String get visitAdd => 'Eintrag';

  @override
  String get visitNone => 'Noch keine Einträge.';

  @override
  String get visitConnection => 'Verbunden';

  @override
  String get visitCommissioning => 'Inbetriebnahme';

  @override
  String get visitAcceptance => 'Abnahmeprotokoll';

  @override
  String get visitServiceReport => 'Servicebericht';

  @override
  String get visitFaultReport => 'Störungsmeldung';

  @override
  String get visitHandover => 'Übergabepaket erstellt';

  @override
  String get visitManual => 'Eigener Eintrag';

  @override
  String visitMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get visitDuration => 'Dauer in Minuten';

  @override
  String get visitText => 'Text';

  @override
  String get installationCustomers => 'Kundenakte';

  @override
  String get handoverTitle => 'Übergabepaket';

  @override
  String get handoverTool => 'Anlage an die App des Kunden übergeben';

  @override
  String get handoverFeature => 'Übergabepaket für die App des Kunden';

  @override
  String get handoverReceiveFeature => 'Übergabepaket vom Elektriker öffnen';

  @override
  String get handoverExplain =>
      'Eine Datei für die App deines Kunden: Namen der Gruppenadressen und Geräte, Struktur und Gateway. Keine Cloud, kein Konto: Sie geht per Mail, AirDrop oder USB-Stick. Kundendaten bleiben hier.';

  @override
  String get handoverNeedsCompany =>
      'Trage zuerst deine Firma ein. Der Kunde sieht sie als „eingerichtet von“.';

  @override
  String get handoverContents => 'Inhalt';

  @override
  String get handoverNoGateway => 'kein Gateway gespeichert';

  @override
  String get handoverNoProject => 'Diese Anlage hat noch kein Projekt.';

  @override
  String get handoverIncludeKeys => 'KNX-Secure-Schlüssel mitgeben';

  @override
  String get handoverIncludeKeysHint =>
      'Nur wenn der Kunde sie braucht. Die Datei ist dann immer passwortgeschützt.';

  @override
  String get handoverProtect => 'Mit Passwort schützen';

  @override
  String get handoverPassword => 'Passwort';

  @override
  String get handoverQrLabel => 'QR-Code mit dem Passwort';

  @override
  String get handoverCopyPassword => 'Kopieren';

  @override
  String get handoverNewPassword => 'Neues Passwort';

  @override
  String get handoverPasswordHint =>
      'Gib das Passwort getrennt von der Datei weiter, am besten scannt der Kunde den QR-Code vor Ort. Es wird nirgends gespeichert.';

  @override
  String get handoverCreate => 'Paket erstellen und teilen';

  @override
  String handoverFilePrefix(String name) {
    return 'Übergabe $name';
  }

  @override
  String get handoverScanTitle => 'QR-Code scannen';

  @override
  String get handoverWrongPassword =>
      'Das Passwort stimmt nicht oder die Datei wurde verändert.';

  @override
  String get handoverOpen => 'Öffnen';

  @override
  String get handoverOpening => 'Paket wird geöffnet …';

  @override
  String get handoverUnknownCompany => 'Elektrofachbetrieb';

  @override
  String handoverImportTitle(String company) {
    return 'Anlage von $company einrichten?';
  }

  @override
  String get handoverImportKeys => 'Enthält KNX-Secure-Schlüssel.';

  @override
  String get handoverImportReplaces => 'Das bisherige Projekt wird ersetzt.';

  @override
  String handoverImported(String name, String company) {
    return '$name ist eingerichtet, von $company.';
  }

  @override
  String handoverSetUpBy(String company) {
    return 'Eingerichtet von $company';
  }

  @override
  String get packageCorrupt =>
      'Diese Datei lässt sich nicht lesen. Sie ist beschädigt oder kein Paket von KNX Monitor.';

  @override
  String get packageNewer =>
      'Diese Datei stammt aus einer neueren Version. Bitte die App aktualisieren.';

  @override
  String get packageTooLarge =>
      'Diese Datei ist zu groß, um sie direkt zu öffnen. Bitte in der App über „Paket oder Meldung öffnen“ wählen.';

  @override
  String get packageUnreadable =>
      'Diese Datei ließ sich nicht lesen. Bitte noch einmal öffnen oder in der App über „Paket oder Meldung öffnen“ wählen.';

  @override
  String get packageOpenMenu => 'Paket oder Meldung öffnen';

  @override
  String faultReportTo(String company) {
    return 'An $company melden';
  }

  @override
  String get faultReportTool =>
      'Störung mit echten Daten an deinen Elektriker melden';

  @override
  String faultExplain(String company) {
    return 'Beschreibe kurz, was passiert ist. Daraus entsteht eine Datei für $company, mit der Aufnahme, deinen Markierungen und Screenshots.';
  }

  @override
  String get faultProblem => 'Was ist passiert?';

  @override
  String get faultProblemHint => 'z. B. Licht im Bad geht nicht mehr aus';

  @override
  String get faultSend => 'Datei erstellen und schicken';

  @override
  String faultSentHint(String company) {
    return 'Schicke die Datei per Mail oder Nachricht an $company.';
  }

  @override
  String get faultPrivacy =>
      'Die Datei enthält keine Schlüssel und keine Passwörter. Sie enthält die Telegramme dieser Sitzung, deine Kommentare und das Protokoll der App, auf Wunsch auch Namen und Screenshots. Sie geht nur an die Firma, der du sie schickst: Es gibt keine Cloud und kein Konto.';

  @override
  String get faultFilePrefix => 'Stoerungsmeldung';

  @override
  String faultPickInstallation(String name) {
    return 'Zu welcher Anlage gehört die Meldung von „$name“?';
  }

  @override
  String faultReceived(String name) {
    return 'Meldung liegt jetzt im Verlauf von $name.';
  }

  @override
  String get manualTitle => 'Bewohner-Handbuch';

  @override
  String get manualTool =>
      'Heft für die Bewohner aus Projekt und angelernten Namen';

  @override
  String get manualFeature => 'Bewohner-Handbuch als PDF';

  @override
  String get manualExplain =>
      'Ein Heft für die Menschen, die in der Anlage wohnen: nach Räumen, ohne Adressen und Fachbegriffe. Rückmeldungen und Technisches bleiben draußen.';

  @override
  String manualSummary(int rooms, int count) {
    return '$rooms Bereiche, $count Funktionen';
  }

  @override
  String get manualNote => 'Eigene Hinweise';

  @override
  String get manualNoteHint =>
      'z. B. Hauptschalter und Sicherungen sind im Keller';

  @override
  String get manualCreate => 'Handbuch erstellen und teilen';

  @override
  String get manualEmpty =>
      'Für ein Handbuch braucht es ein Projekt oder angelernte Namen.';

  @override
  String get manualPdfTitle => 'Handbuch für Ihre Anlage';

  @override
  String get manualIntro =>
      'In diesem Heft steht, was Ihre Elektroanlage in jedem Raum kann. Die Taster an der Wand funktionieren wie gewohnt; alles andere läuft im Hintergrund.';

  @override
  String get manualOther => 'Weitere Funktionen';

  @override
  String get manualNoteLabel => 'Hinweise von uns';

  @override
  String get manualTroubleTitle => 'Wenn etwas nicht funktioniert';

  @override
  String get manualTrouble1 => 'Taster noch einmal drücken und kurz warten.';

  @override
  String get manualTrouble2 =>
      'Prüfen, ob auch andere Dinge im Raum betroffen sind, und das notieren.';

  @override
  String get manualTrouble3 =>
      'Sicherungen nicht selbst tauschen, sondern uns anrufen.';

  @override
  String get manualContact => 'So erreichen Sie uns';

  @override
  String get manualKindOnOff => 'Ein- und ausschalten';

  @override
  String get manualKindDim => 'Heller und dunkler';

  @override
  String get manualKindPercent => 'Stufenlos einstellen';

  @override
  String get manualKindBlinds => 'Auf und ab fahren';

  @override
  String get manualKindOpenClose => 'Öffnen und schließen';

  @override
  String get manualKindScene => 'Lichtstimmung abrufen';

  @override
  String get manualKindTemperature => 'Zeigt die Raumtemperatur';

  @override
  String get manualKindSetpoint => 'Wunschtemperatur einstellen';

  @override
  String get manualKindMeasure => 'Zeigt einen Messwert';

  @override
  String get manualKindOther => 'Funktion der Anlage';

  @override
  String get bizStandardTitle => 'Betriebsstandard';

  @override
  String get bizAssistantTitle => 'GA-Assistent';

  @override
  String get bizCheckTitle => 'Prüfung gegen den Standard';

  @override
  String get bizNotesTitle => 'Anlagenhinweise';

  @override
  String get etsTitleStandard => 'Abweichung vom Standard';

  @override
  String get bizSendCancelled => 'Nicht gesendet.';

  @override
  String get bizSurveyTitle => 'Bestandsaufnahme';

  @override
  String get galleryTitle => 'Galerie der Vorlagen';

  @override
  String get galleryIntro =>
      'Fertige Diagramm-Vorlagen mit Rollen statt Adressen. Sie gehören zur App, nichts wird aus dem Netz geladen. Übernehmen legt die Vorlage in deine Bibliothek und wendet sie auf das Projekt dieser Anlage an.';

  @override
  String get gallerySearch => 'Suchen';

  @override
  String get galleryNoMatch => 'Keine Vorlage passt zur Suche.';

  @override
  String galleryFits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Passt $count-mal auf dieses Projekt',
      one: 'Passt einmal auf dieses Projekt',
    );
    return '$_temp0';
  }

  @override
  String get galleryFitsNothing =>
      'Findet in diesem Projekt noch keine passenden Adressen';

  @override
  String galleryAdopted(String name) {
    return '„$name“ liegt jetzt in deiner Bibliothek';
  }

  @override
  String get gallerySubmit => 'Eigene Vorlage einreichen';

  @override
  String get gallerySubmitHint =>
      'Wähle ein Diagramm. Die App erstellt daraus eine Datei mit Namen und Rollen, ohne Adressen und Räume. Teile sie selbst, zum Beispiel per Mail an support@knx-monitor.de; hochgeladen wird nichts.';

  @override
  String get gallerySubmitNone =>
      'Noch kein gespeichertes Diagramm mit erkennbaren Rollen.';

  @override
  String get siteDocsTitle => 'Fotodoku und Etiketten';

  @override
  String get siteDocsTool => 'Fotos des Verteilers, Etiketten mit QR-Code';

  @override
  String get siteDocsPhotos => 'Fotos';

  @override
  String get siteDocsPhotosHint =>
      'Fotos bleiben auf diesem Gerät im Ordner der Anlage und gehen beim Löschen der Anlage mit. Sie stehen nicht im Diagnose- und nicht im Übergabepaket; in einen Servicebericht kommen sie nur, wenn du sie dort auswählst. Ort und Gerätedaten werden aus dem Bild entfernt.';

  @override
  String get siteDocsTakePhoto => 'Foto aufnehmen';

  @override
  String get siteDocsPickPhoto => 'Bild wählen';

  @override
  String get siteDocsCaption => 'Beschriftung';

  @override
  String get siteDocsCaptionHint => 'z. B. Verteiler Keller, Reihe 2';

  @override
  String get siteDocsNoCaption => 'Ohne Beschriftung';

  @override
  String get siteDocsDelete => 'Foto löschen';

  @override
  String get siteDocsQuota =>
      'Kein Platz mehr für Fotos dieser Anlage. Lösche zuerst ältere.';

  @override
  String get siteDocsUnreadable => 'Das Bild ließ sich nicht lesen.';

  @override
  String get siteDocsLabels => 'Etiketten';

  @override
  String get siteDocsLabelsHint =>
      'Bogen A4 mit 70 × 37 mm: physikalische Adresse, Funktion, Einbauort und QR-Code. Der Code öffnet das Gerät nur in dieser App und enthält keine Web-Adresse und keine Zugangsdaten.';

  @override
  String get siteDocsLabelsNoProject =>
      'Etiketten brauchen Geräte aus einem ETS-Projekt.';

  @override
  String get siteDocsLabelsCreate => 'Etiketten erstellen';

  @override
  String get siteDocsLabelsPdf => 'Etiketten';

  @override
  String siteDocsLabelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Etiketten erstellen',
      one: '1 Etikett erstellen',
    );
    return '$_temp0';
  }

  @override
  String get siteDocsLabelsAll => 'Alle wählen';

  @override
  String get siteDocsLabelsNone => 'Keine wählen';

  @override
  String get siteDocsScan => 'Etikett scannen';

  @override
  String siteDocsScanOther(String device, String name) {
    return 'Gerät $device gehört zur Anlage „$name“. Wechsle zuerst dorthin.';
  }

  @override
  String siteDocsScanUnknown(String device) {
    return 'Gerät $device gehört zu einer Anlage, die nicht auf diesem Gerät liegt.';
  }

  @override
  String get siteDocsScanForeign => 'Das ist kein Etikett von KNX Monitor.';

  @override
  String get srPhotos => 'Fotos';

  @override
  String get srPhotosHint => 'Nur die angehakten Fotos kommen in den Bericht.';

  @override
  String get loadTitle => 'Strom und Last';

  @override
  String get loadTool =>
      'Stromwerte und Leistung je Kanal, Maximum, Abweichungen';

  @override
  String get loadExplain =>
      'Werte aus Aktoren mit Strommessung, nur aus Telegrammen, die ohnehin auf dem Bus laufen. Die App fragt nichts ab; wie aktuell ein Wert ist, hängt davon ab, wie der Aktor sendet.';

  @override
  String get loadNone => 'Keine Strom- oder Leistungswerte erkannt';

  @override
  String get loadNoneDetail =>
      'Erkannt werden Adressen mit Datentyp 7.012, 9.021, 14.019, 9.024 oder 14.056 und Zahlenadressen mit Namen wie „Strom“ oder „Leistung“.';

  @override
  String get loadNoValues => 'Noch kein Messwert mitgehört';

  @override
  String loadPeak(String value, String when, int count) {
    return 'Maximum $value am $when · $count Messwerte';
  }

  @override
  String loadRulesExplain(int samples, int hours, int percent, int recent) {
    return 'Hinweise erst ab $samples Messwerten über mindestens $hours Stunden. Abweichung: alle letzten $recent Werte mehr als $percent % neben dem Üblichen (Median), ein Ausreißer zählt nicht. Verbraucher, die oft aus sind, melden keinen Ausfall.';
  }

  @override
  String loadHintSilent(String typical, int minutes, String time) {
    return 'Sendet vermutlich nicht mehr: sonst etwa alle $minutes min, zuletzt um $time. Üblich waren $typical.';
  }

  @override
  String loadHintDropped(String typical, String latest) {
    return 'Vermutlich ausgefallen oder abgeschaltet: üblich $typical, zuletzt $latest.';
  }

  @override
  String loadHintDeviation(String typical, String latest, String percent) {
    return 'Weicht ab: üblich $typical, zuletzt $latest ($percent %). Vermutlich hat sich am Verbraucher etwas geändert.';
  }

  @override
  String get checkFilterTitle => 'Koppler: Filtertabellen';

  @override
  String get checkFilterHint =>
      'Die Filtertabellen werden nicht gelesen und nicht beschrieben. Das Ergebnis stammt aus dem Projekt und dem Mitgehörten und ist deshalb nur eine Vermutung.';

  @override
  String get checkFilterLive => 'Laufender Mitschnitt';

  @override
  String checkFilterCrossRow(String senders, String receivers) {
    return 'Sender auf $senders, Empfänger auf $receivers: kommt vermutlich nur an, wenn die Filtertabelle des Kopplers sie kennt';
  }

  @override
  String checkFilterConfirmedRow(String lines) {
    return 'Auf $lines von einer anderen Linie gesehen, der Übergang funktioniert vermutlich';
  }

  @override
  String checkFilterMissingRow(String seen, int count, String missing) {
    return 'Auf $seen gesehen ($count×), auf $missing nicht, obwohl dort ein Empfänger sitzt. Vermutlich fehlt die Adresse in der Filtertabelle oder sie wurde nicht neu geladen.';
  }

  @override
  String get checkFilterNoPoints =>
      'Ein Vergleich am Bus braucht zwei gleichzeitige Mitschnitte auf verschiedenen Linien. Bisher stammt das Ergebnis nur aus dem Projekt.';

  @override
  String get etsTitleFilterCrossLine => 'Linienübergreifende Adressen';

  @override
  String etsTodoFilterCrossLine(String line, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Adressen laufen',
      one: '1 Adresse läuft',
    );
    return '$_temp0 zu Linie $line. Prüfe, ob der Koppler dorthin nach der letzten Änderung geladen wurde (Filtertabelle); die App kann das nicht sehen.';
  }

  @override
  String get etsTitleFilterNotForwarded => 'Vermutlich vom Koppler gefiltert';

  @override
  String etsTodoFilterNotForwarded(String line) {
    return 'Kam auf Linie $line nicht an, obwohl dort ein Empfänger sitzt. Filtertabelle des Kopplers in der ETS prüfen und neu laden.';
  }

  @override
  String get plantTitle => 'Anlagenbericht';

  @override
  String get plantTool =>
      'Monats- oder Quartalsbericht von Box und Add-on, als PDF';

  @override
  String get plantIntro =>
      'Box und Add-on verdichten den Betrieb der Anlage zu einem Bericht: Verfügbarkeit, Verkehr, Buslast, verstummte Geräte, Rauchmelder und Batterien. Die Daten bleiben auf dem Server.';

  @override
  String get plantEnabled => 'Bericht erstellen';

  @override
  String get plantEnabledHint =>
      'Standard aus. Der erste Bericht entsteht nach Ende des laufenden Zeitraums.';

  @override
  String get plantLastError =>
      'Der letzte Lauf ist fehlgeschlagen; die Aufzeichnung läuft weiter.';

  @override
  String get plantPeriod => 'Zeitraum';

  @override
  String get plantPeriodMonthly => 'Monatlich';

  @override
  String get plantPeriodQuarterly => 'Quartalsweise';

  @override
  String get plantMaintenance => 'Wartung';

  @override
  String get plantMaintenanceNone =>
      'Kein Wartungsintervall in der Kundenakte.';

  @override
  String get plantNotify => 'Mitteilungen';

  @override
  String get plantNotifyHint =>
      'Standard aus. Nur eine Zusammenfassung wie „Bericht bereit: 2 Befunde“, nie Adressen, Namen oder Werte. Das Ziel wählst du.';

  @override
  String get plantNotifyTarget => 'Ziel';

  @override
  String get plantNotifyOff => 'Keine Mitteilungen';

  @override
  String get plantNotifyWebhook => 'Webhook';

  @override
  String get plantNotifyHa => 'Home Assistant';

  @override
  String get plantNotifyUrl => 'Adresse';

  @override
  String get plantNotifyTopic => 'Topic';

  @override
  String get plantNotifyToken => 'Zugangstoken';

  @override
  String get plantNotifyTokenSet =>
      'Gespeichert; leer lassen, um es zu behalten';

  @override
  String get plantNotifyTokenOptional => 'Optional';

  @override
  String get plantNotifyReady => 'Wenn ein Bericht bereit ist';

  @override
  String get plantNotifyUrgent =>
      'Bei dringenden Befunden und fälliger Wartung';

  @override
  String get plantNotifySave => 'Speichern';

  @override
  String get plantNotifyTest => 'Test senden';

  @override
  String get plantTestSent => 'Testmitteilung zugestellt.';

  @override
  String get plantNotifyErrorOff => 'kein Ziel gewählt';

  @override
  String get plantNotifyErrorTimeout => 'das Ziel antwortet nicht';

  @override
  String get plantNotifyErrorInvalid =>
      'die Adresse oder das Topic ist ungültig';

  @override
  String get plantNotifyErrorNetwork => 'keine Verbindung zum Ziel';

  @override
  String get plantReports => 'Berichte';

  @override
  String get plantNoReports => 'Noch kein Bericht.';

  @override
  String get plantGenerateNow => 'Zwischenstand erstellen';

  @override
  String get plantGenerating => 'Bericht entsteht …';

  @override
  String get plantPartial => 'Zwischenstand';

  @override
  String get plantResultGood => 'Keine Auffälligkeiten im Zeitraum.';

  @override
  String get plantStatusNew => 'neu';

  @override
  String get plantStatusUnchanged => 'unverändert';

  @override
  String get plantStatusResolved => 'behoben';

  @override
  String get plantFindings => 'Befunde';

  @override
  String get plantFindingsNone => 'Keine Befunde.';

  @override
  String get plantResolved => 'Seit dem letzten Bericht behoben';

  @override
  String get plantSafety => 'Rauchmelder, Störungen, Batterien';

  @override
  String get plantSafetyHint =>
      'Letzter Stand, erkannt an Name und Datentyp im Projekt. Ersetzt keine Prüfung der Melder.';

  @override
  String get plantSafetyActive => 'aktiv';

  @override
  String get plantSafetyOk => 'in Ordnung';

  @override
  String get plantSafetyUnknown => 'unbekannt';

  @override
  String get plantOutageList => 'Ausfälle';

  @override
  String get plantOutageOffline => 'Server lief nicht';

  @override
  String get plantOutageDisconnected => 'Bus nicht verbunden';

  @override
  String get plantTopSenders => 'Aktivste Geräte';

  @override
  String get plantLines => 'Buslast je Linie (Mittel / Spitzenstunde)';

  @override
  String get plantRepeatList => 'Wiederholungen je Gerät';

  @override
  String get plantPdf => 'Als PDF';

  @override
  String get plantPdfName => 'Anlagenbericht';

  @override
  String get plantPdfTitle => 'Anlagenbericht';

  @override
  String get plantPdfNote =>
      'Erstellt aus den Daten der Daueraufzeichnung. Die Buslast ist eine Schätzung aus den mitgehörten Telegrammen; Geräte hinter Linienkopplern sind nur sichtbar, soweit die Filter sie durchlassen.';

  @override
  String get plantAvailabilityLabel => 'Verfügbarkeit';

  @override
  String get plantTelegramsLabel => 'Telegramme';

  @override
  String get plantLoadLabel => 'Buslast Mittel / Spitze';

  @override
  String get plantCoverageLabel => 'Tage mit Daten';

  @override
  String get visitReport => 'Anlagenbericht erstellt';

  @override
  String plantDeviceSilent(String label, String since) {
    return 'Gerät $label antwortet nicht mehr seit $since';
  }

  @override
  String plantCyclicSilent(String label, String since) {
    return '$label sendet sonst regelmäßig, zuletzt am $since';
  }

  @override
  String plantStuck(String label, String since) {
    return '$label: Messwert ändert sich nicht mehr seit $since';
  }

  @override
  String plantRepeats(String label, String rate) {
    return 'Gerät $label wiederholt $rate % seiner Telegramme';
  }

  @override
  String plantBusLoad(String rate) {
    return 'Buslast bis $rate % in der Spitzenstunde';
  }

  @override
  String plantOutages(String rate) {
    return 'Verfügbarkeit nur $rate %';
  }

  @override
  String plantRestarts(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n unerwartete Neustarts des Servers',
      one: '1 unerwarteter Neustart des Servers',
    );
    return '$_temp0';
  }

  @override
  String plantAlarmActive(String label, String since) {
    return '$label: Alarm aktiv seit $since';
  }

  @override
  String plantFaultActive(String label, String since) {
    return '$label: Störung aktiv seit $since';
  }

  @override
  String plantBatteryLow(String label, String since) {
    return '$label: Batterie schwach, gemeldet am $since';
  }

  @override
  String plantNotifyErrorHttp(String code) {
    return 'das Ziel meldet HTTP $code';
  }

  @override
  String plantTestFailed(String reason) {
    return 'Nicht zugestellt: $reason';
  }

  @override
  String plantResultAttention(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Punkte brauchen Aufmerksamkeit.',
      one: '1 Punkt braucht Aufmerksamkeit.',
    );
    return '$_temp0';
  }

  @override
  String plantEntryFindings(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Befunde',
      one: '1 Befund',
      zero: 'Keine Befunde',
    );
    return '$_temp0';
  }

  @override
  String plantEntryNew(int n) {
    return '$n neu';
  }

  @override
  String plantEntryResolved(int n) {
    return '$n behoben';
  }

  @override
  String plantCoverage(int days, int total) {
    return 'Daten für $days von $total Tagen';
  }

  @override
  String plantAvailability(String rate) {
    return 'Verfügbarkeit $rate %';
  }

  @override
  String plantTelegrams(int n) {
    return '$n Telegramme';
  }

  @override
  String plantLoad(String average, String peak) {
    return 'Buslast $average % / Spitze $peak %';
  }

  @override
  String get crashTitle => 'KNX Monitor wurde unerwartet beendet';

  @override
  String get crashReport => 'Bericht erstellen';

  @override
  String get crashDismiss => 'Ausblenden';

  @override
  String get restartReasonError => 'Fehler im Server';

  @override
  String get restartReasonHost => 'Gerät neu gestartet oder Stromausfall';

  @override
  String get restartReasonUnknown => 'Grund unbekannt';

  @override
  String crashBody(String time) {
    return 'Zuletzt im Vordergrund: $time. Nichts wird automatisch gesendet. Mit dem Bericht siehst du das bereinigte Protokoll im Diagnosepaket und entscheidest selbst, ob du es teilst.';
  }

  @override
  String serverRestarts(int count, String time, String reason) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unerwartete Neustarts',
      one: '1 unerwarteter Neustart',
    );
    return '$_temp0 in 30 Tagen, zuletzt $time ($reason)';
  }

  @override
  String findingRestarts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unerwartete Neustarts des Servers',
      one: '1 unerwarteter Neustart des Servers',
    );
    return '$_temp0 in den letzten 30 Tagen';
  }

  @override
  String plantBusErrors(String rate) {
    return '$rate % der Telegramme abgelehnt oder gestört (Busmonitor)';
  }

  @override
  String get dataExportTitle => 'Datenexport';

  @override
  String get dataExportTool =>
      'Zähler und Werte nach InfluxDB oder Prometheus, mit Grafana-Vorlage';

  @override
  String get dataExportIntro =>
      'Für den eigenen Grafana-Server. Standard aus. Es geht nur etwas hinaus, wenn du unten ein Ziel einträgst; Prometheus ruft nur aus dem lokalen Netz und mit Token ab.';

  @override
  String get dataExportValues => 'Auch Adressen, Namen und Werte';

  @override
  String get dataExportValuesHint =>
      'Sonst nur Zähler des Busses. Mit diesem Schalter landen Namen und Messwerte der Anlage in der Datenbank.';

  @override
  String get dataExportPrometheus => 'Prometheus (Abruf)';

  @override
  String get dataExportPort => 'Port';

  @override
  String get dataExportTokenSet =>
      'Zugangstoken gespeichert; es wird nicht noch einmal angezeigt.';

  @override
  String get dataExportTokenTitle => 'Token für Prometheus';

  @override
  String get dataExportTokenBody =>
      'Einmalig angezeigt. In Prometheus unter „authorization: credentials“ eintragen.';

  @override
  String get dataExportCopy => 'Kopieren';

  @override
  String get dataExportClose => 'Schließen';

  @override
  String get dataExportInflux => 'InfluxDB (Senden)';

  @override
  String get dataExportInfluxUrl => 'Adresse';

  @override
  String get dataExportInfluxOrg => 'Organisation (InfluxDB 2)';

  @override
  String get dataExportInfluxBucket => 'Bucket (InfluxDB 2)';

  @override
  String get dataExportInfluxDatabase => 'Datenbank (InfluxDB 1)';

  @override
  String get dataExportInfluxToken => 'Zugangstoken';

  @override
  String get dataExportInterval => 'Sendetakt in Sekunden';

  @override
  String get dataExportTest => 'Verbindung testen';

  @override
  String get dataExportTestOk => 'Testzeile angekommen.';

  @override
  String get dataExportSave => 'Speichern';

  @override
  String get dataExportGrafana => 'Grafana-Vorlage';

  @override
  String get dataExportGrafanaHint =>
      'In Grafana unter Dashboards › Importieren laden und die Datenquelle wählen.';

  @override
  String get dataExportGrafanaPrometheus => 'Für Prometheus speichern';

  @override
  String get dataExportGrafanaInflux => 'Für InfluxDB speichern';

  @override
  String get dataExportBindError =>
      'Der Port ist belegt. Bitte einen anderen wählen.';

  @override
  String dataExportPortHint(String port) {
    return 'Erreichbar unter http://<Adresse>:$port/metrics';
  }

  @override
  String get teamTitle => 'Betrieb';

  @override
  String get teamAskTitle => 'Meister fragen';

  @override
  String teamPdfChecked(String name, String date) {
    return 'Geprüft von: $name, $date';
  }

  @override
  String teamPdfApproved(String name, String date) {
    return 'Abgenommen von: $name, $date';
  }

  @override
  String installationDeleteSureTitle(String name) {
    return '„$name“ wirklich endgültig löschen?';
  }

  @override
  String get installationDeleteSureBody =>
      'Das lässt sich nicht rückgängig machen. Unterschriebene Abnahmeprotokolle und Serviceberichte, Kundendaten, Besuchsverlauf, Fotos, ETS-Projekt, Keyring und Langzeitverlauf sind danach auf diesem Gerät unwiederbringlich weg. Sichere vorher, was du als Nachweis brauchst.';

  @override
  String get installationDeleteSureConfirm => 'Endgültig löschen';

  @override
  String get appLockSettings => 'App-Sperre';

  @override
  String get appLockExplain =>
      'Schützt die App, falls das Gerät verloren geht oder gestohlen wird: Beim Start und nach der gewählten Zeit im Hintergrund muss sich jemand ausweisen. Der Bus läuft währenddessen weiter.';

  @override
  String get appLockTitle => 'KNX Monitor ist gesperrt';

  @override
  String get appLockReason => 'KNX Monitor entsperren';

  @override
  String get appLockSystemHint =>
      'Mit Face ID, Fingerabdruck, Windows Hello oder dem Gerätecode entsperren.';

  @override
  String get appLockPasswordHint => 'Mit dem App-Passwort entsperren.';

  @override
  String get appLockPassword => 'App-Passwort';

  @override
  String get appLockUnlock => 'Entsperren';

  @override
  String get appLockWrong =>
      'Das hat nicht geklappt. Nach mehreren Fehlversuchen musst du warten.';

  @override
  String get appLockForgot => 'Passwort vergessen';

  @override
  String get appLockForgotTitle => 'Passwort vergessen?';

  @override
  String get appLockForgotBody =>
      'Das App-Passwort lässt sich nicht zurücksetzen, sonst wäre die Sperre wertlos. Du kannst nur alle Daten der App auf diesem Gerät löschen: Projekte, Aufnahmen, Kundendaten und Schlüssel.';

  @override
  String get appLockForgotBodyTeam =>
      'Das App-Passwort lässt sich nicht zurücksetzen, sonst wäre die Sperre wertlos. Du kannst nur alle Daten der App auf diesem Gerät löschen: Projekte, Aufnahmen, Kundendaten, Schlüssel und die Anmeldung.';

  @override
  String get appLockForgotContinue => 'Weiter';

  @override
  String get appLockForgotSureTitle => 'Wirklich alles löschen?';

  @override
  String get appLockForgotSureBody =>
      'Das lässt sich nicht rückgängig machen. Zurück kommt nur, was in einer eigenen Sicherung liegt. Die App beendet sich danach.';

  @override
  String get appLockForgotSureBodyTeam =>
      'Das lässt sich nicht rückgängig machen. Zurück kommt nur, was in deinem Konto, deinem Betrieb oder einer eigenen Sicherung liegt. Die App beendet sich danach.';

  @override
  String get appLockForgotConfirm => 'Alles löschen';

  @override
  String get appLockRequiredTitle => 'Sperre einrichten';

  @override
  String get appLockRequiredBody =>
      'Du arbeitest in einem Betrieb und hast Kundendaten auf dem Gerät. Darum braucht die App eine Sperre.';

  @override
  String get appLockRequiredNote =>
      'Dein Betrieb verlangt die Sperre, solange du Mitglied bist.';

  @override
  String get appLockUseSystem => 'Gerätesperre nutzen';

  @override
  String get appLockSystemFailed =>
      'Die Gerätesperre hat nicht bestätigt. Versuch es erneut oder nimm ein App-Passwort.';

  @override
  String get appLockNewPassword => 'Neues App-Passwort';

  @override
  String get appLockRepeatPassword => 'App-Passwort wiederholen';

  @override
  String get appLockUsePassword => 'App-Passwort nutzen';

  @override
  String get appLockPasswordWarning =>
      'Das App-Passwort kann niemand zurücksetzen. Dafür bekommst du gleich einen Notfallschlüssel. Fehlen beide, bleibt nur, die Daten der App auf diesem Gerät zu löschen.';

  @override
  String get appLockActiveSystem => 'Eingeschaltet, mit der Gerätesperre.';

  @override
  String get appLockActivePassword => 'Eingeschaltet, mit dem App-Passwort.';

  @override
  String get appLockTimeout => 'Sperren nach';

  @override
  String get appLockTimeoutNow => 'Sofort';

  @override
  String get appLockOff => 'Sperre ausschalten';

  @override
  String get appLockMismatch => 'Die beiden Passwörter stimmen nicht überein.';

  @override
  String appLockTooShort(int count) {
    return 'Mindestens $count Zeichen.';
  }

  @override
  String appLockTimeoutMinutes(int count) {
    return '$count Min.';
  }

  @override
  String get backupTitle => 'Sicherung';

  @override
  String get backupExplain =>
      'Speichert alles von diesem Gerät in eine Datei mit eigenem Passwort: Anlagen, Projekte, Keyrings, Kundenakte, Kommentare, Aufnahmen und Verlauf. Das Format ist offen beschrieben. Ohne das Passwort kommt niemand an die Datei, auch wir nicht. Bitte regelmäßig sichern und an einem anderen Ort aufbewahren.';

  @override
  String get backupCreate => 'Sicherung erstellen';

  @override
  String get backupRestore => 'Sicherung einspielen';

  @override
  String get backupPassword => 'Passwort der Sicherung';

  @override
  String get backupRepeat => 'Passwort wiederholen';

  @override
  String backupTooShort(int count) {
    return 'Mindestens $count Zeichen.';
  }

  @override
  String get backupMismatch => 'Die beiden Passwörter stimmen nicht überein.';

  @override
  String get backupSaved => 'Sicherung gespeichert.';

  @override
  String get backupRestoreTitle => 'Sicherung einspielen?';

  @override
  String get backupRestoreBody =>
      'Dateien mit demselben Namen werden ersetzt. Die App beendet sich danach und ist beim nächsten Start auf dem Stand der Sicherung.';

  @override
  String get backupOpenFailed =>
      'Das hat nicht geklappt: falsches Passwort oder keine gültige Sicherung.';

  @override
  String get backupNewer =>
      'Diese Sicherung stammt aus einer neueren Version. Bitte zuerst die App aktualisieren.';

  @override
  String get backupNotIncluded =>
      'Nicht enthalten: die App-Sperre und der Verlauf auf einer Box.';

  @override
  String get backupNotIncludedTeam =>
      'Nicht enthalten: die Anmeldung, die App-Sperre, die Schlüssel eines Betriebs und der Verlauf auf einer Box.';

  @override
  String get recoveryTitle => 'Notfallschlüssel';

  @override
  String get recoveryUse => 'Notfallschlüssel eingeben';

  @override
  String get recoveryExplain =>
      'Damit kommst du in die App, falls du das App-Passwort vergisst. Bitte außerhalb dieses Geräts aufbewahren, zum Beispiel ausgedruckt oder im Passwortmanager.';

  @override
  String get recoverySavePdf => 'Als PDF speichern';

  @override
  String get recoveryNoted => 'Sicher notiert';

  @override
  String get recoveryRenew => 'Neuen Notfallschlüssel erstellen';

  @override
  String get recoveryResetBody =>
      'Der Notfallschlüssel hat die App geöffnet und gilt nun nicht mehr. Lege eine neue Sperre fest.';

  @override
  String get recoveryPdfIntro =>
      'Dieser Schlüssel öffnet die App-Sperre von KNX Monitor, wenn das App-Passwort vergessen wurde.';

  @override
  String recoveryPdfAccount(String email) {
    return 'Konto: $email';
  }

  @override
  String get recoveryPdfUse =>
      'So geht es: Auf dem Sperrbildschirm „Notfallschlüssel eingeben“ wählen, den Schlüssel eintippen und ein neues Passwort festlegen. Danach gilt dieser Schlüssel nicht mehr; die App erstellt einen neuen.';

  @override
  String get recoveryPdfLimits =>
      'Der Schlüssel gilt nur für dieses Gerät. Er öffnet keine Sicherungsdatei und ersetzt keine Sicherung, falls das Gerät verloren geht.';

  @override
  String get recoveryPdfLimitsTeam =>
      'Der Schlüssel gilt nur für dieses Gerät. Er öffnet weder dein Konto noch eine Sicherungsdatei und ersetzt keine Sicherung, falls das Gerät verloren geht.';

  @override
  String get recoveryPdfKeep =>
      'Wer dieses Blatt und das Gerät zusammen hat, kommt in die App. Bewahre es getrennt vom Gerät auf.';

  @override
  String appLockWait(int seconds) {
    return 'Zu viele Fehlversuche. Noch $seconds Sekunden warten, dann geht es weiter.';
  }

  @override
  String get customerPdf => 'Akte als PDF';

  @override
  String get diagNotFiltered =>
      'Nicht gefiltert: Telegrammwerte (können verraten, wann jemand zu Hause ist), Namen von Gruppenadressen und Geräten, solange der Schalter an ist, sowie Namen, die du selbst in Beschreibung oder Kommentare tippst.';

  @override
  String get diagShotsTitle => 'Screenshots mitsenden';

  @override
  String get diagShotsHint =>
      'Bilder werden nicht gefiltert: Alles, was darauf zu sehen ist, geht an den Empfänger, auch Namen, Adressen und Kundendaten. Sieh sie dir vorher an.';

  @override
  String diagContentShotsOut(int count) {
    return 'Screenshots: $count vorhanden, nicht enthalten';
  }

  @override
  String get historyWithoutTime => 'Ohne Uhrzeit';

  @override
  String get historyWithoutTimeHint =>
      'Die Box kannte die Uhrzeit nicht und ist neu gestartet. Reihenfolge und Abstände stimmen, Datum und Uhrzeit nicht.';

  @override
  String get installationRecovered => 'Anlage wiederhergestellt';

  @override
  String get errorNetworkGone => 'Das Netzwerk ist weg oder hat gewechselt.';

  @override
  String get boxShareDiffersTitle => 'Andere Daten auf der Box';

  @override
  String get boxShareDiffersBody =>
      'Projekt oder Keyring auf der Box unterscheiden sich von diesem Gerät, und wir wissen nicht, welcher Stand neuer ist. Solange sie sich unterscheiden, entschlüsselt und benennt die Box mit ihrem eigenen Stand.';

  @override
  String get boxShareKeep => 'Box behalten';

  @override
  String get boxShareReplace => 'Von diesem Gerät übernehmen';

  @override
  String backupEstimate(String size) {
    return 'Daten dieses Geräts: etwa $size.';
  }

  @override
  String backupTooLarge(String size, String limit) {
    return 'Die Daten sind mit $size zu groß für eine Sicherung am Stück (höchstens $limit). Es wurde nichts gespeichert. Bitte alte Aufnahmen oder Verlaufstage löschen oder die Aufbewahrung verkürzen.';
  }

  @override
  String get accountMfaPdfTitle => 'Anmeldeschlüssel für die Authenticator-App';

  @override
  String get accountMfaPdfIntro =>
      'Mit diesem Blatt bekommst du die Anmeldecodes für dein KNX-Monitor-Konto zurück, wenn dein Telefon weg ist.';

  @override
  String get accountMfaPdfUse =>
      'So geht es: Neue Authenticator-App installieren, Konto hinzufügen, den QR-Code scannen oder den Schlüssel eintippen. Die App zeigt dann wieder die sechsstelligen Codes.';

  @override
  String get accountMfaPdfWarning =>
      'Wer dieses Blatt hat, kann sich die Codes selbst erzeugen. Wegschließen wie einen Hausschlüssel, nicht fotografieren und nicht in die Cloud legen. Hast du den Zugang neu eingerichtet, entferne im Konto die alte App: Dann ist dieses Blatt wertlos.';

  @override
  String get backupReminder =>
      'Deine letzte Sicherung ist über 30 Tage her oder fehlt noch. Kundenakten und Anlagen liegen nur auf diesem Gerät.';

  @override
  String get backupReminderOpen => 'Jetzt sichern';

  @override
  String get backupReminderDismiss => 'Später';

  @override
  String backupLast(String date) {
    return 'Letzte Sicherung auf diesem Gerät: $date';
  }

  @override
  String get backupNever => 'Von diesem Gerät gibt es noch keine Sicherung.';

  @override
  String get backupSlow =>
      'Das Verschlüsseln kann auf älteren Geräten bis zu einer Minute dauern.';

  @override
  String get zipTooLarge =>
      'Die Datei ist ausgepackt zu groß und wurde nicht geöffnet.';

  @override
  String get installationsNewerTitle => 'Neuere Daten';

  @override
  String get installationsNewerBody =>
      'Diese Daten stammen aus einer neueren Version von KNX Monitor. Bitte aktualisiere die App. Deine Daten bleiben unverändert.';

  @override
  String get quarantineTitle => 'Alte Daten nicht lesbar';

  @override
  String quarantineBody(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien ($size) lassen',
      one: 'Eine Datei ($size) lässt',
    );
    return '$_temp0 sich nicht öffnen, weil der Schlüssel auf diesem Gerät fehlt, zum Beispiel nach einem Gerätewechsel. Es bleibt alles auf dem Gerät. Mit einer Sicherung holst du die Daten zurück.';
  }

  @override
  String get quarantineRestore => 'Aus Sicherung wiederherstellen';

  @override
  String get quarantineDelete => 'Dateien löschen';

  @override
  String get quarantineDeleteBody =>
      'Diese Dateien lassen sich danach nie wieder öffnen.';

  @override
  String get boxForeignTitle => 'Diese Box ist nicht im lokalen Netz';

  @override
  String boxForeignBody(String address) {
    return 'Der Link führt zu $address. Das ist keine Adresse im lokalen Netz. Wer diesen Server betreibt, bekommt dein ETS-Projekt mit allen Adressen und Namen. Verbinde dich nur, wenn du ihn selbst betreibst.';
  }

  @override
  String get boxForeignConfirm => 'Trotzdem verbinden';

  @override
  String get boxKeyringTitle => 'KNX-Secure-Schlüssel auf diese Box geben?';

  @override
  String boxKeyringBody(String address) {
    return 'Die Box unter $address bekäme die Schlüssel und Passwörter deiner KNX-Secure-Anlage (Keyring, IP-Secure-Zugang zum Gateway), damit sie sich verbindet und gesicherte Telegramme lesbar aufzeichnet. Wer Zugriff auf die Box hat, kommt an diese Schlüssel. Stimme nur zu, wenn es deine Box ist.';
  }

  @override
  String get boxKeyringAllow => 'Schlüssel geben';

  @override
  String get boxKeyringDeny => 'Nicht geben';

  @override
  String get historyPausedPlan =>
      'Der Verlauf ist pausiert: Langzeitverlauf gehört zu Plus. Neue Telegramme werden nicht gespeichert, vorhandene Tage bleiben erhalten.';

  @override
  String backupSideFiles(String size) {
    return 'Ältere und beschädigte Fassungen belegen zusätzlich $size.';
  }

  @override
  String get appLockHideTitle => 'Im App-Umschalter verbergen';

  @override
  String get appLockHideHint =>
      'Android zeigt dann im App-Umschalter ein leeres Bild, und Screenshots der App gehen nicht mehr.';

  @override
  String faultShotsLeftOut(int count) {
    return 'Screenshots an Kommentaren ($count) bleiben ohne den Schalter draußen.';
  }

  @override
  String get boxPasswordMustTitle => 'Eigenes Box-Passwort setzen';

  @override
  String get boxPasswordRequired =>
      'Erst ein eigenes Box-Passwort setzen. Das vom Aufkleber kann jeder lesen, der die Box sieht.';

  @override
  String get boxPasswordStillSticker =>
      'Es gilt noch das Passwort vom Aufkleber. Wer es hat, kann die Box steuern und den Keyring lesen. Setze unten ein eigenes; es verschwindet dann von der SD-Karte.';

  @override
  String get boxPlainWarning =>
      'Unverschlüsselt: Diese Verbindung läuft über dein Netz im Klartext, auch der Gerätezugang und die Telegramme. Am besten im WLAN der Box bleiben.';

  @override
  String get boxPlainWarningTls =>
      'Unverschlüsselt: Diese Verbindung läuft über dein Netz im Klartext. Die Box kann HTTPS: Auf ihrer Seite /pair einen neuen QR-Code erzeugen und scannen, dann ist die Verbindung verschlüsselt.';

  @override
  String get boxWifiChange => 'WLAN-Passwort ändern';

  @override
  String get boxWifiHint =>
      '8 bis 63 Zeichen ohne Leerzeichen und ohne \" \' \\ \$ `. Der WLAN-Code des Aufklebers gilt danach nicht mehr.';

  @override
  String get boxWifiConfirm =>
      'Alle Geräte fliegen aus dem WLAN der Box und müssen mit dem neuen Passwort wieder beitreten. Dieses Gerät macht das selbst, soweit das System es erlaubt.';

  @override
  String get boxWifiChanged =>
      'WLAN-Passwort geändert. Die Box startet ihr WLAN gleich neu.';

  @override
  String get boxLowSpace =>
      'Speicher voll: Die Box zeichnet gerade nicht auf. Ältere Tage sind schon gelöscht. Platz schaffen oder Aufbewahrung verkürzen, dann läuft es von selbst weiter.';

  @override
  String get cloudSyncFeature => 'Abgleich zwischen deinen Geräten';

  @override
  String get cloudSyncTitle => 'Geräte abgleichen';

  @override
  String get hpTitle => 'Hausplan';

  @override
  String get hpEntry => 'Haus planen';

  @override
  String get writeNoticeTitle => 'Eingriff in die Anlage';

  @override
  String get writeNoticeBody =>
      'Dieser Wert geht auf den Bus und kann echte Geräte schalten. Für den Schaltvorgang und seine Folgen bist du verantwortlich. Wir übernehmen dafür keine Haftung, außer wo das Gesetz sie zwingend vorschreibt.';

  @override
  String get writeNoticeHide => 'Nicht mehr anzeigen';

  @override
  String get writeNoticeHideHint =>
      'Das Ausblenden steht mit Datum in Diagnosepaketen und Fehlerberichten.';

  @override
  String get writeNoticeConfirm => 'Schreiben';

  @override
  String get writeNoticeRestore => 'Hinweis vor dem Schreiben wieder anzeigen';

  @override
  String diagContentWriteNotice(String date) {
    return 'Hinweis vor dem Schreiben: ausgeblendet am $date';
  }

  @override
  String get telegramMenuDetails => 'Details öffnen';

  @override
  String get telegramMenuSelect => 'Auswählen';

  @override
  String get scanCameraDenied =>
      'Kamera nicht freigegeben. Erlaube sie in den Einstellungen des Geräts, oder gib die Angaben von Hand ein.';

  @override
  String get backupShort =>
      'Alles von diesem Gerät in einer Datei mit eigenem Passwort.';

  @override
  String get backupAppStorage => 'Speicher der App';

  @override
  String get backupPrevious => 'Vorige Fassungen';

  @override
  String get backupLastRow => 'Letzte Sicherung';

  @override
  String get backupNoneYet => 'Noch keine';

  @override
  String get appLockMethodSystem => 'Face ID, Fingerabdruck oder Gerätecode';

  @override
  String get appLockMethodPassword => 'Mit dem App-Passwort';

  @override
  String get lessonsLessons => 'Lektionen';

  @override
  String get lessonsKind => 'Kurz erklärt';

  @override
  String get lessonsPractice => 'Üben';

  @override
  String lessonsTermCount(int count) {
    return '$count Begriffe';
  }

  @override
  String get quizMeta => 'Fragen aus deiner Anlage';

  @override
  String get handoverShort => 'Alles für die App des Kunden in einer Datei.';

  @override
  String get handoverProject => 'Projekt';

  @override
  String get customerMaintenance => 'Wartung';

  @override
  String customerMaintEvery(int count) {
    return 'Alle $count Monate';
  }

  @override
  String customerMaintIn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'In $count Monaten',
      one: 'In 1 Monat',
      zero: 'In diesem Monat',
    );
    return '$_temp0';
  }

  @override
  String get customerVisitAdd => 'Besuch eintragen';

  @override
  String get customerVisits => 'Besuche';

  @override
  String get customerDocuments => 'Dokumente';

  @override
  String get srIncludes => 'Enthält';

  @override
  String get reactMedian => 'Median';

  @override
  String get reactSlowest => 'Langsamste';

  @override
  String get reactPairs => 'Befehl und Rückmeldung';

  @override
  String get loadChannelsLabel => 'Kanäle';

  @override
  String get loadHighest => 'Höchster Wert';

  @override
  String get loadConsumers => 'Größte Verbraucher';

  @override
  String hpRoomsOf(int shown, int total) {
    return '$shown von $total';
  }

  @override
  String get exportsData => 'Daten';

  @override
  String get exportsPermanent => 'Dauerhaft';

  @override
  String get ackLast => 'Letzte';

  @override
  String get ackHeard => 'Zuletzt gehört';

  @override
  String get learnNamed => 'Benannt';

  @override
  String get learnOpenCount => 'Offen';

  @override
  String get learnPressTitle => 'Drück einen Taster';

  @override
  String get chartsAddresses => 'Adressen';

  @override
  String get planLicenseEnter => 'Lizenz eingeben';

  @override
  String get planLicenseField => 'Lizenz';

  @override
  String get planLicenseHelp =>
      'Die ganze Zeile aus der Mail einfügen, sie beginnt mit KNX1. Sie gilt auf deinen eigenen Windows-Geräten.';

  @override
  String get planLicenseApply => 'Freischalten';

  @override
  String get planLicenseInvalid =>
      'Diese Lizenz stimmt nicht. Bitte die ganze Zeile aus der Mail einfügen.';

  @override
  String get planLicenseEnded =>
      'Diese Lizenz gilt nicht mehr: Das Abo ist beendet oder der Kauf wurde erstattet.';

  @override
  String get planLicenseCheckoutOpened =>
      'Die Kaufseite ist im Browser offen. Nach dem Kauf kommt deine Lizenz per Mail, die gibst du hier unter „Lizenz eingeben“ ein.';

  @override
  String planLicenseActive(String tier) {
    return '$tier ist freigeschaltet.';
  }

  @override
  String get addonReadOnly =>
      'Nur-Lesen ist an: Der Server sendet nichts auf den Bus. Im Add-on unter Konfiguration „Nur lesen“ ausschalten, auf Box und Docker READ_ONLY entfernen.';

  @override
  String get exportsEtsHistory =>
      'Verlauf als ETS-Datei (für Home Assistant und SpectrumKNX)';

  @override
  String get exportsEtsHistoryMeta =>
      'Dauerhafte Aufzeichnung, einzelne Tage oder alles';

  @override
  String get exportsEtsHistoryHint =>
      'Lädt die Telegramme der dauerhaften Aufzeichnung als Gruppenmonitor-Datei der ETS. SpectrumKNX, die ETS und KNX Monitor öffnen sie direkt.';

  @override
  String get exportsEtsHistoryDownload => 'Herunterladen';

  @override
  String get exportsEtsHistoryCancel => 'Abbrechen';

  @override
  String get exportsEtsHistoryLoading => 'Verlauf wird geladen …';

  @override
  String get chartsPeriodLoaded => 'Geladen';

  @override
  String get chartsPeriodToday => 'Heute';

  @override
  String get chartsPeriodLoadedHint =>
      'Geladen zeigt die letzten 5.000 Telegramme, die die App gerade im Speicher hat. Heute, 7 und 30 Tage kommen aus dem Verlauf von Add-on oder Box.';

  @override
  String chartsPeriodFailed(String error) {
    return 'Verlauf nicht geladen: $error';
  }

  @override
  String get chartsPeriodMetrics =>
      'Bus-Kennzahlen zeigen nur den geladenen Zeitraum.';

  @override
  String get chartsDashedHint =>
      'Gestrichelt: Der letzte Wert gilt weiter, seitdem kam kein neues Telegramm.';

  @override
  String get chartsPeriodUnreachable => 'Add-on oder Box antwortet nicht.';

  @override
  String get chartsPeriodRetry => 'Erneut laden';

  @override
  String get exportsEtsHistoryAll => 'Alles';

  @override
  String get exportsEtsHistoryAllHint =>
      'Der ganze Verlauf als ZIP mit einer Datei pro Tag. SpectrumKNX importiert sie in einem Rutsch, etwa für einen Umzug. Bei vielen Wochen kann das einige Minuten dauern.';

  @override
  String get chartsAnnotateHere => 'Hier kommentieren';

  @override
  String get annotationValuesLabel => 'Werte';

  @override
  String get groupRename => 'Namen korrigieren';

  @override
  String get groupRenamed => 'Name selbst korrigiert – ändern';

  @override
  String groupRenameTitle(String address) {
    return 'Name für $address';
  }

  @override
  String get groupRenameField => 'Name';

  @override
  String groupRenameHelp(String name) {
    return 'Im Projekt: „$name“. Die Korrektur gilt in der App und geht mit den Aufgaben für die ETS als Gruppenadress-Import zurück.';
  }

  @override
  String get groupRenameRevert => 'Wie im Projekt';

  @override
  String get groupReplaceTitle => 'Namen suchen und ersetzen';

  @override
  String get groupReplaceFind => 'Suchen';

  @override
  String get groupReplaceWith => 'Ersetzen durch';

  @override
  String get groupReplaceHint =>
      'Zum Beispiel einen Tippfehler, der in vielen Namen vorkommt. Groß- und Kleinschreibung zählt.';

  @override
  String groupReplaceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Namen werden geändert, zum Beispiel:',
      one: '1 Name wird geändert:',
      zero: 'Kein Name enthält diesen Text.',
    );
    return '$_temp0';
  }

  @override
  String get groupReplaceApply => 'Ersetzen';

  @override
  String groupReplaceDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Namen korrigiert. Sie gehen mit den Aufgaben für die ETS zurück.',
      one: '1 Name korrigiert. Er geht mit den Aufgaben für die ETS zurück.',
    );
    return '$_temp0';
  }

  @override
  String get etsTitleRename => 'Name korrigiert';

  @override
  String etsTodoRename(String name) {
    return 'Namen in „$name“ ändern – erledigt der Gruppenadress-Import.';
  }

  @override
  String get exportFailedGeneric =>
      'Export hat nicht geklappt. Versuch es noch einmal.';

  @override
  String get pdfExportFailedGeneric =>
      'PDF hat nicht geklappt. Versuch es noch einmal.';

  @override
  String get boxShareFailed => 'Die Box hat die Daten nicht angenommen.';

  @override
  String get huntLoadFailed =>
      'Fehlerjagd nicht geladen. Ist die Box erreichbar?';

  @override
  String get actionFailed => 'Das hat nicht geklappt. Versuch es noch einmal.';

  @override
  String get commonUndo => 'Rückgängig';

  @override
  String get visitDeleteTitle => 'Eintrag löschen?';

  @override
  String watchRemoved(String what) {
    return 'Wächter entfernt: $what';
  }

  @override
  String learnForgotten(String name) {
    return 'Vergessen: $name';
  }

  @override
  String boxPairNamed(String name) {
    return 'Name im Link: $name';
  }

  @override
  String get boxPairUnencrypted =>
      'Unverschlüsselt (HTTP): Wer im selben Netz mitliest, sieht alles, was die App an diese Box schickt. Verbinde dich nur in deinem eigenen Netz.';

  @override
  String get boxReplaceTitle => 'Gekoppelte Box ersetzen?';

  @override
  String boxReplaceBody(String current, String next) {
    return 'Gekoppelt ist $current. Der Link würde sie durch $next ersetzen, die bisherige Kopplung geht dabei verloren.';
  }

  @override
  String get boxReplaceConfirm => 'Ersetzen';

  @override
  String get boxProjectTitle => 'Projekt an diese Box geben?';

  @override
  String boxProjectBody(String box) {
    return 'Die Box $box wurde über einen Link aus einer anderen App oder Webseite gekoppelt. Gibst du ihr dein Projekt, bekommt sie das ETS-Projekt mit allen Adressen und Namen, den Namen der Anlage und die Gateway-Adresse. Bis dahin bekommt sie nichts davon.';
  }

  @override
  String get boxProjectAllow => 'Projekt geben';

  @override
  String get boxProjectDeny => 'Noch nicht';

  @override
  String get appLockRestart =>
      'Zu viele Fehlversuche. Beende die App und öffne sie neu, dann kannst du es noch einmal versuchen.';
}
