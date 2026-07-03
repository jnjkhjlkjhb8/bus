import 'dart:async';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/decoders/thsr_decoder.dart';
import 'package:wheres_the_car/data/decoders/tra_decoder.dart';
import 'package:wheres_the_car/data/generated/tra.pb.dart'
    show Resp_tra_delay, Resp_tra_live_board, tra_LiveBoards, tra_delays;
import 'package:wheres_the_car/data/repositories/thsr_repository.dart';
import 'package:wheres_the_car/data/repositories/tra_repository.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_event.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_state.dart';

class RailBloc extends Bloc<RailEvent, RailState> {
  RailBloc() : super(const RailInitial()) {
    on<RailSystemChanged>(_onSystemChanged);
    on<RailStationSelected>(_onStationSelected);
    on<RailLiveBoardStarted>(_onLiveBoardStarted);
    on<RailLiveBoardStopped>(_onLiveBoardStopped);
    on<RailQueryChanged>(_onQueryChanged);
    on<RailTimetableRequested>(_onTimetableRequested);
    on<RailTrainStopsRequested>(_onTrainStopsRequested);
    on<RailDelaysUpdated>(_onDelaysUpdated);
  }

  static final _dateFormat = DateFormat('yyyy-MM-dd');

  RailLiveBoardLoaded _defaultLoaded(RailSystem system) {
    final now = DateTime.now();
    return RailLiveBoardLoaded(
      system: system,
      stationId: '',
      stationName: '桃園',
      traItems: const [],
      queryOriginId: '',
      queryOriginName: '起點站',
      queryDestId: '',
      queryDestName: '終點站',
      queryDate: now,
      queryTime: TimeOfDay.fromDateTime(now),
      departureMode: true,
    );
  }

  void _onSystemChanged(RailSystemChanged event, Emitter<RailState> emit) {
    final current = state;
    if (current is RailLiveBoardLoaded) {
      emit(current.copyWith(system: event.system));
    } else {
      emit(_defaultLoaded(event.system));
    }
  }

  void _onStationSelected(RailStationSelected event, Emitter<RailState> emit) {
    final current = state;
    if (current is RailLiveBoardLoaded) {
      emit(
        current.copyWith(
          stationId: event.stationId,
          stationName: event.stationName,
        ),
      );
    } else {
      emit(
        _defaultLoaded(RailSystem.tra).copyWith(
          stationId: event.stationId,
          stationName: event.stationName,
        ),
      );
    }
    add(const RailLiveBoardStarted());
  }

  Future<void> _onLiveBoardStarted(
    RailLiveBoardStarted event,
    Emitter<RailState> emit,
  ) async {
    final current = state;
    final system = current is RailLiveBoardLoaded
        ? current.system
        : RailSystem.tra;
    final stationId = current is RailLiveBoardLoaded ? current.stationId : '';
    if (stationId.isEmpty) return;
    if (system != RailSystem.tra) return;

    final date = _dateFormat.format(DateTime.now());
    await emit.forEach<Resp_tra_live_board>(
      TraRepository.instance.liveBoard(stationId, date),
      onData: (response) {
        final boards = tra_LiveBoards.fromBuffer(response.data);
        final items = TraDecoder.instance.decodeLiveBoard(boards);
        final loaded = current is RailLiveBoardLoaded
            ? current.copyWith(traItems: items)
            : _defaultLoaded(system).copyWith(
                stationId: stationId,
                traItems: items,
              );
        return loaded;
      },
      onError: (e, _) => RailError(AppError.from(e)),
    );
  }

  void _onLiveBoardStopped(
    RailLiveBoardStopped event,
    Emitter<RailState> emit,
  ) {}

  void _onQueryChanged(RailQueryChanged event, Emitter<RailState> emit) {
    final current = state;
    if (current is RailLiveBoardLoaded) {
      emit(
        current.copyWith(
          queryOriginId: event.originId,
          queryOriginName: event.originName,
          queryDestId: event.destId,
          queryDestName: event.destName,
          queryDate: event.date,
          queryTime: event.time,
          departureMode: event.departureMode,
        ),
      );
    }
  }

  Future<void> _onTimetableRequested(
    RailTimetableRequested event,
    Emitter<RailState> emit,
  ) async {
    final current = state;
    final system = current is RailLiveBoardLoaded
        ? current.system
        : RailSystem.tra;
    final originName = current is RailLiveBoardLoaded
        ? current.queryOriginName
        : '';
    final destName = current is RailLiveBoardLoaded
        ? current.queryDestName
        : '';

    emit(
      RailTimetableLoading(
        system: system,
        originName: originName,
        destName: destName,
        date: event.date,
      ),
    );

    try {
      if (system == RailSystem.tra) {
        final result = await TraRepository.instance.timetable(
          event.date,
          event.originId,
          event.destId,
        );
        final items = TraDecoder.instance.decodeTimetable(result);
        emit(
          RailTimetableLoaded(
            system: system,
            originName: originName,
            destName: destName,
            date: event.date,
            traItems: items,
          ),
        );
        await emit.forEach<Resp_tra_delay>(
          TraRepository.instance.delay(
            event.date,
            event.originId,
            event.destId,
          ),
          onData: (response) {
            final current = state;
            if (current is! RailTimetableLoaded) return state;
            final parsed = tra_delays.fromBuffer(response.data);
            return current.copyWith(
              delays: Map<String, int>.from(
                TraDecoder.instance.decodeDelayMap(parsed),
              ),
            );
          },
          onError: (e, s) => state,
        );
      } else {
        final result = await ThsrRepository.instance.timetable(
          event.date,
          event.originId,
          event.destId,
        );
        final items = ThsrDecoder.instance.decodeTimetable(result);
        emit(
          RailTimetableLoaded(
            system: system,
            originName: originName,
            destName: destName,
            date: event.date,
            thsrItems: items,
          ),
        );
      }
    } on Object catch (e) {
      emit(RailError(AppError.from(e)));
    }
  }

  void _onDelaysUpdated(RailDelaysUpdated event, Emitter<RailState> emit) {
    final current = state;
    if (current is! RailTimetableLoaded) return;
    emit(current.copyWith(delays: event.delays));
  }

  Future<void> _onTrainStopsRequested(
    RailTrainStopsRequested event,
    Emitter<RailState> emit,
  ) async {
    try {
      final current = state;
      final system = current is RailTimetableLoaded
          ? current.system
          : RailSystem.tra;
      if (system == RailSystem.tra) {
        final result = await TraRepository.instance.stops(
          event.date,
          event.trainNo,
        );
        final stops = TraDecoder.instance.decodeStops(result);
        emit(
          RailTrainStopsLoaded(
            system: system,
            trainNo: event.trainNo,
            trainType: '台鐵',
            traStops: stops,
          ),
        );
      } else {
        final result = await ThsrRepository.instance.stops(
          event.date,
          event.trainNo,
        );
        final stops = ThsrDecoder.instance.decodeStopTimes(result);
        emit(
          RailTrainStopsLoaded(
            system: system,
            trainNo: event.trainNo,
            trainType: '高鐵',
            thsrStops: stops,
          ),
        );
      }
    } on Object catch (e) {
      emit(RailError(AppError.from(e)));
    }
  }
}
