import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/decoders/alert_decoder.dart';
import 'package:wheres_the_car/data/generated/alert.pbgrpc.dart';
import 'package:wheres_the_car/data/models/alert_models.dart';
import 'package:wheres_the_car/data/repositories/settings_repository.dart';

class AlertRepository {
  AlertRepository({Alert_ServiceClient? client, SettingsRepository? settings})
    : _client = client,
      _settings = settings ?? SettingsRepository.instance;

  static final AlertRepository instance = AlertRepository();

  Alert_ServiceClient? _client;
  Alert_ServiceClient get _grpc => _client ??= GrpcClient.instance.alert;

  final SettingsRepository _settings;

  /// Alert message keys the user has already read, persisted across restarts.
  Set<String> readAlerts() => _settings.readAlerts();

  Future<void> persistReadAlerts(Set<String> read) =>
      _settings.setReadAlerts(read);

  /// Server-streaming: emits bus service alerts for [city] until cancelled.
  Stream<AlertViewModel> busNews(String city) => _decoded(
    _grpc.busNews(Alert_Bus_Ask(city: city)),
    AlertSource(AlertSourceKind.bus, city),
  );

  /// Server-streaming: emits metro service alerts for [system] until cancelled.
  ///
  /// [system] — metro operator code, e.g. `'TRTC'`.
  Stream<AlertViewModel> metroAlert(String system) => _decoded(
    _grpc.metroAlert(Alert_Metro_Ask(system: system)),
    AlertSource(AlertSourceKind.metro, system),
  );

  /// Server-streaming: emits TRA nationwide service alerts.
  Stream<AlertViewModel> traAlert() => _decoded(
    _grpc.traAlert(Alert_Ask()),
    const AlertSource(AlertSourceKind.tra),
  );

  /// Server-streaming: emits THSR nationwide service alerts.
  Stream<AlertViewModel> thsrAlert() => _decoded(
    _grpc.thsrAlert(Alert_Ask()),
    const AlertSource(AlertSourceKind.thsr),
  );

  /// Decodes each proto envelope to a domain [AlertViewModel], dropping
  /// messages that fail to parse. Keeps the proto seam inside data/.
  Stream<AlertViewModel> _decoded(Stream<Alert_Msg> source, AlertSource from) =>
      source
          .map((msg) => AlertDecoder.instance.decode(msg.data, source: from))
          .where((vm) => vm != null)
          .cast<AlertViewModel>();
}
