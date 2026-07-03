import 'dart:async';
import 'package:flutter/material.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';

class BottomSheetShell extends StatelessWidget {
  const BottomSheetShell({
    required this.child,
    this.initialOffset = const SheetOffset.proportionalToViewport(0.5),
    this.minOffset = const SheetOffset.proportionalToViewport(0.25),
    this.maxOffset = const SheetOffset.proportionalToViewport(1),
    super.key,
  });

  final Widget child;
  final SheetOffset initialOffset;
  final SheetOffset minOffset;
  final SheetOffset maxOffset;

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    SheetOffset initialOffset = const SheetOffset.proportionalToViewport(0.5),
    SheetOffset minOffset = const SheetOffset.proportionalToViewport(0.25),
    SheetOffset maxOffset = const SheetOffset.proportionalToViewport(1),
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
