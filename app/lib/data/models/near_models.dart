import 'package:equatable/equatable.dart';

enum NearStationType { bus, bike, mrt, tra, thsr }

class NearStationViewModel extends Equatable {
  const NearStationViewModel({
    required this.type,
    required this.stationId,
    required this.stationName,
    required this.lat,
    required this.lon,
    required this.walkingMinutes,
    required this.distanceMeters,
    this.lineIds = const [],
  });

  final NearStationType type;
  final String stationId;
  final String stationName;
  final double lat;
  final double lon;
  final int walkingMinutes;
  final int distanceMeters;
  final List<String> lineIds;

  String get displayDistance {
    if (distanceMeters < 1000) return '${distanceMeters}m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)}km';
  }

  @override
  List<Object?> get props => [type, stationId, stationName];
}
