import 'dart:async';
import 'package:flutter/material.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';

/// The single source of truth for bottom-sheet snap heights.
///
/// Every draggable sheet in the app snaps to these three detents so switching
/// between pages never lands the sheet at an unfamiliar height. Pages pick
/// which detent they *open* at (`peek`/`half`/`tall`) from this same set; the
/// physical stops are always identical, which is what removes the jump.
abstract final class AppSheetSnap {
  /// Viewport fractions backing each detent — also the clamp bounds a page
  /// hands to [carriedSheetOffset].
  static const peekFrac = 0.25;
  static const halfFrac = 0.5;
  static const tallFrac = 0.85;
  static const fullFrac = 1.0;

  /// Map/list glancing height — the resting detent for map-front pages.
  static const peek = SheetOffset.proportionalToViewport(peekFrac);

  /// The default open height for content-led pages.
  static const half = SheetOffset.proportionalToViewport(halfFrac);

  /// Tall-but-not-full: forms and detail views that open large, and metro's
  /// capped max (keeps the line map peeking above the sheet).
  static const tall = SheetOffset.proportionalToViewport(tallFrac);

  /// Full-height read.
  static const full = SheetOffset.proportionalToViewport(fullFrac);

  /// The standard three-detent grid used by most pages.
  static const grid = SheetSnapGrid(snaps: [peek, half, full]);
}

/// The viewport fraction a sibling sheet should open at to continue where a
/// live sheet currently sits, clamped into [min]..[max]; [fallback] when the
/// sheet has no metrics yet (first build). Pure so it is unit-testable.
///
/// This is scoped per page: a page reads its own sheet's height when opening
/// a sibling sheet, so heights stay continuous *within* a page while different
/// pages remain independent.
double carriedFraction({
  required double offset,
  required double viewportHeight,
  required double min,
  required double max,
  required double fallback,
}) {
  if (viewportHeight <= 0) return fallback.clamp(min, max);
  return (offset / viewportHeight).clamp(min, max);
}

/// [carriedFraction] read from a live [controller], as a [SheetOffset] ready
/// to hand to a sibling sheet's `initialOffset`.
SheetOffset carriedSheetOffset(
  SheetController? controller, {
  required double min,
  required double max,
  required double fallback,
}) {
  final metrics = controller?.metrics;
  return SheetOffset.proportionalToViewport(
    carriedFraction(
      offset: metrics?.offset ?? 0,
      viewportHeight: metrics?.viewportSize.height ?? 0,
      min: min,
      max: max,
      fallback: fallback,
    ),
  );
}

class BottomSheetShell extends StatelessWidget {
  const BottomSheetShell({
    required this.child,
    this.initialOffset = AppSheetSnap.half,
    this.minOffset = AppSheetSnap.peek,
    this.maxOffset = AppSheetSnap.full,
    super.key,
  });

  final Widget child;
  final SheetOffset initialOffset;
  final SheetOffset minOffset;
  final SheetOffset maxOffset;

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    SheetOffset initialOffset = AppSheetSnap.half,
    SheetOffset minOffset = AppSheetSnap.peek,
    SheetOffset maxOffset = AppSheetSnap.full,
  }) {
    return Navigator.of(context).push(
      ModalSheetRoute<T>(
        swipeDismissible: true,
        builder: (_) => BottomSheetShell(
          initialOffset: initialOffset,
          minOffset: minOffset,
          maxOffset: maxOffset,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Sheet(
      initialOffset: initialOffset,
      snapGrid: SheetSnapGrid(
        snaps: [minOffset, initialOffset, maxOffset],
      ),
      scrollConfiguration: const SheetScrollConfiguration(),
      decoration: MaterialSheetDecoration(
        size: SheetSize.stretch,
        color: cs.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusBottomSheet),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetDragHandle(),
          child,
        ],
      ),
    );
  }
}

class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: '拖曳調整',
      child: SizedBox(
        width: double.infinity,
        height: 28,
        child: Center(
          child: Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outline,
              borderRadius: BorderRadius.circular(100),
            ),
          ),
        ),
      ),
    );
  }
}

class SheetExitGestureDetector extends StatefulWidget {
  const SheetExitGestureDetector({
    required this.child,
    required this.onExit,
    super.key,
  });

  final Widget child;
  final VoidCallback onExit;

  @override
  State<SheetExitGestureDetector> createState() =>
      _SheetExitGestureDetectorState();
}

class _SheetExitGestureDetectorState extends State<SheetExitGestureDetector> {
  Timer? _exitTimer;
  bool _isHoldingOverflow = false;

  void _startTimer() {
    if (_exitTimer != null) return;
    _isHoldingOverflow = true;
    _exitTimer = Timer(const Duration(milliseconds: 300), () {
      if (_isHoldingOverflow && mounted) {
        widget.onExit();
      }
      _cleanup();
    });
  }

  void _cleanup() {
    _exitTimer?.cancel();
    _exitTimer = null;
    _isHoldingOverflow = false;
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SheetNotification>(
      onNotification: (notification) {
        if (notification is SheetOverflowNotification) {
          final metrics = notification.metrics;
          // Check if we are at maximum offset (fully expanded sheet)
          final isAtMax = (metrics.offset - metrics.maxOffset).abs() < 1.0;

          if (isAtMax && notification.overflow > 0) {
            _startTimer();
          } else {
            _cleanup();
          }
        } else if (notification is SheetDragEndNotification) {
          _cleanup();
        }
        return false;
      },
      child: widget.child,
    );
  }
}
