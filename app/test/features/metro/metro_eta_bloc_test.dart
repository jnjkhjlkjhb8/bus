import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_eta_bloc.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_eta_state.dart';

void main() {
  test('MetroEtaBloc has empty arrivals initially', () {
    final bloc = MetroEtaBloc();
    addTearDown(bloc.close);
    expect(bloc.state.arrivals, isEmpty);
    expect(bloc.state, isA<MetroEtaState>());
  });
}
