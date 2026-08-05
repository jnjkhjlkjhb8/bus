import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:grpc/grpc.dart';
import 'package:wheres_the_bus/core/grpc/grpc_compression_interceptor.dart';
import 'package:wheres_the_bus/core/grpc/grpc_deadline_interceptor.dart';
import 'package:wheres_the_bus/core/grpc/grpc_error_interceptor.dart';
import 'package:wheres_the_bus/core/lifecycle/app_foreground.dart';
import 'package:wheres_the_bus/data/generated/alert.pbgrpc.dart';
import 'package:wheres_the_bus/data/generated/bike.pbgrpc.dart';
import 'package:wheres_the_bus/data/generated/bus.pbgrpc.dart';
import 'package:wheres_the_bus/data/generated/feedback.pbgrpc.dart';
import 'package:wheres_the_bus/data/generated/firebase.pbgrpc.dart';
import 'package:wheres_the_bus/data/generated/maas.pbgrpc.dart';
import 'package:wheres_the_bus/data/generated/mrt.pbgrpc.dart';
import 'package:wheres_the_bus/data/generated/near.pbgrpc.dart';
import 'package:wheres_the_bus/data/generated/thsr.pbgrpc.dart';
import 'package:wheres_the_bus/data/generated/tra.pbgrpc.dart';

class GrpcClient {
  GrpcClient._();
  static final GrpcClient instance = GrpcClient._();
  static const _host = String.fromEnvironment(
    'GRPC_HOST',
    defaultValue: '127.0.0.1',
  );
  static const _port = int.fromEnvironment('GRPC_PORT', defaultValue: 50051);
  static const _tls = bool.fromEnvironment('GRPC_TLS');
  // No defaultValue on purpose: an unset APP_ENV must land in the strict
  // branch of validateConfig below, not silently masquerade as 'dev'.
  static const _appEnv = String.fromEnvironment('APP_ENV');
  static bool _configValidated = false;

  /// Rejects a channel config that would silently fall back to loopback or
  /// unencrypted transport in a deployed environment (F43). Strict unless
  /// the build explicitly opts into a local flavor: only the exact values
  /// `dev` and `test` relax the guard. Everything else — `staging`,
  /// `production`, an unset APP_ENV, or a misspelling like `prod` /
  /// `Production` — must have a real host and TLS enabled, or this throws.
  /// Fail closed: a typo in the flavor file can tighten validation but
  /// never bypass it.
  static void validateConfig({
    required String appEnv,
    required String host,
    required bool tls,
  }) {
    final isLocalEnv = appEnv == 'dev' || appEnv == 'test';
    if (isLocalEnv) return;
    if (host.isEmpty || host == 'localhost' || host == '127.0.0.1') {
      throw StateError(
        'GRPC_HOST must be a non-loopback host in the "$appEnv" environment',
      );
    }
    if (!tls) {
      throw StateError('GRPC_TLS must be true in the "$appEnv" environment');
    }
  }

  /// Validates the compiled channel config. Must complete before the channel
  /// is first built.
  ///
  /// A failure here must surface to the caller rather than be swallowed
  /// (F58): a swallowed validation failure would leave a build that never
  /// checked its own host/TLS config free to open a channel anyway. The
  /// `_buildChannel` guard below fails closed on that.
  static Future<void> init() async {
    validateConfig(appEnv: _appEnv, host: _host, tls: _tls);
    _configValidated = true;
    _observeForeground();
    warmConnection();
  }

  static bool _observingForeground = false;

  static void _observeForeground() {
    if (_observingForeground) return;
    _observingForeground = true;
    AppForeground.value.addListener(handleForeground);
  }

  /// Recycles the channel the moment the app comes back on screen.
  ///
  /// A suspended app's transport is usually dead but still looks `ready`, and
  /// keepalive (FDPL-49) only proves that a ping interval later — a whole
  /// screen of stale content in the meantime. Resuming is the one instant when
  /// nothing is subscribed (live feeds are foreground-gated) and the rider is
  /// about to look, so dropping the connection and dialing again costs a
  /// handshake and buys a fresh frame (FDPL-50).
  ///
  /// Registered before any `ResilientSubscription` — `init` runs during
  /// bootstrap, blocs come later — so the channel is already replaced by the
  /// time the feeds re-listen against it.
  @visibleForTesting
  static void handleForeground() {
    if (!AppForeground.value.value) return;
    instance.recycle();
    warmConnection();
  }

  /// Opens the connection now rather than on the first RPC.
  ///
  /// The channel is lazy, so without this the TCP connect and TLS handshake
  /// land on home's first nearby query — which goes out ~120 ms after launch
  /// and is the metric the whole startup path is measured by. Failure is
  /// ignored on purpose: offline at launch is normal, and the next real RPC
  /// reconnects on its own.
  static void warmConnection() {
    instance._channel.getConnection().ignore();
  }

  ClientChannel? _channelInstance;

  /// Built on demand rather than bound once. A channel that has been shut down
  /// is terminally shut down — every later RPC on it throws
  /// `Channel shutting down.` — so a single [shutdown], or a resume-time
  /// reconnect, used to brick every client for the rest of the process
  /// (FDPL-51). The service clients below are getters for the same reason:
  /// each RPC binds to whatever channel is current.
  ClientChannel get _channel => _channelInstance ??= _buildChannel();

  /// Drops the current channel so the next RPC builds a fresh one. In-flight
  /// calls are terminated rather than drained: this runs when the transport
  /// underneath is already known to be gone.
  void recycle() {
    final old = _channelInstance;
    _channelInstance = null;
    old?.terminate().ignore();
  }

  /// How many channels this client has built. Lets a test tell a recycle from
  /// a channel that was merely reused.
  @visibleForTesting
  int channelGeneration = 0;

  ClientChannel _buildChannel() {
    channelGeneration++;
    if (_tls && !_configValidated) {
      throw StateError(
        'GrpcClient.init() must complete successfully before the channel '
        'is used when GRPC_TLS is enabled',
      );
    }
    return ClientChannel(
      _host,
      port: _port,
      options: ChannelOptions(
        // The router is reached through a Cloudflare Tunnel hostname, so the
        // presented chain is a publicly trusted one that rotates on
        // Cloudflare's schedule. Certificate pinning against the router's own
        // self-signed leaf (which cloudflared still terminates on the origin
        // hop) would break at the first rotation, so trust resolution is left
        // to the platform store and the default hostname check.
        credentials: _tls
            ? const ChannelCredentials.secure()
            : const ChannelCredentials.insecure(),
        // Without pings, grpc-dart never notices a transport the OS killed
        // under a suspended app: the HTTP/2 connection stays `ready` and a
        // stream opened on it hangs forever, because only unary calls carry a
        // deadline (see [GrpcDeadlineInterceptor]). The stream then produces
        // neither data nor error, so [ResilientSubscription] has nothing to
        // reconnect on and the whole live chain goes silent (FDPL-49). A ping
        // that goes unanswered tears the transport down instead, which surfaces
        // as the stream error the retry path is built for.
        //
        // `permitWithoutCalls` stays false: streams are dropped while
        // backgrounded, and pinging an idle channel would be pure radio cost.
        keepAlive: const ClientKeepAliveOptions(
          pingInterval: Duration(seconds: 20),
          timeout: Duration(seconds: 10),
        ),
        // A connect attempt against an unreachable host must fail on a
        // human timescale rather than sit on the OS default.
        connectTimeout: const Duration(seconds: 10),
        // Advertises `grpc-accept-encoding: gzip,identity` and decodes gzipped
        // responses. Identity stays listed so a router without the compressor
        // registered still answers. [GrpcCompressionInterceptor] is the other
        // half — see there for why advertising alone would do nothing.
        codecRegistry: CodecRegistry(
          codecs: const [GzipCodec(), IdentityCodec()],
        ),
      ),
    );
  }

  static final List<ClientInterceptor> _interceptors = [
    GrpcCompressionInterceptor(),
    GrpcDeadlineInterceptor(),
    GrpcErrorInterceptor(),
  ];

  Bus_Route_ServiceClient get busRoute =>
      Bus_Route_ServiceClient(_channel, interceptors: _interceptors);
  Bus_Station_ServiceClient get busStation =>
      Bus_Station_ServiceClient(_channel, interceptors: _interceptors);
  Bike_ServiceClient get bike =>
      Bike_ServiceClient(_channel, interceptors: _interceptors);
  Mrt_ServiceClient get mrt =>
      Mrt_ServiceClient(_channel, interceptors: _interceptors);
  TRA_timetable_serviceClient get traTimetable =>
      TRA_timetable_serviceClient(_channel, interceptors: _interceptors);
  TRA_Detain_serviceClient get traDetain =>
      TRA_Detain_serviceClient(_channel, interceptors: _interceptors);
  Thsr_timetable_serviceClient get thsr =>
      Thsr_timetable_serviceClient(_channel, interceptors: _interceptors);
  Thsr_Detain_serviceClient get thsrDetain =>
      Thsr_Detain_serviceClient(_channel, interceptors: _interceptors);
  Alert_ServiceClient get alert =>
      Alert_ServiceClient(_channel, interceptors: _interceptors);
  Near_Station_ServiceClient get near =>
      Near_Station_ServiceClient(_channel, interceptors: _interceptors);
  MaasServiceClient get maas =>
      MaasServiceClient(_channel, interceptors: _interceptors);
  Firebase_ServiceClient get firebase =>
      Firebase_ServiceClient(_channel, interceptors: _interceptors);
  Feedback_ServiceClient get feedback =>
      Feedback_ServiceClient(_channel, interceptors: _interceptors);

  Future<void> shutdown() async {
    final old = _channelInstance;
    _channelInstance = null;
    await old?.shutdown();
  }
}
