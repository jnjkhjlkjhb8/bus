import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';

class HttpClient {
  HttpClient._();
  static final HttpClient instance = HttpClient._();
  static const _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
  late final Dio dio =
      Dio(
          BaseOptions(
            baseUrl: _baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
          ),
        )
        ..interceptors.add(
          PrettyDioLogger(
            requestBody: true,
            responseBody: false,
          ),
        )
        ..interceptors.add(
          InterceptorsWrapper(
            onError: (error, handler) {
              CrashReporter.record(error, error.stackTrace);
              handler.next(error);
            },
          ),
        );
}
