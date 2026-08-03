import 'package:flutter/material.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/data/models/thsr_models.dart';
import 'package:wheres_the_bus/data/models/tra_models.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';

/// One amenity a train carries, as published by the operator.
///
/// The order of the enum is the order the marks render in: a fixed sequence
/// means the same slot always holds the same amenity, so the eye can skip
/// straight to the one it cares about instead of re-reading each row.
///
/// TRA drives these from `tra_timetable.mask`. THSR publishes no per-train
/// amenity flags — every high-speed train carries the same business and
/// non-reserved cars — so [overnight] is the only mark its timetable can set.
enum RailServiceMark {
  wheelchair('assets/rails/notes/serve-wheelchair.png'),
  bike('assets/rails/notes/serve-bicy.png'),
  dining('assets/rails/notes/serve-lunchbox.png'),
  breastfeeding('assets/rails/notes/serve-nursingroom.png'),
  daily('assets/rails/notes/serve-everyday.png'),
  overnight('assets/rails/notes/serve-crossday.png');

  const RailServiceMark(this.asset);

  final String asset;

  String labelOf(AppI18n i18n) => switch (this) {
    RailServiceMark.wheelchair => i18n.railServiceWheelchair,
    RailServiceMark.bike => i18n.railServiceBike,
    RailServiceMark.dining => i18n.railServiceDining,
    RailServiceMark.breastfeeding => i18n.railServiceNursing,
    RailServiceMark.daily => i18n.railServiceDaily,
    RailServiceMark.overnight => i18n.railServiceOvernight,
  };

  /// Marks worth showing beside a row in the timetable list. [daily] is the
  /// exception: it describes which days the train runs at all, which the user
  /// has already fixed by picking a date, so it stays in the detail screen.
  /// [overnight] earns its place because it changes what the arrival time in
  /// the same row means — "抵達 00:35" is tomorrow, not twenty minutes ago.
  static const Set<RailServiceMark> _listVisible = {
    wheelchair,
    bike,
    dining,
    breastfeeding,
    overnight,
  };

  bool get showsInList => _listVisible.contains(this);

  static List<RailServiceMark> forTra(TraTimetableItem item) => [
    if (item.isDisabledFriendly) wheelchair,
    if (item.hasBike) bike,
    if (item.hasDiningCar) dining,
    if (item.hasBreastfeeding) breastfeeding,
    if (item.runsDaily) daily,
  ];

  static List<RailServiceMark> forThsr(ThsrTimetableItem item) => [
    if (item.isOvernight) overnight,
  ];
}

/// The marks as they appear in a timetable row: the operator's artwork, sized
/// down.
///
/// Rendered as drawn. Recolouring is not available: each mark is a white glyph
/// knocked out of a filled colour plate, so any single-tone filter paints
/// plate and glyph alike and leaves a solid square. Restraint comes from size
/// and count instead — 14px, at most three, in a fixed-width slot so a row
/// with three marks and a row with none put the columns in the same place.
class RailServiceMarkRow extends StatelessWidget {
  const RailServiceMarkRow({
    required this.marks,
    super.key,
    this.maxVisible = 3,
  });

  final List<RailServiceMark> marks;

  /// Marks past this count collapse into a `+N` counter rather than squeezing
  /// the train number column.
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visible = marks.where((m) => m.showsInList).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    final shown = visible.take(maxVisible).toList();
    final overflow = visible.length - shown.length;

    return Semantics(
      label: visible.map((m) => m.labelOf(AppI18n.of(context))).join('、'),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mark in shown) ...[
            Image.asset(mark.asset, width: 14, height: 14),
            const SizedBox(width: 3),
          ],
          if (overflow > 0)
            Text(
              '+$overflow',
              style: AppTextStyles.memo.copyWith(
                fontSize: 10,
                color: cs.outline,
              ),
            ),
        ],
      ),
    );
  }
}

/// The marks as they appear on the train detail screen: original artwork with
/// its label, wrapped so long lists reflow instead of clipping.
class RailServiceMarkChips extends StatelessWidget {
  const RailServiceMarkChips({required this.marks, super.key});

  final List<RailServiceMark> marks;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      children: [
        for (final mark in marks)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                mark.asset,
                width: 20,
                height: 20,
              ),
            ],
          ),
      ],
    );
  }
}
