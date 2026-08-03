import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/core/storage/hive_store.dart';
import 'package:wheres_the_bus/data/models/fare_type.dart';
import 'package:wheres_the_bus/data/repositories/settings_repository.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';

/// Rebuilds [builder] with the rider's current ticket type, and again the
/// moment they change it in Settings.
///
/// Every fare in the app is quoted through this, so a rider who sets 敬老 sees
/// their own price on screens that were already loaded — the alternative,
/// resolving the ticket type when the fare is fetched, leaves whatever screen
/// they came from quoting 全票 until it refetches, which is exactly the screen
/// they walk back to after changing the setting.
class FarePreferenceBuilder extends StatelessWidget {
  const FarePreferenceBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, FareType fareType) builder;

  @override
  Widget build(BuildContext context) {
    if (!HiveStore.settingsReady) {
      return builder(context, FareType.full);
    }
    return ValueListenableBuilder(
      valueListenable: HiveStore.settings.listenable(
        keys: const [SettingsRepository.fareTypeKey],
      ),
      builder: (context, _, _) =>
          builder(context, SettingsRepository.instance.fareType),
    );
  }
}

/// A price with the ticket type it belongs to.
///
/// The type sits beside the number rather than in a heading above it, because
/// the number is what the rider reads first and the type is what makes it
/// trustworthy. When the pair prices no fare for [requested], the label names
/// what was actually found and a note says so outright — a full fare shown
/// silently under a 敬老 preference is a wrong number, not a graceful fallback.
class FareAmount extends StatelessWidget {
  const FareAmount({
    required this.fare,
    required this.requested,
    this.style,
    super.key,
  });

  final ResolvedFare fare;

  /// The rider's preference, to compare against `ResolvedFare.matched`.
  final FareType requested;

  /// Overrides the price style. Defaults to the screen-heading scale.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final i18n = AppI18n.of(context);
    final isFallback = fare.matched != requested;
    final priceStyle = (style ?? AppTextStyles.heading1).copyWith(
      fontFeatures: AppTextStyles.tabularFigures,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            // Keyed on the value so a preference change cross-fades the number
            // instead of swapping it — the price is the one thing on screen
            // that changed, and a hard swap reads as a glitch.
            AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? AppMotion.instant
                  : AppMotion.micro,
              switchInCurve: AppMotion.easeOut,
              switchOutCurve: AppMotion.easeOut,
              child: Text(
                '\$${fare.price}',
                key: ValueKey(fare.price),
                style: priceStyle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              fare.matched.labelOf(i18n),
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (isFallback)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              i18n.fareFallbackNote(
                requested.labelOf(i18n),
                fare.matched.labelOf(i18n),
              ),
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
