import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/grpc/grpc_client.dart';

void main() {
  group('GrpcClient.validateConfig', () {
    test('allows loopback + insecure on dev', () {
      expect(
        () => GrpcClient.validateConfig(
          appEnv: 'dev',
          host: '127.0.0.1',
          tls: false,
        ),
        returnsNormally,
      );
    });

    test('rejects loopback host on production', () {
      expect(
        () => GrpcClient.validateConfig(
          appEnv: 'production',
          host: '127.0.0.1',
          tls: true,
        ),
        throwsStateError,
      );
    });

    test('rejects empty host on staging', () {
      expect(
        () => GrpcClient.validateConfig(
          appEnv: 'staging',
          host: '',
          tls: true,
        ),
        throwsStateError,
      );
    });

    test('rejects insecure TLS on production even with a real host', () {
      expect(
        () => GrpcClient.validateConfig(
          appEnv: 'production',
          host: 'api.example.com',
          tls: false,
        ),
        throwsStateError,
      );
    });

    test('accepts a real host with TLS on staging', () {
      expect(
        () => GrpcClient.validateConfig(
          appEnv: 'staging',
          host: 'staging.example.com',
          tls: true,
        ),
        returnsNormally,
      );
    });
  });
}
