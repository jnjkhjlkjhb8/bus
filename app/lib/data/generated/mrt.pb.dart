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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// Wire-compatible with the former `bytes data = 1`: field 1 still carries a
/// marshaled Mrt_live, now typed for the interface.
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
    $core.String? stationName,
    $core.String? system,
    $core.String? tripHeadSign,
    $core.String? destinationStaionID,
    $core.String? destinationStationName,
    $core.int? serviceStatus,
    $core.int? estimateTime,
    $core.String? countDown,
    $core.String? nowDateTime,
    $core.String? cN1,
    $core.String? trainNumber,
    CartWeight? weight,
  }) {
    final result = create();
    if (lineID != null) result.lineID = lineID;
    if (stationID != null) result.stationID = stationID;
    if (stationName != null) result.stationName = stationName;
    if (system != null) result.system = system;
    if (tripHeadSign != null) result.tripHeadSign = tripHeadSign;
    if (destinationStaionID != null)
      result.destinationStaionID = destinationStaionID;
    if (destinationStationName != null)
      result.destinationStationName = destinationStationName;
    if (serviceStatus != null) result.serviceStatus = serviceStatus;
    if (estimateTime != null) result.estimateTime = estimateTime;
    if (countDown != null) result.countDown = countDown;
    if (nowDateTime != null) result.nowDateTime = nowDateTime;
    if (cN1 != null) result.cN1 = cN1;
    if (trainNumber != null) result.trainNumber = trainNumber;
    if (weight != null) result.weight = weight;
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
    ..aOS(3, _omitFieldNames ? '' : 'StationName', protoName: 'StationName')
    ..aOS(4, _omitFieldNames ? '' : 'system')
    ..aOS(5, _omitFieldNames ? '' : 'TripHeadSign', protoName: 'TripHeadSign')
    ..aOS(6, _omitFieldNames ? '' : 'DestinationStaionID',
        protoName: 'DestinationStaionID')
    ..aOS(7, _omitFieldNames ? '' : 'DestinationStationName',
        protoName: 'DestinationStationName')
    ..aI(8, _omitFieldNames ? '' : 'ServiceStatus', protoName: 'ServiceStatus')
    ..aI(9, _omitFieldNames ? '' : 'EstimateTime', protoName: 'EstimateTime')
    ..aOS(10, _omitFieldNames ? '' : 'CountDown', protoName: 'CountDown')
    ..aOS(11, _omitFieldNames ? '' : 'NowDateTime', protoName: 'NowDateTime')
    ..aOS(12, _omitFieldNames ? '' : 'CN1', protoName: 'CN1')
    ..aOS(13, _omitFieldNames ? '' : 'TrainNumber', protoName: 'TrainNumber')
    ..aOM<CartWeight>(14, _omitFieldNames ? '' : 'Weight',
        protoName: 'Weight', subBuilder: CartWeight.create)
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
  $core.String get stationName => $_getSZ(2);
  @$pb.TagNumber(3)
  set stationName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStationName() => $_has(2);
  @$pb.TagNumber(3)
  void clearStationName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get system => $_getSZ(3);
  @$pb.TagNumber(4)
  set system($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSystem() => $_has(3);
  @$pb.TagNumber(4)
  void clearSystem() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get tripHeadSign => $_getSZ(4);
  @$pb.TagNumber(5)
  set tripHeadSign($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTripHeadSign() => $_has(4);
  @$pb.TagNumber(5)
  void clearTripHeadSign() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get destinationStaionID => $_getSZ(5);
  @$pb.TagNumber(6)
  set destinationStaionID($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDestinationStaionID() => $_has(5);
  @$pb.TagNumber(6)
  void clearDestinationStaionID() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get destinationStationName => $_getSZ(6);
  @$pb.TagNumber(7)
  set destinationStationName($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasDestinationStationName() => $_has(6);
  @$pb.TagNumber(7)
  void clearDestinationStationName() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get serviceStatus => $_getIZ(7);
  @$pb.TagNumber(8)
  set serviceStatus($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasServiceStatus() => $_has(7);
  @$pb.TagNumber(8)
  void clearServiceStatus() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get estimateTime => $_getIZ(8);
  @$pb.TagNumber(9)
  set estimateTime($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasEstimateTime() => $_has(8);
  @$pb.TagNumber(9)
  void clearEstimateTime() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get countDown => $_getSZ(9);
  @$pb.TagNumber(10)
  set countDown($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasCountDown() => $_has(9);
  @$pb.TagNumber(10)
  void clearCountDown() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get nowDateTime => $_getSZ(10);
  @$pb.TagNumber(11)
  set nowDateTime($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasNowDateTime() => $_has(10);
  @$pb.TagNumber(11)
  void clearNowDateTime() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get cN1 => $_getSZ(11);
  @$pb.TagNumber(12)
  set cN1($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasCN1() => $_has(11);
  @$pb.TagNumber(12)
  void clearCN1() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get trainNumber => $_getSZ(12);
  @$pb.TagNumber(13)
  set trainNumber($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasTrainNumber() => $_has(12);
  @$pb.TagNumber(13)
  void clearTrainNumber() => $_clearField(13);

  @$pb.TagNumber(14)
  CartWeight get weight => $_getN(13);
  @$pb.TagNumber(14)
  set weight(CartWeight value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasWeight() => $_has(13);
  @$pb.TagNumber(14)
  void clearWeight() => $_clearField(14);
  @$pb.TagNumber(14)
  CartWeight ensureWeight() => $_ensure(13);
}

class CartWeight extends $pb.GeneratedMessage {
  factory CartWeight({
    $core.String? cart1L,
    $core.String? cart2L,
    $core.String? cart3L,
    $core.String? cart4L,
    $core.String? cart5L,
    $core.String? cart6L,
  }) {
    final result = create();
    if (cart1L != null) result.cart1L = cart1L;
    if (cart2L != null) result.cart2L = cart2L;
    if (cart3L != null) result.cart3L = cart3L;
    if (cart4L != null) result.cart4L = cart4L;
    if (cart5L != null) result.cart5L = cart5L;
    if (cart6L != null) result.cart6L = cart6L;
    return result;
  }

  CartWeight._();

  factory CartWeight.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CartWeight.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CartWeight',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'Cart1L', protoName: 'Cart1L')
    ..aOS(2, _omitFieldNames ? '' : 'Cart2L', protoName: 'Cart2L')
    ..aOS(3, _omitFieldNames ? '' : 'Cart3L', protoName: 'Cart3L')
    ..aOS(4, _omitFieldNames ? '' : 'Cart4L', protoName: 'Cart4L')
    ..aOS(5, _omitFieldNames ? '' : 'Cart5L', protoName: 'Cart5L')
    ..aOS(6, _omitFieldNames ? '' : 'Cart6L', protoName: 'Cart6L')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CartWeight clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CartWeight copyWith(void Function(CartWeight) updates) =>
      super.copyWith((message) => updates(message as CartWeight)) as CartWeight;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CartWeight create() => CartWeight._();
  @$core.override
  CartWeight createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CartWeight getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CartWeight>(create);
  static CartWeight? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get cart1L => $_getSZ(0);
  @$pb.TagNumber(1)
  set cart1L($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCart1L() => $_has(0);
  @$pb.TagNumber(1)
  void clearCart1L() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get cart2L => $_getSZ(1);
  @$pb.TagNumber(2)
  set cart2L($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCart2L() => $_has(1);
  @$pb.TagNumber(2)
  void clearCart2L() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get cart3L => $_getSZ(2);
  @$pb.TagNumber(3)
  set cart3L($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCart3L() => $_has(2);
  @$pb.TagNumber(3)
  void clearCart3L() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get cart4L => $_getSZ(3);
  @$pb.TagNumber(4)
  set cart4L($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCart4L() => $_has(3);
  @$pb.TagNumber(4)
  void clearCart4L() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get cart5L => $_getSZ(4);
  @$pb.TagNumber(5)
  set cart5L($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCart5L() => $_has(4);
  @$pb.TagNumber(5)
  void clearCart5L() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get cart6L => $_getSZ(5);
  @$pb.TagNumber(6)
  set cart6L($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCart6L() => $_has(5);
  @$pb.TagNumber(6)
  void clearCart6L() => $_clearField(6);
}

/// CreateMrtTrackRequest opens a metro alight-reminder session. The app always
/// sends a full car_id (derived from the boarded arrival's paired congestion CN1
/// or typed by the rider); the backend does no prefix probing. dest_station_id is
/// the train's terminal (from the tapped arrival row); target_station_id is the
/// alight station; lead_stops is the 提前站數 lead. system is fixed "TRTC".
class CreateMrtTrackRequest extends $pb.GeneratedMessage {
  factory CreateMrtTrackRequest({
    $core.String? installId,
    $core.String? carId,
    $core.String? boardStationId,
    $core.String? destStationId,
    $core.String? targetStationId,
    $core.int? leadStops,
    $core.String? system,
  }) {
    final result = create();
    if (installId != null) result.installId = installId;
    if (carId != null) result.carId = carId;
    if (boardStationId != null) result.boardStationId = boardStationId;
    if (destStationId != null) result.destStationId = destStationId;
    if (targetStationId != null) result.targetStationId = targetStationId;
    if (leadStops != null) result.leadStops = leadStops;
    if (system != null) result.system = system;
    return result;
  }

  CreateMrtTrackRequest._();

  factory CreateMrtTrackRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateMrtTrackRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateMrtTrackRequest',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'installId')
    ..aOS(2, _omitFieldNames ? '' : 'carId')
    ..aOS(3, _omitFieldNames ? '' : 'boardStationId')
    ..aOS(4, _omitFieldNames ? '' : 'destStationId')
    ..aOS(5, _omitFieldNames ? '' : 'targetStationId')
    ..aI(6, _omitFieldNames ? '' : 'leadStops')
    ..aOS(7, _omitFieldNames ? '' : 'system')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMrtTrackRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMrtTrackRequest copyWith(
          void Function(CreateMrtTrackRequest) updates) =>
      super.copyWith((message) => updates(message as CreateMrtTrackRequest))
          as CreateMrtTrackRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateMrtTrackRequest create() => CreateMrtTrackRequest._();
  @$core.override
  CreateMrtTrackRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateMrtTrackRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateMrtTrackRequest>(create);
  static CreateMrtTrackRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get installId => $_getSZ(0);
  @$pb.TagNumber(1)
  set installId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstallId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get carId => $_getSZ(1);
  @$pb.TagNumber(2)
  set carId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCarId() => $_has(1);
  @$pb.TagNumber(2)
  void clearCarId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get boardStationId => $_getSZ(2);
  @$pb.TagNumber(3)
  set boardStationId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBoardStationId() => $_has(2);
  @$pb.TagNumber(3)
  void clearBoardStationId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get destStationId => $_getSZ(3);
  @$pb.TagNumber(4)
  set destStationId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDestStationId() => $_has(3);
  @$pb.TagNumber(4)
  void clearDestStationId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get targetStationId => $_getSZ(4);
  @$pb.TagNumber(5)
  set targetStationId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTargetStationId() => $_has(4);
  @$pb.TagNumber(5)
  void clearTargetStationId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get leadStops => $_getIZ(5);
  @$pb.TagNumber(6)
  set leadStops($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLeadStops() => $_has(5);
  @$pb.TagNumber(6)
  void clearLeadStops() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get system => $_getSZ(6);
  @$pb.TagNumber(7)
  set system($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSystem() => $_has(6);
  @$pb.TagNumber(7)
  void clearSystem() => $_clearField(7);
}

class WatchMrtTrackRequest extends $pb.GeneratedMessage {
  factory WatchMrtTrackRequest({
    $core.String? trackId,
  }) {
    final result = create();
    if (trackId != null) result.trackId = trackId;
    return result;
  }

  WatchMrtTrackRequest._();

  factory WatchMrtTrackRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory WatchMrtTrackRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchMrtTrackRequest',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'trackId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchMrtTrackRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchMrtTrackRequest copyWith(void Function(WatchMrtTrackRequest) updates) =>
      super.copyWith((message) => updates(message as WatchMrtTrackRequest))
          as WatchMrtTrackRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WatchMrtTrackRequest create() => WatchMrtTrackRequest._();
  @$core.override
  WatchMrtTrackRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static WatchMrtTrackRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchMrtTrackRequest>(create);
  static WatchMrtTrackRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get trackId => $_getSZ(0);
  @$pb.TagNumber(1)
  set trackId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTrackId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTrackId() => $_clearField(1);
}

class CancelMrtTrackRequest extends $pb.GeneratedMessage {
  factory CancelMrtTrackRequest({
    $core.String? installId,
    $core.String? trackId,
  }) {
    final result = create();
    if (installId != null) result.installId = installId;
    if (trackId != null) result.trackId = trackId;
    return result;
  }

  CancelMrtTrackRequest._();

  factory CancelMrtTrackRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CancelMrtTrackRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CancelMrtTrackRequest',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'installId')
    ..aOS(2, _omitFieldNames ? '' : 'trackId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancelMrtTrackRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancelMrtTrackRequest copyWith(
          void Function(CancelMrtTrackRequest) updates) =>
      super.copyWith((message) => updates(message as CancelMrtTrackRequest))
          as CancelMrtTrackRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CancelMrtTrackRequest create() => CancelMrtTrackRequest._();
  @$core.override
  CancelMrtTrackRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CancelMrtTrackRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CancelMrtTrackRequest>(create);
  static CancelMrtTrackRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get installId => $_getSZ(0);
  @$pb.TagNumber(1)
  set installId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasInstallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearInstallId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get trackId => $_getSZ(1);
  @$pb.TagNumber(2)
  set trackId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTrackId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTrackId() => $_clearField(2);
}

class MrtTrackAck extends $pb.GeneratedMessage {
  factory MrtTrackAck({
    $core.bool? ok,
  }) {
    final result = create();
    if (ok != null) result.ok = ok;
    return result;
  }

  MrtTrackAck._();

  factory MrtTrackAck.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MrtTrackAck.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MrtTrackAck',
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'ok')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MrtTrackAck clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MrtTrackAck copyWith(void Function(MrtTrackAck) updates) =>
      super.copyWith((message) => updates(message as MrtTrackAck))
          as MrtTrackAck;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MrtTrackAck create() => MrtTrackAck._();
  @$core.override
  MrtTrackAck createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MrtTrackAck getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MrtTrackAck>(create);
  static MrtTrackAck? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get ok => $_getBF(0);
  @$pb.TagNumber(1)
  set ok($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOk() => $_has(0);
  @$pb.TagNumber(1)
  void clearOk() => $_clearField(1);
}

/// MrtTrackState is both the CreateTrack response and each WatchTrack stream item.
/// path_station_ids/path_station_names run board→terminal; current_index is the
/// last station the train has passed (0 = at board), target_index is the alight
/// station's position, remaining_stops = target_index − current_index. status is
/// one of tracking / lead_fired / arrived / lost / stale / cancelled.
/// next_poll_at_unix is an internal scheduling field, harmless to expose.
class MrtTrackState extends $pb.GeneratedMessage {
  factory MrtTrackState({
    $core.String? trackId,
    $core.String? tripId,
    $core.String? carId,
    $core.Iterable<$core.String>? pathStationIds,
    $core.Iterable<$core.String>? pathStationNames,
    $core.int? targetIndex,
    $core.int? currentIndex,
    $core.int? remainingStops,
    $core.String? nextStationId,
    $core.String? nextStationName,
    $core.double? progress,
    $core.String? status,
    $fixnum.Int64? nextPollAtUnix,
    $core.int? leadStops,
    $core.String? system,
    $fixnum.Int64? lastProgressAtUnix,
  }) {
    final result = create();
    if (trackId != null) result.trackId = trackId;
    if (tripId != null) result.tripId = tripId;
    if (carId != null) result.carId = carId;
    if (pathStationIds != null) result.pathStationIds.addAll(pathStationIds);
    if (pathStationNames != null)
      result.pathStationNames.addAll(pathStationNames);
    if (targetIndex != null) result.targetIndex = targetIndex;
    if (currentIndex != null) result.currentIndex = currentIndex;
    if (remainingStops != null) result.remainingStops = remainingStops;
    if (nextStationId != null) result.nextStationId = nextStationId;
    if (nextStationName != null) result.nextStationName = nextStationName;
    if (progress != null) result.progress = progress;
    if (status != null) result.status = status;
    if (nextPollAtUnix != null) result.nextPollAtUnix = nextPollAtUnix;
    if (leadStops != null) result.leadStops = leadStops;
    if (system != null) result.system = system;
    if (lastProgressAtUnix != null)
      result.lastProgressAtUnix = lastProgressAtUnix;
    return result;
  }

  MrtTrackState._();

  factory MrtTrackState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MrtTrackState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MrtTrackState',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'trackId')
    ..aOS(2, _omitFieldNames ? '' : 'tripId')
    ..aOS(3, _omitFieldNames ? '' : 'carId')
    ..pPS(4, _omitFieldNames ? '' : 'pathStationIds')
    ..pPS(5, _omitFieldNames ? '' : 'pathStationNames')
    ..aI(6, _omitFieldNames ? '' : 'targetIndex')
    ..aI(7, _omitFieldNames ? '' : 'currentIndex')
    ..aI(8, _omitFieldNames ? '' : 'remainingStops')
    ..aOS(9, _omitFieldNames ? '' : 'nextStationId')
    ..aOS(10, _omitFieldNames ? '' : 'nextStationName')
    ..aD(11, _omitFieldNames ? '' : 'progress')
    ..aOS(12, _omitFieldNames ? '' : 'status')
    ..aInt64(13, _omitFieldNames ? '' : 'nextPollAtUnix')
    ..aI(14, _omitFieldNames ? '' : 'leadStops')
    ..aOS(15, _omitFieldNames ? '' : 'system')
    ..aInt64(16, _omitFieldNames ? '' : 'lastProgressAtUnix')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MrtTrackState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MrtTrackState copyWith(void Function(MrtTrackState) updates) =>
      super.copyWith((message) => updates(message as MrtTrackState))
          as MrtTrackState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MrtTrackState create() => MrtTrackState._();
  @$core.override
  MrtTrackState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MrtTrackState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MrtTrackState>(create);
  static MrtTrackState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get trackId => $_getSZ(0);
  @$pb.TagNumber(1)
  set trackId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTrackId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTrackId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get tripId => $_getSZ(1);
  @$pb.TagNumber(2)
  set tripId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTripId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTripId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get carId => $_getSZ(2);
  @$pb.TagNumber(3)
  set carId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCarId() => $_has(2);
  @$pb.TagNumber(3)
  void clearCarId() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get pathStationIds => $_getList(3);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get pathStationNames => $_getList(4);

  @$pb.TagNumber(6)
  $core.int get targetIndex => $_getIZ(5);
  @$pb.TagNumber(6)
  set targetIndex($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTargetIndex() => $_has(5);
  @$pb.TagNumber(6)
  void clearTargetIndex() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get currentIndex => $_getIZ(6);
  @$pb.TagNumber(7)
  set currentIndex($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasCurrentIndex() => $_has(6);
  @$pb.TagNumber(7)
  void clearCurrentIndex() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get remainingStops => $_getIZ(7);
  @$pb.TagNumber(8)
  set remainingStops($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasRemainingStops() => $_has(7);
  @$pb.TagNumber(8)
  void clearRemainingStops() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get nextStationId => $_getSZ(8);
  @$pb.TagNumber(9)
  set nextStationId($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasNextStationId() => $_has(8);
  @$pb.TagNumber(9)
  void clearNextStationId() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get nextStationName => $_getSZ(9);
  @$pb.TagNumber(10)
  set nextStationName($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasNextStationName() => $_has(9);
  @$pb.TagNumber(10)
  void clearNextStationName() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.double get progress => $_getN(10);
  @$pb.TagNumber(11)
  set progress($core.double value) => $_setDouble(10, value);
  @$pb.TagNumber(11)
  $core.bool hasProgress() => $_has(10);
  @$pb.TagNumber(11)
  void clearProgress() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get status => $_getSZ(11);
  @$pb.TagNumber(12)
  set status($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasStatus() => $_has(11);
  @$pb.TagNumber(12)
  void clearStatus() => $_clearField(12);

  @$pb.TagNumber(13)
  $fixnum.Int64 get nextPollAtUnix => $_getI64(12);
  @$pb.TagNumber(13)
  set nextPollAtUnix($fixnum.Int64 value) => $_setInt64(12, value);
  @$pb.TagNumber(13)
  $core.bool hasNextPollAtUnix() => $_has(12);
  @$pb.TagNumber(13)
  void clearNextPollAtUnix() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.int get leadStops => $_getIZ(13);
  @$pb.TagNumber(14)
  set leadStops($core.int value) => $_setSignedInt32(13, value);
  @$pb.TagNumber(14)
  $core.bool hasLeadStops() => $_has(13);
  @$pb.TagNumber(14)
  void clearLeadStops() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get system => $_getSZ(14);
  @$pb.TagNumber(15)
  set system($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasSystem() => $_has(14);
  @$pb.TagNumber(15)
  void clearSystem() => $_clearField(15);

  /// Internal: when the position last advanced. The tracker ends a session as
  /// stale when no advance lands within the stale window. Harmless to expose.
  @$pb.TagNumber(16)
  $fixnum.Int64 get lastProgressAtUnix => $_getI64(15);
  @$pb.TagNumber(16)
  set lastProgressAtUnix($fixnum.Int64 value) => $_setInt64(15, value);
  @$pb.TagNumber(16)
  $core.bool hasLastProgressAtUnix() => $_has(15);
  @$pb.TagNumber(16)
  void clearLastProgressAtUnix() => $_clearField(16);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
