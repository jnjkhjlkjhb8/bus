// This is a generated file - do not edit.
//
// Generated from bike.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class Bike_request extends $pb.GeneratedMessage {
  factory Bike_request({
    $core.String? stationUID,
  }) {
    final result = create();
    if (stationUID != null) result.stationUID = stationUID;
    return result;
  }

  Bike_request._();

  factory Bike_request.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bike_request.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bike_request',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'StationUID', protoName: 'StationUID')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bike_request clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bike_request copyWith(void Function(Bike_request) updates) =>
      super.copyWith((message) => updates(message as Bike_request))
          as Bike_request;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bike_request create() => Bike_request._();
  @$core.override
  Bike_request createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bike_request getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bike_request>(create);
  static Bike_request? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get stationUID => $_getSZ(0);
  @$pb.TagNumber(1)
  set stationUID($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStationUID() => $_has(0);
  @$pb.TagNumber(1)
  void clearStationUID() => $_clearField(1);
}

class Resp_Bike_eta extends $pb.GeneratedMessage {
  factory Resp_Bike_eta({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  Resp_Bike_eta._();

  factory Resp_Bike_eta.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Resp_Bike_eta.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Resp_Bike_eta',
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_Bike_eta clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_Bike_eta copyWith(void Function(Resp_Bike_eta) updates) =>
      super.copyWith((message) => updates(message as Resp_Bike_eta))
          as Resp_Bike_eta;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Resp_Bike_eta create() => Resp_Bike_eta._();
  @$core.override
  Resp_Bike_eta createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Resp_Bike_eta getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Resp_Bike_eta>(create);
  static Resp_Bike_eta? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

class Bike_static extends $pb.GeneratedMessage {
  factory Bike_static({
    $core.String? stationUID,
    $core.String? name,
    $core.int? serviceType,
    $core.int? capacity,
    $core.String? city,
    $core.String? lat,
    $core.String? lon,
    $core.String? address,
  }) {
    final result = create();
    if (stationUID != null) result.stationUID = stationUID;
    if (name != null) result.name = name;
    if (serviceType != null) result.serviceType = serviceType;
    if (capacity != null) result.capacity = capacity;
    if (city != null) result.city = city;
    if (lat != null) result.lat = lat;
    if (lon != null) result.lon = lon;
    if (address != null) result.address = address;
    return result;
  }

  Bike_static._();

  factory Bike_static.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bike_static.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bike_static',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'StationUID', protoName: 'StationUID')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aI(3, _omitFieldNames ? '' : 'serviceType')
    ..aI(4, _omitFieldNames ? '' : 'capacity')
    ..aOS(5, _omitFieldNames ? '' : 'city')
    ..aOS(6, _omitFieldNames ? '' : 'Lat', protoName: 'Lat')
    ..aOS(7, _omitFieldNames ? '' : 'Lon', protoName: 'Lon')
    ..aOS(8, _omitFieldNames ? '' : 'address')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bike_static clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bike_static copyWith(void Function(Bike_static) updates) =>
      super.copyWith((message) => updates(message as Bike_static))
          as Bike_static;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bike_static create() => Bike_static._();
  @$core.override
  Bike_static createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bike_static getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bike_static>(create);
  static Bike_static? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get stationUID => $_getSZ(0);
  @$pb.TagNumber(1)
  set stationUID($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStationUID() => $_has(0);
  @$pb.TagNumber(1)
  void clearStationUID() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get serviceType => $_getIZ(2);
  @$pb.TagNumber(3)
  set serviceType($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasServiceType() => $_has(2);
  @$pb.TagNumber(3)
  void clearServiceType() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get capacity => $_getIZ(3);
  @$pb.TagNumber(4)
  set capacity($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCapacity() => $_has(3);
  @$pb.TagNumber(4)
  void clearCapacity() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get city => $_getSZ(4);
  @$pb.TagNumber(5)
  set city($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCity() => $_has(4);
  @$pb.TagNumber(5)
  void clearCity() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get lat => $_getSZ(5);
  @$pb.TagNumber(6)
  set lat($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLat() => $_has(5);
  @$pb.TagNumber(6)
  void clearLat() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get lon => $_getSZ(6);
  @$pb.TagNumber(7)
  set lon($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLon() => $_has(6);
  @$pb.TagNumber(7)
  void clearLon() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get address => $_getSZ(7);
  @$pb.TagNumber(8)
  set address($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAddress() => $_has(7);
  @$pb.TagNumber(8)
  void clearAddress() => $_clearField(8);
}

class Bike_eta extends $pb.GeneratedMessage {
  factory Bike_eta({
    $core.String? stationUID,
    $core.int? serviceStatus,
    $core.int? serviceType,
    $core.int? availableReturnBikes,
    $core.int? generalBikes,
    $core.int? electricBikes,
  }) {
    final result = create();
    if (stationUID != null) result.stationUID = stationUID;
    if (serviceStatus != null) result.serviceStatus = serviceStatus;
    if (serviceType != null) result.serviceType = serviceType;
    if (availableReturnBikes != null)
      result.availableReturnBikes = availableReturnBikes;
    if (generalBikes != null) result.generalBikes = generalBikes;
    if (electricBikes != null) result.electricBikes = electricBikes;
    return result;
  }

  Bike_eta._();

  factory Bike_eta.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bike_eta.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bike_eta',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'StationUID', protoName: 'StationUID')
    ..aI(2, _omitFieldNames ? '' : 'ServiceStatus', protoName: 'ServiceStatus')
    ..aI(3, _omitFieldNames ? '' : 'ServiceType', protoName: 'ServiceType')
    ..aI(4, _omitFieldNames ? '' : 'AvailableReturnBikes',
        protoName: 'AvailableReturnBikes')
    ..aI(5, _omitFieldNames ? '' : 'GeneralBikes', protoName: 'GeneralBikes')
    ..aI(6, _omitFieldNames ? '' : 'ElectricBikes', protoName: 'ElectricBikes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bike_eta clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bike_eta copyWith(void Function(Bike_eta) updates) =>
      super.copyWith((message) => updates(message as Bike_eta)) as Bike_eta;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bike_eta create() => Bike_eta._();
  @$core.override
  Bike_eta createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bike_eta getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Bike_eta>(create);
  static Bike_eta? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get stationUID => $_getSZ(0);
  @$pb.TagNumber(1)
  set stationUID($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStationUID() => $_has(0);
  @$pb.TagNumber(1)
  void clearStationUID() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get serviceStatus => $_getIZ(1);
  @$pb.TagNumber(2)
  set serviceStatus($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasServiceStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearServiceStatus() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get serviceType => $_getIZ(2);
  @$pb.TagNumber(3)
  set serviceType($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasServiceType() => $_has(2);
  @$pb.TagNumber(3)
  void clearServiceType() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get availableReturnBikes => $_getIZ(3);
  @$pb.TagNumber(4)
  set availableReturnBikes($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAvailableReturnBikes() => $_has(3);
  @$pb.TagNumber(4)
  void clearAvailableReturnBikes() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get generalBikes => $_getIZ(4);
  @$pb.TagNumber(5)
  set generalBikes($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasGeneralBikes() => $_has(4);
  @$pb.TagNumber(5)
  void clearGeneralBikes() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get electricBikes => $_getIZ(5);
  @$pb.TagNumber(6)
  set electricBikes($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasElectricBikes() => $_has(5);
  @$pb.TagNumber(6)
  void clearElectricBikes() => $_clearField(6);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
