part of '../home_screen.dart';

/// Members are labelled individually up to this many. Above it the group falls
/// back to plain plates, with the label reserved for the selected member: four
/// long capsules at one junction collide whichever side they lean to, and at
/// that density the question being asked is "which one did I tap", not "name
/// all of them".
const int _kLabelAllUpTo = 3;

/// Breathing room around the member bounds when the camera fits them, in
/// logical pixels. Clears the 44px floating controls and their 16px margin
/// with room to spare, so the outermost pole's capsule lands on the map
/// rather than under the chrome.
const double _kMemberBoundsPadding = 120;

/// How far off the camera centre a group has to be before the tap pans to it,
/// as a fraction of the viewport's shorter side. Inside this the pin is
/// already comfortably in view, and panning to it only adds a lurch before the
/// bounds fit that follows.
const double _kRecentreThresholdFrac = 0.22;

/// Metres per degree of latitude. A station group spans ~100 m, so the
/// spherical correction is far below a pixel.
const double _kMetresPerDegree = 111320;

/// Where the open group is in its life.
///
/// The poles are markers throughout: the map composites a marker with the
/// ground in the same frame, so it holds still through a pan, which a widget
/// pinned to a coordinate cannot — it has to chase the camera over the
/// platform channel and shakes.
enum _SpreadPhase {
  /// No group open.
  idle,

  /// Group tapped, poles still being fetched. Its own pin stands in — the wait
  /// is a network round trip long and the spot the user tapped stays occupied.
  holding,

  /// Poles on the map.
  open,
}

/// What the map is showing for the open bus station group: where it came from,
/// the poles under it, and which one the sheet has selected.
///
/// Snapshotted off [BusStopBloc] rather than read from it, so the capsules
/// survive the bloc being closed on the way out.
typedef _MemberSpread = ({
  LatLng origin,
  List<BusStationMember> members,
  Map<String, String> labels,
  String? selectedUid,
});

/// How one pole is drawn, resolved once per spread.
typedef _SpreadPart = ({
  BusStationMember member,
  String label,
  bool labelled,
  bool selected,
  bool flip,
});

/// Screen position of [point] for a camera centred on [center] at [zoom].
///
/// **Only valid while the camera is still.** Google keeps the camera target
/// centred in what is left of the viewport after padding, but the camera state
/// this reads arrives on the platform channel out of step with the map's own
/// frames. That is fine for the one thing it is used for — deciding whether
/// the poles are already framed, asked once before a camera move rather than
/// per frame — and would not be for anything drawn from it. Mercator is linear
/// in longitude and locally linear in latitude, so a first-order expansion
/// around the centre is exact to well under a pixel across a station group.
Offset _projectToScreen({
  required LatLng point,
  required LatLng center,
  required double zoom,
  required Size viewport,
  required double bottomPadding,
}) {
  final mpp = metersPerPixel(center.latitude, zoom);
  final cosLat = math.cos(center.latitude * math.pi / 180);
  final dx =
      (point.longitude - center.longitude) * _kMetresPerDegree * cosLat / mpp;
  final dy = -(point.latitude - center.latitude) * _kMetresPerDegree / mpp;
  return Offset(
    viewport.width / 2 + dx,
    (viewport.height - bottomPadding) / 2 + dy,
  );
}

extension _HomeScreenMemberCapsules on _HomeScreenState {
  /// Resolves each pole's part and caches it for the run.
  void _resolveSpreadParts(_MemberSpread spread) {
    final labelAll = spread.members.length <= _kLabelAllUpTo;
    _spreadParts = [
      for (final m in spread.members)
        _spreadPart(m, spread, labelAll: labelAll),
    ];
  }

  _SpreadPart _spreadPart(
    BusStationMember member,
    _MemberSpread spread, {
    required bool labelAll,
  }) {
    final selected = member.stationUid == spread.selectedUid;
    final label = spread.labels[member.stationUid] ?? member.stationName;
    // A label earns its place by saying where the pole goes. Until arrivals
    // name a destination, memberStopLabels falls back to the station name —
    // which every pole in the group shares, so a row of identical capsules
    // would answer nothing. Unnamed poles stay bare until one is picked, and
    // then only the picked one speaks, which is answer enough.
    final named = label.startsWith(kMemberDestinationPrefix);
    return (
      member: member,
      label: label,
      labelled: named ? labelAll || selected : selected,
      selected: selected,
      // The label leans away from the group centre, so poles on opposite sides
      // of a junction lean apart instead of into each other. Ceiling: three or
      // more on the same side still overlap, which is what the plates-only
      // fallback above _kLabelAllUpTo is for.
      flip: member.lon < spread.origin.longitude,
    );
  }

  /// Publishes the poles as markers, replacing whatever the group set held —
  /// the holding pin on the way in, an older selection on a refresh.
  Future<void> _publishMemberMarkers() async {
    final revision = ++_memberRevision;
    if (_spreadParts.isEmpty) {
      _memberMarkers.value = const {};
      return;
    }
    final built = <Marker>[];
    for (final part in _spreadParts) {
      final capsule = part.labelled
          ? await MapMarkers.stationCapsule(
              asset: 'assets/marker/Bus.svg',
              label: part.label,
              selected: part.selected,
              flip: part.flip,
            )
          : (
              icon: await MapMarkers.svgAsset(
                'assets/marker/Bus.svg',
                size: _kIconMarkerSize,
              ),
              anchor: const Offset(0.5, 0.5),
            );
      built.add(
        Marker(
          markerId: MarkerId('member:${part.member.stationUid}'),
          position: LatLng(part.member.lat, part.member.lon),
          icon: capsule.icon,
          anchor: capsule.anchor,
          zIndexInt: part.selected ? 1 : 0,
          onTap: () =>
              _selectMember(part.selected ? null : part.member.stationUid),
        ),
      );
    }
    if (!mounted || revision != _memberRevision) return;
    _memberMarkers.value = built.toSet();
  }

  /// Stand-in for the tapped group while its poles are being fetched. It moves
  /// out of the nearby set and into this one the moment the group is opened,
  /// so nothing blinks where the user just tapped.
  Future<void> _holdGroupPin(NearStationViewModel station) async {
    final revision = _memberRevision;
    final icon = await _markerIcon(station, _markerStyle(_zoom));
    if (!mounted ||
        revision != _memberRevision ||
        _spreadPhase.value != _SpreadPhase.holding) {
      return;
    }
    _memberMarkers.value = {
      Marker(
        markerId: MarkerId('${station.type.name}:${station.stationId}'),
        position: LatLng(station.lat, station.lon),
        icon: icon,
        anchor: const Offset(0.5, 0.5),
      ),
    };
  }
}
