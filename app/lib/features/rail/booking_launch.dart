import 'package:url_launcher/url_launcher.dart';
import 'package:wheres_the_car/core/http/http_client.dart';

Future<void> launchRailBooking({
  required bool isThsr,
  required String origin,
  required String destination,
  required String date,
  required String trainNumber,
}) async {
  final agency = isThsr ? 'hsr' : 'tra';
  final scheme = isThsr ? 'thsrc' : 'tra-tip';
  var installed = false;
  try {
    installed = await canLaunchUrl(Uri.parse('$scheme://'));
  } on Object catch (_) {
    installed = false;
  }
  final kind = installed ? 'direct' : 'web';

  final url = await _bookingUrl(
    agency: agency,
    kind: kind,
    origin: origin,
    destination: destination,
    date: date,
    trainNumber: trainNumber,
  );

  await launchUrl(
    Uri.parse(url ?? _fallbackBookingSite(isThsr)),
    mode: LaunchMode.externalApplication,
  );
}

Future<String?> _bookingUrl({
  required String agency,
  required String kind,
  required String origin,
  required String destination,
  required String date,
  required String trainNumber,
}) async {
  try {
    final res = await HttpClient.instance.dio.get<Map<String, dynamic>>(
      '/api/booking/deeplink',
      queryParameters: <String, String>{
        'agency': agency,
        'kind': kind,
        'start_station': origin,
        'end_station': destination,
        'train_date': date,
        'train_number': trainNumber,
      },
    );
    final url = res.data?['url'];
    return url is String && url.isNotEmpty ? url : null;
  } on Object catch (_) {
    // Router unavailable (e.g. non-prod has no TDX credentials → 503) or
    // network error: caller falls back to the plain booking site.
    return null;
  }
}

String _fallbackBookingSite(bool isThsr) => isThsr
    ? 'https://irs.thsrc.com.tw/IMINT/'
    : 'https://www.railway.gov.tw/tra-tip-web/tip/tip001/tip123/query';
