import 'package:grpc/grpc.dart';

/// Marks every request as gzip-encoded, which is what makes the router gzip its
/// *response*: grpc-go answers in whatever encoding the request arrived in, so
/// advertising `grpc-accept-encoding` alone (what [CodecRegistry] does) is not
/// enough.
///
/// The payloads this pays for are the static ones — a 公路客運 route's
/// `Bus_subroute` carries verbatim TDX fare JSON whose repeated keys compress
/// roughly 25x. Requests themselves are tens of bytes; gzipping them is the
/// price of the header, not a saving.
///
/// Streams are covered too, for the response side: an ETA or alert frame is the
/// same repetitive proto every tick. Every stream here is server-streaming
/// except `Near_Station_Service.near`, whose client half sends a position ping
/// small enough that gzip framing roughly doubles it — some tens of bytes per
/// ping, against a `resp_near` payload worth compressing on the way back.
class GrpcCompressionInterceptor extends ClientInterceptor {
  GrpcCompressionInterceptor();

  static const _gzip = GzipCodec();

  // A call site that picked its own codec wins, same as the deadline
  // interceptor: `mergedWith` takes the argument's compression first.
  CallOptions _gzipped(CallOptions options) =>
      CallOptions(compression: _gzip).mergedWith(options);

  @override
  ResponseFuture<R> interceptUnary<Q, R>(
    ClientMethod<Q, R> method,
    Q request,
    CallOptions options,
    ClientUnaryInvoker<Q, R> invoker,
  ) => invoker(method, request, _gzipped(options));

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
    ClientMethod<Q, R> method,
    Stream<Q> requests,
    CallOptions options,
    ClientStreamingInvoker<Q, R> invoker,
  ) => invoker(method, requests, _gzipped(options));
}
