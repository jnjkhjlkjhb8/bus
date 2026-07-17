part of '../view/rail_screen.dart';

class _TrainCard extends StatefulWidget {
  const _TrainCard({
    required this.type,
    required this.number,
    required this.delay,
    required this.depart,
    required this.arrive,
    required this.duration,
    required this.origin,
    required this.destination,
    required this.date,
    required this.fare,
    required this.isThsr,
  });

  final String type;
  final String number;
  final int delay;
  final String depart;
  final String arrive;
  final String duration;
  final String origin;
  final String destination;
  final String date;

  /// Adult (全票) fare in NT$ for this O/D from the server, or null when the
  /// fare query had no data — the price is hidden rather than faked.
  final int? fare;
  final bool isThsr;

  @override
  State<_TrainCard> createState() => _TrainCardState();
}

class _TrainCardState extends State<_TrainCard> {
  // trainNo lives in identity.routeKey and the service date in
  // identity.direction (trackOnly rail legs carry no real O/D keys), so both
  // must match to recognise this card's train as the one being tracked.
  bool _isTracking(JourneySessionState s) {
    final leg = s.currentLeg;
    return s.trackOnly &&
        s.phase == JourneyPhase.waiting &&
        leg != null &&
        (leg.kind == JourneyLegKind.tra || leg.kind == JourneyLegKind.thsr) &&
        leg.identity.routeKey == widget.number &&
        leg.identity.direction == widget.date;
  }

  JourneyLeg _buildLeg() {
    final departAt = DateTime.tryParse('${widget.date} ${widget.depart}');
    // Fold the current delay into the countdown so 追蹤 reflects live 誤點.
    final scheduledDeparture = departAt?.add(Duration(minutes: widget.delay));
    return JourneyLeg(
      kind: widget.isThsr ? JourneyLegKind.thsr : JourneyLegKind.tra,
      routeLabel: '${widget.type} ${widget.number} 往${widget.destination}',
      boardStop: widget.origin,
      alightStop: widget.destination,
      stopNames: const [],
      identity: PlanIdentity(
        routeType: widget.isThsr ? 'thsr' : 'tra',
        routeKey: widget.number,
        direction: widget.date,
        departureStopKey: '',
        arrivalStopKey: '',
        supported: false,
      ),
      leadingWalkMinutes: 0,
      scheduledDeparture: scheduledDeparture,
      scheduledArrival: DateTime.tryParse('${widget.date} ${widget.arrive}'),
      boardLocation: const PlanPoint(lat: 0, lng: 0),
      stopLocations: const [],
    );
  }

  Widget _trackButton(BuildContext context, ColorScheme cs) {
    final session = context.read<JourneySessionBloc>();
    return BlocSelector<JourneySessionBloc, JourneySessionState, bool>(
      selector: _isTracking,
      builder: (context, active) {
        return Pressable(
          onTap: () {
            unawaited(HapticService.instance.lightTap());
            if (active) {
              session.add(const JourneyCancelled());
            } else {
              session.add(
                JourneyStarted(trackOnly: true, legs: [_buildLeg()]),
              );
            }
          },
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: active ? cs.onSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              // Keep the border in both states so the button width is stable.
              border: Border.all(color: cs.onSurface),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.radar_rounded,
                  size: 13,
                  color: active ? cs.surface : cs.onSurface,
                ),
                const SizedBox(width: 4),
                Text(
                  active ? '追蹤中' : '追蹤',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: active ? cs.surface : cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Pressable(
      onTap: () {
        unawaited(HapticService.instance.lightTap());
        unawaited(
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RailTrainScreen(
                type: widget.type,
                trainNo: widget.number,
                date: widget.date,
              ),
            ),
          ),
        );
      },
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TrainTypeChip(type: widget.type),
                    const SizedBox(width: 8),
                    Text(
                      widget.number,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.delay > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '+${widget.delay}分',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _trackButton(context, cs),
                    const SizedBox(width: 12),
                    if (widget.fare != null) ...[
                      Text(
                        'NT\$ ${widget.fare}',
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Pressable(
                      onTap: () {
                        unawaited(HapticService.instance.lightTap());
                        unawaited(
                          launchRailBooking(
                            isThsr: widget.isThsr,
                            origin: widget.origin,
                            destination: widget.destination,
                            date: widget.date,
                            trainNumber: widget.number,
                          ),
                        );
                      },
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '訂購',
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 75,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.depart,
                        style: AppTextStyles.memo.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                          fontFeatures: AppTextStyles.tabularFigures,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.duration,
                        style: AppTextStyles.bodyVerySmall.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.arrive,
                        style: AppTextStyles.memo.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                          fontFeatures: AppTextStyles.tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 64,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 6,
                              height: double.infinity,
                              decoration: BoxDecoration(
                                color: cs.outlineVariant,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            Align(
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: cs.outlineVariant,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.topCenter,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: cs.outlineVariant,
                                    width: 3.5,
                                  ),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: cs.outlineVariant,
                                    width: 3.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 64,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                widget.origin,
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                widget.destination,
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(
              color: cs.outlineVariant.withValues(alpha: 0.5),
              height: 1,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '備註：',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
