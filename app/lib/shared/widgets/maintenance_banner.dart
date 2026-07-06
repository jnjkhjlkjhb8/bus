import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/firebase/remote_config.dart';

/// Ops-controlled maintenance notice, shown app-wide when
/// `maintenance_banner_enabled` is on and `maintenance_banner_text` is set.
///
/// Static (no animation) and non-dismissible: ops turn it off via the remote
/// flag. The remote value is fixed for the session, so the banner reflects a
/// change on the next fetch/launch — reading once at build is enough.
class MaintenanceBanner extends StatelessWidget {
  const MaintenanceBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.getBool('maintenance_banner_enabled')) {
      return const SizedBox.shrink();
    }
    final text = AppConfig.getString('maintenance_banner_text');
    if (text.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          color: AppTheme.warningBg,
          border: Border.symmetric(
            horizontal: BorderSide(color: AppTheme.warningBorder, width: 0.5),
          ),
        ),
        child: Row(
          spacing: 6,
          children: [
            const Icon(
              Icons.build_rounded,
              size: 18,
              color: AppTheme.warningBorder,
            ),
            Expanded(
              child: Text(
                text,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppTheme.warningBorder,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
