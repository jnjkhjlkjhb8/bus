import 'dart:convert';
import 'package:wheres_the_car/data/models/alert_models.dart';

class AlertDecoder {
  const AlertDecoder._();
  static const AlertDecoder instance = AlertDecoder._();

  /// TDX MQTT alert JSON → AlertViewModel. The [source] tags the row with the
  /// stream it arrived on. Every enriched field degrades to null when the feed
  /// omits it; only the message is guaranteed.
  AlertViewModel? decode(List<int> data, {AlertSource? source}) {
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      final msg =
          (json['data'] as String?) ??
          (json['Description'] as String?) ??
          (json['description'] as String?) ??
          (json['Message'] as String?) ??
          json.toString();
      return AlertViewModel(
        message: msg,
        level: _level(json),
        rawJson: json,
        title: (json['Title'] as String?) ?? (json['title'] as String?),
        time: _time(json),
        source: source,
      );
    } on Object catch (_) {
      return null;
    }
  }

  DateTime? _time(Map<String, dynamic> json) {
    final raw = (json['UpdateTime'] ?? json['PublishTime'])?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  AlertSeverity _level(Map<String, dynamic> json) {
    final status = (json['Status'] ?? json['status'] ?? '')
        .toString()
        .toLowerCase();
    if (status == 'red' || status == '3' || status.contains('中斷')) {
      return AlertSeverity.red;
    }
    return AlertSeverity.yellow;
  }
}
