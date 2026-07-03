import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/firebase/firebase_bootstrap.dart';
import 'package:wheres_the_car/core/firebase/firebase_gate.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/core/storage/hive_store.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';

enum _Appearance {
  system('跟隨系統'),
  light('淺色模式'),
  dark('深色模式');

  const _Appearance(this.label);
  final String label;
}

enum _Language {
  system('跟隨系統'),
  zh('繁體中文'),
  en('English');

  const _Language(this.label);
  final String label;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.updatePushPreference});

  final Future<bool> Function({required bool requested})? updatePushPreference;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _Appearance _appearance = _Appearance.system;
  _Language _language = _Language.system;
  int _versionTaps = 0;
  bool _devMode = false;
  bool _pushUpdating = false;
  late bool _pushEnabled;
  late bool _analyticsEnabled;
  late bool _crashlyticsEnabled;
  late bool _largeText;

  @override
  void initState() {
    super.initState();
    _devMode = HiveStore.devModeEnabled;
    _pushEnabled = HiveStore.pushEnabled;
    _analyticsEnabled = HiveStore.analyticsEnabled;
    _crashlyticsEnabled = HiveStore.crashlyticsEnabled;
    _largeText = HiveStore.largeText;
  }

  Future<void> _setPush(bool value) async {
    if (_pushUpdating) return;
    HiveStore.pushEnabled = value;
    setState(() {
      _pushEnabled = value;
      _pushUpdating = true;
    });
    var enabled = false;
    try {
      enabled =
          await (widget.updatePushPreference ??
              FirebaseBootstrap.updatePushPreference)(requested: value);
    } on Object catch (_) {
      enabled = false;
    } finally {
      HiveStore.pushEnabled = enabled;
      if (mounted) {
        setState(() {
          _pushEnabled = enabled;
          _pushUpdating = false;
        });
      }
    }
  }

  Future<void> _setCollection({
    required bool value,
    required void Function({required bool value}) persist,
    required void Function({required bool value}) update,
    required Future<void> Function({required bool value}) setCollectionEnabled,
  }) async {
    persist(value: value);
    setState(() => update(value: value));
    if (!FirebaseGate.enabled) return;
    try {
      await setCollectionEnabled(value: value);
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
    }
  }

  void _onVersionTap() {
    _versionTaps++;
    if (_versionTaps >= 5 && !_devMode) {
      HiveStore.devModeEnabled = true;
      setState(() => _devMode = true);
      _versionTaps = 0;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('開發者模式已啟用')),
      );
    }
  }

  Future<void> _pickLanguage() async {
    final result = await context.push<String>(
      '/settings/language',
      extra: {
        'options': _Language.values.map((e) => e.label).toList(),
        'selected': _language.label,
      },
    );
    if (result != null && mounted) {
      setState(() {
        _language = _Language.values.firstWhere(
          (e) => e.label == result,
          orElse: () => _language,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: '設定', centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _SettingsSection(
            title: '外觀與語言',
            children: [
              _SettingsSwitchRow(
                icon: Icons.dark_mode_outlined,
                label: '深色模式',
                value: _appearance == _Appearance.dark,
                onChanged: (v) {
                  setState(() {
                    _appearance = v ? _Appearance.dark : _Appearance.light;
                  });
                },
              ),
              _SettingsRow(
                icon: Icons.language_rounded,
                label: '語言',
                value: _language.label,
                hasChevron: 1,
                onTap: _pickLanguage,
              ),
              _SettingsSwitchRow(
                icon: Icons.text_fields_rounded,
                label: '大字體模式',
                value: _largeText,
                onChanged: (v) {
                  HiveStore.largeText = v;
                  setState(() => _largeText = v);
                },
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
                value: _pushEnabled,
                onChanged: _pushUpdating ? null : _setPush,
              ),
              _SettingsSwitchRow(
                icon: Icons.analytics_outlined,
                label: 'Analytics 使用資料',
                value: _analyticsEnabled,
                onChanged: (value) => _setCollection(
                  value: value,
                  persist: ({required value}) =>
                      HiveStore.analyticsEnabled = value,
                  update: ({required value}) => _analyticsEnabled = value,
                  setCollectionEnabled: ({required value}) => FirebaseAnalytics
                      .instance
                      .setAnalyticsCollectionEnabled(value),
                ),
              ),
              _SettingsSwitchRow(
                icon: Icons.bug_report_outlined,
                label: 'Crashlytics 錯誤回報',
                value: _crashlyticsEnabled,
                onChanged: (value) => _setCollection(
                  value: value,
                  persist: ({required value}) =>
                      HiveStore.crashlyticsEnabled = value,
                  update: ({required value}) => _crashlyticsEnabled = value,
                  setCollectionEnabled: ({required value}) =>
                      FirebaseCrashlytics.instance
                          .setCrashlyticsCollectionEnabled(value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: '關於',
            children: [
              _SettingsRow(
                icon: Icons.help_outline_rounded,
                label: '常見問題 FAQ',
                hasChevron: 1,
                onTap: () {},
              ),
              _SettingsRow(
                icon: Icons.bug_report_outlined,
                label: '回報問題',
                hasChevron: 1,
                onTap: () {},
              ),
              _SettingsRow(
                icon: Icons.lock_outline_rounded,
                label: '隱私權政策',
                hasChevron: 1,
                onTap: () {},
              ),
              _SettingsRow(
                icon: Icons.info_outline_rounded,
                label: '目前版本',
                value: '1.0.0',
                onTap: _onVersionTap,
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
          const _SettingsSection(
            title: '資料庫狀態',
            children: [
              _SettingsRow(
                icon: Symbols.database_rounded,
                label: 'TDX 靜態資料',
                value: '今日 06:00',
                valueColor: AppTheme.statusArriving,
                statusIcon: Icons.check_circle_rounded,
              ),
            ],
          ),
          if (_devMode) ...[
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
                    unawaited(context.push('/ui-kit'));
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
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sw = Switch(
      value: value,
      onChanged: onChanged,
      thumbIcon: WidgetStateProperty.resolveWith(
        (states) => Icon(
          states.contains(WidgetState.selected)
              ? Icons.check_rounded
              : Icons.close_rounded,
          size: 16,
        ),
      ),
    );

    return GestureDetector(
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
                  ],
                ),
              ),
              sw,
            ],
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
  });
  final IconData icon;
  final String label;
  final String? value;
  final Color? valueColor;
  final IconData? statusIcon;
  final int hasChevron;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(label, style: AppTextStyles.bodyLarge),
            const Spacer(),
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
            if (hasChevron == 1)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
              )
            else if (hasChevron == 2)
              Icon(
                Symbols.arrow_insert_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
