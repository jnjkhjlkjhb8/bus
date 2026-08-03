part of '../view/search_screen.dart';

/// Cities the current results are spread across, as a row of filter chips.
///
/// Renders nothing below two options. One city is not a choice, and a
/// permanent row of every city in Taiwan would charge all 22 chips' worth of
/// vertical space to the majority of queries — which land in one city — to
/// serve the minority that don't.
class _CityFilterRail extends StatelessWidget {
  const _CityFilterRail({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  /// TDX city codes, already ordered by the bloc.
  final List<String> options;

  /// The selected code, or null when results span every option. There is no
  /// "all" chip: nothing selected already says it, and one more chip on a
  /// row this narrow costs more than it explains.
  final String? selected;

  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // The row can appear or disappear between two result sets that both have
    // rows on screen (refining a query narrows it to one city). Sizing that
    // change instead of cutting it keeps the list from jumping under a
    // finger that is on its way to a result.
    return AnimatedSize(
      duration: reduceMotion ? Duration.zero : AppMotion.short,
      curve: AppMotion.easeOut,
      alignment: Alignment.topCenter,
      child: options.length < 2
          ? const SizedBox(width: double.infinity)
          : Semantics(
              container: true,
              label: AppI18n.of(context).searchCityFilter,
              child: Padding(
                // Aligned with the result rows' 20pt gutter. No vertical
                // padding: the chips carry their own to reach a 44pt touch
                // target, and doubling it would make the row taller than the
                // header it sits under.
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: FilterChipGroup<String>(
                  options: {for (final code in options) code: cityName(code)},
                  selected: {?selected},
                  onToggle: onToggle,
                ),
              ),
            ),
    );
  }
}
