// This is a generated file - do not edit.
//
// Generated from tra.proto.

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

@$core.Deprecated('Use resp_tra_live_boardDescriptor instead')
const Resp_tra_live_board$json = {
  '1': 'Resp_tra_live_board',
  '2': [
    {
      '1': 'data',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.tra_LiveBoards',
      '10': 'data'
    },
  ],
};

/// Descriptor for `Resp_tra_live_board`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resp_tra_live_boardDescriptor = $convert.base64Decode(
    'ChNSZXNwX3RyYV9saXZlX2JvYXJkEiMKBGRhdGEYASABKAsyDy50cmFfTGl2ZUJvYXJkc1IEZG'
    'F0YQ==');

@$core.Deprecated('Use resp_tra_delayDescriptor instead')
const Resp_tra_delay$json = {
  '1': 'Resp_tra_delay',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 11, '6': '.tra_delays', '10': 'data'},
  ],
};

/// Descriptor for `Resp_tra_delay`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resp_tra_delayDescriptor = $convert.base64Decode(
    'Cg5SZXNwX3RyYV9kZWxheRIfCgRkYXRhGAEgASgLMgsudHJhX2RlbGF5c1IEZGF0YQ==');

@$core.Deprecated('Use ask_detainDescriptor instead')
const ask_detain$json = {
  '1': 'ask_detain',
  '2': [
    {'1': 'date', '3': 1, '4': 1, '5': 9, '10': 'date'},
    {'1': 'trainno', '3': 2, '4': 1, '5': 9, '10': 'trainno'},
  ],
};

/// Descriptor for `ask_detain`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ask_detainDescriptor = $convert.base64Decode(
    'Cgphc2tfZGV0YWluEhIKBGRhdGUYASABKAlSBGRhdGUSGAoHdHJhaW5ubxgCIAEoCVIHdHJhaW'
    '5ubw==');

@$core.Deprecated('Use ask_routeDescriptor instead')
const ask_route$json = {
  '1': 'ask_route',
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

/// Descriptor for `ask_route`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ask_routeDescriptor = $convert.base64Decode(
    'Cglhc2tfcm91dGUSEgoEZGF0ZRgBIAEoCVIEZGF0ZRIqChFvcmlnaW5fc3RhdGlvbl9pZBgCIA'
    'EoCVIPb3JpZ2luU3RhdGlvbklkEjQKFmRlc3RpbmF0aW9uX3N0YXRpb25faWQYAyABKAlSFGRl'
    'c3RpbmF0aW9uU3RhdGlvbklk');

@$core.Deprecated('Use ask_staitonDescriptor instead')
const ask_staiton$json = {
  '1': 'ask_staiton',
  '2': [
    {'1': 'station_id', '3': 1, '4': 1, '5': 9, '10': 'stationId'},
    {'1': 'date', '3': 2, '4': 1, '5': 9, '10': 'date'},
  ],
};

/// Descriptor for `ask_staiton`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ask_staitonDescriptor = $convert.base64Decode(
    'Cgthc2tfc3RhaXRvbhIdCgpzdGF0aW9uX2lkGAEgASgJUglzdGF0aW9uSWQSEgoEZGF0ZRgCIA'
    'EoCVIEZGF0ZQ==');

@$core.Deprecated('Use traFareItemDescriptor instead')
const TraFareItem$json = {
  '1': 'TraFareItem',
  '2': [
    {'1': 'origin_station_id', '3': 1, '4': 1, '5': 9, '10': 'originStationId'},
    {
      '1': 'destination_station_id',
      '3': 2,
      '4': 1,
      '5': 9,
      '10': 'destinationStationId'
    },
    {'1': 'ticket_type', '3': 3, '4': 1, '5': 9, '10': 'ticketType'},
    {'1': 'price', '3': 4, '4': 1, '5': 5, '10': 'price'},
  ],
};

/// Descriptor for `TraFareItem`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List traFareItemDescriptor = $convert.base64Decode(
    'CgtUcmFGYXJlSXRlbRIqChFvcmlnaW5fc3RhdGlvbl9pZBgBIAEoCVIPb3JpZ2luU3RhdGlvbk'
    'lkEjQKFmRlc3RpbmF0aW9uX3N0YXRpb25faWQYAiABKAlSFGRlc3RpbmF0aW9uU3RhdGlvbklk'
    'Eh8KC3RpY2tldF90eXBlGAMgASgJUgp0aWNrZXRUeXBlEhQKBXByaWNlGAQgASgFUgVwcmljZQ'
    '==');

@$core.Deprecated('Use tra_fare_itemsDescriptor instead')
const tra_fare_items$json = {
  '1': 'tra_fare_items',
  '2': [
    {'1': 'items', '3': 1, '4': 3, '5': 11, '6': '.TraFareItem', '10': 'items'},
  ],
};

/// Descriptor for `tra_fare_items`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tra_fare_itemsDescriptor = $convert.base64Decode(
    'Cg50cmFfZmFyZV9pdGVtcxIiCgVpdGVtcxgBIAMoCzIMLlRyYUZhcmVJdGVtUgVpdGVtcw==');

@$core.Deprecated('Use tra_timetablesDescriptor instead')
const tra_timetables$json = {
  '1': 'tra_timetables',
  '2': [
    {
      '1': 'items',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.tra_timetable',
      '10': 'items'
    },
  ],
};

/// Descriptor for `tra_timetables`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tra_timetablesDescriptor = $convert.base64Decode(
    'Cg50cmFfdGltZXRhYmxlcxIkCgVpdGVtcxgBIAMoCzIOLnRyYV90aW1ldGFibGVSBWl0ZW1z');

@$core.Deprecated('Use tra_stoptimesDescriptor instead')
const tra_stoptimes$json = {
  '1': 'tra_stoptimes',
  '2': [
    {
      '1': 'items',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.tra_stoptime',
      '10': 'items'
    },
  ],
};

/// Descriptor for `tra_stoptimes`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tra_stoptimesDescriptor = $convert.base64Decode(
    'Cg10cmFfc3RvcHRpbWVzEiMKBWl0ZW1zGAEgAygLMg0udHJhX3N0b3B0aW1lUgVpdGVtcw==');

@$core.Deprecated('Use tra_delaysDescriptor instead')
const tra_delays$json = {
  '1': 'tra_delays',
  '2': [
    {
      '1': 'delay',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.tra_delays.DelayEntry',
      '10': 'delay'
    },
  ],
  '3': [tra_delays_DelayEntry$json],
};

@$core.Deprecated('Use tra_delaysDescriptor instead')
const tra_delays_DelayEntry$json = {
  '1': 'DelayEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 5, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `tra_delays`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tra_delaysDescriptor = $convert.base64Decode(
    'Cgp0cmFfZGVsYXlzEiwKBWRlbGF5GAEgAygLMhYudHJhX2RlbGF5cy5EZWxheUVudHJ5UgVkZW'
    'xheRo4CgpEZWxheUVudHJ5EhAKA2tleRgBIAEoCVIDa2V5EhQKBXZhbHVlGAIgASgFUgV2YWx1'
    'ZToCOAE=');

@$core.Deprecated('Use tra_stoptimeDescriptor instead')
const tra_stoptime$json = {
  '1': 'tra_stoptime',
  '2': [
    {'1': 'stop_sequence', '3': 3, '4': 1, '5': 5, '10': 'stopSequence'},
    {'1': 'station_id', '3': 1, '4': 1, '5': 9, '10': 'stationId'},
    {'1': 'station_name', '3': 2, '4': 1, '5': 9, '10': 'stationName'},
    {'1': 'ArrivalTime', '3': 4, '4': 1, '5': 9, '10': 'ArrivalTime'},
    {'1': 'DepartureTime', '3': 5, '4': 1, '5': 9, '10': 'DepartureTime'},
    {'1': 'SuspendedFlag', '3': 6, '4': 1, '5': 8, '10': 'SuspendedFlag'},
  ],
};

/// Descriptor for `tra_stoptime`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tra_stoptimeDescriptor = $convert.base64Decode(
    'Cgx0cmFfc3RvcHRpbWUSIwoNc3RvcF9zZXF1ZW5jZRgDIAEoBVIMc3RvcFNlcXVlbmNlEh0KCn'
    'N0YXRpb25faWQYASABKAlSCXN0YXRpb25JZBIhCgxzdGF0aW9uX25hbWUYAiABKAlSC3N0YXRp'
    'b25OYW1lEiAKC0Fycml2YWxUaW1lGAQgASgJUgtBcnJpdmFsVGltZRIkCg1EZXBhcnR1cmVUaW'
    '1lGAUgASgJUg1EZXBhcnR1cmVUaW1lEiQKDVN1c3BlbmRlZEZsYWcYBiABKAhSDVN1c3BlbmRl'
    'ZEZsYWc=');

@$core.Deprecated('Use tra_timetableDescriptor instead')
const tra_timetable$json = {
  '1': 'tra_timetable',
  '2': [
    {'1': 'TrainDate', '3': 1, '4': 1, '5': 9, '10': 'TrainDate'},
    {'1': 'TrainNo', '3': 2, '4': 1, '5': 9, '10': 'TrainNo'},
    {'1': 'Direction', '3': 3, '4': 1, '5': 5, '10': 'Direction'},
    {
      '1': 'Starting_Station_Name',
      '3': 4,
      '4': 1,
      '5': 9,
      '10': 'StartingStationName'
    },
    {
      '1': 'Ending_Station_Name',
      '3': 5,
      '4': 1,
      '5': 9,
      '10': 'EndingStationName'
    },
    {'1': 'TrainTypeID', '3': 6, '4': 1, '5': 9, '10': 'TrainTypeID'},
    {'1': 'TrainTypeCode', '3': 7, '4': 1, '5': 9, '10': 'TrainTypeCode'},
    {'1': 'TrainTypeName', '3': 8, '4': 1, '5': 9, '10': 'TrainTypeName'},
    {'1': 'TripLine', '3': 9, '4': 1, '5': 5, '10': 'TripLine'},
    {'1': 'mask', '3': 10, '4': 1, '5': 5, '10': 'mask'},
    {'1': 'Note', '3': 11, '4': 1, '5': 9, '10': 'Note'},
    {'1': 'Starting_Time', '3': 12, '4': 1, '5': 9, '10': 'StartingTime'},
    {'1': 'Ending_Time', '3': 13, '4': 1, '5': 9, '10': 'EndingTime'},
    {'1': 'Travel_Time', '3': 14, '4': 1, '5': 9, '10': 'TravelTime'},
  ],
};

/// Descriptor for `tra_timetable`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tra_timetableDescriptor = $convert.base64Decode(
    'Cg10cmFfdGltZXRhYmxlEhwKCVRyYWluRGF0ZRgBIAEoCVIJVHJhaW5EYXRlEhgKB1RyYWluTm'
    '8YAiABKAlSB1RyYWluTm8SHAoJRGlyZWN0aW9uGAMgASgFUglEaXJlY3Rpb24SMgoVU3RhcnRp'
    'bmdfU3RhdGlvbl9OYW1lGAQgASgJUhNTdGFydGluZ1N0YXRpb25OYW1lEi4KE0VuZGluZ19TdG'
    'F0aW9uX05hbWUYBSABKAlSEUVuZGluZ1N0YXRpb25OYW1lEiAKC1RyYWluVHlwZUlEGAYgASgJ'
    'UgtUcmFpblR5cGVJRBIkCg1UcmFpblR5cGVDb2RlGAcgASgJUg1UcmFpblR5cGVDb2RlEiQKDV'
    'RyYWluVHlwZU5hbWUYCCABKAlSDVRyYWluVHlwZU5hbWUSGgoIVHJpcExpbmUYCSABKAVSCFRy'
    'aXBMaW5lEhIKBG1hc2sYCiABKAVSBG1hc2sSEgoETm90ZRgLIAEoCVIETm90ZRIjCg1TdGFydG'
    'luZ19UaW1lGAwgASgJUgxTdGFydGluZ1RpbWUSHwoLRW5kaW5nX1RpbWUYDSABKAlSCkVuZGlu'
    'Z1RpbWUSHwoLVHJhdmVsX1RpbWUYDiABKAlSClRyYXZlbFRpbWU=');

@$core.Deprecated('Use tra_delayDescriptor instead')
const tra_delay$json = {
  '1': 'tra_delay',
  '2': [
    {'1': 'train_no', '3': 1, '4': 1, '5': 9, '10': 'trainNo'},
    {'1': 'station_id', '3': 2, '4': 1, '5': 9, '10': 'stationId'},
    {'1': 'delay', '3': 3, '4': 1, '5': 5, '10': 'delay'},
  ],
};

/// Descriptor for `tra_delay`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tra_delayDescriptor = $convert.base64Decode(
    'Cgl0cmFfZGVsYXkSGQoIdHJhaW5fbm8YASABKAlSB3RyYWluTm8SHQoKc3RhdGlvbl9pZBgCIA'
    'EoCVIJc3RhdGlvbklkEhQKBWRlbGF5GAMgASgFUgVkZWxheQ==');

@$core.Deprecated('Use tra_LiveBoardDescriptor instead')
const tra_LiveBoard$json = {
  '1': 'tra_LiveBoard',
  '2': [
    {'1': 'train_no', '3': 1, '4': 1, '5': 9, '10': 'trainNo'},
    {'1': 'direction', '3': 2, '4': 1, '5': 8, '10': 'direction'},
    {'1': 'train_type_id', '3': 3, '4': 1, '5': 9, '10': 'trainTypeId'},
    {'1': 'train_type_code', '3': 4, '4': 1, '5': 9, '10': 'trainTypeCode'},
    {'1': 'train_type_name', '3': 5, '4': 1, '5': 9, '10': 'trainTypeName'},
    {'1': 'ending_station_id', '3': 6, '4': 1, '5': 9, '10': 'endingStationId'},
    {
      '1': 'ending_station_name',
      '3': 7,
      '4': 1,
      '5': 9,
      '10': 'endingStationName'
    },
    {
      '1': 'scheduled_arrival_time',
      '3': 8,
      '4': 1,
      '5': 9,
      '10': 'scheduledArrivalTime'
    },
    {
      '1': 'scheduled_departure_time',
      '3': 9,
      '4': 1,
      '5': 9,
      '10': 'scheduledDepartureTime'
    },
    {'1': 'delay', '3': 10, '4': 1, '5': 5, '10': 'delay'},
    {'1': 'trip_line', '3': 11, '4': 1, '5': 5, '10': 'tripLine'},
  ],
};

/// Descriptor for `tra_LiveBoard`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tra_LiveBoardDescriptor = $convert.base64Decode(
    'Cg10cmFfTGl2ZUJvYXJkEhkKCHRyYWluX25vGAEgASgJUgd0cmFpbk5vEhwKCWRpcmVjdGlvbh'
    'gCIAEoCFIJZGlyZWN0aW9uEiIKDXRyYWluX3R5cGVfaWQYAyABKAlSC3RyYWluVHlwZUlkEiYK'
    'D3RyYWluX3R5cGVfY29kZRgEIAEoCVINdHJhaW5UeXBlQ29kZRImCg90cmFpbl90eXBlX25hbW'
    'UYBSABKAlSDXRyYWluVHlwZU5hbWUSKgoRZW5kaW5nX3N0YXRpb25faWQYBiABKAlSD2VuZGlu'
    'Z1N0YXRpb25JZBIuChNlbmRpbmdfc3RhdGlvbl9uYW1lGAcgASgJUhFlbmRpbmdTdGF0aW9uTm'
    'FtZRI0ChZzY2hlZHVsZWRfYXJyaXZhbF90aW1lGAggASgJUhRzY2hlZHVsZWRBcnJpdmFsVGlt'
    'ZRI4ChhzY2hlZHVsZWRfZGVwYXJ0dXJlX3RpbWUYCSABKAlSFnNjaGVkdWxlZERlcGFydHVyZV'
    'RpbWUSFAoFZGVsYXkYCiABKAVSBWRlbGF5EhsKCXRyaXBfbGluZRgLIAEoBVIIdHJpcExpbmU=');

@$core.Deprecated('Use tra_LiveBoardsDescriptor instead')
const tra_LiveBoards$json = {
  '1': 'tra_LiveBoards',
  '2': [
    {'1': 'station_id', '3': 1, '4': 1, '5': 9, '10': 'stationId'},
    {
      '1': 'items',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.tra_LiveBoard',
      '10': 'items'
    },
  ],
};

/// Descriptor for `tra_LiveBoards`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tra_LiveBoardsDescriptor = $convert.base64Decode(
    'Cg50cmFfTGl2ZUJvYXJkcxIdCgpzdGF0aW9uX2lkGAEgASgJUglzdGF0aW9uSWQSJAoFaXRlbX'
    'MYAiADKAsyDi50cmFfTGl2ZUJvYXJkUgVpdGVtcw==');
