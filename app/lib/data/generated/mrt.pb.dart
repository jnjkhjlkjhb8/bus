// This is a generated file - do not edit.
//
// Generated from mrt.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class Resp_Mrt_eta extends $pb.GeneratedMessage {
  factory Resp_Mrt_eta({
    Mrt_live? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  Resp_Mrt_eta._();

  factory Resp_Mrt_eta.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Resp_Mrt_eta.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Resp_Mrt_eta',
      createEmptyInstance: create)
    ..aOM<Mrt_live>(1, _omitFieldNames ? '' : 'data',
        subBuilder: Mrt_live.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_Mrt_eta clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_Mrt_eta copyWith(void Function(Resp_Mrt_eta) updates) =>
      super.copyWith((message) => updates(message as Resp_Mrt_eta))
          as Resp_Mrt_eta;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Resp_Mrt_eta create() => Resp_Mrt_eta._();
  @$core.override
  Resp_Mrt_eta createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Resp_Mrt_eta getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Resp_Mrt_eta>(create);
  static Resp_Mrt_eta? _defaultInstance;

  @$pb.TagNumber(1)
  Mrt_live get data => $_getN(0);
  @$pb.TagNumber(1)
  set data(Mrt_live value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
  @$pb.TagNumber(1)
  Mrt_live ensureData() => $_ensure(0);
}

class Ask_mrt extends $pb.GeneratedMessage {
  factory Ask_mrt({
    $core.String? system,
    $core.String? stationID,
  }) {
    final result = create();
    if (system != null) result.system = system;
    if (stationID != null) result.stationID = stationID;
    return result;
  }

  Ask_mrt._();

  factory Ask_mrt.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Ask_mrt.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Ask_mrt',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'system')
    ..aOS(2, _omitFieldNames ? '' : 'StationID', protoName: 'StationID')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ask_mrt clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ask_mrt copyWith(void Function(Ask_mrt) updates) =>
      super.copyWith((message) => updates(message as Ask_mrt)) as Ask_mrt;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Ask_mrt create() => Ask_mrt._();
  @$core.override
  Ask_mrt createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Ask_mrt getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Ask_mrt>(create);
  static Ask_mrt? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get system => $_getSZ(0);
  @$pb.TagNumber(1)
  set system($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSystem() => $_has(0);
  @$pb.TagNumber(1)
  void clearSystem() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get stationID => $_getSZ(1);
  @$pb.TagNumber(2)
  set stationID($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStationID() => $_has(1);
  @$pb.TagNumber(2)
  void clearStationID() => $_clearField(2);
}

class Mrt_live extends $pb.GeneratedMessage {
  factory Mrt_live({
    $core.String? lineID,
    $core.String? stationID,
    $core.String? system,
    $core.String? tripHeadSign,
    $core.String? destinationStaionID,
    $core.String? destinationStationName,
    $core.int? serviceStatus,
    $core.int? estimateTime,
  }) {
    final result = create();
    if (lineID != null) result.lineID = lineID;
    if (stationID != null) result.stationID = stationID;
    if (system != null) result.system = system;
    if (tripHeadSign != null) result.tripHeadSign = tripHeadSign;
    if (destinationStaionID != null)
      result.destinationStaionID = destinationStaionID;
    if (destinationStationName != null)
      result.destinationStationName = destinationStationName;
    if (serviceStatus != null) result.serviceStatus = serviceStatus;
    if (estimateTime != null) result.estimateTime = estimateTime;
    return result;
  }

  Mrt_live._();

  factory Mrt_live.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Mrt_live.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Mrt_live',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'LineID', protoName: 'LineID')
    ..aOS(2, _omitFieldNames ? '' : 'StationID', protoName: 'StationID')
    ..aOS(3, _omitFieldNames ? '' : 'system')
    ..aOS(4, _omitFieldNames ? '' : 'TripHeadSign', protoName: 'TripHeadSign')
    ..aOS(5, _omitFieldNames ? '' : 'DestinationStaionID',
        protoName: 'DestinationStaionID')
    ..aOS(6, _omitFieldNames ? '' : 'DestinationStationName',
        protoName: 'DestinationStationName')
    ..aI(7, _omitFieldNames ? '' : 'ServiceStatus', protoName: 'ServiceStatus')
    ..aI(8, _omitFieldNames ? '' : 'EstimateTime', protoName: 'EstimateTime')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Mrt_live clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Mrt_live copyWith(void Function(Mrt_live) updates) =>
      super.copyWith((message) => updates(message as Mrt_live)) as Mrt_live;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Mrt_live create() => Mrt_live._();
  @$core.override
  Mrt_live createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Mrt_live getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Mrt_live>(create);
  static Mrt_live? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get lineID => $_getSZ(0);
  @$pb.TagNumber(1)
  set lineID($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLineID() => $_has(0);
  @$pb.TagNumber(1)
  void clearLineID() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get stationID => $_getSZ(1);
  @$pb.TagNumber(2)
  set stationID($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStationID() => $_has(1);
  @$pb.TagNumber(2)
  void clearStationID() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get system => $_getSZ(2);
  @$pb.TagNumber(3)
  set system($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSystem() => $_has(2);
  @$pb.TagNumber(3)
  void clearSystem() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get tripHeadSign => $_getSZ(3);
  @$pb.TagNumber(4)
  set tripHeadSign($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTripHeadSign() => $_has(3);
  @$pb.TagNumber(4)
  void clearTripHeadSign() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get destinationStaionID => $_getSZ(4);
  @$pb.TagNumber(5)
  set destinationStaionID($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDestinationStaionID() => $_has(4);
  @$pb.TagNumber(5)
  void clearDestinationStaionID() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get destinationStationName => $_getSZ(5);
  @$pb.TagNumber(6)
  set destinationStationName($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDestinationStationName() => $_has(5);
  @$pb.TagNumber(6)
  void clearDestinationStationName() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get serviceStatus => $_getIZ(6);
  @$pb.TagNumber(7)
  set serviceStatus($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasServiceStatus() => $_has(6);
  @$pb.TagNumber(7)
  void clearServiceStatus() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get estimateTime => $_getIZ(7);
  @$pb.TagNumber(8)
  set estimateTime($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasEstimateTime() => $_has(7);
  @$pb.TagNumber(8)
  void clearEstimateTime() => $_clearField(8);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
