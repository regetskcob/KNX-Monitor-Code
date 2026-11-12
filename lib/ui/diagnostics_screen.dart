import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/diagnostics.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/filter.dart';
import '../model/telegram_log.dart';
import '../model/xknx_editor_settings.dart';
import '../platform/xknx_editor_client.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/palette.dart';
import 'common.dart';
import 'device_sheet.dart' show DeviceLink;
import 'inventory_view.dart';
import 'statistics_screen.dart' show FigureBox;
import 'xknx_editor_sheet.dart' show xknxEditorErrorText;

/// Diagnostic tools: read the status of all addresses, find devices in
/// programming mode, check an individual address. Read-only.
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key, required this.tunnel, this.log, this.onFilter, this.onHealth, this.onSecurity});

  final KnxTunnel tunnel;

  /// Monitor traffic: found devices then open their device sheet.
  final TelegramLog? log;

  /// Sets the search in the monitor and returns there (line scan: the scanned line).
  final ValueChanged<String>? onFilter;

  /// Opens the security check (its own page, also reachable without
  /// diagnostics).
  final VoidCallback? onSecurity;

  /// Opens the "Gesundheit" (health) tool, which now hosts "Status lesen".
  final VoidCallback? onHealth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(s.diagnosticsTitle),
        // Reading status lives in "Gesundheit": a link there instead of a hint
        // card.
        actions: [
          if (onSecurity != null)
            IconButton(tooltip: s.secTitle, onPressed: onSecurity, icon: const Icon(AppIcons.secure)),
          if (onHealth != null)
            IconButton(tooltip: s.healthTitle, onPressed: onHealth, icon: const Icon(AppIcons.health)),
        ],
      ),
      // One card per tool: title and main action on top, results below.
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.dashboard),
          child: ListView(
            padding: Gap.page,
            children: [
              for (final (i, tool) in <Widget>[
                _ProgrammingModeCard(tunnel: tunnel, log: log, onFilter: onFilter),
                _AddressCheckCard(tunnel: tunnel, log: log, onFilter: onFilter),
                _LineScanCard(tunnel: tunnel, log: log, onFilter: onFilter),
                InventoryCard(tunnel: tunnel),
              ].indexed) ...[if (i > 0) const SizedBox(height: Gap.inner), SectionCard(child: tool)],
            ],
          ),
        ),
      ),
    );
  }
}

String _deviceName(int address) {
  final d = CatalogStore.instance.device(address);
  return d == null ? s.diagNotInProject : [d.name, ?d.location].join(' · ');
}

class _Explanation extends StatelessWidget {
  const _Explanation(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: context.hz.textMuted));
  }
}

/// Error message with a symbol (octagon), never color alone.
class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return HorizontNotice(HorizontStatus.critical, child: Text(text));
  }
}

/// Ergebniszeilen, dazwischen Haarlinien.
class _Results extends StatelessWidget {
  const _Results(this.rows);

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, row) in rows.indexed) ...[if (i > 0) const Divider(height: Lines.hairline), row],
    ],
  );
}

/// Small progress spinner inside buttons.
const _spinner = SizedBox.square(
  dimension: 16,
  child: CircularProgressIndicator.adaptive(strokeWidth: Lines.selection),
);

class _ProgrammingModeCard extends StatefulWidget {
  const _ProgrammingModeCard({required this.tunnel, this.log, this.onFilter});

  final KnxTunnel tunnel;
  final TelegramLog? log;
  final ValueChanged<String>? onFilter;

  @override
  State<_ProgrammingModeCard> createState() => _ProgrammingModeCardState();
}

class _ProgrammingModeCardState extends State<_ProgrammingModeCard> {
  bool _busy = false;
  List<int>? _found;
  String? _error;

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final found = await Diagnostics(widget.tunnel).findProgrammingMode();
      if (mounted) setState(() => _found = found);
    } on KnxException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    return DiagnosticTool(
      title: s.diagProgTitle,
      text: s.diagProgText,
      action: TextButton.icon(
        onPressed: _busy ? null : _search,
        icon: _busy ? _spinner : null,
        label: Text(_busy ? s.diagSearching : s.diagSearch),
      ),
      children: [
        if (_error != null) ...[const SizedBox(height: Gap.inner), _ErrorLine(_error!)],
        if (found != null) ...[
          const SizedBox(height: HzSpace.s16),
          if (found.isEmpty)
            _Explanation(s.diagProgNone)
          else
            _Results([
              for (final pa in found)
                _ResultRow(
                  status: found.length > 1 ? HorizontStatus.warning : HorizontStatus.positive,
                  title: formatIndividual(pa),
                  subtitle: _deviceName(pa),
                  device: pa,
                  log: widget.log,
                  onFilter: widget.onFilter,
                ),
            ]),
        ],
      ],
    );
  }
}

// --- Check address ---------------------------------------------------------

class _AddressCheckCard extends StatefulWidget {
  const _AddressCheckCard({required this.tunnel, this.log, this.onFilter});

  final KnxTunnel tunnel;
  final TelegramLog? log;
  final ValueChanged<String>? onFilter;

  @override
  State<_AddressCheckCard> createState() => _AddressCheckCardState();
}

class _AddressCheckCardState extends State<_AddressCheckCard> {
  final _input = TextEditingController();
  bool _busy = false;
  AddressCheck? _result;
  String? _error;
  DeviceDetails? _details;
  bool _detailsBusy = false;
  String? _detailsError;
  XknxDevicePreview? _preview;
  bool _previewBusy = false;
  String? _previewError;

  /// Download preview through the XKNX Editor: does the device carry the project?
  Future<void> _comparePreview(int address) async {
    setState(() {
      _previewBusy = true;
      _previewError = null;
      _preview = null;
    });
    final client = await XknxEditorSettings.client();
    try {
      final preview = await client.previewDownload(formatIndividual(address));
      if (mounted) setState(() => _preview = preview);
    } on XknxEditorException catch (e) {
      if (mounted) {
        setState(() => _previewError = xknxEditorErrorText(e));
      }
    } finally {
      client.close();
      if (mounted) setState(() => _previewBusy = false);
    }
  }

  Future<void> _readDetails(int address) async {
    setState(() {
      _detailsBusy = true;
      _detailsError = null;
      _details = null;
    });
    try {
      final details = await Diagnostics(widget.tunnel).readDeviceInfo(address);
      if (mounted) setState(() => details == null ? _detailsError = s.diagDeviceInfoFailed : _details = details);
    } on KnxException catch (e) {
      if (mounted) setState(() => _detailsError = e.message);
    } finally {
      if (mounted) setState(() => _detailsBusy = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final address = parseIndividual(_input.text);
    if (address == null) {
      setState(() => _error = s.diagAddressInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _details = null;
      _detailsError = null;
      _preview = null;
      _previewError = null;
    });
    try {
      final result = await Diagnostics(widget.tunnel).checkAddress(address);
      if (mounted) setState(() => _result = result);
    } on KnxException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return DiagnosticTool(
      title: s.diagAddressTitle,
      text: s.diagAddressText,
      controls: Row(
        children: [
          Expanded(
            child: HorizontField(
              label: s.columnAddress,
              child: TextField(
                style: context.hzTheme.field,
                controller: _input,
                // Digits with punctuation: the decimal pad shows a comma in
                // German.
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                inputFormatters: const [dotForComma],
                autocorrect: false,
                decoration: InputDecoration(hintText: '1.1.18', isDense: true),
                onSubmitted: (_) => _check(),
              ),
            ),
          ),
          const SizedBox(width: Gap.inner),
          FilledButton(onPressed: _busy ? null : _check, child: _busy ? _spinner : Text(s.diagCheck)),
        ],
      ),
      children: [
        if (_error != null) ...[const SizedBox(height: Gap.inner), _ErrorLine(_error!)],
        if (r != null) ...[
          const SizedBox(height: HzSpace.s16),
          _Results([
            _ResultRow(
              status: switch (r.state) {
                AddressState.present => HorizontStatus.positive,
                AddressState.free => HorizontStatus.neutral,
                AddressState.unknown => HorizontStatus.warning,
              },
              title:
                  '${formatIndividual(r.address)}  ${switch (r.state) {
                    AddressState.present => s.diagAddressPresent,
                    AddressState.free => s.diagAddressFree,
                    AddressState.unknown => s.diagAddressUnknown,
                  }}',
              subtitle: [
                if (r.state == AddressState.present) _deviceName(r.address),
                if (r.maskText != null) s.diagMaskVersion(r.maskText!),
              ].join(' · '),
              device: r.state == AddressState.present ? r.address : null,
              log: widget.log,
              onFilter: widget.onFilter,
            ),
          ]),
          if (r.state == AddressState.present) ...[
            const SizedBox(height: Gap.item),
            Wrap(
              spacing: Gap.item,
              runSpacing: Gap.item,
              children: [
                OutlinedButton.icon(
                  onPressed: _detailsBusy ? null : () => _readDetails(r.address),
                  icon: _detailsBusy ? _spinner : const Icon(AppIcons.info, size: 18),
                  label: Text(s.diagDeviceInfo),
                ),
                // The editor runs on the user's computer; the browser cannot reach it.
                if (!kIsWeb && CatalogStore.instance.device(r.address) != null)
                  Tooltip(
                    message: s.xknxEditorPreviewHint,
                    child: OutlinedButton.icon(
                      onPressed: _previewBusy ? null : () => _comparePreview(r.address),
                      icon: _previewBusy ? _spinner : const Icon(AppIcons.etsTasks, size: 18),
                      label: Text(s.xknxEditorPreview),
                    ),
                  ),
              ],
            ),
          ],
          if (_previewError != null) ...[const SizedBox(height: Gap.item), _ErrorLine(_previewError!)],
          if (_preview case final p?) ...[
            const SizedBox(height: Gap.item),
            HorizontNotice(
              p.config == 0 ? HorizontStatus.positive : HorizontStatus.warning,
              child: Text(p.config == 0 ? s.xknxEditorPreviewSame : s.xknxEditorPreviewDiff(p.config)),
            ),
          ],
          if (_detailsError != null) ...[const SizedBox(height: Gap.item), _ErrorLine(_detailsError!)],
          if (_details != null) ...[const SizedBox(height: Gap.inner), _DeviceDetailsTable(details: _details!)],
        ],
      ],
    );
  }
}

/// Properties of a device, with the serial number matched against the project.
class _DeviceDetailsTable extends StatelessWidget {
  const _DeviceDetailsTable({required this.details});

  final DeviceDetails details;

  static String _hex(int v, int digits) => v.toRadixString(16).toUpperCase().padLeft(digits, '0');

  static String _manufacturer(int id) => CatalogStore.instance.catalog.manufacturers[id] ?? 'M-${_hex(id, 4)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final d = details;
    final projectSerial = CatalogStore.instance.device(d.address)?.serial;
    final serialWarning = d.serial != null && projectSerial != null && projectSerial != d.serial;
    final program = d.program;
    final rows = <(String, String, bool)>[
      if (d.maskVersion != null) (s.devMask, _hex(d.maskVersion!, 4), false),
      (s.devManufacturer, d.manufacturerId == null ? s.devUnsupported : _manufacturer(d.manufacturerId!), false),
      (
        s.devSerial,
        d.serial == null
            ? s.devUnsupported
            : [
                d.serial!,
                if (projectSerial != null)
                  projectSerial == d.serial ? s.devSerialMatch : s.devSerialMismatch(projectSerial),
              ].join(' · '),
        serialWarning,
      ),
      if (d.orderInfo != null) (s.devOrder, d.orderInfo!, false),
      if (d.hardwareType != null) (s.devHardware, d.hardwareType!, false),
      if (d.firmware != null) (s.devFirmware, '${d.firmware! >> 4}.${d.firmware! & 0x0F}', false),
      if (d.programmingMode != null) (s.devProgMode, d.programmingMode! ? s.devOn : s.devOff, d.programmingMode!),
      if (program != null)
        (
          s.devApplication,
          '${_manufacturer(program.manufacturer)} · ${_hex(program.deviceType, 4)} · v${program.version}',
          false,
        ),
    ];
    // Table with hairlines, values in bold; deviations marked with a symbol.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (label, value, warning)) in rows.indexed) ...[
          if (i > 0) const Divider(height: Lines.hairline),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 150,
                  child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                ),
                if (warning) ...[
                  Icon(HorizontStatus.warning.icon, size: 16, color: hz.warning),
                  const SizedBox(width: HzSpace.s4),
                ],
                Expanded(
                  child: SelectableText(
                    value,
                    style: context
                        .figures(theme.textTheme.bodyMedium)
                        .copyWith(fontWeight: FontWeight.w600, color: warning ? hz.warning : null),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// --- Linienscan ----------------------------------------------------------------

class _LineScanCard extends StatefulWidget {
  const _LineScanCard({required this.tunnel, this.log, this.onFilter});

  final KnxTunnel tunnel;
  final TelegramLog? log;
  final ValueChanged<String>? onFilter;

  @override
  State<_LineScanCard> createState() => _LineScanCardState();
}

class _LineScanCardState extends State<_LineScanCard> {
  final _line = TextEditingController(text: '1.1');
  RangeValues _range = const RangeValues(0, 255);
  LineScanRun? _run;
  final _idle = ValueNotifier(0);
  String? _error;

  @override
  void dispose() {
    _run?.dispose();
    _idle.dispose();
    _line.dispose();
    super.dispose();
  }

  void _start() {
    final parts = _line.text.trim().split('.').map(int.tryParse).toList();
    if (parts.length != 2 || parts.any((p) => p == null || p < 0 || p > 15)) {
      setState(() => _error = s.scanInvalidLine);
      return;
    }
    _run?.dispose();
    setState(() {
      _error = null;
      _run = LineScanRun(
        widget.tunnel,
        area: parts[0]!,
        line: parts[1]!,
        from: _range.start.round(),
        to: _range.end.round(),
      )..start();
    });
  }

  /// Not in the project, but explainable: our own tunnel and the gateway's
  /// other tunnel addresses (directly after its address, or with the same mask
  /// version on the same line).
  Map<int, String> _tunnelLabels(List<AddressCheck> present) {
    final store = CatalogStore.instance;
    final tunnel = widget.tunnel;
    final gateway = tunnel.gatewayInfo.value;
    final result = <int, String>{};
    final own = tunnel.tunnelAddress;
    if (own != null && store.device(own) == null) result[own] = s.diagOwnTunnel;
    if (gateway == null) return result;
    final name = store.device(gateway.address)?.name ?? gateway.name;
    final gatewayMask = present.where((r) => r.address == gateway.address).firstOrNull?.maskText;
    final unknown = {
      for (final r in present)
        if (store.device(r.address) == null) r.address: r,
    };
    // Tunnels maintained in the project (additional addresses): don't guess.
    final gatewayDevice = store.device(gateway.address);
    if (gatewayDevice != null &&
        store.catalog.devices.values.where((d) => d.product != null && d.product == gatewayDevice.product).length > 1) {
      return result;
    }
    // Contiguous, directly after the gateway.
    for (var pa = gateway.address + 1; unknown.containsKey(pa) && (pa & 0xFF) != 0; pa++) {
      result.putIfAbsent(pa, () => s.diagGatewayTunnel(name));
    }
    for (final r in unknown.values) {
      if (gatewayMask != null && r.maskText == gatewayMask && (r.address >> 8) == (gateway.address >> 8)) {
        result.putIfAbsent(r.address, () => s.diagGatewayTunnel(name));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = CatalogStore.instance;
    return ListenableBuilder(
      listenable: _run ?? _idle,
      builder: (context, _) {
        final run = _run;
        final busy = run?.running == true;
        // Match against the project (only meaningful with .knxproj devices).
        final inRange = run == null
            ? const <int>[]
            : [
                // Tunnels only respond while they are in use; don't count them
                // as "missing".
                for (final MapEntry(key: pa, value: d) in store.catalog.devices.entries)
                  if (!d.isTunnel &&
                      (pa >> 12) == run.area &&
                      ((pa >> 8) & 0x0F) == run.line &&
                      (pa & 0xFF) >= run.from &&
                      (pa & 0xFF) < run.from + run.checked)
                    pa,
              ];
        final presentSet = {for (final r in run?.present ?? const <AddressCheck>[]) r.address};
        final missing = [
          for (final pa in inRange)
            if (!presentSet.contains(pa)) pa,
        ]..sort();
        final tunnels = _tunnelLabels(run?.present ?? const []);
        final unexpected = [
          for (final r in run?.present ?? const <AddressCheck>[])
            if (store.catalog.devices.isNotEmpty && store.device(r.address) == null && !tunnels.containsKey(r.address))
              r,
        ];
        return DiagnosticTool(
          title: s.scanTitle,
          text: s.scanExplain,
          action: busy
              ? TextButton(onPressed: run!.cancel, child: Text(s.commonCancel))
              : TextButton(onPressed: _start, child: Text(s.scanStart)),
          controls: Builder(
            builder: (context) {
              final line = SizedBox(
                width: 110,
                child: HorizontField(
                  label: s.scanLine,
                  child: TextField(
                    style: context.hzTheme.field,
                    controller: _line,
                    enabled: !busy,
                    // Digits with punctuation: the decimal pad shows a comma in
                    // German.
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    inputFormatters: const [dotForComma],
                    decoration: InputDecoration(errorText: _error, isDense: true),
                  ),
                ),
              );
              final range = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.scanRange(_range.start.round(), _range.end.round()), style: theme.textTheme.bodySmall),
                  RangeSlider(
                    values: _range,
                    min: 0,
                    max: 255,
                    divisions: 255,
                    onChanged: busy ? null : (v) => setState(() => _range = v),
                  ),
                ],
              );
              return ScanControls(line: line, range: range);
            },
          ),
          children: [
            if (run != null) ...[
              const SizedBox(height: Gap.inner),
              LinearProgressIndicator(value: run.progress, minHeight: HzSpace.s4, borderRadius: Radii.row),
              const SizedBox(height: Gap.inner),
              FigureBox(
                figures: [
                  (s.scanPresent, formatInt(run.present.length)),
                  (s.scanChecked, '${run.checked} / ${run.total}'),
                  if (store.catalog.devices.isNotEmpty) ...[
                    (s.scanMissing, formatInt(missing.length)),
                    (s.scanUnexpected, formatInt(unexpected.length)),
                  ],
                ],
              ),
              // The scanned line in the live list, as from the topology.
              if (widget.onFilter case final filter?)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => filter(lineQuery((run.area << 4) | run.line)),
                    icon: const Icon(AppIcons.filter),
                    label: Text(s.devLineShow('${run.area}.${run.line}')),
                  ),
                ),
              const SizedBox(height: Gap.inner),
              if (run.present.isNotEmpty)
                _Results([
                  for (final r in run.present)
                    _ResultRow(
                      status: unexpected.contains(r) ? HorizontStatus.warning : HorizontStatus.positive,
                      title: formatIndividual(r.address),
                      subtitle: [
                        tunnels[r.address] ?? _deviceName(r.address),
                        if (r.maskText != null) s.diagMaskVersion(r.maskText!),
                      ].join(' · '),
                      device: r.address,
                      log: widget.log,
                      onFilter: widget.onFilter,
                    ),
                ]),
              if (missing.isNotEmpty) ...[
                const SizedBox(height: Gap.section),
                SectionTitle(s.scanMissing, count: missing.length),
                const SizedBox(height: Gap.item),
                _Results([
                  for (final pa in missing)
                    _ResultRow(
                      status: HorizontStatus.warning,
                      title: formatIndividual(pa),
                      subtitle: _deviceName(pa),
                      device: pa,
                      log: widget.log,
                      onFilter: widget.onFilter,
                    ),
                ]),
              ],
            ],
          ],
        );
      },
    );
  }
}

/// Result row: status symbol, "address  text", the name below.
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.status,
    required this.title,
    required this.subtitle,
    this.device,
    this.log,
    this.onFilter,
  });

  final HorizontStatus status;
  final String title;
  final String subtitle;

  /// Device of the row: with [log] it opens its device sheet, as in the live list.
  final int? device;
  final TelegramLog? log;
  final ValueChanged<String>? onFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: HzSpace.s12),
      child: Row(
        children: [
          Icon(status.icon, size: HzIconSize.row, color: status.color(hz)),
          const SizedBox(width: Gap.inner),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AddressTitle(title),
                if (subtitle.isNotEmpty)
                  Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint)),
              ],
            ),
          ),
        ],
      ),
    );
    return switch ((device, log)) {
      (final device?, final log?) => DeviceLink(address: device, log: log, onFilter: onFilter, child: row),
      _ => row,
    };
  }
}
