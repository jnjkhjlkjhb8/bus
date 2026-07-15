import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/data/models/alert_models.dart';

/// Relative time in Traditional Chinese, coarsened to the buckets a rider
/// cares about. Pure so it can be unit-tested against a fixed [now].
String alertRelativeTime(DateTime time, DateTime now) {
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return '剛剛';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前';
  if (diff.inHours < 24) return '${diff.inHours} 小時前';

  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(time.year, time.month, time.day);
  if (today.difference(that).inDays == 1) return '昨天';
  return '${time.month}/${time.day}';
}

/// Label + operator color for an [AlertSource]. Metro/bus resolve their code to
/// a localized operator name; rail kinds are fixed. Returns null for a null
/// source so callers can omit the chip entirely.
({String label, Color color})? _resolve(AlertSource source) {
  switch (source.kind) {
    case AlertSourceKind.metro:
      final label = switch (source.code) {
        'TRTC' => '北捷',
        'TYMC' => '桃捷',
        'KRTC' => '高捷',
        'TMRT' => '中捷',
        _ => source.code,
      };
      return (label: label, color: AppTheme.mrtBL);
    case AlertSourceKind.tra:
      return (label: '台鐵', color: AppTheme.trainRangecar);
    case AlertSourceKind.thsr:
      return (label: '高鐵', color: AppTheme.trainThsr);
    case AlertSourceKind.bus:
      final label = switch (source.code) {
        'Taipei' => '北市公車',
        'NewTaipei' => '新北公車',
        'Taoyuan' => '桃園公車',
        'Taichung' => '中市公車',
        'Tainan' => '南市公車',
        'Kaohsiung' => '高市公車',
        _ => '公車',
      };
      // Ink carries the bus chip. In dark mode a #111111 fill would vanish, so
      // fall back to the inverse surface pair which keeps the contrast.
      return (label: label, color: AppTheme.inkLight);
  }
}

/// Compact operator tag: which system an alert belongs to, colored by operator
/// (colors are data here, not decoration). Renders nothing for a null source.
class AlertSourceChip extends StatelessWidget {
  const AlertSourceChip({required this.source, super.key});

  final AlertSource? source;

  @override
  Widget build(BuildContext context) {
    final source = this.source;
    if (source == null) return const SizedBox.shrink();
    final resolved = _resolve(source);
    if (resolved == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    // The Ink bus chip needs a dark-mode substitute; operator colors stand on
    // their own against both surfaces.
    final isInk = resolved.color == AppTheme.inkLight;
    final bg = isInk && dark ? cs.inverseSurface : resolved.color;
    final fg = isInk && dark ? cs.onInverseSurface : Colors.white;

    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        resolved.label,
        style: TextStyle(
          fontFamily: 'IBMPlexSans',
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          height: 1,
          color: fg,
        ),
      ),
    );
  }
}
