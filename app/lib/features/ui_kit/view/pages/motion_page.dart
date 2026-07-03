import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';

class MotionPage extends StatelessWidget {
  const MotionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Motion'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: const [
          ShowcaseSection(
            title: 'Timings',
            child: Column(
              children: [
                _TimingRow('press', AppMotion.press),
                _TimingRow('short', AppMotion.short),
                _TimingRow('medium', AppMotion.medium),
                _TimingRow('sheet', AppMotion.sheet),
              ],
            ),
          ),
          ShowcaseSection(
            title: 'Easing Demo (tap to replay)',
            child: Column(
              children: [
                _EasingDemo('easeOut', AppMotion.easeOut, AppMotion.medium),
                _EasingDemo('easeInOut', AppMotion.easeInOut, AppMotion.medium),
                _EasingDemo('drawer', AppMotion.drawer, AppMotion.sheet),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimingRow extends StatelessWidget {
  const _TimingRow(this.name, this.duration);
  final String name;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              name,
              style: AppTextStyles.bodySmall.copyWith(
                fontFamily: 'IBMPlexMono',
              ),
            ),
          ),
          Container(
            width: duration.inMilliseconds.toDouble() * 0.6,
            height: 8,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(AppTheme.radiusStadium),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${duration.inMilliseconds}ms',
            style: AppTextStyles.bodySmall.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _EasingDemo extends StatefulWidget {
  const _EasingDemo(this.name, this.curve, this.duration);
  final String name;
  final Curve curve;
  final Duration duration;

  @override
  State<_EasingDemo> createState() => _EasingDemoState();
}

class _EasingDemoState extends State<_EasingDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = CurvedAnimation(parent: _ctrl, curve: widget.curve);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _replay() {
    _ctrl.reset();
    unawaited(_ctrl.forward());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: MediaQuery.disableAnimationsOf(context) ? null : _replay,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.name,
              style: AppTextStyles.bodySmall.copyWith(
                fontFamily: 'IBMPlexMono',
              ),
            ),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                height: 32,
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (_, _) => Align(
                    alignment: Alignment.centerLeft,
                    child: Transform.translate(
                      offset: Offset(
                        _anim.value * (constraints.maxWidth - 32),
                        0,
                      ),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
