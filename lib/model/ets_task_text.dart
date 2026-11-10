import '../knx/group_catalog.dart';
import '../l10n/locale_controller.dart';
import 'betrieb_mode.dart';
import 'ets_tasks.dart';

String _dptText(Dpt? d) => d == null ? '—' : '$d';
String _lineText(int line) => '${(line >> 4) & 0x0F}.${line & 0x0F}';

/// Title of a task, as in the PDF "Tasks for ETS".
String etsTaskTitle(EtsTask t) => switch (t.kind) {
  EtsTaskKind.dpt => s.etsTitleDpt,
  EtsTaskKind.learnedName => s.etsTitleLearnedName,
  EtsTaskKind.learnedNew => s.etsTitleLearnedNew,
  EtsTaskKind.rename => s.etsTitleRename,
  EtsTaskKind.noName => s.etsTitleNoName,
  EtsTaskKind.noDpt => s.etsTitleNoDpt,
  EtsTaskKind.withoutSender => s.checkWithoutSender,
  EtsTaskKind.withoutReceiver => s.checkWithoutReceiver,
  EtsTaskKind.mainGroup1415 => s.checkMainGroup1415,
  EtsTaskKind.filterNotForwarded => s.etsTitleFilterNotForwarded,
  EtsTaskKind.filterCrossLine => s.etsTitleFilterCrossLine,
  EtsTaskKind.statusWithoutTransmit => s.checkStatusNoTransmit,
  EtsTaskKind.readWithoutReadFlag => s.checkReadNoReadFlag,
  EtsTaskKind.multipleReadAnswers => s.checkMultipleReadAnswers,
  EtsTaskKind.objectWithoutCommunication => s.etsTitleNoComm,
  EtsTaskKind.multipleSenders => s.checkMultipleSenders,
  EtsTaskKind.deviceWithoutLinks => s.etsTitleNoLinks,
  EtsTaskKind.notInProject => s.etsTitleNotInProject,
  EtsTaskKind.serialMismatch => s.etsTitleSerial,
  EtsTaskKind.missingOnBus => s.etsTitleMissing,
  EtsTaskKind.crowdedLine => s.checkCrowdedLines,
  EtsTaskKind.standardDeviation => Betrieb.enabled ? s.etsTitleStandard : '',
};

/// What to do for a task, as in the PDF "Tasks for ETS".
String etsTaskTodo(EtsTask t) => switch (t.kind) {
  EtsTaskKind.dpt => s.etsTodoDpt(_dptText(t.dpt)),
  EtsTaskKind.learnedName => s.etsTodoLearnedName(t.name ?? ''),
  EtsTaskKind.learnedNew => s.etsTodoLearnedNew(t.name ?? ''),
  EtsTaskKind.rename => s.etsTodoRename(t.name ?? ''),
  EtsTaskKind.noName => s.etsTodoNoName,
  EtsTaskKind.noDpt => s.etsTodoNoDpt,
  EtsTaskKind.withoutSender => s.etsTodoWithoutSender,
  EtsTaskKind.withoutReceiver => s.etsTodoWithoutReceiver,
  EtsTaskKind.mainGroup1415 => s.etsTodoMainGroup1415,
  EtsTaskKind.filterNotForwarded => s.etsTodoFilterNotForwarded(_lineText(t.line ?? 0)),
  EtsTaskKind.filterCrossLine => s.etsTodoFilterCrossLine(_lineText(t.line ?? 0), t.count ?? 0),
  EtsTaskKind.statusWithoutTransmit => s.etsTodoStatusNoTransmit,
  EtsTaskKind.readWithoutReadFlag => s.etsTodoReadNoReadFlag,
  EtsTaskKind.multipleReadAnswers => s.etsTodoMultipleReadAnswers,
  EtsTaskKind.objectWithoutCommunication => s.etsTodoNoComm,
  EtsTaskKind.multipleSenders => s.etsTodoMultipleSenders,
  EtsTaskKind.deviceWithoutLinks => s.etsTodoNoLinks,
  EtsTaskKind.notInProject => s.etsTodoNotInProject,
  EtsTaskKind.serialMismatch => s.etsTodoSerial(t.serial ?? '—'),
  EtsTaskKind.missingOnBus => s.etsTodoMissing,
  EtsTaskKind.crowdedLine => s.etsTodoCrowdedLine(_lineText(t.line ?? 0), t.count ?? 0),
  EtsTaskKind.standardDeviation => t.name ?? '',
};
