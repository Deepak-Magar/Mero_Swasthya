import 'package:flutter/material.dart';

import 'app_colors.dart';

// `TriageColors` used to live in this file and half the app imports it from
// here. It moved to `app_colors.dart` with the rest of the palette; this
// re-export keeps every existing import site correct.
export 'app_colors.dart';

/// Spacing scale. Four numbers, used everywhere, so that the rhythm of the app
/// is a decision made once rather than a hundred magic paddings.
///
/// The grouping rule the whole restyle rests on: lines that describe the *same
/// thing* (a name, an age, a ward) sit [tight] apart and read as one block;
/// blocks sit [lg] or [xl] apart. Whitespace does the work a 1 px divider used
/// to do, and does it better.
class AppSpacing {
  const AppSpacing._();

  /// Within a cluster — name above age above ward.
  static const double tight = 4;

  /// Between a label and its value.
  static const double sm = 8;

  /// The default gap between rows inside a card.
  static const double md = 12;

  /// Between cards, and the inner padding of a card.
  static const double lg = 16;

  /// Between sections.
  static const double xl = 24;

  /// The page gutter — every screen's horizontal padding.
  static const double gutter = 20;

  /// Corner radius for cards, sheets and tiles.
  static const double radius = 16;

  /// Corner radius for fields, chips and buttons.
  static const double radiusSm = 12;
}

class AppTheme {
  const AppTheme._();

  /// The seed the Material 3 scheme is generated from. The generated scheme is
  /// then overridden on every role the app actually paints with, so the seed
  /// only decides the handful of container shades nothing names directly.
  static const Color seed = AppColors.brandBlue;

  /// Spec §16: minimum tap target 48 dp.
  static const double minTapTarget = 48;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;

    // Dark mode keeps the *same* semantic colours — a red triage is the same
    // red at night — and only swaps the neutrals.
    final Color background =
        isLight ? AppColors.background : const Color(0xFF0F172A);
    final Color surface = isLight ? AppColors.surface : const Color(0xFF1E293B);
    final Color textPrimary =
        isLight ? AppColors.textPrimary : const Color(0xFFF1F5F9);
    final Color textSecondary =
        isLight ? AppColors.textSecondary : const Color(0xFF94A3B8);

    // Dark mode lifts the brand hues rather than reusing the light ones: brand
    // blue on the dark scaffold measures 2.04:1, which is not a colour, it is
    // a rumour. See the "Dark mode" block in `app_colors.dart`.
    final Color primary = AppColors.brand(brightness);
    final Color onPrimary =
        isLight ? AppColors.onBrand : AppColors.onBrandDark;
    final Color secondary =
        isLight ? AppColors.brandGreen : AppColors.brandGreenDark;
    final Color error =
        isLight ? AppColors.triageRed : AppColors.triageRedDark;
    final Color brandTint = AppColors.brandTint(brightness);

    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: onPrimary,
      secondary: secondary,
      onSecondary: onPrimary,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      outline: textSecondary,
      outlineVariant: textSecondary.withValues(alpha: 0.24),
      error: error,
      onError: isLight ? AppColors.onBrand : AppColors.onBrandDark,
    );

    final textTheme = _textTheme(textPrimary, textSecondary);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: textTheme,

      // Flat by design. The app bar is the page's title, not a shelf above it;
      // a shadow there competes with the cards, which is where the depth is
      // supposed to be.
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: textPrimary),
        actionsIconTheme: IconThemeData(color: textPrimary),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size.fromHeight(minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size.fromHeight(minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          side: BorderSide(color: primary.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(minTapTarget, minTapTarget),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(minTapTarget, minTapTarget),
          foregroundColor: textSecondary,
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      ),

      // Filled with the surface, plus a hairline.
      //
      // The hairline is not decoration; it is the field. "Filled with surface,
      // no border" reads perfectly on the page, where a white field sits on the
      // #F8FAFC scaffold — and disappears completely the moment the field is
      // inside something white, which is where half of them are: a FormSection
      // card, a bottom sheet. Found on the phone: the whole birth-plan sheet
      // and S23's server address rendered as floating labels over nothing.
      //
      // One 1 px line at 20 % of the secondary ink is the least that makes a
      // field legible on both grounds. It is a long way from the outlined boxes
      // this restyle removed.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        // A field error is the one place the app tells somebody what to do
        // next; a single clipped line with an ellipsis is not that. Two lines
        // hold every message the ARB has, in both languages.
        errorMaxLines: 2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: BorderSide(
            color: textSecondary.withValues(alpha: 0.2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: BorderSide(
            color: textSecondary.withValues(alpha: 0.2),
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: BorderSide(
            color: textSecondary.withValues(alpha: 0.12),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: const BorderSide(color: AppColors.triageRed, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          borderSide: const BorderSide(color: AppColors.triageRed, width: 2),
        ),
        labelStyle: TextStyle(color: textSecondary),
        floatingLabelStyle: TextStyle(color: primary),
        hintStyle: TextStyle(color: textSecondary),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: isLight
            ? brandTint
            : primary.withValues(alpha: 0.24),
        selectedColor: primary,
        checkmarkColor: onPrimary,
        side: BorderSide.none,
        elevation: 0,
        pressElevation: 0,
        labelStyle: TextStyle(
          color: textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(
          color: onPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: const StadiumBorder(),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: textSecondary.withValues(alpha: 0.3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: TextStyle(
          color: onPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        elevation: 2,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: brandTint,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? primary
                : textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? primary
                : textSecondary,
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        titleTextStyle: textTheme.titleLarge,
      ),

      // Kept flat and borderless so that a stray `Card` left anywhere cannot
      // reintroduce the outlined look SoftCard replaced.
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
      ),

      listTileTheme: ListTileThemeData(
        minVerticalPadding: 12,
        iconColor: textSecondary,
        textColor: textPrimary,
        titleTextStyle: textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(
          color: textSecondary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      ),

      // Whitespace groups things now. A divider that does slip through should
      // be a hairline, not a rule.
      dividerTheme: DividerThemeData(
        color: textSecondary.withValues(alpha: 0.12),
        thickness: 1,
        space: AppSpacing.lg,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? onPrimary
              : surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : textSecondary.withValues(alpha: 0.3),
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(onPrimary),
        side: BorderSide(color: textSecondary, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : textSecondary,
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? primary
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? onPrimary
                : textPrimary,
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: textSecondary.withValues(alpha: 0.24)),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
          ),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textSecondary,
        indicatorColor: primary,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }

  /// A 32 / 24 / 20 / 16 / 14 / 12 scale, headings at w700.
  ///
  /// No `fontFamily` is set anywhere: the app keeps the platform font, which is
  /// what renders Devanagari correctly on a Nepali phone. Naming a Latin family
  /// here would silently break every Nepali string — the conjuncts would fall
  /// back glyph by glyph and the matras would detach.
  static TextTheme _textTheme(Color primary, Color secondary) {
    // Devanagari sits taller than Latin and its vowel signs need headroom
    // above and below the baseline, so every style here carries an explicit
    // line height rather than leaning on the font's default.
    TextStyle heading(double size, {double height = 1.3}) => TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w700,
          color: primary,
          height: height,
          letterSpacing: -0.2,
        );

    TextStyle body(double size, {FontWeight weight = FontWeight.w400}) =>
        TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: primary,
          height: 1.45,
        );

    return TextTheme(
      displaySmall: heading(32, height: 1.25),
      headlineMedium: heading(24),
      headlineSmall: heading(24),
      titleLarge: heading(20),
      titleMedium: heading(16, height: 1.4),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: primary,
        height: 1.4,
      ),
      bodyLarge: body(16),
      bodyMedium: body(14),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: secondary,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: primary,
        height: 1.4,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: secondary,
        height: 1.4,
      ),
      labelSmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: secondary,
        height: 1.4,
        letterSpacing: 0.6,
      ),
    );
  }
}
