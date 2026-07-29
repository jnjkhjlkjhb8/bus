// This is a generated file - do not edit.
//
// Generated from bus.proto.

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

@$core.Deprecated('Use bus_Ask_RouteDescriptor instead')
const Bus_Ask_Route$json = {
  '1': 'Bus_Ask_Route',
  '2': [
    {'1': 'SubRouteUID', '3': 1, '4': 1, '5': 9, '10': 'SubRouteUID'},
  ],
};

/// Descriptor for `Bus_Ask_Route`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_Ask_RouteDescriptor = $convert.base64Decode(
    'Cg1CdXNfQXNrX1JvdXRlEiAKC1N1YlJvdXRlVUlEGAEgASgJUgtTdWJSb3V0ZVVJRA==');

@$core.Deprecated('Use bus_Ask_StationGroupDescriptor instead')
const Bus_Ask_StationGroup$json = {
  '1': 'Bus_Ask_StationGroup',
  '2': [
    {'1': 'city', '3': 1, '4': 1, '5': 9, '10': 'city'},
    {'1': 'group_uid', '3': 2, '4': 1, '5': 9, '10': 'groupUid'},
  ],
};

/// Descriptor for `Bus_Ask_StationGroup`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_Ask_StationGroupDescriptor = $convert.base64Decode(
    'ChRCdXNfQXNrX1N0YXRpb25Hcm91cBISCgRjaXR5GAEgASgJUgRjaXR5EhsKCWdyb3VwX3VpZB'
    'gCIAEoCVIIZ3JvdXBVaWQ=');

@$core.Deprecated('Use bus_Ask_StationDescriptor instead')
const Bus_Ask_Station$json = {
  '1': 'Bus_Ask_Station',
  '2': [
    {'1': 'StationName', '3': 1, '4': 1, '5': 9, '10': 'StationName'},
    {'1': 'city', '3': 2, '4': 1, '5': 9, '10': 'city'},
  ],
};

/// Descriptor for `Bus_Ask_Station`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_Ask_StationDescriptor = $convert.base64Decode(
    'Cg9CdXNfQXNrX1N0YXRpb24SIAoLU3RhdGlvbk5hbWUYASABKAlSC1N0YXRpb25OYW1lEhIKBG'
    'NpdHkYAiABKAlSBGNpdHk=');

@$core.Deprecated('Use resp_Bus_staticDescriptor instead')
const Resp_Bus_static$json = {
  '1': 'Resp_Bus_static',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 11, '6': '.Bus_subroute', '10': 'data'},
  ],
};

/// Descriptor for `Resp_Bus_static`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resp_Bus_staticDescriptor = $convert.base64Decode(
    'Cg9SZXNwX0J1c19zdGF0aWMSIQoEZGF0YRgBIAEoCzINLkJ1c19zdWJyb3V0ZVIEZGF0YQ==');

@$core.Deprecated('Use resp_Bus_etaDescriptor instead')
const Resp_Bus_eta$json = {
  '1': 'Resp_Bus_eta',
  '2': [
    {
      '1': 'data',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.Bus_RouteArrival',
      '10': 'data'
    },
  ],
};

/// Descriptor for `Resp_Bus_eta`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resp_Bus_etaDescriptor = $convert.base64Decode(
    'CgxSZXNwX0J1c19ldGESJQoEZGF0YRgBIAEoCzIRLkJ1c19Sb3V0ZUFycml2YWxSBGRhdGE=');

@$core.Deprecated('Use resp_Bus_station_etaDescriptor instead')
const Resp_Bus_station_eta$json = {
  '1': 'Resp_Bus_station_eta',
  '2': [
    {
      '1': 'data',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.Bus_StationArrival',
      '10': 'data'
    },
  ],
};

/// Descriptor for `Resp_Bus_station_eta`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resp_Bus_station_etaDescriptor = $convert.base64Decode(
    'ChRSZXNwX0J1c19zdGF0aW9uX2V0YRInCgRkYXRhGAEgASgLMhMuQnVzX1N0YXRpb25BcnJpdm'
    'FsUgRkYXRh');

@$core.Deprecated('Use resp_Bus_daily_timetableDescriptor instead')
const Resp_Bus_daily_timetable$json = {
  '1': 'Resp_Bus_daily_timetable',
  '2': [
    {
      '1': 'data',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.Bus_DailyTimetables',
      '10': 'data'
    },
  ],
};

/// Descriptor for `Resp_Bus_daily_timetable`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resp_Bus_daily_timetableDescriptor =
    $convert.base64Decode(
        'ChhSZXNwX0J1c19kYWlseV90aW1ldGFibGUSKAoEZGF0YRgBIAEoCzIULkJ1c19EYWlseVRpbW'
        'V0YWJsZXNSBGRhdGE=');

@$core.Deprecated('Use busOperatorDescriptor instead')
const BusOperator$json = {
  '1': 'BusOperator',
  '2': [
    {'1': 'operator_id', '3': 1, '4': 1, '5': 9, '10': 'operatorId'},
    {'1': 'operator_name', '3': 2, '4': 1, '5': 9, '10': 'operatorName'},
    {'1': 'operator_phone', '3': 3, '4': 1, '5': 9, '10': 'operatorPhone'},
    {'1': 'operator_url', '3': 4, '4': 1, '5': 9, '10': 'operatorUrl'},
  ],
};

/// Descriptor for `BusOperator`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List busOperatorDescriptor = $convert.base64Decode(
    'CgtCdXNPcGVyYXRvchIfCgtvcGVyYXRvcl9pZBgBIAEoCVIKb3BlcmF0b3JJZBIjCg1vcGVyYX'
    'Rvcl9uYW1lGAIgASgJUgxvcGVyYXRvck5hbWUSJQoOb3BlcmF0b3JfcGhvbmUYAyABKAlSDW9w'
    'ZXJhdG9yUGhvbmUSIQoMb3BlcmF0b3JfdXJsGAQgASgJUgtvcGVyYXRvclVybA==');

@$core.Deprecated('Use bus_subrouteDescriptor instead')
const Bus_subroute$json = {
  '1': 'Bus_subroute',
  '2': [
    {'1': 'RouteUID', '3': 1, '4': 1, '5': 9, '10': 'RouteUID'},
    {'1': 'RouteName', '3': 2, '4': 1, '5': 9, '10': 'RouteName'},
    {'1': 'SubRouteUID', '3': 3, '4': 1, '5': 9, '10': 'SubRouteUID'},
    {'1': 'SubRouteName', '3': 4, '4': 1, '5': 9, '10': 'SubRouteName'},
    {
      '1': 'DepartureStopName',
      '3': 5,
      '4': 1,
      '5': 9,
      '10': 'DepartureStopName'
    },
    {
      '1': 'DestinationStopName',
      '3': 6,
      '4': 1,
      '5': 9,
      '10': 'DestinationStopName'
    },
    {'1': 'city', '3': 7, '4': 1, '5': 9, '10': 'city'},
    {
      '1': 'Directions',
      '3': 8,
      '4': 3,
      '5': 11,
      '6': '.Bus_subroute.DirectionsEntry',
      '10': 'Directions'
    },
    {
      '1': 'operators',
      '3': 9,
      '4': 3,
      '5': 11,
      '6': '.BusOperator',
      '10': 'operators'
    },
    {'1': 'fare', '3': 10, '4': 1, '5': 11, '6': '.Bus_Fare', '10': 'fare'},
  ],
  '3': [Bus_subroute_DirectionsEntry$json],
};

@$core.Deprecated('Use bus_subrouteDescriptor instead')
const Bus_subroute_DirectionsEntry$json = {
  '1': 'DirectionsEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 5, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 11, '6': '.Direction', '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `Bus_subroute`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_subrouteDescriptor = $convert.base64Decode(
    'CgxCdXNfc3Vicm91dGUSGgoIUm91dGVVSUQYASABKAlSCFJvdXRlVUlEEhwKCVJvdXRlTmFtZR'
    'gCIAEoCVIJUm91dGVOYW1lEiAKC1N1YlJvdXRlVUlEGAMgASgJUgtTdWJSb3V0ZVVJRBIiCgxT'
    'dWJSb3V0ZU5hbWUYBCABKAlSDFN1YlJvdXRlTmFtZRIsChFEZXBhcnR1cmVTdG9wTmFtZRgFIA'
    'EoCVIRRGVwYXJ0dXJlU3RvcE5hbWUSMAoTRGVzdGluYXRpb25TdG9wTmFtZRgGIAEoCVITRGVz'
    'dGluYXRpb25TdG9wTmFtZRISCgRjaXR5GAcgASgJUgRjaXR5Ej0KCkRpcmVjdGlvbnMYCCADKA'
    'syHS5CdXNfc3Vicm91dGUuRGlyZWN0aW9uc0VudHJ5UgpEaXJlY3Rpb25zEioKCW9wZXJhdG9y'
    'cxgJIAMoCzIMLkJ1c09wZXJhdG9yUglvcGVyYXRvcnMSHQoEZmFyZRgKIAEoCzIJLkJ1c19GYX'
    'JlUgRmYXJlGkkKD0RpcmVjdGlvbnNFbnRyeRIQCgNrZXkYASABKAVSA2tleRIgCgV2YWx1ZRgC'
    'IAEoCzIKLkRpcmVjdGlvblIFdmFsdWU6AjgB');

@$core.Deprecated('Use directionDescriptor instead')
const Direction$json = {
  '1': 'Direction',
  '2': [
    {
      '1': 'DepartureStopName',
      '3': 1,
      '4': 1,
      '5': 9,
      '10': 'DepartureStopName'
    },
    {
      '1': 'DestinationStopName',
      '3': 2,
      '4': 1,
      '5': 9,
      '10': 'DestinationStopName'
    },
    {'1': 'Geometry', '3': 3, '4': 1, '5': 9, '10': 'Geometry'},
    {'1': 'Stops', '3': 4, '4': 3, '5': 11, '6': '.Bus_stop', '10': 'Stops'},
    {
      '1': 'Schedules',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.Bus_Schedule',
      '10': 'Schedules'
    },
    {'1': 'first_bus_time', '3': 6, '4': 1, '5': 9, '10': 'firstBusTime'},
    {'1': 'last_bus_time', '3': 7, '4': 1, '5': 9, '10': 'lastBusTime'},
    {
      '1': 'holiday_first_bus_time',
      '3': 8,
      '4': 1,
      '5': 9,
      '10': 'holidayFirstBusTime'
    },
    {
      '1': 'holiday_last_bus_time',
      '3': 9,
      '4': 1,
      '5': 9,
      '10': 'holidayLastBusTime'
    },
  ],
};

/// Descriptor for `Direction`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List directionDescriptor = $convert.base64Decode(
    'CglEaXJlY3Rpb24SLAoRRGVwYXJ0dXJlU3RvcE5hbWUYASABKAlSEURlcGFydHVyZVN0b3BOYW'
    '1lEjAKE0Rlc3RpbmF0aW9uU3RvcE5hbWUYAiABKAlSE0Rlc3RpbmF0aW9uU3RvcE5hbWUSGgoI'
    'R2VvbWV0cnkYAyABKAlSCEdlb21ldHJ5Eh8KBVN0b3BzGAQgAygLMgkuQnVzX3N0b3BSBVN0b3'
    'BzEisKCVNjaGVkdWxlcxgFIAMoCzINLkJ1c19TY2hlZHVsZVIJU2NoZWR1bGVzEiQKDmZpcnN0'
    'X2J1c190aW1lGAYgASgJUgxmaXJzdEJ1c1RpbWUSIgoNbGFzdF9idXNfdGltZRgHIAEoCVILbG'
    'FzdEJ1c1RpbWUSMwoWaG9saWRheV9maXJzdF9idXNfdGltZRgIIAEoCVITaG9saWRheUZpcnN0'
    'QnVzVGltZRIxChVob2xpZGF5X2xhc3RfYnVzX3RpbWUYCSABKAlSEmhvbGlkYXlMYXN0QnVzVG'
    'ltZQ==');

@$core.Deprecated('Use bus_stopDescriptor instead')
const Bus_stop$json = {
  '1': 'Bus_stop',
  '2': [
    {'1': 'StopUID', '3': 1, '4': 1, '5': 9, '10': 'StopUID'},
    {'1': 'StopName', '3': 2, '4': 1, '5': 9, '10': 'StopName'},
    {'1': 'StopSequence', '3': 3, '4': 1, '5': 5, '10': 'StopSequence'},
    {'1': 'PositionLon', '3': 4, '4': 1, '5': 1, '10': 'PositionLon'},
    {'1': 'PositionLat', '3': 5, '4': 1, '5': 1, '10': 'PositionLat'},
    {'1': 'StationID', '3': 6, '4': 1, '5': 9, '10': 'StationID'},
  ],
};

/// Descriptor for `Bus_stop`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_stopDescriptor = $convert.base64Decode(
    'CghCdXNfc3RvcBIYCgdTdG9wVUlEGAEgASgJUgdTdG9wVUlEEhoKCFN0b3BOYW1lGAIgASgJUg'
    'hTdG9wTmFtZRIiCgxTdG9wU2VxdWVuY2UYAyABKAVSDFN0b3BTZXF1ZW5jZRIgCgtQb3NpdGlv'
    'bkxvbhgEIAEoAVILUG9zaXRpb25Mb24SIAoLUG9zaXRpb25MYXQYBSABKAFSC1Bvc2l0aW9uTG'
    'F0EhwKCVN0YXRpb25JRBgGIAEoCVIJU3RhdGlvbklE');

@$core.Deprecated('Use routeOfStopDescriptor instead')
const RouteOfStop$json = {
  '1': 'RouteOfStop',
  '2': [
    {'1': 'SubRouteUID', '3': 2, '4': 1, '5': 9, '10': 'SubRouteUID'},
    {'1': 'Direction', '3': 3, '4': 1, '5': 5, '10': 'Direction'},
    {'1': 'Stops', '3': 4, '4': 3, '5': 11, '6': '.Bus_stop', '10': 'Stops'},
  ],
  '9': [
    {'1': 1, '2': 2},
  ],
};

/// Descriptor for `RouteOfStop`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List routeOfStopDescriptor = $convert.base64Decode(
    'CgtSb3V0ZU9mU3RvcBIgCgtTdWJSb3V0ZVVJRBgCIAEoCVILU3ViUm91dGVVSUQSHAoJRGlyZW'
    'N0aW9uGAMgASgFUglEaXJlY3Rpb24SHwoFU3RvcHMYBCADKAsyCS5CdXNfc3RvcFIFU3RvcHNK'
    'BAgBEAI=');

@$core.Deprecated('Use shapeDescriptor instead')
const Shape$json = {
  '1': 'Shape',
  '2': [
    {'1': 'SubRouteUID', '3': 1, '4': 1, '5': 9, '10': 'SubRouteUID'},
    {'1': 'Direction', '3': 2, '4': 1, '5': 5, '10': 'Direction'},
    {'1': 'Geometry', '3': 3, '4': 1, '5': 9, '10': 'Geometry'},
  ],
};

/// Descriptor for `Shape`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List shapeDescriptor = $convert.base64Decode(
    'CgVTaGFwZRIgCgtTdWJSb3V0ZVVJRBgBIAEoCVILU3ViUm91dGVVSUQSHAoJRGlyZWN0aW9uGA'
    'IgASgFUglEaXJlY3Rpb24SGgoIR2VvbWV0cnkYAyABKAlSCEdlb21ldHJ5');

@$core.Deprecated('Use stationDescriptor instead')
const Station$json = {
  '1': 'Station',
  '2': [
    {'1': 'StationUID', '3': 1, '4': 1, '5': 9, '10': 'StationUID'},
    {'1': 'StationName', '3': 2, '4': 1, '5': 9, '10': 'StationName'},
    {'1': 'city', '3': 3, '4': 1, '5': 9, '10': 'city'},
    {'1': 'PositionLon', '3': 4, '4': 1, '5': 1, '10': 'PositionLon'},
    {'1': 'PositionLat', '3': 5, '4': 1, '5': 1, '10': 'PositionLat'},
  ],
};

/// Descriptor for `Station`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stationDescriptor = $convert.base64Decode(
    'CgdTdGF0aW9uEh4KClN0YXRpb25VSUQYASABKAlSClN0YXRpb25VSUQSIAoLU3RhdGlvbk5hbW'
    'UYAiABKAlSC1N0YXRpb25OYW1lEhIKBGNpdHkYAyABKAlSBGNpdHkSIAoLUG9zaXRpb25Mb24Y'
    'BCABKAFSC1Bvc2l0aW9uTG9uEiAKC1Bvc2l0aW9uTGF0GAUgASgBUgtQb3NpdGlvbkxhdA==');

@$core.Deprecated('Use bus_StationGroupDescriptor instead')
const Bus_StationGroup$json = {
  '1': 'Bus_StationGroup',
  '2': [
    {'1': 'group_uid', '3': 1, '4': 1, '5': 9, '10': 'groupUid'},
    {'1': 'group_name', '3': 2, '4': 1, '5': 9, '10': 'groupName'},
    {'1': 'city', '3': 3, '4': 1, '5': 9, '10': 'city'},
    {'1': 'position_lon', '3': 4, '4': 1, '5': 1, '10': 'positionLon'},
    {'1': 'position_lat', '3': 5, '4': 1, '5': 1, '10': 'positionLat'},
    {
      '1': 'members',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.Bus_StationGroupMember',
      '10': 'members'
    },
  ],
};

/// Descriptor for `Bus_StationGroup`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_StationGroupDescriptor = $convert.base64Decode(
    'ChBCdXNfU3RhdGlvbkdyb3VwEhsKCWdyb3VwX3VpZBgBIAEoCVIIZ3JvdXBVaWQSHQoKZ3JvdX'
    'BfbmFtZRgCIAEoCVIJZ3JvdXBOYW1lEhIKBGNpdHkYAyABKAlSBGNpdHkSIQoMcG9zaXRpb25f'
    'bG9uGAQgASgBUgtwb3NpdGlvbkxvbhIhCgxwb3NpdGlvbl9sYXQYBSABKAFSC3Bvc2l0aW9uTG'
    'F0EjEKB21lbWJlcnMYBiADKAsyFy5CdXNfU3RhdGlvbkdyb3VwTWVtYmVyUgdtZW1iZXJz');

@$core.Deprecated('Use bus_StationGroupMemberDescriptor instead')
const Bus_StationGroupMember$json = {
  '1': 'Bus_StationGroupMember',
  '2': [
    {'1': 'station_uid', '3': 1, '4': 1, '5': 9, '10': 'stationUid'},
    {'1': 'station_id', '3': 2, '4': 1, '5': 9, '10': 'stationId'},
    {'1': 'station_name', '3': 3, '4': 1, '5': 9, '10': 'stationName'},
    {'1': 'position_lon', '3': 4, '4': 1, '5': 1, '10': 'positionLon'},
    {'1': 'position_lat', '3': 5, '4': 1, '5': 1, '10': 'positionLat'},
  ],
};

/// Descriptor for `Bus_StationGroupMember`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_StationGroupMemberDescriptor = $convert.base64Decode(
    'ChZCdXNfU3RhdGlvbkdyb3VwTWVtYmVyEh8KC3N0YXRpb25fdWlkGAEgASgJUgpzdGF0aW9uVW'
    'lkEh0KCnN0YXRpb25faWQYAiABKAlSCXN0YXRpb25JZBIhCgxzdGF0aW9uX25hbWUYAyABKAlS'
    'C3N0YXRpb25OYW1lEiEKDHBvc2l0aW9uX2xvbhgEIAEoAVILcG9zaXRpb25Mb24SIQoMcG9zaX'
    'Rpb25fbGF0GAUgASgBUgtwb3NpdGlvbkxhdA==');

@$core.Deprecated('Use bus_RouteArrivalDescriptor instead')
const Bus_RouteArrival$json = {
  '1': 'Bus_RouteArrival',
  '2': [
    {'1': 'sub_route_uid', '3': 1, '4': 1, '5': 9, '10': 'subRouteUid'},
    {
      '1': 'stops',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.Bus_RouteEstimate',
      '10': 'stops'
    },
  ],
  '9': [
    {'1': 2, '2': 3},
  ],
};

/// Descriptor for `Bus_RouteArrival`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_RouteArrivalDescriptor = $convert.base64Decode(
    'ChBCdXNfUm91dGVBcnJpdmFsEiIKDXN1Yl9yb3V0ZV91aWQYASABKAlSC3N1YlJvdXRlVWlkEi'
    'gKBXN0b3BzGAMgAygLMhIuQnVzX1JvdXRlRXN0aW1hdGVSBXN0b3BzSgQIAhAD');

@$core.Deprecated('Use bus_StationArrivalDescriptor instead')
const Bus_StationArrival$json = {
  '1': 'Bus_StationArrival',
  '2': [
    {'1': 'station_name', '3': 1, '4': 1, '5': 9, '10': 'stationName'},
    {'1': 'station_uid', '3': 2, '4': 3, '5': 9, '10': 'stationUid'},
    {
      '1': 'routes',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.Bus_StopEstimate',
      '10': 'routes'
    },
  ],
};

/// Descriptor for `Bus_StationArrival`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_StationArrivalDescriptor = $convert.base64Decode(
    'ChJCdXNfU3RhdGlvbkFycml2YWwSIQoMc3RhdGlvbl9uYW1lGAEgASgJUgtzdGF0aW9uTmFtZR'
    'IfCgtzdGF0aW9uX3VpZBgCIAMoCVIKc3RhdGlvblVpZBIpCgZyb3V0ZXMYAyADKAsyES5CdXNf'
    'U3RvcEVzdGltYXRlUgZyb3V0ZXM=');

@$core.Deprecated('Use bus_RouteEstimateDescriptor instead')
const Bus_RouteEstimate$json = {
  '1': 'Bus_RouteEstimate',
  '2': [
    {'1': 'stop_uid', '3': 1, '4': 1, '5': 9, '10': 'stopUid'},
    {'1': 'direction', '3': 2, '4': 1, '5': 5, '10': 'direction'},
    {'1': 'estimate', '3': 3, '4': 1, '5': 5, '10': 'estimate'},
    {'1': 'NextBusTime', '3': 4, '4': 1, '5': 9, '10': 'NextBusTime'},
    {'1': 'Stop_status', '3': 5, '4': 1, '5': 5, '10': 'StopStatus'},
    {'1': 'src_update_time', '3': 6, '4': 1, '5': 9, '10': 'srcUpdateTime'},
    {
      '1': 'Buses',
      '3': 7,
      '4': 3,
      '5': 11,
      '6': '.Bus_position',
      '10': 'Buses'
    },
    {'1': 'StopSequence', '3': 8, '4': 1, '5': 5, '10': 'StopSequence'},
    {'1': 'arrival_unix', '3': 9, '4': 1, '5': 3, '10': 'arrivalUnix'},
    {'1': 'plate_numb', '3': 10, '4': 1, '5': 9, '10': 'plateNumb'},
  ],
};

/// Descriptor for `Bus_RouteEstimate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_RouteEstimateDescriptor = $convert.base64Decode(
    'ChFCdXNfUm91dGVFc3RpbWF0ZRIZCghzdG9wX3VpZBgBIAEoCVIHc3RvcFVpZBIcCglkaXJlY3'
    'Rpb24YAiABKAVSCWRpcmVjdGlvbhIaCghlc3RpbWF0ZRgDIAEoBVIIZXN0aW1hdGUSIAoLTmV4'
    'dEJ1c1RpbWUYBCABKAlSC05leHRCdXNUaW1lEh8KC1N0b3Bfc3RhdHVzGAUgASgFUgpTdG9wU3'
    'RhdHVzEiYKD3NyY191cGRhdGVfdGltZRgGIAEoCVINc3JjVXBkYXRlVGltZRIjCgVCdXNlcxgH'
    'IAMoCzINLkJ1c19wb3NpdGlvblIFQnVzZXMSIgoMU3RvcFNlcXVlbmNlGAggASgFUgxTdG9wU2'
    'VxdWVuY2USIQoMYXJyaXZhbF91bml4GAkgASgDUgthcnJpdmFsVW5peBIdCgpwbGF0ZV9udW1i'
    'GAogASgJUglwbGF0ZU51bWI=');

@$core.Deprecated('Use bus_StopEstimateDescriptor instead')
const Bus_StopEstimate$json = {
  '1': 'Bus_StopEstimate',
  '2': [
    {'1': 'stop_uid', '3': 1, '4': 1, '5': 9, '10': 'stopUid'},
    {'1': 'sub_route_uid', '3': 2, '4': 1, '5': 9, '10': 'subRouteUid'},
    {'1': 'route_name', '3': 3, '4': 1, '5': 9, '10': 'routeName'},
    {'1': 'Direction', '3': 4, '4': 1, '5': 5, '10': 'Direction'},
    {'1': 'estimate', '3': 5, '4': 1, '5': 5, '10': 'estimate'},
    {'1': 'NextBusTime', '3': 6, '4': 1, '5': 9, '10': 'NextBusTime'},
    {'1': 'Stop_status', '3': 7, '4': 1, '5': 5, '10': 'StopStatus'},
    {'1': 'src_update_time', '3': 8, '4': 1, '5': 9, '10': 'srcUpdateTime'},
    {
      '1': 'Buses',
      '3': 9,
      '4': 3,
      '5': 11,
      '6': '.Bus_position',
      '10': 'Buses'
    },
    {'1': 'arrival_unix', '3': 10, '4': 1, '5': 3, '10': 'arrivalUnix'},
    {'1': 'destination', '3': 11, '4': 1, '5': 9, '10': 'destination'},
  ],
};

/// Descriptor for `Bus_StopEstimate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_StopEstimateDescriptor = $convert.base64Decode(
    'ChBCdXNfU3RvcEVzdGltYXRlEhkKCHN0b3BfdWlkGAEgASgJUgdzdG9wVWlkEiIKDXN1Yl9yb3'
    'V0ZV91aWQYAiABKAlSC3N1YlJvdXRlVWlkEh0KCnJvdXRlX25hbWUYAyABKAlSCXJvdXRlTmFt'
    'ZRIcCglEaXJlY3Rpb24YBCABKAVSCURpcmVjdGlvbhIaCghlc3RpbWF0ZRgFIAEoBVIIZXN0aW'
    '1hdGUSIAoLTmV4dEJ1c1RpbWUYBiABKAlSC05leHRCdXNUaW1lEh8KC1N0b3Bfc3RhdHVzGAcg'
    'ASgFUgpTdG9wU3RhdHVzEiYKD3NyY191cGRhdGVfdGltZRgIIAEoCVINc3JjVXBkYXRlVGltZR'
    'IjCgVCdXNlcxgJIAMoCzINLkJ1c19wb3NpdGlvblIFQnVzZXMSIQoMYXJyaXZhbF91bml4GAog'
    'ASgDUgthcnJpdmFsVW5peBIgCgtkZXN0aW5hdGlvbhgLIAEoCVILZGVzdGluYXRpb24=');

@$core.Deprecated('Use bus_positionDescriptor instead')
const Bus_position$json = {
  '1': 'Bus_position',
  '2': [
    {'1': 'plate_numb', '3': 1, '4': 1, '5': 9, '10': 'plateNumb'},
    {'1': 'position_lon', '3': 2, '4': 1, '5': 1, '10': 'positionLon'},
    {'1': 'position_lat', '3': 3, '4': 1, '5': 1, '10': 'positionLat'},
    {'1': 'speed', '3': 4, '4': 1, '5': 5, '10': 'speed'},
    {'1': 'azimuth', '3': 5, '4': 1, '5': 5, '10': 'azimuth'},
    {'1': 'duty_status', '3': 9, '4': 1, '5': 5, '10': 'dutyStatus'},
    {'1': 'bus_status', '3': 10, '4': 1, '5': 5, '10': 'busStatus'},
    {'1': 'gps_time_unix', '3': 11, '4': 1, '5': 3, '10': 'gpsTimeUnix'},
  ],
  '9': [
    {'1': 6, '2': 7},
    {'1': 7, '2': 8},
    {'1': 8, '2': 9},
  ],
  '10': ['DutyStatus', 'BusStatus', 'gps_time'],
};

/// Descriptor for `Bus_position`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_positionDescriptor = $convert.base64Decode(
    'CgxCdXNfcG9zaXRpb24SHQoKcGxhdGVfbnVtYhgBIAEoCVIJcGxhdGVOdW1iEiEKDHBvc2l0aW'
    '9uX2xvbhgCIAEoAVILcG9zaXRpb25Mb24SIQoMcG9zaXRpb25fbGF0GAMgASgBUgtwb3NpdGlv'
    'bkxhdBIUCgVzcGVlZBgEIAEoBVIFc3BlZWQSGAoHYXppbXV0aBgFIAEoBVIHYXppbXV0aBIfCg'
    'tkdXR5X3N0YXR1cxgJIAEoBVIKZHV0eVN0YXR1cxIdCgpidXNfc3RhdHVzGAogASgFUglidXNT'
    'dGF0dXMSIgoNZ3BzX3RpbWVfdW5peBgLIAEoA1ILZ3BzVGltZVVuaXhKBAgGEAdKBAgHEAhKBA'
    'gIEAlSCkR1dHlTdGF0dXNSCUJ1c1N0YXR1c1IIZ3BzX3RpbWU=');

@$core.Deprecated('Use bus_ScheduleDescriptor instead')
const Bus_Schedule$json = {
  '1': 'Bus_Schedule',
  '2': [
    {'1': 'is_timetable', '3': 1, '4': 1, '5': 8, '10': 'isTimetable'},
    {'1': 'tripid', '3': 2, '4': 1, '5': 9, '10': 'tripid'},
    {'1': 'islowfloor', '3': 3, '4': 1, '5': 8, '10': 'islowfloor'},
    {'1': 'start_Time', '3': 4, '4': 1, '5': 9, '10': 'startTime'},
    {'1': 'end_Time', '3': 5, '4': 1, '5': 9, '10': 'endTime'},
    {
      '1': 'MinHeadwayMins_arrival_time',
      '3': 6,
      '4': 1,
      '5': 9,
      '10': 'MinHeadwayMinsArrivalTime'
    },
    {
      '1': 'MaxHeadwayMins_departure_time',
      '3': 7,
      '4': 1,
      '5': 9,
      '10': 'MaxHeadwayMinsDepartureTime'
    },
    {'1': 'service_day', '3': 8, '4': 1, '5': 5, '10': 'serviceDay'},
  ],
};

/// Descriptor for `Bus_Schedule`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_ScheduleDescriptor = $convert.base64Decode(
    'CgxCdXNfU2NoZWR1bGUSIQoMaXNfdGltZXRhYmxlGAEgASgIUgtpc1RpbWV0YWJsZRIWCgZ0cm'
    'lwaWQYAiABKAlSBnRyaXBpZBIeCgppc2xvd2Zsb29yGAMgASgIUgppc2xvd2Zsb29yEh0KCnN0'
    'YXJ0X1RpbWUYBCABKAlSCXN0YXJ0VGltZRIZCghlbmRfVGltZRgFIAEoCVIHZW5kVGltZRI+Ch'
    'tNaW5IZWFkd2F5TWluc19hcnJpdmFsX3RpbWUYBiABKAlSGU1pbkhlYWR3YXlNaW5zQXJyaXZh'
    'bFRpbWUSQgodTWF4SGVhZHdheU1pbnNfZGVwYXJ0dXJlX3RpbWUYByABKAlSG01heEhlYWR3YX'
    'lNaW5zRGVwYXJ0dXJlVGltZRIfCgtzZXJ2aWNlX2RheRgIIAEoBVIKc2VydmljZURheQ==');

@$core.Deprecated('Use bus_DailyTimetablesDescriptor instead')
const Bus_DailyTimetables$json = {
  '1': 'Bus_DailyTimetables',
  '2': [
    {'1': 'SubRouteUID', '3': 1, '4': 1, '5': 9, '10': 'SubRouteUID'},
    {
      '1': 'direction',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.Bus_DailyTimetables.DirectionEntry',
      '10': 'direction'
    },
  ],
  '3': [Bus_DailyTimetables_DirectionEntry$json],
  '9': [
    {'1': 2, '2': 3},
  ],
};

@$core.Deprecated('Use bus_DailyTimetablesDescriptor instead')
const Bus_DailyTimetables_DirectionEntry$json = {
  '1': 'DirectionEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 5, '10': 'key'},
    {
      '1': 'value',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.Bus_DirectionTimetable',
      '10': 'value'
    },
  ],
  '7': {'7': true},
};

/// Descriptor for `Bus_DailyTimetables`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_DailyTimetablesDescriptor = $convert.base64Decode(
    'ChNCdXNfRGFpbHlUaW1ldGFibGVzEiAKC1N1YlJvdXRlVUlEGAEgASgJUgtTdWJSb3V0ZVVJRB'
    'JBCglkaXJlY3Rpb24YAyADKAsyIy5CdXNfRGFpbHlUaW1ldGFibGVzLkRpcmVjdGlvbkVudHJ5'
    'UglkaXJlY3Rpb24aVQoORGlyZWN0aW9uRW50cnkSEAoDa2V5GAEgASgFUgNrZXkSLQoFdmFsdW'
    'UYAiABKAsyFy5CdXNfRGlyZWN0aW9uVGltZXRhYmxlUgV2YWx1ZToCOAFKBAgCEAM=');

@$core.Deprecated('Use bus_DirectionTimetableDescriptor instead')
const Bus_DirectionTimetable$json = {
  '1': 'Bus_DirectionTimetable',
  '2': [
    {
      '1': 'DailyTimetables',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.Bus_DailyTimetable',
      '10': 'DailyTimetables'
    },
  ],
};

/// Descriptor for `Bus_DirectionTimetable`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_DirectionTimetableDescriptor =
    $convert.base64Decode(
        'ChZCdXNfRGlyZWN0aW9uVGltZXRhYmxlEj0KD0RhaWx5VGltZXRhYmxlcxgBIAMoCzITLkJ1c1'
        '9EYWlseVRpbWV0YWJsZVIPRGFpbHlUaW1ldGFibGVz');

@$core.Deprecated('Use bus_DailyTimetableDescriptor instead')
const Bus_DailyTimetable$json = {
  '1': 'Bus_DailyTimetable',
  '2': [
    {'1': 'TripID', '3': 1, '4': 1, '5': 9, '10': 'TripID'},
    {'1': 'IsLowFloor', '3': 2, '4': 1, '5': 8, '10': 'IsLowFloor'},
    {
      '1': 'StopTimes',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.Bus_StopTime',
      '10': 'StopTimes'
    },
  ],
};

/// Descriptor for `Bus_DailyTimetable`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_DailyTimetableDescriptor = $convert.base64Decode(
    'ChJCdXNfRGFpbHlUaW1ldGFibGUSFgoGVHJpcElEGAEgASgJUgZUcmlwSUQSHgoKSXNMb3dGbG'
    '9vchgCIAEoCFIKSXNMb3dGbG9vchIrCglTdG9wVGltZXMYAyADKAsyDS5CdXNfU3RvcFRpbWVS'
    'CVN0b3BUaW1lcw==');

@$core.Deprecated('Use bus_StopTimeDescriptor instead')
const Bus_StopTime$json = {
  '1': 'Bus_StopTime',
  '2': [
    {'1': 'StopSequence', '3': 1, '4': 1, '5': 5, '10': 'StopSequence'},
    {'1': 'ArrivalTime', '3': 2, '4': 1, '5': 9, '10': 'ArrivalTime'},
    {'1': 'DepartureTime', '3': 3, '4': 1, '5': 9, '10': 'DepartureTime'},
    {'1': 'StopUID', '3': 4, '4': 1, '5': 9, '10': 'StopUID'},
  ],
};

/// Descriptor for `Bus_StopTime`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_StopTimeDescriptor = $convert.base64Decode(
    'CgxCdXNfU3RvcFRpbWUSIgoMU3RvcFNlcXVlbmNlGAEgASgFUgxTdG9wU2VxdWVuY2USIAoLQX'
    'JyaXZhbFRpbWUYAiABKAlSC0Fycml2YWxUaW1lEiQKDURlcGFydHVyZVRpbWUYAyABKAlSDURl'
    'cGFydHVyZVRpbWUSGAoHU3RvcFVJRBgEIAEoCVIHU3RvcFVJRA==');

@$core.Deprecated('Use bus_FareDescriptor instead')
const Bus_Fare$json = {
  '1': 'Bus_Fare',
  '2': [
    {'1': 'fare_pricing_type', '3': 2, '4': 1, '5': 5, '10': 'farePricingType'},
    {'1': 'is_free_bus', '3': 3, '4': 1, '5': 8, '10': 'isFreeBus'},
    {
      '1': 'section_fares_json',
      '3': 4,
      '4': 1,
      '5': 12,
      '10': 'sectionFaresJson'
    },
    {'1': 'stage_fares_json', '3': 5, '4': 1, '5': 12, '10': 'stageFaresJson'},
    {'1': 'od_fares_json', '3': 6, '4': 1, '5': 12, '10': 'odFaresJson'},
  ],
  '9': [
    {'1': 1, '2': 2},
  ],
  '10': ['sub_route_uid'],
};

/// Descriptor for `Bus_Fare`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bus_FareDescriptor = $convert.base64Decode(
    'CghCdXNfRmFyZRIqChFmYXJlX3ByaWNpbmdfdHlwZRgCIAEoBVIPZmFyZVByaWNpbmdUeXBlEh'
    '4KC2lzX2ZyZWVfYnVzGAMgASgIUglpc0ZyZWVCdXMSLAoSc2VjdGlvbl9mYXJlc19qc29uGAQg'
    'ASgMUhBzZWN0aW9uRmFyZXNKc29uEigKEHN0YWdlX2ZhcmVzX2pzb24YBSABKAxSDnN0YWdlRm'
    'FyZXNKc29uEiIKDW9kX2ZhcmVzX2pzb24YBiABKAxSC29kRmFyZXNKc29uSgQIARACUg1zdWJf'
    'cm91dGVfdWlk');
