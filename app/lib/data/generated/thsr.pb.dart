// This is a generated file - do not edit.
//
// Generated from thsr.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class thsr_ask_detain extends $pb.GeneratedMessage {
  factory thsr_ask_detain({
    $core.String? date,
    $core.String? trainno,
  }) {
    final result = create();
    if (date != null) result.date = date;
    if (trainno != null) result.trainno = trainno;
    return result;
  }

  thsr_ask_detain._();

  factory thsr_ask_detain.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory thsr_ask_detain.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'thsr_ask_detain',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'date')
    ..aOS(2, _omitFieldNames ? '' : 'trainno')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsr_ask_detain clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsr_ask_detain copyWith(void Function(thsr_ask_detain) updates) =>
      super.copyWith((message) => updates(message as thsr_ask_detain))
          as thsr_ask_detain;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static thsr_ask_detain create() => thsr_ask_detain._();
  @$core.override
  thsr_ask_detain createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static thsr_ask_detain getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<thsr_ask_detain>(create);
  static thsr_ask_detain? _defaultInstance;

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

class thsr_timetables extends $pb.GeneratedMessage {
  factory thsr_timetables({
    $core.Iterable<thsa_timetable>? items,
  }) {
    final result = create();
    if (items != null) result.items.addAll(items);
    return result;
  }

  thsr_timetables._();

  factory thsr_timetables.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory thsr_timetables.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'thsr_timetables',
      createEmptyInstance: create)
    ..pPM<thsa_timetable>(1, _omitFieldNames ? '' : 'items',
        subBuilder: thsa_timetable.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsr_timetables clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsr_timetables copyWith(void Function(thsr_timetables) updates) =>
      super.copyWith((message) => updates(message as thsr_timetables))
          as thsr_timetables;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static thsr_timetables create() => thsr_timetables._();
  @$core.override
  thsr_timetables createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static thsr_timetables getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<thsr_timetables>(create);
  static thsr_timetables? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<thsa_timetable> get items => $_getList(0);
}

class thsr_stoptimes extends $pb.GeneratedMessage {
  factory thsr_stoptimes({
    $core.Iterable<thsa_stoptime>? items,
  }) {
    final result = create();
    if (items != null) result.items.addAll(items);
    return result;
  }

  thsr_stoptimes._();

  factory thsr_stoptimes.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory thsr_stoptimes.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'thsr_stoptimes',
      createEmptyInstance: create)
    ..pPM<thsa_stoptime>(1, _omitFieldNames ? '' : 'items',
        subBuilder: thsa_stoptime.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsr_stoptimes clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsr_stoptimes copyWith(void Function(thsr_stoptimes) updates) =>
      super.copyWith((message) => updates(message as thsr_stoptimes))
          as thsr_stoptimes;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static thsr_stoptimes create() => thsr_stoptimes._();
  @$core.override
  thsr_stoptimes createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static thsr_stoptimes getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<thsr_stoptimes>(create);
  static thsr_stoptimes? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<thsa_stoptime> get items => $_getList(0);
}

class Resp_Data extends $pb.GeneratedMessage {
  factory Resp_Data({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  Resp_Data._();

  factory Resp_Data.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Resp_Data.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Resp_Data',
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_Data clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_Data copyWith(void Function(Resp_Data) updates) =>
      super.copyWith((message) => updates(message as Resp_Data)) as Resp_Data;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Resp_Data create() => Resp_Data._();
  @$core.override
  Resp_Data createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Resp_Data getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Resp_Data>(create);
  static Resp_Data? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);
}

class Ask_Thsr extends $pb.GeneratedMessage {
  factory Ask_Thsr({
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

  Ask_Thsr._();

  factory Ask_Thsr.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Ask_Thsr.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Ask_Thsr',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'date')
    ..aOS(2, _omitFieldNames ? '' : 'originStationId')
    ..aOS(3, _omitFieldNames ? '' : 'destinationStationId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ask_Thsr clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Ask_Thsr copyWith(void Function(Ask_Thsr) updates) =>
      super.copyWith((message) => updates(message as Ask_Thsr)) as Ask_Thsr;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Ask_Thsr create() => Ask_Thsr._();
  @$core.override
  Ask_Thsr createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Ask_Thsr getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Ask_Thsr>(create);
  static Ask_Thsr? _defaultInstance;

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

class thsa_fare extends $pb.GeneratedMessage {
  factory thsa_fare({
    $core.String? originStationId,
    $core.String? destinationStationId,
    $core.int? ticketType,
    $core.int? fareClass,
    $core.int? cabinClas,
    $core.int? price,
  }) {
    final result = create();
    if (originStationId != null) result.originStationId = originStationId;
    if (destinationStationId != null)
      result.destinationStationId = destinationStationId;
    if (ticketType != null) result.ticketType = ticketType;
    if (fareClass != null) result.fareClass = fareClass;
    if (cabinClas != null) result.cabinClas = cabinClas;
    if (price != null) result.price = price;
    return result;
  }

  thsa_fare._();

  factory thsa_fare.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory thsa_fare.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'thsa_fare',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'originStationId')
    ..aOS(2, _omitFieldNames ? '' : 'destinationStationId')
    ..aI(3, _omitFieldNames ? '' : 'ticketType')
    ..aI(4, _omitFieldNames ? '' : 'fareClass')
    ..aI(5, _omitFieldNames ? '' : 'cabinClas')
    ..aI(6, _omitFieldNames ? '' : 'price')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsa_fare clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsa_fare copyWith(void Function(thsa_fare) updates) =>
      super.copyWith((message) => updates(message as thsa_fare)) as thsa_fare;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static thsa_fare create() => thsa_fare._();
  @$core.override
  thsa_fare createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static thsa_fare getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<thsa_fare>(create);
  static thsa_fare? _defaultInstance;

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
  $core.int get ticketType => $_getIZ(2);
  @$pb.TagNumber(3)
  set ticketType($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTicketType() => $_has(2);
  @$pb.TagNumber(3)
  void clearTicketType() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get fareClass => $_getIZ(3);
  @$pb.TagNumber(4)
  set fareClass($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFareClass() => $_has(3);
  @$pb.TagNumber(4)
  void clearFareClass() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get cabinClas => $_getIZ(4);
  @$pb.TagNumber(5)
  set cabinClas($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCabinClas() => $_has(4);
  @$pb.TagNumber(5)
  void clearCabinClas() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get price => $_getIZ(5);
  @$pb.TagNumber(6)
  set price($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPrice() => $_has(5);
  @$pb.TagNumber(6)
  void clearPrice() => $_clearField(6);
}

class thsa_fares extends $pb.GeneratedMessage {
  factory thsa_fares({
    $core.Iterable<thsa_fare>? items,
  }) {
    final result = create();
    if (items != null) result.items.addAll(items);
    return result;
  }

  thsa_fares._();

  factory thsa_fares.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory thsa_fares.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'thsa_fares',
      createEmptyInstance: create)
    ..pPM<thsa_fare>(1, _omitFieldNames ? '' : 'items',
        subBuilder: thsa_fare.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsa_fares clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsa_fares copyWith(void Function(thsa_fares) updates) =>
      super.copyWith((message) => updates(message as thsa_fares)) as thsa_fares;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static thsa_fares create() => thsa_fares._();
  @$core.override
  thsa_fares createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static thsa_fares getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<thsa_fares>(create);
  static thsa_fares? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<thsa_fare> get items => $_getList(0);
}

class thsa_stoptime extends $pb.GeneratedMessage {
  factory thsa_stoptime({
    $core.String? stationId,
    $core.String? stationName,
    $core.int? stopSequence,
    $core.String? arrivalTime,
    $core.String? departureTime,
  }) {
    final result = create();
    if (stationId != null) result.stationId = stationId;
    if (stationName != null) result.stationName = stationName;
    if (stopSequence != null) result.stopSequence = stopSequence;
    if (arrivalTime != null) result.arrivalTime = arrivalTime;
    if (departureTime != null) result.departureTime = departureTime;
    return result;
  }

  thsa_stoptime._();

  factory thsa_stoptime.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory thsa_stoptime.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'thsa_stoptime',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'stationId')
    ..aOS(2, _omitFieldNames ? '' : 'stationName')
    ..aI(3, _omitFieldNames ? '' : 'stopSequence')
    ..aOS(4, _omitFieldNames ? '' : 'ArrivalTime', protoName: 'ArrivalTime')
    ..aOS(5, _omitFieldNames ? '' : 'DepartureTime', protoName: 'DepartureTime')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsa_stoptime clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsa_stoptime copyWith(void Function(thsa_stoptime) updates) =>
      super.copyWith((message) => updates(message as thsa_stoptime))
          as thsa_stoptime;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static thsa_stoptime create() => thsa_stoptime._();
  @$core.override
  thsa_stoptime createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static thsa_stoptime getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<thsa_stoptime>(create);
  static thsa_stoptime? _defaultInstance;

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
}

class thsa_timetable extends $pb.GeneratedMessage {
  factory thsa_timetable({
    $core.String? trainDate,
    $core.String? trainNo,
    $core.int? direction,
    $core.String? startingStationID,
    $core.String? startingStationName,
    $core.String? endingStationID,
    $core.String? endingStationName,
    $core.String? note,
    $core.bool? overnight,
    $core.String? startingTime,
    $core.String? endingTime,
    $core.String? travelTime,
  }) {
    final result = create();
    if (trainDate != null) result.trainDate = trainDate;
    if (trainNo != null) result.trainNo = trainNo;
    if (direction != null) result.direction = direction;
    if (startingStationID != null) result.startingStationID = startingStationID;
    if (startingStationName != null)
      result.startingStationName = startingStationName;
    if (endingStationID != null) result.endingStationID = endingStationID;
    if (endingStationName != null) result.endingStationName = endingStationName;
    if (note != null) result.note = note;
    if (overnight != null) result.overnight = overnight;
    if (startingTime != null) result.startingTime = startingTime;
    if (endingTime != null) result.endingTime = endingTime;
    if (travelTime != null) result.travelTime = travelTime;
    return result;
  }

  thsa_timetable._();

  factory thsa_timetable.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory thsa_timetable.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'thsa_timetable',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'TrainDate', protoName: 'TrainDate')
    ..aOS(2, _omitFieldNames ? '' : 'TrainNo', protoName: 'TrainNo')
    ..aI(3, _omitFieldNames ? '' : 'Direction', protoName: 'Direction')
    ..aOS(4, _omitFieldNames ? '' : 'StartingStationID',
        protoName: 'Starting_Station_ID')
    ..aOS(5, _omitFieldNames ? '' : 'StartingStationName',
        protoName: 'Starting_Station_Name')
    ..aOS(6, _omitFieldNames ? '' : 'EndingStationID',
        protoName: 'EndingStationID')
    ..aOS(7, _omitFieldNames ? '' : 'EndingStationName',
        protoName: 'EndingStationName')
    ..aOS(8, _omitFieldNames ? '' : 'Note', protoName: 'Note')
    ..aOB(9, _omitFieldNames ? '' : 'Overnight', protoName: 'Overnight')
    ..aOS(12, _omitFieldNames ? '' : 'StartingTime', protoName: 'Starting_Time')
    ..aOS(13, _omitFieldNames ? '' : 'EndingTime', protoName: 'Ending_Time')
    ..aOS(14, _omitFieldNames ? '' : 'TravelTime', protoName: 'Travel_Time')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsa_timetable clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsa_timetable copyWith(void Function(thsa_timetable) updates) =>
      super.copyWith((message) => updates(message as thsa_timetable))
          as thsa_timetable;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static thsa_timetable create() => thsa_timetable._();
  @$core.override
  thsa_timetable createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static thsa_timetable getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<thsa_timetable>(create);
  static thsa_timetable? _defaultInstance;

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
  $core.String get startingStationID => $_getSZ(3);
  @$pb.TagNumber(4)
  set startingStationID($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStartingStationID() => $_has(3);
  @$pb.TagNumber(4)
  void clearStartingStationID() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get startingStationName => $_getSZ(4);
  @$pb.TagNumber(5)
  set startingStationName($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasStartingStationName() => $_has(4);
  @$pb.TagNumber(5)
  void clearStartingStationName() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get endingStationID => $_getSZ(5);
  @$pb.TagNumber(6)
  set endingStationID($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasEndingStationID() => $_has(5);
  @$pb.TagNumber(6)
  void clearEndingStationID() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get endingStationName => $_getSZ(6);
  @$pb.TagNumber(7)
  set endingStationName($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasEndingStationName() => $_has(6);
  @$pb.TagNumber(7)
  void clearEndingStationName() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get note => $_getSZ(7);
  @$pb.TagNumber(8)
  set note($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasNote() => $_has(7);
  @$pb.TagNumber(8)
  void clearNote() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get overnight => $_getBF(8);
  @$pb.TagNumber(9)
  set overnight($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasOvernight() => $_has(8);
  @$pb.TagNumber(9)
  void clearOvernight() => $_clearField(9);

  @$pb.TagNumber(12)
  $core.String get startingTime => $_getSZ(9);
  @$pb.TagNumber(12)
  set startingTime($core.String value) => $_setString(9, value);
  @$pb.TagNumber(12)
  $core.bool hasStartingTime() => $_has(9);
  @$pb.TagNumber(12)
  void clearStartingTime() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get endingTime => $_getSZ(10);
  @$pb.TagNumber(13)
  set endingTime($core.String value) => $_setString(10, value);
  @$pb.TagNumber(13)
  $core.bool hasEndingTime() => $_has(10);
  @$pb.TagNumber(13)
  void clearEndingTime() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get travelTime => $_getSZ(11);
  @$pb.TagNumber(14)
  set travelTime($core.String value) => $_setString(11, value);
  @$pb.TagNumber(14)
  $core.bool hasTravelTime() => $_has(11);
  @$pb.TagNumber(14)
  void clearTravelTime() => $_clearField(14);
}

class thsr_seat_segment extends $pb.GeneratedMessage {
  factory thsr_seat_segment({
    $core.String? originStationId,
    $core.String? destinationStationId,
    $core.String? standardSeatStatus,
    $core.String? businessSeatStatus,
  }) {
    final result = create();
    if (originStationId != null) result.originStationId = originStationId;
    if (destinationStationId != null)
      result.destinationStationId = destinationStationId;
    if (standardSeatStatus != null)
      result.standardSeatStatus = standardSeatStatus;
    if (businessSeatStatus != null)
      result.businessSeatStatus = businessSeatStatus;
    return result;
  }

  thsr_seat_segment._();

  factory thsr_seat_segment.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory thsr_seat_segment.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'thsr_seat_segment',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'originStationId')
    ..aOS(2, _omitFieldNames ? '' : 'destinationStationId')
    ..aOS(3, _omitFieldNames ? '' : 'standardSeatStatus')
    ..aOS(4, _omitFieldNames ? '' : 'businessSeatStatus')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsr_seat_segment clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsr_seat_segment copyWith(void Function(thsr_seat_segment) updates) =>
      super.copyWith((message) => updates(message as thsr_seat_segment))
          as thsr_seat_segment;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static thsr_seat_segment create() => thsr_seat_segment._();
  @$core.override
  thsr_seat_segment createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static thsr_seat_segment getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<thsr_seat_segment>(create);
  static thsr_seat_segment? _defaultInstance;

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
  $core.String get standardSeatStatus => $_getSZ(2);
  @$pb.TagNumber(3)
  set standardSeatStatus($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStandardSeatStatus() => $_has(2);
  @$pb.TagNumber(3)
  void clearStandardSeatStatus() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get businessSeatStatus => $_getSZ(3);
  @$pb.TagNumber(4)
  set businessSeatStatus($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBusinessSeatStatus() => $_has(3);
  @$pb.TagNumber(4)
  void clearBusinessSeatStatus() => $_clearField(4);
}

class thsr_available_seats extends $pb.GeneratedMessage {
  factory thsr_available_seats({
    $core.String? trainNo,
    $core.Iterable<thsr_seat_segment>? segments,
  }) {
    final result = create();
    if (trainNo != null) result.trainNo = trainNo;
    if (segments != null) result.segments.addAll(segments);
    return result;
  }

  thsr_available_seats._();

  factory thsr_available_seats.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory thsr_available_seats.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'thsr_available_seats',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'trainNo')
    ..pPM<thsr_seat_segment>(3, _omitFieldNames ? '' : 'segments',
        subBuilder: thsr_seat_segment.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsr_available_seats clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  thsr_available_seats copyWith(void Function(thsr_available_seats) updates) =>
      super.copyWith((message) => updates(message as thsr_available_seats))
          as thsr_available_seats;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static thsr_available_seats create() => thsr_available_seats._();
  @$core.override
  thsr_available_seats createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static thsr_available_seats getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<thsr_available_seats>(create);
  static thsr_available_seats? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get trainNo => $_getSZ(0);
  @$pb.TagNumber(1)
  set trainNo($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTrainNo() => $_has(0);
  @$pb.TagNumber(1)
  void clearTrainNo() => $_clearField(1);

  @$pb.TagNumber(3)
  $pb.PbList<thsr_seat_segment> get segments => $_getList(1);
}

class Resp_thsr_seats extends $pb.GeneratedMessage {
  factory Resp_thsr_seats({
    $core.List<$core.int>? data,
  }) {
    final result = create();
    if (data != null) result.data = data;
    return result;
  }

  Resp_thsr_seats._();

  factory Resp_thsr_seats.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Resp_thsr_seats.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Resp_thsr_seats',
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_thsr_seats clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Resp_thsr_seats copyWith(void Function(Resp_thsr_seats) updates) =>
      super.copyWith((message) => updates(message as Resp_thsr_seats))
          as Resp_thsr_seats;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Resp_thsr_seats create() => Resp_thsr_seats._();
  @$core.override
  Resp_thsr_seats createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Resp_thsr_seats getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Resp_thsr_seats>(create);
  static Resp_thsr_seats? _defaultInstance;

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
