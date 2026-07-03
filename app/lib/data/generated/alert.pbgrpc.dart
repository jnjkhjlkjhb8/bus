// This is a generated file - do not edit.
//
// Generated from alert.proto.

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

import 'alert.pb.dart' as $0;

export 'alert.pb.dart';

@$pb.GrpcServiceName('Alert_Service')
class Alert_ServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  Alert_ServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseStream<$0.Alert_Msg> busNews(
    $0.Alert_Bus_Ask request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$busNews, $async.Stream.fromIterable([request]),
        options: options);
  }

  $grpc.ResponseStream<$0.Alert_Msg> metroAlert(
    $0.Alert_Metro_Ask request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$metroAlert, $async.Stream.fromIterable([request]),
        options: options);
  }

  $grpc.ResponseStream<$0.Alert_Msg> traAlert(
    $0.Alert_Ask request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$traAlert, $async.Stream.fromIterable([request]),
        options: options);
  }

  $grpc.ResponseStream<$0.Alert_Msg> thsrAlert(
    $0.Alert_Ask request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$thsrAlert, $async.Stream.fromIterable([request]),
        options: options);
  }

  // method descriptors

  static final _$busNews = $grpc.ClientMethod<$0.Alert_Bus_Ask, $0.Alert_Msg>(
      '/Alert_Service/busNews',
      ($0.Alert_Bus_Ask value) => value.writeToBuffer(),
      $0.Alert_Msg.fromBuffer);
  static final _$metroAlert =
      $grpc.ClientMethod<$0.Alert_Metro_Ask, $0.Alert_Msg>(
          '/Alert_Service/metroAlert',
          ($0.Alert_Metro_Ask value) => value.writeToBuffer(),
          $0.Alert_Msg.fromBuffer);
  static final _$traAlert = $grpc.ClientMethod<$0.Alert_Ask, $0.Alert_Msg>(
      '/Alert_Service/traAlert',
      ($0.Alert_Ask value) => value.writeToBuffer(),
      $0.Alert_Msg.fromBuffer);
  static final _$thsrAlert = $grpc.ClientMethod<$0.Alert_Ask, $0.Alert_Msg>(
      '/Alert_Service/thsrAlert',
      ($0.Alert_Ask value) => value.writeToBuffer(),
      $0.Alert_Msg.fromBuffer);
}

@$pb.GrpcServiceName('Alert_Service')
abstract class Alert_ServiceBase extends $grpc.Service {
  $core.String get $name => 'Alert_Service';

  Alert_ServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.Alert_Bus_Ask, $0.Alert_Msg>(
        'busNews',
        busNews_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.Alert_Bus_Ask.fromBuffer(value),
        ($0.Alert_Msg value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Alert_Metro_Ask, $0.Alert_Msg>(
        'metroAlert',
        metroAlert_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.Alert_Metro_Ask.fromBuffer(value),
        ($0.Alert_Msg value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Alert_Ask, $0.Alert_Msg>(
        'traAlert',
        traAlert_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.Alert_Ask.fromBuffer(value),
        ($0.Alert_Msg value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Alert_Ask, $0.Alert_Msg>(
        'thsrAlert',
        thsrAlert_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.Alert_Ask.fromBuffer(value),
        ($0.Alert_Msg value) => value.writeToBuffer()));
  }

  $async.Stream<$0.Alert_Msg> busNews_Pre($grpc.ServiceCall $call,
      $async.Future<$0.Alert_Bus_Ask> $request) async* {
    yield* busNews($call, await $request);
  }

  $async.Stream<$0.Alert_Msg> busNews(
      $grpc.ServiceCall call, $0.Alert_Bus_Ask request);

  $async.Stream<$0.Alert_Msg> metroAlert_Pre($grpc.ServiceCall $call,
      $async.Future<$0.Alert_Metro_Ask> $request) async* {
    yield* metroAlert($call, await $request);
  }

  $async.Stream<$0.Alert_Msg> metroAlert(
      $grpc.ServiceCall call, $0.Alert_Metro_Ask request);

  $async.Stream<$0.Alert_Msg> traAlert_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Alert_Ask> $request) async* {
    yield* traAlert($call, await $request);
  }

  $async.Stream<$0.Alert_Msg> traAlert(
      $grpc.ServiceCall call, $0.Alert_Ask request);

  $async.Stream<$0.Alert_Msg> thsrAlert_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Alert_Ask> $request) async* {
    yield* thsrAlert($call, await $request);
  }

  $async.Stream<$0.Alert_Msg> thsrAlert(
      $grpc.ServiceCall call, $0.Alert_Ask request);
}
