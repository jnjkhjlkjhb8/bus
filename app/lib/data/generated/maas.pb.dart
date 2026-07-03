// This is a generated file - do not edit.
//
// Generated from maas.proto.

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

class MaasPlanRequest extends $pb.GeneratedMessage {
  factory MaasPlanRequest({
    $core.double? fromLat,
    $core.double? fromLon,
    $core.double? toLat,
    $core.double? toLon,
    $core.String? date,
    $core.String? time,
    $core.bool? arriveBy,
    $core.double? gc,
    $core.Iterable<$core.int>? transitModes,
  }) {
    final result = create();
    if (fromLat != null) result.fromLat = fromLat;
    if (fromLon != null) result.fromLon = fromLon;
    if (toLat != null) result.toLat = toLat;
    if (toLon != null) result.toLon = toLon;
    if (date != null) result.date = date;
    if (time != null) result.time = time;
    if (arriveBy != null) result.arriveBy = arriveBy;
    if (gc != null) result.gc = gc;
    if (transitModes != null) result.transitModes.addAll(transitModes);
    return result;
  }

  MaasPlanRequest._();

  factory MaasPlanRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MaasPlanRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MaasPlanRequest',
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'fromLat', protoName: 'fromLat')
    ..aD(2, _omitFieldNames ? '' : 'fromLon', protoName: 'fromLon')
    ..aD(3, _omitFieldNames ? '' : 'toLat', protoName: 'toLat')
    ..aD(4, _omitFieldNames ? '' : 'toLon', protoName: 'toLon')
    ..aOS(5, _omitFieldNames ? '' : 'date')
    ..aOS(6, _omitFieldNames ? '' : 'time')
    ..aOB(7, _omitFieldNames ? '' : 'arriveBy', protoName: 'arriveBy')
    ..aD(8, _omitFieldNames ? '' : 'gc')
    ..p<$core.int>(9, _omitFieldNames ? '' : 'transitModes', $pb.PbFieldType.K3,
        protoName: 'transitModes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MaasPlanRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MaasPlanRequest copyWith(void Function(MaasPlanRequest) updates) =>
      super.copyWith((message) => updates(message as MaasPlanRequest))
          as MaasPlanRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MaasPlanRequest create() => MaasPlanRequest._();
  @$core.override
  MaasPlanRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MaasPlanRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MaasPlanRequest>(create);
  static MaasPlanRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get fromLat => $_getN(0);
  @$pb.TagNumber(1)
  set fromLat($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFromLat() => $_has(0);
  @$pb.TagNumber(1)
  void clearFromLat() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get fromLon => $_getN(1);
  @$pb.TagNumber(2)
  set fromLon($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFromLon() => $_has(1);
  @$pb.TagNumber(2)
  void clearFromLon() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get toLat => $_getN(2);
  @$pb.TagNumber(3)
  set toLat($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasToLat() => $_has(2);
  @$pb.TagNumber(3)
  void clearToLat() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get toLon => $_getN(3);
  @$pb.TagNumber(4)
  set toLon($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasToLon() => $_has(3);
  @$pb.TagNumber(4)
  void clearToLon() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get date => $_getSZ(4);
  @$pb.TagNumber(5)
  set date($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDate() => $_has(4);
  @$pb.TagNumber(5)
  void clearDate() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get time => $_getSZ(5);
  @$pb.TagNumber(6)
  set time($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTime() => $_has(5);
  @$pb.TagNumber(6)
  void clearTime() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get arriveBy => $_getBF(6);
  @$pb.TagNumber(7)
  set arriveBy($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasArriveBy() => $_has(6);
  @$pb.TagNumber(7)
  void clearArriveBy() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.double get gc => $_getN(7);
  @$pb.TagNumber(8)
  set gc($core.double value) => $_setDouble(7, value);
  @$pb.TagNumber(8)
  $core.bool hasGc() => $_has(7);
  @$pb.TagNumber(8)
  void clearGc() => $_clearField(8);

  @$pb.TagNumber(9)
  $pb.PbList<$core.int> get transitModes => $_getList(8);
}

class MaasPlanResponse extends $pb.GeneratedMessage {
  factory MaasPlanResponse({
    $core.Iterable<Route>? routes,
  }) {
    final result = create();
    if (routes != null) result.routes.addAll(routes);
    return result;
  }

  MaasPlanResponse._();

  factory MaasPlanResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MaasPlanResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MaasPlanResponse',
      createEmptyInstance: create)
    ..pPM<Route>(1, _omitFieldNames ? '' : 'routes', subBuilder: Route.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MaasPlanResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MaasPlanResponse copyWith(void Function(MaasPlanResponse) updates) =>
      super.copyWith((message) => updates(message as MaasPlanResponse))
          as MaasPlanResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MaasPlanResponse create() => MaasPlanResponse._();
  @$core.override
  MaasPlanResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MaasPlanResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MaasPlanResponse>(create);
  static MaasPlanResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Route> get routes => $_getList(0);
}

class Route extends $pb.GeneratedMessage {
  factory Route({
    $fixnum.Int64? travelTime,
    $core.String? startTime,
    $core.String? endTime,
    $core.int? transfers,
    $core.Iterable<Section>? sections,
  }) {
    final result = create();
    if (travelTime != null) result.travelTime = travelTime;
    if (startTime != null) result.startTime = startTime;
    if (endTime != null) result.endTime = endTime;
    if (transfers != null) result.transfers = transfers;
    if (sections != null) result.sections.addAll(sections);
    return result;
  }

  Route._();

  factory Route.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Route.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Route',
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'travelTime', protoName: 'travelTime')
    ..aOS(2, _omitFieldNames ? '' : 'startTime', protoName: 'startTime')
    ..aOS(3, _omitFieldNames ? '' : 'endTime', protoName: 'endTime')
    ..aI(4, _omitFieldNames ? '' : 'transfers')
    ..pPM<Section>(5, _omitFieldNames ? '' : 'sections',
        subBuilder: Section.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Route clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Route copyWith(void Function(Route) updates) =>
      super.copyWith((message) => updates(message as Route)) as Route;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Route create() => Route._();
  @$core.override
  Route createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Route getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Route>(create);
  static Route? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get travelTime => $_getI64(0);
  @$pb.TagNumber(1)
  set travelTime($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTravelTime() => $_has(0);
  @$pb.TagNumber(1)
  void clearTravelTime() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get startTime => $_getSZ(1);
  @$pb.TagNumber(2)
  set startTime($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStartTime() => $_has(1);
  @$pb.TagNumber(2)
  void clearStartTime() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get endTime => $_getSZ(2);
  @$pb.TagNumber(3)
  set endTime($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEndTime() => $_has(2);
  @$pb.TagNumber(3)
  void clearEndTime() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get transfers => $_getIZ(3);
  @$pb.TagNumber(4)
  set transfers($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTransfers() => $_has(3);
  @$pb.TagNumber(4)
  void clearTransfers() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<Section> get sections => $_getList(4);
}

class Section extends $pb.GeneratedMessage {
  factory Section({
    $core.String? type,
    Summary? travelSummary,
    Place? departure,
    Place? arrival,
    Transport? transport,
    $core.Iterable<IntermediateStop>? intermediateStops,
    Agency? agency,
    NotificationIdentity? notificationIdentity,
  }) {
    final result = create();
    if (type != null) result.type = type;
    if (travelSummary != null) result.travelSummary = travelSummary;
    if (departure != null) result.departure = departure;
    if (arrival != null) result.arrival = arrival;
    if (transport != null) result.transport = transport;
    if (intermediateStops != null)
      result.intermediateStops.addAll(intermediateStops);
    if (agency != null) result.agency = agency;
    if (notificationIdentity != null)
      result.notificationIdentity = notificationIdentity;
    return result;
  }

  Section._();

  factory Section.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Section.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Section',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'type')
    ..aOM<Summary>(2, _omitFieldNames ? '' : 'travelSummary',
        protoName: 'travelSummary', subBuilder: Summary.create)
    ..aOM<Place>(3, _omitFieldNames ? '' : 'departure',
        subBuilder: Place.create)
    ..aOM<Place>(4, _omitFieldNames ? '' : 'arrival', subBuilder: Place.create)
    ..aOM<Transport>(5, _omitFieldNames ? '' : 'transport',
        subBuilder: Transport.create)
    ..pPM<IntermediateStop>(6, _omitFieldNames ? '' : 'intermediateStops',
        protoName: 'intermediateStops', subBuilder: IntermediateStop.create)
    ..aOM<Agency>(7, _omitFieldNames ? '' : 'agency', subBuilder: Agency.create)
    ..aOM<NotificationIdentity>(
        8, _omitFieldNames ? '' : 'notificationIdentity',
        subBuilder: NotificationIdentity.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Section clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Section copyWith(void Function(Section) updates) =>
      super.copyWith((message) => updates(message as Section)) as Section;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Section create() => Section._();
  @$core.override
  Section createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Section getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Section>(create);
  static Section? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get type => $_getSZ(0);
  @$pb.TagNumber(1)
  set type($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  @$pb.TagNumber(2)
  Summary get travelSummary => $_getN(1);
  @$pb.TagNumber(2)
  set travelSummary(Summary value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasTravelSummary() => $_has(1);
  @$pb.TagNumber(2)
  void clearTravelSummary() => $_clearField(2);
  @$pb.TagNumber(2)
  Summary ensureTravelSummary() => $_ensure(1);

  @$pb.TagNumber(3)
  Place get departure => $_getN(2);
  @$pb.TagNumber(3)
  set departure(Place value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasDeparture() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeparture() => $_clearField(3);
  @$pb.TagNumber(3)
  Place ensureDeparture() => $_ensure(2);

  @$pb.TagNumber(4)
  Place get arrival => $_getN(3);
  @$pb.TagNumber(4)
  set arrival(Place value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasArrival() => $_has(3);
  @$pb.TagNumber(4)
  void clearArrival() => $_clearField(4);
  @$pb.TagNumber(4)
  Place ensureArrival() => $_ensure(3);

  @$pb.TagNumber(5)
  Transport get transport => $_getN(4);
  @$pb.TagNumber(5)
  set transport(Transport value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasTransport() => $_has(4);
  @$pb.TagNumber(5)
  void clearTransport() => $_clearField(5);
  @$pb.TagNumber(5)
  Transport ensureTransport() => $_ensure(4);

  @$pb.TagNumber(6)
  $pb.PbList<IntermediateStop> get intermediateStops => $_getList(5);

  @$pb.TagNumber(7)
  Agency get agency => $_getN(6);
  @$pb.TagNumber(7)
  set agency(Agency value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasAgency() => $_has(6);
  @$pb.TagNumber(7)
  void clearAgency() => $_clearField(7);
  @$pb.TagNumber(7)
  Agency ensureAgency() => $_ensure(6);

  @$pb.TagNumber(8)
  NotificationIdentity get notificationIdentity => $_getN(7);
  @$pb.TagNumber(8)
  set notificationIdentity(NotificationIdentity value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasNotificationIdentity() => $_has(7);
  @$pb.TagNumber(8)
  void clearNotificationIdentity() => $_clearField(8);
  @$pb.TagNumber(8)
  NotificationIdentity ensureNotificationIdentity() => $_ensure(7);
}

class NotificationIdentity extends $pb.GeneratedMessage {
  factory NotificationIdentity({
    $core.String? routeType,
    $core.String? routeKey,
    $core.String? direction,
    $core.String? departureStopKey,
    $core.String? arrivalStopKey,
    $core.bool? supported,
  }) {
    final result = create();
    if (routeType != null) result.routeType = routeType;
    if (routeKey != null) result.routeKey = routeKey;
    if (direction != null) result.direction = direction;
    if (departureStopKey != null) result.departureStopKey = departureStopKey;
    if (arrivalStopKey != null) result.arrivalStopKey = arrivalStopKey;
    if (supported != null) result.supported = supported;
    return result;
  }

  NotificationIdentity._();

  factory NotificationIdentity.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory NotificationIdentity.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NotificationIdentity',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'routeType')
    ..aOS(2, _omitFieldNames ? '' : 'routeKey')
    ..aOS(3, _omitFieldNames ? '' : 'direction')
    ..aOS(4, _omitFieldNames ? '' : 'departureStopKey')
    ..aOS(5, _omitFieldNames ? '' : 'arrivalStopKey')
    ..aOB(6, _omitFieldNames ? '' : 'supported')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NotificationIdentity clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NotificationIdentity copyWith(void Function(NotificationIdentity) updates) =>
      super.copyWith((message) => updates(message as NotificationIdentity))
          as NotificationIdentity;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static NotificationIdentity create() => NotificationIdentity._();
  @$core.override
  NotificationIdentity createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static NotificationIdentity getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NotificationIdentity>(create);
  static NotificationIdentity? _defaultInstance;

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

  @$pb.TagNumber(3)
  $core.String get direction => $_getSZ(2);
  @$pb.TagNumber(3)
  set direction($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDirection() => $_has(2);
  @$pb.TagNumber(3)
  void clearDirection() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get departureStopKey => $_getSZ(3);
  @$pb.TagNumber(4)
  set departureStopKey($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDepartureStopKey() => $_has(3);
  @$pb.TagNumber(4)
  void clearDepartureStopKey() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get arrivalStopKey => $_getSZ(4);
  @$pb.TagNumber(5)
  set arrivalStopKey($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasArrivalStopKey() => $_has(4);
  @$pb.TagNumber(5)
  void clearArrivalStopKey() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get supported => $_getBF(5);
  @$pb.TagNumber(6)
  set supported($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSupported() => $_has(5);
  @$pb.TagNumber(6)
  void clearSupported() => $_clearField(6);
}

class Summary extends $pb.GeneratedMessage {
  factory Summary({
    $fixnum.Int64? duration,
    $core.double? length,
  }) {
    final result = create();
    if (duration != null) result.duration = duration;
    if (length != null) result.length = length;
    return result;
  }

  Summary._();

  factory Summary.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Summary.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Summary',
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'duration')
    ..aD(2, _omitFieldNames ? '' : 'length')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Summary clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Summary copyWith(void Function(Summary) updates) =>
      super.copyWith((message) => updates(message as Summary)) as Summary;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Summary create() => Summary._();
  @$core.override
  Summary createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Summary getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Summary>(create);
  static Summary? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get duration => $_getI64(0);
  @$pb.TagNumber(1)
  set duration($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDuration() => $_has(0);
  @$pb.TagNumber(1)
  void clearDuration() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get length => $_getN(1);
  @$pb.TagNumber(2)
  set length($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLength() => $_has(1);
  @$pb.TagNumber(2)
  void clearLength() => $_clearField(2);
}

class Place extends $pb.GeneratedMessage {
  factory Place({
    $core.String? name,
    $core.String? type,
    Location? location,
    $core.String? time,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (type != null) result.type = type;
    if (location != null) result.location = location;
    if (time != null) result.time = time;
    return result;
  }

  Place._();

  factory Place.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Place.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Place',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'type')
    ..aOM<Location>(3, _omitFieldNames ? '' : 'location',
        subBuilder: Location.create)
    ..aOS(4, _omitFieldNames ? '' : 'time')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Place clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Place copyWith(void Function(Place) updates) =>
      super.copyWith((message) => updates(message as Place)) as Place;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Place create() => Place._();
  @$core.override
  Place createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Place getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Place>(create);
  static Place? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get type => $_getSZ(1);
  @$pb.TagNumber(2)
  set type($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => $_clearField(2);

  @$pb.TagNumber(3)
  Location get location => $_getN(2);
  @$pb.TagNumber(3)
  set location(Location value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasLocation() => $_has(2);
  @$pb.TagNumber(3)
  void clearLocation() => $_clearField(3);
  @$pb.TagNumber(3)
  Location ensureLocation() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get time => $_getSZ(3);
  @$pb.TagNumber(4)
  set time($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTime() => $_has(3);
  @$pb.TagNumber(4)
  void clearTime() => $_clearField(4);
}

class Location extends $pb.GeneratedMessage {
  factory Location({
    $core.double? lat,
    $core.double? lng,
  }) {
    final result = create();
    if (lat != null) result.lat = lat;
    if (lng != null) result.lng = lng;
    return result;
  }

  Location._();

  factory Location.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Location.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Location',
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'lat')
    ..aD(2, _omitFieldNames ? '' : 'lng')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Location clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Location copyWith(void Function(Location) updates) =>
      super.copyWith((message) => updates(message as Location)) as Location;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Location create() => Location._();
  @$core.override
  Location createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Location getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Location>(create);
  static Location? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get lat => $_getN(0);
  @$pb.TagNumber(1)
  set lat($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLat() => $_has(0);
  @$pb.TagNumber(1)
  void clearLat() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get lng => $_getN(1);
  @$pb.TagNumber(2)
  set lng($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLng() => $_has(1);
  @$pb.TagNumber(2)
  void clearLng() => $_clearField(2);
}

class Transport extends $pb.GeneratedMessage {
  factory Transport({
    $core.String? mode,
    $core.String? name,
    $core.String? shortName,
    $core.String? longName,
    $core.String? headsign,
    $core.String? category,
    $core.String? routeColor,
  }) {
    final result = create();
    if (mode != null) result.mode = mode;
    if (name != null) result.name = name;
    if (shortName != null) result.shortName = shortName;
    if (longName != null) result.longName = longName;
    if (headsign != null) result.headsign = headsign;
    if (category != null) result.category = category;
    if (routeColor != null) result.routeColor = routeColor;
    return result;
  }

  Transport._();

  factory Transport.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Transport.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Transport',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'mode')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'shortName', protoName: 'shortName')
    ..aOS(4, _omitFieldNames ? '' : 'longName', protoName: 'longName')
    ..aOS(5, _omitFieldNames ? '' : 'headsign')
    ..aOS(6, _omitFieldNames ? '' : 'category')
    ..aOS(7, _omitFieldNames ? '' : 'routeColor', protoName: 'routeColor')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Transport clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Transport copyWith(void Function(Transport) updates) =>
      super.copyWith((message) => updates(message as Transport)) as Transport;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Transport create() => Transport._();
  @$core.override
  Transport createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Transport getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Transport>(create);
  static Transport? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get mode => $_getSZ(0);
  @$pb.TagNumber(1)
  set mode($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMode() => $_has(0);
  @$pb.TagNumber(1)
  void clearMode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get shortName => $_getSZ(2);
  @$pb.TagNumber(3)
  set shortName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasShortName() => $_has(2);
  @$pb.TagNumber(3)
  void clearShortName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get longName => $_getSZ(3);
  @$pb.TagNumber(4)
  set longName($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLongName() => $_has(3);
  @$pb.TagNumber(4)
  void clearLongName() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get headsign => $_getSZ(4);
  @$pb.TagNumber(5)
  set headsign($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasHeadsign() => $_has(4);
  @$pb.TagNumber(5)
  void clearHeadsign() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get category => $_getSZ(5);
  @$pb.TagNumber(6)
  set category($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCategory() => $_has(5);
  @$pb.TagNumber(6)
  void clearCategory() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get routeColor => $_getSZ(6);
  @$pb.TagNumber(7)
  set routeColor($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasRouteColor() => $_has(6);
  @$pb.TagNumber(7)
  void clearRouteColor() => $_clearField(7);
}

class IntermediateStop extends $pb.GeneratedMessage {
  factory IntermediateStop({
    $core.String? name,
    Location? location,
    $core.String? departureTime,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (location != null) result.location = location;
    if (departureTime != null) result.departureTime = departureTime;
    return result;
  }

  IntermediateStop._();

  factory IntermediateStop.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory IntermediateStop.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'IntermediateStop',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOM<Location>(2, _omitFieldNames ? '' : 'location',
        subBuilder: Location.create)
    ..aOS(3, _omitFieldNames ? '' : 'departureTime', protoName: 'departureTime')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  IntermediateStop clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  IntermediateStop copyWith(void Function(IntermediateStop) updates) =>
      super.copyWith((message) => updates(message as IntermediateStop))
          as IntermediateStop;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static IntermediateStop create() => IntermediateStop._();
  @$core.override
  IntermediateStop createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static IntermediateStop getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<IntermediateStop>(create);
  static IntermediateStop? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  Location get location => $_getN(1);
  @$pb.TagNumber(2)
  set location(Location value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasLocation() => $_has(1);
  @$pb.TagNumber(2)
  void clearLocation() => $_clearField(2);
  @$pb.TagNumber(2)
  Location ensureLocation() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get departureTime => $_getSZ(2);
  @$pb.TagNumber(3)
  set departureTime($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDepartureTime() => $_has(2);
  @$pb.TagNumber(3)
  void clearDepartureTime() => $_clearField(3);
}

class Agency extends $pb.GeneratedMessage {
  factory Agency({
    $core.String? agencyId,
    $core.String? name,
    $core.String? website,
    $core.String? phone,
  }) {
    final result = create();
    if (agencyId != null) result.agencyId = agencyId;
    if (name != null) result.name = name;
    if (website != null) result.website = website;
    if (phone != null) result.phone = phone;
    return result;
  }

  Agency._();

  factory Agency.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Agency.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Agency',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'agencyId', protoName: 'agencyId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'website')
    ..aOS(4, _omitFieldNames ? '' : 'phone')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Agency clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Agency copyWith(void Function(Agency) updates) =>
      super.copyWith((message) => updates(message as Agency)) as Agency;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Agency create() => Agency._();
  @$core.override
  Agency createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Agency getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Agency>(create);
  static Agency? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get agencyId => $_getSZ(0);
  @$pb.TagNumber(1)
  set agencyId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAgencyId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAgencyId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get website => $_getSZ(2);
  @$pb.TagNumber(3)
  set website($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasWebsite() => $_has(2);
  @$pb.TagNumber(3)
  void clearWebsite() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get phone => $_getSZ(3);
  @$pb.TagNumber(4)
  set phone($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPhone() => $_has(3);
  @$pb.TagNumber(4)
  void clearPhone() => $_clearField(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
