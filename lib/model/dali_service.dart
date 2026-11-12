import 'package:flutter/foundation.dart';

import '../knx/dali_text.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import 'dali.dart';
import 'dali_log.dart';
import 'service_report.dart';

/// What is open on the DALI side, for the service report.
enum DaliIssueKind { fault, testFailed, testOverdue }

/// An open DALI item as plain data: collected from the stores in the app, worded in the report's
/// language (the report isolate has no stores).
@immutable
class DaliIssue {
  const DaliIssue({
    required this.kind,
    required this.gateway,
    this.name,
    this.address,
    this.emergency = false,
    this.faults = 0,
    this.since,
    this.test,
  });

  final DaliIssueKind kind;

  /// Individual address of the gateway.
  final int gateway;

  /// Name entered in the app; without one the luminaire is named by its address.
  final String? name;
  final int? address;
  final bool emergency;
  final int faults;
  final DateTime? since;

  /// The failed or overdue test.
  final EmergencyTest? test;
}

/// Luminaires with a reported fault and emergency luminaires whose last test failed or is
/// overdue, as the stores know them at [now].
List<DaliIssue> collectDaliIssues(DateTime now) {
  final store = DaliStore.instance;
  if (store.isEmpty) return const [];
  DaliIssue of(DaliIssueKind kind, DaliGear? gear, int gateway, {EmergencyTest? test}) => DaliIssue(
    kind: kind,
    gateway: gateway,
    name: gear?.name,
    address: gear?.address ?? test?.address,
    emergency: gear?.emergency ?? true,
    faults: gear?.faults ?? 0,
    since: gear?.since,
    test: test,
  );
  return [
    for (final gear in store.faultyGear) of(DaliIssueKind.fault, gear, gear.gateway),
    for (final row in DaliTestLog.instance.overview(now)) ...[
      if (row.failed)
        of(
          DaliIssueKind.testFailed,
          row.gear,
          row.gateway ?? 0,
          test: row.lastDuration?.result == EmergencyResult.failed ? row.lastDuration : row.lastFunction,
        ),
      if (row.overdue)
        of(
          DaliIssueKind.testOverdue,
          row.gear,
          row.gateway ?? 0,
          test: row.durationDue == TestDue.overdue ? row.lastDuration : row.lastFunction,
        ),
    ],
  ];
}

/// The items of the service report for [issues], in the current language: a fault or a failed test
/// should be fixed, an overdue test is to keep an eye on.
List<ServiceLine> daliServiceLines(List<DaliIssue> issues) {
  String two(int v) => v.toString().padLeft(2, '0');
  String date(DateTime? t) => t == null ? '—' : '${two(t.day)}.${two(t.month)}.${t.year}';
  String name(DaliIssue i) =>
      i.name ??
      switch (i.address) {
        final a? => i.emergency ? s.daliEmergencyN(a) : s.daliGearN(a),
        null => s.daliEmergencyLuminaire,
      };
  String gateway(DaliIssue i) => formatIndividual(i.gateway);
  return [
    for (final i in issues)
      switch (i.kind) {
        DaliIssueKind.fault => ServiceLine(
          ServiceLevel.fix,
          s.daliServiceFault(daliFaultsText(i.faults), name(i)),
          s.daliServiceFaultDetail(i.address == null ? '—' : s.daliGearN(i.address!), gateway(i), date(i.since)),
        ),
        DaliIssueKind.testFailed => ServiceLine(
          ServiceLevel.fix,
          s.daliServiceTestFailed(name(i)),
          i.test == null ? '' : s.daliServiceTestDetail(daliTestKindText(i.test!.kind), date(i.test!.time)),
        ),
        DaliIssueKind.testOverdue => ServiceLine(
          ServiceLevel.watch,
          s.daliServiceOverdue(name(i)),
          i.test == null ? '' : s.daliServiceTestDetail(daliTestKindText(i.test!.kind), date(i.test!.time)),
        ),
      },
  ];
}
