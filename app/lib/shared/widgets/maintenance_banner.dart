import 'package:flutter/material.dart';
import 'package:wheres_the_car/core/firebase/remote_config.dart';
import 'package:wheres_the_car/shared/widgets/status_banner.dart';

/// Ops-controlled maintenance notice, shown app-wide when
/// `maintenance_banner_enabled` is on and `maintenance_banner_text` is set.
///
/// Non-dismissible: ops turn it off via the remote flag. Rebuilds on
/// [AppConfig.version] so a Realtime Remote Config push appears without a
/// relaunch.
class MaintenanceBanner extends StatelessWidget {
  const MaintenanceBanner({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: AppConfig.version,
    builder: (context, _, _) => StatusBanner(
      severity: StatusSeverity.maintenance,
      message: AppConfig.getBool('maintenance_banner_enabled')
          ? AppConfig.getString('maintenance_banner_text')
          : null,
    ),
  );
}
