// This is a generated file - do not edit.
//
// Generated from firebase.proto.

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

import 'firebase.pb.dart' as $0;

export 'firebase.pb.dart';

@$pb.GrpcServiceName('Firebase_Service')
class Firebase_ServiceClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  Firebase_ServiceClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.DeviceState> upsertDevice(
    $0.UpsertDeviceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$upsertDevice, request, options: options);
  }

  $grpc.ResponseFuture<$0.Ack> replaceRouteSubscriptions(
    $0.RouteSubscriptionsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$replaceRouteSubscriptions, request,
        options: options);
  }

  $grpc.ResponseFuture<$0.ArrivalReminder> createArrivalReminder(
    $0.CreateArrivalReminderRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createArrivalReminder, request, options: options);
  }

  $grpc.ResponseFuture<$0.Ack> cancelArrivalReminder(
    $0.CancelArrivalReminderRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$cancelArrivalReminder, request, options: options);
  }

  $grpc.ResponseFuture<$0.DeviceState> listDeviceState(
    $0.DeviceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listDeviceState, request, options: options);
  }

  // method descriptors

  static final _$upsertDevice =
      $grpc.ClientMethod<$0.UpsertDeviceRequest, $0.DeviceState>(
          '/Firebase_Service/upsertDevice',
          ($0.UpsertDeviceRequest value) => value.writeToBuffer(),
          $0.DeviceState.fromBuffer);
  static final _$replaceRouteSubscriptions =
      $grpc.ClientMethod<$0.RouteSubscriptionsRequest, $0.Ack>(
          '/Firebase_Service/replaceRouteSubscriptions',
          ($0.RouteSubscriptionsRequest value) => value.writeToBuffer(),
          $0.Ack.fromBuffer);
  static final _$createArrivalReminder =
      $grpc.ClientMethod<$0.CreateArrivalReminderRequest, $0.ArrivalReminder>(
          '/Firebase_Service/createArrivalReminder',
          ($0.CreateArrivalReminderRequest value) => value.writeToBuffer(),
          $0.ArrivalReminder.fromBuffer);
  static final _$cancelArrivalReminder =
      $grpc.ClientMethod<$0.CancelArrivalReminderRequest, $0.Ack>(
          '/Firebase_Service/cancelArrivalReminder',
          ($0.CancelArrivalReminderRequest value) => value.writeToBuffer(),
          $0.Ack.fromBuffer);
  static final _$listDeviceState =
      $grpc.ClientMethod<$0.DeviceRequest, $0.DeviceState>(
          '/Firebase_Service/listDeviceState',
          ($0.DeviceRequest value) => value.writeToBuffer(),
          $0.DeviceState.fromBuffer);
}

@$pb.GrpcServiceName('Firebase_Service')
abstract class Firebase_ServiceBase extends $grpc.Service {
  $core.String get $name => 'Firebase_Service';

  Firebase_ServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.UpsertDeviceRequest, $0.DeviceState>(
        'upsertDevice',
        upsertDevice_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.UpsertDeviceRequest.fromBuffer(value),
        ($0.DeviceState value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.RouteSubscriptionsRequest, $0.Ack>(
        'replaceRouteSubscriptions',
        replaceRouteSubscriptions_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.RouteSubscriptionsRequest.fromBuffer(value),
        ($0.Ack value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreateArrivalReminderRequest,
            $0.ArrivalReminder>(
        'createArrivalReminder',
        createArrivalReminder_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CreateArrivalReminderRequest.fromBuffer(value),
        ($0.ArrivalReminder value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CancelArrivalReminderRequest, $0.Ack>(
        'cancelArrivalReminder',
        cancelArrivalReminder_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CancelArrivalReminderRequest.fromBuffer(value),
        ($0.Ack value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.DeviceRequest, $0.DeviceState>(
        'listDeviceState',
        listDeviceState_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.DeviceRequest.fromBuffer(value),
        ($0.DeviceState value) => value.writeToBuffer()));
  }

  $async.Future<$0.DeviceState> upsertDevice_Pre($grpc.ServiceCall $call,
      $async.Future<$0.UpsertDeviceRequest> $request) async {
    return upsertDevice($call, await $request);
  }

  $async.Future<$0.DeviceState> upsertDevice(
      $grpc.ServiceCall call, $0.UpsertDeviceRequest request);

  $async.Future<$0.Ack> replaceRouteSubscriptions_Pre($grpc.ServiceCall $call,
      $async.Future<$0.RouteSubscriptionsRequest> $request) async {
    return replaceRouteSubscriptions($call, await $request);
  }

  $async.Future<$0.Ack> replaceRouteSubscriptions(
      $grpc.ServiceCall call, $0.RouteSubscriptionsRequest request);

  $async.Future<$0.ArrivalReminder> createArrivalReminder_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateArrivalReminderRequest> $request) async {
    return createArrivalReminder($call, await $request);
  }

  $async.Future<$0.ArrivalReminder> createArrivalReminder(
      $grpc.ServiceCall call, $0.CreateArrivalReminderRequest request);

  $async.Future<$0.Ack> cancelArrivalReminder_Pre($grpc.ServiceCall $call,
      $async.Future<$0.CancelArrivalReminderRequest> $request) async {
    return cancelArrivalReminder($call, await $request);
  }

  $async.Future<$0.Ack> cancelArrivalReminder(
      $grpc.ServiceCall call, $0.CancelArrivalReminderRequest request);

  $async.Future<$0.DeviceState> listDeviceState_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.DeviceRequest> $request) async {
    return listDeviceState($call, await $request);
  }

  $async.Future<$0.DeviceState> listDeviceState(
      $grpc.ServiceCall call, $0.DeviceRequest request);
}
