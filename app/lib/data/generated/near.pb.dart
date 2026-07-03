// This is a generated file - do not edit.
//
// Generated from near.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class Ask_Near extends $pb.GeneratedMessage {
  factory Ask_Near({
    $core.double? positionLon,
    $core.double? positionLat,
    $core.int? radius,
  }) {
    final result = create();
    if (positionLon != null) result.positionLon = positionLon;
    if (positionLat != null) result.positionLat = positionLat;
    if (radius != null) result.radius = radius;
    return result;
  }

  Ask_Near._();

  factory Ask_Near.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Ask_Near.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Ask_Near',
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'PositionLon', protoName: 'PositionLon')
    ..aD(2, _omitFieldNames ? '' : 'PositionLat', protoName: 'PositionLat')
    ..aI(3, _omitFieldNames ? '' : 'Radius', protoName: 'Radius')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ask_Near clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ask_Near copyWith(void Function(Ask_Near) updates) =>
      super.copyWith((message) => updates(message as Ask_Near)) as Ask_Near;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Ask_Near create() => Ask_Near._();
  @$core.override
  Ask_Near createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Ask_Near getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Ask_Near>(create);
  static Ask_Near? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get positionLon => $_getN(0);
  @$pb.TagNumber(1)
  set positionLon($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPositionLon() => $_has(0);
  @$pb.TagNumber(1)
  void clearPositionLon() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get positionLat => $_getN(1);
  @$pb.TagNumber(2)
  set positionLat($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPositionLat() => $_has(1);
  @$pb.TagNumber(2)
  void clearPositionLat() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get radius => $_getIZ(2);
  @$pb.TagNumber(3)
  set radius($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRadius() => $_has(2);
  @$pb.TagNumber(3)
  void clearRadius() => $_clearField(3);
}

class resp_near extends $pb.GeneratedMessage {
  factory resp_near({
    $core.Iterable<$core.MapEntry<$core.String, array_near>>? nearBusStations,
    $core.Iterable<NearStation>? nearBikeStations,
    $core.Iterable<NearStation>? nearMrtStations,
    $core.Iterable<NearStation>? nearTraStations,
    $core.Iterable<NearStation>? nearThsrStations,
  }) {
    final result = create();
    if (nearBusStations != null)
      result.nearBusStations.addEntries(nearBusStations);
    if (nearBikeStations != null)
      result.nearBikeStations.addAll(nearBikeStations);
    if (nearMrtStations != null) result.nearMrtStations.addAll(nearMrtStations);
    if (nearTraStations != null) result.nearTraStations.addAll(nearTraStations);
    if (nearThsrStations != null)
      result.nearThsrStations.addAll(nearThsrStations);
    return result;
  }

  resp_near._();

  factory resp_near.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory resp_near.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'resp_near',
      createEmptyInstance: create)
    ..m<$core.String, array_near>(1, _omitFieldNames ? '' : 'nearBusStations',
        entryClassName: 'resp_near.NearBusStationsEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OM,
        valueCreator: array_near.create,
        valueDefaultOrMaker: array_near.getDefault)
    ..pPM<NearStation>(2, _omitFieldNames ? '' : 'nearBikeStations',
        subBuilder: NearStation.create)
    ..pPM<NearStation>(3, _omitFieldNames ? '' : 'nearMrtStations',
        subBuilder: NearStation.create)
    ..pPM<NearStation>(4, _omitFieldNames ? '' : 'nearTraStations',
        subBuilder: NearStation.create)
    ..pPM<NearStation>(5, _omitFieldNames ? '' : 'nearThsrStations',
        subBuilder: NearStation.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  resp_near clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  resp_near copyWith(void Function(resp_near) updates) =>
      super.copyWith((message) => updates(message as resp_near)) as resp_near;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static resp_near create() => resp_near._();
  @$core.override
  resp_near createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static resp_near getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<resp_near>(create);
  static resp_near? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbMap<$core.String, array_near> get nearBusStations => $_getMap(0);

  @$pb.TagNumber(2)
  $pb.PbList<NearStation> get nearBikeStations => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<NearStation> get nearMrtStations => $_getList(2);

  @$pb.TagNumber(4)
  $pb.PbList<NearStation> get nearTraStations => $_getList(3);

  @$pb.TagNumber(5)
  $pb.PbList<NearStation> get nearThsrStations => $_getList(4);
}

class array_near extends $pb.GeneratedMessage {
  factory array_near({
    $core.Iterable<NearStation>? nearStations,
  }) {
    final result = create();
    if (nearStations != null) result.nearStations.addAll(nearStations);
    return result;
  }

  array_near._();

  factory array_near.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory array_near.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'array_near',
      createEmptyInstance: create)
    ..pPM<NearStation>(1, _omitFieldNames ? '' : 'nearStations',
        subBuilder: NearStation.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  array_near clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  array_near copyWith(void Function(array_near) updates) =>
      super.copyWith((message) => updates(message as array_near)) as array_near;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static array_near create() => array_near._();
  @$core.override
  array_near createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static array_near getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<array_near>(create);
  static array_near? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<NearStation> get nearStations => $_getList(0);
}

class NearStation extends $pb.GeneratedMessage {
  factory NearStation({
    $core.int? type,
    $core.String? stationID,
    $core.String? stationName,
    $core.String? city,
    $core.double? positionLon,
    $core.double? positionLat,
    $core.int? walk,
    $core.int? distance,
  }) {
    final result = create();
    if (type != null) result.type = type;
    if (stationID != null) result.stationID = stationID;
    if (stationName != null) result.stationName = stationName;
    if (city != null) result.city = city;
    if (positionLon != null) result.positionLon = positionLon;
    if (positionLat != null) result.positionLat = positionLat;
    if (walk != null) result.walk = walk;
    if (distance != null) result.distance = distance;
    return result;
  }

  NearStation._();

  factory NearStation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory NearStation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NearStation',
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'type')
    ..aOS(2, _omitFieldNames ? '' : 'StationID', protoName: 'StationID')
    ..aOS(3, _omitFieldNames ? '' : 'StationName', protoName: 'StationName')
    ..aOS(4, _omitFieldNames ? '' : 'city')
    ..aD(5, _omitFieldNames ? '' : 'PositionLon', protoName: 'PositionLon')
    ..aD(6, _omitFieldNames ? '' : 'PositionLat', protoName: 'PositionLat')
    ..aI(7, _omitFieldNames ? '' : 'walk')
    ..aI(8, _omitFieldNames ? '' : 'distance')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NearStation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NearStation copyWith(void Function(NearStation) updates) =>
      super.copyWith((message) => updates(message as NearStation))
          as NearStation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static NearStation create() => NearStation._();
  @$core.override
  NearStation createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static NearStation getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NearStation>(create);
  static NearStation? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get type => $_getIZ(0);
  @$pb.TagNumber(1)
  set type($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get stationID => $_getSZ(1);
  @$pb.TagNumber(2)
  set stationID($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStationID() => $_has(1);
  @$pb.TagNumber(2)
  void clearStationID() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get stationName => $_getSZ(2);
  @$pb.TagNumber(3)
  set stationName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStationName() => $_has(2);
  @$pb.TagNumber(3)
  void clearStationName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get city => $_getSZ(3);
  @$pb.TagNumber(4)
  set city($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCity() => $_has(3);
  @$pb.TagNumber(4)
  void clearCity() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get positionLon => $_getN(4);
  @$pb.TagNumber(5)
  set positionLon($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPositionLon() => $_has(4);
  @$pb.TagNumber(5)
  void clearPositionLon() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get positionLat => $_getN(5);
  @$pb.TagNumber(6)
  set positionLat($core.double value) => $_setDouble(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPositionLat() => $_has(5);
  @$pb.TagNumber(6)
  void clearPositionLat() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get walk => $_getIZ(6);
  @$pb.TagNumber(7)
  set walk($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasWalk() => $_has(6);
  @$pb.TagNumber(7)
  void clearWalk() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get distance => $_getIZ(7);
  @$pb.TagNumber(8)
  set distance($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasDistance() => $_has(7);
  @$pb.TagNumber(8)
  void clearDistance() => $_clearField(8);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
