import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

enum GenUiStatus { idle, loading, content, error }

class GenUiState extends Equatable {
  const GenUiState({
    this.status = GenUiStatus.idle,
    this.nodes = const [],
  });

  final GenUiStatus status;
  final List<GenUiNode> nodes;

  GenUiState copyWith({GenUiStatus? status, List<GenUiNode>? nodes}) =>
      GenUiState(
        status: status ?? this.status,
        nodes: nodes ?? this.nodes,
      );

  @override
  List<Object?> get props => [status, nodes];
}

class GenUiBloc extends Bloc<GenUiEvent, GenUiState> {
  GenUiBloc({GenUiService service = GenUiService.instance})
      : _service = service,
        super(const GenUiState()) {
    on<GenUiAsked>(_onAsked);
  }

  final GenUiService _service;

  Future<void> _onAsked(GenUiAsked event, Emitter<GenUiState> emit) async {
    final prompt = event.prompt.trim();
    if (prompt.isEmpty) return;
    emit(const GenUiState(status: GenUiStatus.loading));
    try {
      final nodes = await _service.ask(prompt);
      emit(GenUiState(status: GenUiStatus.content, nodes: nodes));
    } on Object {
      emit(const GenUiState(status: GenUiStatus.error));
    }
  }
}
