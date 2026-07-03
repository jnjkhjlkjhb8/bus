class JourneyInfo {
  const JourneyInfo({
    required this.toStationId,
    required this.travelTimeMin,
    required this.fareNt,
  });

  factory JourneyInfo.fromRow(Map<String, dynamic> row) => JourneyInfo(
    toStationId: row['to_station_id'] as String,
    travelTimeMin: row['travel_time_min'] as int,
    fareNt: row['fare_nt'] as int,
  );

  final String toStationId;
  final int travelTimeMin;
  final int fareNt;
}
