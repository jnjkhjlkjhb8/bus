import 'package:grpc/grpc.dart';

/// Applies a default unary-call deadline to every gRPC request that doesn't
/// already carry one (F42), so a stalled backend can never hang a UI call
/// indefinitely. A call-site [CallOptions.timeout] (e.g. one built by
/// `FirebaseCallOptions.build`) always wins — this interceptor only fills
/// the gap when nothing was set.
class GrpcDeadlineInterceptor extends ClientInterceptor {
  GrpcDeadlineInterceptor({
    this.defaultTimeout = const Duration(seconds: 10),
  });

  final Duration defaultTimeout;

  @override
  ResponseFuture<R> interceptUnary<Q, R>(
    ClientMethod<Q, R> method,
    Q request,
    CallOptions options,
    ClientUnaryInvoker<Q, R> invoker,
  ) {
    final withDeadline = options.timeout != null
        ? options
        : CallOptions(timeout: defaultTimeout).mergedWith(options);
    return invoker(method, request, withDeadline);
  }
}
