import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../catalog_store.dart';
import '../knx/gateway_info.dart';
import '../knx/group_catalog.dart';
import '../knx/knx_tunnel.dart';
import '../knx/secure/keyring_store.dart';
import '../knx/shared_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/write_notice.dart';
import '../model/account.dart';
import '../model/activity_range.dart';
import '../model/alarm_notifier.dart';
import '../model/annotation.dart';
import '../model/app_log.dart';
import '../platform/safe_zip.dart';
import '../model/betrieb/team.dart';
import '../model/connection_options.dart';
import '../model/customer.dart';
import '../model/expert_mode.dart';
import '../model/installation.dart';
import '../model/plan.dart';
import '../model/recording.dart';
import '../model/telegram_log.dart';
import '../platform/addon.dart';
import '../platform/os_info.dart';

/// Identifier and version of the package format (in `diagnostics.json`).
const diagnosticsFormat = 'knx-monitor-diagnostics';

/// 2: comments in the recording and screenshots (`shots/`); 1 can still be read.
const diagnosticsFormatVersion = 2;

/// Neutral placeholders for project and installation names.
const placeholderProject = 'Project';
const placeholderInstallation = 'Installation';

/// A Data Secure telegram as it appears on the bus without a keyring: time, source and destination,
/// but no content (type and value are encrypted).
typedef SecureTelegram = ({DateTime time, int source, int destination});

/// Diagnostics package for support: bus recording, project, problem description and technical
/// details as a ZIP. Can be opened again in the app (project + recording) and analysed there.
///
/// The [Scrubber] only removes recognisable patterns and known names. Freely typed names, names of
/// group addresses and devices, and telegram values remain, and telegrams can reveal presence. The
/// package is therefore not "free of personal data"; screenshots are images and are not filtered at
/// all, see `includeShots` in [buildDiagnosticsPackage].
class DiagnosticsPackage {
  DiagnosticsPackage({
    required this.created,
    required this.occurred,
    required this.recording,
    required this.catalog,
    this.problem = '',
    this.expected,
    this.overrides = const {},
    this.projectNames = const {},
    this.technical = const {},
    this.log = const [],
    this.secureTelegrams = const [],
    this.namesIncluded = true,
    this.shots = const {},
    this.packageShots = const [],
  });

  final DateTime created;

  /// When the error occurred.
  final DateTime occurred;

  /// "What happened?" and "What did you expect?"
  final String problem;
  final String? expected;

  /// Telegrams in the recording format (replayable), without Data Secure contents.
  final Recording recording;
  final GroupCatalog catalog;
  final Map<int, Dpt> overrides;

  /// Project names of addresses whose name was corrected in the app; [catalog] has the corrected
  /// ones (`CatalogStore.projectNames`).
  final Map<int, String> projectNames;

  /// Version, platform, connection, plan, settings …
  final Map<String, Object?> technical;

  /// App log messages, scrubbed.
  final List<String> log;
  final List<SecureTelegram> secureTelegrams;

  /// Whether names of group addresses and devices are included.
  final bool namesIncluded;

  /// Screenshots (JPEG) by ID: those of the comments in [recording] and [packageShots].
  final Map<String, Uint8List> shots;

  /// Screenshots for the problem itself, not attached to a comment.
  final List<String> packageShots;

  static const _manifest = 'diagnostics.json';
  static const _recording = 'recording.json';
  static const _project = 'project.json';
  static const _secure = 'secure.json';
  static const _log = 'log.txt';
  static const _shotDir = 'shots/';

  /// Package header (`diagnostics.json`) – also the preview before export.
  Map<String, Object?> get manifest => {
    'format': diagnosticsFormat,
    'version': diagnosticsFormatVersion,
    'created': created.toIso8601String(),
    'occurred': occurred.toIso8601String(),
    'problem': problem,
    'expected': ?expected,
    'namesIncluded': namesIncluded,
    'contents': {
      'telegrams': recording.telegrams.length,
      'from': recording.started.toIso8601String(),
      'to': recording.ended.toIso8601String(),
      'secureTelegramsWithoutContent': secureTelegrams.length,
      'groupAddresses': catalog.length,
      'devices': catalog.devices.length,
      'dptOverrides': overrides.length,
      'nameCorrections': projectNames.length,
      'logLines': log.length,
      'annotations': recording.annotations.length,
      'screenshots': shots.length,
    },
    if (packageShots.isNotEmpty) 'shots': packageShots,
    'technical': technical,
  };

  /// All files of the package with content (for export and tests).
  Map<String, String> get files {
    const json = JsonEncoder.withIndent('  ');
    return {
      _manifest: json.convert(manifest),
      _recording: jsonEncode(recording.toJson()),
      _project: jsonEncode({
        'catalog': catalog.toJson(),
        'overrides': {
          for (final MapEntry(:key, :value) in overrides.entries) '$key': [value.main, value.sub],
        },
        if (projectNames.isNotEmpty)
          'projectNames': {for (final MapEntry(:key, :value) in projectNames.entries) '$key': value},
      }),
      if (secureTelegrams.isNotEmpty)
        _secure: jsonEncode([
          for (final t in secureTelegrams) {'t': t.time.microsecondsSinceEpoch, 's': t.source, 'd': t.destination},
        ]),
      if (log.isNotEmpty) _log: '${log.join('\n')}\n',
    };
  }

  /// [extra]: additional text files (reference of a fault report).
  Uint8List toZip({Map<String, String> extra = const {}}) {
    final archive = Archive();
    for (final MapEntry(key: name, value: content) in {...files, ...extra}.entries) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    for (final MapEntry(key: id, value: jpeg) in shots.entries) {
      archive.addFile(ArchiveFile('$_shotDir$id.jpg', jpeg.length, jpeg));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// Whether this is a ZIP file (for import alongside ETS telegram files).
  static bool looksLikeZip(List<int> bytes) => bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4B;

  /// Reads a package. Throws [FormatException] if it is not one.
  static DiagnosticsPackage fromZip(Uint8List bytes) {
    final Archive archive;
    try {
      archive = decodeZipLimited(bytes);
    } on ZipLimitException {
      throw FormatException(s.zipTooLarge);
    } on Object catch (e) {
      throw FormatException('$e');
    }
    String? read(String name) {
      final f = archive.findFile(name);
      return f == null ? null : utf8.decode(f.content, allowMalformed: true);
    }

    final manifestText = read(_manifest);
    if (manifestText == null) throw FormatException(s.diagPackageInvalid);
    try {
      final m = jsonDecode(manifestText) as Map<String, Object?>;
      if (m['format'] != diagnosticsFormat) throw FormatException(s.diagPackageInvalid);
      if ((m['version'] as int? ?? 0) > diagnosticsFormatVersion) throw FormatException(s.diagPackageNewer);
      final recording = Recording.fromJson(jsonDecode(read(_recording)!) as Map<String, Object?>);
      final project = jsonDecode(read(_project) ?? '{}') as Map<String, Object?>;
      final catalog = project['catalog'] == null
          ? GroupCatalog.empty
          : GroupCatalog.fromJson(project['catalog']! as Map<String, Object?>);
      final overrides = {
        for (final MapEntry(:key, :value) in ((project['overrides'] as Map?) ?? const {}).entries)
          int.parse(key as String): Dpt((value as List)[0] as int, value[1] as int?),
      };
      final projectNames = {
        for (final MapEntry(:key, :value) in ((project['projectNames'] as Map?) ?? const {}).entries)
          int.parse(key as String): value as String,
      };
      final secure = [
        for (final e in (jsonDecode(read(_secure) ?? '[]') as List).cast<Map<String, Object?>>())
          (
            time: DateTime.fromMicrosecondsSinceEpoch(e['t']! as int),
            source: e['s']! as int,
            destination: e['d']! as int,
          ),
      ];
      return DiagnosticsPackage(
        created: DateTime.parse(m['created']! as String),
        occurred: DateTime.parse(m['occurred']! as String),
        problem: m['problem'] as String? ?? '',
        expected: m['expected'] as String?,
        namesIncluded: m['namesIncluded'] != false,
        technical: (m['technical'] as Map?)?.cast<String, Object?>() ?? const {},
        recording: recording,
        catalog: catalog,
        overrides: overrides,
        projectNames: projectNames,
        secureTelegrams: secure,
        log: [...?read(_log)?.split('\n').where((l) => l.isNotEmpty)],
        shots: {
          for (final f in archive.files)
            if (f.isFile && f.name.startsWith(_shotDir) && f.name.endsWith('.jpg'))
              // Only names in our own ID format, nothing with path segments.
              if (f.name.substring(_shotDir.length, f.name.length - 4) case final id when ShotStore.validId(id))
                id: Uint8List.fromList(f.content),
        },
        packageShots: [...?(m['shots'] as List?)?.cast<String>()],
      );
    } on FormatException {
      rethrow;
    } on Object catch (e) {
      // Missing fields, wrong types: not a valid package.
      throw FormatException('${s.diagPackageInvalid} ($e)');
    }
  }
}

/// Removes addresses and identifiers from free text: IP addresses (v4/v6), host names with a known
/// suffix, URLs, e-mail, MAC and KNX serial numbers, and known names (project, installation,
/// customer, business, gateway host) that do not belong in the package. Everything else stays: the
/// pattern does not recognise a freely typed person's name or a host name without a dot.
class Scrubber {
  Scrubber({Iterable<String> known = const []})
    : _known = [
        for (final k in known.map((k) => k.trim()).toSet())
          if (k.length >= 3) k,
      ]..sort((a, b) => b.length.compareTo(a.length));

  final List<String> _known;

  static final _patterns = <(RegExp, String)>[
    // Home folders in file paths (logged paths, FileSystemException texts):
    // the account name is often the real name.
    (RegExp(r'(/Users/|/home/|[A-Za-z]:\\Users\\|[A-Za-z]:/Users/)[^/\\\s"]+', caseSensitive: false), r'$1<home>'),
    (RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+'), '<email>'),
    (RegExp(r'\b[a-z][a-z0-9+.-]*://\S+', caseSensitive: false), '<url>'),
    (RegExp(r'\b[0-9a-f]{2}(?:[:-][0-9a-f]{2}){5}\b', caseSensitive: false), '<mac>'),
    (RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?\b'), '<ip>'),
    (RegExp(r'(?:[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}(?:%\w+)?', caseSensitive: false), '<ip>'),
    (
      RegExp(r'[0-9a-f]{0,4}(?::[0-9a-f]{1,4})*::(?:[0-9a-f]{1,4}(?::[0-9a-f]{1,4})*)?(?:%\w+)?', caseSensitive: false),
      '<ip>',
    ),
    // KNX serial number: 12 hex characters, often as "0083:1A2B3C4D".
    (RegExp(r'\b[0-9a-f]{4}[:.]?[0-9a-f]{8}\b', caseSensitive: false), '<serial>'),
    (
      RegExp(
        r'\b(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:local|lan|home|box|internal|intranet|arpa|localdomain|com|net|org|de|at|ch|eu|io|nl|fr|it|uk|be|dk|se|no|pl|cz)\b',
        caseSensitive: false,
      ),
      '<host>',
    ),
  ];

  String call(String text) {
    var out = text;
    for (final k in _known) {
      out = out.replaceAll(k, '<name>');
    }
    for (final (pattern, replacement) in _patterns) {
      out = out.replaceAll(pattern, replacement);
    }
    return out;
  }

  String? maybe(String? text) => text == null ? null : call(text);

  /// Keys that never belong in the package (credentials and identifiers).
  static final _secretKey = RegExp(
    r'pass|secret|key|token|auth|user|mail|serial|mac|host|^ip$|ssid|address|cert|cookie|session',
    caseSensitive: false,
  );

  /// JSON tree with scrubbed texts; with [dropSecrets] also without sensitive keys (for foreign
  /// data like the add-on status).
  Object? tree(Object? value, {bool dropSecrets = false}) => switch (value) {
    final String text => call(text),
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, value: v) in map.entries)
        if (!dropSecrets || !_secretKey.hasMatch('$key')) '$key': tree(v, dropSecrets: dropSecrets),
    },
    final List<Object?> list => [for (final v in list) tree(v, dropSecrets: dropSecrets)],
    _ => value,
  };
}

/// Catalog without project name and serial numbers; without [keepNames] also without names, paths,
/// locations and descriptions (then addresses and products remain).
GroupCatalog anonymizeCatalog(GroupCatalog c, {required bool keepNames, required Scrubber scrub}) => GroupCatalog(
  {
    for (final g in c.groups.values)
      g.address: GroupInfo(
        address: g.address,
        name: keepNames ? scrub(g.name) : formatGroup(g.address),
        path: keepNames ? scrub.maybe(g.path) : null,
        dpt: g.dpt,
        description: keepNames ? scrub.maybe(g.description) : null,
        links: [
          for (final l in g.links)
            GroupLink(device: l.device, object: l.object, text: keepNames ? scrub.maybe(l.text) : null, sends: l.sends),
        ],
      ),
  },
  devices: {
    for (final d in c.devices.values)
      d.address: DeviceInfo(
        address: d.address,
        name: keepNames ? scrub(d.name) : (scrub.maybe(d.product) ?? formatIndividual(d.address)),
        product: scrub.maybe(d.product),
        manufacturer: d.manufacturer,
        location: keepNames ? scrub.maybe(d.location) : null,
        description: keepNames ? scrub.maybe(d.description) : null,
        tunnelOf: d.tunnelOf,
        neverProgrammed: d.neverProgrammed,
        pendingDownload: d.pendingDownload,
        rf: d.rf,
      ),
  },
  projectName: c.projectName == null ? null : placeholderProject,
  manufacturers: c.manufacturers,
  style: c.style,
  externalSenders: c.externalSenders,
);

/// Assembles the package – purely from the inputs, without app state.
///
/// [telegrams] are limited to [from]…[to]. Telegrams to [secureAddresses] (group addresses with a
/// Data Secure key) are included only with time and addresses, as they would appear without a
/// keyring.
///
/// Screenshots are not filtered. Without [includeShots] they are left out, including those attached
/// to comments. The diagnostics package asks the user about this; the default `true` applies to the
/// fault report, whose images the user attaches there themselves.
DiagnosticsPackage buildDiagnosticsPackage({
  required List<Telegram> telegrams,
  required GroupCatalog catalog,
  required DateTime occurred,
  Map<int, Dpt> overrides = const {},
  Map<int, String> projectNames = const {},
  Set<int> secureAddresses = const {},
  DateTime? from,
  DateTime? to,
  String problem = '',
  String? expected,
  bool keepNames = true,
  Map<String, Object?> technical = const {},
  List<String> log = const [],
  Iterable<String> knownNames = const [],
  List<Annotation> annotations = const [],
  List<Annotation> olderAnnotations = const [],
  Map<String, Uint8List> shots = const {},
  List<String> packageShots = const [],
  bool includeShots = true,
  DateTime? now,
}) {
  final created = now ?? DateTime.now();
  if (!includeShots) {
    shots = const {};
    packageShots = const [];
  }
  final scrub = Scrubber(known: [...knownNames, ?catalog.projectName]);
  // Comments are free text: without names, also without room and device names.
  final scrubNote = keepNames
      ? scrub
      : Scrubber(
          known: [
            ...knownNames,
            ?catalog.projectName,
            for (final g in catalog.groups.values) g.name,
            for (final d in catalog.devices.values) d.name,
          ],
        );
  bool within(DateTime t) => (from == null || !t.isBefore(from)) && (to == null || !t.isAfter(to));
  // Within the time range, plus older comments (outside the recording) on request.
  final notes = [
    for (final a in {
      for (final a in annotations)
        if (within(a.time)) a.id: a,
      for (final a in olderAnnotations) a.id: a,
    }.values)
      a.copyWith(
        note: scrubNote(a.note.trim()),
        shots: [...a.shots.where(shots.containsKey)],
        // Secure telegrams are only included as metadata: their value must not leak through a
        // comment either.
        telegram: switch (a.telegram) {
          final ref? when secureAddresses.contains(ref.destination) => TelegramRef(
            time: ref.time,
            source: ref.source,
            destination: ref.destination,
            type: ref.type,
          ),
          _ => null,
        },
      ),
  ]..sort((a, b) => a.time.compareTo(b.time));
  final usedShots = {...packageShots, for (final a in notes) ...a.shots};
  final inRange = [
    for (final t in telegrams)
      if ((from == null || !t.time.isBefore(from)) && (to == null || !t.time.isAfter(to))) t,
  ]..sort((a, b) => a.time.compareTo(b.time));
  final plain = <Telegram>[];
  final secure = <SecureTelegram>[];
  for (final t in inRange) {
    if (secureAddresses.contains(t.destination)) {
      secure.add((time: t.time, source: t.source, destination: t.destination));
    } else {
      plain.add(_withoutRaw(t));
    }
  }
  String two(int v) => v.toString().padLeft(2, '0');
  final day =
      '${occurred.year}-${two(occurred.month)}-${two(occurred.day)} ${two(occurred.hour)}:${two(occurred.minute)}';
  final recording = Recording(
    id: 'diag-${created.microsecondsSinceEpoch.toRadixString(36)}',
    name: 'Diagnose $day',
    started: from ?? (inRange.isEmpty ? occurred : inRange.first.time),
    ended: to ?? (inRange.isEmpty ? occurred : inRange.last.time),
    project: catalog.projectName == null ? null : placeholderProject,
    telegrams: plain,
    annotations: notes,
  );
  final emptyExpected = expected == null || expected.trim().isEmpty;
  return DiagnosticsPackage(
    created: created,
    occurred: occurred,
    // Description, technical data and log are free text as well: without names
    // they also lose room and device names (log lines name group addresses).
    problem: scrubNote(problem.trim()),
    expected: emptyExpected ? null : scrubNote(expected.trim()),
    recording: recording,
    catalog: anonymizeCatalog(catalog, keepNames: keepNames, scrub: scrub),
    overrides: overrides,
    // Without names the catalog only has addresses: nothing left to correct.
    projectNames: keepNames ? {for (final MapEntry(:key, :value) in projectNames.entries) key: scrub(value)} : const {},
    technical: scrubNote.tree(technical)! as Map<String, Object?>,
    log: [for (final l in log) scrubNote(l)],
    secureTelegrams: secure,
    namesIncluded: keepNames,
    shots: {
      for (final MapEntry(:key, :value) in shots.entries)
        if (usedShots.contains(key)) key: value,
    },
    packageShots: [...packageShots.where(shots.containsKey)],
  );
}

/// Without cEMI raw data: its additional info can carry identifiers (KNX RF: serial number), and
/// recording and replay work without it.
Telegram _withoutRaw(Telegram t) => Telegram(
  time: t.time,
  source: t.source,
  destination: t.destination,
  type: t.type,
  data: t.data,
  isSmall: t.isSmall,
  outgoing: t.outgoing,
  priority: t.priority,
  repeated: t.repeated,
  hopCount: t.hopCount,
  confirmError: t.confirmError,
);

/// Names that never belong in the package (project, installations, gateway host and name, account,
/// customers, business and its members). The [Scrubber] replaces them in free text.
List<String> knownPrivateNames({KnxTunnel? tunnel}) => [
  ...InstallationStore.instance.list.map((i) => i.name).where((n) => n != InstallationStore.defaultName),
  for (final i in InstallationStore.instance.list) ...[?i.gateway?.host, ?i.gateway?.serial, ?i.gateway?.mac],
  ?CatalogStore.instance.catalog.projectName,
  ?CatalogStore.instance.fileName,
  ?KeyringStore.instance.project,
  ?Account.instance.email,
  ?tunnel?.host,
  // The gateway's ETS name ("IP-Router Fam. Schmidt").
  ?tunnel?.deviceName.value,
  ?tunnel?.gatewayInfo.value?.name,
  ...CustomerStore.instance.privateNames,
  ...Team.instance.privateNames,
];

/// Group addresses with a Data Secure key in the loaded keyring.
Set<int> secureGroupAddresses() => {...?KeyringStore.instance.dataSecure?.groupKeys.keys};

/// Technical key data from the app state. Only selected fields: no hosts, serial numbers, MAC,
/// credentials. [error]: error message from which the package is created.
Future<Map<String, Object?>> collectTechnical({KnxTunnel? tunnel, TelegramLog? log, String? error}) async {
  final options = ConnectionOptions.instance;
  final keys = KeyringStore.instance;
  final store = CatalogStore.instance;
  final info = tunnel?.gatewayInfo.value;
  String? version;
  String? build;
  try {
    final p = await PackageInfo.fromPlatform();
    version = p.version;
    build = p.buildNumber;
  } on Object catch (e) {
    debugPrint('Paketinfo nicht lesbar: $e');
  }
  String? os;
  try {
    os = operatingSystemVersion;
  } on Object {
    os = null;
  }
  // Add-on or box: version and connection type of the server.
  Map<String, Object?>? server;
  if (Addon.available) {
    try {
      final status = await Addon.status();
      server = {
        'version': status['version'],
        'state': status['state'],
        'mode': (status['config'] as Map?)?['mode'],
        'haKnx': status['haKnx'],
      };
    } on Object catch (e) {
      server = {'error': '$e'};
    }
  }
  // Display: window in logical points, pixel density, text scale.
  final view = PlatformDispatcher.instance.views.firstOrNull;
  final now = DateTime.now();
  await WriteNotice.instance.load();
  final result = <String, Object?>{
    'writeNotice': WriteNotice.instance.toReport(),
    'app': {
      'version': version,
      'build': build,
      'mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
    },
    'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
    'os': os,
    'homeAssistantAddon': Addon.inHomeAssistant,
    'viaBox': Addon.onBox,
    'server': server,
    'display': view == null
        ? null
        : {
            'width': (view.physicalSize.width / view.devicePixelRatio).round(),
            'height': (view.physicalSize.height / view.devicePixelRatio).round(),
            'pixelRatio': view.devicePixelRatio,
            'textScale': PlatformDispatcher.instance.textScaleFactor,
          },
    'timeZone': {'name': now.timeZoneName, 'offsetMinutes': now.timeZoneOffset.inMinutes},
    'language': LocaleController.instance.locale.languageCode,
    'plan': Plan.instance.value.name,
    'expertMode': expert,
    'connection': {
      'kind': tunnel?.kind ?? _modeLabel(options.mode),
      'mode': options.mode.name,
      'state': tunnel?.state.value.name,
      'error': error ?? tunnel?.error.value,
      'tunnelAddress': tunnel?.tunnelAddress == null ? null : formatIndividual(tunnel!.tunnelAddress!),
      'requestedTunnelAddress': options.tunnelAddress == null ? null : formatIndividual(options.tunnelAddress!),
      if (options.mode == ConnectionMode.routing) 'routingSender': formatIndividual(options.routingAddress),
    },
    'gateway': info == null && tunnel?.deviceName.value == null
        ? null
        : {
            'name': info?.name ?? tunnel?.deviceName.value,
            'medium': info?.mediumText,
            'individualAddress': info?.addressText,
            'services': info == null
                ? null
                : {for (final e in info.services.entries) GatewayInfo.serviceName(e.key): e.value},
            'tunnelSlots': info?.slots.length,
          },
    'settings': {
      'activityRange': ActivityRangeSetting.instance.value.name,
      'alarmNotifications': AlarmNotifySetting.instance.value,
      'installations': InstallationStore.instance.list.length,
      'addressStyle': store.catalog.style.name,
    },
    'project': {
      'groupAddresses': store.catalog.length,
      'devices': store.catalog.devices.length,
      'dptOverrides': store.overrides.length,
    },
    'secure': {
      'keyringLoaded': keys.loaded,
      'groupKeyCount': keys.groupKeyCount,
      'secureTunnelCount': keys.tunnels.length,
      'telegramsWithoutKey': keys.withoutKey.value,
      'telegramsRejected': keys.rejected.value,
    },
    if (log != null)
      'traffic': {
        'telegrams': log.total,
        'perType': {for (final e in log.typeCounts.entries) e.key.name: e.value},
        'repeated': log.repeatedCount,
        'unansweredReads': log.unansweredCount,
        'sent': log.sentCount,
        'groupAddressesSeen': log.latest.length,
      },
  };
  if (tunnel is SharedTunnel || Addon.available) {
    try {
      final status = await Addon.status();
      final config = (status['config'] as Map?) ?? const {};
      // Only state and type; host, credentials etc. stay out.
      result['addon'] = {
        'state': status['state'],
        'error': status['error'],
        'version': status['version'],
        'mode': config['mode'],
        'alarms': config['alarms'],
      };
      final now = DateTime.now();
      result['availability'] = Scrubber().tree(
        await Addon.outages(now.subtract(const Duration(days: 7)), now),
        dropSecrets: true,
      );
      // Unexpected restarts including error text; scrubbed, only in the package. An older server
      // does not know this; the rest of the package is unaffected.
      try {
        result['restarts'] = Scrubber().tree(await Addon.restarts(), dropSecrets: true);
      } on Object catch (e) {
        debugPrint('Neustarts nicht abrufbar: $e');
      }
    } on Object catch (e) {
      result['addon'] = {'error': '$e'};
    }
  }
  return result;
}

String _modeLabel(ConnectionMode mode) => switch (mode) {
  ConnectionMode.udp => 'UDP',
  ConnectionMode.tcp => 'TCP',
  ConnectionMode.routing => 'Routing',
  ConnectionMode.secure => 'IP Secure',
  ConnectionMode.hat => 'KNX-HAT',
  ConnectionMode.homeAssistant => 'Home Assistant',
};

/// Latest app log messages.
List<String> appLogLines() => AppLog.instance.lines;
