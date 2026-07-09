import 'dart:convert';

import 'package:wheres_the_car/data/models/bus_route_detail.dart';

Set<int> decodeBufferSequences(BusFareInfo? fare) {
  if (fare == null || fare.sectionFaresJson.isEmpty) return const {};
  try {
    final parsed = jsonDecode(utf8.decode(fare.sectionFaresJson));
    if (parsed is! List) return const {};
    final out = <int>{};
    for (final section in parsed) {
      if (section is! Map) continue;
      final zones = section['BufferZones'];
      if (zones is! List) continue;
      for (final zone in zones) {
        if (zone is Map && zone['StopSequence'] is num) {
          out.add((zone['StopSequence'] as num).toInt());
        }
      }
    }
    return out;
  } on Object catch (_) {
    return const {};
  }
}

/// A price row within a fare group: fare-class label + `NT$15`.
typedef FareRow = ({String label, String price});

/// A fare group. `segment` labels the origin→destination stage / OD segment
/// (公路客運) or 第N段 when a route has multiple sections; it is null for a
/// single flat section (typical city bus), where the rows stand alone.
typedef FareGroup = ({String? segment, List<FareRow> rows});

/// The full fare table. TDX stores section / stage / OD fares verbatim; every
/// entry carries a `Fares` array of FareClass / TicketType / Price / FareName.
/// We emit one group per segment (or per section), each listing a row per fare
/// class — split by ticket type (現金 / 電子票證) only when the price differs.
/// Prices of -1 mean "no fare" and are dropped; malformed payloads are skipped.
List<FareGroup> decodeFareTable(BusFareInfo? fare) {
  if (fare == null) return const [];
  final groups = <FareGroup>[];
  _addSectionGroups(fare.sectionFaresJson, groups);
  _addSegmentGroups(fare.stageFaresJson, groups);
  _addSegmentGroups(fare.odFaresJson, groups);
  return groups;
}

/// All destinations reachable from one boarding stop, each carrying its own
/// fare rows. `destination` is the arrival stop name.
typedef OdDestination = ({String destination, List<FareRow> rows});

/// Origin-grouped 起迄 / 分段 fare table (公路客運). One entry per boarding
/// stop, so the UI can present "from stop X, fares to …" instead of repeating
/// the origin on every row. Empty for flat-fare city buses, where
/// [decodeFareTable] already yields inline rows.
typedef OdOrigin = ({String origin, List<OdDestination> destinations});

List<OdOrigin> decodeOdFares(BusFareInfo? fare) {
  if (fare == null) return const [];
  final byOrigin = <String, List<OdDestination>>{};
  final order = <String>[];
  void collect(List<int> payload) {
    for (final entry in _decodeList(payload)) {
      if (entry is! Map) continue;
      final rows = _fareRows(entry['Fares']);
      if (rows.isEmpty) continue;
      final o = _stopName(entry['OriginStage'] ?? entry['OriginStop']);
      final d = _stopName(
        entry['DestinationStage'] ?? entry['DestinationStop'],
      );
      if (o == null || d == null) continue;
      byOrigin.putIfAbsent(o, () {
        order.add(o);
        return [];
      }).add((destination: d, rows: rows));
    }
  }

  collect(fare.stageFaresJson);
  collect(fare.odFaresJson);
  return [for (final o in order) (origin: o, destinations: byOrigin[o]!)];
}

/// Cheapest and dearest fare across the origin-grouped table, for the
/// at-a-glance 票價範圍 summary. Null when [origins] carry no priced rows.
({int min, int max})? odFareRange(List<OdOrigin> origins) {
  var min = -1;
  var max = -1;
  for (final origin in origins) {
    for (final dest in origin.destinations) {
      for (final row in dest.rows) {
        final n = int.tryParse(row.price.replaceAll(RegExp('[^0-9]'), ''));
        if (n == null) continue;
        if (min < 0 || n < min) min = n;
        if (n > max) max = n;
      }
    }
  }
  return min < 0 ? null : (min: min, max: max);
}

void _addSectionGroups(List<int> payload, List<FareGroup> out) {
  final parsed = _decodeList(payload);
  final sections = [
    for (final s in parsed)
      if (s is Map) s,
  ];
  for (final (i, s) in sections.indexed) {
    final rows = _fareRows(s['Fares']);
    if (rows.isEmpty) continue;
    // A single section is the whole fare — no segment label needed.
    out.add((segment: sections.length > 1 ? '第${i + 1}段' : null, rows: rows));
  }
}

void _addSegmentGroups(List<int> payload, List<FareGroup> out) {
  for (final entry in _decodeList(payload)) {
    if (entry is! Map) continue;
    final rows = _fareRows(entry['Fares']);
    if (rows.isEmpty) continue;
    out.add((segment: _segmentLabel(entry), rows: rows));
  }
}

List<Object?> _decodeList(List<int> payload) {
  if (payload.isEmpty) return const [];
  try {
    final parsed = jsonDecode(utf8.decode(payload));
    return parsed is List ? parsed : const [];
  } on Object catch (_) {
    return const [];
  }
}

// Origin → destination for a stage/OD entry. Stage/OD descriptors carry a
// StopName that TDX serialises as a plain string (stage sample) or a localized
// {Zh_tw, En} object; both are handled. Null when either endpoint is missing.
String? _segmentLabel(Map<Object?, Object?> entry) {
  final o = _stopName(entry['OriginStage'] ?? entry['OriginStop']);
  final d = _stopName(entry['DestinationStage'] ?? entry['DestinationStop']);
  if (o == null || d == null) return null;
  return '$o → $d';
}

String? _stopName(Object? stop) {
  if (stop is! Map) return null;
  final name = stop['StopName'];
  if (name is String && name.isNotEmpty) return name;
  if (name is Map) {
    final zh = name['Zh_tw'];
    if (zh is String && zh.isNotEmpty) return zh;
  }
  return null;
}

List<FareRow> _fareRows(Object? faresRaw) {
  if (faresRaw is! List) return const [];
  final byClass = <int, List<({String? name, int ticket, int price})>>{};
  for (final f in faresRaw) {
    if (f is! Map) continue;
    final cls = f['FareClass'];
    final price = f['Price'];
    if (cls is! num || price is! num || price <= 0) continue;
    final name = f['FareName'];
    final ticket = f['TicketType'];
    byClass.putIfAbsent(cls.toInt(), () => []).add((
      name: name is String && name.isNotEmpty ? name : null,
      ticket: ticket is num ? ticket.toInt() : 0,
      price: price.toInt(),
    ));
  }
  final rows = <FareRow>[];
  for (final cls in _fareClassOrder(byClass.keys)) {
    final entries = byClass[cls]!;
    final distinctPrices = {for (final e in entries) e.price};
    if (distinctPrices.length == 1) {
      final label = _fareClassLabel(cls);
      rows.add((label: label, price: _money(entries.first.price)));
      continue;
    }
    // Prices split within the class (現金 vs 電子票證, or seat class): one row
    // per entry, deduped, labelled by TDX's FareName when it provides one.
    final seen = <String>{};
    for (final e in entries) {
      final label = e.name != null
          ? e.name!.replaceAll('_', ' ')
          : '${_fareClassLabel(cls)}${e.ticket == 3 ? ' · 電子票證' : ''}';
      if (seen.add('$label|${e.price}')) {
        rows.add((label: label, price: _money(e.price)));
      }
    }
  }
  return rows;
}

// TDX Bus FareClass enum (PTX). 1/10 confirmed against sample FareNames
// (全票/半票); the rest follow the documented enum. Unknown codes fall back to
// a numbered label rather than being dropped.
const Map<int, String> _fareClassLabels = {
  1: '全票',
  10: '半票',
  2: '學生票',
  7: '兒童票',
  3: '敬老票',
  4: '愛心票',
  5: '愛心陪伴票',
  6: '團體票',
  9: '其他優待',
};

// Headline classes (全票, 半票) first, then remaining known classes in map
// order, then any unmapped codes sorted — keeps the common rows on top.
List<int> _fareClassOrder(Iterable<int> classes) {
  const priority = [1, 10, 2, 7, 3, 4, 5, 6, 9];
  final present = classes.toSet();
  final known = [for (final c in priority) if (present.remove(c)) c];
  final unknown = present.toList()..sort();
  return [...known, ...unknown];
}

String _fareClassLabel(int cls) => _fareClassLabels[cls] ?? '票種 $cls';

String _money(int price) => 'NT\$$price';
