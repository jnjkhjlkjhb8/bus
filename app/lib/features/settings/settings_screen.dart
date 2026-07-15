import 'dart:async';

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
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
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
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: _buildBody,
      ),
    );
  }

  Widget _buildBody(BuildContext context, SettingsState state) {
    final bloc = context.read<SettingsBloc>();
    return Scaffold(
      appBar: const DetailAppBar(title: '設定', centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _SettingsSection(
            title: '外觀與語言',
            children: [
              _SettingsRow(
                icon: Icons.dark_mode_outlined,
                label: '外觀',
                value: state.appearance.label,
                hasChevron: 1,
                onTap: () => _pickAppearance(context, state.appearance),
              ),
              // Language selection is memory-only (not wired to
              // MaterialApp's locale), so the picker is disabled rather than
              // offered as a working affordance (F48).
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
          const SizedBox(height: 16),
          _SettingsSection(
            title: '導航',
            children: [
              _SettingsSwitchRow(
                icon: Icons.dashboard_customize_outlined,
                label: '即時動態',
                subtitle: '鎖定畫面、動態島與狀態列顯示即時資訊',
                value: state.liveActivityEnabled,
                onChanged: (v) => bloc.add(LiveActivityToggled(value: v)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: '隱私與資料',
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
                onChanged: (value) => bloc.add(AnalyticsToggled(value: value)),
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
          const SizedBox(height: 16),
          _SettingsSection(
            title: '關於',
            children: [
              // These destinations don't exist yet; a live chevron with an
              // empty handler would be a dead affordance (F45), so each row
              // is disabled with a static "即將推出" marker instead.
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
          const SizedBox(height: 16),
          _SettingsSection(
            title: '資料庫狀態',
            children: [
              _SettingsRow(
                icon: Symbols.database_rounded,
                label: 'TDX 靜態資料',
                value: formatSyncFreshness(state.powerSyncLastSyncedAt),
                valueColor: state.powerSyncLastSyncedAt == null
                    ? null
                    : AppTheme.statusArriving,
                statusIcon: state.powerSyncLastSyncedAt == null
                    ? null
                    : Icons.check_circle_rounded,
              ),
            ],
          ),
          // UI Kit routes exist only in debug builds, so the unlock
          // affordance is compiled out of release builds with them.
          if (kDebugMode && state.devMode) ...[
            const SizedBox(height: 16),
            _SettingsSection(
              title: '開發者',
              children: [
                _SettingsRow(
                  icon: Icons.palette_outlined,
                  label: 'UI Kit',
                  hasChevron: 1,
                  onTap: () {
                    unawaited(HapticService.instance.lightTap());
                    unawaited(context.push(AppRoutes.uiKit));
                  },
                ),
              ],
            ),
          ],
        ],
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
    this.subtitle,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sw = AppSwitch(value: value, onChanged: onChanged);

    // MergeSemantics collapses the label Text and the Switch's own
    // toggled-state node into a single semantics node, so a screen reader
    // announces "label, on/off" once instead of two separate stops (F52).
    return MergeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged != null ? () => onChanged!(!value) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: AppTextStyles.bodyLarge),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Subtitle-less rows keep the base layout (switch flush to
                // the label column); only the taller subtitle rows get the
                // gap.
                if (subtitle != null) const SizedBox(width: 12),
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
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
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
            color: cs.surface,
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
                    indent: 16,
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
    this.hasChevron = 0,
    this.onTap,
    this.comingSoon = false,
  });
  final IconData icon;
  final String label;
  final String? value;
  final Color? valueColor;
  final IconData? statusIcon;
  final int hasChevron;
  final VoidCallback? onTap;

  /// Renders a static, disabled "即將推出" marker instead of the usual
  /// value/chevron and drops the tap handler, for a destination that
  /// doesn't exist yet (F45, F48). Never pulses — the design system reserves
  /// motion for live state, not placeholders.
  final bool comingSoon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Min-height, not fixed: a wrapped label under a large text scale grows
    // the row instead of being clipped (F53).
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Pressable(
        onTap: comingSoon ? null : onTap,
        semanticLabel: comingSoon ? '$label，即將推出' : label,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
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
                  const SizedBox(width: 4),
                ],
                if (value != null)
                  Text(
                    value!,
                    textAlign: TextAlign.right,
                    style: AppTextStyles.heading2.copyWith(
                      color: valueColor ?? cs.onSurface,
                    ),
                  ),
              ],
              if (!comingSoon && hasChevron == 1)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                )
              else if (!comingSoon && hasChevron == 2)
                Icon(
                  Symbols.arrow_insert_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
