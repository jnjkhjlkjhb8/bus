/// What the rider is looking at, when the URL cannot say it.
///
/// A station opened from the home nearby list is a page inside the sheet's own
/// navigator, so the route stays `/` and a report filed from it names no
/// station — which is the one thing a report about a station has to say. A
/// screen that owns such a page [hold]s a label while it is up.
abstract final class ReportScreen {
  static String? _route;
  static String? _detail;

  /// Names what [route] is showing beyond what its URL carries.
  static void hold({required String route, required String detail}) {
    _route = route;
    _detail = detail;
  }

  static void release() {
    _route = null;
    _detail = null;
  }

  /// The held detail when the rider is still on [location], otherwise null: a
  /// page pushed over the home sheet leaves it mounted underneath, and the
  /// station it was showing must not follow the rider onto settings.
  static String? detailFor(String location) =>
      location == _route ? _detail : null;
}
