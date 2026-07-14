// This is a generated file - do not edit.
//
// Generated from bus.proto.

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

class Bus_Ask_Route extends $pb.GeneratedMessage {
  factory Bus_Ask_Route({
    $core.String? subRouteUID,
  }) {
    final result = create();
    if (subRouteUID != null) result.subRouteUID = subRouteUID;
    return result;
  }

  Bus_Ask_Route._();

  factory Bus_Ask_Route.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_Ask_Route.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_Ask_Route',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'SubRouteUID', protoName: 'SubRouteUID')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_Ask_Route clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_Ask_Route copyWith(void Function(Bus_Ask_Route) updates) =>
      super.copyWith((message) => updates(message as Bus_Ask_Route))
          as Bus_Ask_Route;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_Ask_Route create() => Bus_Ask_Route._();
  @$core.override
  Bus_Ask_Route createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_Ask_Route getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bus_Ask_Route>(create);
  static Bus_Ask_Route? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get subRouteUID => $_getSZ(0);
  @$pb.TagNumber(1)
  set subRouteUID($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSubRouteUID() => $_has(0);
  @$pb.TagNumber(1)
  void clearSubRouteUID() => $_clearField(1);
}

class Bus_Ask_StationGroup extends $pb.GeneratedMessage {
  factory Bus_Ask_StationGroup({
    $core.String? city,
    $core.String? groupUid,
  }) {
    final result = create();
    if (city != null) result.city = city;
    if (groupUid != null) result.groupUid = groupUid;
    return result;
  }

  Bus_Ask_StationGroup._();

  factory Bus_Ask_StationGroup.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_Ask_StationGroup.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_Ask_StationGroup',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'city')
    ..aOS(2, _omitFieldNames ? '' : 'groupUid')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_Ask_StationGroup clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_Ask_StationGroup copyWith(void Function(Bus_Ask_StationGroup) updates) =>
      super.copyWith((message) => updates(message as Bus_Ask_StationGroup))
          as Bus_Ask_StationGroup;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_Ask_StationGroup create() => Bus_Ask_StationGroup._();
  @$core.override
  Bus_Ask_StationGroup createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_Ask_StationGroup getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bus_Ask_StationGroup>(create);
  static Bus_Ask_StationGroup? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get city => $_getSZ(0);
  @$pb.TagNumber(1)
  set city($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCity() => $_has(0);
  @$pb.TagNumber(1)
  void clearCity() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get groupUid => $_getSZ(1);
  @$pb.TagNumber(2)
  set groupUid($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGroupUid() => $_has(1);
  @$pb.TagNumber(2)
  void clearGroupUid() => $_clearField(2);
}

class Bus_Ask_Station extends $pb.GeneratedMessage {
  factory Bus_Ask_Station({
    $core.String? stationName,
    $core.String? city,
  }) {
    final result = create();
    if (stationName != null) result.stationName = stationName;
    if (city != null) result.city = city;
    return result;
  }

  Bus_Ask_Station._();

  factory Bus_Ask_Station.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_Ask_Station.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_Ask_Station',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'StationName', protoName: 'StationName')
    ..aOS(2, _omitFieldNames ? '' : 'city')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_Ask_Station clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_Ask_Station copyWith(void Function(Bus_Ask_Station) updates) =>
      super.copyWith((message) => updates(message as Bus_Ask_Station))
          as Bus_Ask_Station;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_Ask_Station create() => Bus_Ask_Station._();
  @$core.override
  Bus_Ask_Station createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_Ask_Station getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bus_Ask_Station>(create);
  static Bus_Ask_Station? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get stationName => $_getSZ(0);
  @$pb.TagNumber(1)
  set stationName($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStationName() => $_has(0);
  @$pb.TagNumber(1)
  void clearStationName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get city => $_getSZ(1);
  @$pb.TagNumber(2)
  set city($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCity() => $_has(1);
  @$pb.TagNumber(2)
  void clearCity() => $_clearField(2);
}

/// Wire-compatible with the former `bytes data = 1`: a length-delimited field 1
/// still carries a marshaled Bus_subroute, now typed for the interface.
class Resp_Bus_static extends $pb.GeneratedMessage {
  factory Resp_Bus_static({
    Bus_subroute? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  Resp_Bus_static._();

  factory Resp_Bus_static.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Resp_Bus_static.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Resp_Bus_static',
      createEmptyInstance: create)
    ..aOM<Bus_subroute>(1, _omitFieldNames ? '' : 'data',
        subBuilder: Bus_subroute.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_Bus_static clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_Bus_static copyWith(void Function(Resp_Bus_static) updates) =>
      super.copyWith((message) => updates(message as Resp_Bus_static))
          as Resp_Bus_static;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Resp_Bus_static create() => Resp_Bus_static._();
  @$core.override
  Resp_Bus_static createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Resp_Bus_static getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Resp_Bus_static>(create);
  static Resp_Bus_static? _defaultInstance;

  @$pb.TagNumber(1)
  Bus_subroute get data => $_getN(0);
  @$pb.TagNumber(1)
  set data(Bus_subroute value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
  @$pb.TagNumber(1)
  Bus_subroute ensureData() => $_ensure(0);
}

/// Route ETA envelope. data is a Bus_RouteArrival (Bus_Route_Service.eta).
class Resp_Bus_eta extends $pb.GeneratedMessage {
  factory Resp_Bus_eta({
    Bus_RouteArrival? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  Resp_Bus_eta._();

  factory Resp_Bus_eta.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Resp_Bus_eta.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Resp_Bus_eta',
      createEmptyInstance: create)
    ..aOM<Bus_RouteArrival>(1, _omitFieldNames ? '' : 'data',
        subBuilder: Bus_RouteArrival.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_Bus_eta clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_Bus_eta copyWith(void Function(Resp_Bus_eta) updates) =>
      super.copyWith((message) => updates(message as Resp_Bus_eta))
          as Resp_Bus_eta;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Resp_Bus_eta create() => Resp_Bus_eta._();
  @$core.override
  Resp_Bus_eta createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Resp_Bus_eta getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Resp_Bus_eta>(create);
  static Resp_Bus_eta? _defaultInstance;

  @$pb.TagNumber(1)
  Bus_RouteArrival get data => $_getN(0);
  @$pb.TagNumber(1)
  set data(Bus_RouteArrival value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
  @$pb.TagNumber(1)
  Bus_RouteArrival ensureData() => $_ensure(0);
}

/// Station-group ETA envelope. data is a Bus_StationArrival
/// (Bus_Station_Service.eta). Split from Resp_Bus_eta so each RPC carries its
/// own payload schema.
class Resp_Bus_station_eta extends $pb.GeneratedMessage {
  factory Resp_Bus_station_eta({
    Bus_StationArrival? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  Resp_Bus_station_eta._();

  factory Resp_Bus_station_eta.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Resp_Bus_station_eta.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Resp_Bus_station_eta',
      createEmptyInstance: create)
    ..aOM<Bus_StationArrival>(1, _omitFieldNames ? '' : 'data',
        subBuilder: Bus_StationArrival.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_Bus_station_eta clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_Bus_station_eta copyWith(void Function(Resp_Bus_station_eta) updates) =>
      super.copyWith((message) => updates(message as Resp_Bus_station_eta))
          as Resp_Bus_station_eta;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Resp_Bus_station_eta create() => Resp_Bus_station_eta._();
  @$core.override
  Resp_Bus_station_eta createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Resp_Bus_station_eta getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Resp_Bus_station_eta>(create);
  static Resp_Bus_station_eta? _defaultInstance;

  @$pb.TagNumber(1)
  Bus_StationArrival get data => $_getN(0);
  @$pb.TagNumber(1)
  set data(Bus_StationArrival value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
  @$pb.TagNumber(1)
  Bus_StationArrival ensureData() => $_ensure(0);
}

class Resp_Bus_daily_timetable extends $pb.GeneratedMessage {
  factory Resp_Bus_daily_timetable({
    Bus_DailyTimetables? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  Resp_Bus_daily_timetable._();

  factory Resp_Bus_daily_timetable.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Resp_Bus_daily_timetable.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Resp_Bus_daily_timetable',
      createEmptyInstance: create)
    ..aOM<Bus_DailyTimetables>(1, _omitFieldNames ? '' : 'data',
        subBuilder: Bus_DailyTimetables.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_Bus_daily_timetable clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_Bus_daily_timetable copyWith(
          void Function(Resp_Bus_daily_timetable) updates) =>
      super.copyWith((message) => updates(message as Resp_Bus_daily_timetable))
          as Resp_Bus_daily_timetable;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Resp_Bus_daily_timetable create() => Resp_Bus_daily_timetable._();
  @$core.override
  Resp_Bus_daily_timetable createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Resp_Bus_daily_timetable getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Resp_Bus_daily_timetable>(create);
  static Resp_Bus_daily_timetable? _defaultInstance;

  @$pb.TagNumber(1)
  Bus_DailyTimetables get data => $_getN(0);
  @$pb.TagNumber(1)
  set data(Bus_DailyTimetables value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
  @$pb.TagNumber(1)
  Bus_DailyTimetables ensureData() => $_ensure(0);
}

class BusOperator extends $pb.GeneratedMessage {
  factory BusOperator({
    $core.String? operatorId,
    $core.String? operatorName,
    $core.String? operatorPhone,
    $core.String? operatorUrl,
  }) {
    final result = create();
    if (operatorId != null) result.operatorId = operatorId;
    if (operatorName != null) result.operatorName = operatorName;
    if (operatorPhone != null) result.operatorPhone = operatorPhone;
    if (operatorUrl != null) result.operatorUrl = operatorUrl;
    return result;
  }

  BusOperator._();

  factory BusOperator.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory BusOperator.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BusOperator',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'operatorId')
    ..aOS(2, _omitFieldNames ? '' : 'operatorName')
    ..aOS(3, _omitFieldNames ? '' : 'operatorPhone')
    ..aOS(4, _omitFieldNames ? '' : 'operatorUrl')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BusOperator clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BusOperator copyWith(void Function(BusOperator) updates) =>
      super.copyWith((message) => updates(message as BusOperator))
          as BusOperator;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BusOperator create() => BusOperator._();
  @$core.override
  BusOperator createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static BusOperator getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BusOperator>(create);
  static BusOperator? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get operatorId => $_getSZ(0);
  @$pb.TagNumber(1)
  set operatorId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOperatorId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOperatorId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get operatorName => $_getSZ(1);
  @$pb.TagNumber(2)
  set operatorName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOperatorName() => $_has(1);
  @$pb.TagNumber(2)
  void clearOperatorName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get operatorPhone => $_getSZ(2);
  @$pb.TagNumber(3)
  set operatorPhone($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOperatorPhone() => $_has(2);
  @$pb.TagNumber(3)
  void clearOperatorPhone() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get operatorUrl => $_getSZ(3);
  @$pb.TagNumber(4)
  set operatorUrl($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOperatorUrl() => $_has(3);
  @$pb.TagNumber(4)
  void clearOperatorUrl() => $_clearField(4);
}

class Bus_subroute extends $pb.GeneratedMessage {
  factory Bus_subroute({
    $core.String? routeUID,
    $core.String? routeName,
    $core.String? subRouteUID,
    $core.String? subRouteName,
    $core.String? departureStopName,
    $core.String? destinationStopName,
    $core.String? city,
    $core.Iterable<$core.MapEntry<$core.int, Direction>>? directions,
    $core.Iterable<BusOperator>? operators,
    Bus_Fare? fare,
  }) {
    final result = create();
    if (routeUID != null) result.routeUID = routeUID;
    if (routeName != null) result.routeName = routeName;
    if (subRouteUID != null) result.subRouteUID = subRouteUID;
    if (subRouteName != null) result.subRouteName = subRouteName;
    if (departureStopName != null) result.departureStopName = departureStopName;
    if (destinationStopName != null)
      result.destinationStopName = destinationStopName;
    if (city != null) result.city = city;
    if (directions != null) result.directions.addEntries(directions);
    if (operators != null) result.operators.addAll(operators);
    if (fare != null) result.fare = fare;
    return result;
  }

  Bus_subroute._();

  factory Bus_subroute.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_subroute.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_subroute',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'RouteUID', protoName: 'RouteUID')
    ..aOS(2, _omitFieldNames ? '' : 'RouteName', protoName: 'RouteName')
    ..aOS(3, _omitFieldNames ? '' : 'SubRouteUID', protoName: 'SubRouteUID')
    ..aOS(4, _omitFieldNames ? '' : 'SubRouteName', protoName: 'SubRouteName')
    ..aOS(5, _omitFieldNames ? '' : 'DepartureStopName',
        protoName: 'DepartureStopName')
    ..aOS(6, _omitFieldNames ? '' : 'DestinationStopName',
        protoName: 'DestinationStopName')
    ..aOS(7, _omitFieldNames ? '' : 'city')
    ..m<$core.int, Direction>(8, _omitFieldNames ? '' : 'Directions',
        protoName: 'Directions',
        entryClassName: 'Bus_subroute.DirectionsEntry',
        keyFieldType: $pb.PbFieldType.O3,
        valueFieldType: $pb.PbFieldType.OM,
        valueCreator: Direction.create,
        valueDefaultOrMaker: Direction.getDefault)
    ..pPM<BusOperator>(9, _omitFieldNames ? '' : 'operators',
        subBuilder: BusOperator.create)
    ..aOM<Bus_Fare>(10, _omitFieldNames ? '' : 'fare',
        subBuilder: Bus_Fare.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_subroute clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_subroute copyWith(void Function(Bus_subroute) updates) =>
      super.copyWith((message) => updates(message as Bus_subroute))
          as Bus_subroute;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_subroute create() => Bus_subroute._();
  @$core.override
  Bus_subroute createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_subroute getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bus_subroute>(create);
  static Bus_subroute? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get routeUID => $_getSZ(0);
  @$pb.TagNumber(1)
  set routeUID($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRouteUID() => $_has(0);
  @$pb.TagNumber(1)
  void clearRouteUID() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get routeName => $_getSZ(1);
  @$pb.TagNumber(2)
  set routeName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRouteName() => $_has(1);
  @$pb.TagNumber(2)
  void clearRouteName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get subRouteUID => $_getSZ(2);
  @$pb.TagNumber(3)
  set subRouteUID($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSubRouteUID() => $_has(2);
  @$pb.TagNumber(3)
  void clearSubRouteUID() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get subRouteName => $_getSZ(3);
  @$pb.TagNumber(4)
  set subRouteName($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSubRouteName() => $_has(3);
  @$pb.TagNumber(4)
  void clearSubRouteName() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get departureStopName => $_getSZ(4);
  @$pb.TagNumber(5)
  set departureStopName($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDepartureStopName() => $_has(4);
  @$pb.TagNumber(5)
  void clearDepartureStopName() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get destinationStopName => $_getSZ(5);
  @$pb.TagNumber(6)
  set destinationStopName($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDestinationStopName() => $_has(5);
  @$pb.TagNumber(6)
  void clearDestinationStopName() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get city => $_getSZ(6);
  @$pb.TagNumber(7)
  set city($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasCity() => $_has(6);
  @$pb.TagNumber(7)
  void clearCity() => $_clearField(7);

  @$pb.TagNumber(8)
  $pb.PbMap<$core.int, Direction> get directions => $_getMap(7);

  @$pb.TagNumber(9)
  $pb.PbList<BusOperator> get operators => $_getList(8);

  @$pb.TagNumber(10)
  Bus_Fare get fare => $_getN(9);
  @$pb.TagNumber(10)
  set fare(Bus_Fare value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasFare() => $_has(9);
  @$pb.TagNumber(10)
  void clearFare() => $_clearField(10);
  @$pb.TagNumber(10)
  Bus_Fare ensureFare() => $_ensure(9);
}

class Direction extends $pb.GeneratedMessage {
  factory Direction({
    $core.String? departureStopName,
    $core.String? destinationStopName,
    $core.String? geometry,
    $core.Iterable<Bus_stop>? stops,
    $core.Iterable<Bus_Schedule>? schedules,
    $core.String? firstBusTime,
    $core.String? lastBusTime,
    $core.String? holidayFirstBusTime,
    $core.String? holidayLastBusTime,
  }) {
    final result = create();
    if (departureStopName != null) result.departureStopName = departureStopName;
    if (destinationStopName != null)
      result.destinationStopName = destinationStopName;
    if (geometry != null) result.geometry = geometry;
    if (stops != null) result.stops.addAll(stops);
    if (schedules != null) result.schedules.addAll(schedules);
    if (firstBusTime != null) result.firstBusTime = firstBusTime;
    if (lastBusTime != null) result.lastBusTime = lastBusTime;
    if (holidayFirstBusTime != null)
      result.holidayFirstBusTime = holidayFirstBusTime;
    if (holidayLastBusTime != null)
      result.holidayLastBusTime = holidayLastBusTime;
    return result;
  }

  Direction._();

  factory Direction.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Direction.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Direction',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'DepartureStopName',
        protoName: 'DepartureStopName')
    ..aOS(2, _omitFieldNames ? '' : 'DestinationStopName',
        protoName: 'DestinationStopName')
    ..aOS(3, _omitFieldNames ? '' : 'Geometry', protoName: 'Geometry')
    ..pPM<Bus_stop>(4, _omitFieldNames ? '' : 'Stops',
        protoName: 'Stops', subBuilder: Bus_stop.create)
    ..pPM<Bus_Schedule>(5, _omitFieldNames ? '' : 'Schedules',
        protoName: 'Schedules', subBuilder: Bus_Schedule.create)
    ..aOS(6, _omitFieldNames ? '' : 'firstBusTime')
    ..aOS(7, _omitFieldNames ? '' : 'lastBusTime')
    ..aOS(8, _omitFieldNames ? '' : 'holidayFirstBusTime')
    ..aOS(9, _omitFieldNames ? '' : 'holidayLastBusTime')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Direction clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Direction copyWith(void Function(Direction) updates) =>
      super.copyWith((message) => updates(message as Direction)) as Direction;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Direction create() => Direction._();
  @$core.override
  Direction createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Direction getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Direction>(create);
  static Direction? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get departureStopName => $_getSZ(0);
  @$pb.TagNumber(1)
  set departureStopName($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDepartureStopName() => $_has(0);
  @$pb.TagNumber(1)
  void clearDepartureStopName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get destinationStopName => $_getSZ(1);
  @$pb.TagNumber(2)
  set destinationStopName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDestinationStopName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDestinationStopName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get geometry => $_getSZ(2);
  @$pb.TagNumber(3)
  set geometry($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGeometry() => $_has(2);
  @$pb.TagNumber(3)
  void clearGeometry() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<Bus_stop> get stops => $_getList(3);

  @$pb.TagNumber(5)
  $pb.PbList<Bus_Schedule> get schedules => $_getList(4);

  @$pb.TagNumber(6)
  $core.String get firstBusTime => $_getSZ(5);
  @$pb.TagNumber(6)
  set firstBusTime($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasFirstBusTime() => $_has(5);
  @$pb.TagNumber(6)
  void clearFirstBusTime() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get lastBusTime => $_getSZ(6);
  @$pb.TagNumber(7)
  set lastBusTime($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLastBusTime() => $_has(6);
  @$pb.TagNumber(7)
  void clearLastBusTime() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get holidayFirstBusTime => $_getSZ(7);
  @$pb.TagNumber(8)
  set holidayFirstBusTime($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasHolidayFirstBusTime() => $_has(7);
  @$pb.TagNumber(8)
  void clearHolidayFirstBusTime() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get holidayLastBusTime => $_getSZ(8);
  @$pb.TagNumber(9)
  set holidayLastBusTime($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasHolidayLastBusTime() => $_has(8);
  @$pb.TagNumber(9)
  void clearHolidayLastBusTime() => $_clearField(9);
}

class Bus_stop extends $pb.GeneratedMessage {
  factory Bus_stop({
    $core.String? stopUID,
    $core.String? stopName,
    $core.int? stopSequence,
    $core.double? positionLon,
    $core.double? positionLat,
    $core.String? stationID,
  }) {
    final result = create();
    if (stopUID != null) result.stopUID = stopUID;
    if (stopName != null) result.stopName = stopName;
    if (stopSequence != null) result.stopSequence = stopSequence;
    if (positionLon != null) result.positionLon = positionLon;
    if (positionLat != null) result.positionLat = positionLat;
    if (stationID != null) result.stationID = stationID;
    return result;
  }

  Bus_stop._();

  factory Bus_stop.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_stop.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_stop',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'StopUID', protoName: 'StopUID')
    ..aOS(2, _omitFieldNames ? '' : 'StopName', protoName: 'StopName')
    ..aI(3, _omitFieldNames ? '' : 'StopSequence', protoName: 'StopSequence')
    ..aD(4, _omitFieldNames ? '' : 'PositionLon', protoName: 'PositionLon')
    ..aD(5, _omitFieldNames ? '' : 'PositionLat', protoName: 'PositionLat')
    ..aOS(6, _omitFieldNames ? '' : 'StationID', protoName: 'StationID')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_stop clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_stop copyWith(void Function(Bus_stop) updates) =>
      super.copyWith((message) => updates(message as Bus_stop)) as Bus_stop;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_stop create() => Bus_stop._();
  @$core.override
  Bus_stop createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_stop getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Bus_stop>(create);
  static Bus_stop? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get stopUID => $_getSZ(0);
  @$pb.TagNumber(1)
  set stopUID($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStopUID() => $_has(0);
  @$pb.TagNumber(1)
  void clearStopUID() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get stopName => $_getSZ(1);
  @$pb.TagNumber(2)
  set stopName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStopName() => $_has(1);
  @$pb.TagNumber(2)
  void clearStopName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get stopSequence => $_getIZ(2);
  @$pb.TagNumber(3)
  set stopSequence($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStopSequence() => $_has(2);
  @$pb.TagNumber(3)
  void clearStopSequence() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get positionLon => $_getN(3);
  @$pb.TagNumber(4)
  set positionLon($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPositionLon() => $_has(3);
  @$pb.TagNumber(4)
  void clearPositionLon() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get positionLat => $_getN(4);
  @$pb.TagNumber(5)
  set positionLat($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPositionLat() => $_has(4);
  @$pb.TagNumber(5)
  void clearPositionLat() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get stationID => $_getSZ(5);
  @$pb.TagNumber(6)
  set stationID($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasStationID() => $_has(5);
  @$pb.TagNumber(6)
  void clearStationID() => $_clearField(6);
}

class RouteOfStop extends $pb.GeneratedMessage {
  factory RouteOfStop({
    $core.String? subRouteUID,
    $core.int? direction,
    $core.Iterable<Bus_stop>? stops,
  }) {
    final result = create();
    if (subRouteUID != null) result.subRouteUID = subRouteUID;
    if (direction != null) result.direction = direction;
    if (stops != null) result.stops.addAll(stops);
    return result;
  }

  RouteOfStop._();

  factory RouteOfStop.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RouteOfStop.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RouteOfStop',
      createEmptyInstance: create)
    ..aOS(2, _omitFieldNames ? '' : 'SubRouteUID', protoName: 'SubRouteUID')
    ..aI(3, _omitFieldNames ? '' : 'Direction', protoName: 'Direction')
    ..pPM<Bus_stop>(4, _omitFieldNames ? '' : 'Stops',
        protoName: 'Stops', subBuilder: Bus_stop.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RouteOfStop clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RouteOfStop copyWith(void Function(RouteOfStop) updates) =>
      super.copyWith((message) => updates(message as RouteOfStop))
          as RouteOfStop;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RouteOfStop create() => RouteOfStop._();
  @$core.override
  RouteOfStop createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RouteOfStop getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RouteOfStop>(create);
  static RouteOfStop? _defaultInstance;

  @$pb.TagNumber(2)
  $core.String get subRouteUID => $_getSZ(0);
  @$pb.TagNumber(2)
  set subRouteUID($core.String value) => $_setString(0, value);
  @$pb.TagNumber(2)
  $core.bool hasSubRouteUID() => $_has(0);
  @$pb.TagNumber(2)
  void clearSubRouteUID() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get direction => $_getIZ(1);
  @$pb.TagNumber(3)
  set direction($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(3)
  $core.bool hasDirection() => $_has(1);
  @$pb.TagNumber(3)
  void clearDirection() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<Bus_stop> get stops => $_getList(2);
}

class Shape extends $pb.GeneratedMessage {
  factory Shape({
    $core.String? subRouteUID,
    $core.int? direction,
    $core.String? geometry,
  }) {
    final result = create();
    if (subRouteUID != null) result.subRouteUID = subRouteUID;
    if (direction != null) result.direction = direction;
    if (geometry != null) result.geometry = geometry;
    return result;
  }

  Shape._();

  factory Shape.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Shape.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Shape',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'SubRouteUID', protoName: 'SubRouteUID')
    ..aI(2, _omitFieldNames ? '' : 'Direction', protoName: 'Direction')
    ..aOS(3, _omitFieldNames ? '' : 'Geometry', protoName: 'Geometry')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Shape clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Shape copyWith(void Function(Shape) updates) =>
      super.copyWith((message) => updates(message as Shape)) as Shape;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Shape create() => Shape._();
  @$core.override
  Shape createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Shape getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Shape>(create);
  static Shape? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get subRouteUID => $_getSZ(0);
  @$pb.TagNumber(1)
  set subRouteUID($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSubRouteUID() => $_has(0);
  @$pb.TagNumber(1)
  void clearSubRouteUID() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get direction => $_getIZ(1);
  @$pb.TagNumber(2)
  set direction($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDirection() => $_has(1);
  @$pb.TagNumber(2)
  void clearDirection() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get geometry => $_getSZ(2);
  @$pb.TagNumber(3)
  set geometry($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGeometry() => $_has(2);
  @$pb.TagNumber(3)
  void clearGeometry() => $_clearField(3);
}

class Station extends $pb.GeneratedMessage {
  factory Station({
    $core.String? stationUID,
    $core.String? stationName,
    $core.String? city,
    $core.double? positionLon,
    $core.double? positionLat,
  }) {
    final result = create();
    if (stationUID != null) result.stationUID = stationUID;
    if (stationName != null) result.stationName = stationName;
    if (city != null) result.city = city;
    if (positionLon != null) result.positionLon = positionLon;
    if (positionLat != null) result.positionLat = positionLat;
    return result;
  }

  Station._();

  factory Station.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Station.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Station',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'StationUID', protoName: 'StationUID')
    ..aOS(2, _omitFieldNames ? '' : 'StationName', protoName: 'StationName')
    ..aOS(3, _omitFieldNames ? '' : 'city')
    ..aD(4, _omitFieldNames ? '' : 'PositionLon', protoName: 'PositionLon')
    ..aD(5, _omitFieldNames ? '' : 'PositionLat', protoName: 'PositionLat')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Station clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Station copyWith(void Function(Station) updates) =>
      super.copyWith((message) => updates(message as Station)) as Station;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Station create() => Station._();
  @$core.override
  Station createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Station getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Station>(create);
  static Station? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get stationUID => $_getSZ(0);
  @$pb.TagNumber(1)
  set stationUID($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStationUID() => $_has(0);
  @$pb.TagNumber(1)
  void clearStationUID() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get stationName => $_getSZ(1);
  @$pb.TagNumber(2)
  set stationName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStationName() => $_has(1);
  @$pb.TagNumber(2)
  void clearStationName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get city => $_getSZ(2);
  @$pb.TagNumber(3)
  set city($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCity() => $_has(2);
  @$pb.TagNumber(3)
  void clearCity() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get positionLon => $_getN(3);
  @$pb.TagNumber(4)
  set positionLon($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPositionLon() => $_has(3);
  @$pb.TagNumber(4)
  void clearPositionLon() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get positionLat => $_getN(4);
  @$pb.TagNumber(5)
  set positionLat($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPositionLat() => $_has(4);
  @$pb.TagNumber(5)
  void clearPositionLat() => $_clearField(5);
}

class Bus_StationGroup extends $pb.GeneratedMessage {
  factory Bus_StationGroup({
    $core.String? groupUid,
    $core.String? groupName,
    $core.String? city,
    $core.double? positionLon,
    $core.double? positionLat,
    $core.Iterable<Bus_StationGroupMember>? members,
  }) {
    final result = create();
    if (groupUid != null) result.groupUid = groupUid;
    if (groupName != null) result.groupName = groupName;
    if (city != null) result.city = city;
    if (positionLon != null) result.positionLon = positionLon;
    if (positionLat != null) result.positionLat = positionLat;
    if (members != null) result.members.addAll(members);
    return result;
  }

  Bus_StationGroup._();

  factory Bus_StationGroup.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_StationGroup.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_StationGroup',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'groupUid')
    ..aOS(2, _omitFieldNames ? '' : 'groupName')
    ..aOS(3, _omitFieldNames ? '' : 'city')
    ..aD(4, _omitFieldNames ? '' : 'positionLon')
    ..aD(5, _omitFieldNames ? '' : 'positionLat')
    ..pPM<Bus_StationGroupMember>(6, _omitFieldNames ? '' : 'members',
        subBuilder: Bus_StationGroupMember.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_StationGroup clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_StationGroup copyWith(void Function(Bus_StationGroup) updates) =>
      super.copyWith((message) => updates(message as Bus_StationGroup))
          as Bus_StationGroup;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_StationGroup create() => Bus_StationGroup._();
  @$core.override
  Bus_StationGroup createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_StationGroup getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bus_StationGroup>(create);
  static Bus_StationGroup? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get groupUid => $_getSZ(0);
  @$pb.TagNumber(1)
  set groupUid($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasGroupUid() => $_has(0);
  @$pb.TagNumber(1)
  void clearGroupUid() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get groupName => $_getSZ(1);
  @$pb.TagNumber(2)
  set groupName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGroupName() => $_has(1);
  @$pb.TagNumber(2)
  void clearGroupName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get city => $_getSZ(2);
  @$pb.TagNumber(3)
  set city($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCity() => $_has(2);
  @$pb.TagNumber(3)
  void clearCity() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get positionLon => $_getN(3);
  @$pb.TagNumber(4)
  set positionLon($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPositionLon() => $_has(3);
  @$pb.TagNumber(4)
  void clearPositionLon() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get positionLat => $_getN(4);
  @$pb.TagNumber(5)
  set positionLat($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPositionLat() => $_has(4);
  @$pb.TagNumber(5)
  void clearPositionLat() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<Bus_StationGroupMember> get members => $_getList(5);
}

class Bus_StationGroupMember extends $pb.GeneratedMessage {
  factory Bus_StationGroupMember({
    $core.String? stationUid,
    $core.String? stationId,
    $core.String? stationName,
    $core.double? positionLon,
    $core.double? positionLat,
  }) {
    final result = create();
    if (stationUid != null) result.stationUid = stationUid;
    if (stationId != null) result.stationId = stationId;
    if (stationName != null) result.stationName = stationName;
    if (positionLon != null) result.positionLon = positionLon;
    if (positionLat != null) result.positionLat = positionLat;
    return result;
  }

  Bus_StationGroupMember._();

  factory Bus_StationGroupMember.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_StationGroupMember.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_StationGroupMember',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'stationUid')
    ..aOS(2, _omitFieldNames ? '' : 'stationId')
    ..aOS(3, _omitFieldNames ? '' : 'stationName')
    ..aD(4, _omitFieldNames ? '' : 'positionLon')
    ..aD(5, _omitFieldNames ? '' : 'positionLat')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_StationGroupMember clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_StationGroupMember copyWith(
          void Function(Bus_StationGroupMember) updates) =>
      super.copyWith((message) => updates(message as Bus_StationGroupMember))
          as Bus_StationGroupMember;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_StationGroupMember create() => Bus_StationGroupMember._();
  @$core.override
  Bus_StationGroupMember createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_StationGroupMember getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bus_StationGroupMember>(create);
  static Bus_StationGroupMember? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get stationUid => $_getSZ(0);
  @$pb.TagNumber(1)
  set stationUid($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStationUid() => $_has(0);
  @$pb.TagNumber(1)
  void clearStationUid() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get stationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set stationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearStationId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get stationName => $_getSZ(2);
  @$pb.TagNumber(3)
  set stationName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStationName() => $_has(2);
  @$pb.TagNumber(3)
  void clearStationName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get positionLon => $_getN(3);
  @$pb.TagNumber(4)
  set positionLon($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPositionLon() => $_has(3);
  @$pb.TagNumber(4)
  void clearPositionLon() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get positionLat => $_getN(4);
  @$pb.TagNumber(5)
  set positionLat($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPositionLat() => $_has(4);
  @$pb.TagNumber(5)
  void clearPositionLat() => $_clearField(5);
}

class Bus_RouteArrival extends $pb.GeneratedMessage {
  factory Bus_RouteArrival({
    $core.String? subRouteUid,
    $core.Iterable<Bus_RouteEstimate>? stops,
  }) {
    final result = create();
    if (subRouteUid != null) result.subRouteUid = subRouteUid;
    if (stops != null) result.stops.addAll(stops);
    return result;
  }

  Bus_RouteArrival._();

  factory Bus_RouteArrival.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_RouteArrival.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_RouteArrival',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'subRouteUid')
    ..pPM<Bus_RouteEstimate>(3, _omitFieldNames ? '' : 'stops',
        subBuilder: Bus_RouteEstimate.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_RouteArrival clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_RouteArrival copyWith(void Function(Bus_RouteArrival) updates) =>
      super.copyWith((message) => updates(message as Bus_RouteArrival))
          as Bus_RouteArrival;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_RouteArrival create() => Bus_RouteArrival._();
  @$core.override
  Bus_RouteArrival createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_RouteArrival getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bus_RouteArrival>(create);
  static Bus_RouteArrival? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get subRouteUid => $_getSZ(0);
  @$pb.TagNumber(1)
  set subRouteUid($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSubRouteUid() => $_has(0);
  @$pb.TagNumber(1)
  void clearSubRouteUid() => $_clearField(1);

  @$pb.TagNumber(3)
  $pb.PbList<Bus_RouteEstimate> get stops => $_getList(1);
}

class Bus_StationArrival extends $pb.GeneratedMessage {
  factory Bus_StationArrival({
    $core.String? stationName,
    $core.Iterable<$core.String>? stationUid,
    $core.Iterable<Bus_StopEstimate>? routes,
  }) {
    final result = create();
    if (stationName != null) result.stationName = stationName;
    if (stationUid != null) result.stationUid.addAll(stationUid);
    if (routes != null) result.routes.addAll(routes);
    return result;
  }

  Bus_StationArrival._();

  factory Bus_StationArrival.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_StationArrival.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_StationArrival',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'stationName')
    ..pPS(2, _omitFieldNames ? '' : 'stationUid')
    ..pPM<Bus_StopEstimate>(3, _omitFieldNames ? '' : 'routes',
        subBuilder: Bus_StopEstimate.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_StationArrival clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_StationArrival copyWith(void Function(Bus_StationArrival) updates) =>
      super.copyWith((message) => updates(message as Bus_StationArrival))
          as Bus_StationArrival;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_StationArrival create() => Bus_StationArrival._();
  @$core.override
  Bus_StationArrival createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_StationArrival getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bus_StationArrival>(create);
  static Bus_StationArrival? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get stationName => $_getSZ(0);
  @$pb.TagNumber(1)
  set stationName($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStationName() => $_has(0);
  @$pb.TagNumber(1)
  void clearStationName() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get stationUid => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<Bus_StopEstimate> get routes => $_getList(2);
}

class Bus_RouteEstimate extends $pb.GeneratedMessage {
  factory Bus_RouteEstimate({
    $core.String? stopUid,
    $core.int? direction,
    $core.int? estimate,
    $core.String? nextBusTime,
    $core.int? stopStatus,
    $core.String? srcUpdateTime,
    $core.Iterable<Bus_position>? buses,
    $core.int? stopSequence,
    $fixnum.Int64? arrivalUnix,
  }) {
    final result = create();
    if (stopUid != null) result.stopUid = stopUid;
    if (direction != null) result.direction = direction;
    if (estimate != null) result.estimate = estimate;
    if (nextBusTime != null) result.nextBusTime = nextBusTime;
    if (stopStatus != null) result.stopStatus = stopStatus;
    if (srcUpdateTime != null) result.srcUpdateTime = srcUpdateTime;
    if (buses != null) result.buses.addAll(buses);
    if (stopSequence != null) result.stopSequence = stopSequence;
    if (arrivalUnix != null) result.arrivalUnix = arrivalUnix;
    return result;
  }

  Bus_RouteEstimate._();

  factory Bus_RouteEstimate.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_RouteEstimate.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_RouteEstimate',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'stopUid')
    ..aI(2, _omitFieldNames ? '' : 'direction')
    ..aI(3, _omitFieldNames ? '' : 'estimate')
    ..aOS(4, _omitFieldNames ? '' : 'NextBusTime', protoName: 'NextBusTime')
    ..aI(5, _omitFieldNames ? '' : 'StopStatus', protoName: 'Stop_status')
    ..aOS(6, _omitFieldNames ? '' : 'srcUpdateTime')
    ..pPM<Bus_position>(7, _omitFieldNames ? '' : 'Buses',
        protoName: 'Buses', subBuilder: Bus_position.create)
    ..aI(8, _omitFieldNames ? '' : 'StopSequence', protoName: 'StopSequence')
    ..aInt64(9, _omitFieldNames ? '' : 'arrivalUnix')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_RouteEstimate clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_RouteEstimate copyWith(void Function(Bus_RouteEstimate) updates) =>
      super.copyWith((message) => updates(message as Bus_RouteEstimate))
          as Bus_RouteEstimate;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_RouteEstimate create() => Bus_RouteEstimate._();
  @$core.override
  Bus_RouteEstimate createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_RouteEstimate getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bus_RouteEstimate>(create);
  static Bus_RouteEstimate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get stopUid => $_getSZ(0);
  @$pb.TagNumber(1)
  set stopUid($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStopUid() => $_has(0);
  @$pb.TagNumber(1)
  void clearStopUid() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get direction => $_getIZ(1);
  @$pb.TagNumber(2)
  set direction($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDirection() => $_has(1);
  @$pb.TagNumber(2)
  void clearDirection() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get estimate => $_getIZ(2);
  @$pb.TagNumber(3)
  set estimate($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEstimate() => $_has(2);
  @$pb.TagNumber(3)
  void clearEstimate() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get nextBusTime => $_getSZ(3);
  @$pb.TagNumber(4)
  set nextBusTime($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasNextBusTime() => $_has(3);
  @$pb.TagNumber(4)
  void clearNextBusTime() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get stopStatus => $_getIZ(4);
  @$pb.TagNumber(5)
  set stopStatus($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasStopStatus() => $_has(4);
  @$pb.TagNumber(5)
  void clearStopStatus() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get srcUpdateTime => $_getSZ(5);
  @$pb.TagNumber(6)
  set srcUpdateTime($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSrcUpdateTime() => $_has(5);
  @$pb.TagNumber(6)
  void clearSrcUpdateTime() => $_clearField(6);

  @$pb.TagNumber(7)
  $pb.PbList<Bus_position> get buses => $_getList(6);

  @$pb.TagNumber(8)
  $core.int get stopSequence => $_getIZ(7);
  @$pb.TagNumber(8)
  set stopSequence($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasStopSequence() => $_has(7);
  @$pb.TagNumber(8)
  void clearStopSequence() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get arrivalUnix => $_getI64(8);
  @$pb.TagNumber(9)
  set arrivalUnix($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasArrivalUnix() => $_has(8);
  @$pb.TagNumber(9)
  void clearArrivalUnix() => $_clearField(9);
}

class Bus_StopEstimate extends $pb.GeneratedMessage {
  factory Bus_StopEstimate({
    $core.String? stopUid,
    $core.String? subRouteUid,
    $core.String? routeName,
    $core.int? direction,
    $core.int? estimate,
    $core.String? nextBusTime,
    $core.int? stopStatus,
    $core.String? srcUpdateTime,
    $core.Iterable<Bus_position>? buses,
    $fixnum.Int64? arrivalUnix,
    $core.String? destination,
  }) {
    final result = create();
    if (stopUid != null) result.stopUid = stopUid;
    if (subRouteUid != null) result.subRouteUid = subRouteUid;
    if (routeName != null) result.routeName = routeName;
    if (direction != null) result.direction = direction;
    if (estimate != null) result.estimate = estimate;
    if (nextBusTime != null) result.nextBusTime = nextBusTime;
    if (stopStatus != null) result.stopStatus = stopStatus;
    if (srcUpdateTime != null) result.srcUpdateTime = srcUpdateTime;
    if (buses != null) result.buses.addAll(buses);
    if (arrivalUnix != null) result.arrivalUnix = arrivalUnix;
    if (destination != null) result.destination = destination;
    return result;
  }

  Bus_StopEstimate._();

  factory Bus_StopEstimate.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_StopEstimate.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_StopEstimate',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'stopUid')
    ..aOS(2, _omitFieldNames ? '' : 'subRouteUid')
    ..aOS(3, _omitFieldNames ? '' : 'routeName')
    ..aI(4, _omitFieldNames ? '' : 'Direction', protoName: 'Direction')
    ..aI(5, _omitFieldNames ? '' : 'estimate')
    ..aOS(6, _omitFieldNames ? '' : 'NextBusTime', protoName: 'NextBusTime')
    ..aI(7, _omitFieldNames ? '' : 'StopStatus', protoName: 'Stop_status')
    ..aOS(8, _omitFieldNames ? '' : 'srcUpdateTime')
    ..pPM<Bus_position>(9, _omitFieldNames ? '' : 'Buses',
        protoName: 'Buses', subBuilder: Bus_position.create)
    ..aInt64(10, _omitFieldNames ? '' : 'arrivalUnix')
    ..aOS(11, _omitFieldNames ? '' : 'destination')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_StopEstimate clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_StopEstimate copyWith(void Function(Bus_StopEstimate) updates) =>
      super.copyWith((message) => updates(message as Bus_StopEstimate))
          as Bus_StopEstimate;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_StopEstimate create() => Bus_StopEstimate._();
  @$core.override
  Bus_StopEstimate createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_StopEstimate getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bus_StopEstimate>(create);
  static Bus_StopEstimate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get stopUid => $_getSZ(0);
  @$pb.TagNumber(1)
  set stopUid($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStopUid() => $_has(0);
  @$pb.TagNumber(1)
  void clearStopUid() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get subRouteUid => $_getSZ(1);
  @$pb.TagNumber(2)
  set subRouteUid($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSubRouteUid() => $_has(1);
  @$pb.TagNumber(2)
  void clearSubRouteUid() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get routeName => $_getSZ(2);
  @$pb.TagNumber(3)
  set routeName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRouteName() => $_has(2);
  @$pb.TagNumber(3)
  void clearRouteName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get direction => $_getIZ(3);
  @$pb.TagNumber(4)
  set direction($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDirection() => $_has(3);
  @$pb.TagNumber(4)
  void clearDirection() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get estimate => $_getIZ(4);
  @$pb.TagNumber(5)
  set estimate($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEstimate() => $_has(4);
  @$pb.TagNumber(5)
  void clearEstimate() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get nextBusTime => $_getSZ(5);
  @$pb.TagNumber(6)
  set nextBusTime($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasNextBusTime() => $_has(5);
  @$pb.TagNumber(6)
  void clearNextBusTime() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get stopStatus => $_getIZ(6);
  @$pb.TagNumber(7)
  set stopStatus($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasStopStatus() => $_has(6);
  @$pb.TagNumber(7)
  void clearStopStatus() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get srcUpdateTime => $_getSZ(7);
  @$pb.TagNumber(8)
  set srcUpdateTime($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasSrcUpdateTime() => $_has(7);
  @$pb.TagNumber(8)
  void clearSrcUpdateTime() => $_clearField(8);

  @$pb.TagNumber(9)
  $pb.PbList<Bus_position> get buses => $_getList(8);

  @$pb.TagNumber(10)
  $fixnum.Int64 get arrivalUnix => $_getI64(9);
  @$pb.TagNumber(10)
  set arrivalUnix($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasArrivalUnix() => $_has(9);
  @$pb.TagNumber(10)
  void clearArrivalUnix() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get destination => $_getSZ(10);
  @$pb.TagNumber(11)
  set destination($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasDestination() => $_has(10);
  @$pb.TagNumber(11)
  void clearDestination() => $_clearField(11);
}

class Bus_position extends $pb.GeneratedMessage {
  factory Bus_position({
    $core.String? plateNumb,
    $core.double? positionLon,
    $core.double? positionLat,
    $core.int? speed,
    $core.int? azimuth,
    $core.int? dutyStatus,
    $core.int? busStatus,
    $fixnum.Int64? gpsTimeUnix,
  }) {
    final result = create();
    if (plateNumb != null) result.plateNumb = plateNumb;
    if (positionLon != null) result.positionLon = positionLon;
    if (positionLat != null) result.positionLat = positionLat;
    if (speed != null) result.speed = speed;
    if (azimuth != null) result.azimuth = azimuth;
    if (dutyStatus != null) result.dutyStatus = dutyStatus;
    if (busStatus != null) result.busStatus = busStatus;
    if (gpsTimeUnix != null) result.gpsTimeUnix = gpsTimeUnix;
    return result;
  }

  Bus_position._();

  factory Bus_position.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_position.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_position',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'plateNumb')
    ..aD(2, _omitFieldNames ? '' : 'positionLon')
    ..aD(3, _omitFieldNames ? '' : 'positionLat')
    ..aI(4, _omitFieldNames ? '' : 'speed')
    ..aI(5, _omitFieldNames ? '' : 'azimuth')
    ..aI(9, _omitFieldNames ? '' : 'dutyStatus')
    ..aI(10, _omitFieldNames ? '' : 'busStatus')
    ..aInt64(11, _omitFieldNames ? '' : 'gpsTimeUnix')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_position clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_position copyWith(void Function(Bus_position) updates) =>
      super.copyWith((message) => updates(message as Bus_position))
          as Bus_position;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_position create() => Bus_position._();
  @$core.override
  Bus_position createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_position getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bus_position>(create);
  static Bus_position? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get plateNumb => $_getSZ(0);
  @$pb.TagNumber(1)
  set plateNumb($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPlateNumb() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlateNumb() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get positionLon => $_getN(1);
  @$pb.TagNumber(2)
  set positionLon($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPositionLon() => $_has(1);
  @$pb.TagNumber(2)
  void clearPositionLon() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get positionLat => $_getN(2);
  @$pb.TagNumber(3)
  set positionLat($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPositionLat() => $_has(2);
  @$pb.TagNumber(3)
  void clearPositionLat() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get speed => $_getIZ(3);
  @$pb.TagNumber(4)
  set speed($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSpeed() => $_has(3);
  @$pb.TagNumber(4)
  void clearSpeed() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get azimuth => $_getIZ(4);
  @$pb.TagNumber(5)
  set azimuth($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAzimuth() => $_has(4);
  @$pb.TagNumber(5)
  void clearAzimuth() => $_clearField(5);

  @$pb.TagNumber(9)
  $core.int get dutyStatus => $_getIZ(5);
  @$pb.TagNumber(9)
  set dutyStatus($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(9)
  $core.bool hasDutyStatus() => $_has(5);
  @$pb.TagNumber(9)
  void clearDutyStatus() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get busStatus => $_getIZ(6);
  @$pb.TagNumber(10)
  set busStatus($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(10)
  $core.bool hasBusStatus() => $_has(6);
  @$pb.TagNumber(10)
  void clearBusStatus() => $_clearField(10);

  @$pb.TagNumber(11)
  $fixnum.Int64 get gpsTimeUnix => $_getI64(7);
  @$pb.TagNumber(11)
  set gpsTimeUnix($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(11)
  $core.bool hasGpsTimeUnix() => $_has(7);
  @$pb.TagNumber(11)
  void clearGpsTimeUnix() => $_clearField(11);
}

class Bus_Schedule extends $pb.GeneratedMessage {
  factory Bus_Schedule({
    $core.bool? isTimetable,
    $core.String? tripid,
    $core.bool? islowfloor,
    $core.String? startTime,
    $core.String? endTime,
    $core.String? minHeadwayMinsArrivalTime,
    $core.String? maxHeadwayMinsDepartureTime,
    $core.int? serviceDay,
  }) {
    final result = create();
    if (isTimetable != null) result.isTimetable = isTimetable;
    if (tripid != null) result.tripid = tripid;
    if (islowfloor != null) result.islowfloor = islowfloor;
    if (startTime != null) result.startTime = startTime;
    if (endTime != null) result.endTime = endTime;
    if (minHeadwayMinsArrivalTime != null)
      result.minHeadwayMinsArrivalTime = minHeadwayMinsArrivalTime;
    if (maxHeadwayMinsDepartureTime != null)
      result.maxHeadwayMinsDepartureTime = maxHeadwayMinsDepartureTime;
    if (serviceDay != null) result.serviceDay = serviceDay;
    return result;
  }

  Bus_Schedule._();

  factory Bus_Schedule.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_Schedule.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_Schedule',
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isTimetable')
    ..aOS(2, _omitFieldNames ? '' : 'tripid')
    ..aOB(3, _omitFieldNames ? '' : 'islowfloor')
    ..aOS(4, _omitFieldNames ? '' : 'startTime', protoName: 'start_Time')
    ..aOS(5, _omitFieldNames ? '' : 'endTime', protoName: 'end_Time')
    ..aOS(6, _omitFieldNames ? '' : 'MinHeadwayMinsArrivalTime',
        protoName: 'MinHeadwayMins_arrival_time')
    ..aOS(7, _omitFieldNames ? '' : 'MaxHeadwayMinsDepartureTime',
        protoName: 'MaxHeadwayMins_departure_time')
    ..aI(8, _omitFieldNames ? '' : 'serviceDay')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_Schedule clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_Schedule copyWith(void Function(Bus_Schedule) updates) =>
      super.copyWith((message) => updates(message as Bus_Schedule))
          as Bus_Schedule;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_Schedule create() => Bus_Schedule._();
  @$core.override
  Bus_Schedule createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_Schedule getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bus_Schedule>(create);
  static Bus_Schedule? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isTimetable => $_getBF(0);
  @$pb.TagNumber(1)
  set isTimetable($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIsTimetable() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsTimetable() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get tripid => $_getSZ(1);
  @$pb.TagNumber(2)
  set tripid($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTripid() => $_has(1);
  @$pb.TagNumber(2)
  void clearTripid() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get islowfloor => $_getBF(2);
  @$pb.TagNumber(3)
  set islowfloor($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIslowfloor() => $_has(2);
  @$pb.TagNumber(3)
  void clearIslowfloor() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get startTime => $_getSZ(3);
  @$pb.TagNumber(4)
  set startTime($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStartTime() => $_has(3);
  @$pb.TagNumber(4)
  void clearStartTime() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get endTime => $_getSZ(4);
  @$pb.TagNumber(5)
  set endTime($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEndTime() => $_has(4);
  @$pb.TagNumber(5)
  void clearEndTime() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get minHeadwayMinsArrivalTime => $_getSZ(5);
  @$pb.TagNumber(6)
  set minHeadwayMinsArrivalTime($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMinHeadwayMinsArrivalTime() => $_has(5);
  @$pb.TagNumber(6)
  void clearMinHeadwayMinsArrivalTime() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get maxHeadwayMinsDepartureTime => $_getSZ(6);
  @$pb.TagNumber(7)
  set maxHeadwayMinsDepartureTime($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasMaxHeadwayMinsDepartureTime() => $_has(6);
  @$pb.TagNumber(7)
  void clearMaxHeadwayMinsDepartureTime() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get serviceDay => $_getIZ(7);
  @$pb.TagNumber(8)
  set serviceDay($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasServiceDay() => $_has(7);
  @$pb.TagNumber(8)
  void clearServiceDay() => $_clearField(8);
}

class Bus_DailyTimetables extends $pb.GeneratedMessage {
  factory Bus_DailyTimetables({
    $core.String? subRouteUID,
    $core.Iterable<$core.MapEntry<$core.int, Bus_DirectionTimetable>>?
        direction,
  }) {
    final result = create();
    if (subRouteUID != null) result.subRouteUID = subRouteUID;
    if (direction != null) result.direction.addEntries(direction);
    return result;
  }

  Bus_DailyTimetables._();

  factory Bus_DailyTimetables.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_DailyTimetables.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_DailyTimetables',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'SubRouteUID', protoName: 'SubRouteUID')
    ..m<$core.int, Bus_DirectionTimetable>(
        3, _omitFieldNames ? '' : 'direction',
        entryClassName: 'Bus_DailyTimetables.DirectionEntry',
        keyFieldType: $pb.PbFieldType.O3,
        valueFieldType: $pb.PbFieldType.OM,
        valueCreator: Bus_DirectionTimetable.create,
        valueDefaultOrMaker: Bus_DirectionTimetable.getDefault)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_DailyTimetables clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_DailyTimetables copyWith(void Function(Bus_DailyTimetables) updates) =>
      super.copyWith((message) => updates(message as Bus_DailyTimetables))
          as Bus_DailyTimetables;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_DailyTimetables create() => Bus_DailyTimetables._();
  @$core.override
  Bus_DailyTimetables createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_DailyTimetables getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bus_DailyTimetables>(create);
  static Bus_DailyTimetables? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get subRouteUID => $_getSZ(0);
  @$pb.TagNumber(1)
  set subRouteUID($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSubRouteUID() => $_has(0);
  @$pb.TagNumber(1)
  void clearSubRouteUID() => $_clearField(1);

  @$pb.TagNumber(3)
  $pb.PbMap<$core.int, Bus_DirectionTimetable> get direction => $_getMap(1);
}

class Bus_DirectionTimetable extends $pb.GeneratedMessage {
  factory Bus_DirectionTimetable({
    $core.Iterable<Bus_DailyTimetable>? dailyTimetables,
  }) {
    final result = create();
    if (dailyTimetables != null) result.dailyTimetables.addAll(dailyTimetables);
    return result;
  }

  Bus_DirectionTimetable._();

  factory Bus_DirectionTimetable.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_DirectionTimetable.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_DirectionTimetable',
      createEmptyInstance: create)
    ..pPM<Bus_DailyTimetable>(1, _omitFieldNames ? '' : 'DailyTimetables',
        protoName: 'DailyTimetables', subBuilder: Bus_DailyTimetable.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_DirectionTimetable clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_DirectionTimetable copyWith(
          void Function(Bus_DirectionTimetable) updates) =>
      super.copyWith((message) => updates(message as Bus_DirectionTimetable))
          as Bus_DirectionTimetable;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_DirectionTimetable create() => Bus_DirectionTimetable._();
  @$core.override
  Bus_DirectionTimetable createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_DirectionTimetable getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bus_DirectionTimetable>(create);
  static Bus_DirectionTimetable? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Bus_DailyTimetable> get dailyTimetables => $_getList(0);
}

class Bus_DailyTimetable extends $pb.GeneratedMessage {
  factory Bus_DailyTimetable({
    $core.String? tripID,
    $core.bool? isLowFloor,
    $core.Iterable<Bus_StopTime>? stopTimes,
  }) {
    final result = create();
    if (tripID != null) result.tripID = tripID;
    if (isLowFloor != null) result.isLowFloor = isLowFloor;
    if (stopTimes != null) result.stopTimes.addAll(stopTimes);
    return result;
  }

  Bus_DailyTimetable._();

  factory Bus_DailyTimetable.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_DailyTimetable.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_DailyTimetable',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'TripID', protoName: 'TripID')
    ..aOB(2, _omitFieldNames ? '' : 'IsLowFloor', protoName: 'IsLowFloor')
    ..pPM<Bus_StopTime>(3, _omitFieldNames ? '' : 'StopTimes',
        protoName: 'StopTimes', subBuilder: Bus_StopTime.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_DailyTimetable clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_DailyTimetable copyWith(void Function(Bus_DailyTimetable) updates) =>
      super.copyWith((message) => updates(message as Bus_DailyTimetable))
          as Bus_DailyTimetable;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_DailyTimetable create() => Bus_DailyTimetable._();
  @$core.override
  Bus_DailyTimetable createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_DailyTimetable getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bus_DailyTimetable>(create);
  static Bus_DailyTimetable? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tripID => $_getSZ(0);
  @$pb.TagNumber(1)
  set tripID($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTripID() => $_has(0);
  @$pb.TagNumber(1)
  void clearTripID() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get isLowFloor => $_getBF(1);
  @$pb.TagNumber(2)
  set isLowFloor($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIsLowFloor() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsLowFloor() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<Bus_StopTime> get stopTimes => $_getList(2);
}

class Bus_StopTime extends $pb.GeneratedMessage {
  factory Bus_StopTime({
    $core.int? stopSequence,
    $core.String? arrivalTime,
    $core.String? departureTime,
    $core.String? stopUID,
  }) {
    final result = create();
    if (stopSequence != null) result.stopSequence = stopSequence;
    if (arrivalTime != null) result.arrivalTime = arrivalTime;
    if (departureTime != null) result.departureTime = departureTime;
    if (stopUID != null) result.stopUID = stopUID;
    return result;
  }

  Bus_StopTime._();

  factory Bus_StopTime.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_StopTime.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_StopTime',
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'StopSequence', protoName: 'StopSequence')
    ..aOS(2, _omitFieldNames ? '' : 'ArrivalTime', protoName: 'ArrivalTime')
    ..aOS(3, _omitFieldNames ? '' : 'DepartureTime', protoName: 'DepartureTime')
    ..aOS(4, _omitFieldNames ? '' : 'StopUID', protoName: 'StopUID')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_StopTime clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_StopTime copyWith(void Function(Bus_StopTime) updates) =>
      super.copyWith((message) => updates(message as Bus_StopTime))
          as Bus_StopTime;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_StopTime create() => Bus_StopTime._();
  @$core.override
  Bus_StopTime createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_StopTime getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bus_StopTime>(create);
  static Bus_StopTime? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get stopSequence => $_getIZ(0);
  @$pb.TagNumber(1)
  set stopSequence($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStopSequence() => $_has(0);
  @$pb.TagNumber(1)
  void clearStopSequence() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get arrivalTime => $_getSZ(1);
  @$pb.TagNumber(2)
  set arrivalTime($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasArrivalTime() => $_has(1);
  @$pb.TagNumber(2)
  void clearArrivalTime() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get departureTime => $_getSZ(2);
  @$pb.TagNumber(3)
  set departureTime($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDepartureTime() => $_has(2);
  @$pb.TagNumber(3)
  void clearDepartureTime() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get stopUID => $_getSZ(3);
  @$pb.TagNumber(4)
  set stopUID($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStopUID() => $_has(3);
  @$pb.TagNumber(4)
  void clearStopUID() => $_clearField(4);
}

class Bus_Fare extends $pb.GeneratedMessage {
  factory Bus_Fare({
    $core.int? farePricingType,
    $core.bool? isFreeBus,
    $core.List<$core.int>? sectionFaresJson,
    $core.List<$core.int>? stageFaresJson,
    $core.List<$core.int>? odFaresJson,
  }) {
    final result = create();
    if (farePricingType != null) result.farePricingType = farePricingType;
    if (isFreeBus != null) result.isFreeBus = isFreeBus;
    if (sectionFaresJson != null) result.sectionFaresJson = sectionFaresJson;
    if (stageFaresJson != null) result.stageFaresJson = stageFaresJson;
    if (odFaresJson != null) result.odFaresJson = odFaresJson;
    return result;
  }

  Bus_Fare._();

  factory Bus_Fare.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Bus_Fare.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bus_Fare',
      createEmptyInstance: create)
    ..aI(2, _omitFieldNames ? '' : 'farePricingType')
    ..aOB(3, _omitFieldNames ? '' : 'isFreeBus')
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'sectionFaresJson', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'stageFaresJson', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'odFaresJson', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_Fare clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bus_Fare copyWith(void Function(Bus_Fare) updates) =>
      super.copyWith((message) => updates(message as Bus_Fare)) as Bus_Fare;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Bus_Fare create() => Bus_Fare._();
  @$core.override
  Bus_Fare createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Bus_Fare getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Bus_Fare>(create);
  static Bus_Fare? _defaultInstance;

  @$pb.TagNumber(2)
  $core.int get farePricingType => $_getIZ(0);
  @$pb.TagNumber(2)
  set farePricingType($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(2)
  $core.bool hasFarePricingType() => $_has(0);
  @$pb.TagNumber(2)
  void clearFarePricingType() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get isFreeBus => $_getBF(1);
  @$pb.TagNumber(3)
  set isFreeBus($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(3)
  $core.bool hasIsFreeBus() => $_has(1);
  @$pb.TagNumber(3)
  void clearIsFreeBus() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get sectionFaresJson => $_getN(2);
  @$pb.TagNumber(4)
  set sectionFaresJson($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(4)
  $core.bool hasSectionFaresJson() => $_has(2);
  @$pb.TagNumber(4)
  void clearSectionFaresJson() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get stageFaresJson => $_getN(3);
  @$pb.TagNumber(5)
  set stageFaresJson($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(5)
  $core.bool hasStageFaresJson() => $_has(3);
  @$pb.TagNumber(5)
  void clearStageFaresJson() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get odFaresJson => $_getN(4);
  @$pb.TagNumber(6)
  set odFaresJson($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(6)
  $core.bool hasOdFaresJson() => $_has(4);
  @$pb.TagNumber(6)
  void clearOdFaresJson() => $_clearField(6);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
