import 'package:wheres_the_car/data/generated/thsr.pb.dart';
import 'package:wheres_the_car/data/generated/tra.pb.dart';
import 'package:wheres_the_car/data/models/search_models.dart';

/// Converts a backend-shaped search result into row presentation data.
SearchResultViewData searchResult(BackendSearchResult result) {
  final hasRouteSubtitle = result.depart.isNotEmpty && result.destin.isNotEmpty;

  return SearchResultViewData(
    type: result.type,
    uid: result.uid,
    title: result.name,
    subtitle: hasRouteSubtitle
        ? '${result.depart} → ${result.destin}'
        : result.city ?? '',
  );
}

/// Builds a TRA route title from backend timetable data.
String traRouteTitle(tra_timetable timetable) {
  return '${timetable.trainNo} / ${timetable.trainTypeName}';
}

/// Builds a TRA route subtitle from backend timetable data.
String traRouteSubtitle(tra_timetable timetable) {
  return '${timetable.startingStationName} → ${timetable.endingStationName}';
}

/// Builds a THSR route title from backend timetable data.
String thsrRouteTitle(thsa_timetable timetable) {
  return '${timetable.trainNo} / 高鐵';
}

/// Builds a THSR route subtitle from backend timetable data.
String thsrRouteSubtitle(thsa_timetable timetable) {
  return '${timetable.startingStationName} → ${timetable.endingStationName}';
}
