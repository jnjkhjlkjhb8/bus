import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wheres_the_car/app/router/app_routes.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/firebase/firebase_gate.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/data/repositories/settings_repository.dart';
import 'package:wheres_the_car/features/settings/bloc/settings_bloc.dart';
import 'package:wheres_the_car/features/settings/bloc/settings_event.dart';
import 'package:wheres_the_car/features/settings/bloc/settings_state.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_snackbar.dart';
import 'package:wheres_the_car/shared/widgets/app_switch.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    this.updatePushPreference,
    this.settings,
    this.packageInfoLoader,
    this.lastSyncedAtOf,
  });

  final PushUpdater? updatePushPreference;

  /// Injectable for tests; defaults to the shared repository instance.
  final SettingsRepository? settings;

  /// Injectable for tests; forwarded to [SettingsBloc].
  final Future<PackageInfo> Function()? packageInfoLoader;

  /// Injectable for tests; forwarded to [SettingsBloc].
  final DateTime? Function()? lastSyncedAtOf;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SettingsBloc(
        settings: settings,
        updatePushPreference: updatePushPreference,
        packageInfoLoader: packageInfoLoader,
        lastSyncedAtOf: lastSyncedAtOf,
      ),
      child: const _SettingsView(),
    );
  }
}

/// Formats [dt] for the "資料庫狀態" freshness row: same-day syncs read
/// "今日 HH:mm"; anything older reads "MM/dd HH:mm" so a stale sync is
/// visibly stale rather than silently rendered like a fresh one.
String formatSyncFreshness(DateTime? dt) {
  if (dt == null) return '尚未同步';
  final local = dt.toLocal();
  final now = DateTime.now();
  final isToday =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  final time = DateFormat('HH:mm').format(local);
  return isToday ? '今日 $time' : '${DateFormat('MM/dd').format(local)} $time';
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  Future<void> _pickAppearance(
    BuildContext context,
    Appearance current,
  ) async {
    final result = await context.push<String>(
      AppRoutes.settingsAppearance,
      extra: {
        'options': Appearance.values.map((e) => e.label).toList(),
        'selected': current.label,
      },
    );
    if (result != null && context.mounted) {
      final picked = Appearance.values.firstWhere(
        (e) => e.label == result,
        orElse: () => current,
      );
      context.read<SettingsBloc>().add(AppearanceSelected(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsBloc, SettingsState>(
      // Announce dev mode only on the false -> true unlock transition.
      listenWhen: (prev, curr) => !prev.devMode && curr.devMode,
      listener: (context, state) => AppSnackbar.show(context, '開發者模式已啟用'),
      child: BlocBuilder<SettingsBloc, SettingsState>(builder: _buildBody),
    );
  }

  Widget _buildBody(BuildContext context, SettingsState state) {
    final bloc = context.read<SettingsBloc>();
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _LargeTitleHeader(
              title: '設定',
              topPadding: topPadding,
              reduceMotion: reduceMotion,
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 32),
            sliver: SliverList.list(
              children: [
                _SettingsSection(
                  title: '外觀與語言',
                  children: [
                    _SettingsRow(
                      icon: Icons.dark_mode_outlined,
                      label: '外觀',
                      value: state.appearance.label,
                      chevron: true,
                      onTap: () => _pickAppearance(context, state.appearance),
                    ),
                    // Language selection is memory-only (not wired to
                    // MaterialApp's locale), so the picker is disabled rather
                    // than offered as a working affordance (F48).
                    const _SettingsRow(
                      icon: Icons.language_rounded,
                      label: '語言',
                      comingSoon: true,
                    ),
                    _SettingsSwitchRow(
                      icon: Icons.text_fields_rounded,
                      label: '大字體模式',
                      value: state.largeText,
                      onChanged: (v) => bloc.add(LargeTextToggled(value: v)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SettingsSection(
                  title: '導航',
                  // Row-level explanation moved to a group footer (HIG
                  // footnote): the switch row stays a single scannable line.
                  footer: '在鎖定畫面、動態島與狀態列顯示班次即時資訊。',
                  children: [
                    _SettingsSwitchRow(
                      icon: Icons.dashboard_customize_outlined,
                      label: '即時動態',
                      value: state.liveActivityEnabled,
                      onChanged: (v) => bloc.add(LiveActivityToggled(value: v)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SettingsSection(
                  title: '隱私與資料',
                  footer: '匿名的使用與當機資料協助我們改善 App，不含個人身分資訊，可隨時關閉。',
                  children: [
                    _SettingsSwitchRow(
                      icon: Icons.notifications_none_rounded,
                      label: '推播通知',
                      value: state.pushEnabled,
                      onChanged: state.pushUpdating
                          ? null
                          : (v) => bloc.add(PushToggled(value: v)),
                    ),
                    _SettingsSwitchRow(
                      icon: Icons.analytics_outlined,
                      label: 'Analytics 使用資料',
                      value: state.analyticsEnabled,
                      onChanged: (value) =>
                          bloc.add(AnalyticsToggled(value: value)),
                    ),
                    _SettingsSwitchRow(
                      icon: Icons.bug_report_outlined,
                      label: 'Crashlytics 錯誤回報',
                      value: state.crashlyticsEnabled,
                      onChanged: (value) =>
                          bloc.add(CrashlyticsToggled(value: value)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SettingsSection(
                  title: '關於',
                  children: [
                    // These destinations don't exist yet; a live chevron with
                    // an empty handler would be a dead affordance (F45), so
                    // each row is disabled with a static "即將推出" marker.
                    const _SettingsRow(
                      icon: Icons.help_outline_rounded,
                      label: '常見問題 FAQ',
                      comingSoon: true,
                    ),
                    const _SettingsRow(
                      icon: Icons.bug_report_outlined,
                      label: '回報問題',
                      comingSoon: true,
                    ),
                    const _SettingsRow(
                      icon: Icons.lock_outline_rounded,
                      label: '隱私權政策',
                      comingSoon: true,
                    ),
                    _SettingsRow(
                      icon: Icons.info_outline_rounded,
                      label: '目前版本',
                      value: state.appVersion.isEmpty ? '—' : state.appVersion,
                      monoValue: true,
                      onTap: () => bloc.add(const VersionTapped()),
                    ),
                    if (FirebaseGate.appEnv != 'prod' &&
                        FirebaseGate.appEnv != 'production')
                      const _SettingsRow(
                        icon: Icons.developer_mode_rounded,
                        label: '環境',
                        value: FirebaseGate.appEnv,
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                _SettingsSection(
                  title: '資料庫狀態',
                  footer: '離線搜尋所用的靜態班表。每日凌晨自動同步。',
                  children: [
                    _SettingsRow(
                      icon: Symbols.database_rounded,
                      label: 'TDX 靜態資料',
                      value: formatSyncFreshness(state.powerSyncLastSyncedAt),
                      monoValue: true,
                      valueColor: state.powerSyncLastSyncedAt == null
                          ? null
                          : AppTheme.statusArrivingText,
                      statusIcon: state.powerSyncLastSyncedAt == null
                          ? null
                          : Icons.check_circle_rounded,
                    ),
                  ],
                ),
                // UI Kit routes exist only in debug builds, so the unlock
                // affordance is compiled out of release builds with them.
                if (kDebugMode && state.devMode) ...[
                  const SizedBox(height: 24),
                  _SettingsSection(
                    title: '開發者',
                    children: [
                      _SettingsRow(
                        icon: Icons.palette_outlined,
                        label: 'UI Kit',
                        chevron: true,
                        onTap: () {
                          unawaited(HapticService.instance.lightTap());
                          unawaited(context.push(AppRoutes.uiKit));
                        },
                      ),
                    ],
                  ),
                ],
                _AppIdentityFooter(version: state.appVersion),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinned header with an iOS-style large title that collapses into a
/// translucent, blurred toolbar as the list scrolls under it. Collapse is
/// scroll-linked (direct manipulation), so it needs no [AnimationController];
/// [AppMotion] curves shape the fade of each layer against scroll progress,
/// and [reduceMotion] drops the non-essential vertical drift.
class _LargeTitleHeader extends SliverPersistentHeaderDelegate {
  const _LargeTitleHeader({
    required this.title,
    required this.topPadding,
    required this.reduceMotion,
  });

  final String title;
  final double topPadding;
  final bool reduceMotion;

  static const double _bar = 44;
  static const double _largeBlock = 52;

  @override
  double get minExtent => topPadding + _bar;

  @override
  double get maxExtent => topPadding + _bar + _largeBlock;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final cs = Theme.of(context).colorScheme;
    final t = (shrinkOffset / _largeBlock).clamp(0.0, 1.0);

    // Each layer fades on its own eased curve so the crossfade reads as one
    // material collapsing, not two opacities racing.
    final chrome = AppMotion.easeOut.transform(t);
    final compact = AppMotion.easeInOut.transform(
      ((t - 0.35) / 0.65).clamp(0.0, 1.0),
    );
    final large =
        1.0 - AppMotion.easeInOut.transform((t / 0.7).clamp(0.0, 1.0));

    return SizedBox.expand(
      child: Stack(
        children: [
          // Translucent bar: invisible at rest, blurs the content scrolling
          // beneath and drops a hairline once collapse begins.
          if (chrome > 0.001)
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 18 * chrome,
                    sigmaY: 18 * chrome,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.surface.withValues(alpha: 0.72 * chrome),
                      border: Border(
                        bottom: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: chrome),
                          width: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Back affordance — pinned top-left across the whole collapse.
          Positioned(
            top: topPadding,
            left: 4,
            child: const _BackButton(),
          ),
          // Collapsed centred title.
          Positioned(
            top: topPadding,
            left: 44,
            right: 44,
            height: _bar,
            child: Center(
              child: Opacity(
                opacity: compact,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
            ),
          ),
          // Resting large title, anchored to the header's bottom edge.
          Positioned(
            left: 20,
            right: 20,
            bottom: 10,
            child: Opacity(
              opacity: large,
              child: Transform.translate(
                offset: Offset(0, reduceMotion ? 0 : t * -6),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.displayLarge,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_LargeTitleHeader old) =>
      old.title != title ||
      old.topPadding != topPadding ||
      old.reduceMotion != reduceMotion;
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: () => Navigator.of(context, rootNavigator: true).maybePop(),
      semanticLabel: '返回',
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 20,
          color: cs.onSurface,
        ),
      ),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sw = AppSwitch(value: value, onChanged: onChanged);

    // MergeSemantics collapses the label Text and the Switch's own
    // toggled-state node into a single semantics node, so a screen reader
    // announces "label, on/off" once instead of two separate stops (F52).
    return MergeSemantics(
      child: Pressable(
        onTap: onChanged != null ? () => onChanged!(!value) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: cs.onSurfaceVariant),
                  const SizedBox(width: 12),
                ],
                Expanded(child: Text(label, style: AppTextStyles.bodyLarge)),
                const SizedBox(width: 12),
                sw,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
    this.footer,
  });

  final String title;
  final List<Widget> children;

  /// Optional HIG-style footnote rendered under the group. Carries the "why"
  /// for a group of toggles so individual rows stay one scannable line.
  final String? footer;

  // Separators start at the label column (past the 20px icon + 12px gap),
  // the iOS inset-grouped signature; a full-bleed divider reads as a table.
  static const double _dividerIndent = 48;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
          child: Text(
            title,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            // surfaceContainerLow (card), not surface: an elevated group must
            // never paint the scaffold colour or it vanishes in dark mode.
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 0.5,
                    thickness: 0.5,
                    indent: _dividerIndent,
                    color: cs.outlineVariant,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: children[i],
                ),
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 7, 6, 0),
            child: Text(
              footer!,
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    this.value,
    this.valueColor,
    this.statusIcon,
    this.chevron = false,
    this.monoValue = false,
    this.onTap,
    this.comingSoon = false,
  });
  final IconData icon;
  final String label;
  final String? value;
  final Color? valueColor;
  final IconData? statusIcon;
  final bool chevron;

  /// Renders the trailing value in IBM Plex Mono (tabular): versions and sync
  /// timestamps, where digits should not shift width between states.
  final bool monoValue;
  final VoidCallback? onTap;

  /// Renders a static, disabled "即將推出" marker instead of the usual
  /// value/chevron and drops the tap handler, for a destination that
  /// doesn't exist yet (F45, F48). Never pulses — the design system reserves
  /// motion for live state, not placeholders.
  final bool comingSoon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Trailing detail is secondary, at label size — the label leads, the
    // value supports (HIG). Mono values keep tabular figures.
    final baseValue = monoValue ? AppTextStyles.memo : AppTextStyles.bodyLarge;
    final valueStyle = baseValue.copyWith(
      color: valueColor ?? cs.onSurfaceVariant,
    );

    // Min-height, not fixed: a wrapped label under a large text scale grows
    // the row instead of being clipped (F53).
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Pressable(
        onTap: comingSoon ? null : onTap,
        semanticLabel: comingSoon ? '$label，即將推出' : label,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: AppTextStyles.bodyLarge)),
              if (comingSoon)
                Text(
                  '即將推出',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                )
              else ...[
                if (statusIcon != null) ...[
                  Icon(statusIcon, size: 18, color: valueColor),
                  const SizedBox(width: 6),
                ],
                if (value != null)
                  Text(value!, textAlign: TextAlign.right, style: valueStyle),
                if (chevron) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: cs.outline,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Closes the list with the app's own name and version, so "關於" isn't the
/// only place the app identifies itself.
class _AppIdentityFooter extends StatelessWidget {
  const _AppIdentityFooter({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 8),
      child: Column(
        children: [
          Text(
            '我車呢',
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (version.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              version,
              style: AppTextStyles.memo.copyWith(color: cs.outline),
            ),
          ],
        ],
      ),
    );
  }
}
