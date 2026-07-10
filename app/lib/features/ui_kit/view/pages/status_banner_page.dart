import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/status_banner.dart';

class StatusBannerPage extends StatelessWidget {
  const StatusBannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Status Banner'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: const [
          ShowcaseSection(
            title: 'Maintenance',
            child: StatusBanner(
              severity: StatusSeverity.maintenance,
              message: '系統維護中（03:00–05:00），即時到站可能暫停。',
            ),
          ),
          ShowcaseSection(
            title: 'Neutral',
            child: StatusBanner(
              severity: StatusSeverity.neutral,
              message: '目前離線，顯示快取資料。',
            ),
          ),
          ShowcaseSection(
            title: 'Two-line clamp',
            child: StatusBanner(
              severity: StatusSeverity.maintenance,
              message: '系統維護中（03:00–05:00），即時到站與規劃可能暫停，'
                  '靜態時刻表不受影響。造成不便敬請見諒，我們會盡快恢復服務。',
            ),
          ),
          ShowcaseSection(
            title: 'Empty message collapses',
            child: StatusBanner(severity: StatusSeverity.maintenance),
          ),
          ShowcaseSection(title: 'Enter / exit', child: _SqueezeDemo()),
        ],
      ),
    );
  }
}

/// Mirrors the real placement: the banner sits above content and pushes it
/// down as it grows, rather than floating over it.
class _SqueezeDemo extends StatefulWidget {
  const _SqueezeDemo();

  @override
  State<_SqueezeDemo> createState() => _SqueezeDemoState();
}

class _SqueezeDemoState extends State<_SqueezeDemo> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        StatusBanner(
          severity: StatusSeverity.maintenance,
          message: _shown ? '系統維護中，即時到站可能暫停。' : null,
        ),
        Container(
          height: 96,
          alignment: Alignment.center,
          color: cs.surfaceContainerHighest,
          child: Text(
            'content below',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => setState(() => _shown = !_shown),
          child: Text(_shown ? 'Clear message' : 'Push message'),
        ),
      ],
    );
  }
}
