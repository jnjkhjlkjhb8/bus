// This is a generated file - do not edit.
//
// Generated from mrt.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'mrt.pb.dart' as $0;

export 'mrt.pb.dart';

@$pb.GrpcServiceName('Mrt_Service')
class Mrt_ServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  Mrt_ServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseStream<$0.Resp_Mrt_eta> eta(
    $0.Ask_mrt request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$eta, $async.Stream.fromIterable([request]),
        options: options);
  }

  // method descriptors

  static final _$eta = $grpc.ClientMethod<$0.Ask_mrt, $0.Resp_Mrt_eta>(
      '/Mrt_Service/eta',
      ($0.Ask_mrt value) => value.writeToBuffer(),
      $0.Resp_Mrt_eta.fromBuffer);
}

@$pb.GrpcServiceName('Mrt_Service')
abstract class Mrt_ServiceBase extends $grpc.Service {
  $core.String get $name => 'Mrt_Service';

  Mrt_ServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.Ask_mrt, $0.Resp_Mrt_eta>(
        'eta',
        eta_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.Ask_mrt.fromBuffer(value),
        ($0.Resp_Mrt_eta value) => value.writeToBuffer()));
  }

  $async.Stream<$0.Resp_Mrt_eta> eta_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Ask_mrt> $request) async* {
    yield* eta($call, await $request);
  }

  $async.Stream<$0.Resp_Mrt_eta> eta(
      $grpc.ServiceCall call, $0.Ask_mrt request);
}
