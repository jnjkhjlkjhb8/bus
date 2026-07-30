import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/core/haptics/haptic_service.dart';
import 'package:wheres_the_bus/data/models/favorite.dart';
import 'package:wheres_the_bus/data/models/journey_info.dart';
import 'package:wheres_the_bus/data/models/metro_map_models.dart';
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
    // Selecting a station turns the whole map into the answer — every other
    // station gets a travel-time/fare label. At `half` the sheet covers the
    // southern third of the network, so it yields to `peek` and lets the map
    // be read; pulling it back up is one drag. The map itself never moves,
    // so a station tapped while zoomed in stays exactly under the finger.
    unawaited(
      _sheetController.animateToDetent(
        AppSheetSnap.peek,
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
      // The station card's close button and the app bar's back button both
      // stay (see AppSheet.onExit).
      onExit: null,
      // Capped at `tall`, not `full`: keeps the line map peeking above the
      // sheet (metro is not a map-front page — the map is the content).
      // Capped a second time at the content's own height: a station with no
      // live arrivals is a short card, and without this the rider can drag it
      // to `tall` and pull a screenful of blank surface up behind it.
      snapGrid: const ContentCappedSnapGrid(
        base: SheetSnapGrid(
          snaps: [AppSheetSnap.peek, AppSheetSnap.half, AppSheetSnap.tall],
          minFlingSpeed: AppSheetSnap.flingSpeed,
        ),
      ),
      // Sizes to its content (no Expanded, and the pages inside shrink-wrap)
      // so the grid above has a content height to clamp against. Pages whose
      // own content fills the sheet — the station list — still do.
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
                onStationTap: _selectStation,
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
            _buildBottomSheetWidget(context, cs),
          ],
        ),
      ),
    );
  }
}
