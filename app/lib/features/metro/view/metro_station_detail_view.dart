import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/data/models/arrival_display.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/data/models/metro_map_models.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_eta_bloc.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_eta_event.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_eta_state.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/motion/stagger.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_car/shared/widgets/eta_list_tile.dart';
import 'package:wheres_the_car/shared/widgets/sheet_detail_header.dart';
import 'package:wheres_the_car/shared/widgets/state_cards.dart';
import 'package:wheres_the_car/shared/widgets/transport_icon.dart';

part '../widgets/metro_station_detail_widgets.dart';

const _kLineNames = <String, String>{
  'BL': '板南線',
  'R': '淡水信義線',
  'G': '松山新店線',
  'BR': '文湖線',
  'O': '中和新蘆線',
  'Y': '環狀線',
};

final RegExp _digits = RegExp(r'\d+');

String _lineCode(String id) => id.split('_').first.replaceAll(_digits, '');

String _lineName(String id) => _kLineNames[_lineCode(id)] ?? _lineCode(id);

/// Line label for a (possibly interchange) id, e.g. `板南線・文湖線`.
String _stationLineLabel(String id) => id
    .split('_')
    .map((p) => p.replaceAll(_digits, ''))
    .map((code) => _kLineNames[code] ?? code)
    .join('・');

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
class MetroStationDetailView extends StatelessWidget {
  const MetroStationDetailView({
    required this.system,
    required this.stationId,
    required this.name,
    this.onClose,
    super.key,
  });

  final String system;
  final String stationId;
  final String name;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final sheet = BlocProvider(
      create: (_) => MetroEtaBloc()..add(LoadMetroEta(system, stationId)),
      child: _StationDetailSheet(
        system: system,
        station: MetroMapStation(id: stationId, name: name, x: 0, y: 0),
        onClose: onClose,
      ),
    );
    if (onClose != null) return sheet;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetDragHandle(),
        Flexible(child: sheet),
      ],
    );
  }
}
