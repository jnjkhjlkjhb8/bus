// This is a generated file - do not edit.
//
// Generated from tra.proto.

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

import 'tra.pb.dart' as $0;

export 'tra.pb.dart';

@$pb.GrpcServiceName('TRA_timetable_service')
class TRA_timetable_serviceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  TRA_timetable_serviceClient(super.channel,
      {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.tra_timetables> timetable(
    $0.ask_route request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$timetable, request, options: options);
  }

  $grpc.ResponseFuture<$0.TraFareItem> fare(
    $0.ask_staiton request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$fare, request, options: options);
  }

  $grpc.ResponseStream<$0.Resp_tra_delay> delay(
    $0.ask_route request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$delay, $async.Stream.fromIterable([request]),
        options: options);
  }

  // method descriptors

  static final _$timetable =
      $grpc.ClientMethod<$0.ask_route, $0.tra_timetables>(
          '/TRA_timetable_service/timetable',
          ($0.ask_route value) => value.writeToBuffer(),
          $0.tra_timetables.fromBuffer);
  static final _$fare = $grpc.ClientMethod<$0.ask_staiton, $0.TraFareItem>(
      '/TRA_timetable_service/fare',
      ($0.ask_staiton value) => value.writeToBuffer(),
      $0.TraFareItem.fromBuffer);
  static final _$delay = $grpc.ClientMethod<$0.ask_route, $0.Resp_tra_delay>(
      '/TRA_timetable_service/delay',
      ($0.ask_route value) => value.writeToBuffer(),
      $0.Resp_tra_delay.fromBuffer);
}

@$pb.GrpcServiceName('TRA_timetable_service')
abstract class TRA_timetable_serviceServiceBase extends $grpc.Service {
  $core.String get $name => 'TRA_timetable_service';

  TRA_timetable_serviceServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.ask_route, $0.tra_timetables>(
        'timetable',
        timetable_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ask_route.fromBuffer(value),
        ($0.tra_timetables value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ask_staiton, $0.TraFareItem>(
        'fare',
        fare_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ask_staiton.fromBuffer(value),
        ($0.TraFareItem value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ask_route, $0.Resp_tra_delay>(
        'delay',
        delay_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.ask_route.fromBuffer(value),
        ($0.Resp_tra_delay value) => value.writeToBuffer()));
  }

  $async.Future<$0.tra_timetables> timetable_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.ask_route> $request) async {
    return timetable($call, await $request);
  }

  $async.Future<$0.tra_timetables> timetable(
      $grpc.ServiceCall call, $0.ask_route request);

  $async.Future<$0.TraFareItem> fare_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.ask_staiton> $request) async {
    return fare($call, await $request);
  }

  $async.Future<$0.TraFareItem> fare(
      $grpc.ServiceCall call, $0.ask_staiton request);

  $async.Stream<$0.Resp_tra_delay> delay_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.ask_route> $request) async* {
    yield* delay($call, await $request);
  }

  $async.Stream<$0.Resp_tra_delay> delay(
      $grpc.ServiceCall call, $0.ask_route request);
}

@$pb.GrpcServiceName('TRA_Detain_service')
class TRA_Detain_serviceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  TRA_Detain_serviceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.tra_stoptimes> stops(
    $0.ask_detain request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$stops, request, options: options);
  }

  $grpc.ResponseStream<$0.Resp_tra_delay> delay(
    $0.ask_detain request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$delay, $async.Stream.fromIterable([request]),
        options: options);
  }

  // method descriptors

  static final _$stops = $grpc.ClientMethod<$0.ask_detain, $0.tra_stoptimes>(
      '/TRA_Detain_service/stops',
      ($0.ask_detain value) => value.writeToBuffer(),
      $0.tra_stoptimes.fromBuffer);
  static final _$delay = $grpc.ClientMethod<$0.ask_detain, $0.Resp_tra_delay>(
      '/TRA_Detain_service/delay',
      ($0.ask_detain value) => value.writeToBuffer(),
      $0.Resp_tra_delay.fromBuffer);
}

@$pb.GrpcServiceName('TRA_Detain_service')
abstract class TRA_Detain_serviceServiceBase extends $grpc.Service {
  $core.String get $name => 'TRA_Detain_service';

  TRA_Detain_serviceServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.ask_detain, $0.tra_stoptimes>(
        'stops',
        stops_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ask_detain.fromBuffer(value),
        ($0.tra_stoptimes value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ask_detain, $0.Resp_tra_delay>(
        'delay',
        delay_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.ask_detain.fromBuffer(value),
        ($0.Resp_tra_delay value) => value.writeToBuffer()));
  }

  $async.Future<$0.tra_stoptimes> stops_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.ask_detain> $request) async {
    return stops($call, await $request);
  }

  $async.Future<$0.tra_stoptimes> stops(
      $grpc.ServiceCall call, $0.ask_detain request);

  $async.Stream<$0.Resp_tra_delay> delay_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.ask_detain> $request) async* {
    yield* delay($call, await $request);
  }

  $async.Stream<$0.Resp_tra_delay> delay(
      $grpc.ServiceCall call, $0.ask_detain request);
}
