import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Body of a form page that follows the available width, like the service report and the
/// acceptance protocol: below [Breakpoints.expanded] one column in reading width, from there on
/// the [columns] side by side, each with its own sections, inside [Widths.wide].
///
/// [intro] is the explaining text above: on a wide window it stays a reading column at the start
/// instead of running across all columns. The single column shows intro and columns in order, so
/// the keyboard and a screen reader walk the left column before the right one in both layouts.
class FormColumns extends StatelessWidget {
  const FormColumns({super.key, this.intro = const [], required this.columns, this.narrow});

  final List<Widget> intro;
  final List<List<Widget>> columns;

  /// The single column below the intro, where its order differs from the [columns] one after
  /// the other (a preview that leads on the phone and stands beside the fields when wide).
  final List<Widget>? narrow;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < Breakpoints.expanded || columns.length < 2) {
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Widths.reading),
            child: ListView(
              padding: Gap.page,
              children: [
                ...intro,
                ...?narrow,
                if (narrow == null)
                  for (final column in columns) ...column,
              ],
            ),
          ),
        );
      }
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.wide),
          child: SingleChildScrollView(
            padding: Gap.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (intro.isNotEmpty)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: Widths.reading),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: intro),
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Gap.section,
                  children: [
                    for (final column in columns)
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: column),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
