import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:grpc/grpc.dart';
import 'package:wheres_the_car/core/grpc/grpc_error_interceptor.dart';
import 'package:wheres_the_car/data/generated/alert.pbgrpc.dart';
import 'package:wheres_the_car/data/generated/bike.pbgrpc.dart';
import 'package:wheres_the_car/data/generated/bus.pbgrpc.dart';
import 'package:wheres_the_car/data/generated/firebase.pbgrpc.dart';
import 'package:wheres_the_car/data/generated/maas.pbgrpc.dart';
import 'package:wheres_the_car/data/generated/mrt.pbgrpc.dart';
import 'package:wheres_the_car/data/generated/near.pbgrpc.dart';
import 'package:wheres_the_car/data/generated/thsr.pbgrpc.dart';
import 'package:wheres_the_car/data/generated/tra.pbgrpc.dart';

class GrpcClient {
  GrpcClient._();
  static final GrpcClient instance = GrpcClient._();
  static const _host = String.fromEnvironment(
    'GRPC_HOST',
    defaultValue: '127.0.0.1',
  );
  static const _port = int.fromEnvironment('GRPC_PORT', defaultValue: 50051);
  static const _tls = bool.fromEnvironment('GRPC_TLS');
  static Uint8List? _caBytes;

  /// Loads the pinned self-signed CA before the channel is first built.
  /// Must be awaited during startup when [_tls] is true. The cert must carry
  /// the target IP in its SAN, or the TLS handshake fails on hostname check.
  static Future<void> init() async {
    if (!_tls) return;
    _caBytes = (await rootBundle.load('assets/grpc.crt')).buffer.asUint8List();
  }

  late final ClientChannel _channel = ClientChannel(
    _host,
    port: _port,
    options: ChannelOptions(
      credentials: _tls
          ? ChannelCredentials.secure(certificates: _caBytes)
          : const ChannelCredentials.insecure(),
    ),
  );

  static final List<ClientInterceptor> _interceptors = [
    GrpcErrorInterceptor(),
  ];

  late final Bus_Route_ServiceClient busRoute = Bus_Route_ServiceClient(
    _channel,
    interceptors: _interceptors,
  );
  late final Bus_Station_ServiceClient busStation = Bus_Station_ServiceClient(
    _channel,
    interceptors: _interceptors,
  );
  late final Bike_ServiceClient bike = Bike_ServiceClient(
    _channel,
    interceptors: _interceptors,
  );
  late final Mrt_ServiceClient mrt = Mrt_ServiceClient(
    _channel,
    interceptors: _interceptors,
  );
  late final TRA_station_serviceClient traStation = TRA_station_serviceClient(
    _channel,
    interceptors: _interceptors,
  );
  late final TRA_timetable_serviceClient traTimetable =
      TRA_timetable_serviceClient(_channel, interceptors: _interceptors);
  late final TRA_Detain_serviceClient traDetain = TRA_Detain_serviceClient(
    _channel,
    interceptors: _interceptors,
  );
  late final Thsr_timetable_serviceClient thsr = Thsr_timetable_serviceClient(
    _channel,
    interceptors: _interceptors,
  );
  late final Thsr_Detain_serviceClient thsrDetain = Thsr_Detain_serviceClient(
    _channel,
    interceptors: _interceptors,
  );
  late final Alert_ServiceClient alert = Alert_ServiceClient(
    _channel,
    interceptors: _interceptors,
  );
  late final Near_Station_ServiceClient near = Near_Station_ServiceClient(
    _channel,
    interceptors: _interceptors,
  );
  late final MaasServiceClient maas = MaasServiceClient(
    _channel,
    interceptors: _interceptors,
  );
  late final Firebase_ServiceClient firebase = Firebase_ServiceClient(
    _channel,
    interceptors: _interceptors,
  );

  Future<void> shutdown() => _channel.shutdown();
}
