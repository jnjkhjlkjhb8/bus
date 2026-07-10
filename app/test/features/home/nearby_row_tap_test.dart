import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/models/near_models.dart';
import 'package:wheres_the_car/features/home/home_screen.dart';

void main() {
  testWidgets('點附近車站列會以該站呼叫 onStationTap', (tester) async {
    const station = NearStationViewModel(
      type: NearStationType.bus,
      stationId: 'S1',
      stationName: '台北車站',
      lat: 25,
      lon: 121.5,
      walkingMinutes: 3,
      distanceMeters: 200,
    );
    NearStationViewModel? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildNearbyRowForTest(
            station: station,
            onStationTap: (s) => tapped = s,
          ),
        ),
      ),
    );
    await tester.tap(find.text('台北車站'));
    expect(tapped, station);
  });
}
