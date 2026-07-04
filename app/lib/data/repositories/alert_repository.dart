import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/decoders/alert_decoder.dart';
import 'package:wheres_the_car/data/generated/alert.pb.dart';
import 'package:wheres_the_car/data/models/alert_models.dart';

class AlertRepository {
  const AlertRepository._();
  static const instance = AlertRepository._();

  /// Server-streaming: emits bus service alerts for [city] until cancelled.
  Stream<AlertViewModel> busNews(String city) =>
      _decoded(GrpcClient.instance.alert.busNews(Alert_Bus_Ask(city: city)));

  /// Server-streaming: emits metro service alerts for [system] until cancelled.
  ///
  /// [system] — metro operator code, e.g. `'TRTC'`.
  Stream<AlertViewModel> metroAlert(String system) => _decoded(
    GrpcClient.instance.alert.metroAlert(Alert_Metro_Ask(system: system)),
  );

  /// Server-streaming: emits TRA nationwide service alerts.
  Stream<AlertViewModel> traAlert() =>
      _decoded(GrpcClient.instance.alert.traAlert(Alert_Ask()));

  /// Server-streaming: emits THSR nationwide service alerts.
  Stream<AlertViewModel> thsrAlert() =>
      _decoded(GrpcClient.instance.alert.thsrAlert(Alert_Ask()));

  /// Decodes each proto envelope to a domain [AlertViewModel], dropping
  /// messages that fail to parse. Keeps the proto seam inside data/.
  Stream<AlertViewModel> _decoded(Stream<Alert_Msg> source) => source
      .map((msg) => AlertDecoder.instance.decode(msg.data))
      .where((vm) => vm != null)
      .cast<AlertViewModel>();
}
