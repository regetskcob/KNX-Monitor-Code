import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/group_catalog.dart';
import '../knx/knx_tunnel.dart';
import '../knx/shared_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/expert_mode.dart';
import '../model/send_scheduler.dart';
import 'write_confirm.dart';
import 'common.dart';
import 'telegram_row.dart';
import 'write_value.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../model/plan.dart';
import 'plan_screen.dart';

enum _Mode { read, write }

/// Opens the sheet for reading/writing, optionally with a preset group address.
Future<void> showSendSheet(BuildContext context, KnxTunnel tunnel, {int? address}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => SafeArea(
      top: false,
      child: _SendSheet(tunnel: tunnel, address: address),
    ),
  );
}

class _SendSheet extends StatefulWidget {
  const _SendSheet({required this.tunnel, this.address});

  final KnxTunnel tunnel;
  final int? address;

  @override
  State<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<_SendSheet> {
  static String _lastAddress = '';

  late final TextEditingController _ga;
  _Mode _mode = _Mode.write;
  bool _reading = false;
  String? _readStatus;

  int? get _address => parseGroup(_ga.text);
  GroupInfo? get _info => _address == null ? null : CatalogStore.instance.info(_address!);
  Dpt? get _dpt => _address == null ? null : CatalogStore.instance.dptOf(_address!);

  /// Expert mode: delay sending or repeat it cyclically (seconds, 0 = off).
  int _delay = 0;
  int _interval = 0;
  static const _delayChoices = [0, 1, 5, 10, 30, 60];
  static const _intervalChoices = [0, 1, 5, 10, 30, 60, 300];
  List<int> _recent = const [];

  @override
  void initState() {
    super.initState();
    _ga = TextEditingController(text: widget.address != null ? formatGroup(widget.address!) : _lastAddress);
    RecentAddresses.load().then((r) {
      if (mounted) setState(() => _recent = r);
    });
  }

  Future<void> _remember() async {
    final a = _address;
    if (a == null) return;
    final r = await RecentAddresses.remember(a);
    if (mounted) setState(() => _recent = r);
  }

  /// Writes, immediately or as a scheduled job.
  Future<bool?> _write({int? small, List<int> data = const []}) async {
    final address = _requireAddress();
    await requireWriteConfirmation(context, address, small: small, data: data);
    unawaited(_remember());
    if (_delay == 0 && _interval == 0) return widget.tunnel.write(address, small: small, data: data);
    SendScheduler.instance.add(
      SendJob(
        address: address,
        label: '${formatGroup(address)} · ${small ?? hex(data)}',
        small: small,
        data: data,
        delay: Duration(seconds: _delay),
        interval: _interval == 0 ? null : Duration(seconds: _interval),
      ),
    );
    return null;
  }

  @override
  void dispose() {
    _lastAddress = _ga.text;
    _ga.dispose();
    super.dispose();
  }

  int _requireAddress() => _address ?? (throw KnxException(s.sendInvalidAddress));

  Future<void> _read() async {
    setState(() {
      _reading = true;
      _readStatus = null;
    });
    try {
      unawaited(_remember());
      final confirmed = await widget.tunnel.read(_requireAddress());
      _readStatus = s.sendReadSent(confirmationText(confirmed));
    } on KnxException catch (e) {
      _readStatus = e.message;
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final data = context.hzTheme.data;
    final small = theme.textTheme.bodySmall;
    final info = _info;
    final insets = MediaQuery.viewInsetsOf(context);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.gutter + insets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.sendTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: Gap.inner),
          // Read-only server: sending fails, so say so beforehand.
          if (widget.tunnel case SharedTunnel(readOnly: true)) ...[
            DecoratedBox(
              decoration: BoxDecoration(color: hz.infoTint, borderRadius: Radii.tile),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: HzSpace.s16, vertical: HzSpace.s12),
                child: Row(
                  spacing: HzSpace.s8,
                  children: [
                    Icon(HorizontStatus.info.icon, size: HzIconSize.row, color: hz.info),
                    Expanded(child: Text(s.addonReadOnly, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.inner),
          ],
          // Writing interferes with the installation: always visible, in addition
          // to the confirmation before sending.
          if (_mode == _Mode.write) ...[
            DecoratedBox(
              decoration: BoxDecoration(color: hz.warningTint, borderRadius: Radii.tile),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: HzSpace.s16, vertical: HzSpace.s12),
                child: Row(
                  spacing: HzSpace.s8,
                  children: [
                    Icon(HorizontStatus.warning.icon, size: HzIconSize.row, color: hz.warning),
                    Expanded(
                      child: Text(
                        s.writeNoticeTitle,
                        style: theme.textTheme.bodyMedium?.copyWith(color: hz.warning, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.inner),
          ],
          _AddressField(controller: _ga, onChanged: () => setState(() => _readStatus = null)),
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: HzSpace.s8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: HzSpace.s8,
                children: [
                  for (final a in _recent)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: switch (CatalogStore.instance.info(a)?.name) {
                        final name? => Text(name),
                        null => Text(formatGroup(a), style: data),
                      },
                      tooltip: formatGroup(a),
                      onPressed: () => setState(() {
                        _ga.text = formatGroup(a);
                        _readStatus = null;
                      }),
                    ),
                ],
              ),
            ),
          ],
          // Target of the action: name, below it address and data type in monospace.
          if (info != null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.inner),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.name, style: theme.textTheme.bodyLarge),
                  Text(
                    [formatGroup(info.address), if (info.dpt != null) 'DPT ${info.dpt}'].join(metaSeparator),
                    style: context.mono(small).copyWith(color: hz.textFaint),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Gap.inner),
          SegmentedButton<_Mode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: _Mode.write, label: Text(s.typeWrite)),
              ButtonSegment(value: _Mode.read, label: Text(s.typeRead)),
            ],
            selected: {_mode},
            onSelectionChanged: (v) => setState(() => _mode = v.first),
          ),
          const SizedBox(height: Gap.inner),
          switch (_mode) {
            _Mode.write => WriteValueControl(
              // Rebuild when address/DPT changes so the format fits.
              key: ValueKey('${_address}_$_dpt'),
              dpt: _dpt,
              onWrite: _write,
            ),
            _Mode.read => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _reading ? null : _read,
                  icon: const Icon(AppIcons.read),
                  label: Text(s.sendReadValue),
                ),
                if (_readStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Gap.inner),
                    child: Text(_readStatus!, style: TextStyle(color: hz.textMuted)),
                  ),
              ],
            ),
          },
          if (expert && _mode == _Mode.write && !Plan.instance.allows(Feature.scheduledSend)) ...[
            const SizedBox(height: Gap.section),
            // Delay and repeat belong to Pro: visible but locked.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(AppIcons.locked),
                label: Text('${s.sendDelay} · ${s.sendRepeat}'),
                onPressed: () async {
                  if (await unlock(context, Feature.scheduledSend) && mounted) setState(() {});
                },
              ),
            ),
          ] else if (expert && _mode == _Mode.write) ...[
            const SizedBox(height: Gap.section),
            Row(
              spacing: Gap.inner,
              children: [
                Expanded(
                  child: HorizontField(
                    label: s.sendDelay,
                    child: DropdownButtonFormField<int>(
                      initialValue: _delay,
                      isDense: true,
                      decoration: InputDecoration(isDense: true),
                      items: [
                        for (final d in _delayChoices)
                          DropdownMenuItem(value: d, child: Text(d == 0 ? s.sendNow : '$d s')),
                      ],
                      onChanged: (v) => setState(() => _delay = v ?? 0),
                    ),
                  ),
                ),
                Expanded(
                  child: HorizontField(
                    label: s.sendRepeat,
                    child: DropdownButtonFormField<int>(
                      initialValue: _interval,
                      isDense: true,
                      decoration: InputDecoration(isDense: true),
                      items: [
                        for (final d in _intervalChoices)
                          DropdownMenuItem(
                            value: d,
                            child: Text(
                              d == 0 ? s.sendOnce : (d < 60 ? s.sendEverySeconds(d) : s.sendEveryMinutes(d ~/ 60)),
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _interval = v ?? 0),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const _ScheduledJobs(),
        ],
      ),
    );
  }
}

/// Running scheduled sends with stop.
class _ScheduledJobs extends StatelessWidget {
  const _ScheduledJobs();

  @override
  Widget build(BuildContext context) {
    final scheduler = SendScheduler.instance;
    return ListenableBuilder(
      listenable: scheduler,
      builder: (context, _) {
        if (scheduler.jobs.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: Gap.section),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: SectionTitle(s.sendScheduled, count: scheduler.jobs.length)),
                  TextButton(onPressed: scheduler.stopAll, child: Text(s.sendStopAll)),
                ],
              ),
              for (final job in scheduler.jobs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(job.interval == null ? AppIcons.dateTime : AppIcons.restart),
                  title: Text(job.label, style: context.hzTheme.data),
                  subtitle: Text(
                    [
                      if (job.interval != null) s.sendEverySeconds(job.interval!.inSeconds),
                      if (job.sent > 0) s.sendCount(job.sent),
                      if (job.next != null) s.sendNext(formatTime(job.next!, millis: false)),
                      ?job.lastError,
                    ].join(' · '),
                  ),
                  trailing: IconButton(
                    tooltip: s.sendStop,
                    icon: const Icon(AppIcons.stop),
                    onPressed: () => scheduler.stop(job),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Group address field with suggestions from the catalog (name or address).
class _AddressField extends StatefulWidget {
  const _AddressField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  State<_AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends State<_AddressField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onChanged = widget.onChanged;
    final groups = CatalogStore.instance.catalog.groups.values;
    return RawAutocomplete<GroupInfo>(
      textEditingController: widget.controller,
      focusNode: _focus,
      displayStringForOption: (g) => formatGroup(g.address),
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty || groups.isEmpty || parseGroup(q) != null) {
          return const [];
        }
        return groups.where((g) => g.name.toLowerCase().contains(q) || formatGroup(g.address).startsWith(q)).take(30);
      },
      onSelected: (_) => onChanged(),
      // The hint in the field says what belongs in it; the screen reader still
      // gets the label.
      fieldViewBuilder: (context, c, focus, onSubmit) => Semantics(
        label: s.sendGroupAddress,
        child: TextField(
          controller: c,
          focusNode: focus,
          autocorrect: false,
          style: context.hzTheme.data,
          decoration: InputDecoration(hintText: groups.isEmpty ? '1/2/3' : s.sendGroupAddressHint, isDense: true),
          onChanged: (_) => onChanged(),
        ),
      ),
      optionsViewBuilder: (context, onSelect, options) {
        final hz = context.hz;
        final data = context.hzTheme.data;
        // Suggestions: surface with hairline, radius 10, no shadow.
        return Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            color: hz.surface,
            shape: RoundedRectangleBorder(
              borderRadius: Radii.card,
              side: BorderSide(color: hz.line, width: Lines.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: HzSpace.s4),
                shrinkWrap: true,
                children: [
                  for (final g in options)
                    ListTile(
                      dense: true,
                      title: Text(g.name),
                      subtitle: Text(
                        [formatGroup(g.address), if (g.dpt != null) 'DPT ${g.dpt}'].join(metaSeparator),
                        style: data.copyWith(color: hz.textMuted),
                      ),
                      onTap: () => onSelect(g),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
