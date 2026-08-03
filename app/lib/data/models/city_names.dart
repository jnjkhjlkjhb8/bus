/// TDX city codes and their Chinese display names.
///
/// `search_vector.city` stores the raw TDX code (`NewTaipei`), which is what
/// the search API filters on and returns. Nothing user-facing should show
/// that code, so every display path goes through [cityName].
///
/// The backend keeps its own copy in `services/functions/vector.go`, where the
/// names are folded into the embedding text rather than rendered. The two
/// lists are the same data for different jobs; a code missing here degrades to
/// the raw code rather than to a blank, so an unmapped city is visible instead
/// of silent.
///
/// Insertion order is north to south — the order Taiwanese transit signage,
/// timetables, and route lists use — and is the tiebreak for anything ranking
/// cities, so a list of them never comes out alphabetised by an English code
/// the reader never sees.
const Map<String, String> kCityNames = {
  'Keelung': '基隆市',
  'Taipei': '台北市',
  'NewTaipei': '新北市',
  'Taoyuan': '桃園市',
  'Hsinchu': '新竹市',
  'HsinchuCounty': '新竹縣',
  'MiaoliCounty': '苗栗縣',
  'Taichung': '台中市',
  'ChanghuaCounty': '彰化縣',
  'NantouCounty': '南投縣',
  'YunlinCounty': '雲林縣',
  'Chiayi': '嘉義市',
  'ChiayiCounty': '嘉義縣',
  'Tainan': '台南市',
  'Kaohsiung': '高雄市',
  'PingtungCounty': '屏東縣',
  'YilanCounty': '宜蘭縣',
  'HualienCounty': '花蓮縣',
  'TaitungCounty': '台東縣',
  'PenghuCounty': '澎湖縣',
  'KinmenCounty': '金門縣',
  'LienchiangCounty': '連江縣',
  'InterCity': '公路客運',
  // TDX is inconsistent about the `County` suffix across datasets, so both
  // spellings land in `search_vector.city` and both have to resolve.
  'Miaoli': '苗栗縣',
  'Changhua': '彰化縣',
  'Nantou': '南投縣',
  'Yunlin': '雲林縣',
  'Pingtung': '屏東縣',
  'Yilan': '宜蘭縣',
  'Hualien': '花蓮縣',
  'Taitung': '台東縣',
  'Penghu': '澎湖縣',
  'Kinmen': '金門縣',
  'Lienchiang': '連江縣',
};

/// Chinese display name for a TDX city [code], or the code itself when it maps
/// to nothing.
String cityName(String code) => kCityNames[code] ?? code;

final Map<String, int> _cityRank = {
  for (final (index, code) in kCityNames.keys.indexed) code: index,
};

/// Rank used to order cities north to south. Unmapped codes sort last, in
/// their own alphabetical order, rather than jumping to the front.
int cityOrder(String code) => _cityRank[code] ?? kCityNames.length;
