part of '../view/rail_screen.dart';

/// Loading stand-in for the timetable.
///
/// It is the table, minus the values: same header, same `_Cols` slots, same
/// row padding, surface and dividers as [_TrainRow]. The old card stack said
/// nothing true about what was coming — a card per train, inset 16px inside a
/// list whose rows are full-bleed — so every row jumped left and shrank the
/// moment the query returned.
///
/// The header stays solid rather than joining the pulse: its labels are static
/// text that is already correct before any train arrives.
class _TimetableSkeleton extends StatelessWidget {
  const _TimetableSkeleton();

  /// Enough rows to fill a phone viewport under the context bar; fewer would
  /// leave the page half empty and then fill in.
  static const _rowCount = 7;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        const _TimetableHeader(),
        SkeletonFade(
          child: Column(
            children: [
              for (var i = 0; i < _rowCount; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 16,
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                const _SkeletonTrainRow(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One loading row, on [_TrainRow]'s geometry: the departure bone in the
/// departure column, the connector hairline the loaded row also draws, and the
/// number/type slot over the reserved service-mark line.
class _SkeletonTrainRow extends StatelessWidget {
  const _SkeletonTrainRow();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: _Cols.scaled(context, _Cols.depart),
            child: SkeletonBone(
              width: scaler.scale(62),
              height: scaler.scale(21),
            ),
          ),
          const SizedBox(width: 8),
          // Drawn, not boned: the connector is a hairline in the loaded row
          // too, and it keeps the row from reading as three floating blocks.
          Expanded(child: Container(height: 1, color: cs.outlineVariant)),
          const SizedBox(width: 8),
          SizedBox(
            width: _Cols.scaled(context, _Cols.arrive),
            child: Align(
              alignment: Alignment.centerRight,
              child: SkeletonBone(
                width: scaler.scale(44),
                height: scaler.scale(15),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: _Cols.scaled(context, _Cols.number),
                    // The number's own line box (memo at 12): together with the
                    // mark line below it, this is what sets a loaded row's
                    // height, so the bone has to occupy it rather than just its
                    // glyph.
                    height: scaler.scale(12 * AppTextStyles.memo.height!),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SkeletonBone(
                        width: scaler.scale(26),
                        height: scaler.scale(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SkeletonBone(
                    // TrainTypeChip's compact minimum width, so the chip lands
                    // on the bone rather than beside it. The bone's default
                    // radius is the chip radius already.
                    width: scaler.scale(46),
                    height: scaler.scale(16),
                  ),
                ],
              ),
              // The mark line is reserved on every loaded row, marks or not.
              SizedBox(height: _Cols.scaled(context, _Cols.markLine)),
            ],
          ),
        ],
      ),
    );
  }
}
