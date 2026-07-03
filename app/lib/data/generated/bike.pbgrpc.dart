// This is a generated file - do not edit.
//
// Generated from bike.proto.

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

import 'bike.pb.dart' as $0;

export 'bike.pb.dart';

@$pb.GrpcServiceName('Bike_Service')
class Bike_ServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  Bike_ServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.Bike_static> static(
    $0.Bike_request request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$static, request, options: options);
  }

  $grpc.ResponseStream<$0.Resp_Bike_eta> eta(
    $0.Bike_request request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$eta, $async.Stream.fromIterable([request]),
        options: options);
  }

  // method descriptors

  static final _$static = $grpc.ClientMethod<$0.Bike_request, $0.Bike_static>(
      '/Bike_Service/static',
      ($0.Bike_request value) => value.writeToBuffer(),
      $0.Bike_static.fromBuffer);
  static final _$eta = $grpc.ClientMethod<$0.Bike_request, $0.Resp_Bike_eta>(
      '/Bike_Service/eta',
      ($0.Bike_request value) => value.writeToBuffer(),
      $0.Resp_Bike_eta.fromBuffer);
}

@$pb.GrpcServiceName('Bike_Service')
abstract class Bike_ServiceBase extends $grpc.Service {
  $core.String get $name => 'Bike_Service';

  Bike_ServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.Bike_request, $0.Bike_static>(
        'static',
        static_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Bike_request.fromBuffer(value),
        ($0.Bike_static value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Bike_request, $0.Resp_Bike_eta>(
        'eta',
        eta_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.Bike_request.fromBuffer(value),
        ($0.Resp_Bike_eta value) => value.writeToBuffer()));
  }

  $async.Future<$0.Bike_static> static_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Bike_request> $request) async {
    return static($call, await $request);
  }

  $async.Future<$0.Bike_static> static(
      $grpc.ServiceCall call, $0.Bike_request request);

  $async.Stream<$0.Resp_Bike_eta> eta_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Bike_request> $request) async* {
    yield* eta($call, await $request);
  }

  $async.Stream<$0.Resp_Bike_eta> eta(
      $grpc.ServiceCall call, $0.Bike_request request);
}
