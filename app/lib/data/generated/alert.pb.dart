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

class Alert_Msg extends $pb.GeneratedMessage {
  factory Alert_Msg({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
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
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
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

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
