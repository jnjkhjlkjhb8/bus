// This is a generated file - do not edit.
//
// Generated from alert.proto.

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

class Alert_Ask extends $pb.GeneratedMessage {
  factory Alert_Ask() => create();

  Alert_Ask._();

  factory Alert_Ask.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Alert_Ask.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Alert_Ask',
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Alert_Ask clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Alert_Ask copyWith(void Function(Alert_Ask) updates) =>
      super.copyWith((message) => updates(message as Alert_Ask)) as Alert_Ask;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Alert_Ask create() => Alert_Ask._();
  @$core.override
  Alert_Ask createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Alert_Ask getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Alert_Ask>(create);
  static Alert_Ask? _defaultInstance;
}

class Alert_Bus_Ask extends $pb.GeneratedMessage {
  factory Alert_Bus_Ask({
    $core.String? city,
  }) {
    final result = create();
    if (city != null) result.city = city;
    return result;
  }

  Alert_Bus_Ask._();

  factory Alert_Bus_Ask.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Alert_Bus_Ask.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Alert_Bus_Ask',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'city')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Alert_Bus_Ask clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Alert_Bus_Ask copyWith(void Function(Alert_Bus_Ask) updates) =>
      super.copyWith((message) => updates(message as Alert_Bus_Ask))
          as Alert_Bus_Ask;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Alert_Bus_Ask create() => Alert_Bus_Ask._();
  @$core.override
  Alert_Bus_Ask createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Alert_Bus_Ask getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Alert_Bus_Ask>(create);
  static Alert_Bus_Ask? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get city => $_getSZ(0);
  @$pb.TagNumber(1)
  set city($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCity() => $_has(0);
  @$pb.TagNumber(1)
  void clearCity() => $_clearField(1);
}

class Alert_Metro_Ask extends $pb.GeneratedMessage {
  factory Alert_Metro_Ask({
    $core.String? system,
  }) {
    final result = create();
    if (system != null) result.system = system;
    return result;
  }

  Alert_Metro_Ask._();

  factory Alert_Metro_Ask.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Alert_Metro_Ask.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Alert_Metro_Ask',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'system')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Alert_Metro_Ask clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Alert_Metro_Ask copyWith(void Function(Alert_Metro_Ask) updates) =>
      super.copyWith((message) => updates(message as Alert_Metro_Ask))
          as Alert_Metro_Ask;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Alert_Metro_Ask create() => Alert_Metro_Ask._();
  @$core.override
  Alert_Metro_Ask createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Alert_Metro_Ask getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Alert_Metro_Ask>(create);
  static Alert_Metro_Ask? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get system => $_getSZ(0);
  @$pb.TagNumber(1)
  set system($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSystem() => $_has(0);
  @$pb.TagNumber(1)
  void clearSystem() => $_clearField(1);
}

/// One MQTT payload after normalization. TDX ships several alerts per message in
/// three different envelopes; the ingestor unwraps all of them, so every payload
/// on the wire is this one shape and carries the channel's current snapshot.
class Alert_Msg extends $pb.GeneratedMessage {
  factory Alert_Msg({
    $core.Iterable<Alert_Item>? items,
  }) {
    final result = create();
    if (items != null) result.items.addAll(items);
    return result;
  }

  Alert_Msg._();

  factory Alert_Msg.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Alert_Msg.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Alert_Msg',
      createEmptyInstance: create)
    ..pPM<Alert_Item>(2, _omitFieldNames ? '' : 'items',
        subBuilder: Alert_Item.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Alert_Msg clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Alert_Msg copyWith(void Function(Alert_Msg) updates) =>
      super.copyWith((message) => updates(message as Alert_Msg)) as Alert_Msg;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Alert_Msg create() => Alert_Msg._();
  @$core.override
  Alert_Msg createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Alert_Msg getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Alert_Msg>(create);
  static Alert_Msg? _defaultInstance;

  @$pb.TagNumber(2)
  $pb.PbList<Alert_Item> get items => $_getList(0);
}

/// One service disruption. route_keys are the identities the alert is scoped to
/// (bus subroutes, TRA train numbers, metro lines); empty means it names no
/// route and applies system-wide.
class Alert_Item extends $pb.GeneratedMessage {
  factory Alert_Item({
    $core.String? id,
    $core.String? routeType,
    $core.Iterable<$core.String>? routeKeys,
    $core.String? title,
    $core.String? body,
    $core.String? level,
    $fixnum.Int64? timeUnix,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (routeType != null) result.routeType = routeType;
    if (routeKeys != null) result.routeKeys.addAll(routeKeys);
    if (title != null) result.title = title;
    if (body != null) result.body = body;
    if (level != null) result.level = level;
    if (timeUnix != null) result.timeUnix = timeUnix;
    return result;
  }

  Alert_Item._();

  factory Alert_Item.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Alert_Item.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Alert_Item',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'routeType')
    ..pPS(3, _omitFieldNames ? '' : 'routeKeys')
    ..aOS(4, _omitFieldNames ? '' : 'title')
    ..aOS(5, _omitFieldNames ? '' : 'body')
    ..aOS(6, _omitFieldNames ? '' : 'level')
    ..aInt64(7, _omitFieldNames ? '' : 'timeUnix')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Alert_Item clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Alert_Item copyWith(void Function(Alert_Item) updates) =>
      super.copyWith((message) => updates(message as Alert_Item)) as Alert_Item;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Alert_Item create() => Alert_Item._();
  @$core.override
  Alert_Item createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Alert_Item getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Alert_Item>(create);
  static Alert_Item? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get routeType => $_getSZ(1);
  @$pb.TagNumber(2)
  set routeType($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRouteType() => $_has(1);
  @$pb.TagNumber(2)
  void clearRouteType() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get routeKeys => $_getList(2);

  @$pb.TagNumber(4)
  $core.String get title => $_getSZ(3);
  @$pb.TagNumber(4)
  set title($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTitle() => $_has(3);
  @$pb.TagNumber(4)
  void clearTitle() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get body => $_getSZ(4);
  @$pb.TagNumber(5)
  set body($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBody() => $_has(4);
  @$pb.TagNumber(5)
  void clearBody() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get level => $_getSZ(5);
  @$pb.TagNumber(6)
  set level($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLevel() => $_has(5);
  @$pb.TagNumber(6)
  void clearLevel() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get timeUnix => $_getI64(6);
  @$pb.TagNumber(7)
  set timeUnix($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTimeUnix() => $_has(6);
  @$pb.TagNumber(7)
  void clearTimeUnix() => $_clearField(7);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
