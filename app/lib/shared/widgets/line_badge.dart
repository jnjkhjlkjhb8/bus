import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';

Color mrtLineColor(String lineCode, ColorScheme cs) {
  final code = lineCode.toUpperCase();
  if (code.startsWith('BR')) return AppTheme.mrtBR;
  if (code.startsWith('BL')) return AppTheme.mrtBL;
  if (code.startsWith('R')) return AppTheme.mrtR;
  if (code.startsWith('G')) return AppTheme.mrtG;
  if (code.startsWith('O')) return AppTheme.mrtO;
  if (code.startsWith('Y')) return AppTheme.mrtY;
  if (code.startsWith('A')) return AppTheme.mrtAM;
  if (code.startsWith('C')) return AppTheme.mrtKG;
  if (code.startsWith('KO')) return AppTheme.mrtKO;
  if (code.startsWith('KR')) return AppTheme.mrtKR;
  return cs.onSurfaceVariant;
}

String mrtLineLabel(String lineCode) {
  final code = lineCode.toUpperCase();
  if (code.startsWith('BR')) return '文湖';
  if (code.startsWith('BL')) return '板南';
  if (code.startsWith('R')) return '淡水';
  if (code.startsWith('G')) return '松山';
  if (code.startsWith('O')) return '中和';
  if (code.startsWith('Y')) return '環狀';
  if (code.startsWith('A')) return '機捷';
  if (code.startsWith('C')) return '輕軌';
  if (code.startsWith('KO')) return '高捷';
  if (code.startsWith('KR')) return '高捷';
  return lineCode;
}

class LineBadge extends StatelessWidget {
  const LineBadge({
    required this.label,
    required this.color,
    this.svgAsset,
    this.size = 25,
    super.key,
  });

  final String label;
  final Color color;
  final String? svgAsset;
  final double size;

  static String? trtcAsset(String code) => switch (code) {
    'BL' => 'assets/mrt/TRTC/BL.svg',
    'R' => 'assets/mrt/TRTC/R.svg',
    'G' => 'assets/mrt/TRTC/G.svg',
    'O' => 'assets/mrt/TRTC/O.svg',
    'BR' => 'assets/mrt/TRTC/BR.svg',
    'Y' => 'assets/mrt/TRTC/Y.svg',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final asset = svgAsset;
    if (asset == null) return _fallback();

    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      placeholderBuilder: (_) => _fallback(),
    );
  }

  Widget _fallback() {
    final textColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: textColor,
          fontSize: (size * 0.36).clamp(9, 14),
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
