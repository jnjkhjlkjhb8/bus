import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';

class StaggerItem extends StatefulWidget {
  const StaggerItem({
    required this.index,
    required this.child,
    this.maxStep = 8,
    super.key,
  });

  final int index;
  final Widget child;
  final int maxStep;

  @override
  State<StaggerItem> createState() => _StaggerItemState();
}

class _StaggerItemState extends State<StaggerItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: AppMotion.short);
    _opacity = CurvedAnimation(parent: _ctrl, curve: AppMotion.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: AppMotion.easeOut));
    final step = widget.index < widget.maxStep ? widget.index : widget.maxStep;
    unawaited(
      Future.delayed(Duration(milliseconds: step * 50), () {
        if (mounted) unawaited(_ctrl.forward());
      }),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
