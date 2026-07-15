import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wheres_the_car/app/router/app_routes.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/accordion_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/alerts_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/availability_gauge_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/avatar_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/badge_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/bottom_sheet_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/breadcrumb_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/buttons_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/cards_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/chat_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/checkbox_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/color_picker_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/colors_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/date_picker_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/divider_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/drawer_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/dropdown_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/edit_bar_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/file_tree_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/filter_chip_group_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/icons_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/input_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/leg_ribbon_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/line_badge_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/menu_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/modal_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/motion_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/pagination_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/progress_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/quantity_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/radio_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/scrollbar_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/segment_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/shadows_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/slider_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/snackbar_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/spacing_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/spinner_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/status_banner_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/stepper_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/switch_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/table_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/tabs_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/time_picker_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/tooltip_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/pages/typography_page.dart';
import 'package:wheres_the_car/features/ui_kit/view/ui_kit_home_screen.dart';

Page<T> _page<T>(Widget child) => MaterialPage<T>(child: child);

/// UI Kit gallery routes, present in the route graph only in debug builds.
///
/// Two guards on purpose: [enabled] is the runtime seam route-graph tests use
/// to assert release semantics, while the [kDebugMode] check is a
/// compile-time constant so release builds tree-shake every gallery page out
/// of the binary regardless of the flag callers pass.
List<RouteBase> debugUiKitRoutes({required bool enabled}) {
  if (!enabled || !kDebugMode) return const [];
  return [
    GoRoute(
      path: AppRoutes.uiKit,
      pageBuilder: (_, _) => _page(const UiKitHomeScreen()),
      routes: [
        GoRoute(
          path: 'typography',
          pageBuilder: (_, _) => _page(const TypographyPage()),
        ),
        GoRoute(
          path: 'colors',
          pageBuilder: (_, _) => _page(const ColorsPage()),
        ),
        GoRoute(
          path: 'icons',
          pageBuilder: (_, _) => _page(const IconsPage()),
        ),
        GoRoute(
          path: 'divider',
          pageBuilder: (_, _) => _page(const DividerPage()),
        ),
        GoRoute(
          path: 'spacing',
          pageBuilder: (_, _) => _page(const SpacingPage()),
        ),
        GoRoute(
          path: 'shadows',
          pageBuilder: (_, _) => _page(const ShadowsPage()),
        ),
        GoRoute(
          path: 'motion',
          pageBuilder: (_, _) => _page(const MotionPage()),
        ),
        GoRoute(
          path: 'input',
          pageBuilder: (_, _) => _page(const InputPage()),
        ),
        GoRoute(
          path: 'dropdown',
          pageBuilder: (_, _) => _page(const DropdownPage()),
        ),
        GoRoute(
          path: 'radio',
          pageBuilder: (_, _) => _page(const RadioPage()),
        ),
        GoRoute(
          path: 'checkbox',
          pageBuilder: (_, _) => _page(const CheckboxPage()),
        ),
        GoRoute(
          path: 'switch',
          pageBuilder: (_, _) => _page(const SwitchPage()),
        ),
        GoRoute(
          path: 'quantity',
          pageBuilder: (_, _) => _page(const QuantityPage()),
        ),
        GoRoute(
          path: 'slider',
          pageBuilder: (_, _) => _page(const SliderPage()),
        ),
        GoRoute(
          path: 'segment',
          pageBuilder: (_, _) => _page(const SegmentPage()),
        ),
        GoRoute(
          path: 'date-picker',
          pageBuilder: (_, _) => _page(const DatePickerPage()),
        ),
        GoRoute(
          path: 'color-picker',
          pageBuilder: (_, _) => _page(const ColorPickerPage()),
        ),
        GoRoute(
          path: 'buttons',
          pageBuilder: (_, _) => _page(const ButtonsPage()),
        ),
        GoRoute(
          path: 'menu',
          pageBuilder: (_, _) => _page(const MenuPage()),
        ),
        GoRoute(
          path: 'edit-bar',
          pageBuilder: (_, _) => _page(const EditBarPage()),
        ),
        GoRoute(
          path: 'alerts',
          pageBuilder: (_, _) => _page(const AlertsPage()),
        ),
        GoRoute(
          path: 'spinner',
          pageBuilder: (_, _) => _page(const SpinnerPage()),
        ),
        GoRoute(
          path: 'progress',
          pageBuilder: (_, _) => _page(const ProgressPage()),
        ),
        GoRoute(
          path: 'tooltip',
          pageBuilder: (_, _) => _page(const TooltipPage()),
        ),
        GoRoute(
          path: 'snackbar',
          pageBuilder: (_, _) => _page(const SnackbarPage()),
        ),
        GoRoute(
          path: 'status-banner',
          pageBuilder: (_, _) => _page(const StatusBannerPage()),
        ),
        GoRoute(
          path: 'badge',
          pageBuilder: (_, _) => _page(const BadgePage()),
        ),
        GoRoute(
          path: 'tabs',
          pageBuilder: (_, _) => _page(const TabsPage()),
        ),
        GoRoute(
          path: 'breadcrumb',
          pageBuilder: (_, _) => _page(const BreadcrumbPage()),
        ),
        GoRoute(
          path: 'pagination',
          pageBuilder: (_, _) => _page(const PaginationPage()),
        ),
        GoRoute(
          path: 'stepper',
          pageBuilder: (_, _) => _page(const StepperPage()),
        ),
        GoRoute(
          path: 'drawer',
          pageBuilder: (_, _) => _page(const DrawerPage()),
        ),
        GoRoute(
          path: 'modal',
          pageBuilder: (_, _) => _page(const ModalPage()),
        ),
        GoRoute(
          path: 'accordion',
          pageBuilder: (_, _) => _page(const AccordionPage()),
        ),
        GoRoute(
          path: 'bottom-sheet',
          pageBuilder: (_, _) => _page(const BottomSheetPage()),
        ),
        GoRoute(
          path: 'cards',
          pageBuilder: (_, _) => _page(const CardsPage()),
        ),
        GoRoute(
          path: 'avatar',
          pageBuilder: (_, _) => _page(const AvatarPage()),
        ),
        GoRoute(
          path: 'table',
          pageBuilder: (_, _) => _page(const TablePage()),
        ),
        GoRoute(
          path: 'file-tree',
          pageBuilder: (_, _) => _page(const FileTreePage()),
        ),
        GoRoute(
          path: 'chat',
          pageBuilder: (_, _) => _page(const ChatPage()),
        ),
        GoRoute(
          path: 'scrollbar',
          pageBuilder: (_, _) => _page(const ScrollbarPage()),
        ),
        GoRoute(
          path: 'availability-gauge',
          pageBuilder: (_, _) => _page(const AvailabilityGaugePage()),
        ),
        GoRoute(
          path: 'line-badge',
          pageBuilder: (_, _) => _page(const LineBadgePage()),
        ),
        GoRoute(
          path: 'filter-chip-group',
          pageBuilder: (_, _) => _page(const FilterChipGroupPage()),
        ),
        GoRoute(
          path: 'leg-ribbon',
          pageBuilder: (_, _) => _page(const LegRibbonPage()),
        ),
        GoRoute(
          path: 'time-picker',
          pageBuilder: (_, _) => _page(const TimePickerPage()),
        ),
      ],
    ),
  ];
}
