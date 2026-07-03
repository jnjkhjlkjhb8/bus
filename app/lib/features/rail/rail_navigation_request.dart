import 'package:wheres_the_car/features/rail/bloc/rail_event.dart';

/// One-shot channel: search overlay → rail screen.
/// The overlay can't reach RailBloc (root navigator boundary), so it writes
/// here; the rail screen reads and clears on didChangeDependencies.
class RailNavigationRequest {
  RailNavigationRequest._();

  static ({String stationId, String stationName, RailSystem system})? _pending;

  static void set({
    required String stationId,
    required String stationName,
    required RailSystem system,
  }) {
    _pending = (stationId: stationId, stationName: stationName, system: system);
  }

  static ({String stationId, String stationName, RailSystem system})?
  consume() {
    final v = _pending;
    _pending = null;
    return v;
  }
}
