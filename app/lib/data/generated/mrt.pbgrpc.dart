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

  /// Metro alight reminder (捷運下車提醒, ADR-0015): a car-bound tracking session.
  /// CreateTrack resolves the car to a trip and returns the initial live state;
  /// WatchTrack streams the evolving state; CancelTrack ends the session.
  $grpc.ResponseFuture<$0.MrtTrackState> createTrack(
    $0.CreateMrtTrackRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createTrack, request, options: options);
  }

  $grpc.ResponseStream<$0.MrtTrackState> watchTrack(
    $0.WatchMrtTrackRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$watchTrack, $async.Stream.fromIterable([request]),
        options: options);
  }

  $grpc.ResponseFuture<$0.MrtTrackAck> cancelTrack(
    $0.CancelMrtTrackRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$cancelTrack, request, options: options);
  }

  // method descriptors

  static final _$eta = $grpc.ClientMethod<$0.Ask_mrt, $0.Resp_Mrt_eta>(
      '/Mrt_Service/eta',
      ($0.Ask_mrt value) => value.writeToBuffer(),
      $0.Resp_Mrt_eta.fromBuffer);
  static final _$createTrack =
      $grpc.ClientMethod<$0.CreateMrtTrackRequest, $0.MrtTrackState>(
          '/Mrt_Service/CreateTrack',
          ($0.CreateMrtTrackRequest value) => value.writeToBuffer(),
          $0.MrtTrackState.fromBuffer);
  static final _$watchTrack =
      $grpc.ClientMethod<$0.WatchMrtTrackRequest, $0.MrtTrackState>(
          '/Mrt_Service/WatchTrack',
          ($0.WatchMrtTrackRequest value) => value.writeToBuffer(),
          $0.MrtTrackState.fromBuffer);
  static final _$cancelTrack =
      $grpc.ClientMethod<$0.CancelMrtTrackRequest, $0.MrtTrackAck>(
          '/Mrt_Service/CancelTrack',
          ($0.CancelMrtTrackRequest value) => value.writeToBuffer(),
          $0.MrtTrackAck.fromBuffer);
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
    $addMethod($grpc.ServiceMethod<$0.CreateMrtTrackRequest, $0.MrtTrackState>(
        'CreateTrack',
        createTrack_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CreateMrtTrackRequest.fromBuffer(value),
        ($0.MrtTrackState value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.WatchMrtTrackRequest, $0.MrtTrackState>(
        'WatchTrack',
        watchTrack_Pre,
        false,
        true,
        ($core.List<$core.int> value) =>
            $0.WatchMrtTrackRequest.fromBuffer(value),
        ($0.MrtTrackState value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CancelMrtTrackRequest, $0.MrtTrackAck>(
        'CancelTrack',
        cancelTrack_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CancelMrtTrackRequest.fromBuffer(value),
        ($0.MrtTrackAck value) => value.writeToBuffer()));
  }

  $async.Stream<$0.Resp_Mrt_eta> eta_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Ask_mrt> $request) async* {
    yield* eta($call, await $request);
  }

  $async.Stream<$0.Resp_Mrt_eta> eta(
      $grpc.ServiceCall call, $0.Ask_mrt request);

  $async.Future<$0.MrtTrackState> createTrack_Pre($grpc.ServiceCall $call,
      $async.Future<$0.CreateMrtTrackRequest> $request) async {
    return createTrack($call, await $request);
  }

  $async.Future<$0.MrtTrackState> createTrack(
      $grpc.ServiceCall call, $0.CreateMrtTrackRequest request);

  $async.Stream<$0.MrtTrackState> watchTrack_Pre($grpc.ServiceCall $call,
      $async.Future<$0.WatchMrtTrackRequest> $request) async* {
    yield* watchTrack($call, await $request);
  }

  $async.Stream<$0.MrtTrackState> watchTrack(
      $grpc.ServiceCall call, $0.WatchMrtTrackRequest request);

  $async.Future<$0.MrtTrackAck> cancelTrack_Pre($grpc.ServiceCall $call,
      $async.Future<$0.CancelMrtTrackRequest> $request) async {
    return cancelTrack($call, await $request);
  }

  $async.Future<$0.MrtTrackAck> cancelTrack(
      $grpc.ServiceCall call, $0.CancelMrtTrackRequest request);
}
