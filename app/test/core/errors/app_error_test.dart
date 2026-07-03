import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';

void main() {
  test('grpc unavailable maps to OfflineError', () {
    expect(AppError.from(const GrpcError.unavailable()), isA<OfflineError>());
  });

  test('grpc deadlineExceeded maps to TimeoutError', () {
    expect(
      AppError.from(const GrpcError.deadlineExceeded()),
      isA<TimeoutError>(),
    );
  });

  test('grpc notFound maps to NotFoundError', () {
    expect(AppError.from(const GrpcError.notFound()), isA<NotFoundError>());
  });

  test('other grpc codes map to ServerError with code', () {
    final e = AppError.from(const GrpcError.internal());
    expect(e, isA<ServerError>());
    expect((e as ServerError).code, StatusCode.internal);
  });

  test('arbitrary exception maps to UnknownError', () {
    expect(AppError.from(StateError('x')), isA<UnknownError>());
  });

  test('AppError passes through unchanged', () {
    const offline = OfflineError();
    expect(AppError.from(offline), same(offline));
  });

  test('every error has copy', () {
    for (final e in [
      const OfflineError(),
      const TimeoutError(),
      const NotFoundError(),
      const ServerError(13),
      const UnknownError(),
    ]) {
      expect(e.title, isNotEmpty);
      expect(e.hint, isNotEmpty);
    }
  });
}
