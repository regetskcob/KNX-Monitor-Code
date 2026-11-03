import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/annotation.dart';
import '../theme/app_icons.dart';
import 'annotations.dart';
import 'recording_timeline.dart';
import 'telegram_row.dart';

/// All comments of the installation by day, newest first, including those
/// without a recording, for reading, editing and deleting.
class AnnotationsScreen extends StatelessWidget {
  const AnnotationsScreen({super.key, this.device, this.groups = const {}});

  /// Only the comments on this device (with its addresses [groups]).
  final int? device;
  final Set<int> groups;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: device == null
            ? Text(s.annotationsTitle)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Kennung(formatIndividual(device!)), Text(s.annotationsTitle)],
              ),
      ),
      body: ListenableBuilder(
        listenable: AnnotationStore.instance,
        builder: (context, _) {
          final all = device == null
              ? AnnotationStore.instance.all.reversed.toList()
              : AnnotationScope.forDevice(device!, groups);
          if (all.isEmpty) {
            return HorizontEmptyHint(icon: AppIcons.annotation, text: s.annotationsEmpty);
          }
          final children = <Widget>[];
          String? day;
          for (final a in all) {
            final d = formatDate(a.time);
            if (d != day) {
              day = d;
              children.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(HzSpace.s16, HzSpace.s16, HzSpace.s16, HzSpace.s4),
                  child: Kennung(d),
                ),
              );
            }
            children.add(AnnotationTile(annotation: a, onTap: () => editAnnotation(context, a)));
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: HzSpace.s32),
            children: children,
          );
        },
      ),
    );
  }
}
