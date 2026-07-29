// This is a generated file - do not edit.
//
// Generated from mrt.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use resp_Mrt_etaDescriptor instead')
const Resp_Mrt_eta$json = {
  '1': 'Resp_Mrt_eta',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 11, '6': '.Mrt_live', '10': 'data'},
  ],
};

/// Descriptor for `Resp_Mrt_eta`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resp_Mrt_etaDescriptor = $convert.base64Decode(
    'CgxSZXNwX01ydF9ldGESHQoEZGF0YRgBIAEoCzIJLk1ydF9saXZlUgRkYXRh');

@$core.Deprecated('Use ask_mrtDescriptor instead')
const Ask_mrt$json = {
  '1': 'Ask_mrt',
  '2': [
    {'1': 'system', '3': 1, '4': 1, '5': 9, '10': 'system'},
    {'1': 'StationID', '3': 2, '4': 1, '5': 9, '10': 'StationID'},
  ],
};

/// Descriptor for `Ask_mrt`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ask_mrtDescriptor = $convert.base64Decode(
    'CgdBc2tfbXJ0EhYKBnN5c3RlbRgBIAEoCVIGc3lzdGVtEhwKCVN0YXRpb25JRBgCIAEoCVIJU3'
    'RhdGlvbklE');

@$core.Deprecated('Use mrt_liveDescriptor instead')
const Mrt_live$json = {
  '1': 'Mrt_live',
  '2': [
    {'1': 'LineID', '3': 1, '4': 1, '5': 9, '10': 'LineID'},
    {'1': 'StationID', '3': 2, '4': 1, '5': 9, '10': 'StationID'},
    {'1': 'StationName', '3': 3, '4': 1, '5': 9, '10': 'StationName'},
    {'1': 'system', '3': 4, '4': 1, '5': 9, '10': 'system'},
    {'1': 'TripHeadSign', '3': 5, '4': 1, '5': 9, '10': 'TripHeadSign'},
    {
      '1': 'DestinationStaionID',
      '3': 6,
      '4': 1,
      '5': 9,
      '10': 'DestinationStaionID'
    },
    {
      '1': 'DestinationStationName',
      '3': 7,
      '4': 1,
      '5': 9,
      '10': 'DestinationStationName'
    },
    {'1': 'ServiceStatus', '3': 8, '4': 1, '5': 5, '10': 'ServiceStatus'},
    {'1': 'EstimateTime', '3': 9, '4': 1, '5': 5, '10': 'EstimateTime'},
    {'1': 'CountDown', '3': 10, '4': 1, '5': 9, '10': 'CountDown'},
    {'1': 'NowDateTime', '3': 11, '4': 1, '5': 9, '10': 'NowDateTime'},
    {'1': 'CN1', '3': 12, '4': 1, '5': 9, '10': 'CN1'},
    {'1': 'TrainNumber', '3': 13, '4': 1, '5': 9, '10': 'TrainNumber'},
    {
      '1': 'Weight',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.CartWeight',
      '10': 'Weight'
    },
  ],
};

/// Descriptor for `Mrt_live`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mrt_liveDescriptor = $convert.base64Decode(
    'CghNcnRfbGl2ZRIWCgZMaW5lSUQYASABKAlSBkxpbmVJRBIcCglTdGF0aW9uSUQYAiABKAlSCV'
    'N0YXRpb25JRBIgCgtTdGF0aW9uTmFtZRgDIAEoCVILU3RhdGlvbk5hbWUSFgoGc3lzdGVtGAQg'
    'ASgJUgZzeXN0ZW0SIgoMVHJpcEhlYWRTaWduGAUgASgJUgxUcmlwSGVhZFNpZ24SMAoTRGVzdG'
    'luYXRpb25TdGFpb25JRBgGIAEoCVITRGVzdGluYXRpb25TdGFpb25JRBI2ChZEZXN0aW5hdGlv'
    'blN0YXRpb25OYW1lGAcgASgJUhZEZXN0aW5hdGlvblN0YXRpb25OYW1lEiQKDVNlcnZpY2VTdG'
    'F0dXMYCCABKAVSDVNlcnZpY2VTdGF0dXMSIgoMRXN0aW1hdGVUaW1lGAkgASgFUgxFc3RpbWF0'
    'ZVRpbWUSHAoJQ291bnREb3duGAogASgJUglDb3VudERvd24SIAoLTm93RGF0ZVRpbWUYCyABKA'
    'lSC05vd0RhdGVUaW1lEhAKA0NOMRgMIAEoCVIDQ04xEiAKC1RyYWluTnVtYmVyGA0gASgJUgtU'
    'cmFpbk51bWJlchIjCgZXZWlnaHQYDiABKAsyCy5DYXJ0V2VpZ2h0UgZXZWlnaHQ=');

@$core.Deprecated('Use cartWeightDescriptor instead')
const CartWeight$json = {
  '1': 'CartWeight',
  '2': [
    {'1': 'Cart1L', '3': 1, '4': 1, '5': 9, '10': 'Cart1L'},
    {'1': 'Cart2L', '3': 2, '4': 1, '5': 9, '10': 'Cart2L'},
    {'1': 'Cart3L', '3': 3, '4': 1, '5': 9, '10': 'Cart3L'},
    {'1': 'Cart4L', '3': 4, '4': 1, '5': 9, '10': 'Cart4L'},
    {'1': 'Cart5L', '3': 5, '4': 1, '5': 9, '10': 'Cart5L'},
    {'1': 'Cart6L', '3': 6, '4': 1, '5': 9, '10': 'Cart6L'},
  ],
};

/// Descriptor for `CartWeight`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List cartWeightDescriptor = $convert.base64Decode(
    'CgpDYXJ0V2VpZ2h0EhYKBkNhcnQxTBgBIAEoCVIGQ2FydDFMEhYKBkNhcnQyTBgCIAEoCVIGQ2'
    'FydDJMEhYKBkNhcnQzTBgDIAEoCVIGQ2FydDNMEhYKBkNhcnQ0TBgEIAEoCVIGQ2FydDRMEhYK'
    'BkNhcnQ1TBgFIAEoCVIGQ2FydDVMEhYKBkNhcnQ2TBgGIAEoCVIGQ2FydDZM');

@$core.Deprecated('Use createMrtTrackRequestDescriptor instead')
const CreateMrtTrackRequest$json = {
  '1': 'CreateMrtTrackRequest',
  '2': [
    {'1': 'install_id', '3': 1, '4': 1, '5': 9, '10': 'installId'},
    {'1': 'car_id', '3': 2, '4': 1, '5': 9, '10': 'carId'},
    {'1': 'board_station_id', '3': 3, '4': 1, '5': 9, '10': 'boardStationId'},
    {'1': 'dest_station_id', '3': 4, '4': 1, '5': 9, '10': 'destStationId'},
    {'1': 'target_station_id', '3': 5, '4': 1, '5': 9, '10': 'targetStationId'},
    {'1': 'lead_stops', '3': 6, '4': 1, '5': 5, '10': 'leadStops'},
    {'1': 'system', '3': 7, '4': 1, '5': 9, '10': 'system'},
  ],
};

/// Descriptor for `CreateMrtTrackRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createMrtTrackRequestDescriptor = $convert.base64Decode(
    'ChVDcmVhdGVNcnRUcmFja1JlcXVlc3QSHQoKaW5zdGFsbF9pZBgBIAEoCVIJaW5zdGFsbElkEh'
    'UKBmNhcl9pZBgCIAEoCVIFY2FySWQSKAoQYm9hcmRfc3RhdGlvbl9pZBgDIAEoCVIOYm9hcmRT'
    'dGF0aW9uSWQSJgoPZGVzdF9zdGF0aW9uX2lkGAQgASgJUg1kZXN0U3RhdGlvbklkEioKEXRhcm'
    'dldF9zdGF0aW9uX2lkGAUgASgJUg90YXJnZXRTdGF0aW9uSWQSHQoKbGVhZF9zdG9wcxgGIAEo'
    'BVIJbGVhZFN0b3BzEhYKBnN5c3RlbRgHIAEoCVIGc3lzdGVt');

@$core.Deprecated('Use watchMrtTrackRequestDescriptor instead')
const WatchMrtTrackRequest$json = {
  '1': 'WatchMrtTrackRequest',
  '2': [
    {'1': 'track_id', '3': 1, '4': 1, '5': 9, '10': 'trackId'},
  ],
};

/// Descriptor for `WatchMrtTrackRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchMrtTrackRequestDescriptor =
    $convert.base64Decode(
        'ChRXYXRjaE1ydFRyYWNrUmVxdWVzdBIZCgh0cmFja19pZBgBIAEoCVIHdHJhY2tJZA==');

@$core.Deprecated('Use cancelMrtTrackRequestDescriptor instead')
const CancelMrtTrackRequest$json = {
  '1': 'CancelMrtTrackRequest',
  '2': [
    {'1': 'install_id', '3': 1, '4': 1, '5': 9, '10': 'installId'},
    {'1': 'track_id', '3': 2, '4': 1, '5': 9, '10': 'trackId'},
  ],
};

/// Descriptor for `CancelMrtTrackRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List cancelMrtTrackRequestDescriptor = $convert.base64Decode(
    'ChVDYW5jZWxNcnRUcmFja1JlcXVlc3QSHQoKaW5zdGFsbF9pZBgBIAEoCVIJaW5zdGFsbElkEh'
    'kKCHRyYWNrX2lkGAIgASgJUgd0cmFja0lk');

@$core.Deprecated('Use mrtTrackAckDescriptor instead')
const MrtTrackAck$json = {
  '1': 'MrtTrackAck',
  '2': [
    {'1': 'ok', '3': 1, '4': 1, '5': 8, '10': 'ok'},
  ],
};

/// Descriptor for `MrtTrackAck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mrtTrackAckDescriptor =
    $convert.base64Decode('CgtNcnRUcmFja0FjaxIOCgJvaxgBIAEoCFICb2s=');

@$core.Deprecated('Use mrtTrackStateDescriptor instead')
const MrtTrackState$json = {
  '1': 'MrtTrackState',
  '2': [
    {'1': 'track_id', '3': 1, '4': 1, '5': 9, '10': 'trackId'},
    {'1': 'trip_id', '3': 2, '4': 1, '5': 9, '10': 'tripId'},
    {'1': 'car_id', '3': 3, '4': 1, '5': 9, '10': 'carId'},
    {'1': 'path_station_ids', '3': 4, '4': 3, '5': 9, '10': 'pathStationIds'},
    {
      '1': 'path_station_names',
      '3': 5,
      '4': 3,
      '5': 9,
      '10': 'pathStationNames'
    },
    {'1': 'target_index', '3': 6, '4': 1, '5': 5, '10': 'targetIndex'},
    {'1': 'current_index', '3': 7, '4': 1, '5': 5, '10': 'currentIndex'},
    {'1': 'remaining_stops', '3': 8, '4': 1, '5': 5, '10': 'remainingStops'},
    {'1': 'next_station_id', '3': 9, '4': 1, '5': 9, '10': 'nextStationId'},
    {
      '1': 'next_station_name',
      '3': 10,
      '4': 1,
      '5': 9,
      '10': 'nextStationName'
    },
    {'1': 'progress', '3': 11, '4': 1, '5': 1, '10': 'progress'},
    {'1': 'status', '3': 12, '4': 1, '5': 9, '10': 'status'},
    {'1': 'next_poll_at_unix', '3': 13, '4': 1, '5': 3, '10': 'nextPollAtUnix'},
    {'1': 'lead_stops', '3': 14, '4': 1, '5': 5, '10': 'leadStops'},
    {'1': 'system', '3': 15, '4': 1, '5': 9, '10': 'system'},
    {
      '1': 'last_progress_at_unix',
      '3': 16,
      '4': 1,
      '5': 3,
      '10': 'lastProgressAtUnix'
    },
  ],
};

/// Descriptor for `MrtTrackState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mrtTrackStateDescriptor = $convert.base64Decode(
    'Cg1NcnRUcmFja1N0YXRlEhkKCHRyYWNrX2lkGAEgASgJUgd0cmFja0lkEhcKB3RyaXBfaWQYAi'
    'ABKAlSBnRyaXBJZBIVCgZjYXJfaWQYAyABKAlSBWNhcklkEigKEHBhdGhfc3RhdGlvbl9pZHMY'
    'BCADKAlSDnBhdGhTdGF0aW9uSWRzEiwKEnBhdGhfc3RhdGlvbl9uYW1lcxgFIAMoCVIQcGF0aF'
    'N0YXRpb25OYW1lcxIhCgx0YXJnZXRfaW5kZXgYBiABKAVSC3RhcmdldEluZGV4EiMKDWN1cnJl'
    'bnRfaW5kZXgYByABKAVSDGN1cnJlbnRJbmRleBInCg9yZW1haW5pbmdfc3RvcHMYCCABKAVSDn'
    'JlbWFpbmluZ1N0b3BzEiYKD25leHRfc3RhdGlvbl9pZBgJIAEoCVINbmV4dFN0YXRpb25JZBIq'
    'ChFuZXh0X3N0YXRpb25fbmFtZRgKIAEoCVIPbmV4dFN0YXRpb25OYW1lEhoKCHByb2dyZXNzGA'
    'sgASgBUghwcm9ncmVzcxIWCgZzdGF0dXMYDCABKAlSBnN0YXR1cxIpChFuZXh0X3BvbGxfYXRf'
    'dW5peBgNIAEoA1IObmV4dFBvbGxBdFVuaXgSHQoKbGVhZF9zdG9wcxgOIAEoBVIJbGVhZFN0b3'
    'BzEhYKBnN5c3RlbRgPIAEoCVIGc3lzdGVtEjEKFWxhc3RfcHJvZ3Jlc3NfYXRfdW5peBgQIAEo'
    'A1ISbGFzdFByb2dyZXNzQXRVbml4');
