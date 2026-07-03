import 'dart:convert';
import 'package:wheres_the_car/data/models/alert_models.dart';

class AlertDecoder {
  const AlertDecoder._();
  static const AlertDecoder instance = AlertDecoder._();

  /// TDX MQTT alert JSON → AlertViewModel.
  AlertViewModel? decode(List<int> data) {
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      final msg =
          (json['data'] as String?) ??
          (json['Message'] as String?) ??
          json.toString();
      return AlertViewModel(
        message: msg,
        level: _level(json),
        rawJson: json,
      );
    } on Object catch (_) {
      return null;
    }
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
