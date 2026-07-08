import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';

class UiKitHomeScreen extends StatefulWidget {
  const UiKitHomeScreen({super.key});

  @override
  State<UiKitHomeScreen> createState() => _UiKitHomeScreenState();
}

class _UiKitHomeScreenState extends State<UiKitHomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    unawaited(_ctrl.forward());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'UI Kit'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          children: [
            const _SectionHeader('Foundations'),
            ..._foundations.asMap().entries.map(
              (e) => _AnimatedRow(
                index: e.key,
                controller: _ctrl,
                item: e.value,
              ),
            ),
            const _SectionHeader('Form'),
            ..._form.asMap().entries.map(
              (e) => _AnimatedRow(
                index: _foundations.length + e.key,
                controller: _ctrl,
                item: e.value,
              ),
            ),
            const _SectionHeader('Action'),
            ..._action.asMap().entries.map(
              (e) => _AnimatedRow(
                index: _foundations.length + _form.length + e.key,
                controller: _ctrl,
                item: e.value,
              ),
            ),
            const _SectionHeader('Feedback'),
            ..._feedback.asMap().entries.map(
              (e) => _AnimatedRow(
                index:
                    _foundations.length + _form.length + _action.length + e.key,
                controller: _ctrl,
                item: e.value,
              ),
            ),
            const _SectionHeader('Navigation'),
            ..._navigation.asMap().entries.map(
              (e) => _AnimatedRow(
                index:
                    _foundations.length +
                    _form.length +
                    _action.length +
                    _feedback.length +
                    e.key,
                controller: _ctrl,
                item: e.value,
              ),
            ),
            const _SectionHeader('Overlay'),
            ..._overlay.asMap().entries.map(
              (e) => _AnimatedRow(
                index:
                    _foundations.length +
                    _form.length +
                    _action.length +
                    _feedback.length +
                    _navigation.length +
                    e.key,
                controller: _ctrl,
                item: e.value,
              ),
            ),
            const _SectionHeader('Display'),
            ..._display.asMap().entries.map(
              (e) => _AnimatedRow(
                index:
                    _foundations.length +
                    _form.length +
                    _action.length +
                    _feedback.length +
                    _navigation.length +
                    _overlay.length +
                    e.key,
                controller: _ctrl,
                item: e.value,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        title,
        style: AppTextStyles.bodySmall.copyWith(
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AnimatedRow extends StatelessWidget {
  const _AnimatedRow({
    required this.index,
    required this.controller,
    required this.item,
  });

  final int index;
  final AnimationController controller;
  final _UiKitItem item;

  @override
  Widget build(BuildContext context) {
    final delay = (index * 40).clamp(0, 400);
    final start = delay / (400 + AppMotion.short.inMilliseconds);
    final end =
        start +
        AppMotion.short.inMilliseconds / (400 + AppMotion.short.inMilliseconds);
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end.clamp(0.0, 1.0), curve: AppMotion.easeOut),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: animation.drive(
          Tween(begin: const Offset(0, 0.15), end: Offset.zero),
        ),
        child: ListTile(
          leading: Icon(item.icon, size: 22),
          title: Text(item.label, style: AppTextStyles.bodyRegular),
          trailing: const Icon(Icons.chevron_right_rounded, size: 20),
          onTap: () => context.push(item.route),
          minVerticalPadding: 10,
        ),
      ),
    );
  }
}

class _UiKitItem {
  const _UiKitItem(this.label, this.icon, this.route);
  final String label;
  final IconData icon;
  final String route;
}

const _foundations = [
  _UiKitItem('Typography', Icons.text_fields_rounded, '/ui-kit/typography'),
  _UiKitItem('Colors', Icons.palette_rounded, '/ui-kit/colors'),
  _UiKitItem('Icons', Icons.star_rounded, '/ui-kit/icons'),
  _UiKitItem('Divider', Icons.horizontal_rule_rounded, '/ui-kit/divider'),
  _UiKitItem('Spacing & Radii', Icons.straighten_rounded, '/ui-kit/spacing'),
  _UiKitItem('Shadows', Icons.layers_rounded, '/ui-kit/shadows'),
  _UiKitItem('Motion', Icons.animation_rounded, '/ui-kit/motion'),
];

const _form = [
  _UiKitItem('Input', Icons.input_rounded, '/ui-kit/input'),
  _UiKitItem(
    'Dropdown',
    Icons.arrow_drop_down_circle_rounded,
    '/ui-kit/dropdown',
  ),
  _UiKitItem('Radio', Icons.radio_button_checked_rounded, '/ui-kit/radio'),
  _UiKitItem('Checkbox', Icons.check_box_rounded, '/ui-kit/checkbox'),
  _UiKitItem('Switch', Icons.toggle_on_rounded, '/ui-kit/switch'),
  _UiKitItem('Quantity Selector', Icons.exposure_rounded, '/ui-kit/quantity'),
  _UiKitItem('Slider', Icons.tune_rounded, '/ui-kit/slider'),
  _UiKitItem('Segment', Icons.view_week_rounded, '/ui-kit/segment'),
  _UiKitItem(
    'Date Picker',
    Icons.calendar_today_rounded,
    '/ui-kit/date-picker',
  ),
  _UiKitItem('Color Picker', Icons.colorize_rounded, '/ui-kit/color-picker'),
];

const _action = [
  _UiKitItem('Buttons', Icons.smart_button_rounded, '/ui-kit/buttons'),
  _UiKitItem('Menu', Icons.more_horiz_rounded, '/ui-kit/menu'),
  _UiKitItem('Edit Bar', Icons.format_bold_rounded, '/ui-kit/edit-bar'),
];

const _feedback = [
  _UiKitItem('Alerts', Icons.warning_amber_rounded, '/ui-kit/alerts'),
  _UiKitItem('Spinner', Icons.refresh_rounded, '/ui-kit/spinner'),
  _UiKitItem('Progress Bar', Icons.linear_scale_rounded, '/ui-kit/progress'),
  _UiKitItem('Tooltip', Icons.info_rounded, '/ui-kit/tooltip'),
  _UiKitItem('Snackbar', Icons.chat_bubble_outline_rounded, '/ui-kit/snackbar'),
  _UiKitItem('Badge', Icons.badge_rounded, '/ui-kit/badge'),
];

const _navigation = [
  _UiKitItem('Tabs', Icons.tab_rounded, '/ui-kit/tabs'),
  _UiKitItem('Breadcrumb', Icons.account_tree_rounded, '/ui-kit/breadcrumb'),
  _UiKitItem('Pagination', Icons.first_page_rounded, '/ui-kit/pagination'),
  _UiKitItem('Stepper', Icons.linear_scale_rounded, '/ui-kit/stepper'),
  _UiKitItem('Drawer', Icons.menu_rounded, '/ui-kit/drawer'),
];

const _overlay = [
  _UiKitItem('Modal', Icons.open_in_new_rounded, '/ui-kit/modal'),
  _UiKitItem('Accordion', Icons.expand_more_rounded, '/ui-kit/accordion'),
  _UiKitItem(
    'Bottom Sheet',
    Icons.vertical_align_bottom_rounded,
    '/ui-kit/bottom-sheet',
  ),
];

const _display = [
  _UiKitItem('Cards', Icons.credit_card_rounded, '/ui-kit/cards'),
  _UiKitItem('Avatar', Icons.account_circle_rounded, '/ui-kit/avatar'),
  _UiKitItem('Table', Icons.table_chart_rounded, '/ui-kit/table'),
  _UiKitItem('File Tree', Icons.account_tree_rounded, '/ui-kit/file-tree'),
  _UiKitItem('Chat', Icons.chat_bubble_rounded, '/ui-kit/chat'),
  _UiKitItem('Scrollbar', Icons.more_vert_rounded, '/ui-kit/scrollbar'),
  _UiKitItem(
    'Availability Gauge',
    Icons.pedal_bike_rounded,
    '/ui-kit/availability-gauge',
  ),
  _UiKitItem('Line Badge', Icons.label_rounded, '/ui-kit/line-badge'),
  _UiKitItem(
    'Filter Chip Group',
    Icons.filter_alt_rounded,
    '/ui-kit/filter-chip-group',
  ),
  _UiKitItem('Leg Ribbon', Icons.route_rounded, '/ui-kit/leg-ribbon'),
  _UiKitItem('Time Picker', Icons.schedule_rounded, '/ui-kit/time-picker'),
];
