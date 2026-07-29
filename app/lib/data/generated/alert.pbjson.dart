// This is a generated file - do not edit.
//
// Generated from alert.proto.

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

@$core.Deprecated('Use alert_AskDescriptor instead')
const Alert_Ask$json = {
  '1': 'Alert_Ask',
};

/// Descriptor for `Alert_Ask`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List alert_AskDescriptor =
    $convert.base64Decode('CglBbGVydF9Bc2s=');

@$core.Deprecated('Use alert_Bus_AskDescriptor instead')
const Alert_Bus_Ask$json = {
  '1': 'Alert_Bus_Ask',
  '2': [
    {'1': 'city', '3': 1, '4': 1, '5': 9, '10': 'city'},
  ],
};

/// Descriptor for `Alert_Bus_Ask`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List alert_Bus_AskDescriptor =
    $convert.base64Decode('Cg1BbGVydF9CdXNfQXNrEhIKBGNpdHkYASABKAlSBGNpdHk=');

@$core.Deprecated('Use alert_Metro_AskDescriptor instead')
const Alert_Metro_Ask$json = {
  '1': 'Alert_Metro_Ask',
  '2': [
    {'1': 'system', '3': 1, '4': 1, '5': 9, '10': 'system'},
  ],
};

/// Descriptor for `Alert_Metro_Ask`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List alert_Metro_AskDescriptor = $convert
    .base64Decode('Cg9BbGVydF9NZXRyb19Bc2sSFgoGc3lzdGVtGAEgASgJUgZzeXN0ZW0=');

@$core.Deprecated('Use alert_MsgDescriptor instead')
const Alert_Msg$json = {
  '1': 'Alert_Msg',
  '2': [
    {'1': 'items', '3': 2, '4': 3, '5': 11, '6': '.Alert_Item', '10': 'items'},
  ],
  '9': [
    {'1': 1, '2': 2},
  ],
};

/// Descriptor for `Alert_Msg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List alert_MsgDescriptor = $convert.base64Decode(
    'CglBbGVydF9Nc2cSIQoFaXRlbXMYAiADKAsyCy5BbGVydF9JdGVtUgVpdGVtc0oECAEQAg==');

@$core.Deprecated('Use alert_ItemDescriptor instead')
const Alert_Item$json = {
  '1': 'Alert_Item',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'route_type', '3': 2, '4': 1, '5': 9, '10': 'routeType'},
    {'1': 'route_keys', '3': 3, '4': 3, '5': 9, '10': 'routeKeys'},
    {'1': 'title', '3': 4, '4': 1, '5': 9, '10': 'title'},
    {'1': 'body', '3': 5, '4': 1, '5': 9, '10': 'body'},
    {'1': 'level', '3': 6, '4': 1, '5': 9, '10': 'level'},
    {'1': 'time_unix', '3': 7, '4': 1, '5': 3, '10': 'timeUnix'},
  ],
};

/// Descriptor for `Alert_Item`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List alert_ItemDescriptor = $convert.base64Decode(
    'CgpBbGVydF9JdGVtEg4KAmlkGAEgASgJUgJpZBIdCgpyb3V0ZV90eXBlGAIgASgJUglyb3V0ZV'
    'R5cGUSHQoKcm91dGVfa2V5cxgDIAMoCVIJcm91dGVLZXlzEhQKBXRpdGxlGAQgASgJUgV0aXRs'
    'ZRISCgRib2R5GAUgASgJUgRib2R5EhQKBWxldmVsGAYgASgJUgVsZXZlbBIbCgl0aW1lX3VuaX'
    'gYByABKANSCHRpbWVVbml4');
