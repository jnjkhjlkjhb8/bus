import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color train3000 = Color(0xFF75147C);
  static const Color trainSelfstrong = Color(0xFFF08D36);
  static const Color trainRangecar = Color(0xFF0108B5);
  static const Color trainRangefast = Color(0xFF99C242);
  static const Color trainTaroko = Color(0xFFEC5E2A);
  static const Color trainOrangelight = Color(0xFFF8D448);
  static const Color trainThsr = Color(0xFFDB5325);
  static const Color mrtBL = Color(0xFF0070BD);
  static const Color mrtR = Color(0xFFE3002C);
  static const Color mrtG = Color(0xFF008659);
  static const Color mrtO = Color(0xFFF2A83B);
  static const Color mrtBR = Color(0xFFC48C31);
  static const Color mrtY = Color(0xFFFFDB00);
  static const Color mrtAM = Color(0xFF8246AF);
  static const Color mrtTG = Color(0xFF9BC346);
  static const Color mrtKG = Color(0xFF90BE50);
  static const Color mrtKR = Color(0xFFE3002C);
  static const Color mrtKO = Color(0xFFE6A739);
  static const Color ferryBlue = Color(0xFF0288D1);

  static const Color statusArriving = Color(0xFF12B76A);
  static const Color statusArrivingText = Color(0xFF0E7C42);
  static const Color statusApproach = Color(0xFFF79009);
  static const Color etaArriving = Color(0xFFB42318);
  static const Color etaApproaching = Color(0xFFB54708);
  static const Color trainDelay = Color(0xFFD92D20);
  static const Color warningBg = Color(0xFFFEF0C7);
  static const Color warningBorder = Color(0xFFB54708);

  static const double radiusCard = 12;
  static const double radiusModal = 12;
  static const double radiusBottom = 8;
  static const double radiusStadium = 999;
  static const double radiusSearchBar = 28;
  static const double radiusChip = 4;
  static const double radiusButton = 8;
  static const double radiusBottomSheet = 28;

  // Pure Achromatic color tokens (Light Mode)
  static const Color inkLight = Color(0xFF111111);
  static const Color inkSecondaryLight = Color(0xFF636363);
  static const Color inkDisabledLight = Color(0xFFBFBFBF);
  static const Color borderLight = Color(0xFFE0E0E0);
  static const Color surfaceLight = Color(0xFFF7F7F7);
  static const Color surfaceCardLight = Color(0xFFFFFFFF);
  static const Color surfacePressLight = Color(0xFFEFEFEF);
  static const Color surfaceHighlightLight = Color(0xFFE8E8E8);

  // Pure Achromatic color tokens (Dark Mode)
  static const Color inkDark = Color(0xFFF5F5F5);
  static const Color inkSecondaryDark = Color(0xFF9E9E9E);
  static const Color inkDisabledDark = Color(0xFF383838);
  static const Color borderDark = Color(0xFF383838);
  static const Color surfaceDark = Color(0xFF111111);
  static const Color surfaceCardDark = Color(0xFF1C1C1C);
  static const Color surfacePressDark = Color(0xFF282828);
  static const Color surfaceHighlightDark = Color(0xFF2C2C2C);

  // Custom static schemes ensuring pure neutral surfaces and maximum contrast
  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: inkLight,
    onPrimary: Colors.white,
    primaryContainer: surfacePressLight,
    onPrimaryContainer: inkLight,
    secondary: inkSecondaryLight,
    onSecondary: Colors.white,
    error: Color(0xFFBA1A1A),
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFFBA1A1A),
    surface: surfaceLight,
    onSurface: inkLight,
    surfaceContainerLow: surfaceCardLight,
    surfaceContainerHighest: surfacePressLight,
    onSurfaceVariant: inkSecondaryLight,
    outline: inkDisabledLight,
    outlineVariant: borderLight,
  );

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: inkDark,
    onPrimary: inkLight,
    primaryContainer: surfacePressDark,
    onPrimaryContainer: inkDark,
    secondary: inkSecondaryDark,
    onSecondary: inkLight,
    error: Color(0xFFBA1A1A),
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFFBA1A1A),
    surface: surfaceDark,
    onSurface: inkDark,
    surfaceContainerLow: surfaceCardDark,
    surfaceContainerHighest: surfacePressDark,
    onSurfaceVariant: inkSecondaryDark,
    outline: borderDark,
    outlineVariant: borderDark,
  );

  static TextTheme _text(ColorScheme cs) => TextTheme(
    displayLarge: TextStyle(
      fontFamily: 'Inter',
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.3,
      color: cs.onSurface,
    ),
    headlineLarge: TextStyle(
      fontFamily: 'Inter',
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.3,
      color: cs.onSurface,
    ),
    titleLarge: TextStyle(
      fontFamily: 'Inter',
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.3,
      color: cs.onSurface,
    ),
    titleMedium: TextStyle(
      fontFamily: 'Inter',
      fontSize: 16,
      fontWeight: FontWeight.w700,
      height: 1.35,
      color: cs.onSurface,
    ),
    titleSmall: TextStyle(
      fontFamily: 'Inter',
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.45,
      color: cs.onSurface,
    ),
    bodyLarge: TextStyle(
      fontFamily: 'Inter',
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: cs.onSurface,
    ),
    bodyMedium: TextStyle(
      fontFamily: 'Inter',
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: cs.onSurface,
    ),
    bodySmall: TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.4,
      color: cs.onSurfaceVariant,
    ),
    labelLarge: TextStyle(
      fontFamily: 'Inter',
      fontSize: 14,
      fontWeight: FontWeight.w700,
      height: 1.4,
      color: cs.onSurface,
    ),
    labelMedium: TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 1.4,
      color: cs.onSurfaceVariant,
    ),
    labelSmall: TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      fontWeight: FontWeight.w500,
      height: 1.4,
      color: cs.onSurfaceVariant,
    ),
  );

  static CardThemeData _card(ColorScheme cs) => CardThemeData(
    color: cs.brightness == Brightness.light
        ? surfaceCardLight
        : surfaceCardDark,
    elevation: 1,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusCard),
    ),
    clipBehavior: Clip.antiAlias,
    margin: EdgeInsets.zero,
  );

  static ThemeData get light => _build(lightScheme);

  static ThemeData get dark => _build(darkScheme);

  static ThemeData _build(ColorScheme cs) => ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: cs,
    textTheme: _text(cs),
    cardTheme: _card(cs),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: cs.onSurface,
      titleTextStyle: _text(cs).titleLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        minimumSize: const Size(64, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusButton),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusChip),
      ),
    ),
    scaffoldBackgroundColor: cs.surface,
    dividerTheme: DividerThemeData(
      space: 0,
      thickness: 0.5,
      color: cs.outlineVariant,
    ),
  );
}
