import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wheres_the_bus/features/alerts/view/notice_rail_host.dart';
import 'package:wheres_the_bus/features/feedback/view/shake_report_host.dart';
import 'package:wheres_the_bus/shared/widgets/nav_mini_bar.dart';

/// Shell around the app's single StatefulShellRoute branch: routed content
/// fills the window, with system banners overlaid at the top and the floating
/// [NavMiniBar] at the bottom.
///
/// Banners paint over the shell rather than occupying layout space, so a
/// full-bleed map branch stays edge-to-edge when one appears. To keep that
/// from swallowing the controls of the branches that aren't full-bleed, the
/// measured banner height is republished to the shell as `MediaQuery.padding
/// .top` and `viewPadding.top`. A screen that already insets by the status bar
/// (search, rail,
/// settings) clears the banner for free; one that deliberately ignores
/// padding (the map) still bleeds to the top edge.
class MainScaffold extends StatefulWidget {
  const MainScaffold({required this.shell, super.key});

  /// The active branch navigator. Typed [Widget] (the router passes a
  /// `StatefulNavigationShell`) so tests can render the scaffold around any
  /// content.
  final Widget shell;

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  /// Height of the banner stack, republished as a top inset. Measured after
  /// layout rather than derived, because the strip's height depends on text
  /// scale and on how many lines the message wraps to.
  final _bannerHeight = ValueNotifier<double>(0);

  @override
  void dispose() {
    _bannerHeight.dispose();
    super.dispose();
  }

  /// Wrapped here rather than in `app.dart`: every route in the app is a
  /// branch of the one shell this scaffold builds, and this is the outermost
  /// place that still sits *under* the router — so the listener can read the
  /// current route and push the report form on the same navigator.
  @override
  Widget build(BuildContext context) =>
      ShakeReportHost(child: _buildScaffold(context));

  Widget _buildScaffold(BuildContext context) => Scaffold(
    // The shell holds every branch page at once, so resizing it for the
    // keyboard shrinks the pages behind the one being typed on — the home map
    // relayouts and slides as the keyboard animates. Pages that need keyboard
    // avoidance (search) have their own Scaffold and do it there.
    resizeToAvoidBottomInset: false,
    body: Stack(
      children: [
        Positioned.fill(
          child: ValueListenableBuilder<double>(
            valueListenable: _bannerHeight,
            builder: (context, height, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(
                    top: math.max(media.padding.top, height),
                  ),
                  // viewPadding too: the sheet's own MediaQuery derives its
                  // padding from viewPadding rather than inheriting it, so a
                  // padding-only override is dropped at the sheet boundary and
                  // the page pads by the bare status bar.
                  viewPadding: media.viewPadding.copyWith(
                    top: math.max(media.viewPadding.top, height),
                  ),
                ),
                child: child!,
              );
            },
            child: widget.shell,
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: _MeasuredHeight(
            onChanged: (height) => _bannerHeight.value = height,
            child: const NoticeRailHost(),
          ),
        ),
        const Align(alignment: Alignment.bottomCenter, child: NavMiniBar()),
      ],
    ),
  );
}

/// Reports its child's rendered height after every layout pass.
///
/// The banners grow and collapse through `AnimatedSize`, so the height is a
/// moving target for the duration of the transition; reporting per frame lets
/// the inset track it instead of snapping once at the end.
class _MeasuredHeight extends StatefulWidget {
  const _MeasuredHeight({required this.child, required this.onChanged});

  final Widget child;
  final ValueChanged<double> onChanged;

  @override
  State<_MeasuredHeight> createState() => _MeasuredHeightState();
}

class _MeasuredHeightState extends State<_MeasuredHeight> {
  final GlobalKey _key = GlobalKey();
  double _last = 0;

  /// Measured off a layout notification rather than a rebuild: the banners
  /// resize from their own bloc state, which never rebuilds this widget, so
  /// keying off `build` alone would miss every appearance.
  void _report() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final height = _key.currentContext?.size?.height ?? 0;
      if (height == _last) return;
      _last = height;
      widget.onChanged(height);
    });
  }

  @override
  Widget build(BuildContext context) {
    _report();
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _report();
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: KeyedSubtree(key: _key, child: widget.child),
      ),
    );
  }
}
