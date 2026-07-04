import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/grpc/resilient_stream.dart';

/// A single live-data subscription a bloc can own with one field. Wraps
/// ResilientSubscription (retry/backoff, terminal-error handling, crash
/// reporting) behind a calm façade: give it a source and an onData callback;
/// optionally observe failure/recovery. Cancel via [cancel].
class LiveData<T> {
  LiveData.watch({
    required Stream<T> Function() source,
    required void Function(T data) onData,
    void Function(AppError error)? onFailure,
    void Function()? onRecovered,
  }) : _sub = ResilientSubscription<T>(
         source: source,
         onData: onData,
         onFailure: onFailure ?? _noop,
         onRecovered: onRecovered,
       );

  final ResilientSubscription<T> _sub;

  static void _noop(AppError _) {}

  Future<void> cancel() => _sub.cancel();
}
