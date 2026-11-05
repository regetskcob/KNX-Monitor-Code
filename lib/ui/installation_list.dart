import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/secure/keyring_store.dart';
import '../l10n/locale_controller.dart';
import '../model/customer.dart';
import '../model/betrieb/team_model.dart';
import '../model/handover.dart';
import '../model/installation.dart';
import '../platform/addon.dart';
import 'betrieb/team_approval_dialog.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../model/plan.dart';
import 'catalog_actions.dart';
import 'customers_screen.dart';
import 'handover_screen.dart';
import 'plan_screen.dart';

/// Switches to the installation; switches the KNX box along with it (which then
/// records there).
Future<void> _useInstallation(String id) {
  final store = InstallationStore.instance;
  return Addon.box != null ? store.useOnBox(id) : store.switchTo(id);
}

/// Enter a name (create or rename).
class _NameDialog extends StatefulWidget {
  const _NameDialog({this.initial = ''});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() => Navigator.pop(context, _name.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    title: Text(widget.initial.isEmpty ? s.installationNew : s.installationRename),
    content: Material(
      type: MaterialType.transparency,
      child: TextField(
        style: context.hzTheme.field,
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: s.installationName, hintText: s.installationNameHint),
        onSubmitted: (_) => _done(),
      ),
    ),
    actions: [
      horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context)),
      horizontDialogAction(context, label: s.commonSave, primary: true, onPressed: _done),
    ],
  );
}

/// The active installation as the head of the connection: name, project and
/// keyring at a glance, expanded with the tiles to change them. In expert mode
/// with a menu to switch, create, rename and delete.
class InstallationCard extends StatefulWidget {
  const InstallationCard({
    super.key,
    required this.busy,
    required this.onSwitched,
    required this.switchable,
    required this.showKeyring,
  });

  final bool busy;

  /// Another installation is now active: fill the fields with its gateway.
  final ValueChanged<Installation> onSwitched;

  /// Multiple installations (expert mode): menu to switch.
  final bool switchable;

  /// Keyring tile in the expanded part (expert mode).
  final bool showKeyring;

  @override
  State<InstallationCard> createState() => _InstallationCardState();
}

class _InstallationCardState extends State<InstallationCard> {
  /// `null` = automatic: expanded as long as no project is loaded.
  bool? _open;

  Future<void> _switch(Installation i) async {
    await _useInstallation(i.id);
    widget.onSwitched(i);
  }

  Future<void> _create() async {
    final plan = Plan.instance;
    final store = InstallationStore.instance;
    if (store.list.length >= plan.maxInstallations && plan.installationsCapped) {
      await showAdaptiveDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog.adaptive(
          title: Text(s.planOneInstallationTitle),
          content: Text(s.planOneInstallationHere),
          actions: [
            horizontDialogAction(
              dialog,
              label: s.commonClose,
              primary: true,
              onPressed: () => Navigator.of(dialog).pop(),
            ),
          ],
        ),
      );
      return;
    }
    if (store.list.length >= plan.maxInstallations) {
      await showPlanScreen(
        context,
        reason: s.planMoreInstallations(tierName(plan.value), plan.maxInstallations),
        need: plan.value == Tier.free ? Tier.plus : Tier.pro,
      );
      if (store.list.length >= plan.maxInstallations || !mounted) return;
    }
    if (!mounted) return;
    final name = await showAdaptiveDialog<String>(context: context, builder: (_) => const _NameDialog());
    if (name == null || name.isEmpty) return;
    final i = await store.create(name);
    await _switch(i);
    if (mounted) setState(() => _open = true);
  }

  Future<void> _rename(Installation i) async {
    final name = await showAdaptiveDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: i.name),
    );
    if (name == null || name.isEmpty) return;
    await InstallationStore.instance.rename(i.id, name);
  }

  /// Customer file (Pro); the installation can also be switched from here.
  Future<void> _openCustomers() async {
    // Existing files stay readable after a subscription ends.
    if (CustomerStore.instance.entries.isEmpty && !await unlock(context, Feature.customerRecords) || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CustomersScreen(onOpen: _switch)));
  }

  /// A delete prompt; true only after an explicit tap on [confirm].
  Future<bool> _askDelete(String title, String body, String confirm) async =>
      await showAdaptiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: Text(title),
          content: Text(body),
          actions: [
            horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
            horizontDialogAction(
              context,
              label: confirm,
              destructive: true,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ) ==
      true;

  /// Deletes the active installation after switching to another one first. This
  /// irrevocably affects logs and customer data too, so in a team it requires
  /// the right or an approval, and always two confirmations.
  Future<void> _delete(Installation i) async {
    final store = InstallationStore.instance;
    if (!await ensureTeamRight(context, TeamAction.deleteInstallation) || !mounted) return;
    final body = store.onBox(i.id)
        ? '${s.installationDeleteBody}\n\n${s.installationDeleteOnBox}'
        : s.installationDeleteBody;
    if (!await _askDelete(s.installationDeleteTitle(i.name), body, s.commonDelete) || !mounted) return;
    if (!await _askDelete(
      s.installationDeleteSureTitle(i.name),
      s.installationDeleteSureBody,
      s.installationDeleteSureConfirm,
    )) {
      return;
    }
    await _switch(store.list.firstWhere((o) => o.id != i.id));
    await store.delete(i.id);
  }

  @override
  Widget build(BuildContext context) {
    final store = InstallationStore.instance;
    final catalog = CatalogStore.instance;
    final keyring = KeyringStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        store,
        catalog,
        keyring,
        CustomerStore.instance,
        HandoverStore.instance,
        LocaleController.instance,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final hz = context.hz;
        final active = store.active;
        final c = catalog.catalog;
        final loaded = !c.isEmpty;
        final open = _open ?? !loaded;
        // If the installation still has its default name, it takes the project
        // name.
        final project = loaded ? c.projectName : null;
        final title = active.name == InstallationStore.defaultName && project != null ? project : active.name;
        // Summary: project (unless already the title), key figures, keyring.
        final summary = [
          if (loaded) ...[
            if (project != null && project != title) project,
            if (c.devices.isNotEmpty) s.deviceCount(c.devices.length),
            s.groupAddressCount(c.length),
          ] else
            s.catalogNone,
          if (widget.showKeyring && keyring.loaded) s.keyringTitle,
          if (Addon.box != null && active.id == store.boxActive) s.installationBoxRecording,
          if (CustomerStore.instance.maintenanceDue(active.id)) s.customerDue,
          if (HandoverStore.instance.origin case final origin? when origin.contact.name.isNotEmpty)
            s.handoverSetUpBy(origin.contact.name),
        ].join(metaSeparator);
        void toggle() => setState(() => _open = !open);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: hz.surface,
            border: Border.all(color: hz.line, width: Lines.hairline),
            borderRadius: Radii.tile,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                borderRadius: Radii.tile,
                onTap: toggle,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(Gap.card, Gap.inner, HzSpace.s4, Gap.inner),
                  child: Row(
                    children: [
                      Icon(AppIcons.installation, color: hz.text),
                      const SizedBox(width: Gap.inner),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: theme.textTheme.titleSmall),
                            Text(summary, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                          ],
                        ),
                      ),
                      if (widget.switchable) _menu(context, store, active),
                      Semantics(
                        expanded: open,
                        child: IconButton(
                          tooltip: open
                              ? MaterialLocalizations.of(context).expandedIconTapHint
                              : MaterialLocalizations.of(context).collapsedIconTapHint,
                          onPressed: toggle,
                          icon: Icon(open ? AppIcons.collapse : AppIcons.expand),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: Motion.of(context),
                curve: Motion.curve,
                alignment: Alignment.topCenter,
                child: !open
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(Gap.inner, 0, Gap.inner, Gap.inner),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: Gap.inner,
                          children: [
                            const CatalogTile(),
                            if (widget.showKeyring) const KeyringTile(),
                            if (HandoverStore.instance.origin case final origin?) HandoverOriginTile(origin: origin),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Switch, create, rename, delete.
  Widget _menu(BuildContext context, InstallationStore store, Installation active) => PopupMenuButton<void Function()>(
    tooltip: s.installationsTitle,
    enabled: !widget.busy,
    // Labeled like "Ersetzen" and "Importieren" in the tiles.
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: HzSpace.s8, vertical: HzSpace.s12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: HzSpace.s4,
        children: [
          SizedBox.square(dimension: 18, child: CustomPaint(painter: _FolderPainter(context.hz.accentText))),
          // Large text: only the icon (word in the tooltip), otherwise the
          // installation name would break mid-word ("Installa-tion").
          if (MediaQuery.textScalerOf(context).scale(10) <= 13)
            Text(
              s.installationSwitch,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: context.hz.accentText),
            ),
        ],
      ),
    ),
    onSelected: (action) => action(),
    itemBuilder: (context) => [
      for (final i in store.list)
        PopupMenuItem(
          value: () => _switch(i),
          enabled: i.id != active.id,
          child: Row(
            children: [
              SizedBox(width: HzSpace.s24, child: i.id == active.id ? const Icon(AppIcons.check, size: 18) : null),
              Expanded(child: Text(i.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(value: _openCustomers, child: Text(s.installationCustomers)),
      PopupMenuItem(value: () => pickPackageFile(this.context), child: Text(s.packageOpenMenu)),
      PopupMenuItem(value: _create, child: Text(s.installationNew)),
      PopupMenuItem(value: () => _rename(active), child: Text(s.installationRename)),
      // The only one stays, as does the one the box is currently recording
      // into.
      PopupMenuItem(
        enabled: store.list.length > 1 && active.id != store.boxActive,
        value: () => _delete(active),
        child: Text(s.commonDelete),
      ),
    ],
  );
}

/// Folder icon in the style of the Horizont icons (stroke, angular). Horizont
/// has no folder yet; belongs in the package later.
class _FolderPainter extends CustomPainter {
  _FolderPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.1, h * 0.22)
      ..lineTo(w * 0.4, h * 0.22)
      ..lineTo(w * 0.5, h * 0.32)
      ..lineTo(w * 0.9, h * 0.32)
      ..lineTo(w * 0.9, h * 0.8)
      ..lineTo(w * 0.1, h * 0.8)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  @override
  bool shouldRepaint(_FolderPainter old) => old.color != color;
}
