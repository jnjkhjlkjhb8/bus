import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/features/bike/bloc/bike_station_bloc.dart';

void main() {
  test('BikeStationBloc starts in loading state', () {
    final bloc = BikeStationBloc(stationUid: 'bike-tpe');
    addTearDown(bloc.close);
    expect(bloc.state.loading, isTrue);
    expect(bloc.state.available, 0);
  });
}
