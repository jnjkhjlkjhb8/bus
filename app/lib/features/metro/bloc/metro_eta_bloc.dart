import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/core/powersync/powersync_service.dart';
import 'package:wheres_the_car/data/decoders/mrt_decoder.dart';
import 'package:wheres_the_car/data/generated/mrt.pb.dart';
import 'package:wheres_the_car/data/models/eta_format.dart';
import 'package:wheres_the_car/data/repositories/mrt_repository.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_eta_event.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_eta_state.dart';

class MetroEtaBloc extends Bloc<MetroEtaEvent, MetroEtaState> {
  MetroEtaBloc() : super(const MetroEtaState()) {
    on<LoadMetroEta>(_onLoad);
    on<MetroEtaArrived>(_onArrived);
  }

  StreamSubscription<Resp_Mrt_eta>? _sub;

  Future<void> _onLoad(LoadMetroEta e, Emitter<MetroEtaState> emit) async {
    await _sub?.cancel();
    emit(const MetroEtaState(loading: true));
    try {
      _sub = MrtRepository.instance.eta(e.system, e.stationId).listen((resp) {
        final live = MrtDecoder.instance.decodeEta(
          Uint8List.fromList(resp.data),
        );
        final mins = etaCeilMinutes(live.estimateTime);
        add(
          MetroEtaArrived(
            MetroArrival(
              line: live.lineID,
              destination: live.destinationStationName,
              estimateMinutes: mins,
              approaching: live.estimateTime <= 30,
            ),
          ),
        );
      });
      final rows = await PowerSyncService.instance.db.getAll(
        'SELECT destinationstaionid, first_train_time, last_train_time '
        'FROM mrt_schedule WHERE station_id = ?',
        [e.stationId],
      );
      emit(state.copyWith(
        schedule: [
          for (final r in rows)
            MetroSchedule(
              destination: r['destinationstaionid'] as String,
              firstTime: r['first_train_time'] as String,
              lastTime: r['last_train_time'] as String,
            ),
        ],
      ));
    } on Object catch (err) {
      emit(state.copyWith(loading: false, error: err.toString()));
    }
  }

  void _onArrived(MetroEtaArrived e, Emitter<MetroEtaState> emit) {
    final next = [
      ...state.arrivals.where(
        (a) =>
            !(a.line == e.arrival.line &&
                a.destination == e.arrival.destination),
      ),
      e.arrival,
    ]..sort((a, b) => a.estimateMinutes.compareTo(b.estimateMinutes));
    emit(state.copyWith(arrivals: next, loading: false));
  }

  @override
  Future<void> close() {
    unawaited(_sub?.cancel());
    return super.close();
  }
}
