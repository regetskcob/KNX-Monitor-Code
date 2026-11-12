import '../l10n/locale_controller.dart';
import 'dali.dart';
import 'telegram.dart';

/// Words for the decoded DALI datapoint types ([decodeDaliReport] and friends give values, the
/// texts are made here from `lib/l10n/`).
abstract final class DaliText {
  /// Name of the luminaire or group a telegram is about, set by the DALI model: for a diagnostic
  /// telegram the DALI [address] from the payload ([isGroup]: a group), for converter status and
  /// test result the luminaire behind the group address. `null` = no name known.
  static String? Function(Telegram t, {int? address, bool isGroup})? nameOf;
}

/// The diagnostic types the app offers when the type of an address is chosen by hand (listening
/// without an ETS project). They are shown, never sent.
const daliDisplayDpts = [Dpt(237, 600), Dpt(238, 600), Dpt(244, 600), Dpt(245, 600)];

/// Name of a DALI type for lists: "DALI-Diagnose · 237.600".
String daliDptLabel(Dpt dpt) => switch (dpt.main) {
  237 || 238 => '${s.daliDptDiagnostic} · $dpt',
  244 => '${s.daliDptConverterStatus} · $dpt',
  _ => '${s.daliDptTestResult} · $dpt',
};

/// Reported faults in words: "Lampenfehler", "EVG-Fehler, Lampenfehler", "in Ordnung".
String daliFaultsText(int faults) => faults == 0
    ? s.daliOk
    : [
        if (faults & DaliFault.gear != 0) s.daliGearFault,
        if (faults & DaliFault.converter != 0) s.daliConverterFault,
        if (faults & DaliFault.lamp != 0) s.daliLampFault,
      ].join(', ');

String daliModeText(ConverterMode mode) => switch (mode) {
  ConverterMode.unknown => s.daliModeUnknown,
  ConverterMode.normal => s.daliModeNormal,
  ConverterMode.inhibit => s.daliModeInhibit,
  ConverterMode.hardwiredInhibit => s.daliModeHardwiredInhibit,
  ConverterMode.rest => s.daliModeRest,
  ConverterMode.emergency => s.daliModeEmergency,
  ConverterMode.extendedEmergency => s.daliModeExtendedEmergency,
  ConverterMode.functionTest => s.daliModeFunctionTest,
  ConverterMode.durationTest => s.daliModeDurationTest,
  ConverterMode.partialDurationTest => s.daliModePartialTest,
};

String daliTestKindText(EmergencyTestKind kind) => switch (kind) {
  EmergencyTestKind.function => s.daliTestFunction,
  EmergencyTestKind.duration => s.daliTestDuration,
  EmergencyTestKind.partial => s.daliTestPartial,
};

String daliOutcomeText(ConverterTestOutcome outcome) => switch (outcome) {
  ConverterTestOutcome.unknown => s.daliUnknown,
  ConverterTestOutcome.passed => s.daliOutcomePassed,
  ConverterTestOutcome.passedLate => s.daliOutcomePassedLate,
  ConverterTestOutcome.failed => s.daliOutcomeFailed,
  ConverterTestOutcome.failedLate => s.daliOutcomeFailedLate,
  ConverterTestOutcome.stopped => s.daliOutcomeStopped,
};

String daliStartText(ConverterTestStart start) => switch (start) {
  ConverterTestStart.unknown => s.daliUnknown,
  ConverterTestStart.automatic => s.daliStartAutomatic,
  ConverterTestStart.gateway => s.daliStartGateway,
};

String daliResultText(EmergencyResult result) => switch (result) {
  EmergencyResult.passed => s.daliOutcomePassed,
  EmergencyResult.failed => s.daliOutcomeFailed,
  EmergencyResult.unknown => s.daliUnknown,
};

String daliReasonText(EmergencyReason reason) => switch (reason) {
  EmergencyReason.delayExceeded => s.daliReasonLate,
  EmergencyReason.stopped => s.daliOutcomeStopped,
  EmergencyReason.battery => s.daliReasonBattery,
  EmergencyReason.lamp => s.daliReasonLamp,
  EmergencyReason.durationShort => s.daliReasonDuration,
};

/// Battery charge of a partial duration test (0 to 254) in percent.
String daliChargeText(int charge) => '${(charge * 100 / 254).round()} %';

/// Discharge time in minutes; the largest value means "or longer".
String daliMinutesText(int minutes) => minutes >= 510 ? s.daliMinutesMax : s.daliMinutes(minutes);

String _flag(ConverterFlag f) => switch (f) {
  ConverterFlag.unknown => s.daliUnknown,
  ConverterFlag.no => s.commonNo,
  ConverterFlag.yes => s.yes,
};

String _tests(ConverterTestResult r) {
  final parts = [
    for (final kind in EmergencyTestKind.values)
      if (r.outcomeOf(kind) != ConverterTestOutcome.unknown)
        [
          daliTestKindText(kind),
          daliOutcomeText(r.outcomeOf(kind)),
          if (kind == EmergencyTestKind.duration &&
              (r.duration == ConverterTestOutcome.passed || r.duration == ConverterTestOutcome.passedLate))
            '(${daliMinutesText(r.durationMinutes)})',
        ].join(' '),
  ];
  return parts.isEmpty ? s.daliNoTestResult : parts.join(', ');
}

/// Plain text of a telegram with a DALI type: "EVG 12 · Lampenfehler", with a name from the
/// model "Flur EG Leuchte 2 · Lampenfehler". `null` if the payload cannot be decoded (wrong
/// length, reserved value): the monitor then shows hex.
String? daliValueText(Dpt dpt, Telegram t) {
  if (t.isSmall || !isDaliDpt(dpt.main, dpt.sub)) return null;
  String joined(String? who, String what) => who == null ? what : '$who · $what';
  switch (dpt.main) {
    case 237 || 238:
      final r = decodeDaliReport(dpt.main, t.data);
      if (r == null) return null;
      final who =
          DaliText.nameOf?.call(t, address: r.address, isGroup: r.isGroup) ??
          (r.isGroup ? s.daliGroupN(r.address) : s.daliGearN(r.address));
      return joined(who, r.readRequest ? s.daliQuery : daliFaultsText(r.faults));
    case 244:
      final v = decodeConverterStatus(t.data);
      if (v == null) return null;
      return joined(
        DaliText.nameOf?.call(t),
        [daliModeText(v.mode), if (v.failure == ConverterFlag.yes) s.daliConverterFault].join(', '),
      );
    default:
      final v = decodeConverterTestResult(t.data);
      return v == null ? null : joined(DaliText.nameOf?.call(t), _tests(v));
  }
}

/// A row of the "DALI" section in the telegram details. [flag]: a yes/no field (shown as a badge
/// with [value]), `null` for a value; [fault]: the flag reports a failure (set = critical).
typedef DaliDetailRow = ({String label, String value, bool? flag, bool fault});

/// All fields of a telegram with a DALI type, for the details. Empty if it cannot be decoded.
List<DaliDetailRow> daliDetailRows(Dpt dpt, Telegram t) {
  if (t.isSmall || !isDaliDpt(dpt.main, dpt.sub)) return const [];
  DaliDetailRow flag(String label, bool set) =>
      (label: label, value: set ? s.daliFlagSet : s.daliFlagClear, flag: set, fault: true);
  DaliDetailRow row(String label, String value) => (label: label, value: value, flag: null, fault: false);
  // Yes/no fields look like the fault flags, without the alarm colour.
  DaliDetailRow yesNo(String label, bool v) =>
      (label: label, value: v ? s.daliFlagSet : s.daliFlagClear, flag: v, fault: false);
  switch (dpt.main) {
    case 237:
      final v = decodeDaliGearDiagnostic(t.data);
      if (v == null) return const [];
      return [
        flag(s.daliLampFault, v.lampFailure),
        flag(s.daliGearFault, v.ballastFailure),
        flag(s.daliConverterFault, v.converterError),
        row(s.daliRowAddressKind, v.isGroup ? s.daliRowKindGroup : s.daliRowKindDevice),
        row(s.daliRowAddress, '${v.address}'),
        yesNo(s.daliRowQuery, v.readRequest),
      ];
    case 238:
      final v = decodeDaliDiagnostic(t.data);
      if (v == null) return const [];
      return [
        flag(s.daliLampFault, v.lampFailure),
        flag(s.daliGearFault, v.ballastFailure),
        row(s.daliRowAddress, '${v.address}'),
      ];
    case 244:
      final v = decodeConverterStatus(t.data);
      if (v == null) return const [];
      return [
        row(s.daliRowMode, daliModeText(v.mode)),
        row(s.daliRowFailure, _flag(v.failure)),
        row(s.daliRowPending(s.daliTestFunction), _flag(v.functionTestPending)),
        row(s.daliRowPending(s.daliTestDuration), _flag(v.durationTestPending)),
        row(s.daliRowPending(s.daliTestPartial), _flag(v.partialDurationTestPending)),
        yesNo(s.daliRowHardwiredSwitch, v.hardwiredSwitch),
        yesNo(s.daliRowHardwiredInhibit, v.hardwiredInhibit),
      ];
    default:
      final v = decodeConverterTestResult(t.data);
      if (v == null) return const [];
      return [
        for (final kind in EmergencyTestKind.values) ...[
          row(s.daliRowLast(daliTestKindText(kind)), daliOutcomeText(v.outcomeOf(kind))),
          row(s.daliRowStarted(daliTestKindText(kind)), daliStartText(v.startOf(kind))),
        ],
        // The discharge time belongs to the last passed duration test; after a failed one it says
        // nothing about that test.
        row(
          s.daliRowDischarge,
          v.duration == ConverterTestOutcome.passed || v.duration == ConverterTestOutcome.passedLate
              ? daliMinutesText(v.durationMinutes)
              : '—',
        ),
        row(s.daliRowCharge, v.partialCharge == null ? s.daliUnknown : daliChargeText(v.partialCharge!)),
      ];
  }
}

/// Why a telegram on an address with a DALI type shows hex: the length does not fit, or a
/// reserved value is set. `null` if it decodes (or is no DALI type).
String? daliMismatch(Dpt dpt, Telegram t) {
  if (t.type == TelegramType.read || !isDaliDpt(dpt.main, dpt.sub) || daliValueText(dpt, t) != null) return null;
  final expected = daliDptSize(dpt.main)!;
  final actual = t.isSmall ? 0 : t.data.length;
  return actual != expected ? s.daliMismatchLength('$dpt', expected, actual) : s.daliMismatchReserved('$dpt');
}
