// This is a generated file - do not edit.
//
// Generated from near.proto.

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

import 'near.pb.dart' as $0;

export 'near.pb.dart';

@$pb.GrpcServiceName('Near_Station_Service')
class Near_Station_ServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  Near_Station_ServiceClient(super.channel,
      {super.options, super.interceptors});

  $grpc.ResponseStream<$0.resp_near> near(
    $async.Stream<$0.Ask_Near> request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$near, request, options: options);
  }

  // method descriptors

  static final _$near = $grpc.ClientMethod<$0.Ask_Near, $0.resp_near>(
      '/Near_Station_Service/near',
      ($0.Ask_Near value) => value.writeToBuffer(),
      $0.resp_near.fromBuffer);
}

@$pb.GrpcServiceName('Near_Station_Service')
abstract class Near_Station_ServiceBase extends $grpc.Service {
  $core.String get $name => 'Near_Station_Service';

  Near_Station_ServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.Ask_Near, $0.resp_near>(
        'near',
        near,
        true,
        true,
        ($core.List<$core.int> value) => $0.Ask_Near.fromBuffer(value),
        ($0.resp_near value) => value.writeToBuffer()));
  }

  $async.Stream<$0.resp_near> near(
      $grpc.ServiceCall call, $async.Stream<$0.Ask_Near> request);
}
