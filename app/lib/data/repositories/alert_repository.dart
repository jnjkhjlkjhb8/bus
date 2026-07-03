import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/generated/alert.pb.dart';

class AlertRepository {
  const AlertRepository._();
  static const instance = AlertRepository._();

  /// Server-streaming: emits bus service alerts for [city] until cancelled.
  Stream<Alert_Msg> busNews(String city) =>
      GrpcClient.instance.alert.busNews(Alert_Bus_Ask(city: city));

  /// Server-streaming: emits metro service alerts for [system] until cancelled.
  ///
  /// [system] — metro operator code, e.g. `'TRTC'`.
  Stream<Alert_Msg> metroAlert(String system) =>
      GrpcClient.instance.alert.metroAlert(Alert_Metro_Ask(system: system));

  /// Server-streaming: emits TRA nationwide service alerts.
  Stream<Alert_Msg> traAlert() =>
      GrpcClient.instance.alert.traAlert(Alert_Ask());

  /// Server-streaming: emits THSR nationwide service alerts.
  Stream<Alert_Msg> thsrAlert() =>
      GrpcClient.instance.alert.thsrAlert(Alert_Ask());
}
