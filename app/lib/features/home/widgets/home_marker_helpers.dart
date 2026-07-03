part of '../home_screen.dart';

const _kLargeDotZoomThreshold = 13.0;
const _kSmallDotSize = 7.0;
const _kLargeDotSize = 10.0;
const _kMapMarkerLimit = 60;
const _kFallbackRadiusMeters = 900;

enum _MarkerStyle { largeDot, smallDot }

_MarkerStyle _markerStyle(double zoom) {
  if (zoom >= _kLargeDotZoomThreshold) return _MarkerStyle.largeDot;
  return _MarkerStyle.smallDot;
}

Color _mrtColor(String stationId) {
  final code = stationId.split(RegExp(r'[_\d]')).first.toUpperCase();
  switch (code) {
    case 'BL':
      return AppTheme.mrtBL;
    case 'R':
      return AppTheme.mrtR;
    case 'G':
      return AppTheme.mrtG;
    case 'O':
      return AppTheme.mrtO;
    case 'BR':
      return AppTheme.mrtBR;
    case 'Y':
      return AppTheme.mrtY;
    default:
      return AppTheme.mrtBL;
  }
}

double _dotMarkerSize(_MarkerStyle style) =>
    style == _MarkerStyle.largeDot ? _kLargeDotSize : _kSmallDotSize;

Future<BitmapDescriptor> _markerIcon(
  NearStationViewModel s,
  _MarkerStyle style,
) {
  final dotSize = _dotMarkerSize(style);
  switch (s.type) {
    case NearStationType.bus:
      return MapMarkers.dot(const Color(0xFFC03634), size: dotSize);
    case NearStationType.bike:
      return MapMarkers.dot(const Color(0xFFDFE24D), size: dotSize);
    case NearStationType.mrt:
      return MapMarkers.dot(_mrtColor(s.stationId), size: dotSize);
    case NearStationType.tra:
    case NearStationType.thsr:
      return MapMarkers.dot(const Color(0xFF285FF4), size: dotSize);
  }
}

TransportType _nearbyIconType(NearStationViewModel s) {
  switch (s.type) {
    case NearStationType.bus:
      return TransportType.bus;
    case NearStationType.bike:
      return TransportType.bike;
    case NearStationType.mrt:
      return _mrtLineType(s.stationId);
    case NearStationType.tra:
      return TransportType.tra;
    case NearStationType.thsr:
      return TransportType.thsr;
  }
}

TransportType _mrtLineType(String stationId) {
  final code = stationId.split(RegExp(r'[_\d]')).first.toUpperCase();
  switch (code) {
    case 'BL':
      return TransportType.mrtBL;
    case 'R':
      return TransportType.mrtR;
    case 'G':
      return TransportType.mrtG;
    case 'O':
      return TransportType.mrtO;
    case 'BR':
      return TransportType.mrtBR;
    case 'Y':
      return TransportType.mrtY;
    default:
      return TransportType.mrtBL;
  }
}
