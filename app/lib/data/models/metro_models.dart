import 'package:equatable/equatable.dart';

/// One live metro arrival estimate. estimateSeconds is raw; callers apply
/// etaCeilMinutes (eta_format.dart) for display so the ceil rule has one owner.
class MetroLiveArrival extends Equatable {
  const MetroLiveArrival({
    required this.line,
    required this.destination,
    required this.estimateSeconds,
  });

  final String line;
  final String destination;
  final int estimateSeconds;

  @override
  List<Object?> get props => [line, destination, estimateSeconds];
}

/// One row of a station's first/last-train schedule, per destination.
class MetroScheduleEntry extends Equatable {
  const MetroScheduleEntry({
    required this.destination,
    required this.firstTime,
    required this.lastTime,
  });

  factory MetroScheduleEntry.fromRow(Map<String, dynamic> row) =>
      MetroScheduleEntry(
        destination: row['destinationstaionid'] as String,
        firstTime: row['first_train_time'] as String,
        lastTime: row['last_train_time'] as String,
      );

  final String destination;
  final String firstTime;
  final String lastTime;

  @override
  List<Object?> get props => [destination, firstTime, lastTime];
}
