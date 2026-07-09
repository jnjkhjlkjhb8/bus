import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/data/models/search_models.dart';
import 'package:wheres_the_car/features/search/genui/data/genui_service.dart';
import 'package:wheres_the_car/features/search/genui/model/genui_node.dart';

sealed class GenUiEvent extends Equatable {
  const GenUiEvent();
  @override
  List<Object?> get props => const [];
}

class GenUiAsked extends GenUiEvent {
  const GenUiAsked(this.prompt);
  final String prompt;
  @override
  List<Object?> get props => [prompt];
}

class GenUiCancelled extends GenUiEvent {
  const GenUiCancelled();
}

class GenUiPhaseChanged extends GenUiEvent {
  const GenUiPhaseChanged(this.phase, this.query);
  final GenUiPhase phase;
  final String? query;
  @override
  List<Object?> get props => [phase, query];
}

enum GenUiStatus { idle, loading, content, error }

enum GenUiErrorKind { offline, generic }

class GenUiState extends Equatable {
  const GenUiState({
    this.status = GenUiStatus.idle,
    this.nodes = const [],
    this.refs = const {},
    this.phase = GenUiPhase.thinking,
    this.phaseQuery,
    this.errorKind = GenUiErrorKind.generic,
    this.lastPrompt = '',
  });

  final GenUiStatus status;
  final List<GenUiNode> nodes;
  final Map<String, SearchResult> refs;
  final GenUiPhase phase;
  final String? phaseQuery;
  final GenUiErrorKind errorKind;
  final String lastPrompt;

  @override
  List<Object?> get props =>
      [status, nodes, refs, phase, phaseQuery, errorKind, lastPrompt];
}

class GenUiBloc extends Bloc<GenUiEvent, GenUiState> {
  GenUiBloc({
    GenUiService service = GenUiService.instance,
    Duration timeout = const Duration(seconds: 25),
  })  : _service = service,
        _timeout = timeout,
        super(const GenUiState()) {
    on<GenUiAsked>(_onAsked);
    on<GenUiCancelled>(_onCancelled);
    on<GenUiPhaseChanged>(_onPhaseChanged);
  }

  final Duration _timeout;
  final GenUiService _service;
  // 世代計數:取消或重問後,舊請求完成時比對不符即丟棄結果。
  var _generation = 0;

  Future<void> _onAsked(GenUiAsked event, Emitter<GenUiState> emit) async {
    final prompt = event.prompt.trim();
    if (prompt.isEmpty) return;
    final gen = ++_generation;
    emit(GenUiState(status: GenUiStatus.loading, lastPrompt: prompt));
    try {
      final answer = await _service
          .ask(
            prompt,
            onPhase: (phase, query) {
              if (gen == _generation && !isClosed) {
                add(GenUiPhaseChanged(phase, query));
              }
            },
          )
          .timeout(_timeout);
      if (gen != _generation) return;
      emit(GenUiState(
        status: GenUiStatus.content,
        nodes: answer.nodes,
        refs: answer.refs,
        lastPrompt: prompt,
      ));
    } on Object catch (e) {
      if (gen != _generation) return;
      emit(GenUiState(
        status: GenUiStatus.error,
        errorKind:
            _isOffline(e) ? GenUiErrorKind.offline : GenUiErrorKind.generic,
        lastPrompt: prompt,
      ));
    }
  }

  void _onCancelled(GenUiCancelled event, Emitter<GenUiState> emit) {
    _generation++;
    emit(GenUiState(lastPrompt: state.lastPrompt));
  }

  void _onPhaseChanged(GenUiPhaseChanged event, Emitter<GenUiState> emit) {
    if (state.status != GenUiStatus.loading) return;
    emit(GenUiState(
      status: GenUiStatus.loading,
      phase: event.phase,
      phaseQuery: event.query,
      lastPrompt: state.lastPrompt,
    ));
  }

  static bool _isOffline(Object e) =>
      e is SocketException || e.toString().contains('SocketException');
}
