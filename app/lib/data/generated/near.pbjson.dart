// This is a generated file - do not edit.
//
// Generated from near.proto.

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

@$core.Deprecated('Use ask_NearDescriptor instead')
const Ask_Near$json = {
  '1': 'Ask_Near',
  '2': [
    {'1': 'PositionLon', '3': 1, '4': 1, '5': 1, '10': 'PositionLon'},
    {'1': 'PositionLat', '3': 2, '4': 1, '5': 1, '10': 'PositionLat'},
    {'1': 'Radius', '3': 3, '4': 1, '5': 5, '10': 'Radius'},
  ],
};

/// Descriptor for `Ask_Near`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ask_NearDescriptor = $convert.base64Decode(
    'CghBc2tfTmVhchIgCgtQb3NpdGlvbkxvbhgBIAEoAVILUG9zaXRpb25Mb24SIAoLUG9zaXRpb2'
    '5MYXQYAiABKAFSC1Bvc2l0aW9uTGF0EhYKBlJhZGl1cxgDIAEoBVIGUmFkaXVz');

@$core.Deprecated('Use resp_nearDescriptor instead')
const resp_near$json = {
  '1': 'resp_near',
  '2': [
    {
      '1': 'near_bus_stations',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.resp_near.NearBusStationsEntry',
      '10': 'nearBusStations'
    },
    {
      '1': 'near_bike_stations',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.NearStation',
      '10': 'nearBikeStations'
    },
    {
      '1': 'near_mrt_stations',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.NearStation',
      '10': 'nearMrtStations'
    },
    {
      '1': 'near_tra_stations',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.NearStation',
      '10': 'nearTraStations'
    },
    {
      '1': 'near_thsr_stations',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.NearStation',
      '10': 'nearThsrStations'
    },
  ],
  '3': [resp_near_NearBusStationsEntry$json],
};

@$core.Deprecated('Use resp_nearDescriptor instead')
const resp_near_NearBusStationsEntry$json = {
  '1': 'NearBusStationsEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 11, '6': '.array_near', '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `resp_near`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resp_nearDescriptor = $convert.base64Decode(
    'CglyZXNwX25lYXISSwoRbmVhcl9idXNfc3RhdGlvbnMYASADKAsyHy5yZXNwX25lYXIuTmVhck'
    'J1c1N0YXRpb25zRW50cnlSD25lYXJCdXNTdGF0aW9ucxI6ChJuZWFyX2Jpa2Vfc3RhdGlvbnMY'
    'AiADKAsyDC5OZWFyU3RhdGlvblIQbmVhckJpa2VTdGF0aW9ucxI4ChFuZWFyX21ydF9zdGF0aW'
    '9ucxgDIAMoCzIMLk5lYXJTdGF0aW9uUg9uZWFyTXJ0U3RhdGlvbnMSOAoRbmVhcl90cmFfc3Rh'
    'dGlvbnMYBCADKAsyDC5OZWFyU3RhdGlvblIPbmVhclRyYVN0YXRpb25zEjoKEm5lYXJfdGhzcl'
    '9zdGF0aW9ucxgFIAMoCzIMLk5lYXJTdGF0aW9uUhBuZWFyVGhzclN0YXRpb25zGk8KFE5lYXJC'
    'dXNTdGF0aW9uc0VudHJ5EhAKA2tleRgBIAEoCVIDa2V5EiEKBXZhbHVlGAIgASgLMgsuYXJyYX'
    'lfbmVhclIFdmFsdWU6AjgB');

@$core.Deprecated('Use array_nearDescriptor instead')
const array_near$json = {
  '1': 'array_near',
  '2': [
    {
      '1': 'near_stations',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.NearStation',
      '10': 'nearStations'
    },
  ],
};

/// Descriptor for `array_near`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List array_nearDescriptor = $convert.base64Decode(
    'CgphcnJheV9uZWFyEjEKDW5lYXJfc3RhdGlvbnMYASADKAsyDC5OZWFyU3RhdGlvblIMbmVhcl'
    'N0YXRpb25z');

@$core.Deprecated('Use nearStationDescriptor instead')
const NearStation$json = {
  '1': 'NearStation',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 5, '10': 'type'},
    {'1': 'StationID', '3': 2, '4': 1, '5': 9, '10': 'StationID'},
    {'1': 'StationName', '3': 3, '4': 1, '5': 9, '10': 'StationName'},
    {'1': 'city', '3': 4, '4': 1, '5': 9, '10': 'city'},
    {'1': 'PositionLon', '3': 5, '4': 1, '5': 1, '10': 'PositionLon'},
    {'1': 'PositionLat', '3': 6, '4': 1, '5': 1, '10': 'PositionLat'},
    {'1': 'walk', '3': 7, '4': 1, '5': 5, '10': 'walk'},
    {'1': 'distance', '3': 8, '4': 1, '5': 5, '10': 'distance'},
    {'1': 'routed', '3': 9, '4': 1, '5': 8, '10': 'routed'},
  ],
};

/// Descriptor for `NearStation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List nearStationDescriptor = $convert.base64Decode(
    'CgtOZWFyU3RhdGlvbhISCgR0eXBlGAEgASgFUgR0eXBlEhwKCVN0YXRpb25JRBgCIAEoCVIJU3'
    'RhdGlvbklEEiAKC1N0YXRpb25OYW1lGAMgASgJUgtTdGF0aW9uTmFtZRISCgRjaXR5GAQgASgJ'
    'UgRjaXR5EiAKC1Bvc2l0aW9uTG9uGAUgASgBUgtQb3NpdGlvbkxvbhIgCgtQb3NpdGlvbkxhdB'
    'gGIAEoAVILUG9zaXRpb25MYXQSEgoEd2FsaxgHIAEoBVIEd2FsaxIaCghkaXN0YW5jZRgIIAEo'
    'BVIIZGlzdGFuY2USFgoGcm91dGVkGAkgASgIUgZyb3V0ZWQ=');
