// This is a generated file - do not edit.
//
// Generated from thsr.proto.

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

@$core.Deprecated('Use thsr_ask_detainDescriptor instead')
const thsr_ask_detain$json = {
  '1': 'thsr_ask_detain',
  '2': [
    {'1': 'date', '3': 1, '4': 1, '5': 9, '10': 'date'},
    {'1': 'trainno', '3': 2, '4': 1, '5': 9, '10': 'trainno'},
  ],
};

/// Descriptor for `thsr_ask_detain`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List thsr_ask_detainDescriptor = $convert.base64Decode(
    'Cg90aHNyX2Fza19kZXRhaW4SEgoEZGF0ZRgBIAEoCVIEZGF0ZRIYCgd0cmFpbm5vGAIgASgJUg'
    'd0cmFpbm5v');

@$core.Deprecated('Use thsr_timetablesDescriptor instead')
const thsr_timetables$json = {
  '1': 'thsr_timetables',
  '2': [
    {
      '1': 'items',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.thsa_timetable',
      '10': 'items'
    },
  ],
};

/// Descriptor for `thsr_timetables`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List thsr_timetablesDescriptor = $convert.base64Decode(
    'Cg90aHNyX3RpbWV0YWJsZXMSJQoFaXRlbXMYASADKAsyDy50aHNhX3RpbWV0YWJsZVIFaXRlbX'
    'M=');

@$core.Deprecated('Use thsr_stoptimesDescriptor instead')
const thsr_stoptimes$json = {
  '1': 'thsr_stoptimes',
  '2': [
    {
      '1': 'items',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.thsa_stoptime',
      '10': 'items'
    },
  ],
};

/// Descriptor for `thsr_stoptimes`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List thsr_stoptimesDescriptor = $convert.base64Decode(
    'Cg50aHNyX3N0b3B0aW1lcxIkCgVpdGVtcxgBIAMoCzIOLnRoc2Ffc3RvcHRpbWVSBWl0ZW1z');

@$core.Deprecated('Use resp_DataDescriptor instead')
const Resp_Data$json = {
  '1': 'Resp_Data',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `Resp_Data`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resp_DataDescriptor =
    $convert.base64Decode('CglSZXNwX0RhdGESEgoEZGF0YRgBIAEoDFIEZGF0YQ==');

@$core.Deprecated('Use ask_ThsrDescriptor instead')
const Ask_Thsr$json = {
  '1': 'Ask_Thsr',
  '2': [
    {'1': 'date', '3': 1, '4': 1, '5': 9, '10': 'date'},
    {'1': 'origin_station_id', '3': 2, '4': 1, '5': 9, '10': 'originStationId'},
    {
      '1': 'destination_station_id',
      '3': 3,
      '4': 1,
      '5': 9,
      '10': 'destinationStationId'
    },
  ],
};

/// Descriptor for `Ask_Thsr`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ask_ThsrDescriptor = $convert.base64Decode(
    'CghBc2tfVGhzchISCgRkYXRlGAEgASgJUgRkYXRlEioKEW9yaWdpbl9zdGF0aW9uX2lkGAIgAS'
    'gJUg9vcmlnaW5TdGF0aW9uSWQSNAoWZGVzdGluYXRpb25fc3RhdGlvbl9pZBgDIAEoCVIUZGVz'
    'dGluYXRpb25TdGF0aW9uSWQ=');

@$core.Deprecated('Use thsa_fareDescriptor instead')
const thsa_fare$json = {
  '1': 'thsa_fare',
  '2': [
    {'1': 'origin_station_id', '3': 1, '4': 1, '5': 9, '10': 'originStationId'},
    {
      '1': 'destination_station_id',
      '3': 2,
      '4': 1,
      '5': 9,
      '10': 'destinationStationId'
    },
    {'1': 'ticket_type', '3': 3, '4': 1, '5': 5, '10': 'ticketType'},
    {'1': 'fare_class', '3': 4, '4': 1, '5': 5, '10': 'fareClass'},
    {'1': 'cabin_clas', '3': 5, '4': 1, '5': 5, '10': 'cabinClas'},
    {'1': 'price', '3': 6, '4': 1, '5': 5, '10': 'price'},
  ],
};

/// Descriptor for `thsa_fare`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List thsa_fareDescriptor = $convert.base64Decode(
    'Cgl0aHNhX2ZhcmUSKgoRb3JpZ2luX3N0YXRpb25faWQYASABKAlSD29yaWdpblN0YXRpb25JZB'
    'I0ChZkZXN0aW5hdGlvbl9zdGF0aW9uX2lkGAIgASgJUhRkZXN0aW5hdGlvblN0YXRpb25JZBIf'
    'Cgt0aWNrZXRfdHlwZRgDIAEoBVIKdGlja2V0VHlwZRIdCgpmYXJlX2NsYXNzGAQgASgFUglmYX'
    'JlQ2xhc3MSHQoKY2FiaW5fY2xhcxgFIAEoBVIJY2FiaW5DbGFzEhQKBXByaWNlGAYgASgFUgVw'
    'cmljZQ==');

@$core.Deprecated('Use thsa_faresDescriptor instead')
const thsa_fares$json = {
  '1': 'thsa_fares',
  '2': [
    {'1': 'items', '3': 1, '4': 3, '5': 11, '6': '.thsa_fare', '10': 'items'},
  ],
};

/// Descriptor for `thsa_fares`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List thsa_faresDescriptor = $convert.base64Decode(
    'Cgp0aHNhX2ZhcmVzEiAKBWl0ZW1zGAEgAygLMgoudGhzYV9mYXJlUgVpdGVtcw==');

@$core.Deprecated('Use thsa_stoptimeDescriptor instead')
const thsa_stoptime$json = {
  '1': 'thsa_stoptime',
  '2': [
    {'1': 'stop_sequence', '3': 3, '4': 1, '5': 5, '10': 'stopSequence'},
    {'1': 'station_id', '3': 1, '4': 1, '5': 9, '10': 'stationId'},
    {'1': 'station_name', '3': 2, '4': 1, '5': 9, '10': 'stationName'},
    {'1': 'ArrivalTime', '3': 4, '4': 1, '5': 9, '10': 'ArrivalTime'},
    {'1': 'DepartureTime', '3': 5, '4': 1, '5': 9, '10': 'DepartureTime'},
  ],
};

/// Descriptor for `thsa_stoptime`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List thsa_stoptimeDescriptor = $convert.base64Decode(
    'Cg10aHNhX3N0b3B0aW1lEiMKDXN0b3Bfc2VxdWVuY2UYAyABKAVSDHN0b3BTZXF1ZW5jZRIdCg'
    'pzdGF0aW9uX2lkGAEgASgJUglzdGF0aW9uSWQSIQoMc3RhdGlvbl9uYW1lGAIgASgJUgtzdGF0'
    'aW9uTmFtZRIgCgtBcnJpdmFsVGltZRgEIAEoCVILQXJyaXZhbFRpbWUSJAoNRGVwYXJ0dXJlVG'
    'ltZRgFIAEoCVINRGVwYXJ0dXJlVGltZQ==');

@$core.Deprecated('Use thsa_timetableDescriptor instead')
const thsa_timetable$json = {
  '1': 'thsa_timetable',
  '2': [
    {'1': 'TrainDate', '3': 1, '4': 1, '5': 9, '10': 'TrainDate'},
    {'1': 'TrainNo', '3': 2, '4': 1, '5': 9, '10': 'TrainNo'},
    {'1': 'Direction', '3': 3, '4': 1, '5': 5, '10': 'Direction'},
    {
      '1': 'Starting_Station_ID',
      '3': 4,
      '4': 1,
      '5': 9,
      '10': 'StartingStationID'
    },
    {
      '1': 'Starting_Station_Name',
      '3': 5,
      '4': 1,
      '5': 9,
      '10': 'StartingStationName'
    },
    {'1': 'EndingStationID', '3': 6, '4': 1, '5': 9, '10': 'EndingStationID'},
    {
      '1': 'EndingStationName',
      '3': 7,
      '4': 1,
      '5': 9,
      '10': 'EndingStationName'
    },
    {'1': 'Note', '3': 8, '4': 1, '5': 9, '10': 'Note'},
    {'1': 'Overnight', '3': 9, '4': 1, '5': 8, '10': 'Overnight'},
    {'1': 'Starting_Time', '3': 12, '4': 1, '5': 9, '10': 'StartingTime'},
    {'1': 'Ending_Time', '3': 13, '4': 1, '5': 9, '10': 'EndingTime'},
    {'1': 'Travel_Time', '3': 14, '4': 1, '5': 9, '10': 'TravelTime'},
  ],
};

/// Descriptor for `thsa_timetable`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List thsa_timetableDescriptor = $convert.base64Decode(
    'Cg50aHNhX3RpbWV0YWJsZRIcCglUcmFpbkRhdGUYASABKAlSCVRyYWluRGF0ZRIYCgdUcmFpbk'
    '5vGAIgASgJUgdUcmFpbk5vEhwKCURpcmVjdGlvbhgDIAEoBVIJRGlyZWN0aW9uEi4KE1N0YXJ0'
    'aW5nX1N0YXRpb25fSUQYBCABKAlSEVN0YXJ0aW5nU3RhdGlvbklEEjIKFVN0YXJ0aW5nX1N0YX'
    'Rpb25fTmFtZRgFIAEoCVITU3RhcnRpbmdTdGF0aW9uTmFtZRIoCg9FbmRpbmdTdGF0aW9uSUQY'
    'BiABKAlSD0VuZGluZ1N0YXRpb25JRBIsChFFbmRpbmdTdGF0aW9uTmFtZRgHIAEoCVIRRW5kaW'
    '5nU3RhdGlvbk5hbWUSEgoETm90ZRgIIAEoCVIETm90ZRIcCglPdmVybmlnaHQYCSABKAhSCU92'
    'ZXJuaWdodBIjCg1TdGFydGluZ19UaW1lGAwgASgJUgxTdGFydGluZ1RpbWUSHwoLRW5kaW5nX1'
    'RpbWUYDSABKAlSCkVuZGluZ1RpbWUSHwoLVHJhdmVsX1RpbWUYDiABKAlSClRyYXZlbFRpbWU=');

@$core.Deprecated('Use thsr_seat_segmentDescriptor instead')
const thsr_seat_segment$json = {
  '1': 'thsr_seat_segment',
  '2': [
    {'1': 'origin_station_id', '3': 1, '4': 1, '5': 9, '10': 'originStationId'},
    {
      '1': 'destination_station_id',
      '3': 2,
      '4': 1,
      '5': 9,
      '10': 'destinationStationId'
    },
    {
      '1': 'standard_seat_status',
      '3': 3,
      '4': 1,
      '5': 9,
      '10': 'standardSeatStatus'
    },
    {
      '1': 'business_seat_status',
      '3': 4,
      '4': 1,
      '5': 9,
      '10': 'businessSeatStatus'
    },
  ],
};

/// Descriptor for `thsr_seat_segment`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List thsr_seat_segmentDescriptor = $convert.base64Decode(
    'ChF0aHNyX3NlYXRfc2VnbWVudBIqChFvcmlnaW5fc3RhdGlvbl9pZBgBIAEoCVIPb3JpZ2luU3'
    'RhdGlvbklkEjQKFmRlc3RpbmF0aW9uX3N0YXRpb25faWQYAiABKAlSFGRlc3RpbmF0aW9uU3Rh'
    'dGlvbklkEjAKFHN0YW5kYXJkX3NlYXRfc3RhdHVzGAMgASgJUhJzdGFuZGFyZFNlYXRTdGF0dX'
    'MSMAoUYnVzaW5lc3Nfc2VhdF9zdGF0dXMYBCABKAlSEmJ1c2luZXNzU2VhdFN0YXR1cw==');

@$core.Deprecated('Use thsr_available_seatsDescriptor instead')
const thsr_available_seats$json = {
  '1': 'thsr_available_seats',
  '2': [
    {'1': 'train_no', '3': 1, '4': 1, '5': 9, '10': 'trainNo'},
    {
      '1': 'segments',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.thsr_seat_segment',
      '10': 'segments'
    },
  ],
};

/// Descriptor for `thsr_available_seats`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List thsr_available_seatsDescriptor = $convert.base64Decode(
    'ChR0aHNyX2F2YWlsYWJsZV9zZWF0cxIZCgh0cmFpbl9ubxgBIAEoCVIHdHJhaW5ObxIuCghzZW'
    'dtZW50cxgDIAMoCzISLnRoc3Jfc2VhdF9zZWdtZW50UghzZWdtZW50cw==');

@$core.Deprecated('Use resp_thsr_seatsDescriptor instead')
const Resp_thsr_seats$json = {
  '1': 'Resp_thsr_seats',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `Resp_thsr_seats`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resp_thsr_seatsDescriptor = $convert
    .base64Decode('Cg9SZXNwX3Roc3Jfc2VhdHMSEgoEZGF0YRgBIAEoDFIEZGF0YQ==');
