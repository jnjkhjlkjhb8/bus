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
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `Resp_Mrt_eta`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resp_Mrt_etaDescriptor =
    $convert.base64Decode('CgxSZXNwX01ydF9ldGESEgoEZGF0YRgBIAEoDFIEZGF0YQ==');

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
    {'1': 'system', '3': 3, '4': 1, '5': 9, '10': 'system'},
    {'1': 'TripHeadSign', '3': 4, '4': 1, '5': 9, '10': 'TripHeadSign'},
    {
      '1': 'DestinationStaionID',
      '3': 5,
      '4': 1,
      '5': 9,
      '10': 'DestinationStaionID'
    },
    {
      '1': 'DestinationStationName',
      '3': 6,
      '4': 1,
      '5': 9,
      '10': 'DestinationStationName'
    },
    {'1': 'ServiceStatus', '3': 7, '4': 1, '5': 5, '10': 'ServiceStatus'},
    {'1': 'EstimateTime', '3': 8, '4': 1, '5': 5, '10': 'EstimateTime'},
  ],
};

/// Descriptor for `Mrt_live`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mrt_liveDescriptor = $convert.base64Decode(
    'CghNcnRfbGl2ZRIWCgZMaW5lSUQYASABKAlSBkxpbmVJRBIcCglTdGF0aW9uSUQYAiABKAlSCV'
    'N0YXRpb25JRBIWCgZzeXN0ZW0YAyABKAlSBnN5c3RlbRIiCgxUcmlwSGVhZFNpZ24YBCABKAlS'
    'DFRyaXBIZWFkU2lnbhIwChNEZXN0aW5hdGlvblN0YWlvbklEGAUgASgJUhNEZXN0aW5hdGlvbl'
    'N0YWlvbklEEjYKFkRlc3RpbmF0aW9uU3RhdGlvbk5hbWUYBiABKAlSFkRlc3RpbmF0aW9uU3Rh'
    'dGlvbk5hbWUSJAoNU2VydmljZVN0YXR1cxgHIAEoBVINU2VydmljZVN0YXR1cxIiCgxFc3RpbW'
    'F0ZVRpbWUYCCABKAVSDEVzdGltYXRlVGltZQ==');
