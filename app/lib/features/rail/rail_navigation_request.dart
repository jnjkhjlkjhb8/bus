import 'package:wheres_the_car/features/rail/bloc/rail_event.dart';

/// One-shot hand-off channel into the rail screen.
///
/// Producers sit above the rail screen's navigator boundary (the home sheet, a
/// station detail view) and can't reach the rail bloc directly, so they write a
/// request here; the rail screen reads and clears it on didChangeDependencies.
///
/// Two shapes:
/// - a station preset (origin only, [autoSubmit] false) — pre-fills the picker
///   without running a query;
/// - a full O/D query ([autoSubmit] true) — the rail screen dispatches the
///   timetable request immediately on open.
class RailQueryRequest {
  const RailQueryRequest({
    required this.system,
    required this.originName,
    required this.date,
    this.originId,
    this.destName,
    this.destId,
    this.autoSubmit = false,
    this.isDeparture = true,
  });

  final RailSystem system;
  final String originName;
  final String? originId;
  final String? destName;
  final String? destId;
  // [date] carries the selected time-of-day; with [isDeparture] it bounds the
  // results (depart at/after vs arrive at/before) once the rail screen queries.
  final DateTime date;
  final bool autoSubmit;
  final bool isDeparture;
}

class RailNavigationRequest {
  RailNavigationRequest._();

  static RailQueryRequest? _pending;

  // A named method reads better than a setter at the call sites
  // (`RailNavigationRequest.set(...)`) and pairs with `consume()`.
  // ignore: use_setters_to_change_properties
  static void set(RailQueryRequest request) {
    _pending = request;
  }

  static RailQueryRequest? consume() {
    final v = _pending;
    _pending = null;
    return v;
  }
}
