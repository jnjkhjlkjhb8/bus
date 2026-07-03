part of '../view/bus_stop_screen.dart';

class _EtaChevronTile extends StatelessWidget {
  const _EtaChevronTile({
    required this.arrival,
    required this.highlighted,
    required this.colorScheme,
  });
  final _Arrival arrival;
  final bool highlighted;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: EtaListTile(
            routeNo: arrival.routeNo,
            destination: arrival.destination,
            status: arrival.status,
            highlighted: highlighted,
            onTap: () {
              unawaited(HapticService.instance.lightTap());
              unawaited(context.push('/bus/route/${arrival.routeNo}'));
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.only(right: highlighted ? 20 : 12),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: highlighted
                ? colorScheme.onPrimaryContainer.withValues(alpha: 0.6)
                : colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
