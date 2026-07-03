// This is a generated file - do not edit.
//
// Generated from maas.proto.

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

import 'maas.pb.dart' as $0;

export 'maas.pb.dart';

@$pb.GrpcServiceName('MaasService')
class MaasServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  MaasServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.MaasPlanResponse> plan(
    $0.MaasPlanRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$plan, request, options: options);
  }

  // method descriptors

  static final _$plan =
      $grpc.ClientMethod<$0.MaasPlanRequest, $0.MaasPlanResponse>(
          '/MaasService/plan',
          ($0.MaasPlanRequest value) => value.writeToBuffer(),
          $0.MaasPlanResponse.fromBuffer);
}

@$pb.GrpcServiceName('MaasService')
abstract class MaasServiceBase extends $grpc.Service {
  $core.String get $name => 'MaasService';

  MaasServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.MaasPlanRequest, $0.MaasPlanResponse>(
        'plan',
        plan_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.MaasPlanRequest.fromBuffer(value),
        ($0.MaasPlanResponse value) => value.writeToBuffer()));
  }

  $async.Future<$0.MaasPlanResponse> plan_Pre($grpc.ServiceCall $call,
      $async.Future<$0.MaasPlanRequest> $request) async {
    return plan($call, await $request);
  }

  $async.Future<$0.MaasPlanResponse> plan(
      $grpc.ServiceCall call, $0.MaasPlanRequest request);
}
