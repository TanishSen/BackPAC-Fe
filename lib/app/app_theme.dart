import 'package:flutter/material.dart';

/// Every colour, size and duration the app draws with.
///
/// Nothing outside this file hard-codes a hex value or a font size — change a
/// token here and the whole app follows.
class AppColors {
  const AppColors._();

  /// The page behind everything: a very light, slightly cool grey.
  static const Color canvas = Color(0xFFF2F2F5);
  static const Color surface = Color(0xFFFEFEFE);

  /// Brand indigo, and the tints built from it.
  static const Color brand = Color(0xFF6A68DF);
  static const Color brandSoft = Color(0xFFA78BFA);
  static const Color brandWash = Color(0xFFEEEDFC);
  static const Color brandLine = Color(0xFFD9D7F7);

  /// The warm accent from the branding sheet.
  static const Color peach = Color(0xFFEFB995);
  static const Color peachWash = Color(0xFFFDF0E6);

  static const Color ink = Color(0xFF2E2C2D);
  static const Color inkSoft = Color(0xFF4A484B);
  static const Color muted = Color(0xFF8A8892);
  static const Color line = Color(0xFFE8E8EE);

  /// Tints for the soft reflection under the orb, sampled from its own palette.
  static const Color reflectPink = Color(0xFFF07EC8);
  static const Color reflectOrange = Color(0xFFFF9350);
  static const Color reflectViolet = Color(0xFF8F7BE8);
}

class AppSpacing {
  const AppSpacing._();

  static const double pageH = 20;
  static const double bottomSafe = 28;
  static const double buttonHeight = 64;
  static const double buttonRadius = 34;
  static const double bubbleRadius = 20;

  /// Cards, sheets and the composer all share one corner radius family.
  static const double cardRadius = 22;
  static const double chipRadius = 22;
  static const double gap = 14;
}

class AppDurations {
  const AppDurations._();

  /// How long after the page appears the orb says hello.
  static const Duration greetingDelay = Duration(milliseconds: 700);

  /// How long it talks for, and how long until it says hello again.
  static const Duration greetingSpeech = Duration(milliseconds: 2600);
  static const Duration greetingInterval = Duration(seconds: 11);

  static const Duration bubbleIn = Duration(milliseconds: 420);

  /// Entrance animations: one beat, staggered by [stagger] per item.
  static const Duration enter = Duration(milliseconds: 460);
  static const Duration stagger = Duration(milliseconds: 70);

  /// How long the assistant "thinks" before its reply lands.
  static const Duration thinking = Duration(milliseconds: 1100);
}

/// Text styles.
///
/// Poppins, per the branding sheet — bundled in assets/fonts (SIL Open Font
/// License, the licence text sits beside the files), not fetched at runtime.
/// Every style in the app comes from here, so the face is one constant.
class AppText {
  const AppText._();

  static const String _family = 'Poppins';

  static const TextStyle wordmark = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppColors.brand,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: _family,
    fontSize: 34,
    height: 1.24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    color: AppColors.ink,
  );

  /// "Hi, Jasmin"
  static const TextStyle title = TextStyle(
    fontFamily: _family,
    fontSize: 26,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    color: AppColors.ink,
  );

  /// Section headings: "History", "Plan something new".
  static const TextStyle section = TextStyle(
    fontFamily: _family,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.ink,
  );

  static const TextStyle cardTitle = TextStyle(
    fontFamily: _family,
    fontSize: 15.5,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    color: AppColors.ink,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _family,
    fontSize: 14.5,
    height: 1.55,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: AppColors.muted,
  );

  /// Chat message text — darker and tighter than [body].
  static const TextStyle message = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: AppColors.ink,
  );

  static const TextStyle label = TextStyle(
    fontFamily: _family,
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
    color: AppColors.inkSoft,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _family,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: AppColors.muted,
  );

  static const TextStyle bubble = TextStyle(
    fontFamily: _family,
    fontSize: 17,
    height: 1.2,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.3,
    color: AppColors.ink,
  );

  static const TextStyle button = TextStyle(
    fontFamily: _family,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppColors.ink,
  );
}

ThemeData buildAppTheme() {
  final ThemeData base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      surface: AppColors.canvas,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.canvas,
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
      fontFamily: AppText._family,
    ),
  );
}
