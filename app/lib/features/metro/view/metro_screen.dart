import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/app/theme/app_shadows.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/data/models/journey_info.dart';
import 'package:wheres_the_car/data/models/metro_map_models.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_bloc.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_event.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_state.dart';
import 'package:wheres_the_car/features/metro/view/metro_station_detail_view.dart';
import 'package:wheres_the_car/features/metro/widgets/metro_svg_map.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_sliding_segment.dart';
import 'package:wheres_the_car/shared/widgets/app_snackbar.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_car/shared/widgets/error_state_view.dart';
import 'package:wheres_the_car/shared/widgets/transport_icon.dart';

part '../widgets/metro_placeholder_widgets.dart';
part '../widgets/metro_system_widgets.dart';

const _kLineNames = <String, String>{
  'BL': '板南線',
  'R': '淡水信義線',
  'G': '松山新店線',
  'BR': '文湖線',
  'O': '中和新蘆線',
};

final RegExp _digits = RegExp(r'\d+');

String _lineCode(String id) => id.split('_').first.replaceAll(_digits, '');

String _lineName(String id) => _kLineNames[_lineCode(id)] ?? _lineCode(id);

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
  const MetroScreen({super.key});

  @override
  State<MetroScreen> createState() => _MetroScreenState();
}

enum _MapMode { time, fare }

class _MetroScreenState extends State<MetroScreen> {
  MetroMapStation? _selected;
  MetroMapStation? _prevSelected;
  _MapMode _mode = _MapMode.time;
  final _metroBloc = MetroBloc();

  @override
  void dispose() {
    unawaited(_metroBloc.close());
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
    setState(() {
      _prevSelected = _selected;
      _selected = station;
    });
    _metroBloc.add(MetroStationTapped(stationId: station.id));
  }

  Map<String, String> _buildLabels(
    List<MetroMapStation> all,
    Map<String, JourneyInfo>? matrix,
  ) {
    if (_selected == null || matrix == null) return const {};
    return {
      for (final s in all)
        if (s.id != _selected!.id)
          if (matrix[s.id] case final info?)
            s.id: _mode == _MapMode.time
                ? (info.travelTimeMin > 0 ? '${info.travelTimeMin}' : '—')
                : '\$${info.fareNt}',
    };
  }

  Widget _buildBottomSheetWidget(BuildContext context, ColorScheme cs) {
    return Sheet(
      initialOffset: const SheetOffset.proportionalToViewport(0.5),
      snapGrid: const SheetSnapGrid(
        snaps: [
          SheetOffset.proportionalToViewport(0.25),
          SheetOffset.proportionalToViewport(0.5),
          SheetOffset.proportionalToViewport(0.85),
        ],
      ),
      scrollConfiguration: const SheetScrollConfiguration(),
      decoration: MaterialSheetDecoration(
        size: SheetSize.stretch,
        color: cs.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusBottomSheet),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      child: Column(
        children: [
          const SheetDragHandle(),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppSlidingSegment<_MapMode>(
              options: const {_MapMode.time: '旅途時間', _MapMode.fare: '票價'},
              value: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
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
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ...previousChildren,
                      ?currentChild,
                    ],
                  );
                },
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
                        key: const ValueKey('detail'),
                        system: 'TRTC',
                        stationId: _selected!.id,
                        name: _selected!.name,
                        onClose: _dismiss,
                      )
                    : _MetroPlaceholderSheet(
                        key: const ValueKey('placeholder'),
                        onStationSelect: _selectStation,
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
            SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppBarCircleButton(
                        onTap: () => Navigator.of(
                          context,
                          rootNavigator: true,
                        ).maybePop(),
                        semanticLabel: '返回',
                        child: Icon(
                          Icons.arrow_back_rounded,
                          size: 20,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const _SystemPill(),
                    ],
                  ),
                ),
              ),
            ),
            SheetViewport(
              child: SheetExitGestureDetector(
                onExit: () {
                  if (_selected != null) {
                    _dismiss();
                  } else {
                    unawaited(
                      Navigator.of(context, rootNavigator: true).maybePop(),
                    );
                  }
                },
                child: _buildBottomSheetWidget(context, cs),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
