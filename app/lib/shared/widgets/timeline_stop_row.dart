import 'package:flutter/material.dart';

class TimelineStopRow extends StatelessWidget {
  const TimelineStopRow({
    required this.name,
    required this.segmentHeight,
    required this.isFirst,
    required this.isLast,
    this.topColor,
    this.bottomColor,
    this.right,
    this.vehicleProgress,
    this.vehiclePlate,
    this.nameStyle,
    super.key,
  });

  final String name;
  final double segmentHeight;
  final bool isFirst;
  final bool isLast;
  final Color? topColor;
  final Color? bottomColor;
  final Widget? right;
  final double? vehicleProgress;
  final String? vehiclePlate;
  final TextStyle? nameStyle;

  static const _dotR = 7.0;

  double _barY() {
    final dotY = segmentHeight / 2;
    return dotY + _dotR + (segmentHeight - dotY - _dotR) * vehicleProgress!;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasVehicle = vehicleProgress != null && vehiclePlate != null;

    final pill = SizedBox(
      width: 20,
      height: segmentHeight,
      child: CustomPaint(
        painter: PillPainter(
          topColor: topColor ?? cs.outlineVariant,
          bottomColor: bottomColor ?? cs.outlineVariant,
          isFirst: isFirst,
          isLast: isLast,
        ),
      ),
    );

    final row = SizedBox(
      height: segmentHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 166,
            child: Row(
              spacing: 16,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style:
                        nameStyle ?? const TextStyle(fontSize: 14, height: 1.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                pill,
              ],
            ),
          ),
          if (right != null && !hasVehicle) right!,
        ],
      ),
    );

    if (!hasVehicle) return row;

    final barY = _barY();
    return Stack(
      children: [
        row,
        Positioned(
          top: barY - 1.5,
          left: 0,
          right: 0,
          child: Row(
            children: [
              const SizedBox(width: 140),
              Container(width: 40, height: 3, color: cs.onSurface),
              const SizedBox(width: 8),
              Text(
                vehiclePlate!,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class StopEtaMinutes extends StatelessWidget {
  const StopEtaMinutes({required this.minutes, this.color, super.key});
  final int minutes;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$minutes',
          style: TextStyle(
            fontSize: 14,
            color: color ?? cs.onSurface,
            height: 1.5,
          ),
        ),
        SizedBox(
          width: 8,
          height: 14,
          child: Text(
            '分',
            style: TextStyle(fontSize: 8, color: cs.outline, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class StopStatusText extends StatelessWidget {
  const StopStatusText({required this.text, this.color, super.key});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        color: color ?? Theme.of(context).colorScheme.onSurface,
        height: 1.5,
      ),
    );
  }
}

class StopTimePair extends StatelessWidget {
  const StopTimePair({
    this.primaryTime,
    this.primaryLabel,
    this.secondaryTime,
    this.secondaryLabel,
    super.key,
  });

  final String? primaryTime;
  final String? primaryLabel;
  final String? secondaryTime;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (primaryTime != null)
          _TimeRow(time: primaryTime!, label: primaryLabel ?? '抵達'),
        if (secondaryTime != null)
          _TimeRow(time: secondaryTime!, label: secondaryLabel ?? '出發'),
      ],
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.time, required this.label});
  final String time;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(time, style: const TextStyle(fontSize: 14, height: 1.5)),
        SizedBox(
          width: 16,
          height: 14,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 8,
              color: Theme.of(context).colorScheme.outline,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class PillPainter extends CustomPainter {
  const PillPainter({
    required this.topColor,
    required this.bottomColor,
    required this.isFirst,
    required this.isLast,
  });

  final Color topColor;
  final Color bottomColor;
  final bool isFirst;
  final bool isLast;

  static const _cx = 10.0;
  static const _hw = 8.0;
  static const _r = 8.0;
  static const _dotR = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final dotY = size.height / 2;

    if (!isFirst) {
      final rect = Rect.fromLTRB(_cx - _hw, 0, _cx + _hw, dotY);
      if (isLast) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            bottomLeft: const Radius.circular(_r),
            bottomRight: const Radius.circular(_r),
          ),
          Paint()..color = topColor,
        );
      } else {
        canvas.drawRect(rect, Paint()..color = topColor);
      }
    }

    if (!isLast) {
      final rect = Rect.fromLTRB(_cx - _hw, dotY, _cx + _hw, size.height);
      if (isFirst) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: const Radius.circular(_r),
            topRight: const Radius.circular(_r),
          ),
          Paint()..color = bottomColor,
        );
      } else {
        canvas.drawRect(rect, Paint()..color = bottomColor);
      }
    }

    canvas.drawCircle(Offset(_cx, dotY), _dotR, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(PillPainter old) =>
      old.topColor != topColor ||
      old.bottomColor != bottomColor ||
      old.isFirst != isFirst ||
      old.isLast != isLast;
}
