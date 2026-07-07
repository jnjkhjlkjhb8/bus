import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/data/models/near_models.dart';

/// 依站別回傳首頁第二層 sheet 要顯示的 detail 內容。
/// Task 3-7 逐一把各 case 換成真正的 *DetailView；在那之前一律回 placeholder。
Widget stationDetailPage(NearStationViewModel station) {
  switch (station.type) {
    case NearStationType.bus:
    case NearStationType.bike:
    case NearStationType.mrt:
    case NearStationType.tra:
    case NearStationType.thsr:
      return _StationDetailPlaceholder(station: station);
  }
}

class _StationDetailPlaceholder extends StatelessWidget {
  const _StationDetailPlaceholder({required this.station});

  final NearStationViewModel station;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(station.stationName, style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          Text(
            '步行 ${station.walkingMinutes} 分',
            style: AppTextStyles.bodyRegular,
          ),
        ],
      ),
    );
  }
}
