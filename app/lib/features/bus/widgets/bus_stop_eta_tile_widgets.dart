part of '../view/bus_stop_detail_view.dart';

class _EtaChevronTile extends StatelessWidget {
  const _EtaChevronTile({
    required this.arrival,
    required this.highlighted,
  });
  final BusStopArrivalItem arrival;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: EtaListTile.fromDisplay(
            arrival.display,
            highlighted: highlighted,
            onTap: () {
              unawaited(HapticService.instance.lightTap());
              final target = arrival.subRouteUid.isNotEmpty
                  ? arrival.subRouteUid
                  : arrival.display.label;
              unawaited(context.push('/bus/route/$target'));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: cs.outline,
          ),
        ),
      ],
    );
  }
}
