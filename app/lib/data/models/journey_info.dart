class JourneyInfo {
  const JourneyInfo({
    required this.toStationId,
    required this.fareNt,
  });

  factory JourneyInfo.fromRow(Map<String, dynamic> row) => JourneyInfo(
    toStationId: row['to_station_id'] as String,
    fareNt: row['fare_nt'] as int,
  );

  final String toStationId;
  final int fareNt;
}
