import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/core/haptics/haptic_service.dart';
import 'package:wheres_the_bus/data/models/favorite.dart';
import 'package:wheres_the_bus/data/models/journey_info.dart';
import 'package:wheres_the_bus/data/models/metro_map_models.dart';
import 'package:wheres_the_bus/data/models/metro_topology.dart';
import 'package:wheres_the_bus/features/metro/bloc/mrt_track_bloc.dart';
import 'package:wheres_the_bus/features/metro/bloc/mrt_track_event.dart';
import 'package:wheres_the_bus/features/metro/bloc/mrt_track_state.dart';
import 'package:wheres_the_bus/features/metro/data/mrt_car_binding.dart';
import 'package:wheres_the_bus/shared/widgets/alight_track/alight_confirm_bar.dart';
import 'package:wheres_the_bus/shared/widgets/alight_track/alight_pick_capsule.dart';
import 'package:wheres_the_bus/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_bus/features/metro/data/metro_line_names.dart';
import 'package:wheres_the_bus/features/metro/bloc/metro_bloc.dart';
import 'package:wheres_the_bus/features/metro/bloc/metro_event.dart';
import 'package:wheres_the_bus/features/metro/bloc/metro_state.dart';
import 'package:wheres_the_bus/features/metro/view/metro_station_detail_view.dart';
import 'package:wheres_the_bus/features/metro/widgets/metro_svg_map.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';
import 'package:wheres_the_bus/shared/widgets/app_bars.dart';
import 'package:wheres_the_bus/shared/widgets/app_sliding_segment.dart';
import 'package:wheres_the_bus/shared/widgets/app_snackbar.dart';
import 'package:wheres_the_bus/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_bus/shared/widgets/error_state_view.dart';
import 'package:wheres_the_bus/shared/widgets/transport_icon.dart';

part '../widgets/metro_placeholder_widgets.dart';
part '../widgets/metro_system_widgets.dart';

final RegExp _digits = RegExp(r'\d+');

String _lineCode(String id) => id.split('_').first.replaceAll(_digits, '');

String _lineName(AppI18n i18n, String id) =>
    metroLineNames(i18n)[_lineCode(id)] ?? _lineCode(id);

TransportType _getTransportType(String line) {
  switch (line) {
    case 'BL':
      return TransportType.mrtBL;
    case 'R':
      return TransportType.mrtR;
    case 'G':
      return TransportType.mrtG;
    case 'BR':
      return TransportType.mrtBR;
    case 'O':
      return TransportType.mrtO;
    default:
      return TransportType.mrtBL;
  }
}

@Preview(name: 'MetroScreen — full', group: 'Metro', size: Size(390, 844))
Widget metroScreenPreview() => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.light,
  home: const MetroScreen(),
);

@Preview(
  name: 'MetroScreen — full (dark)',
  group: 'Metro',
  brightness: Brightness.dark,
  size: Size(390, 844),
)
Widget metroScreenDarkPreview() => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.dark,
  home: const MetroScreen(),
);

@Preview(
  name: 'MetroScreen — station detail',
  group: 'Metro',
  size: Size(390, 720),
)
Widget metroDetailPreview() {
  final station = metroMapStations.firstWhere(
    (s) => s.id.contains('_'),
    orElse: () => metroMapStations.first,
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: Scaffold(
      backgroundColor: AppTheme.surfaceLight,
      body: SafeArea(
        child: MetroStationDetailView(
          system: 'TRTC',
          stationId: station.id,
          name: station.name,
          onClose: () {},
        ),
      ),
    ),
  );
}

class MetroScreen extends StatefulWidget {
  const MetroScreen({super.key, this.initialStation});

  /// Station to pre-select on open (matched by map id or display name), so
  /// entry points that already know the station — e.g. a search result —
  /// land on it instead of the bare map.
  final String? initialStation;

  @override
  State<MetroScreen> createState() => _MetroScreenState();
}

enum _MapMode { time, fare }

class _MetroScreenState extends State<MetroScreen> {
  MetroMapStation? _selected;
  MetroMapStation? _prevSelected;
  _MapMode _mode = _MapMode.time;
  final _metroBloc = MetroBloc();
  final _sheetController = SheetController();

  @override
  void initState() {
    super.initState();
    final query = widget.initialStation;
    if (query == null || query.isEmpty) return;
    for (final s in metroMapStations) {
      if (s.id == query || s.name == query) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _selectStation(s);
        });
        break;
      }
    }
  }

  @override
  void dispose() {
    unawaited(_metroBloc.close());
    _sheetController.dispose();
    super.dispose();
  }

  /// The stations the boarded train still calls at, or null when no pick is
  /// open. Null is what puts the map back in its normal mode.
  Set<String>? _pickAheadIds(BuildContext context) {
    final arrival = context.watch<MrtTrackBloc>().state.pickArrival;
    if (arrival == null) return null;
    return MetroTopology.aheadStations(
      line: arrival.line,
      boardCode: arrival.stationId,
      terminalCode: arrival.destinationStationId,
    ).map((stop) => stop.id).toSet();
  }

  /// A tap on the map means "select this station" normally, and "this is where
  /// I get off" while a pick is open.
  void _onMapStationTap(MetroMapStation station) {
    final track = context.read<MrtTrackBloc>();
    if (track.state.picking) {
      track.add(MrtAlightTargetPicked(station.id));
      return;
    }
    _selectStation(station);
  }

  void _dismiss() {
    _metroBloc.add(const MetroStationDismissed());
    setState(() {
      _prevSelected = null;
      _selected = null;
    });
  }

  void _selectStation(MetroMapStation station) {
    unawaited(HapticService.instance.lightTap());
    setState(() {
      _prevSelected = _selected;
      _selected = station;
    });
    _metroBloc.add(MetroStationTapped(stationId: station.id));
    // `half`: enough room to read the station's detail card without a drag,
    // while the map above it stays visible. The map itself never moves, so a
    // station tapped while zoomed in stays exactly under the finger.
    unawaited(
      _sheetController.animateToDetent(
        AppSheetSnap.half,
        reduced: AppMotion.reduced(context),
      ),
    );
  }

  Map<String, String> _buildLabels(
    List<MetroMapStation> all,
    Map<String, JourneyInfo>? matrix,
  ) {
    if (_selected == null || matrix == null) return const {};
    return {
      for (final s in all)
        if (s.id != _selected!.id)
          if (_journeyFor(matrix, s.id) case final info?)
            s.id: _mode == _MapMode.time
                ? (info.travelTimeMin > 0 ? '${info.travelTimeMin}' : '—')
                : '${info.fareNt}',
    };
  }

  /// Interchange ids combine both line codes (e.g. `'BL15_BR10'`); the matrix
  /// is keyed by single TDX codes, so match on whichever component is present.
  JourneyInfo? _journeyFor(Map<String, JourneyInfo> matrix, String id) {
    for (final code in id.split('_')) {
      if (matrix[code] case final info?) return info;
    }
    return null;
  }

  Widget _buildBottomSheetWidget(BuildContext context, ColorScheme cs) {
    return AppSheet(
      controller: _sheetController,
      // Capped at `tall`, not `full`: keeps the line map peeking above the
      // sheet (metro is not a map-front page — the map is the content). Not
      // content-capped: the station detail card must reach the same max as
      // the station list, even on a station whose own card is short.
      snapGrid: const SheetSnapGrid(
        snaps: [AppSheetSnap.peek, AppSheetSnap.half, AppSheetSnap.tall],
        minFlingSpeed: AppSheetSnap.flingSpeed,
      ),
      // The status-bar padding ramp targets `full`; this sheet never reaches
      // it, so the ramp would never finish closing and leaves a permanent gap
      // above the drag handle at `tall`.
      padStatusBar: false,
      // Sizes to its content (no Expanded, and the pages inside shrink-wrap).
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetDragHandle(),
          const SizedBox(height: 12),
          Flexible(
            child: BlocBuilder<MetroBloc, MetroState>(
              builder: (context, state) => AnimatedSwitcher(
                duration: AppMotion.short,
                switchInCurve: AppMotion.easeOut,
                switchOutCurve: AppMotion.easeOut,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                // Only the incoming page sizes the sheet: the outgoing one is
                // positioned, so it fills whatever height the new page asks
                // for instead of holding the sheet at its own. The station
                // list fills the viewport, so leaving it unpositioned kept the
                // sheet full-height for the length of the fade — a blank band
                // under a short station card on every tap. Top-aligned rather
                // than the default centre so the header stays put mid-fade.
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    for (final child in previousChildren)
                      Positioned.fill(child: child),
                    ?currentChild,
                  ],
                ),
                child: state.error != null
                    ? ErrorStateView(
                        key: const ValueKey('error'),
                        error: state.error!,
                        onRetry: _selected == null
                            ? null
                            : () => _metroBloc.add(
                                MetroStationTapped(stationId: _selected!.id),
                              ),
                      )
                    : _selected != null
                    ? MetroStationDetailView(
                        // Keyed by station id, not a constant 'detail': the
                        // nested BlocProvider(create:) runs once per element,
                        // so a constant key reused the same MetroEtaBloc across
                        // station switches — title updated (widget prop) but
                        // ETA/schedule stayed on the first station.
                        key: ValueKey('detail:${_selected!.id}'),
                        system: 'TRTC',
                        stationId: _selected!.id,
                        name: _selected!.name,
                        onClose: _dismiss,
                      )
                    : _MetroPlaceholderSheet(
                        key: const ValueKey('placeholder'),
                        onStationSelect: _selectStation,
                        sheetController: _sheetController,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocProvider.value(
      value: _metroBloc,
      child: Scaffold(
        // The map SVG is transparent, so the Scaffold paints the map canvas.
        // A dedicated canvas — crisp white in light, deepened near-black in
        // dark — instead of the grey scaffold surface, so lines and the
        // #1a1a1a interchange dots lift off the background.
        backgroundColor: cs.brightness == Brightness.dark
            ? const Color(0xFF0C0C0C)
            : Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            BlocBuilder<MetroBloc, MetroState>(
              // The map only reads journeyMatrix (via _buildLabels below);
              // activeStationId/error changes elsewhere in MetroState
              // shouldn't force a full SVG map + ~120 label rebuild.
              buildWhen: (previous, current) =>
                  previous.journeyMatrix != current.journeyMatrix,
              builder: (context, state) => MetroSvgMap(
                selectedStationId: _selected?.id,
                onStationTap: _onMapStationTap,
                pickAheadIds: _pickAheadIds(context),
                pickBoardId: context
                    .watch<MrtTrackBloc>()
                    .state
                    .pickArrival
                    ?.stationId,
                pickedStationId: context
                    .watch<MrtTrackBloc>()
                    .state
                    .pickTargetStationId,
                stationLabels: _buildLabels(
                  metroMapStations,
                  state.journeyMatrix,
                ),
                animate: _prevSelected == null && _selected != null,
              ),
            ),
            // Both map-level controls share one row so the width they compete
            // for is real: the back button and system pill take their intrinsic
            // width, and the time/fare switch flex-shrinks into whatever is
            // left instead of overdrawing them at large text scales. The
            // switch lives on the map because it drives the whole-map station
            // labels, and surfaces only once a station is selected.
            Align(
              alignment: Alignment.topCenter,
              child: FloatingAppBar(
                leading: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppBarBackButton(floating: true),
                    SizedBox(width: AppBarMetrics.gap),
                    _SystemPill(),
                  ],
                ),
                trailing: Flexible(
                  child: AnimatedSwitcher(
                    duration: AppMotion.short,
                    switchInCurve: AppMotion.easeOut,
                    switchOutCurve: AppMotion.easeOut,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.9,
                          end: 1,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _selected != null
                        ? _MapModeChip(
                            key: const ValueKey('map-mode-chip'),
                            mode: _mode,
                            onChanged: (m) => setState(() => _mode = m),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            if (!context.watch<MrtTrackBloc>().state.picking)
              _buildBottomSheetWidget(context, cs),
            if (context.watch<MrtTrackBloc>().state.picking)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 60,
                left: 0,
                right: 0,
                child: Center(
                  child: AlightPickCapsule(
                    onCancel: () => context.read<MrtTrackBloc>().add(
                      const MrtAlightPickCancelled(),
                    ),
                  ),
                ),
              ),
            const Align(
              alignment: Alignment.bottomCenter,
              child: _MetroAlightDock(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The bottom half of the metro 下車提醒 flow: the confirm bar once a station
/// has been picked, and the manage card while a session is running.
///
/// It reads the flow straight from [MrtTrackBloc] rather than taking it down
/// through the map, because the bell that opens the flow lives on a different
/// screen (the station sheet, or a station opened from search).
class _MetroAlightDock extends StatefulWidget {
  const _MetroAlightDock();

  @override
  State<_MetroAlightDock> createState() => _MetroAlightDockState();
}

class _MetroAlightDockState extends State<_MetroAlightDock> {
  final _carController = TextEditingController();

  @override
  void dispose() {
    _carController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MrtTrackBloc, MrtTrackBlocState>(
      builder: (context, state) {
        final arrival = state.pickArrival;
        final targetId = state.pickTargetStationId;
        if (arrival == null || targetId == null) {
          return const SizedBox.shrink();
        }
        final ahead = MetroTopology.aheadStations(
          line: arrival.line,
          boardCode: arrival.stationId,
          terminalCode: arrival.destinationStationId,
        );
        final target = ahead.where((s) => s.id == targetId).firstOrNull;
        if (target == null) return const SizedBox.shrink();

        // Derived from the congestion feed's paired carriage when there is one
        // (ADR-0015); otherwise the rider reads it off the car and types it,
        // and that field is the only thing standing between them and 開始.
        final autoCarId = deriveCarIdFromCn1(arrival.cn1);
        final carId = arrival.cn1.isNotEmpty
            ? autoCarId
            : _carController.text.trim();

        return AlightConfirmBar(
          targetName: target.name,
          lead: state.pickLead,
          onLeadChanged: (v) =>
              context.read<MrtTrackBloc>().add(MrtAlightLeadChanged(v)),
          onRepick: () => context.read<MrtTrackBloc>().add(
            const MrtAlightTargetCleared(),
          ),
          onCancel: () => context.read<MrtTrackBloc>().add(
            const MrtAlightPickCancelled(),
          ),
          canStart: carId.isNotEmpty,
          busy: state.creating,
          errorText: state.createError == MrtTrackCreateError.none
              ? null
              : _errorText(AppI18n.of(context), state.createError),
          binding: arrival.cn1.isNotEmpty
              ? AlightBindingChip(
                  label: AppI18n.of(context).metroCarChip(autoCarId),
                )
              : _CarNumberField(
                  controller: _carController,
                  // The CTA is gated on a car number being present, so the
                  // field has to force a rebuild as it is typed.
                  onChanged: (_) => setState(() {}),
                ),
          onStart: () => context.read<MrtTrackBloc>().add(
            MrtTrackRequested(
              carId: carId,
              boardStationId: arrival.stationId,
              destStationId: arrival.destinationStationId,
              targetStationId: target.id,
              leadStops: state.pickLead,
              // The reminder can be armed from the platform while the train is
              // still several stations out; these let the session watch the
              // arrival board until it pulls in.
              system: arrival.system,
              trainNumber: arrival.trainNumber,
              boardEtaSeconds: arrival.estimateSeconds,
            ),
          ),
        );
      },
    );
  }

  static String _errorText(AppI18n i18n, MrtTrackCreateError error) =>
      switch (error) {
        MrtTrackCreateError.notReachable => i18n.mrtAlightNotReachable,
        MrtTrackCreateError.notFound => i18n.mrtAlightNotFound,
        MrtTrackCreateError.generic => i18n.mrtAlightGenericError,
        MrtTrackCreateError.none => '',
      };
}

/// Manual carriage entry, for a train whose congestion feed came unpaired.
class _CarNumberField extends StatelessWidget {
  const _CarNumberField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: AppTextStyles.memo.copyWith(fontSize: 16),
      decoration: InputDecoration(
        isDense: true,
        labelText: AppI18n.of(context).mrtAlightCarNumberLabel,
        hintText: AppI18n.of(context).mrtAlightCarNumberHint,
        hintStyle: AppTextStyles.memo.copyWith(
          fontSize: 16,
          color: cs.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        ),
      ),
    );
  }
}
