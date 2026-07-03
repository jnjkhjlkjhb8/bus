// This is a generated file - do not edit.
//
// Generated from tra.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class Resp_tra_live_board extends $pb.GeneratedMessage {
  factory Resp_tra_live_board({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  Resp_tra_live_board._();

  factory Resp_tra_live_board.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Resp_tra_live_board.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Resp_tra_live_board',
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_tra_live_board clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_tra_live_board copyWith(void Function(Resp_tra_live_board) updates) =>
      super.copyWith((message) => updates(message as Resp_tra_live_board))
          as Resp_tra_live_board;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Resp_tra_live_board create() => Resp_tra_live_board._();
  @$core.override
  Resp_tra_live_board createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Resp_tra_live_board getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Resp_tra_live_board>(create);
  static Resp_tra_live_board? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

class Resp_tra_delay extends $pb.GeneratedMessage {
  factory Resp_tra_delay({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  Resp_tra_delay._();

  factory Resp_tra_delay.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Resp_tra_delay.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Resp_tra_delay',
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_tra_delay clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_tra_delay copyWith(void Function(Resp_tra_delay) updates) =>
      super.copyWith((message) => updates(message as Resp_tra_delay))
          as Resp_tra_delay;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Resp_tra_delay create() => Resp_tra_delay._();
  @$core.override
  Resp_tra_delay createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Resp_tra_delay getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Resp_tra_delay>(create);
  static Resp_tra_delay? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

class ask_detain extends $pb.GeneratedMessage {
  factory ask_detain({
    $core.String? date,
    $core.String? trainno,
  }) {
    final result = create();
    if (date != null) result.date = date;
    if (trainno != null) result.trainno = trainno;
    return result;
  }

  ask_detain._();

  factory ask_detain.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ask_detain.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ask_detain',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'date')
    ..aOS(2, _omitFieldNames ? '' : 'trainno')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ask_detain clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ask_detain copyWith(void Function(ask_detain) updates) =>
      super.copyWith((message) => updates(message as ask_detain)) as ask_detain;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ask_detain create() => ask_detain._();
  @$core.override
  ask_detain createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ask_detain getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ask_detain>(create);
  static ask_detain? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get date => $_getSZ(0);
  @$pb.TagNumber(1)
  set date($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDate() => $_has(0);
  @$pb.TagNumber(1)
  void clearDate() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get trainno => $_getSZ(1);
  @$pb.TagNumber(2)
  set trainno($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTrainno() => $_has(1);
  @$pb.TagNumber(2)
  void clearTrainno() => $_clearField(2);
}

class ask_route extends $pb.GeneratedMessage {
  factory ask_route({
    $core.String? date,
    $core.String? originStationId,
    $core.String? destinationStationId,
  }) {
    final result = create();
    if (date != null) result.date = date;
    if (originStationId != null) result.originStationId = originStationId;
    if (destinationStationId != null)
      result.destinationStationId = destinationStationId;
    return result;
  }

  ask_route._();

  factory ask_route.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ask_route.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ask_route',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'date')
    ..aOS(2, _omitFieldNames ? '' : 'originStationId')
    ..aOS(3, _omitFieldNames ? '' : 'destinationStationId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ask_route clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ask_route copyWith(void Function(ask_route) updates) =>
      super.copyWith((message) => updates(message as ask_route)) as ask_route;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ask_route create() => ask_route._();
  @$core.override
  ask_route createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ask_route getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ask_route>(create);
  static ask_route? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get date => $_getSZ(0);
  @$pb.TagNumber(1)
  set date($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDate() => $_has(0);
  @$pb.TagNumber(1)
  void clearDate() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get originStationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set originStationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOriginStationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearOriginStationId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get destinationStationId => $_getSZ(2);
  @$pb.TagNumber(3)
  set destinationStationId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDestinationStationId() => $_has(2);
  @$pb.TagNumber(3)
  void clearDestinationStationId() => $_clearField(3);
}

class ask_staiton extends $pb.GeneratedMessage {
  factory ask_staiton({
    $core.String? stationId,
    $core.String? date,
  }) {
    final result = create();
    if (stationId != null) result.stationId = stationId;
    if (date != null) result.date = date;
    return result;
  }

  ask_staiton._();

  factory ask_staiton.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ask_staiton.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ask_staiton',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'stationId')
    ..aOS(2, _omitFieldNames ? '' : 'date')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ask_staiton clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ask_staiton copyWith(void Function(ask_staiton) updates) =>
      super.copyWith((message) => updates(message as ask_staiton))
          as ask_staiton;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ask_staiton create() => ask_staiton._();
  @$core.override
  ask_staiton createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ask_staiton getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ask_staiton>(create);
  static ask_staiton? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get stationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set stationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearStationId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get date => $_getSZ(1);
  @$pb.TagNumber(2)
  set date($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDate() => $_has(1);
  @$pb.TagNumber(2)
  void clearDate() => $_clearField(2);
}

class TraFareItem extends $pb.GeneratedMessage {
  factory TraFareItem({
    $core.String? originStationId,
    $core.String? destinationStationId,
    $core.String? ticketType,
    $core.int? price,
  }) {
    final result = create();
    if (originStationId != null) result.originStationId = originStationId;
    if (destinationStationId != null)
      result.destinationStationId = destinationStationId;
    if (ticketType != null) result.ticketType = ticketType;
    if (price != null) result.price = price;
    return result;
  }

  TraFareItem._();

  factory TraFareItem.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TraFareItem.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TraFareItem',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'originStationId')
    ..aOS(2, _omitFieldNames ? '' : 'destinationStationId')
    ..aOS(3, _omitFieldNames ? '' : 'ticketType')
    ..aI(4, _omitFieldNames ? '' : 'price')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TraFareItem clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TraFareItem copyWith(void Function(TraFareItem) updates) =>
      super.copyWith((message) => updates(message as TraFareItem))
          as TraFareItem;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TraFareItem create() => TraFareItem._();
  @$core.override
  TraFareItem createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TraFareItem getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TraFareItem>(create);
  static TraFareItem? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get originStationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set originStationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOriginStationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOriginStationId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get destinationStationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set destinationStationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDestinationStationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDestinationStationId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get ticketType => $_getSZ(2);
  @$pb.TagNumber(3)
  set ticketType($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTicketType() => $_has(2);
  @$pb.TagNumber(3)
  void clearTicketType() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get price => $_getIZ(3);
  @$pb.TagNumber(4)
  set price($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPrice() => $_has(3);
  @$pb.TagNumber(4)
  void clearPrice() => $_clearField(4);
}

class tra_fare_items extends $pb.GeneratedMessage {
  factory tra_fare_items({
    $core.Iterable<TraFareItem>? items,
  }) {
    final result = create();
    if (items != null) result.items.addAll(items);
    return result;
  }

  tra_fare_items._();

  factory tra_fare_items.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory tra_fare_items.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'tra_fare_items',
      createEmptyInstance: create)
    ..pPM<TraFareItem>(1, _omitFieldNames ? '' : 'items',
        subBuilder: TraFareItem.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_fare_items clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_fare_items copyWith(void Function(tra_fare_items) updates) =>
      super.copyWith((message) => updates(message as tra_fare_items))
          as tra_fare_items;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static tra_fare_items create() => tra_fare_items._();
  @$core.override
  tra_fare_items createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static tra_fare_items getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<tra_fare_items>(create);
  static tra_fare_items? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<TraFareItem> get items => $_getList(0);
}

class tra_timetables extends $pb.GeneratedMessage {
  factory tra_timetables({
    $core.Iterable<tra_timetable>? items,
  }) {
    final result = create();
    if (items != null) result.items.addAll(items);
    return result;
  }

  tra_timetables._();

  factory tra_timetables.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory tra_timetables.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'tra_timetables',
      createEmptyInstance: create)
    ..pPM<tra_timetable>(1, _omitFieldNames ? '' : 'items',
        subBuilder: tra_timetable.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_timetables clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_timetables copyWith(void Function(tra_timetables) updates) =>
      super.copyWith((message) => updates(message as tra_timetables))
          as tra_timetables;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static tra_timetables create() => tra_timetables._();
  @$core.override
  tra_timetables createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static tra_timetables getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<tra_timetables>(create);
  static tra_timetables? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<tra_timetable> get items => $_getList(0);
}

class tra_stoptimes extends $pb.GeneratedMessage {
  factory tra_stoptimes({
    $core.Iterable<tra_stoptime>? items,
  }) {
    final result = create();
    if (items != null) result.items.addAll(items);
    return result;
  }

  tra_stoptimes._();

  factory tra_stoptimes.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory tra_stoptimes.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'tra_stoptimes',
      createEmptyInstance: create)
    ..pPM<tra_stoptime>(1, _omitFieldNames ? '' : 'items',
        subBuilder: tra_stoptime.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_stoptimes clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_stoptimes copyWith(void Function(tra_stoptimes) updates) =>
      super.copyWith((message) => updates(message as tra_stoptimes))
          as tra_stoptimes;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static tra_stoptimes create() => tra_stoptimes._();
  @$core.override
  tra_stoptimes createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static tra_stoptimes getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<tra_stoptimes>(create);
  static tra_stoptimes? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<tra_stoptime> get items => $_getList(0);
}

class tra_delays extends $pb.GeneratedMessage {
  factory tra_delays({
    $core.Iterable<$core.MapEntry<$core.String, $core.int>>? delay,
  }) {
    final result = create();
    if (delay != null) result.delay.addEntries(delay);
    return result;
  }

  tra_delays._();

  factory tra_delays.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory tra_delays.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'tra_delays',
      createEmptyInstance: create)
    ..m<$core.String, $core.int>(1, _omitFieldNames ? '' : 'delay',
        entryClassName: 'tra_delays.DelayEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.O3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_delays clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_delays copyWith(void Function(tra_delays) updates) =>
      super.copyWith((message) => updates(message as tra_delays)) as tra_delays;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static tra_delays create() => tra_delays._();
  @$core.override
  tra_delays createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static tra_delays getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<tra_delays>(create);
  static tra_delays? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbMap<$core.String, $core.int> get delay => $_getMap(0);
}

class tra_stoptime extends $pb.GeneratedMessage {
  factory tra_stoptime({
    $core.String? stationId,
    $core.String? stationName,
    $core.int? stopSequence,
    $core.String? arrivalTime,
    $core.String? departureTime,
    $core.bool? suspendedFlag,
  }) {
    final result = create();
    if (stationId != null) result.stationId = stationId;
    if (stationName != null) result.stationName = stationName;
    if (stopSequence != null) result.stopSequence = stopSequence;
    if (arrivalTime != null) result.arrivalTime = arrivalTime;
    if (departureTime != null) result.departureTime = departureTime;
    if (suspendedFlag != null) result.suspendedFlag = suspendedFlag;
    return result;
  }

  tra_stoptime._();

  factory tra_stoptime.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory tra_stoptime.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'tra_stoptime',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'stationId')
    ..aOS(2, _omitFieldNames ? '' : 'stationName')
    ..aI(3, _omitFieldNames ? '' : 'stopSequence')
    ..aOS(4, _omitFieldNames ? '' : 'ArrivalTime', protoName: 'ArrivalTime')
    ..aOS(5, _omitFieldNames ? '' : 'DepartureTime', protoName: 'DepartureTime')
    ..aOB(6, _omitFieldNames ? '' : 'SuspendedFlag', protoName: 'SuspendedFlag')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_stoptime clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_stoptime copyWith(void Function(tra_stoptime) updates) =>
      super.copyWith((message) => updates(message as tra_stoptime))
          as tra_stoptime;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static tra_stoptime create() => tra_stoptime._();
  @$core.override
  tra_stoptime createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static tra_stoptime getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<tra_stoptime>(create);
  static tra_stoptime? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get stationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set stationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearStationId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get stationName => $_getSZ(1);
  @$pb.TagNumber(2)
  set stationName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStationName() => $_has(1);
  @$pb.TagNumber(2)
  void clearStationName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get stopSequence => $_getIZ(2);
  @$pb.TagNumber(3)
  set stopSequence($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStopSequence() => $_has(2);
  @$pb.TagNumber(3)
  void clearStopSequence() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get arrivalTime => $_getSZ(3);
  @$pb.TagNumber(4)
  set arrivalTime($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasArrivalTime() => $_has(3);
  @$pb.TagNumber(4)
  void clearArrivalTime() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get departureTime => $_getSZ(4);
  @$pb.TagNumber(5)
  set departureTime($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDepartureTime() => $_has(4);
  @$pb.TagNumber(5)
  void clearDepartureTime() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get suspendedFlag => $_getBF(5);
  @$pb.TagNumber(6)
  set suspendedFlag($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSuspendedFlag() => $_has(5);
  @$pb.TagNumber(6)
  void clearSuspendedFlag() => $_clearField(6);
}

class tra_timetable extends $pb.GeneratedMessage {
  factory tra_timetable({
    $core.String? trainDate,
    $core.String? trainNo,
    $core.int? direction,
    $core.String? startingStationName,
    $core.String? endingStationName,
    $core.String? trainTypeID,
    $core.String? trainTypeCode,
    $core.String? trainTypeName,
    $core.int? tripLine,
    $core.int? mask,
    $core.String? note,
    $core.String? startingTime,
    $core.String? endingTime,
    $core.String? travelTime,
  }) {
    final result = create();
    if (trainDate != null) result.trainDate = trainDate;
    if (trainNo != null) result.trainNo = trainNo;
    if (direction != null) result.direction = direction;
    if (startingStationName != null)
      result.startingStationName = startingStationName;
    if (endingStationName != null) result.endingStationName = endingStationName;
    if (trainTypeID != null) result.trainTypeID = trainTypeID;
    if (trainTypeCode != null) result.trainTypeCode = trainTypeCode;
    if (trainTypeName != null) result.trainTypeName = trainTypeName;
    if (tripLine != null) result.tripLine = tripLine;
    if (mask != null) result.mask = mask;
    if (note != null) result.note = note;
    if (startingTime != null) result.startingTime = startingTime;
    if (endingTime != null) result.endingTime = endingTime;
    if (travelTime != null) result.travelTime = travelTime;
    return result;
  }

  tra_timetable._();

  factory tra_timetable.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory tra_timetable.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'tra_timetable',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'TrainDate', protoName: 'TrainDate')
    ..aOS(2, _omitFieldNames ? '' : 'TrainNo', protoName: 'TrainNo')
    ..aI(3, _omitFieldNames ? '' : 'Direction', protoName: 'Direction')
    ..aOS(4, _omitFieldNames ? '' : 'StartingStationName',
        protoName: 'Starting_Station_Name')
    ..aOS(5, _omitFieldNames ? '' : 'EndingStationName',
        protoName: 'Ending_Station_Name')
    ..aOS(6, _omitFieldNames ? '' : 'TrainTypeID', protoName: 'TrainTypeID')
    ..aOS(7, _omitFieldNames ? '' : 'TrainTypeCode', protoName: 'TrainTypeCode')
    ..aOS(8, _omitFieldNames ? '' : 'TrainTypeName', protoName: 'TrainTypeName')
    ..aI(9, _omitFieldNames ? '' : 'TripLine', protoName: 'TripLine')
    ..aI(10, _omitFieldNames ? '' : 'mask')
    ..aOS(11, _omitFieldNames ? '' : 'Note', protoName: 'Note')
    ..aOS(12, _omitFieldNames ? '' : 'StartingTime', protoName: 'Starting_Time')
    ..aOS(13, _omitFieldNames ? '' : 'EndingTime', protoName: 'Ending_Time')
    ..aOS(14, _omitFieldNames ? '' : 'TravelTime', protoName: 'Travel_Time')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_timetable clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_timetable copyWith(void Function(tra_timetable) updates) =>
      super.copyWith((message) => updates(message as tra_timetable))
          as tra_timetable;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static tra_timetable create() => tra_timetable._();
  @$core.override
  tra_timetable createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static tra_timetable getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<tra_timetable>(create);
  static tra_timetable? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get trainDate => $_getSZ(0);
  @$pb.TagNumber(1)
  set trainDate($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTrainDate() => $_has(0);
  @$pb.TagNumber(1)
  void clearTrainDate() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get trainNo => $_getSZ(1);
  @$pb.TagNumber(2)
  set trainNo($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTrainNo() => $_has(1);
  @$pb.TagNumber(2)
  void clearTrainNo() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get direction => $_getIZ(2);
  @$pb.TagNumber(3)
  set direction($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDirection() => $_has(2);
  @$pb.TagNumber(3)
  void clearDirection() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get startingStationName => $_getSZ(3);
  @$pb.TagNumber(4)
  set startingStationName($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStartingStationName() => $_has(3);
  @$pb.TagNumber(4)
  void clearStartingStationName() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get endingStationName => $_getSZ(4);
  @$pb.TagNumber(5)
  set endingStationName($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEndingStationName() => $_has(4);
  @$pb.TagNumber(5)
  void clearEndingStationName() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get trainTypeID => $_getSZ(5);
  @$pb.TagNumber(6)
  set trainTypeID($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTrainTypeID() => $_has(5);
  @$pb.TagNumber(6)
  void clearTrainTypeID() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get trainTypeCode => $_getSZ(6);
  @$pb.TagNumber(7)
  set trainTypeCode($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTrainTypeCode() => $_has(6);
  @$pb.TagNumber(7)
  void clearTrainTypeCode() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get trainTypeName => $_getSZ(7);
  @$pb.TagNumber(8)
  set trainTypeName($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTrainTypeName() => $_has(7);
  @$pb.TagNumber(8)
  void clearTrainTypeName() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get tripLine => $_getIZ(8);
  @$pb.TagNumber(9)
  set tripLine($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasTripLine() => $_has(8);
  @$pb.TagNumber(9)
  void clearTripLine() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get mask => $_getIZ(9);
  @$pb.TagNumber(10)
  set mask($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasMask() => $_has(9);
  @$pb.TagNumber(10)
  void clearMask() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get note => $_getSZ(10);
  @$pb.TagNumber(11)
  set note($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasNote() => $_has(10);
  @$pb.TagNumber(11)
  void clearNote() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get startingTime => $_getSZ(11);
  @$pb.TagNumber(12)
  set startingTime($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasStartingTime() => $_has(11);
  @$pb.TagNumber(12)
  void clearStartingTime() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get endingTime => $_getSZ(12);
  @$pb.TagNumber(13)
  set endingTime($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasEndingTime() => $_has(12);
  @$pb.TagNumber(13)
  void clearEndingTime() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get travelTime => $_getSZ(13);
  @$pb.TagNumber(14)
  set travelTime($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasTravelTime() => $_has(13);
  @$pb.TagNumber(14)
  void clearTravelTime() => $_clearField(14);
}

class tra_delay extends $pb.GeneratedMessage {
  factory tra_delay({
    $core.String? trainNo,
    $core.String? stationId,
    $core.int? delay,
  }) {
    final result = create();
    if (trainNo != null) result.trainNo = trainNo;
    if (stationId != null) result.stationId = stationId;
    if (delay != null) result.delay = delay;
    return result;
  }

  tra_delay._();

  factory tra_delay.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory tra_delay.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'tra_delay',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'trainNo')
    ..aOS(2, _omitFieldNames ? '' : 'stationId')
    ..aI(3, _omitFieldNames ? '' : 'delay')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_delay clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_delay copyWith(void Function(tra_delay) updates) =>
      super.copyWith((message) => updates(message as tra_delay)) as tra_delay;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static tra_delay create() => tra_delay._();
  @$core.override
  tra_delay createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static tra_delay getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<tra_delay>(create);
  static tra_delay? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get trainNo => $_getSZ(0);
  @$pb.TagNumber(1)
  set trainNo($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTrainNo() => $_has(0);
  @$pb.TagNumber(1)
  void clearTrainNo() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get stationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set stationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearStationId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get delay => $_getIZ(2);
  @$pb.TagNumber(3)
  set delay($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDelay() => $_has(2);
  @$pb.TagNumber(3)
  void clearDelay() => $_clearField(3);
}

class tra_LiveBoard extends $pb.GeneratedMessage {
  factory tra_LiveBoard({
    $core.String? trainNo,
    $core.bool? direction,
    $core.String? trainTypeId,
    $core.String? trainTypeCode,
    $core.String? trainTypeName,
    $core.String? endingStationId,
    $core.String? endingStationName,
    $core.String? scheduledArrivalTime,
    $core.String? scheduledDepartureTime,
    $core.int? delay,
    $core.int? tripLine,
  }) {
    final result = create();
    if (trainNo != null) result.trainNo = trainNo;
    if (direction != null) result.direction = direction;
    if (trainTypeId != null) result.trainTypeId = trainTypeId;
    if (trainTypeCode != null) result.trainTypeCode = trainTypeCode;
    if (trainTypeName != null) result.trainTypeName = trainTypeName;
    if (endingStationId != null) result.endingStationId = endingStationId;
    if (endingStationName != null) result.endingStationName = endingStationName;
    if (scheduledArrivalTime != null)
      result.scheduledArrivalTime = scheduledArrivalTime;
    if (scheduledDepartureTime != null)
      result.scheduledDepartureTime = scheduledDepartureTime;
    if (delay != null) result.delay = delay;
    if (tripLine != null) result.tripLine = tripLine;
    return result;
  }

  tra_LiveBoard._();

  factory tra_LiveBoard.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory tra_LiveBoard.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'tra_LiveBoard',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'trainNo')
    ..aOB(2, _omitFieldNames ? '' : 'direction')
    ..aOS(3, _omitFieldNames ? '' : 'trainTypeId')
    ..aOS(4, _omitFieldNames ? '' : 'trainTypeCode')
    ..aOS(5, _omitFieldNames ? '' : 'trainTypeName')
    ..aOS(6, _omitFieldNames ? '' : 'endingStationId')
    ..aOS(7, _omitFieldNames ? '' : 'endingStationName')
    ..aOS(8, _omitFieldNames ? '' : 'scheduledArrivalTime')
    ..aOS(9, _omitFieldNames ? '' : 'scheduledDepartureTime')
    ..aI(10, _omitFieldNames ? '' : 'delay')
    ..aI(11, _omitFieldNames ? '' : 'tripLine')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_LiveBoard clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_LiveBoard copyWith(void Function(tra_LiveBoard) updates) =>
      super.copyWith((message) => updates(message as tra_LiveBoard))
          as tra_LiveBoard;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static tra_LiveBoard create() => tra_LiveBoard._();
  @$core.override
  tra_LiveBoard createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static tra_LiveBoard getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<tra_LiveBoard>(create);
  static tra_LiveBoard? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get trainNo => $_getSZ(0);
  @$pb.TagNumber(1)
  set trainNo($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTrainNo() => $_has(0);
  @$pb.TagNumber(1)
  void clearTrainNo() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get direction => $_getBF(1);
  @$pb.TagNumber(2)
  set direction($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDirection() => $_has(1);
  @$pb.TagNumber(2)
  void clearDirection() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get trainTypeId => $_getSZ(2);
  @$pb.TagNumber(3)
  set trainTypeId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTrainTypeId() => $_has(2);
  @$pb.TagNumber(3)
  void clearTrainTypeId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get trainTypeCode => $_getSZ(3);
  @$pb.TagNumber(4)
  set trainTypeCode($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTrainTypeCode() => $_has(3);
  @$pb.TagNumber(4)
  void clearTrainTypeCode() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get trainTypeName => $_getSZ(4);
  @$pb.TagNumber(5)
  set trainTypeName($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTrainTypeName() => $_has(4);
  @$pb.TagNumber(5)
  void clearTrainTypeName() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get endingStationId => $_getSZ(5);
  @$pb.TagNumber(6)
  set endingStationId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasEndingStationId() => $_has(5);
  @$pb.TagNumber(6)
  void clearEndingStationId() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get endingStationName => $_getSZ(6);
  @$pb.TagNumber(7)
  set endingStationName($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasEndingStationName() => $_has(6);
  @$pb.TagNumber(7)
  void clearEndingStationName() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get scheduledArrivalTime => $_getSZ(7);
  @$pb.TagNumber(8)
  set scheduledArrivalTime($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasScheduledArrivalTime() => $_has(7);
  @$pb.TagNumber(8)
  void clearScheduledArrivalTime() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get scheduledDepartureTime => $_getSZ(8);
  @$pb.TagNumber(9)
  set scheduledDepartureTime($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasScheduledDepartureTime() => $_has(8);
  @$pb.TagNumber(9)
  void clearScheduledDepartureTime() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get delay => $_getIZ(9);
  @$pb.TagNumber(10)
  set delay($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasDelay() => $_has(9);
  @$pb.TagNumber(10)
  void clearDelay() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get tripLine => $_getIZ(10);
  @$pb.TagNumber(11)
  set tripLine($core.int value) => $_setSignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasTripLine() => $_has(10);
  @$pb.TagNumber(11)
  void clearTripLine() => $_clearField(11);
}

class tra_LiveBoards extends $pb.GeneratedMessage {
  factory tra_LiveBoards({
    $core.String? stationId,
    $core.Iterable<tra_LiveBoard>? items,
  }) {
    final result = create();
    if (stationId != null) result.stationId = stationId;
    if (items != null) result.items.addAll(items);
    return result;
  }

  tra_LiveBoards._();

  factory tra_LiveBoards.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory tra_LiveBoards.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'tra_LiveBoards',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'stationId')
    ..pPM<tra_LiveBoard>(2, _omitFieldNames ? '' : 'items',
        subBuilder: tra_LiveBoard.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_LiveBoards clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  tra_LiveBoards copyWith(void Function(tra_LiveBoards) updates) =>
      super.copyWith((message) => updates(message as tra_LiveBoards))
          as tra_LiveBoards;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static tra_LiveBoards create() => tra_LiveBoards._();
  @$core.override
  tra_LiveBoards createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static tra_LiveBoards getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<tra_LiveBoards>(create);
  static tra_LiveBoards? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get stationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set stationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearStationId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<tra_LiveBoard> get items => $_getList(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
