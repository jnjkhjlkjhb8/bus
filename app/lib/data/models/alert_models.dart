import 'package:equatable/equatable.dart';

enum AlertSeverity { red, yellow, green }

/// Which transit domain an alert came from. The subscription layer knows this;
/// carrying it to the UI lets a row show which system is affected at a glance.
enum AlertSourceKind { metro, bus, tra, thsr }

/// Origin of an alert: the domain plus the operator/region code the stream was
/// opened with (e.g. metro `TRTC`, bus `Taipei`). Rail kinds carry an empty
/// code since their streams are nationwide.
class AlertSource extends Equatable {
  const AlertSource(this.kind, [this.code = '']);

  final AlertSourceKind kind;
  final String code;

  @override
  List<Object?> get props => [kind, code];
}

class AlertViewModel extends Equatable {
  const AlertViewModel({
    required this.message,
    required this.level,
    required this.rawJson,
    this.title,
    this.time,
    this.source,
  });

  final String message;
  final AlertSeverity level;
  final Map<String, dynamic> rawJson;

  /// Optional headline distinct from [message]; may be null.
  final String? title;

  /// When the alert was published/updated, if the feed provided it.
  final DateTime? time;

  /// Which system and operator the alert came from, if known.
  final AlertSource? source;

  // [message] stays the sole identity: it is the dedup/read/dismiss key, so
  // enriching a row with title/time/source must not change equality.
  @override
  List<Object?> get props => [message, level];
}
