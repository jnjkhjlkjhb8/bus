import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';

enum AvatarStatus { online, offline }

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.size = 40,
    this.image,
    this.initials,
    this.icon,
    this.status,
  });

  final double size;
  final ImageProvider? image;
  final String? initials;
  final IconData? icon;
  final AvatarStatus? status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasImage = image != null;
    final hasInitials = initials != null && !hasImage;
    final isLarge = size >= 40;

    final bgColor = hasInitials
        ? cs.primaryContainer
        : cs.surfaceContainerHighest;

    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: hasImage ? null : bgColor,
        shape: BoxShape.circle,
        image: hasImage
            ? DecorationImage(image: image!, fit: BoxFit.cover)
            : null,
      ),
      child: hasImage
          ? null
          : Center(
              child: hasInitials
                  ? Text(
                      initials!,
                      style:
                          (isLarge
                                  ? AppTextStyles.bodyRegular
                                  : AppTextStyles.bodySmall)
                              .copyWith(
                                fontWeight: FontWeight.w600,
                                color: cs.onPrimaryContainer,
                              ),
                    )
                  : Icon(
                      icon ?? Icons.person_rounded,
                      size: size * 0.55,
                      color: cs.onSurfaceVariant,
                    ),
            ),
    );

    if (status == null) return circle;

    const dotSize = 8.0;
    const borderWidth = 2.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        circle,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: status == AvatarStatus.online ? cs.tertiary : cs.outline,
              shape: BoxShape.circle,
              border: Border.all(
                color: cs.surface,
                width: borderWidth,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
