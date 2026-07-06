// This is a generated file - do not edit.
//
// Generated from maas.proto.

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

@$core.Deprecated('Use maasPlanRequestDescriptor instead')
const MaasPlanRequest$json = {
  '1': 'MaasPlanRequest',
  '2': [
    {'1': 'fromLat', '3': 1, '4': 1, '5': 1, '10': 'fromLat'},
    {'1': 'fromLon', '3': 2, '4': 1, '5': 1, '10': 'fromLon'},
    {'1': 'toLat', '3': 3, '4': 1, '5': 1, '10': 'toLat'},
    {'1': 'toLon', '3': 4, '4': 1, '5': 1, '10': 'toLon'},
    {'1': 'date', '3': 5, '4': 1, '5': 9, '10': 'date'},
    {'1': 'time', '3': 6, '4': 1, '5': 9, '10': 'time'},
    {'1': 'arriveBy', '3': 7, '4': 1, '5': 8, '10': 'arriveBy'},
    {'1': 'gc', '3': 8, '4': 1, '5': 1, '10': 'gc'},
    {'1': 'transitModes', '3': 9, '4': 3, '5': 5, '10': 'transitModes'},
  ],
};

/// Descriptor for `MaasPlanRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List maasPlanRequestDescriptor = $convert.base64Decode(
    'Cg9NYWFzUGxhblJlcXVlc3QSGAoHZnJvbUxhdBgBIAEoAVIHZnJvbUxhdBIYCgdmcm9tTG9uGA'
    'IgASgBUgdmcm9tTG9uEhQKBXRvTGF0GAMgASgBUgV0b0xhdBIUCgV0b0xvbhgEIAEoAVIFdG9M'
    'b24SEgoEZGF0ZRgFIAEoCVIEZGF0ZRISCgR0aW1lGAYgASgJUgR0aW1lEhoKCGFycml2ZUJ5GA'
    'cgASgIUghhcnJpdmVCeRIOCgJnYxgIIAEoAVICZ2MSIgoMdHJhbnNpdE1vZGVzGAkgAygFUgx0'
    'cmFuc2l0TW9kZXM=');

@$core.Deprecated('Use maasPlanResponseDescriptor instead')
const MaasPlanResponse$json = {
  '1': 'MaasPlanResponse',
  '2': [
    {'1': 'routes', '3': 1, '4': 3, '5': 11, '6': '.Route', '10': 'routes'},
  ],
};

/// Descriptor for `MaasPlanResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List maasPlanResponseDescriptor = $convert.base64Decode(
    'ChBNYWFzUGxhblJlc3BvbnNlEh4KBnJvdXRlcxgBIAMoCzIGLlJvdXRlUgZyb3V0ZXM=');

@$core.Deprecated('Use routeDescriptor instead')
const Route$json = {
  '1': 'Route',
  '2': [
    {'1': 'travelTime', '3': 1, '4': 1, '5': 3, '10': 'travelTime'},
    {'1': 'startTime', '3': 2, '4': 1, '5': 9, '10': 'startTime'},
    {'1': 'endTime', '3': 3, '4': 1, '5': 9, '10': 'endTime'},
    {'1': 'transfers', '3': 4, '4': 1, '5': 5, '10': 'transfers'},
    {
      '1': 'sections',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.Section',
      '10': 'sections'
    },
    {'1': 'totalFare', '3': 6, '4': 1, '5': 5, '10': 'totalFare'},
  ],
};

/// Descriptor for `Route`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List routeDescriptor = $convert.base64Decode(
    'CgVSb3V0ZRIeCgp0cmF2ZWxUaW1lGAEgASgDUgp0cmF2ZWxUaW1lEhwKCXN0YXJ0VGltZRgCIA'
    'EoCVIJc3RhcnRUaW1lEhgKB2VuZFRpbWUYAyABKAlSB2VuZFRpbWUSHAoJdHJhbnNmZXJzGAQg'
    'ASgFUgl0cmFuc2ZlcnMSJAoIc2VjdGlvbnMYBSADKAsyCC5TZWN0aW9uUghzZWN0aW9ucxIcCg'
    'l0b3RhbEZhcmUYBiABKAVSCXRvdGFsRmFyZQ==');

@$core.Deprecated('Use sectionDescriptor instead')
const Section$json = {
  '1': 'Section',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 9, '10': 'type'},
    {
      '1': 'travelSummary',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.Summary',
      '10': 'travelSummary'
    },
    {
      '1': 'departure',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.Place',
      '10': 'departure'
    },
    {'1': 'arrival', '3': 4, '4': 1, '5': 11, '6': '.Place', '10': 'arrival'},
    {
      '1': 'transport',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.Transport',
      '10': 'transport'
    },
    {
      '1': 'intermediateStops',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.IntermediateStop',
      '10': 'intermediateStops'
    },
    {'1': 'agency', '3': 7, '4': 1, '5': 11, '6': '.Agency', '10': 'agency'},
    {
      '1': 'notification_identity',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.NotificationIdentity',
      '10': 'notificationIdentity'
    },
    {'1': 'fare', '3': 9, '4': 1, '5': 5, '10': 'fare'},
  ],
};

/// Descriptor for `Section`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sectionDescriptor = $convert.base64Decode(
    'CgdTZWN0aW9uEhIKBHR5cGUYASABKAlSBHR5cGUSLgoNdHJhdmVsU3VtbWFyeRgCIAEoCzIILl'
    'N1bW1hcnlSDXRyYXZlbFN1bW1hcnkSJAoJZGVwYXJ0dXJlGAMgASgLMgYuUGxhY2VSCWRlcGFy'
    'dHVyZRIgCgdhcnJpdmFsGAQgASgLMgYuUGxhY2VSB2Fycml2YWwSKAoJdHJhbnNwb3J0GAUgAS'
    'gLMgouVHJhbnNwb3J0Ugl0cmFuc3BvcnQSPwoRaW50ZXJtZWRpYXRlU3RvcHMYBiADKAsyES5J'
    'bnRlcm1lZGlhdGVTdG9wUhFpbnRlcm1lZGlhdGVTdG9wcxIfCgZhZ2VuY3kYByABKAsyBy5BZ2'
    'VuY3lSBmFnZW5jeRJKChVub3RpZmljYXRpb25faWRlbnRpdHkYCCABKAsyFS5Ob3RpZmljYXRp'
    'b25JZGVudGl0eVIUbm90aWZpY2F0aW9uSWRlbnRpdHkSEgoEZmFyZRgJIAEoBVIEZmFyZQ==');

@$core.Deprecated('Use notificationIdentityDescriptor instead')
const NotificationIdentity$json = {
  '1': 'NotificationIdentity',
  '2': [
    {'1': 'route_type', '3': 1, '4': 1, '5': 9, '10': 'routeType'},
    {'1': 'route_key', '3': 2, '4': 1, '5': 9, '10': 'routeKey'},
    {'1': 'direction', '3': 3, '4': 1, '5': 9, '10': 'direction'},
    {
      '1': 'departure_stop_key',
      '3': 4,
      '4': 1,
      '5': 9,
      '10': 'departureStopKey'
    },
    {'1': 'arrival_stop_key', '3': 5, '4': 1, '5': 9, '10': 'arrivalStopKey'},
    {'1': 'supported', '3': 6, '4': 1, '5': 8, '10': 'supported'},
  ],
};

/// Descriptor for `NotificationIdentity`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List notificationIdentityDescriptor = $convert.base64Decode(
    'ChROb3RpZmljYXRpb25JZGVudGl0eRIdCgpyb3V0ZV90eXBlGAEgASgJUglyb3V0ZVR5cGUSGw'
    'oJcm91dGVfa2V5GAIgASgJUghyb3V0ZUtleRIcCglkaXJlY3Rpb24YAyABKAlSCWRpcmVjdGlv'
    'bhIsChJkZXBhcnR1cmVfc3RvcF9rZXkYBCABKAlSEGRlcGFydHVyZVN0b3BLZXkSKAoQYXJyaX'
    'ZhbF9zdG9wX2tleRgFIAEoCVIOYXJyaXZhbFN0b3BLZXkSHAoJc3VwcG9ydGVkGAYgASgIUglz'
    'dXBwb3J0ZWQ=');

@$core.Deprecated('Use summaryDescriptor instead')
const Summary$json = {
  '1': 'Summary',
  '2': [
    {'1': 'duration', '3': 1, '4': 1, '5': 3, '10': 'duration'},
    {'1': 'length', '3': 2, '4': 1, '5': 1, '10': 'length'},
  ],
};

/// Descriptor for `Summary`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List summaryDescriptor = $convert.base64Decode(
    'CgdTdW1tYXJ5EhoKCGR1cmF0aW9uGAEgASgDUghkdXJhdGlvbhIWCgZsZW5ndGgYAiABKAFSBm'
    'xlbmd0aA==');

@$core.Deprecated('Use placeDescriptor instead')
const Place$json = {
  '1': 'Place',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'type', '3': 2, '4': 1, '5': 9, '10': 'type'},
    {
      '1': 'location',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.Location',
      '10': 'location'
    },
    {'1': 'time', '3': 4, '4': 1, '5': 9, '10': 'time'},
  ],
};

/// Descriptor for `Place`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List placeDescriptor = $convert.base64Decode(
    'CgVQbGFjZRISCgRuYW1lGAEgASgJUgRuYW1lEhIKBHR5cGUYAiABKAlSBHR5cGUSJQoIbG9jYX'
    'Rpb24YAyABKAsyCS5Mb2NhdGlvblIIbG9jYXRpb24SEgoEdGltZRgEIAEoCVIEdGltZQ==');

@$core.Deprecated('Use locationDescriptor instead')
const Location$json = {
  '1': 'Location',
  '2': [
    {'1': 'lat', '3': 1, '4': 1, '5': 1, '10': 'lat'},
    {'1': 'lng', '3': 2, '4': 1, '5': 1, '10': 'lng'},
  ],
};

/// Descriptor for `Location`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List locationDescriptor = $convert.base64Decode(
    'CghMb2NhdGlvbhIQCgNsYXQYASABKAFSA2xhdBIQCgNsbmcYAiABKAFSA2xuZw==');

@$core.Deprecated('Use transportDescriptor instead')
const Transport$json = {
  '1': 'Transport',
  '2': [
    {'1': 'mode', '3': 1, '4': 1, '5': 9, '10': 'mode'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'shortName', '3': 3, '4': 1, '5': 9, '10': 'shortName'},
    {'1': 'longName', '3': 4, '4': 1, '5': 9, '10': 'longName'},
    {'1': 'headsign', '3': 5, '4': 1, '5': 9, '10': 'headsign'},
    {'1': 'category', '3': 6, '4': 1, '5': 9, '10': 'category'},
    {'1': 'routeColor', '3': 7, '4': 1, '5': 9, '10': 'routeColor'},
  ],
};

/// Descriptor for `Transport`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List transportDescriptor = $convert.base64Decode(
    'CglUcmFuc3BvcnQSEgoEbW9kZRgBIAEoCVIEbW9kZRISCgRuYW1lGAIgASgJUgRuYW1lEhwKCX'
    'Nob3J0TmFtZRgDIAEoCVIJc2hvcnROYW1lEhoKCGxvbmdOYW1lGAQgASgJUghsb25nTmFtZRIa'
    'CghoZWFkc2lnbhgFIAEoCVIIaGVhZHNpZ24SGgoIY2F0ZWdvcnkYBiABKAlSCGNhdGVnb3J5Eh'
    '4KCnJvdXRlQ29sb3IYByABKAlSCnJvdXRlQ29sb3I=');

@$core.Deprecated('Use intermediateStopDescriptor instead')
const IntermediateStop$json = {
  '1': 'IntermediateStop',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'location',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.Location',
      '10': 'location'
    },
    {'1': 'departureTime', '3': 3, '4': 1, '5': 9, '10': 'departureTime'},
  ],
};

/// Descriptor for `IntermediateStop`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List intermediateStopDescriptor = $convert.base64Decode(
    'ChBJbnRlcm1lZGlhdGVTdG9wEhIKBG5hbWUYASABKAlSBG5hbWUSJQoIbG9jYXRpb24YAiABKA'
    'syCS5Mb2NhdGlvblIIbG9jYXRpb24SJAoNZGVwYXJ0dXJlVGltZRgDIAEoCVINZGVwYXJ0dXJl'
    'VGltZQ==');

@$core.Deprecated('Use agencyDescriptor instead')
const Agency$json = {
  '1': 'Agency',
  '2': [
    {'1': 'agencyId', '3': 1, '4': 1, '5': 9, '10': 'agencyId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'website', '3': 3, '4': 1, '5': 9, '10': 'website'},
    {'1': 'phone', '3': 4, '4': 1, '5': 9, '10': 'phone'},
  ],
};

/// Descriptor for `Agency`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List agencyDescriptor = $convert.base64Decode(
    'CgZBZ2VuY3kSGgoIYWdlbmN5SWQYASABKAlSCGFnZW5jeUlkEhIKBG5hbWUYAiABKAlSBG5hbW'
    'USGAoHd2Vic2l0ZRgDIAEoCVIHd2Vic2l0ZRIUCgVwaG9uZRgEIAEoCVIFcGhvbmU=');
