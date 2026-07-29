// This is a generated file - do not edit.
//
// Generated from thsr.proto.

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

import 'thsr.pb.dart' as $0;

export 'thsr.pb.dart';

@$pb.GrpcServiceName('Thsr_timetable_service')
class Thsr_timetable_serviceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  Thsr_timetable_serviceClient(super.channel,
      {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.thsa_fares> fare(
    $0.Ask_Thsr request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$fare, request, options: options);
  }

  $grpc.ResponseFuture<$0.thsr_timetables> timetable(
    $0.Ask_Thsr request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$timetable, request, options: options);
  }

  $grpc.ResponseStream<$0.Resp_thsr_seats> available_seats(
    $0.Ask_Thsr request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$available_seats, $async.Stream.fromIterable([request]),
        options: options);
  }

  $grpc.ResponseFuture<$0.thsr_station_board> station_board(
    $0.thsr_ask_station_board request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$station_board, request, options: options);
  }

  // method descriptors

  static final _$fare = $grpc.ClientMethod<$0.Ask_Thsr, $0.thsa_fares>(
      '/Thsr_timetable_service/fare',
      ($0.Ask_Thsr value) => value.writeToBuffer(),
      $0.thsa_fares.fromBuffer);
  static final _$timetable =
      $grpc.ClientMethod<$0.Ask_Thsr, $0.thsr_timetables>(
          '/Thsr_timetable_service/timetable',
          ($0.Ask_Thsr value) => value.writeToBuffer(),
          $0.thsr_timetables.fromBuffer);
  static final _$available_seats =
      $grpc.ClientMethod<$0.Ask_Thsr, $0.Resp_thsr_seats>(
          '/Thsr_timetable_service/available_seats',
          ($0.Ask_Thsr value) => value.writeToBuffer(),
          $0.Resp_thsr_seats.fromBuffer);
  static final _$station_board =
      $grpc.ClientMethod<$0.thsr_ask_station_board, $0.thsr_station_board>(
          '/Thsr_timetable_service/station_board',
          ($0.thsr_ask_station_board value) => value.writeToBuffer(),
          $0.thsr_station_board.fromBuffer);
}

@$pb.GrpcServiceName('Thsr_timetable_service')
abstract class Thsr_timetable_serviceServiceBase extends $grpc.Service {
  $core.String get $name => 'Thsr_timetable_service';

  Thsr_timetable_serviceServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.Ask_Thsr, $0.thsa_fares>(
        'fare',
        fare_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Ask_Thsr.fromBuffer(value),
        ($0.thsa_fares value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Ask_Thsr, $0.thsr_timetables>(
        'timetable',
        timetable_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Ask_Thsr.fromBuffer(value),
        ($0.thsr_timetables value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Ask_Thsr, $0.Resp_thsr_seats>(
        'available_seats',
        available_seats_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.Ask_Thsr.fromBuffer(value),
        ($0.Resp_thsr_seats value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.thsr_ask_station_board, $0.thsr_station_board>(
            'station_board',
            station_board_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.thsr_ask_station_board.fromBuffer(value),
            ($0.thsr_station_board value) => value.writeToBuffer()));
  }

  $async.Future<$0.thsa_fares> fare_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Ask_Thsr> $request) async {
    return fare($call, await $request);
  }

  $async.Future<$0.thsa_fares> fare(
      $grpc.ServiceCall call, $0.Ask_Thsr request);

  $async.Future<$0.thsr_timetables> timetable_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Ask_Thsr> $request) async {
    return timetable($call, await $request);
  }

  $async.Future<$0.thsr_timetables> timetable(
      $grpc.ServiceCall call, $0.Ask_Thsr request);

  $async.Stream<$0.Resp_thsr_seats> available_seats_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Ask_Thsr> $request) async* {
    yield* available_seats($call, await $request);
  }

  $async.Stream<$0.Resp_thsr_seats> available_seats(
      $grpc.ServiceCall call, $0.Ask_Thsr request);

  $async.Future<$0.thsr_station_board> station_board_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.thsr_ask_station_board> $request) async {
    return station_board($call, await $request);
  }

  $async.Future<$0.thsr_station_board> station_board(
      $grpc.ServiceCall call, $0.thsr_ask_station_board request);
}

@$pb.GrpcServiceName('Thsr_Detain_service')
class Thsr_Detain_serviceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  Thsr_Detain_serviceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.thsr_stoptimes> stops(
    $0.thsr_ask_detain request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$stops, request, options: options);
  }

  // method descriptors

  static final _$stops =
      $grpc.ClientMethod<$0.thsr_ask_detain, $0.thsr_stoptimes>(
          '/Thsr_Detain_service/stops',
          ($0.thsr_ask_detain value) => value.writeToBuffer(),
          $0.thsr_stoptimes.fromBuffer);
}

@$pb.GrpcServiceName('Thsr_Detain_service')
abstract class Thsr_Detain_serviceServiceBase extends $grpc.Service {
  $core.String get $name => 'Thsr_Detain_service';

  Thsr_Detain_serviceServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.thsr_ask_detain, $0.thsr_stoptimes>(
        'stops',
        stops_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.thsr_ask_detain.fromBuffer(value),
        ($0.thsr_stoptimes value) => value.writeToBuffer()));
  }

  $async.Future<$0.thsr_stoptimes> stops_Pre($grpc.ServiceCall $call,
      $async.Future<$0.thsr_ask_detain> $request) async {
    return stops($call, await $request);
  }

  $async.Future<$0.thsr_stoptimes> stops(
      $grpc.ServiceCall call, $0.thsr_ask_detain request);
}
