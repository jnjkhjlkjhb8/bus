// This is a generated file - do not edit.
//
// Generated from bike.proto.

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

@$core.Deprecated('Use bike_requestDescriptor instead')
const Bike_request$json = {
  '1': 'Bike_request',
  '2': [
    {'1': 'StationUID', '3': 1, '4': 1, '5': 9, '10': 'StationUID'},
  ],
};

/// Descriptor for `Bike_request`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bike_requestDescriptor = $convert.base64Decode(
    'CgxCaWtlX3JlcXVlc3QSHgoKU3RhdGlvblVJRBgBIAEoCVIKU3RhdGlvblVJRA==');

@$core.Deprecated('Use resp_Bike_etaDescriptor instead')
const Resp_Bike_eta$json = {
  '1': 'Resp_Bike_eta',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `Resp_Bike_eta`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resp_Bike_etaDescriptor =
    $convert.base64Decode('Cg1SZXNwX0Jpa2VfZXRhEhIKBGRhdGEYASABKAxSBGRhdGE=');

@$core.Deprecated('Use bike_staticDescriptor instead')
const Bike_static$json = {
  '1': 'Bike_static',
  '2': [
    {'1': 'StationUID', '3': 1, '4': 1, '5': 9, '10': 'StationUID'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'service_type', '3': 3, '4': 1, '5': 5, '10': 'serviceType'},
    {'1': 'capacity', '3': 4, '4': 1, '5': 5, '10': 'capacity'},
    {'1': 'city', '3': 5, '4': 1, '5': 9, '10': 'city'},
    {'1': 'Lat', '3': 6, '4': 1, '5': 9, '10': 'Lat'},
    {'1': 'Lon', '3': 7, '4': 1, '5': 9, '10': 'Lon'},
    {'1': 'address', '3': 8, '4': 1, '5': 9, '10': 'address'},
  ],
};

/// Descriptor for `Bike_static`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bike_staticDescriptor = $convert.base64Decode(
    'CgtCaWtlX3N0YXRpYxIeCgpTdGF0aW9uVUlEGAEgASgJUgpTdGF0aW9uVUlEEhIKBG5hbWUYAi'
    'ABKAlSBG5hbWUSIQoMc2VydmljZV90eXBlGAMgASgFUgtzZXJ2aWNlVHlwZRIaCghjYXBhY2l0'
    'eRgEIAEoBVIIY2FwYWNpdHkSEgoEY2l0eRgFIAEoCVIEY2l0eRIQCgNMYXQYBiABKAlSA0xhdB'
    'IQCgNMb24YByABKAlSA0xvbhIYCgdhZGRyZXNzGAggASgJUgdhZGRyZXNz');

@$core.Deprecated('Use bike_etaDescriptor instead')
const Bike_eta$json = {
  '1': 'Bike_eta',
  '2': [
    {'1': 'StationUID', '3': 1, '4': 1, '5': 9, '10': 'StationUID'},
    {'1': 'ServiceStatus', '3': 2, '4': 1, '5': 5, '10': 'ServiceStatus'},
    {'1': 'ServiceType', '3': 3, '4': 1, '5': 5, '10': 'ServiceType'},
    {
      '1': 'AvailableReturnBikes',
      '3': 4,
      '4': 1,
      '5': 5,
      '10': 'AvailableReturnBikes'
    },
    {'1': 'GeneralBikes', '3': 5, '4': 1, '5': 5, '10': 'GeneralBikes'},
    {'1': 'ElectricBikes', '3': 6, '4': 1, '5': 5, '10': 'ElectricBikes'},
  ],
};

/// Descriptor for `Bike_eta`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bike_etaDescriptor = $convert.base64Decode(
    'CghCaWtlX2V0YRIeCgpTdGF0aW9uVUlEGAEgASgJUgpTdGF0aW9uVUlEEiQKDVNlcnZpY2VTdG'
    'F0dXMYAiABKAVSDVNlcnZpY2VTdGF0dXMSIAoLU2VydmljZVR5cGUYAyABKAVSC1NlcnZpY2VU'
    'eXBlEjIKFEF2YWlsYWJsZVJldHVybkJpa2VzGAQgASgFUhRBdmFpbGFibGVSZXR1cm5CaWtlcx'
    'IiCgxHZW5lcmFsQmlrZXMYBSABKAVSDEdlbmVyYWxCaWtlcxIkCg1FbGVjdHJpY0Jpa2VzGAYg'
    'ASgFUg1FbGVjdHJpY0Jpa2Vz');
