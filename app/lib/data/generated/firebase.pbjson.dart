// This is a generated file - do not edit.
//
// Generated from firebase.proto.

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

@$core.Deprecated('Use ackDescriptor instead')
const Ack$json = {
  '1': 'Ack',
  '2': [
    {'1': 'ok', '3': 1, '4': 1, '5': 8, '10': 'ok'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `Ack`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ackDescriptor = $convert.base64Decode(
    'CgNBY2sSDgoCb2sYASABKAhSAm9rEhgKB21lc3NhZ2UYAiABKAlSB21lc3NhZ2U=');

@$core.Deprecated('Use deviceIdentityDescriptor instead')
const DeviceIdentity$json = {
  '1': 'DeviceIdentity',
  '2': [
    {'1': 'install_id', '3': 1, '4': 1, '5': 9, '10': 'installId'},
    {'1': 'fcm_token', '3': 2, '4': 1, '5': 9, '10': 'fcmToken'},
    {'1': 'platform', '3': 3, '4': 1, '5': 9, '10': 'platform'},
    {'1': 'app_version', '3': 4, '4': 1, '5': 9, '10': 'appVersion'},
  ],
};

/// Descriptor for `DeviceIdentity`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceIdentityDescriptor = $convert.base64Decode(
    'Cg5EZXZpY2VJZGVudGl0eRIdCgppbnN0YWxsX2lkGAEgASgJUglpbnN0YWxsSWQSGwoJZmNtX3'
    'Rva2VuGAIgASgJUghmY21Ub2tlbhIaCghwbGF0Zm9ybRgDIAEoCVIIcGxhdGZvcm0SHwoLYXBw'
    'X3ZlcnNpb24YBCABKAlSCmFwcFZlcnNpb24=');

@$core.Deprecated('Use devicePrefsDescriptor instead')
const DevicePrefs$json = {
  '1': 'DevicePrefs',
  '2': [
    {'1': 'push_enabled', '3': 1, '4': 1, '5': 8, '10': 'pushEnabled'},
    {
      '1': 'analytics_enabled',
      '3': 2,
      '4': 1,
      '5': 8,
      '10': 'analyticsEnabled'
    },
    {
      '1': 'crashlytics_enabled',
      '3': 3,
      '4': 1,
      '5': 8,
      '10': 'crashlyticsEnabled'
    },
    {
      '1': 'performance_enabled',
      '3': 4,
      '4': 1,
      '5': 8,
      '10': 'performanceEnabled'
    },
  ],
};

/// Descriptor for `DevicePrefs`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List devicePrefsDescriptor = $convert.base64Decode(
    'CgtEZXZpY2VQcmVmcxIhCgxwdXNoX2VuYWJsZWQYASABKAhSC3B1c2hFbmFibGVkEisKEWFuYW'
    'x5dGljc19lbmFibGVkGAIgASgIUhBhbmFseXRpY3NFbmFibGVkEi8KE2NyYXNobHl0aWNzX2Vu'
    'YWJsZWQYAyABKAhSEmNyYXNobHl0aWNzRW5hYmxlZBIvChNwZXJmb3JtYW5jZV9lbmFibGVkGA'
    'QgASgIUhJwZXJmb3JtYW5jZUVuYWJsZWQ=');

@$core.Deprecated('Use upsertDeviceRequestDescriptor instead')
const UpsertDeviceRequest$json = {
  '1': 'UpsertDeviceRequest',
  '2': [
    {
      '1': 'identity',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.DeviceIdentity',
      '10': 'identity'
    },
    {'1': 'prefs', '3': 2, '4': 1, '5': 11, '6': '.DevicePrefs', '10': 'prefs'},
  ],
};

/// Descriptor for `UpsertDeviceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List upsertDeviceRequestDescriptor = $convert.base64Decode(
    'ChNVcHNlcnREZXZpY2VSZXF1ZXN0EisKCGlkZW50aXR5GAEgASgLMg8uRGV2aWNlSWRlbnRpdH'
    'lSCGlkZW50aXR5EiIKBXByZWZzGAIgASgLMgwuRGV2aWNlUHJlZnNSBXByZWZz');

@$core.Deprecated('Use deviceRequestDescriptor instead')
const DeviceRequest$json = {
  '1': 'DeviceRequest',
  '2': [
    {'1': 'install_id', '3': 1, '4': 1, '5': 9, '10': 'installId'},
  ],
};

/// Descriptor for `DeviceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceRequestDescriptor = $convert.base64Decode(
    'Cg1EZXZpY2VSZXF1ZXN0Eh0KCmluc3RhbGxfaWQYASABKAlSCWluc3RhbGxJZA==');

@$core.Deprecated('Use deviceStateDescriptor instead')
const DeviceState$json = {
  '1': 'DeviceState',
  '2': [
    {
      '1': 'identity',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.DeviceIdentity',
      '10': 'identity'
    },
    {'1': 'prefs', '3': 2, '4': 1, '5': 11, '6': '.DevicePrefs', '10': 'prefs'},
  ],
};

/// Descriptor for `DeviceState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceStateDescriptor = $convert.base64Decode(
    'CgtEZXZpY2VTdGF0ZRIrCghpZGVudGl0eRgBIAEoCzIPLkRldmljZUlkZW50aXR5UghpZGVudG'
    'l0eRIiCgVwcmVmcxgCIAEoCzIMLkRldmljZVByZWZzUgVwcmVmcw==');

@$core.Deprecated('Use routeSubscriptionRequestDescriptor instead')
const RouteSubscriptionRequest$json = {
  '1': 'RouteSubscriptionRequest',
  '2': [
    {'1': 'install_id', '3': 1, '4': 1, '5': 9, '10': 'installId'},
    {'1': 'route_type', '3': 2, '4': 1, '5': 9, '10': 'routeType'},
    {'1': 'route_key', '3': 3, '4': 1, '5': 9, '10': 'routeKey'},
    {'1': 'enabled', '3': 4, '4': 1, '5': 8, '10': 'enabled'},
  ],
};

/// Descriptor for `RouteSubscriptionRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List routeSubscriptionRequestDescriptor = $convert.base64Decode(
    'ChhSb3V0ZVN1YnNjcmlwdGlvblJlcXVlc3QSHQoKaW5zdGFsbF9pZBgBIAEoCVIJaW5zdGFsbE'
    'lkEh0KCnJvdXRlX3R5cGUYAiABKAlSCXJvdXRlVHlwZRIbCglyb3V0ZV9rZXkYAyABKAlSCHJv'
    'dXRlS2V5EhgKB2VuYWJsZWQYBCABKAhSB2VuYWJsZWQ=');

@$core.Deprecated('Use createArrivalReminderRequestDescriptor instead')
const CreateArrivalReminderRequest$json = {
  '1': 'CreateArrivalReminderRequest',
  '2': [
    {'1': 'install_id', '3': 1, '4': 1, '5': 9, '10': 'installId'},
    {'1': 'route_type', '3': 2, '4': 1, '5': 9, '10': 'routeType'},
    {'1': 'route_key', '3': 3, '4': 1, '5': 9, '10': 'routeKey'},
    {'1': 'stop_key', '3': 4, '4': 1, '5': 9, '10': 'stopKey'},
    {'1': 'direction', '3': 5, '4': 1, '5': 9, '10': 'direction'},
    {'1': 'lead_minutes', '3': 6, '4': 1, '5': 5, '10': 'leadMinutes'},
    {'1': 'expires_at_unix', '3': 7, '4': 1, '5': 3, '10': 'expiresAtUnix'},
  ],
};

/// Descriptor for `CreateArrivalReminderRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createArrivalReminderRequestDescriptor = $convert.base64Decode(
    'ChxDcmVhdGVBcnJpdmFsUmVtaW5kZXJSZXF1ZXN0Eh0KCmluc3RhbGxfaWQYASABKAlSCWluc3'
    'RhbGxJZBIdCgpyb3V0ZV90eXBlGAIgASgJUglyb3V0ZVR5cGUSGwoJcm91dGVfa2V5GAMgASgJ'
    'Ughyb3V0ZUtleRIZCghzdG9wX2tleRgEIAEoCVIHc3RvcEtleRIcCglkaXJlY3Rpb24YBSABKA'
    'lSCWRpcmVjdGlvbhIhCgxsZWFkX21pbnV0ZXMYBiABKAVSC2xlYWRNaW51dGVzEiYKD2V4cGly'
    'ZXNfYXRfdW5peBgHIAEoA1INZXhwaXJlc0F0VW5peA==');

@$core.Deprecated('Use arrivalReminderDescriptor instead')
const ArrivalReminder$json = {
  '1': 'ArrivalReminder',
  '2': [
    {'1': 'reminder_id', '3': 1, '4': 1, '5': 9, '10': 'reminderId'},
    {'1': 'install_id', '3': 2, '4': 1, '5': 9, '10': 'installId'},
    {'1': 'route_type', '3': 3, '4': 1, '5': 9, '10': 'routeType'},
    {'1': 'route_key', '3': 4, '4': 1, '5': 9, '10': 'routeKey'},
    {'1': 'stop_key', '3': 5, '4': 1, '5': 9, '10': 'stopKey'},
    {'1': 'direction', '3': 6, '4': 1, '5': 9, '10': 'direction'},
    {'1': 'lead_minutes', '3': 7, '4': 1, '5': 5, '10': 'leadMinutes'},
    {'1': 'expires_at_unix', '3': 8, '4': 1, '5': 3, '10': 'expiresAtUnix'},
  ],
};

/// Descriptor for `ArrivalReminder`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List arrivalReminderDescriptor = $convert.base64Decode(
    'Cg9BcnJpdmFsUmVtaW5kZXISHwoLcmVtaW5kZXJfaWQYASABKAlSCnJlbWluZGVySWQSHQoKaW'
    '5zdGFsbF9pZBgCIAEoCVIJaW5zdGFsbElkEh0KCnJvdXRlX3R5cGUYAyABKAlSCXJvdXRlVHlw'
    'ZRIbCglyb3V0ZV9rZXkYBCABKAlSCHJvdXRlS2V5EhkKCHN0b3Bfa2V5GAUgASgJUgdzdG9wS2'
    'V5EhwKCWRpcmVjdGlvbhgGIAEoCVIJZGlyZWN0aW9uEiEKDGxlYWRfbWludXRlcxgHIAEoBVIL'
    'bGVhZE1pbnV0ZXMSJgoPZXhwaXJlc19hdF91bml4GAggASgDUg1leHBpcmVzQXRVbml4');

@$core.Deprecated('Use cancelArrivalReminderRequestDescriptor instead')
const CancelArrivalReminderRequest$json = {
  '1': 'CancelArrivalReminderRequest',
  '2': [
    {'1': 'reminder_id', '3': 1, '4': 1, '5': 9, '10': 'reminderId'},
    {'1': 'install_id', '3': 2, '4': 1, '5': 9, '10': 'installId'},
  ],
};

/// Descriptor for `CancelArrivalReminderRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List cancelArrivalReminderRequestDescriptor =
    $convert.base64Decode(
        'ChxDYW5jZWxBcnJpdmFsUmVtaW5kZXJSZXF1ZXN0Eh8KC3JlbWluZGVyX2lkGAEgASgJUgpyZW'
        '1pbmRlcklkEh0KCmluc3RhbGxfaWQYAiABKAlSCWluc3RhbGxJZA==');
