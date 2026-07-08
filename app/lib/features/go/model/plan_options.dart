import 'package:equatable/equatable.dart';

/// User-tunable TDX MaaS routing parameters. Defaults mirror the TDX API
/// defaults so an untouched plan behaves exactly as before.
class PlanOptions extends Equatable {
  const PlanOptions({
    this.gc = 0,
    this.top = 5,
    this.transitModes = const [3, 4, 5, 6, 7, 8, 9],
    this.transferMin = 15,
    this.transferMax = 60,
    this.firstMileMode = 0,
    this.firstMileTime = 10,
    this.lastMileMode = 0,
    this.lastMileTime = 10,
  });

  final double gc;
  final int top;
  final List<int> transitModes;
  final int transferMin;
  final int transferMax;
  final int firstMileMode;
  final int firstMileTime;
  final int lastMileMode;
  final int lastMileTime;

  PlanOptions copyWith({
    double? gc,
    int? top,
    List<int>? transitModes,
    int? transferMin,
    int? transferMax,
    int? firstMileMode,
    int? firstMileTime,
    int? lastMileMode,
    int? lastMileTime,
  }) {
    return PlanOptions(
      gc: gc ?? this.gc,
      top: top ?? this.top,
      transitModes: transitModes ?? this.transitModes,
      transferMin: transferMin ?? this.transferMin,
      transferMax: transferMax ?? this.transferMax,
      firstMileMode: firstMileMode ?? this.firstMileMode,
      firstMileTime: firstMileTime ?? this.firstMileTime,
      lastMileMode: lastMileMode ?? this.lastMileMode,
      lastMileTime: lastMileTime ?? this.lastMileTime,
    );
  }

  @override
  List<Object?> get props => [
    gc,
    top,
    transitModes,
    transferMin,
    transferMax,
    firstMileMode,
    firstMileTime,
    lastMileMode,
    lastMileTime,
  ];
}
