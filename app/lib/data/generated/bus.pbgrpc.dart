// This is a generated file - do not edit.
//
// Generated from bus.proto.

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

import 'bus.pb.dart' as $0;

export 'bus.pb.dart';

@$pb.GrpcServiceName('Bus_Route_Service')
class Bus_Route_ServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  Bus_Route_ServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.Resp_Bus_static> static(
    $0.Bus_Ask_Route request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$static, request, options: options);
  }

  $grpc.ResponseFuture<$0.Resp_Bus_daily_timetable> daily(
    $0.Bus_Ask_Route request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$daily, request, options: options);
  }

  $grpc.ResponseStream<$0.Resp_Bus_eta> eta(
    $0.Bus_Ask_Route request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$eta, $async.Stream.fromIterable([request]),
        options: options);
  }

  // method descriptors

  static final _$static =
      $grpc.ClientMethod<$0.Bus_Ask_Route, $0.Resp_Bus_static>(
          '/Bus_Route_Service/static',
          ($0.Bus_Ask_Route value) => value.writeToBuffer(),
          $0.Resp_Bus_static.fromBuffer);
  static final _$daily =
      $grpc.ClientMethod<$0.Bus_Ask_Route, $0.Resp_Bus_daily_timetable>(
          '/Bus_Route_Service/daily',
          ($0.Bus_Ask_Route value) => value.writeToBuffer(),
          $0.Resp_Bus_daily_timetable.fromBuffer);
  static final _$eta = $grpc.ClientMethod<$0.Bus_Ask_Route, $0.Resp_Bus_eta>(
      '/Bus_Route_Service/eta',
      ($0.Bus_Ask_Route value) => value.writeToBuffer(),
      $0.Resp_Bus_eta.fromBuffer);
}

@$pb.GrpcServiceName('Bus_Route_Service')
abstract class Bus_Route_ServiceBase extends $grpc.Service {
  $core.String get $name => 'Bus_Route_Service';

  Bus_Route_ServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.Bus_Ask_Route, $0.Resp_Bus_static>(
        'static',
        static_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Bus_Ask_Route.fromBuffer(value),
        ($0.Resp_Bus_static value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.Bus_Ask_Route, $0.Resp_Bus_daily_timetable>(
            'daily',
            daily_Pre,
            false,
            false,
            ($core.List<$core.int> value) => $0.Bus_Ask_Route.fromBuffer(value),
            ($0.Resp_Bus_daily_timetable value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Bus_Ask_Route, $0.Resp_Bus_eta>(
        'eta',
        eta_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.Bus_Ask_Route.fromBuffer(value),
        ($0.Resp_Bus_eta value) => value.writeToBuffer()));
  }

  $async.Future<$0.Resp_Bus_static> static_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Bus_Ask_Route> $request) async {
    return static($call, await $request);
  }

  $async.Future<$0.Resp_Bus_static> static(
      $grpc.ServiceCall call, $0.Bus_Ask_Route request);

  $async.Future<$0.Resp_Bus_daily_timetable> daily_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Bus_Ask_Route> $request) async {
    return daily($call, await $request);
  }

  $async.Future<$0.Resp_Bus_daily_timetable> daily(
      $grpc.ServiceCall call, $0.Bus_Ask_Route request);

  $async.Stream<$0.Resp_Bus_eta> eta_Pre($grpc.ServiceCall $call,
      $async.Future<$0.Bus_Ask_Route> $request) async* {
    yield* eta($call, await $request);
  }

  $async.Stream<$0.Resp_Bus_eta> eta(
      $grpc.ServiceCall call, $0.Bus_Ask_Route request);
}

@$pb.GrpcServiceName('Bus_Station_Service')
class Bus_Station_ServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  Bus_Station_ServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseStream<$0.Resp_Bus_eta> eta(
    $0.Bus_Ask_Route request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$eta, $async.Stream.fromIterable([request]),
        options: options);
  }

  $grpc.ResponseFuture<$0.Bus_StationGroup> group(
    $0.Bus_Ask_Route request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$group, request, options: options);
  }

  // method descriptors

  static final _$eta = $grpc.ClientMethod<$0.Bus_Ask_Route, $0.Resp_Bus_eta>(
      '/Bus_Station_Service/eta',
      ($0.Bus_Ask_Route value) => value.writeToBuffer(),
      $0.Resp_Bus_eta.fromBuffer);
  static final _$group =
      $grpc.ClientMethod<$0.Bus_Ask_Route, $0.Bus_StationGroup>(
          '/Bus_Station_Service/group',
          ($0.Bus_Ask_Route value) => value.writeToBuffer(),
          $0.Bus_StationGroup.fromBuffer);
}

@$pb.GrpcServiceName('Bus_Station_Service')
abstract class Bus_Station_ServiceBase extends $grpc.Service {
  $core.String get $name => 'Bus_Station_Service';

  Bus_Station_ServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.Bus_Ask_Route, $0.Resp_Bus_eta>(
        'eta',
        eta_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.Bus_Ask_Route.fromBuffer(value),
        ($0.Resp_Bus_eta value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Bus_Ask_Route, $0.Bus_StationGroup>(
        'group',
        group_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Bus_Ask_Route.fromBuffer(value),
        ($0.Bus_StationGroup value) => value.writeToBuffer()));
  }

  $async.Stream<$0.Resp_Bus_eta> eta_Pre($grpc.ServiceCall $call,
      $async.Future<$0.Bus_Ask_Route> $request) async* {
    yield* eta($call, await $request);
  }

  $async.Stream<$0.Resp_Bus_eta> eta(
      $grpc.ServiceCall call, $0.Bus_Ask_Route request);

  $async.Future<$0.Bus_StationGroup> group_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Bus_Ask_Route> $request) async {
    return group($call, await $request);
  }

  $async.Future<$0.Bus_StationGroup> group(
      $grpc.ServiceCall call, $0.Bus_Ask_Route request);
}
