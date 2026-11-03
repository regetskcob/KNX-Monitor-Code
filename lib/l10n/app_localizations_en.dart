// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get splashSubtitle => 'Group monitor for KNXnet/IP';

  @override
  String get commonCancel => 'Cancel';

  @override
  String groupAddressCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count group addresses',
      one: '1 group address',
    );
    return '$_temp0';
  }

  @override
  String deviceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count devices', one: '1 device');
    return '$_temp0';
  }

  @override
  String get connectSubtitle => 'Connect to a KNX/IP gateway';

  @override
  String get connectGateway => 'Gateway';

  @override
  String get connectPort => 'Port';

  @override
  String get connectHostEmpty => 'Enter an IP address';

  @override
  String get connectHostIpv4Only => 'IPv4 only';

  @override
  String get connectHostInvalid => 'Invalid address';

  @override
  String get connectButton => 'Connect';

  @override
  String get connectRecent => 'Recently used';

  @override
  String get connectViewRecordings => 'View recordings';

  @override
  String get catalogNone => 'No group addresses';

  @override
  String get catalogImported => 'imported';

  @override
  String get catalogHint => 'ETS project (.knxproj) or group address CSV for names, datapoint types & devices';

  @override
  String get catalogReplace => 'Replace';

  @override
  String get catalogImport => 'Import';

  @override
  String catalogImportedSnack(String summary) {
    return '$summary imported';
  }

  @override
  String catalogImportFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get catalogPickFile => 'Please choose a .knxproj or .csv file.';

  @override
  String get passwordTitle => 'Project password';

  @override
  String get passwordWrong => 'The password was wrong. Please try again.';

  @override
  String get passwordPrompt => 'The ETS project is protected. The password is only used to open it and is not stored.';

  @override
  String get passwordLabel => 'Password';

  @override
  String get passwordShow => 'Show';

  @override
  String get passwordHide => 'Hide';

  @override
  String get passwordOpen => 'Open';

  @override
  String get activityLast60s => 'last 60 s';

  @override
  String get activityOverRecording => 'across the recording';

  @override
  String get typeWrite => 'Write';

  @override
  String get typeRead => 'Read';

  @override
  String get typeResponse => 'Response';

  @override
  String get issueRepeatedLabel => 'Repeated';

  @override
  String get issueRepeatedHint => 'First attempt not acknowledged – device missing or line disturbed.';

  @override
  String get issueNotConfirmedLabel => 'Not acknowledged';

  @override
  String get issueNotConfirmedHint => 'No receiver acknowledged the telegram.';

  @override
  String get issueUnansweredLabel => 'No response';

  @override
  String get issueUnansweredHint => 'No device responded – read flag or status sender missing?';

  @override
  String get issueSizeMismatchLabel => 'Length ≠ DPT';

  @override
  String get issueSizeMismatchHint => 'The data length does not match the datapoint type from the project.';

  @override
  String get issueUnknownAddressLabel => 'Not in project';

  @override
  String get issueUnknownAddressHint => 'This group address does not exist in the ETS project.';

  @override
  String get issueUnknownDeviceLabel => 'Unknown device';

  @override
  String get issueUnknownDeviceHint => 'The individual address is not assigned to any device in the ETS project.';

  @override
  String get issueUnusualHopLabel => 'Hop';

  @override
  String get issueUnusualHopHint => 'Hop count ≠ 6: telegram passed a coupler (or 7 = unlimited).';

  @override
  String get issueCentralOffOnLabel => 'Central off with on';

  @override
  String get issueCentralOffOnHint =>
      'By its name a central-off address, but the value is 1 – depending on the actuator this switches everything on. Central off should only send 0.';

  @override
  String errorSocket(String error) {
    return 'Socket error: $error';
  }

  @override
  String get errorGatewayNoResponse => 'Gateway does not respond.';

  @override
  String errorNetwork(String error) {
    return 'Network error: $error';
  }

  @override
  String get errorNotConnected => 'Not connected.';

  @override
  String errorTelegramRejected(String status) {
    return 'Gateway rejected the telegram (0x$status).';
  }

  @override
  String get errorNoAck => 'No acknowledgement from the gateway.';

  @override
  String get errorClosedByGateway => 'Connection closed by the gateway.';

  @override
  String get errorGatewayStoppedResponding => 'Gateway stopped responding.';

  @override
  String get errorNoFreeTunnel => 'Gateway reports: no free tunnel.';

  @override
  String get errorTunnelUnsupported => 'Gateway does not support tunneling.';

  @override
  String get errorOptionUnsupported => 'Gateway does not support the connection option.';

  @override
  String errorConnectionRejected(String status) {
    return 'Connection rejected (status 0x$status).';
  }

  @override
  String get projectPasswordWrong => 'Wrong project password.';

  @override
  String get projectPasswordRequired => 'Project is password protected.';

  @override
  String get projectInvalidFile => 'Not a valid .knxproj file.';

  @override
  String get projectDefaultDevice => 'Device';

  @override
  String get projectDefaultGroup => 'Group address';

  @override
  String get projectNoGroups => 'Project contains no group addresses.';

  @override
  String get projectNoData => 'No project data found in the file.';

  @override
  String get projectMissing0xml => '0.xml is missing in the project.';

  @override
  String projectUnreadable(String error) {
    return 'Project not readable: $error';
  }

  @override
  String get csvEmpty => 'File is empty.';

  @override
  String get csvNoAddressColumn => 'No address column found.';

  @override
  String get csvNoGroups => 'No group addresses found.';

  @override
  String get dpt1Off => 'Off';

  @override
  String get dpt1On => 'On';

  @override
  String get dpt1False => 'False';

  @override
  String get dpt1True => 'True';

  @override
  String get dpt1Disable => 'Disabled';

  @override
  String get dpt1Enable => 'Enabled';

  @override
  String get dpt1NoAlarm => 'No alarm';

  @override
  String get dpt1Alarm => 'Alarm';

  @override
  String get dpt1Decrease => 'Decrease';

  @override
  String get dpt1Increase => 'Increase';

  @override
  String get dpt1Up => 'Up';

  @override
  String get dpt1Down => 'Down';

  @override
  String get dpt1Open => 'Open';

  @override
  String get dpt1Close => 'Close';

  @override
  String get dpt1Stop => 'Stop';

  @override
  String get dpt1Start => 'Start';

  @override
  String get dpt1Inactive => 'Inactive';

  @override
  String get dpt1Active => 'Active';

  @override
  String get dpt1Trigger => 'Trigger';

  @override
  String get dpt1NotOccupied => 'Not occupied';

  @override
  String get dpt1Occupied => 'Occupied';

  @override
  String get dpt1Closed => 'Closed';

  @override
  String get dpt1Opened => 'Open';

  @override
  String get dpt1Day => 'Day';

  @override
  String get dpt1Night => 'Night';

  @override
  String get dpt2Forced => 'Forced';

  @override
  String get dpt2Free => 'Free';

  @override
  String get dpt3Brighter => 'Brighter';

  @override
  String get dpt3Darker => 'Darker';

  @override
  String dptSceneNumber(int number) {
    return 'Scene $number';
  }

  @override
  String dptSceneStore(int number) {
    return 'Store scene $number';
  }

  @override
  String dptSceneRecall(int number) {
    return 'Recall scene $number';
  }

  @override
  String get dptSceneLearn => 'learn';

  @override
  String get hvacAuto => 'Auto';

  @override
  String get hvacComfort => 'Comfort';

  @override
  String get hvacStandby => 'Standby';

  @override
  String get hvacEconomy => 'Economy';

  @override
  String get hvacProtection => 'Building protection';

  @override
  String get dptNameSwitch => 'Switch';

  @override
  String get dptNameUpDown => 'Up/Down';

  @override
  String get dptNamePercent => 'Percent';

  @override
  String get dptNameCounter => 'Counter';

  @override
  String get dptNameSigned => 'Signed';

  @override
  String get dptNameScene => 'Scene';

  @override
  String get dptNameFloat => 'Float';

  @override
  String get dptNameTime => 'Time of day';

  @override
  String get dptNameDate => 'Date';

  @override
  String get dptNameDateTime => 'Date/time';

  @override
  String get dptNameText => 'Text';

  @override
  String get weekdayMon => 'Mon';

  @override
  String get weekdayTue => 'Tue';

  @override
  String get weekdayWed => 'Wed';

  @override
  String get weekdayThu => 'Thu';

  @override
  String get weekdayFri => 'Fri';

  @override
  String get weekdaySat => 'Sat';

  @override
  String get weekdaySun => 'Sun';

  @override
  String get writeFormatSwitch => 'On/Off';

  @override
  String get writeFormatNumber => 'Number 0–255';

  @override
  String get writeFormatDecimal => 'Decimal number';

  @override
  String get writeFormatScene => 'Scene 1–64';

  @override
  String get writeFormatHex => 'Raw hex data';

  @override
  String get writeFormatLabel => 'Format';

  @override
  String get writeValueLabel => 'Value';

  @override
  String get writeButton => 'Write';

  @override
  String writeDone(String value) {
    return 'Written: $value';
  }

  @override
  String writeInvalidValue(String format) {
    return 'Invalid value for $format.';
  }

  @override
  String get confirmAcknowledged => 'acknowledged by the bus';

  @override
  String get confirmNotAcknowledged => 'not acknowledged – no receiver?';

  @override
  String get confirmNoConfirmation => 'no confirmation from the gateway';

  @override
  String get sendInvalidAddress => 'Invalid group address.';

  @override
  String sendReadSent(String confirmation) {
    return 'Read request sent$confirmation. The response will appear in the monitor.';
  }

  @override
  String get sendTitle => 'Read / write group address';

  @override
  String get sendReadValue => 'Read value';

  @override
  String get sendGroupAddress => 'Group address';

  @override
  String get sendGroupAddressHint => '1/2/3 or name';

  @override
  String pdfExportFailed(String error) {
    return 'PDF export failed: $error';
  }

  @override
  String activitySemantics(String period) {
    return 'Bus activity $period';
  }

  @override
  String get activityRate => 'Tel./min now';

  @override
  String get activityTotal => 'Total';

  @override
  String get healthRepeated => 'Repeated';

  @override
  String get healthRepeatedTooltip => 'Repeated telegrams – indicate missing acknowledgements';

  @override
  String get healthUnanswered => 'No response';

  @override
  String get healthUnansweredTooltip => 'Read requests without a response within 3 s';

  @override
  String get rowSent => 'Sent';

  @override
  String get rowThisTunnel => 'this tunnel';

  @override
  String get columnTime => 'Time';

  @override
  String get columnType => 'Type';

  @override
  String get columnAddress => 'Address';

  @override
  String get columnName => 'Name';

  @override
  String get columnSender => 'Sender';

  @override
  String get columnValue => 'Value';

  @override
  String badgeSentTooltip(String type) {
    return '$type (sent)';
  }

  @override
  String badgeSentSemantics(String type) {
    return '$type, sent';
  }

  @override
  String get legendOutlinedSent => 'outlined: sent by this app';

  @override
  String get liveWaiting => 'Waiting for telegrams …';

  @override
  String get liveNewest => 'Newest';

  @override
  String get commonSave => 'Save';

  @override
  String get monitorExportTitle => 'KNX telegrams';

  @override
  String get monitorClear => 'Clear monitor';

  @override
  String get monitorImport => 'Import ETS project or CSV …';

  @override
  String get monitorRemoveProject => 'Remove project data';

  @override
  String get monitorDisconnect => 'Disconnect';

  @override
  String get monitorConnecting => 'Connecting …';

  @override
  String get monitorDisconnected => 'Disconnected';

  @override
  String get monitorConnected => 'Connected';

  @override
  String get monitorResume => 'Resume';

  @override
  String get monitorPause => 'Pause display';

  @override
  String get monitorConnectionLost => 'Connection lost.';

  @override
  String get monitorReconnect => 'Reconnect';

  @override
  String recordingDefaultName(String date, String time) {
    return 'Recording $date $time';
  }

  @override
  String recordingSaved(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count telegrams', one: '1 telegram');
    return '“$name” saved · $_temp0';
  }

  @override
  String get recordingView => 'View';

  @override
  String get recordingStart => 'Start recording';

  @override
  String get recordingEdit => 'Edit recording';

  @override
  String get recordingSave => 'Save recording';

  @override
  String recordingCaptured(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count telegrams recorded.',
      one: '1 telegram recorded.',
    );
    return '$_temp0';
  }

  @override
  String get recordingName => 'Name';

  @override
  String get recordingNoteLabel => 'Note (optional)';

  @override
  String get recordingNoteHint => 'What was checked? Findings?';

  @override
  String get recordingContinue => 'Keep recording';

  @override
  String get recordingStopAndSave => 'Stop & save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get labelTelegrams => 'Telegrams';

  @override
  String telegramCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count telegrams', one: '1 telegram');
    return '$_temp0';
  }

  @override
  String get recordingsTitle => 'Recordings';

  @override
  String get recordingsEmpty => 'No recordings yet – tap “Record” in the monitor.';

  @override
  String get recordingsStart => 'Start';

  @override
  String get recordingsDuration => 'Duration';

  @override
  String get recordingDeleteTitle => 'Delete recording?';

  @override
  String recordingDeleteText(String name) {
    return '“$name” will be permanently removed.';
  }

  @override
  String get recordingPdf => 'Recording as PDF';

  @override
  String get recordingEditMenu => 'Edit name & note';

  @override
  String get recordingDeleteMenu => 'Delete recording';

  @override
  String get playerPause => 'Pause playback';

  @override
  String get playerPlay => 'Play recording';

  @override
  String get playerRestart => 'Back to start';

  @override
  String get playerSpeed => 'Speed';

  @override
  String get commonMore => 'More';

  @override
  String get tabOverview => 'Over­view';

  @override
  String get tabLive => 'Live';

  @override
  String get filterHint => 'Filter: 1/2/3, 1.1.5, value …';

  @override
  String get filterHintProject => 'Filter: name, device, 1/2/3, value …';

  @override
  String get filterClear => 'Clear filter';

  @override
  String get selectForPdfTooltip => 'Select telegrams for PDF';

  @override
  String get selectForPdf => 'Select for PDF';

  @override
  String get exportAllPdf => 'Export all as PDF';

  @override
  String get selectEnd => 'End selection';

  @override
  String get selectTitle => 'Select telegrams';

  @override
  String selectCount(int count) {
    return '$count selected';
  }

  @override
  String get selectNone => 'None';

  @override
  String get selectAll => 'All';

  @override
  String selectExport(int count) {
    return 'As PDF ($count)';
  }

  @override
  String get commonClose => 'Close';

  @override
  String get commonNo => 'No';

  @override
  String detailsHistoryPdfName(String name) {
    return 'History $name';
  }

  @override
  String detailsSummaryLine(String type, String sender, String time) {
    return '$type from $sender at $time';
  }

  @override
  String get detailsIssues => 'Issues';

  @override
  String get detailsHistory => 'History';

  @override
  String get detailsChart => 'Chart';

  @override
  String get detailsList => 'List';

  @override
  String get detailsHistoryPdf => 'Export history as PDF';

  @override
  String get detailsWriteValue => 'Write value';

  @override
  String detailsReadSent(String confirmation) {
    return 'Read request sent$confirmation';
  }

  @override
  String get detailsCurrent => 'Current';

  @override
  String get detailsComment => 'Comment';

  @override
  String get detailsRemember => 'Save';

  @override
  String get detailsFilter => 'Filter';

  @override
  String get detailsCopied => 'Copied to clipboard';

  @override
  String get detailsCopy => 'Copy';

  @override
  String get detailsTelegram => 'Telegram';

  @override
  String get detailsDescription => 'Description';

  @override
  String get detailsPriority => 'Priority';

  @override
  String get prioritySystem => 'System';

  @override
  String get priorityNormal => 'Normal';

  @override
  String get priorityUrgent => 'Urgent';

  @override
  String get priorityLow => 'Low';

  @override
  String get detailsRepeatedYes => 'Yes – first attempt not acknowledged';

  @override
  String get detailsHopCount => 'Hop count';

  @override
  String get detailsHopDirect => 'direct';

  @override
  String get detailsHopUnlimited => 'unlimited';

  @override
  String detailsHopCouplers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'via $count couplers',
      one: 'via 1 coupler',
    );
    return '$_temp0';
  }

  @override
  String get detailsConfirmation => 'Confirmation';

  @override
  String get detailsAcknowledged => 'Acknowledged by the bus – received; the status shows whether it was carried out';

  @override
  String get detailsData => 'Data';

  @override
  String detailsLinkedDevices(int count) {
    return 'Linked devices ($count)';
  }

  @override
  String get detailsInterpretations => 'Possible interpretations';

  @override
  String get detailsMoreInterpretations => 'Other interpretations';

  @override
  String get detailsSentLower => 'sent';

  @override
  String detailsOlder(int count) {
    return '… and $count older';
  }

  @override
  String detailsObject(int number) {
    return 'CO $number';
  }

  @override
  String get detailsSends => 'sends';

  @override
  String get detailsReceives => 'receives';

  @override
  String chartSemantics(int count, String last) {
    return 'History chart with $count values, latest $last';
  }

  @override
  String get boardBrightness => 'Brightness';

  @override
  String boardMainGroup(int number) {
    return 'Main group $number';
  }

  @override
  String get boardEmpty => 'No values received yet';

  @override
  String boardSectionSemantics(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count addresses', one: '1 address');
    return '$title, $_temp0';
  }

  @override
  String get diagnosticsTitle => 'Diagnostics';

  @override
  String get diagNotInProject => 'not in project';

  @override
  String get diagScopeStatus => 'Feedback';

  @override
  String get diagProgTitle => 'Programming mode';

  @override
  String get diagProgText =>
      'Finds devices whose programming LED is on – e.g. when ETS reports “multiple devices in programming mode”.';

  @override
  String get diagSearching => 'Searching …';

  @override
  String get diagSearch => 'Search';

  @override
  String get diagProgNone => 'No device in programming mode.';

  @override
  String get diagAddressInvalid => 'Please enter an individual address such as 1.1.18.';

  @override
  String get diagAddressTitle => 'Check individual address';

  @override
  String get diagAddressText => 'Checks like ETS whether an address is in use and reads the device mask version.';

  @override
  String get diagCheck => 'Check';

  @override
  String get diagAddressPresent => 'in use';

  @override
  String get diagAddressFree => 'free – no device acknowledged';

  @override
  String get diagAddressUnknown => 'unclear – no confirmation from the gateway';

  @override
  String diagMaskVersion(String mask) {
    return 'Mask version $mask';
  }

  @override
  String get pdfPeriod => 'Period';

  @override
  String get pdfValues => 'Values';

  @override
  String get pdfMinimum => 'Minimum';

  @override
  String get pdfMaximum => 'Maximum';

  @override
  String get pdfAverage => 'Average';

  @override
  String pdfFooterCreated(String date, String time) {
    return 'Created with KNX Monitor · $date $time';
  }

  @override
  String pdfPage(int page, int total) {
    return 'Page $page of $total';
  }

  @override
  String get pdfNote => 'Note';

  @override
  String get pdfThisDevice => 'this device';

  @override
  String get boardWeather => 'Weather';

  @override
  String get boardEnergy => 'Energy & power';

  @override
  String get boardDateTime => 'Date & time';

  @override
  String get activitySent => 'Sent';

  @override
  String get boardAlarms => 'Alarms & faults';

  @override
  String get alarmLabel => 'Alarm';

  @override
  String get faultLabel => 'Fault';

  @override
  String get activityAlarms => 'Active alarms';

  @override
  String get detailsAlarmTitle => 'Active alert';

  @override
  String get detailsAlarmAlarm => 'This address reports an alarm.';

  @override
  String get detailsAlarmFault => 'This address reports a fault or defect.';

  @override
  String get quickAlarm => 'Alarms';

  @override
  String get quickRepeated => 'Repeated';

  @override
  String get quickUnanswered => 'Unanswered';

  @override
  String get quickUnknown => 'Not in project';

  @override
  String get savedFilters => 'Saved filters';

  @override
  String get saveCurrentFilter => 'Save current filter';

  @override
  String get noSavedFilters => 'No saved filters yet';

  @override
  String get deleteFilter => 'Delete filter';

  @override
  String get filterHelp => 'Filter help';

  @override
  String get filterHelpBody =>
      'Space = AND · comma = OR · -term = NOT\n\n1/2/3 exact · 1/2 range · 1/*/3 or 1/2/1* with wildcard\n1.1.5 sender · 1.1.* line · from:1.1.5\n\ntype:w|r|a (write, read, response)\ndpt:9 or dpt:9.001\ntime:14:05 · time:14:05-14:10 (time of day, end excluded)\nis:alarm · is:repeated · is:unanswered · is:unknown\nis:own · is:received (sent by you or from the bus)\n\nAnything else searches name, range, device and value – umlauts optional.\n\nSeveral OR groups each get a colour in the list. \"Context\" shows the seconds before and after every match.\n\nExamples:\n1/*/* is:unanswered – unanswered reads in main group 1\nkitchen, bath -switch – kitchen or bath, without switch';

  @override
  String get checkTitle => 'Project check';

  @override
  String get checkNoProject => 'Import an ETS project or a group address CSV to compare the bus traffic with it.';

  @override
  String get checkUnknownAddresses => 'Group addresses not in project';

  @override
  String get checkUnknownDevices => 'Senders not in project';

  @override
  String get checkSizeMismatch => 'Data length does not match DPT';

  @override
  String get checkNeverSeen => 'Never seen on the bus';

  @override
  String get checkAllGood => 'No deviations';

  @override
  String checkSenders(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count senders', one: '1 sender');
    return '$_temp0';
  }

  @override
  String checkGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count group addresses',
      one: '1 group address',
    );
    return '$_temp0';
  }

  @override
  String checkExpected(String expected, String seen) {
    return 'expected $expected, seen $seen';
  }

  @override
  String checkBytes(int count) {
    return '$count bytes';
  }

  @override
  String get checkSmall => '≤ 6 bit';

  @override
  String checkMore(int count) {
    return '… and $count more';
  }

  @override
  String get checkNeverSeenHint => 'Depends on the observation period – rarely used addresses appear later.';

  @override
  String get gatewayTitle => 'Gateway';

  @override
  String get gatewayAddress => 'Address';

  @override
  String get gatewayMedium => 'Medium';

  @override
  String get gatewayIndividual => 'Individual address';

  @override
  String get gatewaySerial => 'Serial number';

  @override
  String get gatewayMac => 'MAC address';

  @override
  String get gatewayMulticast => 'Routing multicast';

  @override
  String get gatewayProgMode => 'Programming mode';

  @override
  String get gatewayTunnel => 'This tunnel';

  @override
  String gatewayTunnelValue(String address, int channel) {
    return '$address · channel $channel';
  }

  @override
  String get gatewayServices => 'Supported services';

  @override
  String get gatewaySlots => 'Tunnel slots';

  @override
  String get gatewaySlotFree => 'free';

  @override
  String get gatewaySlotBusy => 'in use';

  @override
  String get gatewayUnknown => 'The gateway has not sent a self-description yet.';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get scanGateways => 'Find gateways';

  @override
  String get scanRunning => 'Searching the local network …';

  @override
  String get scanNone => 'No KNXnet/IP device found.';

  @override
  String get scanFound => 'Found';

  @override
  String get statsTitle => 'Statistics';

  @override
  String get statsSpan => 'Period';

  @override
  String get statsPerMinute => 'Avg tel./min';

  @override
  String get monitorPauseShort => 'Pause';

  @override
  String get statsPerMinuteShort => 'Tel./min';

  @override
  String get statsSendersShort => 'Senders';

  @override
  String get statsGroupsShort => 'Addresses';

  @override
  String get statsSenders => 'Top senders';

  @override
  String get statsGroups => 'Top group addresses';

  @override
  String get statsFlappers => 'Sends unusually often';

  @override
  String get statsFlappersHint => 'On average more often than every 10 s – cycle too short or no hysteresis?';

  @override
  String get statsPeaks => 'Load peaks';

  @override
  String statsRepeatRate(String rate) {
    return '$rate repeated';
  }

  @override
  String statsEvery(String interval) {
    return 'every $interval';
  }

  @override
  String statsPerSecond(int count) {
    return '$count tel./s';
  }

  @override
  String get statsEmpty => 'No telegrams for statistics yet.';

  @override
  String get statsPdfTitle => 'Bus statistics';

  @override
  String get triggerTitle => 'Triggered recording';

  @override
  String get triggerExplain =>
      'Records automatically as soon as the condition occurs – including the telegrams before. Ideal for sporadic faults.';

  @override
  String get triggerCondition => 'Condition';

  @override
  String get triggerKindAddress => 'Group address';

  @override
  String get triggerKindAlarm => 'Alarm or fault';

  @override
  String get triggerKindRepeated => 'Repeated telegram';

  @override
  String get triggerKindUnanswered => 'Unanswered read';

  @override
  String get triggerKindUnknown => 'Address not in project';

  @override
  String get triggerValue => 'Value contains (optional)';

  @override
  String triggerPre(int count) {
    return 'Before: $count telegrams';
  }

  @override
  String triggerPost(int count) {
    return 'After: $count telegrams';
  }

  @override
  String get triggerRearm => 'Re-arm afterwards';

  @override
  String get triggerArm => 'Arm';

  @override
  String get triggerDisarm => 'Disarm';

  @override
  String get triggerArmed => 'Trigger armed';

  @override
  String get triggerRecording => 'Trigger recording';

  @override
  String triggerFired(String name) {
    return 'Trigger fired: “$name” saved';
  }

  @override
  String triggerRecordingName(String condition) {
    return 'Trigger: $condition';
  }

  @override
  String triggerNote(String condition, String time, int pre, int post) {
    return 'Recorded automatically. Condition: $condition. Fired at $time, $pre telegrams before, $post after.';
  }

  @override
  String get triggerInvalidAddress => 'Please enter a group address like 1/2/3.';

  @override
  String get exportAllCsv => 'All as CSV';

  @override
  String get exportAllEts => 'All as ETS telegram file';

  @override
  String get exportCsv => 'As CSV';

  @override
  String get exportEts => 'As ETS telegram file';

  @override
  String exportSaved(String name) {
    return 'Saved: $name';
  }

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get recordingsImport => 'Import ETS telegram file';

  @override
  String recordingsImported(String name, int count) {
    return '“$name” imported · $count telegrams';
  }

  @override
  String recordingsImportFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get scanTitle => 'Line scan';

  @override
  String get scanExplain =>
      'Checks every address of a line like ETS does and compares it with the project. A full scan takes a few minutes.';

  @override
  String get scanLine => 'Line';

  @override
  String scanRange(int from, int to) {
    return 'Devices $from–$to';
  }

  @override
  String get scanStart => 'Start scan';

  @override
  String get scanInvalidLine => 'Please enter a line like 1.1.';

  @override
  String get scanPresent => 'Present';

  @override
  String get scanMissing => 'In project, not responding';

  @override
  String get scanUnexpected => 'Responding, not in project';

  @override
  String get scanChecked => 'Checked';

  @override
  String get mapGraphSelected => 'Connections';

  @override
  String get mapGraphHint => 'Zoom in for more detail. Tap a device to see its connections.';

  @override
  String get mapGraphAll => 'All devices';

  @override
  String get mapGraphUnlinked => 'Devices without links';

  @override
  String get mapTitle => 'Communication map';

  @override
  String get mapSenders => 'Senders';

  @override
  String get mapReceivers => 'Receivers (project)';

  @override
  String get mapListens => 'Listens to';

  @override
  String get mapSends => 'Sends to';

  @override
  String get mapNone => 'None';

  @override
  String mapObserved(int count) {
    return 'observed $count×';
  }

  @override
  String get mapProjectOnly => 'project only';

  @override
  String get mapNotInProject => 'not linked in project';

  @override
  String get mapSearch => 'Search address or device …';

  @override
  String get mapEmpty => 'No bus traffic for a map yet.';

  @override
  String get mapHint => 'Tap to center a node. Lines: solid = observed, dashed = project only.';

  @override
  String get historyTitle => 'Long-term history';

  @override
  String get historyExplain =>
      'Stores all bus traffic per day while the monitor is connected – to review, replay and export later.';

  @override
  String get historyOff => 'Off';

  @override
  String historyDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count days', one: '1 day');
    return '$_temp0';
  }

  @override
  String historyUsage(String size) {
    return 'Used: $size';
  }

  @override
  String historyDayName(String date) {
    return 'History $date';
  }

  @override
  String get historyDeleteAll => 'Delete history';

  @override
  String get historyEmpty => 'No days stored yet.';

  @override
  String get historyOffHint => 'Turning it off deletes the stored history.';

  @override
  String get tabObjects => 'Objects';

  @override
  String get objectsEmpty =>
      'No objects recognized yet – this needs group addresses with a naming scheme (e.g. “EG FL F01 Up/Down”) and bus traffic.';

  @override
  String get objectsOther => 'Other';

  @override
  String get objectCommands => 'Commands';

  @override
  String get objectFeedback => 'Feedback';

  @override
  String get objectFilter => 'Filter monitor to this object';

  @override
  String get objectHint => 'Recognized by the shared name prefix. Solid = value received, dashed = no telegram yet.';

  @override
  String objectMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count addresses', one: '1 address');
    return '$_temp0';
  }

  @override
  String get diagDeviceInfo => 'Read device info';

  @override
  String get diagDeviceInfoFailed => 'Device did not accept a connection.';

  @override
  String get devManufacturer => 'Manufacturer';

  @override
  String get devSerial => 'Serial number';

  @override
  String get devSerialMatch => 'matches project';

  @override
  String devSerialMismatch(String serial) {
    return 'differs from project ($serial)';
  }

  @override
  String get devOrder => 'Order number';

  @override
  String get devHardware => 'Hardware type';

  @override
  String get devFirmware => 'Firmware';

  @override
  String get devProgMode => 'Programming mode';

  @override
  String get devApplication => 'Application';

  @override
  String get devMask => 'Mask version';

  @override
  String get devOn => 'on';

  @override
  String get devOff => 'off';

  @override
  String get devUnsupported => 'not supported';

  @override
  String get expertMode => 'Expert mode';

  @override
  String get expertModeHint => 'Show tools, exports and all metrics directly';

  @override
  String get toolsTitle => 'Tools';

  @override
  String get toolDiagnostics => 'Programming mode, address check, device info, line scan';

  @override
  String get toolCheck => 'Compare bus traffic with the ETS project';

  @override
  String get toolStats => 'Busiest addresses and senders, outliers';

  @override
  String get toolMap => 'Who talks to whom';

  @override
  String get toolTrigger => 'Start recording automatically on an event';

  @override
  String get toolRecordings => 'Saved recordings and long-term history';

  @override
  String get exportMenu => 'Export';

  @override
  String get planFeatureFullExport => 'Full exports: ETS file, ZIP, charts';

  @override
  String get exportSelect => 'Select telegrams …';

  @override
  String get exportSelectHint => 'Only specific telegrams as PDF, CSV or ETS file';

  @override
  String get projectMenu => 'ETS project';

  @override
  String get projectRemove => 'Remove';

  @override
  String get projectHintRaw =>
      'Without an ETS project you only see raw values. With a project, names, units and devices appear.';

  @override
  String get commonDismiss => 'Dismiss';

  @override
  String monitorRetryIn(int seconds) {
    return 'Retrying in $seconds s';
  }

  @override
  String get sectionPin => 'Pin to top';

  @override
  String get sectionUnpin => 'Unpin';

  @override
  String get sectionPinHint => 'Long-press to pin';

  @override
  String get busmonTitle => 'Bus monitor';

  @override
  String get busmonTool => 'Every frame on the line: acknowledgements, repetitions, corrupted telegrams';

  @override
  String get busmonHint =>
      'Shows everything on the line, including acknowledgements and corrupted telegrams. The live monitor pauses meanwhile and reconnects afterwards.';

  @override
  String get busmonConnecting => 'Starting bus monitor …';

  @override
  String busmonFailed(String error) {
    return 'Bus monitor not possible: $error';
  }

  @override
  String get busmonRetry => 'Retry';

  @override
  String get busmonFrames => 'Frames';

  @override
  String get busmonTelegrams => 'Telegrams';

  @override
  String get busmonAck => 'ACK';

  @override
  String get busmonNegative => 'NAK/BUSY';

  @override
  String get busmonErrors => 'Errors';

  @override
  String get busmonRepeated => 'Repeated';

  @override
  String get busmonUnacked => 'No ACK';

  @override
  String get busmonHideAcks => 'Hide acknowledgements';

  @override
  String get busmonOnlyProblems => 'Only anomalies';

  @override
  String get busmonEmpty => 'Nothing on the line yet';

  @override
  String get busmonChecksum => 'Bad checksum';

  @override
  String get busmonStatusError => 'Transmission error';

  @override
  String get busmonIndividual => 'Individually addressed';

  @override
  String get busmonAckText => 'Acknowledged';

  @override
  String get busmonNakText => 'Rejected (NAK)';

  @override
  String get busmonBusyText => 'Busy (BUSY)';

  @override
  String get busmonNakBusyText => 'NAK + BUSY';

  @override
  String get busmonUnknownText => 'Unreadable frame';

  @override
  String get favorites => 'Favorites';

  @override
  String get favoriteAdd => 'Pin to top as favorite';

  @override
  String get favoriteRemove => 'Remove from favorites';

  @override
  String get busmonLoad => 'Bus load';

  @override
  String get busmonLoadHint =>
      'Line occupancy (TP, 9600 bit/s), average of the last 10 s. Sustained values above 50 % indicate problems.';

  @override
  String busmonLoadPeak(String value) {
    return 'Peak $value %';
  }

  @override
  String get busmonSenders => 'Senders';

  @override
  String get busmonSendersHint => 'Devices with repetitions or missing acknowledgements first. Tap to filter the list.';

  @override
  String get busmonDetails => 'Frame details';

  @override
  String get busmonTapHint => 'Tap a frame for details';

  @override
  String get busmonFieldControl => 'Control field';

  @override
  String get busmonFieldRepeat => 'Repetition';

  @override
  String get busmonFieldHops => 'Hop count';

  @override
  String get busmonFieldLength => 'Length';

  @override
  String get busmonFieldPayload => 'Payload';

  @override
  String get busmonFieldChecksum => 'Checksum';

  @override
  String get busmonFieldStatus => 'Status';

  @override
  String get busmonFieldTimestamp => 'Gateway time';

  @override
  String get busmonFieldAck => 'Acknowledgement';

  @override
  String get busmonFieldSource => 'Source';

  @override
  String get busmonFieldTarget => 'Target';

  @override
  String get busmonFieldRaw => 'Raw';

  @override
  String get busmonYes => 'yes';

  @override
  String get busmonNo => 'no';

  @override
  String get busmonChecksumOk => 'correct';

  @override
  String busmonChecksumBad(String expected) {
    return 'wrong (expected $expected)';
  }

  @override
  String busmonStatusOk(int seq) {
    return 'no errors, sequence $seq';
  }

  @override
  String busmonSenderStats(int frames) {
    return '$frames frames';
  }

  @override
  String notifyAlarmTitle(String name) {
    return 'Alarm: $name';
  }

  @override
  String notifyFaultTitle(String name) {
    return 'Fault: $name';
  }

  @override
  String get notifyMenu => 'Alarm notifications';

  @override
  String get filterNoMatch => 'Nothing matches the filter';

  @override
  String get emptyMonitorHint => 'Many devices only send on change. You can query the current state actively.';

  @override
  String get emptyReadStatus => 'Read status';

  @override
  String get topoTitle => 'Topology';

  @override
  String get topoTool => 'Lines, couplers and cross-line communication';

  @override
  String get topoHint =>
      'From the ETS project and observed traffic. The gateway sees its own line and only what couplers forward from other lines. The hop count shows how many couplers a telegram passed.';

  @override
  String topoLine(String line) {
    return 'Line $line';
  }

  @override
  String get topoGatewayHere => 'Gateway';

  @override
  String get topoDevices => 'Devices';

  @override
  String get topoActive => 'Active';

  @override
  String get topoTelegrams => 'Telegrams';

  @override
  String get topoCouplers => 'Couplers to gateway';

  @override
  String topoCoupler(String address, String name) {
    return 'Coupler $address · $name';
  }

  @override
  String get topoNotInProject => 'not in project (tunnel/visu?)';

  @override
  String get topoSilent => 'not seen';

  @override
  String get topoCross => 'Cross-line';

  @override
  String get topoCrossHint =>
      'Addresses with devices in several lines: which lines send, which listen, and how many telegrams from other lines have been observed.';

  @override
  String get topoCheck => 'Check coupler';

  @override
  String get topoCheckHint =>
      'Reads addresses whose sending device sits behind a coupler. If it answers, the coupler forwards in both directions. Read requests only – nothing is switched.';

  @override
  String topoCheckRunning(int done, int total) {
    return 'Checking $done / $total …';
  }

  @override
  String topoCheckPassed(String source) {
    return 'Answered by $source';
  }

  @override
  String get topoCheckNoAnswer => 'no answer – filter table or read flag';

  @override
  String get topoCheckNone => 'No address with a sending device behind a coupler.';

  @override
  String get topoIssues => 'Findings';

  @override
  String get topoNoIssues => 'No findings in the traffic so far.';

  @override
  String topoMismatch(String source, int observed, int expected) {
    return '$source arrives with hop count $observed instead of $expected – probably sits in a different line than its address says.';
  }

  @override
  String topoUnneeded(String address, String name, int count) {
    return '$address $name: forwarded $count× from another line although nobody listens here per project. Often intended for visualisations (X1, Home Assistant), otherwise the coupler may forward everything.';
  }

  @override
  String get topoNoProject =>
      'The topology needs an ETS project (.knxproj) with devices; without a project only observed senders are shown.';

  @override
  String topoSends(String lines) {
    return 'sends $lines';
  }

  @override
  String topoListens(String lines) {
    return 'listens $lines';
  }

  @override
  String get topoCheckNoReadFlag => 'no answer, but telegrams pass the coupler – read flag missing';

  @override
  String get devSent => 'Sent';

  @override
  String get devReceived => 'Received';

  @override
  String get devGroups => 'Addresses';

  @override
  String get devReceivedHint => 'Telegrams to group addresses the device is linked to in the project.';

  @override
  String get devNoLinks => 'Not in the project – received telegrams cannot be assigned.';

  @override
  String get devNothing => 'No telegrams yet';

  @override
  String get devFilterMonitor => 'Filter in monitor';

  @override
  String devLineHops(String line, String hops) {
    return 'Line $line · hop $hops';
  }

  @override
  String get projectTitle => 'ETS project';

  @override
  String get historyDeleteConfirm => 'Delete the entire long-term history? This cannot be undone.';

  @override
  String get activityLastHour => 'last hour';

  @override
  String get activityToday => 'today';

  @override
  String get livePlainTitle => 'Plain text in Live';

  @override
  String get livePlainHint => 'Sentences instead of addresses';

  @override
  String get activityRangeHint => 'Tap to change the time range';

  @override
  String get boardValves => 'Valves & actuating values';

  @override
  String get diagOwnTunnel => 'This app\'s tunnel';

  @override
  String diagGatewayTunnel(String name) {
    return 'probably a tunnel of $name';
  }

  @override
  String get topoTunnels => 'Tunnels';

  @override
  String get mapOverview => 'Overview';

  @override
  String get mapGroups => 'Group addresses';

  @override
  String get mapDevices => 'Devices';

  @override
  String get commTitle => 'Commissioning';

  @override
  String get commTool => 'Read status addresses, check them off, PDF report';

  @override
  String get commExplain =>
      'Reads status and feedback addresses one by one (5 per second). Answers are checked off automatically; rate points without an answer or functions tested on site by hand. The list is kept until you start over.';

  @override
  String get commAnswered => 'Answered';

  @override
  String get commOk => 'OK';

  @override
  String get commNoAnswer => 'No answer';

  @override
  String get commIssue => 'Issue';

  @override
  String get commOpen => 'Open';

  @override
  String get commDone => 'Done';

  @override
  String get commFilterAll => 'All';

  @override
  String get commChecked => 'Checked';

  @override
  String get commStarted => 'Started';

  @override
  String get commPdfTitle => 'Commissioning report';

  @override
  String get commSignedBy => 'Checked by';

  @override
  String get commDate => 'Date';

  @override
  String get commSignature => 'Signature';

  @override
  String commStart(int count) {
    return 'Create and read ($count)';
  }

  @override
  String commReadOpen(int count) {
    return 'Read open ($count)';
  }

  @override
  String get commReadAll => 'Read all again';

  @override
  String get commReadOne => 'Read again';

  @override
  String get commReset => 'Reset';

  @override
  String get commNote => 'Note';

  @override
  String get commRestart => 'Start over';

  @override
  String get commRestartConfirm => 'Discard all results and notes and create a new checklist?';

  @override
  String get commNoProject => 'The checklist needs an ETS project with group addresses.';

  @override
  String get healthTitle => 'Health';

  @override
  String get healthTool => 'Read known addresses, check cycles, values and data types';

  @override
  String get healthExplain =>
      'Reads status addresses and everything that ever answered. Also: who usually sends regularly and is silent now? Are readings plausible? Do size and value match the DPT? How is the bus quality? New findings since the last run come first.';

  @override
  String healthRunNow(int count) {
    return 'Check now ($count addresses)';
  }

  @override
  String get healthPassive => 'Analyse only';

  @override
  String get healthAuto => 'Automatically after connecting (at most once a day)';

  @override
  String healthLastRun(String time) {
    return 'Last run $time';
  }

  @override
  String get healthNever => 'No run yet';

  @override
  String healthRunning(int sent, int total) {
    return 'Running … $sent of $total read';
  }

  @override
  String get healthAreaRead => 'Read test';

  @override
  String get healthAreaCycle => 'Cycles';

  @override
  String get healthAreaValues => 'Values';

  @override
  String get healthAreaDpt => 'Data types';

  @override
  String get healthAreaBus => 'Bus';

  @override
  String get healthAllGood => 'No findings';

  @override
  String get healthNewSection => 'New since last run';

  @override
  String healthAnswered(int answered, int asked) {
    return '$answered of $asked answer';
  }

  @override
  String get healthHistory => 'History';

  @override
  String get healthToCommissioning => 'Add to commissioning';

  @override
  String healthAddedToCommissioning(int count) {
    return '$count addresses added to commissioning';
  }

  @override
  String get healthPdfTitle => 'Health check';

  @override
  String healthNotifyTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new findings',
      one: '1 new finding',
    );
    return 'KNX: $_temp0';
  }

  @override
  String get healthNew => 'new';

  @override
  String get healthBits => '≤ 6 bits';

  @override
  String healthBytes(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'bytes', one: 'byte');
    return '$count $_temp0';
  }

  @override
  String healthNewSilent(String time) {
    return 'No longer answers – last $time';
  }

  @override
  String get healthAlwaysSilent => 'Never answered a read – check the read flag';

  @override
  String healthOverdue(String interval, String time) {
    return 'Usually sends every $interval, last $time';
  }

  @override
  String healthOutOfRange(String value, String sender) {
    return 'Implausible value $value from $sender';
  }

  @override
  String healthStuck(String value, String time) {
    return 'Unchanged $value since $time';
  }

  @override
  String healthDptSize(String sender, String actual, String dpt, String expected, int count) {
    return '$sender sends $actual, DPT $dpt expects $expected ($count×)';
  }

  @override
  String healthDptValue(String sender, String raw, int count) {
    return '$sender sends invalid value $raw ($count×)';
  }

  @override
  String healthMixedSizes(int count) {
    return 'No DPT in project – senders use $count different sizes';
  }

  @override
  String healthRepeats(String rate, int count) {
    return 'Repeats $rate % of $count telegrams – check acknowledgements';
  }

  @override
  String healthUnansweredReads(int count) {
    return '$count reads from other devices unanswered';
  }

  @override
  String get healthUnlinked => 'No device linked in the project – cannot answer (placeholder or leftover?)';

  @override
  String healthAlwaysSilentAt(String sender) {
    return 'Never answered – check the read flag on the sending object: $sender';
  }

  @override
  String get connectDemo => 'Try the demo without a KNX system';

  @override
  String get demoGateway => 'Demo house';

  @override
  String get demoNoBusmonitor => 'The bus monitor needs a real gateway – not available in demo mode.';

  @override
  String get menuGroupCheck => 'Check';

  @override
  String get menuGroupBus => 'Bus & network';

  @override
  String get menuGroupAnalyze => 'Analyse';

  @override
  String get menuGroupRecord => 'Record';

  @override
  String get menuGroupData => 'Data';

  @override
  String get menuGroupSettings => 'Settings';

  @override
  String get connectWithout => 'Without a connection';

  @override
  String get connectDemoShort => 'Try demo';

  @override
  String get connectProject => 'ETS project';

  @override
  String get errorTunnelAddressInUse => 'The requested tunnel address is in use.';

  @override
  String get errorTunnelAddressRejected => 'Gateway rejects the requested tunnel address.';

  @override
  String get errorLayerUnsupported => 'Gateway does not support this tunnel type (link layer/bus monitor).';

  @override
  String get connectModeUdp => 'UDP';

  @override
  String get connectModeTcp => 'TCP';

  @override
  String get connectModeRouting => 'Routing';

  @override
  String get connectModeSecure => 'Secure';

  @override
  String get connectModeUdpHint => 'Tunnel over UDP – works with every IP interface.';

  @override
  String get connectModeTcpHint => 'Tunnel over TCP (KNXnet/IP 2.0) – copes better with Wi-Fi dropouts.';

  @override
  String get connectModeRoutingHint =>
      'Multicast 224.0.23.12 via an IP router – uses no tunnel slot. Mind the router\'s filter tables.';

  @override
  String get connectModeSecureHint =>
      'Encrypted tunnel (KNX IP Secure). User and password are in ETS at the interface\'s tunnel.';

  @override
  String get connectTunnelAddress => 'Tunnel address (optional)';

  @override
  String get connectTunnelAddressHelp => 'Fixed address instead of any free slot; if taken, a free one is used.';

  @override
  String get connectRoutingAddress => 'Own address';

  @override
  String get connectAddressInvalid => 'Individual address like 1.1.240';

  @override
  String get connectSecureUser => 'User';

  @override
  String get connectSecurePassword => 'Password';

  @override
  String get connectSecureDeviceAuth => 'Device authentication code (optional)';

  @override
  String get connectSecureDeviceAuthHelp => 'Verifies that it is really your interface answering.';

  @override
  String routingUnavailable(String reason) {
    return 'Routing not possible: $reason';
  }

  @override
  String get addonTitle => 'Continuous recording in the add-on';

  @override
  String get addonPaused => 'Paused – the tunnel is free, e.g. for ETS.';

  @override
  String addonConnectedSince(String target, String time, int count) {
    return 'Connected to $target since $time · $count telegrams today';
  }

  @override
  String get addonConnecting => 'Add-on is connecting to the bus …';

  @override
  String get addonConnectionLost => 'Connection to the add-on lost.';

  @override
  String get boxAttaching => 'Connecting to the box …';

  @override
  String get boxConnecting => 'Box is connecting to the bus …';

  @override
  String get boxConnectionLost => 'Connection to the box lost.';

  @override
  String get addonDeviceBusy => 'Device is being checked in another view.';

  @override
  String get addonPause => 'Pause';

  @override
  String get addonResume => 'Resume';

  @override
  String get addonOpen => 'Open monitor';

  @override
  String get boxSection => 'KNX box';

  @override
  String get boxPair => 'Pair with KNX box';

  @override
  String get boxPairHint =>
      'Scan the box\'s QR code with the camera, or paste the pairing link or the box\'s IP address here. The link is also on the SD card as knx-box-link.txt.';

  @override
  String get boxPairField => 'Pairing link or IP address of the box';

  @override
  String get boxLinkInvalid => 'Not a valid pairing link.';

  @override
  String get boxPairTitle => 'Connect to KNX box?';

  @override
  String boxPairBody(String address) {
    return 'The app then shows the bus through the box $address. Only confirm if you scanned the QR code yourself.';
  }

  @override
  String boxVia(String name) {
    return 'Via KNX box $name';
  }

  @override
  String get boxGatewayHint => 'The gateway below is set on the box, which stays connected to it.';

  @override
  String get boxLeave => 'Gateway directly';

  @override
  String get boxForget => 'Forget box';

  @override
  String get boxNone => 'No KNX box paired.';

  @override
  String get boxUnauthorized => 'The box rejected access. Scan the box\'s QR code again.';

  @override
  String boxUnreachable(String address) {
    return 'KNX box $address not reachable. Is this device on the box\'s Wi-Fi?';
  }

  @override
  String get historyMaxSize => 'At most';

  @override
  String get historyWriteInterval => 'Write';

  @override
  String get historyWriteNow => 'immediately';

  @override
  String get historyWriteHint => 'Writing less often spares the SD card; a power cut then loses the last block.';

  @override
  String historyDeleteDayConfirm(String date) {
    return 'Delete history of $date?';
  }

  @override
  String outageOffline(String duration) {
    return 'Add-on not running for $duration';
  }

  @override
  String outageDisconnected(String duration) {
    return 'Bus disconnected for $duration';
  }

  @override
  String get secureAuthFailed => 'IP Secure: user or password rejected.';

  @override
  String get secureDeviceAuthFailed =>
      'IP Secure: device authentication code does not match – is it really your interface answering?';

  @override
  String get secureSessionClosed => 'Gateway closed the secure session.';

  @override
  String get secureNoCredentials => 'Enter a password or import a keyring for IP Secure.';

  @override
  String get keyringTitle => 'KNX Secure (keyring)';

  @override
  String get keyringImport => 'Import keyring';

  @override
  String get keyringPassword => 'Keyring password';

  @override
  String get keyringPasswordHint => 'The password set when exporting from ETS.';

  @override
  String get keyringWrongPassword => 'Wrong password.';

  @override
  String get keyringInvalid => 'Not a valid keyring file (.knxkeys).';

  @override
  String keyringLoaded(String project, int keys, int tunnels) {
    return '$project: $keys secured group addresses, $tunnels secure tunnels';
  }

  @override
  String get keyringNone => 'No keyring – Data Secure telegrams stay encrypted.';

  @override
  String get keyringNoneShort => 'Not loaded';

  @override
  String get keyringRemove => 'Remove keyring';

  @override
  String get keyringExplain => 'Keys stay on this device or in the add-on. In ETS: project → export → keyring.';

  @override
  String secureWithoutKeys(int count) {
    return '$count Data Secure telegrams without key – import the keyring to read them.';
  }

  @override
  String secureRejected(int count) {
    return '$count Data Secure telegrams rejected (invalid MAC or sequence number).';
  }

  @override
  String get connectModeHa => 'Home Assistant';

  @override
  String get connectModeHaHint =>
      'No own tunnel: the add-on reads what Home Assistant\'s KNX integration receives and sends through it. Device access (programming mode, address check, bus monitor) is not available this way.';

  @override
  String get connectModeHaAddonOnly => 'Only possible in the Home Assistant add-on.';

  @override
  String get connectModeHat => 'KNX HAT (kBerry)';

  @override
  String get connectModeHatHint =>
      'No gateway: the box is connected straight to the bus line through the KNX HAT (Weinzierl kBerry) on top.';

  @override
  String get connectModeHatBoxOnly => 'Only possible through the KNX Box with a KNX HAT.';

  @override
  String get connectHatAddress => 'Own address (optional)';

  @override
  String get connectHatAddressHelp =>
      'Leave empty to keep the module\'s address (15.15.255 from the factory). An address entered here is written to the module by the box.';

  @override
  String get connectHatBusmonitor => 'Bus monitor';

  @override
  String get connectHatBusmonitorHelp =>
      'All frames including acknowledgements (ACK/NAK/BUSY) for the bus monitor. The box then only listens: no reading or writing from the app.';

  @override
  String get filterOn => 'Turn filter on';

  @override
  String get filterOff => 'Turn filter off temporarily';

  @override
  String get filterContext => 'Context';

  @override
  String filterContextActive(int seconds) {
    return 'Context ±$seconds s';
  }

  @override
  String filterContextSeconds(int seconds) {
    return '±$seconds s around each match';
  }

  @override
  String get filterContextOff => 'Matches only';

  @override
  String get filterContextTooltip => 'Also show telegrams shortly before and after each match';

  @override
  String get writeFormatTime => 'Time';

  @override
  String get writeFormatDate => 'Date';

  @override
  String get writeFormatHvac => 'HVAC mode';

  @override
  String get writeFormatColor => 'Colour (RGB)';

  @override
  String get writeNow => 'Now';

  @override
  String get sendDelay => 'Delay';

  @override
  String get sendRepeat => 'Repeat';

  @override
  String get sendNow => 'now';

  @override
  String get sendOnce => 'once';

  @override
  String sendEverySeconds(int seconds) {
    return 'every $seconds s';
  }

  @override
  String sendEveryMinutes(int minutes) {
    return 'every $minutes min';
  }

  @override
  String get sendScheduled => 'Scheduled sends';

  @override
  String get sendStopAll => 'Stop all';

  @override
  String get sendStop => 'Stop';

  @override
  String sendCount(int count) {
    return 'sent $count×';
  }

  @override
  String sendNext(String time) {
    return 'next $time';
  }

  @override
  String get dptChoose => 'Set datapoint type';

  @override
  String get dptOverridden => 'Datapoint type set manually – change';

  @override
  String dptChooseTitle(String address) {
    return 'Datapoint type for $address';
  }

  @override
  String dptFromProject(String dpt) {
    return 'As in project ($dpt)';
  }

  @override
  String get dptNone => 'No datapoint type (guess)';

  @override
  String get deviceGeneral => 'General';

  @override
  String get deviceOn => 'On';

  @override
  String get deviceOff => 'Off';

  @override
  String deviceChannelSemantics(String channel, String state) {
    return 'Channel $channel: $state';
  }

  @override
  String get heatmapTitle => 'Activity by weekday and hour';

  @override
  String get heatmapEmpty => 'No telegrams yet';

  @override
  String heatmapPeak(String day, int hour, int count) {
    return 'Most telegrams: $day $hour:00 ($count)';
  }

  @override
  String get statsLongTerm => 'Long term (continuous recording)';

  @override
  String statsLongTermTotal(String count) {
    return '$count telegrams in range';
  }

  @override
  String get statsLongTermUnavailable => 'Analysis not available (update the add-on?).';

  @override
  String get chartsTitle => 'Charts';

  @override
  String get toolCharts => 'Compare several values over time';

  @override
  String get chartsAdd => 'Choose addresses';

  @override
  String get chartsMore => 'More';

  @override
  String get chartsEmpty => 'Choose group addresses with numeric values – up to 8, one axis per unit.';

  @override
  String get chartsSaveSelection => 'Save as chart';

  @override
  String get chartsSelectionName => 'Name';

  @override
  String get chartsExportPng => 'As image (PNG)';

  @override
  String get chartsExportCsv => 'As table (CSV)';

  @override
  String get chartsClear => 'Remove all';

  @override
  String get chartsResize => 'Drag to resize charts';

  @override
  String get diagnosticsBundle => 'Diagnostics bundle for bug report';

  @override
  String get aboutLicenses => 'About KNX Monitor and licenses';

  @override
  String get aboutLegalese => '© 2026 regetskcob. All rights reserved.';

  @override
  String get aboutSender => 'a project by regetskcob';

  @override
  String get hzCSeverityOk => 'OK';

  @override
  String get hzCSeverityInfo => 'Note';

  @override
  String get hzCSeverityWarning => 'Warning';

  @override
  String get hzCSeverityError => 'Error';

  @override
  String get hzCRecordingLive => 'Recording';

  @override
  String get sidebarShow => 'Show sidebar';

  @override
  String get sidebarHide => 'Hide sidebar';

  @override
  String get hzFLegend => 'Legend';

  @override
  String get hzFReceived => 'Value received';

  @override
  String get hzFNoTelegram => 'No telegram yet';

  @override
  String get hzFDetected => 'Recognized by the shared name prefix';

  @override
  String hzHCouplerOpen(String address) {
    return 'Coupler $address, show traffic';
  }

  @override
  String hzHLinePair(String a, String b) {
    return 'Line $a ↔ $b';
  }

  @override
  String hzHFlow(String from, String to) {
    return 'Line $from → $to';
  }

  @override
  String get hzHFlowHint =>
      'From a line means the source address lies there. To a line means devices there listen according to the project. Whether the coupler really forwards is only visible to the gateway for telegrams that reach it.';

  @override
  String get hzHSeenAtGateway => 'Seen at gateway';

  @override
  String get hzHWithoutReceiver => 'without receiver';

  @override
  String get hzHFlowEmpty => 'According to the project no group address crosses this coupler.';

  @override
  String get hzHAllDirections => 'All directions';

  @override
  String get hzHFilterHint => 'filter in monitor';

  @override
  String get hzHCouplerUnknown => 'Coupler not in project';

  @override
  String hzHCouplerKennung(String address, String lines) {
    return 'Coupler $address · $lines';
  }

  @override
  String get columnHop => 'Hop';

  @override
  String get menuTitle => 'Menu';

  @override
  String get quickFilterButton => 'Filter';

  @override
  String hzHFlowTelegrams(String from, String to) {
    return 'Telegrams $from → $to';
  }

  @override
  String get heatmapActivity => 'Activity';

  @override
  String get heatmapPerMinute => 'per minute';

  @override
  String get heatmapPerFiveMinutes => 'per 5 minutes';

  @override
  String get heatmapPerHour => 'per hour';

  @override
  String get heatmapWeekly => 'by weekday and hour';

  @override
  String heatmapPeakAt(String time, int count) {
    return 'Most telegrams: $time ($count)';
  }

  @override
  String recordingStartHint(int seconds) {
    return 'Start recording – long press: include the last $seconds s';
  }

  @override
  String recordingPreRoll(int seconds) {
    return 'Record including the last $seconds s';
  }

  @override
  String recordingPreRollStarted(int seconds) {
    return 'Recording – includes the last $seconds s';
  }

  @override
  String get replayMenu => 'Send to the bus …';

  @override
  String get replayTitle => 'Send to the bus';

  @override
  String get replayWarning =>
      'The write telegrams are really sent: actuators switch, blinds move. Only with an eye on the installation.';

  @override
  String replayOtherGateway(String recorded, String current) {
    return 'Recorded at $recorded, sending to $current.';
  }

  @override
  String get replayNoWrites => 'The recording contains no write telegrams.';

  @override
  String replayShorten(int seconds) {
    return 'Shorten pauses to $seconds s';
  }

  @override
  String get replayShortenHint => 'Off: original timing of the recording';

  @override
  String replaySend(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Send $count telegrams',
      one: 'Send 1 telegram',
    );
    return '$_temp0';
  }

  @override
  String get replayConfirmTitle => 'Really send to the bus?';

  @override
  String replayConfirmText(int count, int addresses, String gateway) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count write telegrams',
      one: '1 write telegram',
    );
    String _temp1 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses group addresses',
      one: '1 group address',
    );
    return '$_temp0 to $_temp1 via $gateway. This cannot be undone.';
  }

  @override
  String get replayRunning => 'Sending …';

  @override
  String get replayDone => 'All sent';

  @override
  String get replayStopped => 'Stopped';

  @override
  String replayFailed(String message) {
    return 'Aborted: $message';
  }

  @override
  String get replaySent => 'Sent';

  @override
  String get replayUnconfirmed => 'Not acknowledged';

  @override
  String get replayTotal => 'Total';

  @override
  String get replayStop => 'Stop';

  @override
  String get replayTelegrams => 'Telegrams';

  @override
  String get replayEditHint => 'Tap to change the value, × removes the telegram. The original stays unchanged.';

  @override
  String get replayReset => 'Reset';

  @override
  String get replaySaveCopy => 'Save as copy';

  @override
  String replayCopyName(String name) {
    return '$name · edited';
  }

  @override
  String get replayEdited => 'Edited';

  @override
  String get replayRemove => 'Remove';

  @override
  String get replayInvalidValue => 'Invalid value';

  @override
  String get replayHexHint => 'Bytes in hex, e.g. 0C 1A';

  @override
  String get chartNoValues => 'No numeric values for a chart yet.';

  @override
  String get chartName => 'Chart name';

  @override
  String get chartRename => 'Rename';

  @override
  String get chartDelete => 'Delete chart';

  @override
  String get chartDeleteTitle => 'Delete chart?';

  @override
  String chartDeleteText(String name) {
    return '“$name” will be removed. The data stays.';
  }

  @override
  String pickerApply(int count) {
    return 'Apply · $count';
  }

  @override
  String get pickerEmpty => 'Nothing matches the filter.';

  @override
  String get replayPickTitle => 'Addresses to send';

  @override
  String replayAddressesAll(int count) {
    return 'All $count addresses · choose';
  }

  @override
  String replayAddressesSome(int count, int total) {
    return '$count of $total addresses · change';
  }

  @override
  String get chartNew => 'New chart';

  @override
  String get chartDefaultName => 'Chart';

  @override
  String get commFilterNoAnswer => 'Silent';

  @override
  String get chartsSaved => 'Saved';

  @override
  String get chartsOverviewEmpty => 'No charts yet';

  @override
  String get chartsOverviewEmptyDetail =>
      'Use “New chart” to pick addresses from all sections and save them under a name. The chart then also appears on the overview.';

  @override
  String get chartTemplates => 'Templates';

  @override
  String get chartTemplatesIntro =>
      'Detected from your project. “Adopt” turns one into your own chart that you can change.';

  @override
  String get chartTemplatesTrafficIntro =>
      'From the live traffic. With an ETS project you also get templates per room.';

  @override
  String get chartTemplateAdopt => 'Adopt';

  @override
  String get chartTemplateAdopted => 'Adopted';

  @override
  String get chartTemplatesAdoptAll => 'Adopt all';

  @override
  String chartTemplateAdoptedSnack(String name) {
    return '“$name” adopted';
  }

  @override
  String chartTemplatesAdoptedSnack(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count charts adopted',
      one: '1 chart adopted',
    );
    return '$_temp0';
  }

  @override
  String get chartRecipeClimate => 'Room climate';

  @override
  String get chartRecipeAir => 'Air';

  @override
  String get chartRecipeLight => 'Light & presence';

  @override
  String get chartRecipeShading => 'Shading';

  @override
  String get chartRecipeWeather => 'Weather';

  @override
  String get chartRecipeEnergy => 'Energy';

  @override
  String get chartRecipeTraffic => 'From traffic';

  @override
  String get busMetricTelegrams => 'Telegrams/min';

  @override
  String get busMetricRepeats => 'Repeats/min';

  @override
  String busMetricLine(String line) {
    return 'Line $line';
  }

  @override
  String get chartRecipeBus => 'Bus';

  @override
  String get chartBusOverall => 'Overall';

  @override
  String get chartBusLines => 'Lines';

  @override
  String get chartShareTemplate => 'Share as template';

  @override
  String get chartShareTemplateEmpty => 'No series with a recognisable role – the template would be empty.';

  @override
  String chartShareTemplateDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count series without a recognisable role are not in the template.',
      one: '1 series without a recognisable role is not in the template.',
    );
    return '$_temp0';
  }

  @override
  String get chartTemplateImport => 'Import template';

  @override
  String chartTemplateImported(String name) {
    return 'Template “$name” imported';
  }

  @override
  String chartTemplateImportedNoMatch(String name) {
    return 'Template “$name” imported – it does not match any address in this installation yet.';
  }

  @override
  String get chartTemplateImportFailed => 'Not a valid chart template.';

  @override
  String get chartTemplateRemove => 'Remove template';

  @override
  String get chartTemplateNoMatch => 'Does not match any address in this installation yet.';

  @override
  String get boxAdd => 'Add KNX box';

  @override
  String get boxScanTitle => 'Box QR code';

  @override
  String get boxScanHint => 'Hold the QR code from the box\'s label inside the frame.';

  @override
  String get boxScanManual => 'Paste link or enter address';

  @override
  String get boxScanNoCamera => 'No camera available.';

  @override
  String get boxSetupTitle => 'Set up KNX box';

  @override
  String boxStepWifi(String ssid) {
    return 'Join Wi-Fi $ssid';
  }

  @override
  String boxStepWifiManual(String ssid) {
    return 'Join the Wi-Fi $ssid in Settings and come back.';
  }

  @override
  String get boxStepWifiDenied => 'Joining the Wi-Fi was declined.';

  @override
  String get boxStepReach => 'Reach the box';

  @override
  String get boxStepReachFailed => 'The box does not answer. Is it switched on and this device in its Wi-Fi?';

  @override
  String get boxStepPair => 'Pair with the box';

  @override
  String get boxStepTime => 'Set the box clock';

  @override
  String get boxStepTimeDiffers => 'The box clock is off; check it in the box settings.';

  @override
  String get boxStepGateway => 'Find the gateway on the box\'s cable';

  @override
  String boxStepGatewayFound(String host) {
    return 'Gateway $host set';
  }

  @override
  String get boxStepGatewayChoose => 'Choose the gateway on the connect screen';

  @override
  String get boxSetupRetry => 'Try again';

  @override
  String get boxSetupDone => 'Done';

  @override
  String get boxSettings => 'Box settings';

  @override
  String get boxClock => 'Clock';

  @override
  String get boxClockNone => 'No reliable time';

  @override
  String get boxClockRtc => 'The box\'s battery clock (RTC)';

  @override
  String get boxClockKnx => 'KNX time master on the line';

  @override
  String get boxClockClient => 'Set from an iPhone or iPad';

  @override
  String get boxClockNtp => 'Internet (NTP)';

  @override
  String boxClockOffset(String source, String offset) {
    return '$source is off by $offset.';
  }

  @override
  String get boxClockSetNow => 'Set from this device';

  @override
  String get boxClockFromKnx => 'Set clock from KNX time master';

  @override
  String get boxClockFromKnxHint =>
      'Date and time from the line (DPT 19.001 or 10.001 + 11.001) when no more reliable source is there.';

  @override
  String get boxRecordOnlyWithTime => 'Record only once the time is right';

  @override
  String get boxRecordOnlyWithTimeHint => 'Otherwise the box records at once and puts the time right afterwards.';

  @override
  String boxWaiting(int count) {
    return '$count telegrams not recorded without a time';
  }

  @override
  String get boxTimeAskTitle => 'Box clock is off';

  @override
  String boxTimeAskBody(String offset) {
    return 'The box clock is $offset off from this device. Set it from this device?';
  }

  @override
  String get boxDevices => 'Paired devices';

  @override
  String get boxDeviceSelf => 'this device';

  @override
  String get boxDeviceAdmin => 'manages the box';

  @override
  String get boxDeviceRevoke => 'Revoke';

  @override
  String get boxPasswordChange => 'Change box password';

  @override
  String get boxPasswordHint => 'At least 8 characters. The label\'s QR code no longer pairs new devices afterwards.';

  @override
  String get boxPasswordChanged => 'Password changed.';

  @override
  String get boxNotAdmin => 'Managing needs the box password: scan the QR code on the label.';

  @override
  String get installationsTitle => 'Installations';

  @override
  String get installationNew => 'New installation';

  @override
  String get installationName => 'Installation name';

  @override
  String get installationNameHint => 'e.g. Miller residence, office, home';

  @override
  String get installationRename => 'Rename';

  @override
  String installationDeleteTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get installationDeleteBody =>
      'The ETS project, keyring, health, commissioning, acceptance protocols, service reports, customer data, long-term history and settings of this installation are removed. Recordings are kept.';

  @override
  String get installationNoGateway => 'No gateway yet';

  @override
  String get installationActive => 'Active';

  @override
  String installationSwitched(String name) {
    return 'Installation “$name”';
  }

  @override
  String installationGatewayElsewhere(String name) {
    return 'This gateway belongs to “$name”.';
  }

  @override
  String get installationSwitch => 'Switch';

  @override
  String get installationUnassigned => 'Unassigned';

  @override
  String get installationAll => 'All';

  @override
  String get installationBoxRecording => 'KNX box records here';

  @override
  String get installationHistoryOf => 'History of';

  @override
  String get installationDeleteOnBox => 'Also on the KNX box, including its long-term history.';

  @override
  String get boxRecordingTitle => 'Continuous recording on the KNX box';

  @override
  String get planTitle => 'Plus and Pro';

  @override
  String planFeatureLocked(String feature, String tier) {
    return '“$feature” is part of $tier.';
  }

  @override
  String planCurrent(String tier) {
    return 'Current plan: $tier';
  }

  @override
  String get planActive => 'Active';

  @override
  String get planPlusPitch =>
      'For your own installation: watchers with sound, history, charts, statistics, alarms and export.';

  @override
  String get planProPitch => 'For commissioning and troubleshooting: every tool for professionals, without limits.';

  @override
  String get planUnlimitedRecordings => 'Unlimited recordings';

  @override
  String planInstallations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'up to $count installations',
      one: '1 installation',
    );
    return '$_temp0';
  }

  @override
  String get planUnlimitedInstallations => 'Unlimited installations';

  @override
  String planPerYear(String price) {
    return '$price per year';
  }

  @override
  String planPerMonth(String price) {
    return '$price per month';
  }

  @override
  String planOnce(String price) {
    return '$price one-time';
  }

  @override
  String get planRestore => 'Restore purchases';

  @override
  String planRestored(String tier) {
    return 'Purchases restored: $tier.';
  }

  @override
  String get planNothingRestored => 'No previous purchases found.';

  @override
  String get planNoOffers => 'The offers can’t be loaded right now. Please check your internet connection.';

  @override
  String planBuyFailed(String error) {
    return 'The purchase didn’t go through: $error';
  }

  @override
  String planThanks(String tier) {
    return 'Thank you! $tier is unlocked.';
  }

  @override
  String get planLegal => 'Subscriptions renew automatically and can be cancelled at any time in your store settings.';

  @override
  String get planTerms => 'Terms of use';

  @override
  String get planPrivacy => 'Privacy';

  @override
  String planMoreInstallations(String tier, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count installations',
      one: 'one installation',
    );
    return '$tier includes $_temp0.';
  }

  @override
  String get planMoreRecordings => 'Free keeps one recording. Plus keeps as many as you like.';

  @override
  String get planLongHistory => 'Long-term history comes with Plus. Free shows the last hour in the monitor.';

  @override
  String get planAllOfPlus => 'Everything in Plus, too';

  @override
  String get planBetaTitle => 'Beta: Pro unlocked';

  @override
  String planBetaBody(int months) {
    return 'Thanks for testing! Everything is unlocked in the beta. When KNX Monitor launches on the App Store, this device gets $months months of Pro as a thank-you.';
  }

  @override
  String get planBetaStoreOn => 'Paywall as in the store (sandbox)';

  @override
  String get planBetaStoreOff => 'Beta unlock active again';

  @override
  String planLapsed(String tier) {
    return '$tier works offline for 30 days. That period has run out – connect this device to the internet once and $tier is back right away.';
  }

  @override
  String planBetaReward(String date) {
    return 'Beta thank-you: Pro until $date';
  }

  @override
  String get planManage => 'Manage or cancel subscription';

  @override
  String planTrial(int days, String price) {
    return '$days days free, then $price';
  }

  @override
  String get planFeatureReplay => 'Replay recordings to the bus';

  @override
  String get planFeatureScheduled => 'Delayed and cyclic sending';

  @override
  String healthShowNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'Show $count notes', one: 'Show 1 note');
    return '$_temp0';
  }

  @override
  String get healthHideNotes => 'Hide notes';

  @override
  String get objectReadFeedbacks => 'Read feedbacks';

  @override
  String objectReadSent(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count read requests sent',
      one: '1 read request sent',
    );
    return '$_temp0';
  }

  @override
  String get busmonListening => 'Listening on the line …';

  @override
  String get busmonQuietHint =>
      'No frame for 15 seconds. If the line is quiet, press a switch or use “Read” to cause traffic. Some IP interfaces deliver nothing in bus monitor mode; the live monitor still works then.';

  @override
  String menuMoreTools(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more tools in expert mode',
      one: '1 more tool in expert mode',
    );
    return '$_temp0';
  }

  @override
  String get menuMoreToolsHint => 'Bus monitor, diagnostics, commissioning, topology and more';

  @override
  String get toolObjects => 'Rooms and objects from the ETS project, commands next to feedbacks';

  @override
  String topoRail(String line) {
    return 'Cabinet · line $line';
  }

  @override
  String get topoFlows => 'Traffic between lines';

  @override
  String get topoFlowsHint =>
      'Telegrams per direction: sender in one line, receivers in the other according to the project.';

  @override
  String topoFlowRow(String telegrams, int groups) {
    return '$telegrams telegrams · $groups addresses';
  }

  @override
  String get topoFlowsNone => 'No traffic across the couplers yet.';

  @override
  String get topoLive => 'Across the couplers, live';

  @override
  String get topoLiveNone => 'No telegrams across the couplers yet.';

  @override
  String topoRailMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more devices',
      one: '1 more device',
    );
    return '$_temp0';
  }

  @override
  String get topoRailLess => 'Show fewer';

  @override
  String get topoGroupValue => 'Value';

  @override
  String get topoGroupLines => 'Lines';

  @override
  String get topoGroupDetails => 'History & write';

  @override
  String get topoGroupUnlinked => 'Heard, not linked in the project';

  @override
  String get topoGroupRecent => 'Recent telegrams';

  @override
  String get topoGroupChannel => 'Channel';

  @override
  String get topoGroupHeard => 'heard';

  @override
  String get topoGroupSends => 'sends';

  @override
  String get topoGroupListens => 'listens';

  @override
  String get topoGroupChannels => 'Channels';

  @override
  String buttonKeySemantics(String key, String state) {
    return 'Key $key: $state';
  }

  @override
  String buttonLastPress(String key, String value, String time) {
    return 'Last pressed: $key → $value · $time';
  }

  @override
  String get buttonNoPress => 'No key press since connecting';

  @override
  String buttonPage(String page, String count) {
    return 'Level $page of $count';
  }

  @override
  String get watchTitle => 'Watcher';

  @override
  String watchHit(String what) {
    return 'Watcher: $what';
  }

  @override
  String get watchAdd => 'Watch this address';

  @override
  String get watchRemove => 'Remove watcher';

  @override
  String watchAdded(String what) {
    return 'Watcher armed: $what';
  }

  @override
  String get watchTool => 'Sound and notification when an address is sent';

  @override
  String get watchExplain =>
      'A watcher alerts you with a sound and a notification as soon as its group address is sent – optionally only for a certain value. It listens while the monitor is connected; on iPhone and iPad the screen stays on for that.';

  @override
  String get watchEmpty => 'No watchers yet. Add one, or tap the bell in an address’s details.';

  @override
  String get watchNew => 'New watcher';

  @override
  String get watchSound => 'With sound';

  @override
  String get watchInvalid => 'Please enter a group address like 1/2/3.';

  @override
  String get accountUseEverywhere => 'Use on other devices';

  @override
  String accountSignedInAs(String email) {
    return 'Signed in as $email';
  }

  @override
  String accountFailed(String error) {
    return 'Sign-in failed: $error';
  }

  @override
  String get planCheckoutOpened => 'The checkout is open in your browser. After buying, tap “Restore purchases” here.';

  @override
  String get planPendingApproval =>
      'This purchase is waiting for approval, for example through Ask to Buy or the payment method. Your plan unlocks as soon as it is confirmed.';

  @override
  String get planNotYetAvailable => 'Plus and Pro aren’t available here yet.';

  @override
  String planOpenNotice(String date) {
    return 'Everything was free until now. There are now Free, Plus and Pro: You keep Pro until $date, then Free applies. Your data stays where it is.';
  }

  @override
  String get planOpenEnded =>
      'The transition period is over and Free applies now. Your data stays where it is. Plus or Pro bring the tools back.';

  @override
  String get planSignInToBuy => 'Sign in to buy';

  @override
  String get diagTitle => 'Diagnostics package';

  @override
  String get diagTool => 'Send a problem with recording and project to support';

  @override
  String get diagIntro =>
      'The package helps support reproduce your problem: bus recording, project, your description and technical details in one ZIP file. It may relate to people: check what is in it before sending.';

  @override
  String get diagProblemLabel => 'What happened?';

  @override
  String get diagProblemHint => 'e.g. kitchen light does not react to the push button';

  @override
  String get diagExpectedLabel => 'What did you expect? (optional)';

  @override
  String diagOccurred(String time) {
    return 'Time of the problem: $time';
  }

  @override
  String get diagSourceLabel => 'Bus recording';

  @override
  String diagSourceSession(int count) {
    return 'Current session · $count telegrams';
  }

  @override
  String get diagRangeLabel => 'Time range around the problem';

  @override
  String get diagRangeAll => 'All';

  @override
  String diagRangeMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get diagRangeHint => 'Minutes before the problem (for a recording, before its end).';

  @override
  String get diagNamesTitle => 'Include names';

  @override
  String diagNamesHint(String examples) {
    return 'Names of group addresses and devices, e.g. $examples. They help with the analysis; without them only addresses and products remain.';
  }

  @override
  String get diagNamesHintEmpty =>
      'Names of group addresses and devices help with the analysis; without them only addresses and products remain.';

  @override
  String get diagContents => 'Contents';

  @override
  String diagContentRecording(int count, String from, String to) {
    return 'Bus recording: $count telegrams, $from – $to';
  }

  @override
  String diagContentSecure(int count) {
    return 'Data Secure: $count telegrams with time and addresses only, without content';
  }

  @override
  String diagContentProject(int groups, int devices) {
    return 'Project: $groups group addresses, $devices devices, datapoint types and links';
  }

  @override
  String get diagContentNamesIn => 'Names of group addresses and devices: included';

  @override
  String get diagContentNamesOut => 'Names of group addresses and devices: removed';

  @override
  String get diagContentTechnical =>
      'Technical: app version, platform and OS, connection type, gateway type and name, plan, expert mode, language, settings';

  @override
  String diagContentLog(int count) {
    return 'App messages: $count lines';
  }

  @override
  String get diagExcluded =>
      'Not included: passwords, keyring and keys, the ETS project file. Removed from texts where recognisable: IP addresses, host names, MAC and serial numbers, email, known names of project, installation, customer and company.';

  @override
  String get diagShowFile => 'View file contents';

  @override
  String get diagShare => 'Share package';

  @override
  String get diagSave => 'Save package';

  @override
  String get diagDownload => 'Download package';

  @override
  String get diagPackageInvalid => 'Not a KNX Monitor diagnostics package.';

  @override
  String get diagPackageNewer => 'The diagnostics package comes from a newer app version.';

  @override
  String get diagImportDisconnect => 'Disconnect first to open a diagnostics package.';

  @override
  String diagImported(String name) {
    return 'Diagnostics package opened as installation “$name”.';
  }

  @override
  String get diagImportedRecordingOnly => 'Recording imported. The package\'s project can only be loaded in the apps.';

  @override
  String diagNoteProblem(String text) {
    return 'What happened: $text';
  }

  @override
  String diagNoteExpected(String text) {
    return 'Expected: $text';
  }

  @override
  String diagInstallationName(String date) {
    return 'Diagnostics $date';
  }

  @override
  String get diagImportHint => 'Import: ETS telegram file (.xml) or diagnostics package (.zip)';

  @override
  String get filterActive => 'Filtered';

  @override
  String get watchContains => 'contains';

  @override
  String get watchCondition => 'Condition';

  @override
  String get watchAnyValue => 'any value';

  @override
  String get watchValueExample => 'e.g. On or 20';

  @override
  String get watchAddressHint => '1/2/3 or name';

  @override
  String get watchCreate => 'Create';

  @override
  String get connectModeLabel => 'Connection type';

  @override
  String get commNextOpen => 'Next open item';

  @override
  String get commLinked => 'Linked devices';

  @override
  String deviceSendValue(String value, String address) {
    return 'Send $value to $address';
  }

  @override
  String checkFindings(int n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: '$n findings', one: '1 finding');
    return '$_temp0';
  }

  @override
  String get topoRailActuators => 'Distribution board';

  @override
  String get topoRailSensors => 'Sensors';

  @override
  String get monitorLeaveTitle => 'Disconnect?';

  @override
  String get monitorLeaveText =>
      'Going back to the start page disconnects from the gateway. Recordings and watchers stop.';

  @override
  String get checkSectionTraffic => 'Bus traffic';

  @override
  String get checkSectionProject => 'Project';

  @override
  String get checkStatusNoTransmit => 'Status without T flag';

  @override
  String get checkStatusNoTransmitHint =>
      'No object with the T flag sends on this status address – the status never reaches the bus.';

  @override
  String get checkMultipleSenders => 'Multiple senders';

  @override
  String get checkMultipleSendersHint =>
      'Several objects send to the same address. Intended for push buttons, sensors and visualisations; usually a mistake for actuator channels.';

  @override
  String get checkReadNoReadFlag => 'Read without R flag';

  @override
  String get checkReadNoReadFlagHint =>
      'Status reads and commissioning query these addresses. Without an object with the R flag the request stays unanswered.';

  @override
  String get checkDevicesNoLinks => 'Devices without links';

  @override
  String get checkDevicesNoLinksHint =>
      'No object of these devices has a group address – unfinished or superfluous. Couplers and tunnels are not counted.';

  @override
  String get checkObjectsNoComm => 'Objects without C flag';

  @override
  String get checkObjectsNoCommHint =>
      'The object has an address but no C flag – it does not take part in bus traffic.';

  @override
  String get checkIncomplete => 'Without name or datapoint type';

  @override
  String get checkIncompleteHint =>
      'Without a name and datapoint type, the monitor, diagnostics and the ETS group monitor only show the address and raw value. Add both in ETS.';

  @override
  String get checkNoName => 'no name';

  @override
  String get checkMultipleReadAnswers => 'R flag on several objects';

  @override
  String get checkMultipleReadAnswersHint =>
      'Several objects with the R flag all answer a read request, possibly with different values. Only the object that holds the state should have the R flag.';

  @override
  String get checkWithoutSender => 'No sender';

  @override
  String get checkWithoutSenderHint =>
      'No object in the project sends to this address. Usually a visualisation, logic or panel without a placeholder in the project – its telegrams then show up without a name – otherwise a forgotten link.';

  @override
  String get checkWithoutReceiver => 'No receiver';

  @override
  String get checkWithoutReceiverHint =>
      'No object with C and W flags listens to this address – telegrams sent to it have no effect.';

  @override
  String get checkCrowdedLines => 'Crowded lines';

  @override
  String checkCrowdedLinesHint(int limit) {
    return 'More than $limit devices: the line has little reserve for extensions and bus current. A line segment carries at most 64 devices.';
  }

  @override
  String checkLineDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count devices', one: '1 device');
    return '$_temp0';
  }

  @override
  String get checkMainGroup1415 => 'Main group 14 or 15';

  @override
  String get checkMainGroup1415Hint =>
      'Older line couplers do not keep these main groups in the filter table and either block them or always pass them on. Main groups 0–13 are safer for addresses used across lines.';

  @override
  String get checkCentralOffOn => 'Central off with on';

  @override
  String get checkReimport => 'Re-import the ETS project to read the flags';

  @override
  String get flagLetters => 'CRWTU';

  @override
  String get flagsNone => 'no flags';

  @override
  String get healthNothingToRead =>
      'No address to read yet: without an ETS project, Health checks the traffic it has heard. With a project it also reads every status address.';

  @override
  String get commOkManual => 'Marked OK';

  @override
  String get importReading => 'Reading file …';

  @override
  String get importOpening => 'Opening project …';

  @override
  String get importDecrypting => 'Decrypting and reading project …';

  @override
  String get importSaving => 'Saving project …';

  @override
  String get importSlowHint => 'Large projects can take up to a minute in the browser.';

  @override
  String get addonAttaching => 'Connecting to the add-on …';

  @override
  String get watchWithSound => 'with sound';

  @override
  String get watchSilent => 'silent';

  @override
  String get watchActive => 'Watcher active';

  @override
  String get watchExplainServer =>
      'A watcher reports as soon as its group address is sent – optionally only for a certain value. The add-on checks it even without an open app and sends a Home Assistant notification; an open monitor also plays the sound.';

  @override
  String get boardNoTelegramYet => 'No telegram yet';

  @override
  String get chartsNoValuesYet => 'no values yet';

  @override
  String get chartsWaiting => 'Waiting for the first telegrams – the series appear as soon as the addresses send.';

  @override
  String checkEvaluatedTelegrams(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count telegrams evaluated',
      one: '1 telegram evaluated',
    );
    return '$_temp0';
  }

  @override
  String diagSourceHistory(String date) {
    return 'Long-term history $date';
  }

  @override
  String get annotationTitle => 'Comment';

  @override
  String get annotationEditTitle => 'Edit comment';

  @override
  String get annotationNoteLabel => 'What happened?';

  @override
  String get annotationNoteHint => 'Pressed a third time: the light stays off';

  @override
  String get annotationEmpty => 'Write briefly what happened, or add a screenshot.';

  @override
  String get annotationDelete => 'Delete comment';

  @override
  String get annotationAdd => 'Comment';

  @override
  String annotationAboutTime(String time) {
    return 'At $time';
  }

  @override
  String annotationAboutChart(String names) {
    return 'Chart $names';
  }

  @override
  String get annotationsLabel => 'Comments';

  @override
  String get annotationsTitle => 'Comments';

  @override
  String get annotationsTool => 'What you noticed in telegrams and history';

  @override
  String get annotationsEmpty =>
      'No comments yet. Tap a telegram and choose “Comment”, or add one at the crosshair in a chart.';

  @override
  String get shotsLabel => 'Screenshots';

  @override
  String get shotsAdd => 'Add screenshot';

  @override
  String shotsHint(int max) {
    return 'Up to $max, downscaled. Check first that they show no addresses, names or passwords you do not want to pass on.';
  }

  @override
  String shotsInvalid(String name) {
    return '$name is not a readable image.';
  }

  @override
  String get shotsQuota => 'The space for screenshots is full. Delete older comments with images to add new ones.';

  @override
  String get shotsOpen => 'Show screenshot';

  @override
  String get shotsRemove => 'Remove screenshot';

  @override
  String get timelineTitle => 'Timeline';

  @override
  String get timelineHint =>
      'Drag to move, Ctrl or Cmd with the wheel or two fingers to zoom. Point at a telegram to see it, tap to comment. Tap the time axis to move playback there.';

  @override
  String get timelineEmpty => 'This recording contains no telegrams.';

  @override
  String get timelineNoAnnotations => 'No comments in this period yet. Tap a telegram or a spot on the timeline.';

  @override
  String get timelineRepeated => 'Repeat';

  @override
  String timelineSemantics(int telegrams, int notes) {
    return 'Timeline with $telegrams telegrams and $notes comments';
  }

  @override
  String chartsAnnotate(String time) {
    return 'Comment at $time';
  }

  @override
  String get chartsAnnotateHint => 'Pick a point in the chart to comment';

  @override
  String diagAnnotationsInRange(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comments in this period are included',
      one: '1 comment in this period is included',
      zero: 'No comments in this period',
    );
    return '$_temp0';
  }

  @override
  String diagOlderAnnotations(int count) {
    return 'Include older comments ($count)';
  }

  @override
  String diagOlderAnnotationsHint(int days) {
    return 'From the last $days days, outside the recording, with their telegram';
  }

  @override
  String diagContentAnnotations(int notes, int shots) {
    String _temp0 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes comments',
      one: '1 comment',
      zero: 'No comments',
    );
    String _temp1 = intl.Intl.pluralLogic(
      shots,
      locale: localeName,
      other: '$shots screenshots',
      one: '1 screenshot',
      zero: 'no screenshots',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String diagLarge(int mb) {
    return 'The package is $mb MB and may not fit as an email attachment.';
  }

  @override
  String diagRangeSince(String time) {
    return 'Period: since the start at $time';
  }

  @override
  String get findingsTitle => 'Findings';

  @override
  String get findingsProblem => 'Problem';

  @override
  String get findingsNoProblem => 'No description';

  @override
  String findingsExpected(String text) {
    return 'Expected: $text';
  }

  @override
  String findingsOccurred(String time) {
    return 'Occurred $time';
  }

  @override
  String get findingsHints => 'Hints';

  @override
  String get findingsNoHints => 'Nothing unusual in technical data and traffic.';

  @override
  String get findingsNoAnnotations => 'No comments in the package.';

  @override
  String get findingsBusiest => 'Busiest addresses';

  @override
  String get findingsTechnical => 'Technical';

  @override
  String findingsLog(int count) {
    return 'Log ($count)';
  }

  @override
  String get findingsOnlyErrors => 'Errors only';

  @override
  String get findingsNoLog => 'No log in the package.';

  @override
  String get findingsNoLogErrors => 'No errors in the log.';

  @override
  String get findingLevelCritical => 'Error';

  @override
  String get findingLevelWarning => 'Check';

  @override
  String get findingLevelInfo => 'Info';

  @override
  String findingConnectionError(String error) {
    return 'Connection error: $error';
  }

  @override
  String findingConnectionState(String state) {
    return 'Connection was not established ($state).';
  }

  @override
  String findingSecureRejected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count secure telegrams rejected',
      one: '1 secure telegram rejected',
    );
    return '$_temp0: keys or counters do not match.';
  }

  @override
  String findingSecureWithoutKey(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count secure telegrams',
      one: '1 secure telegram',
    );
    return '$_temp0 without a key: keyring missing or incomplete.';
  }

  @override
  String findingRepeated(int count, int percent) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count repeats', one: '1 repeat');
    return '$_temp0 ($percent %): a sign of interference or missing acknowledgements.';
  }

  @override
  String findingPeakLoad(int count) {
    return 'Load peak: $count telegrams in one second. Often many actuators report back at once after bus voltage recovery or a central command – stagger the actuators\' send delay.';
  }

  @override
  String findingUnansweredReads(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count read requests',
      one: '1 read request',
    );
    return '$_temp0 without a response: check the R flag or the device.';
  }

  @override
  String findingConfirmErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count telegrams', one: '1 telegram');
    return '$_temp0 without confirmation from the interface.';
  }

  @override
  String findingOutages(int count, String summary) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count outages', one: '1 outage');
    return '$_temp0 in the last 7 days: $summary';
  }

  @override
  String findingLogErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count error lines', one: '1 error line');
    return '$_temp0 in the app log.';
  }

  @override
  String findingOldVersion(String version, String current) {
    return 'Older app version $version (current $current).';
  }

  @override
  String findingBuildMode(String mode) {
    return 'Not a release build ($mode).';
  }

  @override
  String get findingNoTelegrams => 'The recording contains no telegrams.';

  @override
  String get factApp => 'App';

  @override
  String get factPlatform => 'Platform';

  @override
  String get factAddon => 'Add-on';

  @override
  String get factConnection => 'Connection';

  @override
  String get factTunnel => 'Tunnel';

  @override
  String get factGateway => 'Gateway';

  @override
  String factTunnelSlots(int count) {
    return '$count tunnels';
  }

  @override
  String get factSecure => 'Secure';

  @override
  String factSecureLoaded(int count) {
    return 'Keyring loaded, $count group keys';
  }

  @override
  String get factSecureNone => 'No keyring';

  @override
  String get factTraffic => 'Traffic';

  @override
  String factTrafficValue(int telegrams, int repeated, int unanswered) {
    return '$telegrams telegrams · $repeated repeats · $unanswered unanswered';
  }

  @override
  String get factPlan => 'Plan';

  @override
  String get factExpert => 'Expert mode';

  @override
  String get reportTitle => 'Report a problem';

  @override
  String get reportTool => 'Reproduce a problem and send it to your electrician';

  @override
  String get reportIntro =>
      'Something does not work as expected? Record the problem here and your electrician sees exactly what happened on the bus, without having to come by.';

  @override
  String get reportStep1 => 'Start recording.';

  @override
  String get reportStep2 =>
      'Reproduce the problem, for example press the switch. Tap “It happened now” each time the problem occurs.';

  @override
  String get reportStep3 => 'Describe briefly what happened and send the package to your electrician.';

  @override
  String get reportNotConnected =>
      'The app is not connected to the bus right now. Only what arrives after connecting is recorded.';

  @override
  String get reportStart => 'Start recording';

  @override
  String reportRunning(String time, int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count telegrams', one: '1 telegram');
    return 'Recording since $time · $_temp0';
  }

  @override
  String get reportNowHint => 'Reproduce the problem now. As soon as it occurs:';

  @override
  String get reportNow => 'It happened now';

  @override
  String reportMarkNote(int n) {
    return 'Problem occurred ($n)';
  }

  @override
  String get reportNoMarks => 'Nothing marked yet.';

  @override
  String reportMarks(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'Marked $count times', one: 'Marked once');
    return '$_temp0';
  }

  @override
  String get reportMarksHint => 'Tap to describe what exactly happened or to add a screenshot.';

  @override
  String get reportFinish => 'Done, create package';

  @override
  String annotationsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count comments', one: '1 comment');
    return '$_temp0';
  }

  @override
  String annotationsAll(int count) {
    return 'All $count comments';
  }

  @override
  String get annotationChoiceTitle => 'Comment';

  @override
  String annotationChoiceText(String time) {
    return 'The app can also start a recording from $time, just before this telegram, so it can be traced later.';
  }

  @override
  String get annotationChoiceOnly => 'Comment only';

  @override
  String get annotationChoiceRecord => 'Also record';

  @override
  String deviceGeneralObjects(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count objects without channel',
      one: '1 object without channel',
    );
    return '$_temp0';
  }

  @override
  String get annotationRecordFailed => 'Recording not started. The comment is saved anyway.';

  @override
  String get dptChange => 'Change datapoint type';

  @override
  String dptChangedFromEts(String dpt) {
    return 'Datapoint type changed, ETS: DPT $dpt';
  }

  @override
  String get checkDptChanged => 'Datapoint types changed in the app';

  @override
  String get checkDptChangedHint =>
      'Update these in ETS, otherwise the old datapoint type remains there after the next project import.';

  @override
  String checkDptChangedRow(String ets, String app) {
    return 'ETS: $ets → app: DPT $app';
  }

  @override
  String get checkDptNone => 'no datapoint type';

  @override
  String get detailsFilterOff => 'Filter off';

  @override
  String get pdfBuilding => 'Creating PDF …';

  @override
  String get exportsTitle => 'Exports';

  @override
  String get exportsReports => 'Reports';

  @override
  String get exportsNoData => 'No data yet';

  @override
  String exportsHealthRun(String time, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count findings',
      one: '1 finding',
      zero: 'no findings',
    );
    return 'Run $time · $_temp0';
  }

  @override
  String exportsCommState(int checked, int total) {
    return '$checked of $total checked';
  }

  @override
  String get exportsBundle => 'Combined export';

  @override
  String get exportsBundleHint => 'Choose what goes into one ZIP file. It is created in the background.';

  @override
  String exportsBundleButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Export $count files as ZIP',
      one: 'Export 1 file as ZIP',
      zero: 'Nothing selected',
    );
    return '$_temp0';
  }

  @override
  String get exportsBuilding => 'Creating export …';

  @override
  String get exportsRecent => 'Recent exports';

  @override
  String exportsRecentEmpty(int keep) {
    return 'No exports yet. The last $keep files of this installation appear here and can be shared again.';
  }

  @override
  String get exportsRemove => 'Remove from list';

  @override
  String get exportsGone => 'File no longer available';

  @override
  String get exportsCheck => 'Check';

  @override
  String get exportsRecheck => 'Check again';

  @override
  String get exportsChecking => 'Running …';

  @override
  String get exportsCheckOffline => 'Connect to the bus to check';

  @override
  String get exportsCheckOpen => 'Check open';

  @override
  String detailsHistoryLatest(int shown, int total) {
    return 'Latest $shown of $total values – all in full screen';
  }

  @override
  String get boxPairPassword => 'Box password';

  @override
  String get boxPairPasswordHint =>
      'Only needed with an IP address. It is on the SD card in knx-box.txt as BOX_PASSWORD.';

  @override
  String get boxNetwork => 'Network';

  @override
  String get boxLanAccess => 'Access via cable';

  @override
  String get boxLanAccessHint =>
      'Off: the box is only reachable in its own Wi-Fi, so nobody on a customer\'s network can get at it. On: for your own box on your own network, where the box password is then enough.';

  @override
  String get boxLanAccessOffTitle => 'Block access via cable?';

  @override
  String get boxLanAccessOffBody =>
      'Devices that reach the box over the wired network lose access, this one too if it is not in the box\'s Wi-Fi right now. After that it only works in the box\'s Wi-Fi.';

  @override
  String get boxLanAccessOff => 'Block';

  @override
  String get boxPasswordAskTitle => 'Set your own box password?';

  @override
  String get boxPasswordAskBody =>
      'The current password is on the label and on the SD card. Anyone who has it can pair with the box. With your own password that no longer works; this device stays paired.';

  @override
  String get boxPasswordAskLater => 'Later';

  @override
  String get haKnxHintTitle => 'KNX integration found';

  @override
  String get haKnxHintBody =>
      'Home Assistant is already connected to the bus. The add-on can share that connection instead of taking its own tunnel slot on the gateway. Programming mode, address check and the bus monitor still need an own tunnel.';

  @override
  String get haKnxHintUse => 'Connect without own tunnel';

  @override
  String get haKnxHintDismiss => 'Keep own tunnel';

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
  String get boxHat => 'KNX HAT (test)';

  @override
  String get boxHatHint =>
      'Checks the kBerry plug-on module on the box\'s serial port: response, modes, telegrams and the bus monitor with acknowledgements.';

  @override
  String get boxHatTitle => 'Test the KNX HAT';

  @override
  String get boxHatIntro =>
      'Preview of the direct bus connection. Connect the bus cable to the module and switch on bus power. Press a few push buttons during the test so that telegrams and acknowledgements arrive. Recording over IP keeps running.';

  @override
  String get boxHatSystem => 'System';

  @override
  String boxHatSystemOk(String device) {
    return '$device is ready.';
  }

  @override
  String boxHatDeviceMissing(String device) {
    return '$device is missing. Check the UART setting in config.txt and restart the box.';
  }

  @override
  String boxHatDeviceNoAccess(String device, String error) {
    return 'No access to $device: $error';
  }

  @override
  String get boxHatSerialConsole => 'The Linux console is still on the serial port (cmdline.txt).';

  @override
  String get boxHatSeconds => 'Listening per step';

  @override
  String get boxHatStart => 'Start test';

  @override
  String boxHatRunning(String step) {
    return 'Running: $step';
  }

  @override
  String get boxHatNoReport => 'No test has run yet.';

  @override
  String get boxHatResult => 'Result';

  @override
  String get boxHatCopy => 'Copy report';

  @override
  String get boxHatCopied => 'Report copied';

  @override
  String get boxHatStepReset => 'Connection';

  @override
  String get boxHatStepIdentify => 'Identification';

  @override
  String get boxHatStepSerial => 'Serial number';

  @override
  String get boxHatStepModes => 'Modes';

  @override
  String get boxHatStepCommMode => 'Mode at start';

  @override
  String get boxHatStepLinkLayer => 'Telegrams (link layer)';

  @override
  String get boxHatStepBusmonitor => 'Bus monitor with acknowledgements';

  @override
  String get boxHatStepRestore => 'Back to BAOS mode';

  @override
  String boxHatBaud(int baud) {
    return '$baud baud';
  }

  @override
  String get boxHatNoAnswer => 'no answer';

  @override
  String get boxHatSkipped => 'skipped';

  @override
  String get boxHatNoBusmonitor => 'no bus monitor';

  @override
  String boxHatFrames(int count, int seconds) {
    return '$count telegrams in $seconds s';
  }

  @override
  String boxHatBusmonCounts(int frames, int ack, int nak, int busy, int repeated, int errors) {
    return '$frames frames: $ack ACK, $nak NAK, $busy BUSY, $repeated repeats, $errors with errors';
  }

  @override
  String get boxHatNothing => 'Nothing received. Press a push button and test again.';

  @override
  String get boxHatModeLinkLayer => 'link layer';

  @override
  String get boxHatModeBusmonitor => 'bus monitor';

  @override
  String get boxHatModeTransportLayer => 'transport layer';

  @override
  String get tourButton => 'Introduction';

  @override
  String get tourNext => 'Next';

  @override
  String get tourBack => 'Back';

  @override
  String get tourClose => 'Close introduction';

  @override
  String tourProgress(int current, int total) {
    return '$current of $total';
  }

  @override
  String get tourDemoHouse => 'Demo house';

  @override
  String get tourChapterBasics => 'Basics';

  @override
  String get tourChapterAnalysis => 'Analysis';

  @override
  String get tourChapterExpert => 'Expert mode';

  @override
  String get tourWelcomeTitle => 'See what happens on your bus.';

  @override
  String get tourWelcomeText =>
      'KNX Monitor listens at your KNX IP gateway and shows every telegram: who sends, to which group address, with which value. This introduction walks you through the main places, with the demo house as an example.';

  @override
  String get tourConnectTitle => 'Connect in one step.';

  @override
  String get tourConnectText =>
      'Search for the gateway or enter its address, then connect. UDP works with every interface; TCP, routing and KNX IP Secure are under connection type. Each site keeps its own installation with gateway, project and settings.';

  @override
  String get tourChipSearch => 'Find gateway';

  @override
  String get tourChipInstallations => 'Installations';

  @override
  String get tourProjectTitle => 'With your ETS project, every value gets a name.';

  @override
  String get tourProjectText =>
      'Import the .knxproj file, with password too, or a group address CSV. Then you see names, rooms, data types and devices instead of 1/2/3 and raw bytes. For KNX Secure, add the keyring. Everything stays on the device.';

  @override
  String get tourChipCsv => 'Group address CSV';

  @override
  String get tourChipLocal => 'Stays on the device';

  @override
  String get tourOverviewTitle => 'Overview: every address as a card.';

  @override
  String get tourOverviewText =>
      'Current value, count and a small history, sorted by rooms and functions. The star keeps favourites, the pin moves a section to the top. The bar at the top counts the telegrams of the last 60 seconds, the hour or the day.';

  @override
  String get tourObjectsTitle => 'Objects: what belongs together stays together.';

  @override
  String get tourObjectsText =>
      'Command and feedback of a light, all values of a room thermostat: in one card. Actuators appear as DIN rail devices with lit channel LEDs.';

  @override
  String get tourLiveTitle => 'Live: every telegram in order.';

  @override
  String get tourLiveText =>
      'Time, type (write, read, response), sender, destination, name and value. Anything odd is marked, such as a wrong length or an unusual hop count. Pause stops the list without losing anything.';

  @override
  String get tourFilterTitle => 'Filter instead of searching.';

  @override
  String get tourFilterText =>
      'The field at the top understands names, addresses, devices and times, also combined. Saved filters are behind the bookmark in the field.';

  @override
  String get tourChipFilterName => 'weather';

  @override
  String get tourChipFilterSender => 'from:1.1.10';

  @override
  String get tourChipFilterTime => 'time:14:05-14:10';

  @override
  String get tourDetailsTitle => 'Details: read, write, comment.';

  @override
  String get tourDetailsText =>
      'A tap on a card or row opens the details: last value, history, sender and linked devices. From there you read the value again, write your own or attach a comment.';

  @override
  String get tourHealthTitle => 'Health: is the installation fine?';

  @override
  String get tourHealthText =>
      'One button reads all status addresses and checks what is already there: silent devices, wrong data types, odd cycles, repeats and bus quality. Every finding leads to the address or device.';

  @override
  String get tourChipSilent => 'Silent addresses';

  @override
  String get tourChipTypes => 'Data types';

  @override
  String get tourChipCycles => 'Cycles';

  @override
  String get tourChipBusQuality => 'Bus quality';

  @override
  String get tourRecordTitle => 'Record, comment, report.';

  @override
  String get tourRecordText =>
      'The red dot records, with name and note. Comments stick to telegrams and recordings, with screenshots. “Report a problem” captures when something went wrong and packs everything for your electrician.';

  @override
  String get tourHistoryTitle => 'History over days.';

  @override
  String get tourHistoryText =>
      'The long-term history keeps whole days, in the add-on and on the KNX box around the clock. You rewind what happened at night, with a timeline per group address and playback at 1 to 60 times the speed.';

  @override
  String get tourChipTimeline => 'Timeline';

  @override
  String get tourChipPlayback => 'Playback 1–60×';

  @override
  String get tourChartsTitle => 'Charts: several values, one time axis.';

  @override
  String get tourChartsText =>
      'Up to eight addresses together, one axis per unit, switching values as their own rows. Saved charts appear as their own section in the overview.';

  @override
  String get tourStatsTitle => 'Statistics: who talks the most?';

  @override
  String get tourStatsText =>
      'Busiest addresses and senders, load peaks and a heatmap over days. A tap on a peak or cell filters the monitor to that time.';

  @override
  String get tourWatchTitle => 'Watchers and alarms.';

  @override
  String get tourWatchText =>
      'A watcher speaks up with a sound as soon as a given address sends or reaches a value. Alarm and fault objects sit at the top of the overview and send notifications if you like.';

  @override
  String get tourChipSound => 'With sound';

  @override
  String get tourExportTitle => 'Export in every format.';

  @override
  String get tourExportText =>
      'Telegrams as PDF, CSV or for ETS, reports of health and commissioning, and a ZIP with everything. The exports page keeps the latest files per installation.';

  @override
  String get tourExpertTitle => 'One switch, and the workshop is there.';

  @override
  String get tourExpertText =>
      'Expert mode on the connect screen or at the bottom of the menu turns on the tools for commissioning and troubleshooting, plus port, tunnel address and connection options. Without it the app stays lean; nothing is lost.';

  @override
  String get tourChipPort => 'Port and tunnel address';

  @override
  String get tourBusmonTitle => 'Bus monitor: every frame.';

  @override
  String get tourBusmonText =>
      'Raw frames with acknowledgements (ACK, NAK, BUSY), repeats and corrupted telegrams, the senders in a column of their own. The interface has to support bus monitor mode for this.';

  @override
  String get tourChipAck => 'ACK · NAK · BUSY';

  @override
  String get tourChipRepeats => 'Repeats';

  @override
  String get tourTopoTitle => 'Topology: lines and couplers.';

  @override
  String get tourTopoText =>
      'Devices by line, hop count, tunnels and traffic across couplers. A device opens its sheet with channels, push buttons and addresses.';

  @override
  String get tourMapTitle => 'Communication map: who talks to whom.';

  @override
  String get tourMapText =>
      'For each address, who sends and who receives according to the project. Solid lines were observed, dashed ones are only in the project.';

  @override
  String get tourCheckTitle => 'Project check.';

  @override
  String get tourCheckText =>
      'Bus traffic against the ETS project: what is missing, what is unknown, what never sends, plus the flags of the objects even without traffic.';

  @override
  String get tourCommTitle => 'Commissioning and diagnostics.';

  @override
  String get tourCommText =>
      'The checklist reads every status address in turn and ticks off answers; what is left you check on site, and you get a PDF report. Diagnostics finds devices in programming mode, checks addresses and scans lines.';

  @override
  String get tourChipProgMode => 'Programming mode';

  @override
  String get tourChipLineScan => 'Line scan';

  @override
  String get tourSendTitle => 'Send, trigger, replay.';

  @override
  String get tourSendText =>
      'Send like the ETS group monitor, delayed or cyclic too. Trigger recordings start on a value, a fault or a repeat, with lead time. A recording can be played back onto the bus, after you confirm it explicitly.';

  @override
  String get tourBoxTitle => 'KNX box for the site.';

  @override
  String get tourBoxText =>
      'A Raspberry Pi that records around the clock and opens its own Wi-Fi. You pair it with the label; the app fetches the history straight from the box. Still a preview.';

  @override
  String get tourChipWifi => 'Own Wi-Fi';

  @override
  String get tourChipSticker => 'Pair with the label';

  @override
  String get tourMoreTitle => 'More with Plus and Pro.';

  @override
  String get tourMoreText =>
      'Plus keeps the history over days and adds charts, statistics, watchers and export. Pro unlocks expert mode with bus monitor, topology, commissioning and diagnostics. You can try everything in the demo house.';

  @override
  String get tourMorePlans => 'See the plans';

  @override
  String get tourReadyTitle => 'Ready.';

  @override
  String get tourReadyText =>
      'In the demo house you try everything safely, without an installation. You find the introduction again on the connect screen at any time.';

  @override
  String get tourOpenDemo => 'Open demo house';

  @override
  String get tourDone => 'Done';

  @override
  String get commSeen => 'Seen';

  @override
  String get commForeign => 'unexpected sender';

  @override
  String get commRollCall => 'Tick off when sent';

  @override
  String get commRollCallExplain =>
      'Roll call: press buttons, open windows – every address on the list that is sent on the bus ticks itself off. If a different device than in the project sends, it is marked.';

  @override
  String get commToneOn => 'With sound (acknowledgement)';

  @override
  String get commToneOff => 'Sound off';

  @override
  String get ackTitle => 'Sound acknowledgement';

  @override
  String get ackTool => 'A sound for every telegram – commission alone';

  @override
  String get ackExplain =>
      'Plays a short sound for every telegram of a line, a device, a group address or the commissioning list. At the push button you hear whether it reaches the bus – no second person at the tablet.';

  @override
  String get ackTargetChecklist => 'Commissioning list';

  @override
  String ackLine(String line) {
    return 'Line $line';
  }

  @override
  String get ackInvalid => 'Address not recognised';

  @override
  String get ackForegroundOnly => 'Acknowledgement runs while the app is in the foreground.';

  @override
  String get ackAndroidBackground =>
      'On Android the acknowledgement keeps running with the screen locked (notification “Sound acknowledgement”). The phone can go in your pocket.';

  @override
  String get ackIosForeground =>
      'iPhone and iPad: only with the app open; the screen stays on for it. iOS does not allow listening in the background. Turn the silent switch off, otherwise it stays quiet.';

  @override
  String get ackRunning => 'Running';

  @override
  String ackCount(int count) {
    return '$count telegrams';
  }

  @override
  String get ackStop => 'Stop';

  @override
  String get ackTarget => 'Whose telegrams?';

  @override
  String get ackKindChecklist => 'List';

  @override
  String get ackKindLine => 'Line';

  @override
  String get ackKindDevice => 'Device';

  @override
  String get ackKindGroup => 'Address';

  @override
  String get ackAddress => 'Address';

  @override
  String get ackStart => 'Start';

  @override
  String get ackSounds => 'Sounds';

  @override
  String get ackSoundsExplain =>
      'Short tick: write. Bright double tone: response. Low tone: a sender that, according to the project, does not send to this address or is unknown. With very many telegrams some sounds are skipped.';

  @override
  String get acceptTitle => 'Acceptance protocol';

  @override
  String get acceptExplain =>
      'Records the state of commissioning: what is tested, what is open, who did it. Customer and technician sign on the device; after that the protocol is frozen and stored with the installation.';

  @override
  String get acceptPdfTitle => 'Acceptance protocol';

  @override
  String get acceptCustomerSection => 'Customer and site';

  @override
  String get acceptCustomer => 'Customer';

  @override
  String get acceptSite => 'Site (address)';

  @override
  String get acceptTechnician => 'Technician';

  @override
  String get acceptNotesSection => 'Agreements';

  @override
  String get acceptFollowUps => 'Agreed follow-ups';

  @override
  String get acceptRemarks => 'Remarks';

  @override
  String get acceptRemarksHint => 'e.g. customer was shown how to use it';

  @override
  String get acceptLanguage => 'Protocol language';

  @override
  String get acceptSignatures => 'Signatures';

  @override
  String get acceptSigner => 'Customer name (block letters)';

  @override
  String get acceptSignCustomer => 'Customer signature';

  @override
  String get acceptSignTechnician => 'Technician signature';

  @override
  String get acceptCreate => 'Create protocol';

  @override
  String get acceptMissing => 'This needs customer, technician and both signatures.';

  @override
  String get acceptEarlier => 'Earlier protocols';

  @override
  String get acceptIssues => 'Issues';

  @override
  String get acceptOpenPoints => 'Open points';

  @override
  String get acceptConfirmation => 'The installation was handed over and accepted in the state described above.';

  @override
  String get acceptRoleCustomer => 'Customer';

  @override
  String get acceptRoleTechnician => 'Technician';

  @override
  String acceptChecksum(String checksum) {
    return 'Checksum (SHA-256): $checksum';
  }

  @override
  String get acceptSignatureNote => 'Simple electronic signature on the device, created with KNX Monitor.';

  @override
  String get signUndo => 'Undo last stroke';

  @override
  String get signClear => 'Clear';

  @override
  String get signDone => 'Done';

  @override
  String get signHint => 'Sign in the field with finger, pencil or mouse.';

  @override
  String get signArea => 'Signature field';

  @override
  String get huntTitle => 'Fault hunt';

  @override
  String get huntTool => 'Catch sporadic faults over days – with the KNX box';

  @override
  String get huntRefresh => 'Refresh';

  @override
  String get huntNeedsBox =>
      'The fault hunt runs on the KNX box or in the Home Assistant add-on, around the clock. Pair the app with a box to set it up.';

  @override
  String get huntExplain =>
      'For faults that only happen sometimes: leave the box at the customer\'s, the hunt catches every hit of a watcher with two minutes before and one after. Afterwards you see who sent it – often it is always the same one.';

  @override
  String get huntRunning => 'Running';

  @override
  String get huntEnded => 'Ended';

  @override
  String huntUntil(String date) {
    return 'until $date';
  }

  @override
  String huntWindow(String from, String to) {
    return 'only $from–$to';
  }

  @override
  String get huntAllDay => 'around the clock';

  @override
  String huntHits(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count hits', one: '1 hit');
    return '$_temp0';
  }

  @override
  String get huntStop => 'Stop hunt';

  @override
  String get huntNew => 'New hunt';

  @override
  String get huntNoWatchers => 'The hunt uses watchers as rules. Create one first, e.g. “Living room blind up = 1”.';

  @override
  String get huntChooseRules => 'What should be caught?';

  @override
  String get huntName => 'Name';

  @override
  String get huntNameHint => 'e.g. blind goes up at night';

  @override
  String get huntDuration => 'Duration';

  @override
  String huntDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count days', one: '1 day');
    return '$_temp0';
  }

  @override
  String get huntOnlyWindow => 'Only in a time window';

  @override
  String get huntOnlyWindowExplain => 'e.g. at night from 22:00 to 06:00 (box time)';

  @override
  String get huntStart => 'Start hunt';

  @override
  String get huntSenders => 'Who sent it?';

  @override
  String get huntResults => 'Hits';

  @override
  String huntFrom(String sender) {
    return 'from $sender';
  }

  @override
  String get huntOpen => 'Open';

  @override
  String huntSaveFailed(String error) {
    return 'Hit not loaded: $error';
  }

  @override
  String get plainThisApp => 'This app';

  @override
  String plainDevice(String address) {
    return 'Device $address';
  }

  @override
  String plainAddress(String address) {
    return 'address $address';
  }

  @override
  String plainRead(String sender, String target) {
    return '$sender asks for $target';
  }

  @override
  String plainReport(String sender, String target, String value) {
    return '$sender reports $target: $value';
  }

  @override
  String plainSet(String sender, String target, String value) {
    return '$sender set $target to $value';
  }

  @override
  String plainAction(String sender, String target, String action) {
    return '$sender $action $target';
  }

  @override
  String get plainSwitchedOn => 'switched on';

  @override
  String get plainSwitchedOff => 'switched off';

  @override
  String get plainMovedUp => 'raised';

  @override
  String get plainMovedDown => 'lowered';

  @override
  String get plainOpened => 'opened';

  @override
  String get plainClosed => 'closed';

  @override
  String get plainStarted => 'started';

  @override
  String get plainStopped => 'stopped';

  @override
  String get plainEnabled => 'enabled';

  @override
  String get plainDisabled => 'disabled';

  @override
  String get plainTriggered => 'triggered';

  @override
  String get plainColumnEvent => 'What happened';

  @override
  String get learnTitle => 'Teach your installation';

  @override
  String get learnTool => 'No ETS project: press a button, name it, done';

  @override
  String get learnExplain =>
      'No ETS project at hand? Press a button or switch a light. The app listens, catches the group addresses including the status feedback and asks what it was. That becomes your own project – overview, objects and charts work right away. An ETS project imported later takes precedence; your names stay for addresses it lacks.';

  @override
  String get learnListening => 'Listening …';

  @override
  String get learnPressNow => 'Now press a button or switch something – ideally one thing at a time.';

  @override
  String get learnDemoPress => 'Press a button in the demo house';

  @override
  String get learnMeasurements => 'Also catch measurements';

  @override
  String get learnMeasurementsHint => 'Off: temperature and similar values don\'t interfere while you press buttons.';

  @override
  String learnCaught(String time) {
    return 'Caught at $time';
  }

  @override
  String get learnRoleCommand => 'Command';

  @override
  String get learnRoleFeedback => 'Feedback';

  @override
  String get learnGuessed => 'guessed';

  @override
  String learnInProject(String name) {
    return 'In project: $name';
  }

  @override
  String get learnQuestion => 'What did you just press?';

  @override
  String get learnRoom => 'Room';

  @override
  String get learnName => 'What is it?';

  @override
  String get learnDevice => 'Device (sender)';

  @override
  String learnDeviceDefault(String room) {
    return '$room button';
  }

  @override
  String get learnStatusSuffix => 'status';

  @override
  String get learnSave => 'Save';

  @override
  String get learnSkip => 'Discard';

  @override
  String learnIgnore(String address) {
    return 'Stop catching $address';
  }

  @override
  String learnSaved(String name) {
    return 'Learned: $name';
  }

  @override
  String learnLearned(int count) {
    return 'Learned ($count)';
  }

  @override
  String get learnNothingYet => 'Nothing learned yet.';

  @override
  String get learnForget => 'Forget';

  @override
  String get learnClearAll => 'Forget everything learned';

  @override
  String get learnClearConfirm => 'Delete all learned names? An imported project stays.';

  @override
  String get learnDemoNote => 'Demo house: what you teach here is kept only until you leave the demo.';

  @override
  String get learnRoomSuggestions =>
      'Living room,Kitchen,Hall,Bathroom,Bedroom,Kids\' room,Office,Dining room,Garden,Basement';

  @override
  String get learnNamesSwitch => 'Light,Ceiling light,Spots,Floor lamp,Socket,Outdoor light';

  @override
  String get learnNamesBlind => 'Shutter,Blind,Awning';

  @override
  String get learnNamesPercent => 'Dimmer,Brightness,Shutter position,Valve';

  @override
  String get learnNamesMeasure => 'Temperature,Humidity,Brightness,Wind,Power';

  @override
  String get learnNamesOther => 'Scene,Window contact,Motion sensor,Dimming';

  @override
  String get learnNoProjectCta => 'No ETS project? Teach your installation';

  @override
  String get learnSource => 'Learned';

  @override
  String learnCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count learned addresses',
      one: '1 learned address',
    );
    return '$_temp0';
  }

  @override
  String get helpNextSteps => 'What to try next';

  @override
  String get helpNoResponseTitle => 'The gateway does not answer';

  @override
  String helpOddPort(int port) {
    return 'Port $port is unusual – KNX IP gateways almost always use 3671.';
  }

  @override
  String get helpCheckIp =>
      'Is the IP address right? “Search gateways” finds devices on the same network; otherwise check your router or ETS.';

  @override
  String get helpSameNetwork =>
      'Is this device on the same network as the gateway? Guest Wi-Fi, VPN or a second router separate networks.';

  @override
  String get helpBusPower =>
      'Is the gateway powered and connected to the bus? Some don\'t answer at all without bus voltage.';

  @override
  String get helpNetworkTitle => 'The network can\'t be reached';

  @override
  String get helpWifiOn => 'Are you on Wi-Fi or LAN – the home network, not mobile data?';

  @override
  String get helpLocalNetworkPermission =>
      'iPhone, iPad and Mac ask once for “local network” access. Declined? Allow it in Settings › Privacy › Local Network.';

  @override
  String helpTcpPort(int port) {
    return 'TCP and IP Secure need port $port open on the gateway. If it can\'t do TCP, choose UDP as connection type.';
  }

  @override
  String get helpNoTunnelTitle => 'All tunnels are in use';

  @override
  String get helpTunnelsHeld =>
      'An IP gateway has only a few tunnels (often 1 to 8). ETS, a visualisation (e.g. Home Assistant, Gira X1) or a logic module keeps them busy.';

  @override
  String get helpCloseEts => 'Close the ETS bus monitor or ETS connection, then connect again here.';

  @override
  String get helpScanShowsSlots => '“Search gateways” shows for many devices how many tunnels are free right now.';

  @override
  String get helpUseRouting => 'Is there an IP router? Routing uses no tunnel (connection type in expert mode).';

  @override
  String get helpTunnelAddressTitle => 'The fixed tunnel address doesn\'t work';

  @override
  String get helpNoFixedAddress =>
      'Clear the fixed tunnel address in the connection settings (expert mode) – the gateway then assigns a free one.';

  @override
  String get helpUnsupportedTitle => 'The device offers no suitable tunnel';

  @override
  String get helpNotAnInterface =>
      'Some devices are pure IP routers, visualisations or servers. Pick the installation\'s IP interface.';

  @override
  String get helpSecureAuthTitle => 'IP Secure: access denied';

  @override
  String get helpSecureKeyring =>
      'Easiest: load the keyring (.knxkeys) exported from ETS – user, password and device code are then right automatically.';

  @override
  String get helpSecurePasswordInEts =>
      'By hand: the tunnel\'s user and password are in ETS on the gateway (Properties › IP › Tunnel).';

  @override
  String get helpSecureNotProjectPassword => 'This is the tunnel password, not the project password of the .knxproj.';

  @override
  String get helpSecureDeviceTitle => 'IP Secure: device code doesn\'t match';

  @override
  String get helpSecureDeviceCode =>
      'The device authentication code is in ETS on the gateway (Properties › IP); the keyring brings it along.';

  @override
  String get helpSecureRightDevice => 'Is it really your interface answering? Check for two devices with the same IP.';

  @override
  String get helpSecureMissingTitle => 'IP Secure needs credentials';

  @override
  String get helpAskElectrician => 'No keyring? Your electrician can give it to you along with the project file.';

  @override
  String get helpRoutingTitle => 'Routing doesn\'t work here';

  @override
  String get helpRoutingMulticast =>
      'Routing uses multicast (224.0.23.12). Many Wi-Fi routers and mesh systems don\'t pass it on.';

  @override
  String get helpTryTunnel => 'Try a tunnel (UDP) with the gateway\'s IP address.';

  @override
  String get helpNoGatewayTitle => 'No gateway found';

  @override
  String get helpSearchSilent =>
      'Some gateways don\'t answer the search. Then type the IP address directly – it\'s in your router or ETS.';

  @override
  String get helpRoutingSearch => 'The search finds IP interfaces (tunnel) and IP routers (routing) alike.';

  @override
  String get helpTryDemo => 'Try it without an installation: the demo house.';

  @override
  String helpFreeTunnels(int free, int total) {
    return '$free of $total tunnels free';
  }

  @override
  String get helpActionScan => 'Search gateways';

  @override
  String get helpActionKeyring => 'Load keyring';

  @override
  String get helpActionProject => 'About the project file';

  @override
  String get helpActionDemo => 'Open demo house';

  @override
  String get projectHelpTitle => 'The ETS project file';

  @override
  String get projectHelpWhatTitle => 'What is a .knxproj?';

  @override
  String get projectHelpWhat =>
      'Your electrician set up the installation with the planning software ETS. The project file (ending .knxproj) holds all the names: which group address switches the kitchen light, which device sits where, what values there are. With it, KNX Monitor shows names instead of numbers.';

  @override
  String get projectHelpPasswordTitle => 'Project password';

  @override
  String get projectHelpPassword =>
      'The file may be protected with a password. The app asks for it when importing and needs it only to open the file – file and password stay on your device.';

  @override
  String get projectHelpKeyringTitle => 'Keyring (.knxkeys)';

  @override
  String get projectHelpKeyring =>
      'If your installation uses KNX Secure (IP Secure or Data Secure), there is also a keyring with its own password. Without it the app can\'t connect to a secure gateway or read encrypted values. Without Secure you don\'t need it.';

  @override
  String get projectHelpGetTitle => 'How do I get it?';

  @override
  String get projectHelpGet =>
      'Ask the company that built the installation. Many hand the file over readily, some for a small fee. For the names, a CSV export of the group addresses from ETS is enough too.';

  @override
  String get projectHelpTemplateTitle => 'Sample request to copy';

  @override
  String get projectHelpTemplate =>
      'Subject: ETS project file for our KNX installation\n\nHello [name],\n\nYou set up the KNX installation at [address]. For maintenance and troubleshooting we would like to keep an overview ourselves. Could you please send us the current ETS project file (.knxproj) with its project password – and, if KNX Secure is used, the keyring (.knxkeys) with its password as well?\n\nA CSV export of the group addresses would already help too. If there are any costs, please let us know beforehand.\n\nThank you and best regards\n[your name]';

  @override
  String get projectHelpCopy => 'Copy text';

  @override
  String get projectHelpCopied => 'Text copied';

  @override
  String get projectHelpNoneTitle => 'Can\'t get the file?';

  @override
  String get projectHelpNone =>
      'Then teach the installation yourself: press a button, name it, done. You\'ll find it in the monitor under “Teach your installation”. A project imported later takes precedence, your names stay for the rest.';

  @override
  String get projectHelpDisclaimer =>
      'This is not legal advice. Whether and how you get the file depends on your contract with the company.';

  @override
  String get projectHelpTool => 'What is a .knxproj, how do I get it?';

  @override
  String get termGroupAddress => 'Group address';

  @override
  String get termIndividualAddress => 'Individual address';

  @override
  String get termStatus => 'Status (feedback)';

  @override
  String get termDpt => 'Datapoint type (DPT)';

  @override
  String get termFlags => 'Flags';

  @override
  String get termLine => 'Line';

  @override
  String get termTunnel => 'Tunnel';

  @override
  String get termGroupAddressText =>
      'A group address (e.g. 1/0/1) is like a channel: a button sends “on” to it, and every actuator listening on that channel switches.';

  @override
  String get termIndividualAddressText =>
      'The individual address (e.g. 1.1.30) is a device\'s house number – area, line, device – and tells you who sent a telegram.';

  @override
  String get termStatusText =>
      'A status is the actuator\'s answer: it tells you whether the light really is on – not just that someone pressed a button.';

  @override
  String get termDptText =>
      'The datapoint type says how to read the bytes: 1.001 means on/off, 5.001 percent, 9.001 temperature in °C.';

  @override
  String get termFlagsText =>
      'Flags define what a device object may do: C communicate, R answer reads, W accept writes, T transmit itself, U take over responses.';

  @override
  String get termLineText =>
      'A line is one run of bus cable with up to 64 devices; line couplers join several lines into an area.';

  @override
  String get termTunnelText =>
      'A tunnel is a network access to the bus. An IP gateway has only a few, and every app, ETS or visualisation uses one.';

  @override
  String termExampleGroup(String address, String name) {
    return 'Here: $address is called “$name”.';
  }

  @override
  String termExampleDevice(String address, String name, String line) {
    return 'Here: $address is “$name” on line $line.';
  }

  @override
  String termExampleStatus(String address, String name) {
    return 'Here: $address “$name” reports the real state.';
  }

  @override
  String termExampleDpt(String name, String dpt) {
    return 'Here: “$name” has type $dpt.';
  }

  @override
  String termExampleFlags(String name, String device, String flags) {
    return 'Here: “$name” on device $device has the flags $flags.';
  }

  @override
  String termExampleLine(String line, int count) {
    return 'Here: line $line has $count devices.';
  }

  @override
  String termExampleTunnel(String address, String gateway) {
    return 'Here: $address is a tunnel of “$gateway”.';
  }

  @override
  String get termExampleNone => 'Your own project has no example for this yet – the demo house does.';

  @override
  String get glossaryTitle => 'Terms';

  @override
  String get glossaryMore => 'Lessons and quiz';

  @override
  String get lessonsTitle => 'Learn KNX';

  @override
  String get lessonsTool => 'Terms, short lessons and a mini quiz';

  @override
  String get lessonsIntro =>
      'Five short lessons on your own installation – or in the demo house. Tap a term to see it with an example.';

  @override
  String lessonsTry(String text) {
    return 'Try it: $text';
  }

  @override
  String get lessonSwitchTitle => '1 · How KNX switches';

  @override
  String get lessonSwitchText =>
      'A button doesn\'t know which light it switches. It just sends “on” to a group address. The actuator listening on that address switches – and reports back on a second address what it did.';

  @override
  String get lessonSwitchTry => 'Watch in the live monitor how an “on” is followed by a status.';

  @override
  String get lessonWhoTitle => '2 · Who is who';

  @override
  String get lessonWhoText =>
      'Every device has an individual address like 1.1.30: area 1, line 1, device 30. That shows in every telegram who sent it – even without a project.';

  @override
  String get lessonWhoTry => 'Tap a telegram and look at the sender.';

  @override
  String get lessonValuesTitle => '3 · Reading values';

  @override
  String get lessonValuesText =>
      'The bus carries only bytes. The datapoint type turns them into “21.5 °C” or “50 %”. Without it the app guesses from the length – 1 bit is usually switching, 2 bytes usually a measurement.';

  @override
  String get lessonValuesTry => 'Look at the temperatures in the overview.';

  @override
  String get lessonReadTitle => '4 · Questions and answers';

  @override
  String get lessonReadText =>
      'The app can “read” an address: it asks, and the device with the read flag answers with the current value. If nobody answers, often just that flag is missing.';

  @override
  String get lessonReadTry => 'The health check asks all status addresses.';

  @override
  String get lessonConnectTitle => '5 · How the app connects';

  @override
  String get lessonConnectText =>
      'The app talks over the network to an IP gateway sitting on the bus. For that it uses a tunnel; when all are taken, it has to wait until ETS or a visualisation frees one.';

  @override
  String get lessonConnectTry => 'Tap the gateway name at the top.';

  @override
  String get quizTitle => 'Mini quiz';

  @override
  String get quizStart => 'Start quiz';

  @override
  String get quizAgain => 'Again';

  @override
  String quizProgress(int current, int total) {
    return 'Question $current of $total';
  }

  @override
  String get quizRight => 'Correct!';

  @override
  String get quizWrong => 'Not quite.';

  @override
  String get quizNext => 'Next';

  @override
  String quizResult(int score, int total) {
    return '$score of $total correct';
  }

  @override
  String get quizDemoNote => 'The questions come from the demo house.';

  @override
  String get quizWhichGroup => 'Which of these is a group address?';

  @override
  String quizWhichLine(String address) {
    return 'Which line is device $address on?';
  }

  @override
  String quizWhichDpt(String name) {
    return 'What kind of value is “$name”?';
  }

  @override
  String get quizDptSwitch => 'On/off (1 bit)';

  @override
  String get quizDptPercent => 'Percent (1 byte)';

  @override
  String get quizDptFloat => 'Measurement like temperature (2 bytes)';

  @override
  String quizWhatStatus(String name) {
    return 'What does “$name” report?';
  }

  @override
  String get quizStatusRight => 'What the actuator really did';

  @override
  String get quizStatusWho => 'Who pressed the button';

  @override
  String get quizStatusTime => 'The time of the button press';

  @override
  String get quizTunnelBusy => 'The gateway answers, but the app gets no connection. What\'s most likely?';

  @override
  String get quizTunnelRight => 'All tunnels are in use';

  @override
  String get quizTunnelWrongGa => 'A group address is wrong';

  @override
  String get quizTunnelWrongDpt => 'A datapoint type is missing';

  @override
  String get quizFlagRead => 'An address never answers reads. Which flag is probably missing?';

  @override
  String get quizFlagReadRight => 'R (read)';

  @override
  String get quizFlagTransmit => 'T (transmit)';

  @override
  String get quizFlagWrite => 'W (write)';

  @override
  String get projectHelpShort => 'Project file?';

  @override
  String get lightUnknown => 'Not checked yet';

  @override
  String get lightGreen => 'All good';

  @override
  String get lightYellow => 'Something looks odd';

  @override
  String get lightRed => 'Please take a look';

  @override
  String get weekTitle => 'Weekly report';

  @override
  String get weekNotChecked => 'Nothing was checked this week.';

  @override
  String get weekAllGood => 'All good this week.';

  @override
  String weekOneIssue(String issue) {
    return 'All good this week except one thing: $issue.';
  }

  @override
  String weekIssues(int count, String issue) {
    return '$count things stood out this week, first: $issue.';
  }

  @override
  String weekResolved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count have resolved themselves since.',
      one: 'One has resolved itself since.',
    );
    return '$_temp0';
  }

  @override
  String weekChecks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count checks',
      one: '1 check',
      zero: 'no check',
    );
    return '$_temp0';
  }

  @override
  String weekBasisContinuous(String server, String checks) {
    return 'Basis: the $server listens around the clock; plus $checks this week.';
  }

  @override
  String weekBasisPartial(String time, int days, String checks) {
    String _temp0 = intl.Intl.pluralLogic(days, locale: localeName, other: '$days days', one: '1 day');
    return 'Basis: the app listened for about $time on $_temp0 this week ($checks). The report can\'t see what happened in between – only a KNX box or the Home Assistant add-on listens around the clock.';
  }

  @override
  String weekBasisNone(String checks) {
    return 'Basis: $checks; otherwise the app barely listened this week.';
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
  String get weekOpen => 'Open';

  @override
  String get weekDone => 'Resolved this week';

  @override
  String get weekCheckNow => 'Check now';

  @override
  String get weekOpenHealth => 'Open health check';

  @override
  String weekLastCheck(String when) {
    return 'Last check: $when';
  }

  @override
  String get weekServerBox => 'KNX box';

  @override
  String get weekServerAddon => 'Home Assistant add-on';

  @override
  String plainFindingSilent(String name) {
    return '“$name” no longer reports';
  }

  @override
  String plainFindingNoAnswer(String name) {
    return '“$name” doesn\'t answer questions';
  }

  @override
  String plainFindingOverdue(String name) {
    return '“$name” has been unusually quiet';
  }

  @override
  String plainFindingImpossible(String name) {
    return '“$name” shows an impossible value';
  }

  @override
  String plainFindingStuck(String name) {
    return '“$name” has been stuck on the same value for hours';
  }

  @override
  String plainFindingFormat(String name) {
    return '“$name” sends values in the wrong format';
  }

  @override
  String plainFindingRepeats(String name) {
    return '“$name” has to repeat often – have the cable or device checked';
  }

  @override
  String get learnKnown => 'in project';

  @override
  String weekLastFullCheck(String when) {
    return 'Last check with read test: $when – read findings date from then.';
  }

  @override
  String get haTitle => 'Home Assistant';

  @override
  String get haTool => 'Configuration for the KNX integration from your project';

  @override
  String get haExplain =>
      'KNX Monitor derives lights, covers, room controllers, switches and sensors for the Home Assistant KNX integration from your ETS project. Pick what you want to use. Please check marked entries – their mapping was not clear-cut.';

  @override
  String get haEmpty =>
      'The configuration needs an ETS project with group addresses and datapoint types. Import it first.';

  @override
  String get haWhere =>
      'In Home Assistant, put it as knx.yaml in the configuration folder (next to configuration.yaml) and include it there:';

  @override
  String get haWhereAddon =>
      'In the add-on: save the file as /homeassistant/knx.yaml (shown as “config” in File editor or Studio Code Server), include it in configuration.yaml and restart Home Assistant. If there already is a “knx:” section, paste the entries there instead of including the file.';

  @override
  String get haEntities => 'Entities';

  @override
  String get haUncertain => 'To check';

  @override
  String get haTypes => 'Types';

  @override
  String get haRooms => 'Rooms';

  @override
  String get haAllRooms => 'All';

  @override
  String get haNoRoom => 'No room';

  @override
  String get haOnlyUncertain => 'Only to check';

  @override
  String get haPreview => 'Preview file';

  @override
  String get haCopy => 'Copy YAML';

  @override
  String get haCopied => 'Configuration copied';

  @override
  String get haYamlDevices => 'Devices (device): assign the area in Home Assistant under Settings › Devices.';

  @override
  String get haDevices => 'Devices';

  @override
  String get haDevicesExplain =>
      'These entities clearly belong together. Accept a suggestion and Home Assistant groups them into one device – handy for dashboards by device. Nothing changes unless you choose so.';

  @override
  String get haDevicesAll => 'Accept all';

  @override
  String get haDevicesNone => 'None';

  @override
  String get haDeviceFromNames => 'recognised by name';

  @override
  String haDeviceFromBus(String device, String address) {
    return 'all sent by $device ($address)';
  }

  @override
  String haDeviceOf(String device) {
    return 'Device: $device';
  }

  @override
  String get haShare => 'Share knx.yaml';

  @override
  String get haPlatformLight => 'Light';

  @override
  String get haPlatformCover => 'Cover';

  @override
  String get haPlatformClimate => 'Climate';

  @override
  String get haPlatformSwitch => 'Switch';

  @override
  String get haPlatformBinarySensor => 'Binary sensor';

  @override
  String get haPlatformSensor => 'Sensor';

  @override
  String get haDoubtNoDpt => 'no datapoint type, mapped by name';

  @override
  String get haDoubtNoState => 'no status address found';

  @override
  String get haDoubtLightOrSwitch => 'light or load? Added as switch';

  @override
  String get haDoubtAmbiguous => 'several addresses fit, the first one is used';

  @override
  String get haDoubtTargetFromCommand => 'setpoint without its own status address';

  @override
  String get haDoubtTypeGuessed => 'only the main DPT is known';

  @override
  String haYamlHeader(String version, String project, String date) {
    return 'KNX Monitor $version – KNX integration for Home Assistant, project “$project”, $date';
  }

  @override
  String get haYamlInclude => 'Include in configuration.yaml with:  knx: !include knx.yaml';

  @override
  String get haYamlSchema =>
      'Keys as per home-assistant.io/integrations/knx – review entries marked “Check” before use.';

  @override
  String haYamlCheck(String reasons) {
    return 'Check: $reasons';
  }

  @override
  String get haDoubtNoSwitch =>
      'brightness only, no switch object – Home Assistant needs “address”, entry commented out';

  @override
  String get chainTitle => 'Cause chain';

  @override
  String get chainLocked => 'Show cause chain';

  @override
  String chainKindScene(String name) {
    return 'Scene “$name”';
  }

  @override
  String chainKindCentral(String name) {
    return 'Central command “$name”';
  }

  @override
  String chainFrom(String what, String sender) {
    return '$what came from $sender';
  }

  @override
  String chainAfterCause(String sentence, String time, String cause) {
    return '$sentence – $time after “$cause”';
  }

  @override
  String chainReactions(String time, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count devices responded',
      one: '1 device responded',
    );
    return '$_temp0 within $time';
  }

  @override
  String chainNoReaction(String time) {
    return 'no device reacted within $time';
  }

  @override
  String get chainQuiet => 'The bus was quiet before and after.';

  @override
  String get chainThis => 'this';

  @override
  String get chainRoleCause => 'Cause';

  @override
  String get chainRoleFeedback => 'Feedback';

  @override
  String get chainRoleFollowUp => 'Follow-up';

  @override
  String get chainRoleCoincident => 'Nearby, unrelated';

  @override
  String get reactTitle => 'Response times';

  @override
  String get reactTool => 'How fast do actuators report back after a command?';

  @override
  String get reactExplain =>
      'Per channel, the time from a write command to the first status feedback (up to 3 s), from the current log. 50–300 ms is typical; much more points to a busy bus, filtering couplers or slow logic.';

  @override
  String get reactEmpty => 'No measurement yet: switch or move something whose status feedback is in the project.';

  @override
  String get reactNoProject => 'Without an ETS project commands and feedback cannot be matched.';

  @override
  String get reactChannels => 'Channels';

  @override
  String reactLine(String median, String p90, String max, int count) {
    return 'median $median · 90% $p90 · max $max · $count×';
  }

  @override
  String reactMissing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count commands without feedback',
      one: '1 command without feedback',
    );
    return '$_temp0';
  }

  @override
  String get invTitle => 'Device inventory';

  @override
  String get invExplain =>
      'Checks address by address which devices on the line respond and reads manufacturer, order number, serial number, firmware and application – without ETS, read-only and with pauses so the bus stays free. With a project: shows what is missing or was replaced. Takes a few minutes depending on the range.';

  @override
  String get invStart => 'Start inventory';

  @override
  String get invFound => 'Found';

  @override
  String get invMatch => 'Matches project';

  @override
  String get invSerialMismatch => 'Serial differs';

  @override
  String get invNotInProject => 'Not in project';

  @override
  String get invTunnel => 'Tunnel address';

  @override
  String get invMissing => 'No response';

  @override
  String get invUnknown => 'Unclear (gateway did not confirm)';

  @override
  String get invShare => 'Share as table';

  @override
  String get invFileName => 'KNX device inventory';

  @override
  String get secTitle => 'Security check';

  @override
  String get secTool => 'Check Secure usage and unknown senders';

  @override
  String get secExplain =>
      'A calm look at the installation’s security: how does the app connect, how much is protected with Data Secure, and do devices send that are not in the project? These are recommendations – many installations run for years without Secure as long as the bus is not reachable from outside.';

  @override
  String get secMetricLink => 'Connection';

  @override
  String get secMetricGateway => 'Gateway';

  @override
  String get secMetricProject => 'Secure in project';

  @override
  String get secMetricSeen => 'Secure in traffic';

  @override
  String get secGatewaySecure => 'supports Secure';

  @override
  String get secGatewayPlain => 'no Secure';

  @override
  String get secLinkSecureTitle => 'Connection encrypted';

  @override
  String get secLinkSecureText =>
      'The app talks to the gateway via KNX IP Secure. Anyone listening on the network sees no telegrams and cannot inject any.';

  @override
  String get secLinkDirectTitle => 'Directly on the bus';

  @override
  String get secLinkDirectText =>
      'The box is connected to the bus via the KNX HAT; there is no KNX IP path between app and bus.';

  @override
  String get secLinkPlainCouldTitle => 'Gateway supports Secure – not in use';

  @override
  String get secLinkRoutingCouldTitle => 'Routing without Secure although the device supports it';

  @override
  String get secLinkPlainCouldText =>
      'The connection is unencrypted. That is common in a home network; if you share the network with guests, cameras or IoT devices, enable IP Secure in ETS and connect with the keyring in the app.';

  @override
  String get secLinkPlainTitle => 'Tunnel without encryption';

  @override
  String get secLinkRoutingTitle => 'Routing without encryption';

  @override
  String get secLinkPlainText =>
      'The gateway has not (yet) reported whether it supports Secure. Unencrypted is fine on your own network as long as port 3671 is not reachable from the internet.';

  @override
  String get secLinkPlainNoSecureText =>
      'The gateway does not offer IP Secure. Keep it on a network with trusted devices only and never expose port 3671 to the internet.';

  @override
  String get secLinkUnknownTitle => 'Connection path unknown';

  @override
  String get secLinkUnknownText => 'The app is attached to Home Assistant; it cannot see how that connects to the bus.';

  @override
  String get secDataNoKeyringTitle => 'No keyring loaded';

  @override
  String get secDataNoKeyringText =>
      'Without a keyring the app cannot tell which group addresses are protected with Data Secure. No secured telegram has been seen so far.';

  @override
  String secDataNoKeyringSeen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count telegrams were protected with Data Secure',
      one: '1 telegram was protected with Data Secure',
    );
    return '$_temp0 – load the keyring from ETS to read them.';
  }

  @override
  String get secDataNoneTitle => 'No Data Secure addresses';

  @override
  String get secDataNoneText =>
      'The keyring holds no keys for group addresses. Data Secure is worth it for door openers, alarms or access – rarely needed for lights and blinds.';

  @override
  String get secDataTitle => 'Data Secure in use';

  @override
  String secDataText(int project, int groups, int seen, int seenAll) {
    return '$project of $groups group addresses in the project are secured; in traffic so far $seen of $seenAll.';
  }

  @override
  String get secWithoutKeyTitle => 'Secured telegrams without key';

  @override
  String secWithoutKeyText(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count telegrams', one: '1 telegram');
    return '$_temp0 could not be decrypted. Usually the keyring is older than the project – export it again from ETS.';
  }

  @override
  String get secRejectedTitle => 'Invalid secured telegrams';

  @override
  String secRejectedText(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count telegrams', one: '1 telegram');
    return '$_temp0 had a wrong checksum or an old counter. A few happen after a restart; if they pile up, check who sends them.';
  }

  @override
  String get secForeignNoProjectTitle => 'Senders cannot be checked';

  @override
  String get secForeignNoProjectText => 'Checking senders needs a .knxproj with topology.';

  @override
  String get secForeignNoneTitle => 'All senders are in the project';

  @override
  String get secForeignNoneText => 'Every telegram in the log came from a device known to ETS.';

  @override
  String secForeignTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count senders not in the project',
      one: '1 sender not in the project',
    );
    return '$_temp0';
  }

  @override
  String get secForeignText =>
      'Usually harmless: visualisations, logic modules or tunnels of other apps. Check unknown addresses in diagnostics; a device nobody knows is worth tracking down.';

  @override
  String get secForeignList => 'Unknown senders';

  @override
  String secForeignRow(int count, String groups) {
    return '$count× · $groups';
  }

  @override
  String get forumTitle => 'For the forum';

  @override
  String forumExplain(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count telegrams', one: '1 telegram');
    return '$_temp0 as text to paste into the KNX user forum. IP addresses, host names, serial numbers, passwords and keys are never included.';
  }

  @override
  String get forumPseudonymize => 'Replace names';

  @override
  String get forumPseudonymizeHint => 'Group addresses become “GA 1”, devices keep only the product name.';

  @override
  String get forumCopy => 'Copy to clipboard';

  @override
  String get forumCopied => 'Forum text copied';

  @override
  String get forumPreview => 'Preview';

  @override
  String get forumHeading => 'Log from KNX Monitor';

  @override
  String get forumTelegrams => 'Telegrams';

  @override
  String get forumGroups => 'Group addresses';

  @override
  String get forumDevices => 'Devices';

  @override
  String get forumColumnGroup => 'GA';

  @override
  String get forumOwn => 'this app';

  @override
  String get forumNoDpt => 'DPT ?';

  @override
  String forumPseudoGroup(int n) {
    return 'GA $n';
  }

  @override
  String forumPseudoDevice(int n) {
    return 'Device $n';
  }

  @override
  String forumMetaApp(String version) {
    return 'KNX Monitor $version';
  }

  @override
  String forumMetaConnection(String kind) {
    return 'Connection: $kind';
  }

  @override
  String forumMetaRange(int count, String date, String from, String to) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count telegrams', one: '1 telegram');
    return '$_temp0 on $date, $from–$to';
  }

  @override
  String forumMetaShortened(int count) {
    return 'shortened to the first $count';
  }

  @override
  String get etsTasks => 'Tasks for ETS';

  @override
  String get etsTasksHint =>
      'One page per device with drawing, channels and tasks to tick off; changed data types as an ETS import.';

  @override
  String get etsTasksNone => 'No tasks: the project passes all checks.';

  @override
  String get etsTasksBuilding => 'Creating tasks …';

  @override
  String etsTasksDrawing(String device) {
    return 'Drawing $device …';
  }

  @override
  String get etsHowTo =>
      'One page per device: the drawing with its channels, the tasks to tick off and the channel assignment from the project. Then import the project into KNX Monitor again; the project check shows what is done.';

  @override
  String get etsSummaryDevices => 'Devices';

  @override
  String get etsSummaryTasks => 'Tasks';

  @override
  String get etsSummaryHints => 'Notes';

  @override
  String get etsOverview => 'Overview';

  @override
  String get etsInProject => 'In the project';

  @override
  String get etsNew => 'New';

  @override
  String get etsImportNote =>
      'Attached as a file for the ETS group address import (Group Addresses › Import): data types, names and new addresses. Preview: test on a copy of the project first.';

  @override
  String etsDevice(String address) {
    return 'Device $address';
  }

  @override
  String get etsTasksOnPage => 'Tasks';

  @override
  String get etsChannels => 'Channel assignment';

  @override
  String get etsColumnChannel => 'Channel';

  @override
  String get etsColumnObject => 'Object';

  @override
  String get etsColumnGroup => 'Group address';

  @override
  String get etsColumnFlags => 'Flags';

  @override
  String etsObject(int number) {
    return 'Object $number';
  }

  @override
  String etsAlsoSends(String devices) {
    return 'also sending: $devices';
  }

  @override
  String get etsNoChannels => 'No linked objects';

  @override
  String etsTodoDpt(String dpt) {
    return 'Set the group address data type to $dpt.';
  }

  @override
  String get etsTodoStatusNoTransmit =>
      'Set the T flag on the object that provides the status (usually the actuator channel).';

  @override
  String get etsTodoReadNoReadFlag => 'Set the R flag on the object that provides the status.';

  @override
  String get etsTodoNoComm => 'Set the C flag or remove the group address from the object.';

  @override
  String get etsTodoMultipleSenders =>
      'Check whether intended; otherwise let only one object send or give it its own address.';

  @override
  String get etsTodoNoLinks => 'Link group addresses or remove the device from the project.';

  @override
  String get etsImportFile => 'Group addresses ETS import (preview)';

  @override
  String get etsHint => 'Note';

  @override
  String get etsTitleNoComm => 'Object without C flag';

  @override
  String get etsTitleNoLinks => 'Device without links';

  @override
  String etsTaskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count tasks', one: '1 task');
    return '$_temp0';
  }

  @override
  String etsHintCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count notes', one: '1 note');
    return '$_temp0';
  }

  @override
  String get etsSummaryImport => 'For the import';

  @override
  String get etsImportSection => 'Group address import';

  @override
  String get etsGroupsSection => 'Group addresses';

  @override
  String get etsProjectSection => 'Project';

  @override
  String get etsTitleLearnedName => 'Name from teach-in';

  @override
  String get etsTitleLearnedNew => 'New address from teach-in';

  @override
  String get etsTitleNoName => 'No name';

  @override
  String get etsTitleNoDpt => 'No data type';

  @override
  String get etsTitleNotInProject => 'On the bus, not in the project';

  @override
  String get etsTitleSerial => 'Serial number differs';

  @override
  String get etsTitleMissing => 'Does not answer';

  @override
  String etsTodoLearnedName(String name) {
    return 'Take over the name “$name” – the group address import does this.';
  }

  @override
  String etsTodoLearnedNew(String name) {
    return 'Create the address “$name” – the group address import does this; then link it to the objects.';
  }

  @override
  String get etsTodoNoName => 'Give it a meaningful name: floor, room, object, function.';

  @override
  String get etsTodoNoDpt =>
      'Set the data type to match the linked object – or set it in the app, then it goes with the import.';

  @override
  String get etsTodoWithoutSender =>
      'Link a sender, or add the visualisation, logic or panel as a placeholder device with this address.';

  @override
  String get etsTodoWithoutReceiver =>
      'Link a receiving object (C and W flags) or delete the address if it is not needed.';

  @override
  String get etsTodoMainGroup1415 =>
      'Move addresses used across lines to main groups 0–13 or check the couplers’ filter tables.';

  @override
  String get etsTodoMultipleReadAnswers =>
      'Keep the R flag only on the object that holds the state, remove it from the others.';

  @override
  String get etsTodoNotInProject =>
      'Add the device to the project (topology, individual address) or find out where it comes from.';

  @override
  String etsTodoSerial(String serial) {
    return 'The device was probably replaced: enter serial number $serial in the project and download the application again.';
  }

  @override
  String get etsTodoMissing =>
      'Check whether the device is connected and programmed – it did not answer during the inventory.';

  @override
  String etsTodoCrowdedLine(String line, int count) {
    return 'Line $line has $count devices: plan a reserve; for extensions a new line or a line repeater.';
  }

  @override
  String get etsTitleDpt => 'Data type';

  @override
  String get planOneInstallationTitle => 'One installation';

  @override
  String get planOneInstallationHere =>
      'There is one installation here. Several installations side by side are available in the app for iPhone, iPad, Android and Mac (Plus or Pro).';

  @override
  String get huntToolAddon => 'Catch sporadic faults over days – in the add-on';

  @override
  String get huntExplainAddon =>
      'For faults that only happen sometimes: the add-on runs around the clock, the hunt catches every hit of a watcher with two minutes before and one after. Afterwards you see who sent it – often it is always the same one.';

  @override
  String get huntOnlyWindowExplainAddon => 'e.g. at night from 22:00 to 06:00 (Home Assistant time)';

  @override
  String get secLinkDemoTitle => 'Demo house';

  @override
  String get secLinkDemoText =>
      'The demo house has no real bus. At your installation the check shows here how the app connects to the gateway – encrypted or not.';

  @override
  String get addonConfigLost => 'The continuous recording settings were damaged – please connect once more.';

  @override
  String get learnRoleAlsoSeen => 'Also seen';

  @override
  String get checkDemoNoFlags =>
      'The demo house has no flags – at your installation the check reads them from the ETS project';

  @override
  String get learnWarmUp => 'Listening for a moment to get to know your bus … Please don\'t press anything yet.';

  @override
  String get invPresent => 'Found';

  @override
  String invManufacturerId(String id) {
    return 'Manufacturer $id';
  }

  @override
  String get ackTestTitle => 'Did you hear it?';

  @override
  String get ackTestText => 'The app just played the acknowledgement tone. Heard it? Then off you go.';

  @override
  String get ackTestNotHeard =>
      'Nothing? Turn the volume up, switch off silent mode (iPhone: switch or Control Centre) and check Bluetooth headphones. Then try again.';

  @override
  String get ackTestNo => 'Didn’t hear it';

  @override
  String get ackTestAgain => 'Play again';

  @override
  String get ackTestYes => 'Heard it, start';

  @override
  String get companyTitle => 'Company';

  @override
  String get companyFeature => 'Company letterhead on all PDFs';

  @override
  String get companyTool => 'Logo and address for the letterhead on PDFs';

  @override
  String get companyExplain =>
      'These details appear as a letterhead on all PDFs. They apply to all installations and stay on this device.';

  @override
  String get companyPreview => 'Letterhead preview';

  @override
  String get companyPreviewEmpty => 'Your company name';

  @override
  String get companyLogo => 'Logo';

  @override
  String get companyLogoPick => 'Choose logo';

  @override
  String get companyLogoReplace => 'Replace logo';

  @override
  String get companyLogoHint => 'PNG, JPEG or SVG. The image is scaled down automatically.';

  @override
  String get companyLogoFailed => 'This image can\'t be read. Please try a PNG or JPEG.';

  @override
  String get companyDetails => 'Details';

  @override
  String get companyName => 'Company name';

  @override
  String get companyAddress => 'Address';

  @override
  String get companyPhone => 'Phone';

  @override
  String get companyEmail => 'Email';

  @override
  String get companyWebsite => 'Website';

  @override
  String get companyVatId => 'VAT ID (optional)';

  @override
  String get companyRegistration => 'Registration (optional)';

  @override
  String get companyTechnician => 'Technician on this device';

  @override
  String get companySaved => 'Saved.';

  @override
  String pdfTechnicianLine(String name) {
    return 'Technician: $name';
  }

  @override
  String get menuGroupDocuments => 'Documents & customers';

  @override
  String get srTitle => 'Service report';

  @override
  String get srTool => 'Report for the customer from recording, comments and health check';

  @override
  String get srFeature => 'Service report for the customer';

  @override
  String get srExplain =>
      'Describe in plain words what was wrong and what you did. The recording and health check are added as evidence. Once created, the report is stored unchanged.';

  @override
  String get srPdfTitle => 'Service report';

  @override
  String get srVisitSection => 'The visit';

  @override
  String get srOccasion => 'Reason for the visit';

  @override
  String get srOccasionHint => 'e.g. hallway light came on by itself at night';

  @override
  String get srObserved => 'What we observed';

  @override
  String get srObservedHint => 'What could be seen, and when did it happen?';

  @override
  String get srDone => 'What we did';

  @override
  String get srDoneHint => 'e.g. readjusted the motion sensor';

  @override
  String get srRecommendation => 'Our recommendation';

  @override
  String get srRecommendationHint => 'What should happen next?';

  @override
  String get srEvidenceSection => 'Evidence';

  @override
  String get srRecording => 'Recording';

  @override
  String get srRecordingNone => 'No recording';

  @override
  String get srUseHealth => 'Include the latest health check';

  @override
  String get srSignatureOptional => 'Signature (optional)';

  @override
  String get srSigned => 'Signed – change';

  @override
  String get srCreate => 'Create and share report';

  @override
  String get srEarlier => 'Earlier reports';

  @override
  String get srResultGood => 'Result: There are no open issues.';

  @override
  String srResultAttention(int count) {
    return 'Result: $count points need your attention (see below).';
  }

  @override
  String get srMeasurement => 'Our measurement';

  @override
  String srMeasurementText(String start, int minutes, int count) {
    return 'From $start we logged what the devices in your installation send to each other for $minutes minutes. That came to $count messages.';
  }

  @override
  String get srComments => 'Notes from the visit';

  @override
  String get srFindings => 'What the analysis shows';

  @override
  String srHealth(String date) {
    return 'Health check of $date';
  }

  @override
  String get srLevelFix => 'Fix';

  @override
  String get srLevelWatch => 'Keep an eye on';

  @override
  String get srLevelInfo => 'For info';

  @override
  String get srConfirmation => 'The customer received this report and confirmed the visit.';

  @override
  String get customerTitle => 'Customer records';

  @override
  String get customerTool => 'Installations, customers, maintenance and visits';

  @override
  String get customerFeature => 'Installations as customer records with visit history';

  @override
  String get customerSearch => 'Search customer, address, order';

  @override
  String get customerSortName => 'Name';

  @override
  String get customerSortVisit => 'Last visit';

  @override
  String get customerSortMaintenance => 'Maintenance';

  @override
  String get customerNone => 'No matching installation.';

  @override
  String customerLastVisit(String date) {
    return 'Last $date';
  }

  @override
  String get customerDue => 'Maintenance due';

  @override
  String customerNextMaintenance(String date) {
    return 'Next maintenance: $date';
  }

  @override
  String get customerLinkFailed => 'This couldn\'t be opened on this device.';

  @override
  String get customerEdit => 'Edit';

  @override
  String get customerEmpty =>
      'No customer details yet. They stay on this device only and are never part of a diagnostics package.';

  @override
  String get customerPrivate =>
      'Customer details stay on this device and are never part of a diagnostics or handover package.';

  @override
  String get customerName => 'Customer';

  @override
  String get customerAddress => 'Site address';

  @override
  String get customerContact => 'Contact person';

  @override
  String get customerPhone => 'Phone';

  @override
  String get customerEmail => 'Email';

  @override
  String get customerOrder => 'Customer or order number';

  @override
  String get customerNotes => 'Notes';

  @override
  String get customerInterval => 'Maintenance interval in months';

  @override
  String get customerCall => 'Call';

  @override
  String get customerMail => 'Send email';

  @override
  String get customerMap => 'Open in maps';

  @override
  String get customerSwitch => 'Switch to this installation';

  @override
  String get customerHistory => 'Visit history';

  @override
  String get visitAdd => 'Entry';

  @override
  String get visitNone => 'No entries yet.';

  @override
  String get visitConnection => 'Connected';

  @override
  String get visitCommissioning => 'Commissioning';

  @override
  String get visitAcceptance => 'Acceptance protocol';

  @override
  String get visitServiceReport => 'Service report';

  @override
  String get visitFaultReport => 'Fault report';

  @override
  String get visitHandover => 'Handover package created';

  @override
  String get visitManual => 'Own entry';

  @override
  String visitMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get visitDuration => 'Duration in minutes';

  @override
  String get visitText => 'Text';

  @override
  String get installationCustomers => 'Customer records';

  @override
  String get handoverTitle => 'Handover package';

  @override
  String get handoverTool => 'Hand the installation over to the customer\'s app';

  @override
  String get handoverFeature => 'Handover package for the customer\'s app';

  @override
  String get handoverReceiveFeature => 'Open a handover package from your electrician';

  @override
  String get handoverExplain =>
      'One file for your customer\'s app: names of group addresses and devices, structure and gateway. No cloud, no account: it goes by mail, AirDrop or USB stick. Customer details stay here.';

  @override
  String get handoverNeedsCompany => 'Enter your company first. The customer sees it as \"set up by\".';

  @override
  String get handoverContents => 'Contents';

  @override
  String get handoverNoGateway => 'no gateway saved';

  @override
  String get handoverNoProject => 'This installation has no project yet.';

  @override
  String get handoverIncludeKeys => 'Include KNX Secure keys';

  @override
  String get handoverIncludeKeysHint => 'Only if the customer needs them. The file is then always password-protected.';

  @override
  String get handoverProtect => 'Protect with password';

  @override
  String get handoverPassword => 'Password';

  @override
  String get handoverQrLabel => 'QR code with the password';

  @override
  String get handoverCopyPassword => 'Copy';

  @override
  String get handoverNewPassword => 'New password';

  @override
  String get handoverPasswordHint =>
      'Pass the password on separately from the file, ideally the customer scans the QR code on site. It is not stored anywhere.';

  @override
  String get handoverCreate => 'Create and share package';

  @override
  String handoverFilePrefix(String name) {
    return 'Handover $name';
  }

  @override
  String get handoverScanTitle => 'Scan QR code';

  @override
  String get handoverWrongPassword => 'The password is wrong or the file was changed.';

  @override
  String get handoverOpen => 'Open';

  @override
  String get handoverOpening => 'Opening package …';

  @override
  String get handoverUnknownCompany => 'your electrician';

  @override
  String handoverImportTitle(String company) {
    return 'Set up installation from $company?';
  }

  @override
  String get handoverImportKeys => 'Contains KNX Secure keys.';

  @override
  String get handoverImportReplaces => 'The current project will be replaced.';

  @override
  String handoverImported(String name, String company) {
    return '$name is set up, by $company.';
  }

  @override
  String handoverSetUpBy(String company) {
    return 'Set up by $company';
  }

  @override
  String get packageCorrupt => 'This file can\'t be read. It is damaged or not a KNX Monitor package.';

  @override
  String get packageNewer => 'This file comes from a newer version. Please update the app.';

  @override
  String get packageTooLarge =>
      'This file is too large to open directly. Please choose it in the app with “Open package or report”.';

  @override
  String get packageUnreadable =>
      'This file could not be read. Please open it again or choose it in the app with “Open package or report”.';

  @override
  String get packageOpenMenu => 'Open package or report';

  @override
  String faultReportTo(String company) {
    return 'Report to $company';
  }

  @override
  String get faultReportTool => 'Report a fault to your electrician with real data';

  @override
  String faultExplain(String company) {
    return 'Briefly describe what happened. This creates a file for $company with the recording, your marks and screenshots.';
  }

  @override
  String get faultProblem => 'What happened?';

  @override
  String get faultProblemHint => 'e.g. bathroom light won\'t turn off';

  @override
  String get faultSend => 'Create and send file';

  @override
  String faultSentHint(String company) {
    return 'Send the file to $company by mail or message.';
  }

  @override
  String get faultPrivacy =>
      'The file contains no keys and no passwords. It contains this session\'s telegrams, your comments and the app log, and if you choose also names and screenshots. It only goes to the company you send it to: there is no cloud and no account.';

  @override
  String get faultFilePrefix => 'Fault report';

  @override
  String faultPickInstallation(String name) {
    return 'Which installation does the report from \"$name\" belong to?';
  }

  @override
  String faultReceived(String name) {
    return 'The report is now in the history of $name.';
  }

  @override
  String get manualTitle => 'Resident manual';

  @override
  String get manualTool => 'Booklet for residents from the project and learned names';

  @override
  String get manualFeature => 'Resident manual as PDF';

  @override
  String get manualExplain =>
      'A booklet for the people living with the installation: by room, without addresses or jargon. Feedback addresses and technical items are left out.';

  @override
  String manualSummary(int rooms, int count) {
    return '$rooms areas, $count functions';
  }

  @override
  String get manualNote => 'Your own notes';

  @override
  String get manualNoteHint => 'e.g. main switch and fuses are in the basement';

  @override
  String get manualCreate => 'Create and share manual';

  @override
  String get manualEmpty => 'A manual needs a project or learned names.';

  @override
  String get manualPdfTitle => 'Manual for your installation';

  @override
  String get manualIntro =>
      'This booklet explains what your electrical installation can do in each room. The wall switches work as usual; everything else runs in the background.';

  @override
  String get manualOther => 'Other functions';

  @override
  String get manualNoteLabel => 'Notes from us';

  @override
  String get manualTroubleTitle => 'If something doesn\'t work';

  @override
  String get manualTrouble1 => 'Press the switch again and wait a moment.';

  @override
  String get manualTrouble2 => 'Check whether other things in the room are affected and note it down.';

  @override
  String get manualTrouble3 => 'Don\'t replace fuses yourself, please call us.';

  @override
  String get manualContact => 'How to reach us';

  @override
  String get manualKindOnOff => 'Turn on and off';

  @override
  String get manualKindDim => 'Brighter and dimmer';

  @override
  String get manualKindPercent => 'Adjust continuously';

  @override
  String get manualKindBlinds => 'Move up and down';

  @override
  String get manualKindOpenClose => 'Open and close';

  @override
  String get manualKindScene => 'Recall a scene';

  @override
  String get manualKindTemperature => 'Shows the room temperature';

  @override
  String get manualKindSetpoint => 'Set the desired temperature';

  @override
  String get manualKindMeasure => 'Shows a measured value';

  @override
  String get manualKindOther => 'Function of the installation';

  @override
  String get bizStandardTitle => 'Company standard';

  @override
  String get bizAssistantTitle => 'GA assistant';

  @override
  String get bizCheckTitle => 'Check against the standard';

  @override
  String get bizNotesTitle => 'Site notes';

  @override
  String get etsTitleStandard => 'Deviation from the standard';

  @override
  String get bizSendCancelled => 'Not sent.';

  @override
  String get bizSurveyTitle => 'Site survey';

  @override
  String get galleryTitle => 'Template gallery';

  @override
  String get galleryIntro =>
      'Ready-made chart templates with roles instead of addresses. They ship with the app, nothing is downloaded. Adopting puts a template in your library and applies it to this installation\'s project.';

  @override
  String get gallerySearch => 'Search';

  @override
  String get galleryNoMatch => 'No template matches your search.';

  @override
  String galleryFits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Fits this project $count times',
      one: 'Fits this project once',
    );
    return '$_temp0';
  }

  @override
  String get galleryFitsNothing => 'Finds no matching addresses in this project yet';

  @override
  String galleryAdopted(String name) {
    return '“$name” is now in your library';
  }

  @override
  String get gallerySubmit => 'Submit your own template';

  @override
  String get gallerySubmitHint =>
      'Pick a chart. The app turns it into a file with name and roles, without addresses or rooms. Share it yourself, for example by mail to support@knx-monitor.de; nothing is uploaded.';

  @override
  String get gallerySubmitNone => 'No saved chart with recognisable roles yet.';

  @override
  String get siteDocsTitle => 'Photos and labels';

  @override
  String get siteDocsTool => 'Photos of the distribution board, labels with QR code';

  @override
  String get siteDocsPhotos => 'Photos';

  @override
  String get siteDocsPhotosHint =>
      'Photos stay on this device in the installation\'s folder and go when the installation is deleted. They are not part of the diagnostics or handover package; they only get into a service report if you pick them there. Location and device data are removed from the image.';

  @override
  String get siteDocsTakePhoto => 'Take photo';

  @override
  String get siteDocsPickPhoto => 'Choose image';

  @override
  String get siteDocsCaption => 'Caption';

  @override
  String get siteDocsCaptionHint => 'e.g. basement board, row 2';

  @override
  String get siteDocsNoCaption => 'No caption';

  @override
  String get siteDocsDelete => 'Delete photo';

  @override
  String get siteDocsQuota => 'No more room for photos of this installation. Delete older ones first.';

  @override
  String get siteDocsUnreadable => 'The image could not be read.';

  @override
  String get siteDocsLabels => 'Labels';

  @override
  String get siteDocsLabelsHint =>
      'A4 sheet with 70 × 37 mm labels: individual address, function, location and QR code. The code opens the device only in this app and contains no web address and no credentials.';

  @override
  String get siteDocsLabelsNoProject => 'Labels need devices from an ETS project.';

  @override
  String get siteDocsLabelsCreate => 'Create labels';

  @override
  String get siteDocsLabelsPdf => 'Labels';

  @override
  String siteDocsLabelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Create $count labels',
      one: 'Create 1 label',
    );
    return '$_temp0';
  }

  @override
  String get siteDocsLabelsAll => 'Select all';

  @override
  String get siteDocsLabelsNone => 'Select none';

  @override
  String get siteDocsScan => 'Scan label';

  @override
  String siteDocsScanOther(String device, String name) {
    return 'Device $device belongs to installation “$name”. Switch to it first.';
  }

  @override
  String siteDocsScanUnknown(String device) {
    return 'Device $device belongs to an installation that is not on this device.';
  }

  @override
  String get siteDocsScanForeign => 'This is not a KNX Monitor label.';

  @override
  String get srPhotos => 'Photos';

  @override
  String get srPhotosHint => 'Only the ticked photos go into the report.';

  @override
  String get loadTitle => 'Current and load';

  @override
  String get loadTool => 'Current and power per channel, peak, deviations';

  @override
  String get loadExplain =>
      'Values from actuators with current measurement, only from telegrams already on the bus. The app requests nothing; how current a value is depends on how the actuator sends.';

  @override
  String get loadNone => 'No current or power values found';

  @override
  String get loadNoneDetail =>
      'Recognised are addresses with data type 7.012, 9.021, 14.019, 9.024 or 14.056 and numeric addresses named like “current” or “power”.';

  @override
  String get loadNoValues => 'No measurement heard yet';

  @override
  String loadPeak(String value, String when, int count) {
    return 'Peak $value on $when · $count measurements';
  }

  @override
  String loadRulesExplain(int samples, int hours, int percent, int recent) {
    return 'Hints only after $samples measurements over at least $hours hours. Deviation: all of the last $recent values more than $percent % off the usual (median), a single outlier does not count. Loads that are often off report no failure.';
  }

  @override
  String loadHintSilent(String typical, int minutes, String time) {
    return 'Probably stopped sending: usually about every $minutes min, last at $time. Usual value $typical.';
  }

  @override
  String loadHintDropped(String typical, String latest) {
    return 'Probably failed or switched off: usually $typical, latest $latest.';
  }

  @override
  String loadHintDeviation(String typical, String latest, String percent) {
    return 'Deviates: usually $typical, latest $latest ($percent %). Something probably changed at the load.';
  }

  @override
  String get checkFilterTitle => 'Couplers: filter tables';

  @override
  String get checkFilterHint =>
      'Filter tables are neither read nor written. The result comes from the project and overheard traffic and is therefore only an assumption.';

  @override
  String get checkFilterLive => 'Current capture';

  @override
  String checkFilterCrossRow(String senders, String receivers) {
    return 'Sender on $senders, receiver on $receivers: presumably only arrives if the coupler\'s filter table knows it';
  }

  @override
  String checkFilterConfirmedRow(String lines) {
    return 'Seen on $lines from another line, the crossing presumably works';
  }

  @override
  String checkFilterMissingRow(String seen, int count, String missing) {
    return 'Seen on $seen ($count×), not on $missing, although a receiver sits there. The address is presumably missing from the filter table or the table was not reloaded.';
  }

  @override
  String get checkFilterNoPoints =>
      'A comparison on the bus needs two simultaneous captures on different lines. So far the result comes from the project only.';

  @override
  String get etsTitleFilterCrossLine => 'Addresses across lines';

  @override
  String etsTodoFilterCrossLine(String line, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count addresses run',
      one: '1 address runs',
    );
    return '$_temp0 to line $line. Check whether the coupler to it was downloaded after the last change (filter table); the app cannot see this.';
  }

  @override
  String get etsTitleFilterNotForwarded => 'Presumably filtered by the coupler';

  @override
  String etsTodoFilterNotForwarded(String line) {
    return 'Did not arrive on line $line, although a receiver sits there. Check the coupler\'s filter table in ETS and download it again.';
  }

  @override
  String get plantTitle => 'Installation report';

  @override
  String get plantTool => 'Monthly or quarterly report from box and add-on, as PDF';

  @override
  String get plantIntro =>
      'The box and the add-on condense the operation of the installation into a report: availability, traffic, bus load, silent devices, smoke detectors and batteries. The data stays on the server.';

  @override
  String get plantEnabled => 'Create reports';

  @override
  String get plantEnabledHint => 'Off by default. The first report is created after the current period ends.';

  @override
  String get plantLastError => 'The last run failed; recording continues.';

  @override
  String get plantPeriod => 'Period';

  @override
  String get plantPeriodMonthly => 'Monthly';

  @override
  String get plantPeriodQuarterly => 'Quarterly';

  @override
  String get plantMaintenance => 'Maintenance';

  @override
  String get plantMaintenanceNone => 'No maintenance interval in the customer record.';

  @override
  String get plantNotify => 'Notifications';

  @override
  String get plantNotifyHint =>
      'Off by default. Only a summary such as “report ready: 2 findings”, never addresses, names or values. You choose the destination.';

  @override
  String get plantNotifyTarget => 'Destination';

  @override
  String get plantNotifyOff => 'No notifications';

  @override
  String get plantNotifyWebhook => 'Webhook';

  @override
  String get plantNotifyHa => 'Home Assistant';

  @override
  String get plantNotifyUrl => 'Address';

  @override
  String get plantNotifyTopic => 'Topic';

  @override
  String get plantNotifyToken => 'Access token';

  @override
  String get plantNotifyTokenSet => 'Saved; leave empty to keep it';

  @override
  String get plantNotifyTokenOptional => 'Optional';

  @override
  String get plantNotifyReady => 'When a report is ready';

  @override
  String get plantNotifyUrgent => 'For urgent findings and due maintenance';

  @override
  String get plantNotifySave => 'Save';

  @override
  String get plantNotifyTest => 'Send test';

  @override
  String get plantTestSent => 'Test notification delivered.';

  @override
  String get plantNotifyErrorOff => 'no destination chosen';

  @override
  String get plantNotifyErrorTimeout => 'the destination does not respond';

  @override
  String get plantNotifyErrorInvalid => 'the address or topic is invalid';

  @override
  String get plantNotifyErrorNetwork => 'no connection to the destination';

  @override
  String get plantReports => 'Reports';

  @override
  String get plantNoReports => 'No report yet.';

  @override
  String get plantGenerateNow => 'Create interim report';

  @override
  String get plantGenerating => 'Creating report …';

  @override
  String get plantPartial => 'Interim report';

  @override
  String get plantResultGood => 'Nothing unusual in this period.';

  @override
  String get plantStatusNew => 'new';

  @override
  String get plantStatusUnchanged => 'unchanged';

  @override
  String get plantStatusResolved => 'resolved';

  @override
  String get plantFindings => 'Findings';

  @override
  String get plantFindingsNone => 'No findings.';

  @override
  String get plantResolved => 'Resolved since the last report';

  @override
  String get plantSafety => 'Smoke detectors, faults, batteries';

  @override
  String get plantSafetyHint =>
      'Last known state, recognised by name and data type in the project. Does not replace testing the detectors.';

  @override
  String get plantSafetyActive => 'active';

  @override
  String get plantSafetyOk => 'OK';

  @override
  String get plantSafetyUnknown => 'unknown';

  @override
  String get plantOutageList => 'Outages';

  @override
  String get plantOutageOffline => 'server not running';

  @override
  String get plantOutageDisconnected => 'bus not connected';

  @override
  String get plantTopSenders => 'Most active devices';

  @override
  String get plantLines => 'Bus load per line (average / peak hour)';

  @override
  String get plantRepeatList => 'Repeats per device';

  @override
  String get plantPdf => 'As PDF';

  @override
  String get plantPdfName => 'Installation-report';

  @override
  String get plantPdfTitle => 'Installation report';

  @override
  String get plantPdfNote =>
      'Created from the continuous recording. Bus load is an estimate from the telegrams heard; devices behind line couplers are only visible as far as the filters let them through.';

  @override
  String get plantAvailabilityLabel => 'Availability';

  @override
  String get plantTelegramsLabel => 'Telegrams';

  @override
  String get plantLoadLabel => 'Bus load average / peak';

  @override
  String get plantCoverageLabel => 'Days with data';

  @override
  String get visitReport => 'Installation report created';

  @override
  String plantDeviceSilent(String label, String since) {
    return 'Device $label has not answered since $since';
  }

  @override
  String plantCyclicSilent(String label, String since) {
    return '$label normally sends regularly, last on $since';
  }

  @override
  String plantStuck(String label, String since) {
    return '$label: reading has not changed since $since';
  }

  @override
  String plantRepeats(String label, String rate) {
    return 'Device $label repeats $rate % of its telegrams';
  }

  @override
  String plantBusLoad(String rate) {
    return 'Bus load up to $rate % in the peak hour';
  }

  @override
  String plantOutages(String rate) {
    return 'Availability only $rate %';
  }

  @override
  String plantRestarts(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n unexpected server restarts',
      one: '1 unexpected server restart',
    );
    return '$_temp0';
  }

  @override
  String plantAlarmActive(String label, String since) {
    return '$label: alarm active since $since';
  }

  @override
  String plantFaultActive(String label, String since) {
    return '$label: fault active since $since';
  }

  @override
  String plantBatteryLow(String label, String since) {
    return '$label: battery low, reported on $since';
  }

  @override
  String plantNotifyErrorHttp(String code) {
    return 'the destination returned HTTP $code';
  }

  @override
  String plantTestFailed(String reason) {
    return 'Not delivered: $reason';
  }

  @override
  String plantResultAttention(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n items need attention.',
      one: '1 item needs attention.',
    );
    return '$_temp0';
  }

  @override
  String plantEntryFindings(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n findings',
      one: '1 finding',
      zero: 'No findings',
    );
    return '$_temp0';
  }

  @override
  String plantEntryNew(int n) {
    return '$n new';
  }

  @override
  String plantEntryResolved(int n) {
    return '$n resolved';
  }

  @override
  String plantCoverage(int days, int total) {
    return 'Data for $days of $total days';
  }

  @override
  String plantAvailability(String rate) {
    return 'Availability $rate %';
  }

  @override
  String plantTelegrams(int n) {
    return '$n telegrams';
  }

  @override
  String plantLoad(String average, String peak) {
    return 'Bus load $average % / peak $peak %';
  }

  @override
  String get crashTitle => 'KNX Monitor ended unexpectedly';

  @override
  String get crashReport => 'Create report';

  @override
  String get crashDismiss => 'Dismiss';

  @override
  String get restartReasonError => 'error in the server';

  @override
  String get restartReasonHost => 'device restarted or power failure';

  @override
  String get restartReasonUnknown => 'reason unknown';

  @override
  String crashBody(String time) {
    return 'Last in the foreground: $time. Nothing is sent automatically. The report shows the cleaned log in the diagnostics package, and you decide whether to share it.';
  }

  @override
  String serverRestarts(int count, String time, String reason) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unexpected restarts',
      one: '1 unexpected restart',
    );
    return '$_temp0 in 30 days, last $time ($reason)';
  }

  @override
  String findingRestarts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unexpected server restarts',
      one: '1 unexpected server restart',
    );
    return '$_temp0 in the last 30 days';
  }

  @override
  String plantBusErrors(String rate) {
    return '$rate % of telegrams rejected or damaged (bus monitor)';
  }

  @override
  String get dataExportTitle => 'Data export';

  @override
  String get dataExportTool => 'Counters and values to InfluxDB or Prometheus, with a Grafana template';

  @override
  String get dataExportIntro =>
      'For your own Grafana server. Off by default. Nothing leaves unless you enter a destination below; Prometheus can only fetch from the local network and with a token.';

  @override
  String get dataExportValues => 'Include addresses, names and values';

  @override
  String get dataExportValuesHint =>
      'Otherwise only bus counters. With this switch, names and readings of the installation end up in the database.';

  @override
  String get dataExportPrometheus => 'Prometheus (scrape)';

  @override
  String get dataExportPort => 'Port';

  @override
  String get dataExportTokenSet => 'Access token saved; it will not be shown again.';

  @override
  String get dataExportTokenTitle => 'Token for Prometheus';

  @override
  String get dataExportTokenBody => 'Shown once. Enter it in Prometheus under “authorization: credentials”.';

  @override
  String get dataExportCopy => 'Copy';

  @override
  String get dataExportClose => 'Close';

  @override
  String get dataExportInflux => 'InfluxDB (send)';

  @override
  String get dataExportInfluxUrl => 'Address';

  @override
  String get dataExportInfluxOrg => 'Organisation (InfluxDB 2)';

  @override
  String get dataExportInfluxBucket => 'Bucket (InfluxDB 2)';

  @override
  String get dataExportInfluxDatabase => 'Database (InfluxDB 1)';

  @override
  String get dataExportInfluxToken => 'Access token';

  @override
  String get dataExportInterval => 'Send interval in seconds';

  @override
  String get dataExportTest => 'Test connection';

  @override
  String get dataExportTestOk => 'Test line delivered.';

  @override
  String get dataExportSave => 'Save';

  @override
  String get dataExportGrafana => 'Grafana template';

  @override
  String get dataExportGrafanaHint => 'Load it in Grafana under Dashboards › Import and choose the data source.';

  @override
  String get dataExportGrafanaPrometheus => 'Save for Prometheus';

  @override
  String get dataExportGrafanaInflux => 'Save for InfluxDB';

  @override
  String get dataExportBindError => 'The port is in use. Please choose another one.';

  @override
  String dataExportPortHint(String port) {
    return 'Available at http://<address>:$port/metrics';
  }

  @override
  String get teamTitle => 'Company';

  @override
  String get teamAskTitle => 'Ask the master';

  @override
  String teamPdfChecked(String name, String date) {
    return 'Checked by: $name, $date';
  }

  @override
  String teamPdfApproved(String name, String date) {
    return 'Approved by: $name, $date';
  }

  @override
  String installationDeleteSureTitle(String name) {
    return 'Really delete “$name” for good?';
  }

  @override
  String get installationDeleteSureBody =>
      'This cannot be undone. Signed acceptance protocols and service reports, customer data, visit history, photos, the ETS project, keyring and long-term history are gone from this device for good. Save whatever you need as proof first.';

  @override
  String get installationDeleteSureConfirm => 'Delete for good';

  @override
  String get appLockSettings => 'App lock';

  @override
  String get appLockExplain =>
      'Protects the app if the device is lost or stolen: At start and after the chosen time in the background, someone has to identify themselves. The bus keeps running meanwhile.';

  @override
  String get appLockTitle => 'KNX Monitor is locked';

  @override
  String get appLockReason => 'Unlock KNX Monitor';

  @override
  String get appLockSystemHint => 'Unlock with Face ID, fingerprint, Windows Hello or the device passcode.';

  @override
  String get appLockPasswordHint => 'Unlock with the app password.';

  @override
  String get appLockPassword => 'App password';

  @override
  String get appLockUnlock => 'Unlock';

  @override
  String get appLockWrong => 'That did not work. After several failed attempts you have to wait.';

  @override
  String get appLockForgot => 'Forgot password';

  @override
  String get appLockForgotTitle => 'Forgot your password?';

  @override
  String get appLockForgotBody =>
      'The app password cannot be reset, otherwise the lock would be worthless. You can only delete all of the app\'s data on this device: projects, recordings, customer data and keys.';

  @override
  String get appLockForgotBodyTeam =>
      'The app password cannot be reset, otherwise the lock would be worthless. You can only delete all of the app\'s data on this device: projects, recordings, customer data, keys and the sign-in.';

  @override
  String get appLockForgotContinue => 'Continue';

  @override
  String get appLockForgotSureTitle => 'Really delete everything?';

  @override
  String get appLockForgotSureBody =>
      'This cannot be undone. Only what is in a backup of your own comes back. The app quits afterwards.';

  @override
  String get appLockForgotSureBodyTeam =>
      'This cannot be undone. Only what is in your account, your company or a backup of your own comes back. The app quits afterwards.';

  @override
  String get appLockForgotConfirm => 'Delete everything';

  @override
  String get appLockRequiredTitle => 'Set up a lock';

  @override
  String get appLockRequiredBody =>
      'You work in a company and have customer data on this device. That is why the app needs a lock.';

  @override
  String get appLockRequiredNote => 'Your company requires the lock while you are a member.';

  @override
  String get appLockUseSystem => 'Use device lock';

  @override
  String get appLockSystemFailed => 'The device lock did not confirm. Try again or use an app password.';

  @override
  String get appLockNewPassword => 'New app password';

  @override
  String get appLockRepeatPassword => 'Repeat app password';

  @override
  String get appLockUsePassword => 'Use app password';

  @override
  String get appLockPasswordWarning =>
      'Nobody can reset the app password. That is why you get a recovery key next. Without both, the only option is to delete the app\'s data on this device.';

  @override
  String get appLockActiveSystem => 'On, with the device lock.';

  @override
  String get appLockActivePassword => 'On, with the app password.';

  @override
  String get appLockTimeout => 'Lock after';

  @override
  String get appLockTimeoutNow => 'At once';

  @override
  String get appLockOff => 'Turn off lock';

  @override
  String get appLockMismatch => 'The two passwords do not match.';

  @override
  String appLockTooShort(int count) {
    return 'At least $count characters.';
  }

  @override
  String appLockTimeoutMinutes(int count) {
    return '$count min';
  }

  @override
  String get backupTitle => 'Backup';

  @override
  String get backupExplain =>
      'Saves everything on this device to a file with its own password: installations, projects, keyrings, customer records, comments, recordings and history. The format is openly documented. Without the password nobody can open the file, including us. Please back up regularly and keep the file somewhere else.';

  @override
  String get backupCreate => 'Create backup';

  @override
  String get backupRestore => 'Restore backup';

  @override
  String get backupPassword => 'Backup password';

  @override
  String get backupRepeat => 'Repeat password';

  @override
  String backupTooShort(int count) {
    return 'At least $count characters.';
  }

  @override
  String get backupMismatch => 'The two passwords do not match.';

  @override
  String get backupSaved => 'Backup saved.';

  @override
  String get backupRestoreTitle => 'Restore backup?';

  @override
  String get backupRestoreBody =>
      'Files with the same name are replaced. The app quits afterwards and starts from the backup\'s state next time.';

  @override
  String get backupOpenFailed => 'That did not work: wrong password or not a valid backup.';

  @override
  String get backupNewer => 'This backup comes from a newer version. Please update the app first.';

  @override
  String get backupNotIncluded => 'Not included: the app lock and history on a box.';

  @override
  String get backupNotIncludedTeam =>
      'Not included: the sign-in, the app lock, a company\'s keys and history on a box.';

  @override
  String get recoveryTitle => 'Recovery key';

  @override
  String get recoveryUse => 'Enter recovery key';

  @override
  String get recoveryExplain =>
      'This gets you into the app if you forget the app password. Please keep it away from this device, for example printed or in a password manager.';

  @override
  String get recoverySavePdf => 'Save as PDF';

  @override
  String get recoveryNoted => 'Noted safely';

  @override
  String get recoveryRenew => 'Create new recovery key';

  @override
  String get recoveryResetBody => 'The recovery key opened the app and is no longer valid. Set a new lock.';

  @override
  String get recoveryPdfIntro => 'This key opens the KNX Monitor app lock if the app password has been forgotten.';

  @override
  String recoveryPdfAccount(String email) {
    return 'Account: $email';
  }

  @override
  String get recoveryPdfUse =>
      'How it works: On the lock screen choose “Enter recovery key”, type the key and set a new password. This key then stops working; the app creates a new one.';

  @override
  String get recoveryPdfLimits =>
      'The key only works on this device. It does not open a backup file and does not replace a backup if the device is lost.';

  @override
  String get recoveryPdfLimitsTeam =>
      'The key only works on this device. It opens neither your account nor a backup file and does not replace a backup if the device is lost.';

  @override
  String get recoveryPdfKeep =>
      'Anyone holding this sheet and the device can get into the app. Keep it separate from the device.';

  @override
  String appLockWait(int seconds) {
    return 'Too many failed attempts. Wait $seconds more seconds, then try again.';
  }

  @override
  String get customerPdf => 'Record as PDF';

  @override
  String get diagNotFiltered =>
      'Not filtered: telegram values (they can reveal when someone is at home), names of group addresses and devices while the switch is on, and names you type into the description or comments yourself.';

  @override
  String get diagShotsTitle => 'Include screenshots';

  @override
  String get diagShotsHint =>
      'Images are not filtered: everything visible goes to the recipient, including names, addresses and customer data. Check them first.';

  @override
  String diagContentShotsOut(int count) {
    return 'Screenshots: $count available, not included';
  }

  @override
  String get historyWithoutTime => 'Without time';

  @override
  String get historyWithoutTimeHint =>
      'The box did not know the time and has restarted. Order and spacing are correct, date and time are not.';

  @override
  String get installationRecovered => 'Recovered site';

  @override
  String get errorNetworkGone => 'The network is gone or has changed.';

  @override
  String get boxShareDiffersTitle => 'Different data on the box';

  @override
  String get boxShareDiffersBody =>
      'The project or keyring on the box differs from this device, and we cannot tell which is newer. While they differ, the box decodes and names telegrams using its own data.';

  @override
  String get boxShareKeep => 'Keep box data';

  @override
  String get boxShareReplace => 'Use this device';

  @override
  String backupEstimate(String size) {
    return 'Data on this device: about $size.';
  }

  @override
  String backupTooLarge(String size, String limit) {
    return 'At $size the data is too large for one backup (maximum $limit). Nothing was saved. Please delete old recordings or history days, or shorten the retention.';
  }

  @override
  String get accountMfaPdfTitle => 'Sign-in key for the authenticator app';

  @override
  String get accountMfaPdfIntro =>
      'With this sheet you get the sign-in codes for your KNX Monitor account back if your phone is gone.';

  @override
  String get accountMfaPdfUse =>
      'How it works: install a new authenticator app, add an account, scan the QR code or type in the key. The app then shows the six-digit codes again.';

  @override
  String get accountMfaPdfWarning =>
      'Anyone who has this sheet can create the codes themselves. Lock it away like a house key, do not photograph it or put it in the cloud. After setting up access again, remove the old app in your account: this sheet is then worthless.';

  @override
  String get backupReminder =>
      'Your last backup is more than 30 days old or still missing. Customer records and sites are only on this device.';

  @override
  String get backupReminderOpen => 'Back up now';

  @override
  String get backupReminderDismiss => 'Later';

  @override
  String backupLast(String date) {
    return 'Last backup on this device: $date';
  }

  @override
  String get backupNever => 'There is no backup from this device yet.';

  @override
  String get backupSlow => 'Encrypting can take up to a minute on older devices.';

  @override
  String get zipTooLarge => 'This file is too large when unpacked and was not opened.';

  @override
  String get installationsNewerTitle => 'Newer data';

  @override
  String get installationsNewerBody =>
      'This data comes from a newer version of KNX Monitor. Please update the app. Your data stays as it is.';

  @override
  String get quarantineTitle => 'Old data can\'t be read';

  @override
  String quarantineBody(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files ($size) can\'t',
      one: 'One file ($size) can\'t',
    );
    return '$_temp0 be opened because the key is missing on this device, for example after moving to a new device. Everything stays on the device. A backup brings your data back.';
  }

  @override
  String get quarantineRestore => 'Restore from a backup';

  @override
  String get quarantineDelete => 'Delete files';

  @override
  String get quarantineDeleteBody => 'These files can never be opened again after this.';

  @override
  String get boxForeignTitle => 'This box is not on your local network';

  @override
  String boxForeignBody(String address) {
    return 'This link leads to $address, which is not an address on your local network. Whoever runs that server gets your ETS project with all addresses and names. Only connect if you run it yourself.';
  }

  @override
  String get boxForeignConfirm => 'Connect anyway';

  @override
  String get boxKeyringTitle => 'Give the keyring to this box?';

  @override
  String boxKeyringBody(String address) {
    return 'The box at $address would get the keys of your KNX Secure installation so it can record secured telegrams in readable form. Anyone with access to the box can reach these keys. Only agree if it is your box.';
  }

  @override
  String get boxKeyringAllow => 'Give keyring';

  @override
  String get boxKeyringDeny => 'Don\'t give';

  @override
  String get historyPausedPlan =>
      'History is paused: long-term history is part of Plus. New telegrams are not saved, existing days are kept.';

  @override
  String backupSideFiles(String size) {
    return 'Older and damaged versions take up another $size.';
  }

  @override
  String get appLockHideTitle => 'Hide in the app switcher';

  @override
  String get appLockHideHint =>
      'Android then shows an empty image in the app switcher, and screenshots of the app no longer work.';

  @override
  String faultShotsLeftOut(int count) {
    return 'Without this switch, screenshots on comments ($count) stay out.';
  }

  @override
  String get boxPasswordMustTitle => 'Set your own box password';

  @override
  String get boxPasswordRequired =>
      'Set your own box password first. Anyone who can see the box can read the one on the sticker.';

  @override
  String get boxPasswordStillSticker =>
      'The password on the sticker is still in use. Anyone who has it can control the box and read the keyring. Set your own below; it is then removed from the SD card.';

  @override
  String get boxPlainWarning =>
      'Unencrypted: this connection crosses your network in plain text, including the device access and the telegrams. Best stay on the box\'s Wi-Fi.';

  @override
  String get boxPlainWarningTls =>
      'Unencrypted: this connection crosses your network in plain text. The box supports HTTPS: create a new QR code on its /pair page and scan it to encrypt the connection.';

  @override
  String get boxWifiChange => 'Change Wi-Fi password';

  @override
  String get boxWifiHint =>
      '8 to 63 characters without spaces and without \" \' \\ \$ `. The Wi-Fi code on the sticker stops working.';

  @override
  String get boxWifiConfirm =>
      'All devices are dropped from the box\'s Wi-Fi and have to rejoin with the new password. This device does that itself where the system allows it.';

  @override
  String get boxWifiChanged => 'Wi-Fi password changed. The box restarts its Wi-Fi in a moment.';

  @override
  String get boxLowSpace =>
      'Storage full: the box is not recording right now. Older days have already been removed. Free some space or shorten the retention and it resumes by itself.';

  @override
  String get cloudSyncFeature => 'Sync between your devices';

  @override
  String get cloudSyncTitle => 'Sync devices';

  @override
  String get hpTitle => 'Home plan';

  @override
  String get hpEntry => 'Plan a home';

  @override
  String get writeNoticeTitle => 'Intervention in the installation';

  @override
  String get writeNoticeBody =>
      'This value goes to the bus and can switch real devices. You are responsible for the switching operation and its consequences. We accept no liability for it, except where the law requires it.';

  @override
  String get writeNoticeHide => 'Don\'t show again';

  @override
  String get writeNoticeHideHint => 'Hiding this is recorded with the date in diagnostics packages and error reports.';

  @override
  String get writeNoticeConfirm => 'Write';

  @override
  String get writeNoticeRestore => 'Show the notice before writing again';

  @override
  String diagContentWriteNotice(String date) {
    return 'Notice before writing: hidden on $date';
  }

  @override
  String get telegramMenuDetails => 'Open details';

  @override
  String get telegramMenuSelect => 'Select';

  @override
  String get scanCameraDenied => 'Camera access is off. Allow it in the device settings, or enter the details by hand.';

  @override
  String get backupShort => 'Everything on this device in one file with its own password.';

  @override
  String get backupAppStorage => 'App storage';

  @override
  String get backupPrevious => 'Previous versions';

  @override
  String get backupLastRow => 'Last backup';

  @override
  String get backupNoneYet => 'None yet';

  @override
  String get appLockMethodSystem => 'Face ID, fingerprint or device passcode';

  @override
  String get appLockMethodPassword => 'With the app password';

  @override
  String get lessonsLessons => 'Lessons';

  @override
  String get lessonsKind => 'Short explanation';

  @override
  String get lessonsPractice => 'Practice';

  @override
  String lessonsTermCount(int count) {
    return '$count terms';
  }

  @override
  String get quizMeta => 'Questions from your installation';

  @override
  String get handoverShort => 'Everything for your customer\'s app in one file.';

  @override
  String get handoverProject => 'Project';

  @override
  String get customerMaintenance => 'Maintenance';

  @override
  String customerMaintEvery(int count) {
    return 'Every $count months';
  }

  @override
  String customerMaintIn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'In $count months',
      one: 'In 1 month',
      zero: 'This month',
    );
    return '$_temp0';
  }

  @override
  String get customerVisitAdd => 'Add visit';

  @override
  String get customerVisits => 'Visits';

  @override
  String get customerDocuments => 'Documents';

  @override
  String get srIncludes => 'Includes';

  @override
  String get reactMedian => 'Median';

  @override
  String get reactSlowest => 'Slowest';

  @override
  String get reactPairs => 'Command and feedback';

  @override
  String get loadChannelsLabel => 'Channels';

  @override
  String get loadHighest => 'Highest value';

  @override
  String get loadConsumers => 'Largest loads';

  @override
  String hpRoomsOf(int shown, int total) {
    return '$shown of $total';
  }

  @override
  String get exportsData => 'Data';

  @override
  String get exportsPermanent => 'Continuous';

  @override
  String get ackLast => 'Last';

  @override
  String get ackHeard => 'Recently heard';

  @override
  String get learnNamed => 'Named';

  @override
  String get learnOpenCount => 'Open';

  @override
  String get learnPressTitle => 'Press a button';

  @override
  String get chartsAddresses => 'Addresses';

  @override
  String get planLicenseEnter => 'Enter license';

  @override
  String get planLicenseField => 'License';

  @override
  String get planLicenseHelp =>
      'Paste the whole line from the email; it starts with KNX1. It works on your own Windows devices.';

  @override
  String get planLicenseApply => 'Activate';

  @override
  String get planLicenseInvalid => 'This license is not valid. Please paste the whole line from the email.';

  @override
  String get planLicenseEnded =>
      'This license no longer applies: the subscription has ended or the purchase was refunded.';

  @override
  String get planLicenseCheckoutOpened =>
      'The checkout is open in your browser. After buying, your license arrives by email; enter it here under “Enter license”.';

  @override
  String planLicenseActive(String tier) {
    return '$tier is activated.';
  }

  @override
  String get addonReadOnly =>
      'Read only is on: the server sends nothing to the bus. Turn off “Read only” in the add-on configuration, or remove READ_ONLY on the box and in Docker.';

  @override
  String get exportsEtsHistory => 'History as ETS file (for Home Assistant and SpectrumKNX)';

  @override
  String get exportsEtsHistoryMeta => 'Continuous recording, up to 30 days';

  @override
  String get exportsEtsHistoryHint =>
      'Downloads the telegrams of the continuous recording as an ETS group monitor file. SpectrumKNX, the ETS and KNX Monitor open it directly.';

  @override
  String get exportsEtsHistoryDownload => 'Download';

  @override
  String get exportsEtsHistoryCancel => 'Cancel';

  @override
  String get exportsEtsHistoryLoading => 'Loading history …';
}
