import 'package:flutter/material.dart';

/// Shared motion timings and curves for the app.
abstract final class AppMotion {
  /// No animation.
  static const Duration instant = Duration.zero;

  /// Press feedback duration.
  static const Duration press = Duration(milliseconds: 110);

  /// Short transition duration.
  static const Duration short = Duration(milliseconds: 180);

  /// Medium transition duration.
  static const Duration medium = Duration(milliseconds: 240);

  /// Sheet transition duration.
  static const Duration sheet = Duration(milliseconds: 280);

  /// Expressive ease-out curve.
  static const Curve easeOut = Cubic(0.23, 1, 0.32, 1);

  /// Expressive ease-in-out curve.
  static const Curve easeInOut = Cubic(0.77, 0, 0.175, 1);

  /// Drawer transition curve.
  static const Curve drawer = Cubic(0.32, 0.72, 0, 1);

  /// Scale applied while a pressable surface is pressed.
  static const double pressedScale = 0.97;
}
