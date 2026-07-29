// This is a generated file - do not edit.
//
// Generated from firebase.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class Ack extends $pb.GeneratedMessage {
  factory Ack({
    $core.bool? ok,
    $core.String? message,
  }) {
    final result = create();
    if (ok != null) result.ok = ok;
    if (message != null) result.message = message;
    return result;
  }

  Ack._();

  factory Ack.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Ack.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Ack',
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'ok')
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ack clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ack copyWith(void Function(Ack) updates) =>
      super.copyWith((message) => updates(message as Ack)) as Ack;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Ack create() => Ack._();
  @$core.override
  Ack createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Ack getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Ack>(create);
  static Ack? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get ok => $_getBF(0);
  @$pb.TagNumber(1)
  set ok($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOk() => $_has(0);
  @$pb.TagNumber(1)
  void clearOk() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);
}

class DeviceIdentity extends $pb.GeneratedMessage {
  factory DeviceIdentity({
    $core.String? installId,
    $core.String? fcmToken,
    $core.String? platform,
    $core.String? appVersion,
  }) {
    final result = create();
    if (installId != null) result.installId = installId;
    if (fcmToken != null) result.fcmToken = fcmToken;
    if (platform != null) result.platform = platform;
    if (appVersion != null) result.appVersion = appVersion;
    return result;
  }

  DeviceIdentity._();

  factory DeviceIdentity.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeviceIdentity.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeviceIdentity',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'installId')
    ..aOS(2, _omitFieldNames ? '' : 'fcmToken')
    ..aOS(3, _omitFieldNames ? '' : 'platform')
    ..aOS(4, _omitFieldNames ? '' : 'appVersion')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceIdentity clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceIdentity copyWith(void Function(DeviceIdentity) updates) =>
      super.copyWith((message) => updates(message as DeviceIdentity))
          as DeviceIdentity;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceIdentity create() => DeviceIdentity._();
  @$core.override
  DeviceIdentity createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeviceIdentity getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeviceIdentity>(create);
  static DeviceIdentity? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get installId => $_getSZ(0);
  @$pb.TagNumber(1)
  set installId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstallId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get fcmToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set fcmToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFcmToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearFcmToken() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get platform => $_getSZ(2);
  @$pb.TagNumber(3)
  set platform($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPlatform() => $_has(2);
  @$pb.TagNumber(3)
  void clearPlatform() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get appVersion => $_getSZ(3);
  @$pb.TagNumber(4)
  set appVersion($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAppVersion() => $_has(3);
  @$pb.TagNumber(4)
  void clearAppVersion() => $_clearField(4);
}

/// Push is the only device preference the rider controls. Analytics, crash and
/// performance collection are always on, so they are not carried here.
class DevicePrefs extends $pb.GeneratedMessage {
  factory DevicePrefs({
    $core.bool? pushEnabled,
  }) {
    final result = create();
    if (pushEnabled != null) result.pushEnabled = pushEnabled;
    return result;
  }

  DevicePrefs._();

  factory DevicePrefs.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DevicePrefs.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DevicePrefs',
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'pushEnabled')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DevicePrefs clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DevicePrefs copyWith(void Function(DevicePrefs) updates) =>
      super.copyWith((message) => updates(message as DevicePrefs))
          as DevicePrefs;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DevicePrefs create() => DevicePrefs._();
  @$core.override
  DevicePrefs createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DevicePrefs getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DevicePrefs>(create);
  static DevicePrefs? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get pushEnabled => $_getBF(0);
  @$pb.TagNumber(1)
  set pushEnabled($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPushEnabled() => $_has(0);
  @$pb.TagNumber(1)
  void clearPushEnabled() => $_clearField(1);
}

class UpsertDeviceRequest extends $pb.GeneratedMessage {
  factory UpsertDeviceRequest({
    DeviceIdentity? identity,
    DevicePrefs? prefs,
  }) {
    final result = create();
    if (identity != null) result.identity = identity;
    if (prefs != null) result.prefs = prefs;
    return result;
  }

  UpsertDeviceRequest._();

  factory UpsertDeviceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpsertDeviceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpsertDeviceRequest',
      createEmptyInstance: create)
    ..aOM<DeviceIdentity>(1, _omitFieldNames ? '' : 'identity',
        subBuilder: DeviceIdentity.create)
    ..aOM<DevicePrefs>(2, _omitFieldNames ? '' : 'prefs',
        subBuilder: DevicePrefs.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpsertDeviceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpsertDeviceRequest copyWith(void Function(UpsertDeviceRequest) updates) =>
      super.copyWith((message) => updates(message as UpsertDeviceRequest))
          as UpsertDeviceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpsertDeviceRequest create() => UpsertDeviceRequest._();
  @$core.override
  UpsertDeviceRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpsertDeviceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpsertDeviceRequest>(create);
  static UpsertDeviceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  DeviceIdentity get identity => $_getN(0);
  @$pb.TagNumber(1)
  set identity(DeviceIdentity value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasIdentity() => $_has(0);
  @$pb.TagNumber(1)
  void clearIdentity() => $_clearField(1);
  @$pb.TagNumber(1)
  DeviceIdentity ensureIdentity() => $_ensure(0);

  @$pb.TagNumber(2)
  DevicePrefs get prefs => $_getN(1);
  @$pb.TagNumber(2)
  set prefs(DevicePrefs value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPrefs() => $_has(1);
  @$pb.TagNumber(2)
  void clearPrefs() => $_clearField(2);
  @$pb.TagNumber(2)
  DevicePrefs ensurePrefs() => $_ensure(1);
}

class DeviceRequest extends $pb.GeneratedMessage {
  factory DeviceRequest({
    $core.String? installId,
  }) {
    final result = create();
    if (installId != null) result.installId = installId;
    return result;
  }

  DeviceRequest._();

  factory DeviceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeviceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeviceRequest',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'installId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceRequest copyWith(void Function(DeviceRequest) updates) =>
      super.copyWith((message) => updates(message as DeviceRequest))
          as DeviceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceRequest create() => DeviceRequest._();
  @$core.override
  DeviceRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeviceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeviceRequest>(create);
  static DeviceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get installId => $_getSZ(0);
  @$pb.TagNumber(1)
  set installId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstallId() => $_clearField(1);
}

class DeviceState extends $pb.GeneratedMessage {
  factory DeviceState({
    DeviceIdentity? identity,
    DevicePrefs? prefs,
  }) {
    final result = create();
    if (identity != null) result.identity = identity;
    if (prefs != null) result.prefs = prefs;
    return result;
  }

  DeviceState._();

  factory DeviceState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeviceState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeviceState',
      createEmptyInstance: create)
    ..aOM<DeviceIdentity>(1, _omitFieldNames ? '' : 'identity',
        subBuilder: DeviceIdentity.create)
    ..aOM<DevicePrefs>(2, _omitFieldNames ? '' : 'prefs',
        subBuilder: DevicePrefs.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceState copyWith(void Function(DeviceState) updates) =>
      super.copyWith((message) => updates(message as DeviceState))
          as DeviceState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceState create() => DeviceState._();
  @$core.override
  DeviceState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeviceState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeviceState>(create);
  static DeviceState? _defaultInstance;

  @$pb.TagNumber(1)
  DeviceIdentity get identity => $_getN(0);
  @$pb.TagNumber(1)
  set identity(DeviceIdentity value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasIdentity() => $_has(0);
  @$pb.TagNumber(1)
  void clearIdentity() => $_clearField(1);
  @$pb.TagNumber(1)
  DeviceIdentity ensureIdentity() => $_ensure(0);

  @$pb.TagNumber(2)
  DevicePrefs get prefs => $_getN(1);
  @$pb.TagNumber(2)
  set prefs(DevicePrefs value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPrefs() => $_has(1);
  @$pb.TagNumber(2)
  void clearPrefs() => $_clearField(2);
  @$pb.TagNumber(2)
  DevicePrefs ensurePrefs() => $_ensure(1);
}

/// One route identity a device's 收藏 resolves to. route_key "*" is the
/// line-wide marker a rail-station 收藏 produces: it matches no real alert
/// scope, so it receives only system-wide disruptions.
class RouteSubscription extends $pb.GeneratedMessage {
  factory RouteSubscription({
    $core.String? routeType,
    $core.String? routeKey,
  }) {
    final result = create();
    if (routeType != null) result.routeType = routeType;
    if (routeKey != null) result.routeKey = routeKey;
    return result;
  }

  RouteSubscription._();

  factory RouteSubscription.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RouteSubscription.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RouteSubscription',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'routeType')
    ..aOS(2, _omitFieldNames ? '' : 'routeKey')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RouteSubscription clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RouteSubscription copyWith(void Function(RouteSubscription) updates) =>
      super.copyWith((message) => updates(message as RouteSubscription))
          as RouteSubscription;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RouteSubscription create() => RouteSubscription._();
  @$core.override
  RouteSubscription createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RouteSubscription getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RouteSubscription>(create);
  static RouteSubscription? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get routeType => $_getSZ(0);
  @$pb.TagNumber(1)
  set routeType($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRouteType() => $_has(0);
  @$pb.TagNumber(1)
  void clearRouteType() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get routeKey => $_getSZ(1);
  @$pb.TagNumber(2)
  set routeKey($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRouteKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearRouteKey() => $_clearField(2);
}

/// The device's whole 訂閱範圍, replacing whatever was stored. Sending an empty
/// list unsubscribes the device from everything.
class RouteSubscriptionsRequest extends $pb.GeneratedMessage {
  factory RouteSubscriptionsRequest({
    $core.String? installId,
    $core.Iterable<RouteSubscription>? subscriptions,
  }) {
    final result = create();
    if (installId != null) result.installId = installId;
    if (subscriptions != null) result.subscriptions.addAll(subscriptions);
    return result;
  }

  RouteSubscriptionsRequest._();

  factory RouteSubscriptionsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RouteSubscriptionsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RouteSubscriptionsRequest',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'installId')
    ..pPM<RouteSubscription>(2, _omitFieldNames ? '' : 'subscriptions',
        subBuilder: RouteSubscription.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RouteSubscriptionsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RouteSubscriptionsRequest copyWith(
          void Function(RouteSubscriptionsRequest) updates) =>
      super.copyWith((message) => updates(message as RouteSubscriptionsRequest))
          as RouteSubscriptionsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RouteSubscriptionsRequest create() => RouteSubscriptionsRequest._();
  @$core.override
  RouteSubscriptionsRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RouteSubscriptionsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RouteSubscriptionsRequest>(create);
  static RouteSubscriptionsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get installId => $_getSZ(0);
  @$pb.TagNumber(1)
  set installId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstallId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<RouteSubscription> get subscriptions => $_getList(1);
}

class CreateArrivalReminderRequest extends $pb.GeneratedMessage {
  factory CreateArrivalReminderRequest({
    $core.String? installId,
    $core.String? routeType,
    $core.String? routeKey,
    $core.String? stopKey,
    $core.String? direction,
    $core.int? leadMinutes,
    $fixnum.Int64? expiresAtUnix,
    $core.String? plate,
  }) {
    final result = create();
    if (installId != null) result.installId = installId;
    if (routeType != null) result.routeType = routeType;
    if (routeKey != null) result.routeKey = routeKey;
    if (stopKey != null) result.stopKey = stopKey;
    if (direction != null) result.direction = direction;
    if (leadMinutes != null) result.leadMinutes = leadMinutes;
    if (expiresAtUnix != null) result.expiresAtUnix = expiresAtUnix;
    if (plate != null) result.plate = plate;
    return result;
  }

  CreateArrivalReminderRequest._();

  factory CreateArrivalReminderRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateArrivalReminderRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateArrivalReminderRequest',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'installId')
    ..aOS(2, _omitFieldNames ? '' : 'routeType')
    ..aOS(3, _omitFieldNames ? '' : 'routeKey')
    ..aOS(4, _omitFieldNames ? '' : 'stopKey')
    ..aOS(5, _omitFieldNames ? '' : 'direction')
    ..aI(6, _omitFieldNames ? '' : 'leadMinutes')
    ..aInt64(7, _omitFieldNames ? '' : 'expiresAtUnix')
    ..aOS(8, _omitFieldNames ? '' : 'plate')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateArrivalReminderRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateArrivalReminderRequest copyWith(
          void Function(CreateArrivalReminderRequest) updates) =>
      super.copyWith(
              (message) => updates(message as CreateArrivalReminderRequest))
          as CreateArrivalReminderRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateArrivalReminderRequest create() =>
      CreateArrivalReminderRequest._();
  @$core.override
  CreateArrivalReminderRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateArrivalReminderRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateArrivalReminderRequest>(create);
  static CreateArrivalReminderRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get installId => $_getSZ(0);
  @$pb.TagNumber(1)
  set installId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstallId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get routeType => $_getSZ(1);
  @$pb.TagNumber(2)
  set routeType($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRouteType() => $_has(1);
  @$pb.TagNumber(2)
  void clearRouteType() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get routeKey => $_getSZ(2);
  @$pb.TagNumber(3)
  set routeKey($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRouteKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearRouteKey() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get stopKey => $_getSZ(3);
  @$pb.TagNumber(4)
  set stopKey($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStopKey() => $_has(3);
  @$pb.TagNumber(4)
  void clearStopKey() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get direction => $_getSZ(4);
  @$pb.TagNumber(5)
  set direction($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDirection() => $_has(4);
  @$pb.TagNumber(5)
  void clearDirection() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get leadMinutes => $_getIZ(5);
  @$pb.TagNumber(6)
  set leadMinutes($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLeadMinutes() => $_has(5);
  @$pb.TagNumber(6)
  void clearLeadMinutes() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get expiresAtUnix => $_getI64(6);
  @$pb.TagNumber(7)
  set expiresAtUnix($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasExpiresAtUnix() => $_has(6);
  @$pb.TagNumber(7)
  void clearExpiresAtUnix() => $_clearField(7);

  /// Non-empty pins the reminder to one vehicle: it fires only when this plate
  /// is the bus arriving at stop_key. Empty keeps the legacy next-bus behaviour.
  @$pb.TagNumber(8)
  $core.String get plate => $_getSZ(7);
  @$pb.TagNumber(8)
  set plate($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasPlate() => $_has(7);
  @$pb.TagNumber(8)
  void clearPlate() => $_clearField(8);
}

class ArrivalReminder extends $pb.GeneratedMessage {
  factory ArrivalReminder({
    $core.String? reminderId,
    $core.String? installId,
    $core.String? routeType,
    $core.String? routeKey,
    $core.String? stopKey,
    $core.String? direction,
    $core.int? leadMinutes,
    $fixnum.Int64? expiresAtUnix,
    $core.String? plate,
  }) {
    final result = create();
    if (reminderId != null) result.reminderId = reminderId;
    if (installId != null) result.installId = installId;
    if (routeType != null) result.routeType = routeType;
    if (routeKey != null) result.routeKey = routeKey;
    if (stopKey != null) result.stopKey = stopKey;
    if (direction != null) result.direction = direction;
    if (leadMinutes != null) result.leadMinutes = leadMinutes;
    if (expiresAtUnix != null) result.expiresAtUnix = expiresAtUnix;
    if (plate != null) result.plate = plate;
    return result;
  }

  ArrivalReminder._();

  factory ArrivalReminder.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ArrivalReminder.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ArrivalReminder',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'reminderId')
    ..aOS(2, _omitFieldNames ? '' : 'installId')
    ..aOS(3, _omitFieldNames ? '' : 'routeType')
    ..aOS(4, _omitFieldNames ? '' : 'routeKey')
    ..aOS(5, _omitFieldNames ? '' : 'stopKey')
    ..aOS(6, _omitFieldNames ? '' : 'direction')
    ..aI(7, _omitFieldNames ? '' : 'leadMinutes')
    ..aInt64(8, _omitFieldNames ? '' : 'expiresAtUnix')
    ..aOS(9, _omitFieldNames ? '' : 'plate')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ArrivalReminder clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ArrivalReminder copyWith(void Function(ArrivalReminder) updates) =>
      super.copyWith((message) => updates(message as ArrivalReminder))
          as ArrivalReminder;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ArrivalReminder create() => ArrivalReminder._();
  @$core.override
  ArrivalReminder createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ArrivalReminder getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ArrivalReminder>(create);
  static ArrivalReminder? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get reminderId => $_getSZ(0);
  @$pb.TagNumber(1)
  set reminderId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasReminderId() => $_has(0);
  @$pb.TagNumber(1)
  void clearReminderId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get installId => $_getSZ(1);
  @$pb.TagNumber(2)
  set installId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasInstallId() => $_has(1);
  @$pb.TagNumber(2)
  void clearInstallId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get routeType => $_getSZ(2);
  @$pb.TagNumber(3)
  set routeType($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRouteType() => $_has(2);
  @$pb.TagNumber(3)
  void clearRouteType() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get routeKey => $_getSZ(3);
  @$pb.TagNumber(4)
  set routeKey($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRouteKey() => $_has(3);
  @$pb.TagNumber(4)
  void clearRouteKey() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get stopKey => $_getSZ(4);
  @$pb.TagNumber(5)
  set stopKey($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasStopKey() => $_has(4);
  @$pb.TagNumber(5)
  void clearStopKey() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get direction => $_getSZ(5);
  @$pb.TagNumber(6)
  set direction($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDirection() => $_has(5);
  @$pb.TagNumber(6)
  void clearDirection() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get leadMinutes => $_getIZ(6);
  @$pb.TagNumber(7)
  set leadMinutes($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLeadMinutes() => $_has(6);
  @$pb.TagNumber(7)
  void clearLeadMinutes() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get expiresAtUnix => $_getI64(7);
  @$pb.TagNumber(8)
  set expiresAtUnix($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasExpiresAtUnix() => $_has(7);
  @$pb.TagNumber(8)
  void clearExpiresAtUnix() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get plate => $_getSZ(8);
  @$pb.TagNumber(9)
  set plate($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasPlate() => $_has(8);
  @$pb.TagNumber(9)
  void clearPlate() => $_clearField(9);
}

class CancelArrivalReminderRequest extends $pb.GeneratedMessage {
  factory CancelArrivalReminderRequest({
    $core.String? reminderId,
    $core.String? installId,
  }) {
    final result = create();
    if (reminderId != null) result.reminderId = reminderId;
    if (installId != null) result.installId = installId;
    return result;
  }

  CancelArrivalReminderRequest._();

  factory CancelArrivalReminderRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CancelArrivalReminderRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CancelArrivalReminderRequest',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'reminderId')
    ..aOS(2, _omitFieldNames ? '' : 'installId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancelArrivalReminderRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancelArrivalReminderRequest copyWith(
          void Function(CancelArrivalReminderRequest) updates) =>
      super.copyWith(
              (message) => updates(message as CancelArrivalReminderRequest))
          as CancelArrivalReminderRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CancelArrivalReminderRequest create() =>
      CancelArrivalReminderRequest._();
  @$core.override
  CancelArrivalReminderRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CancelArrivalReminderRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CancelArrivalReminderRequest>(create);
  static CancelArrivalReminderRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get reminderId => $_getSZ(0);
  @$pb.TagNumber(1)
  set reminderId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasReminderId() => $_has(0);
  @$pb.TagNumber(1)
  void clearReminderId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get installId => $_getSZ(1);
  @$pb.TagNumber(2)
  set installId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasInstallId() => $_has(1);
  @$pb.TagNumber(2)
  void clearInstallId() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
