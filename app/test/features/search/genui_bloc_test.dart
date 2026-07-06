// Sequential add/expect on the same bloc reads clearer than cascades here.
// ignore_for_file: cascade_invocations

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/features/search/bloc/search_state.dart';
import 'package:wheres_the_car/features/search/genui/bloc/genui_bloc.dart';
import 'package:wheres_the_car/features/search/genui/data/genui_service.dart';
import 'package:wheres_the_car/features/search/genui/model/genui_node.dart';

class _FakeService extends GenUiService {
  const _FakeService(this._impl);
  final Future<GenUiAnswer> Function(
    String prompt,
    void Function(GenUiPhase, String?)? onPhase,
  ) _impl;

  @override
  Future<GenUiAnswer> ask(
    String prompt, {
    void Function(GenUiPhase phase, String? query)? onPhase,
  }) =>
      _impl(prompt, onPhase);
}

const _answer = GenUiAnswer(
  nodes: [GenUiText('hi')],
  refs: {
    'U1': SearchResult(
      type: SearchResultType.busRoute,
      uid: 'U1',
      name: '307',
      subtitle: '',
    ),
  },
);

void main() {
  test('success: loading phases then content with refs', () async {
    final bloc = GenUiBloc(
      service: _FakeService((prompt, onPhase) async {
        onPhase?.call(GenUiPhase.searching, '307');
        // Yield so the queued GenUiPhaseChanged event is processed before the
        // content emit, mirroring the real service's await gaps between the
        // searching phase and the final renderUI response.
        await Future<void>.delayed(Duration.zero);
        return _answer;
      }),
    );
    final states = <GenUiState>[];
    final sub = bloc.stream.listen(states.add);
    bloc.add(const GenUiAsked('307 幾分到'));
    await pumpEventQueue();
    expect(states.first.status, GenUiStatus.loading);
    expect(states.any((s) => s.phase == GenUiPhase.searching), isTrue);
    expect(states.last.status, GenUiStatus.content);
    expect(states.last.refs.containsKey('U1'), isTrue);
    await sub.cancel();
    await bloc.close();
  });

  test('cancel: stale result is ignored', () async {
    final gate = Completer<GenUiAnswer>();
    final bloc = GenUiBloc(
      service: _FakeService((prompt, onPhase) => gate.future),
    );
    bloc.add(const GenUiAsked('q'));
    await Future<void>.delayed(Duration.zero);
    bloc.add(const GenUiCancelled());
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.status, GenUiStatus.idle);
    gate.complete(_answer);
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.status, GenUiStatus.idle);
    await bloc.close();
  });

  test('offline error is classified', () async {
    final bloc = GenUiBloc(
      service: _FakeService(
        (prompt, onPhase) => throw const SocketException('no net'),
      ),
    );
    bloc.add(const GenUiAsked('q'));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.status, GenUiStatus.error);
    expect(bloc.state.errorKind, GenUiErrorKind.offline);
    expect(bloc.state.lastPrompt, 'q');
    await bloc.close();
  });

  test('generic error keeps lastPrompt for retry', () async {
    final bloc = GenUiBloc(
      service: _FakeService((prompt, onPhase) => throw StateError('boom')),
    );
    bloc.add(const GenUiAsked('q'));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.status, GenUiStatus.error);
    expect(bloc.state.errorKind, GenUiErrorKind.generic);
    await bloc.close();
  });

  test('timeout ends in generic error', () async {
    final bloc = GenUiBloc(
      service:
          _FakeService((prompt, onPhase) => Completer<GenUiAnswer>().future),
      timeout: const Duration(milliseconds: 10),
    );
    bloc.add(const GenUiAsked('q'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bloc.state.status, GenUiStatus.error);
    expect(bloc.state.errorKind, GenUiErrorKind.generic);
    await bloc.close();
  });
}
