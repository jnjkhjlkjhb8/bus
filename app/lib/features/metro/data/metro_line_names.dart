import 'package:wheres_the_bus/l10n/app_i18n.dart';

/// Metro line code → the line's name in the rider's language.
///
/// Built per call rather than held in a const map: line names follow the
/// rider's language. Lifted out of the metro screens once the alight-tracking
/// card needed the same lookup — three copies of this map had already started
/// drifting apart.
Map<String, String> metroLineNames(AppI18n i18n) => {
  'BL': i18n.metroLineBannan,
  'R': i18n.metroLineTamsuiXinyi,
  'G': i18n.metroLineSongshanXindian,
  'BR': i18n.metroLineWenhu,
  'O': i18n.metroLineZhongheXinlu,
  'Y': i18n.metroLineCircular,
};

/// [code] is a bare line code (`BL`), not a station id. Falls back to the
/// code itself, which is what a rider reads off the station signage anyway.
String metroLineName(AppI18n i18n, String code) =>
    metroLineNames(i18n)[code] ?? code;
