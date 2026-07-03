import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/alert_card.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});
  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  var _redVisible = true;
  var _yellowVisible = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Alerts'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ShowcaseSection(
            title: 'Banners',
            child: Column(
              children: [
                AnimatedAlertBanner(
                  visible: _redVisible,
                  child: AlertCard(
                    level: AlertLevel.red,
                    system: '台鐵',
                    message: '因強風影響，北迴線各列車延誤 20 分鐘',
                    onDismiss: () => setState(() => _redVisible = false),
                  ),
                ),
                AnimatedAlertBanner(
                  visible: _yellowVisible,
                  child: AlertCard(
                    level: AlertLevel.yellow,
                    system: '板南線',
                    message: '府中站施工，部分列車延誤',
                    onDismiss: () => setState(() => _yellowVisible = false),
                  ),
                ),
              ],
            ),
          ),
          const ShowcaseSection(
            title: 'Pulsing Alert Dot',
            child: Row(
              children: [
                PulsingAlertDot(),
                SizedBox(width: 8),
                Text('即時警報'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
