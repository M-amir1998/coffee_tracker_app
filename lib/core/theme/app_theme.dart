import 'package:coffee_tracker/core/theme/finance_colors.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

abstract final class AppTheme {
  static const bodyFont = 'Inter';
  static const displayFont = 'Fraunces';

  static const lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Palette.espresso,
    onPrimary: Palette.cream,
    primaryContainer: Palette.latte,
    onPrimaryContainer: Color(0xFF2A1B16),
    secondary: Color(0xFF8A5A2B),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF6DFC4),
    onSecondaryContainer: Color(0xFF3A2410),
    tertiary: Color(0xFF3F6B53),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFD5E8DC),
    onTertiaryContainer: Color(0xFF10291C),
    error: Color(0xFFA4423C),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF9DEDB),
    onErrorContainer: Color(0xFF410E0B),
    surface: Palette.foam,
    onSurface: Palette.deepCoffee,
    onSurfaceVariant: Color(0xFF5C4D45),
    surfaceDim: Color(0xFFE6DACD),
    surfaceBright: Palette.foam,
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Palette.cream,
    surfaceContainer: Color(0xFFF8EFE5),
    surfaceContainerHigh: Palette.warmBeige,
    surfaceContainerHighest: Color(0xFFECE0D2),
    outline: Color(0xFF857369),
    outlineVariant: Color(0xFFDCCBBC),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF382E2A),
    onInverseSurface: Color(0xFFFBEEE6),
    inversePrimary: Color(0xFFE7BD95),
  );

  static const darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFE2B07F),
    onPrimary: Color(0xFF3B2208),
    primaryContainer: Color(0xFF5A3F2E),
    onPrimaryContainer: Color(0xFFFFDCC2),
    secondary: Color(0xFFD9C2B0),
    onSecondary: Color(0xFF3C2D22),
    secondaryContainer: Color(0xFF54443A),
    onSecondaryContainer: Color(0xFFF6DECB),
    tertiary: Color(0xFF9CCBAE),
    onTertiary: Color(0xFF06381F),
    tertiaryContainer: Color(0xFF24503A),
    onTertiaryContainer: Color(0xFFB8E8C9),
    error: Color(0xFFF2B8B3),
    onError: Color(0xFF601410),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFF9DEDC),
    surface: Color(0xFF1A1311),
    onSurface: Color(0xFFF1E4DB),
    onSurfaceVariant: Color(0xFFD6C3B7),
    surfaceDim: Color(0xFF1A1311),
    surfaceBright: Color(0xFF42372F),
    surfaceContainerLowest: Color(0xFF140E0C),
    surfaceContainerLow: Color(0xFF221A17),
    surfaceContainer: Color(0xFF271E1B),
    surfaceContainerHigh: Color(0xFF322825),
    surfaceContainerHighest: Color(0xFF3D332F),
    outline: Color(0xFF9F8D82),
    outlineVariant: Color(0xFF52443C),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFF1E4DB),
    onInverseSurface: Color(0xFF382E2A),
    inversePrimary: Color(0xFF7A5230),
  );

  static ThemeData light() => _build(lightScheme, FinanceColors.light);
  static ThemeData dark() => _build(darkScheme, FinanceColors.dark);

  /// Background of the page behind cards.
  static Color pageBackground(ColorScheme scheme) =>
      scheme.brightness == Brightness.light ? scheme.surfaceContainerLow : scheme.surface;

  /// Background of cards and sheets.
  static Color cardBackground(ColorScheme scheme) =>
      scheme.brightness == Brightness.light ? scheme.surfaceContainerLowest : scheme.surfaceContainerLow;

  static TextTheme _textTheme(ColorScheme scheme) {
    final base = Typography.material2021(platform: TargetPlatform.android).black.apply(
      fontFamily: bodyFont,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    TextStyle display(TextStyle? style, double size, FontWeight weight, {double height = 1.15}) =>
        (style ?? const TextStyle()).copyWith(
          fontFamily: displayFont,
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: -0.4,
          color: scheme.onSurface,
        );
    return base.copyWith(
      displayLarge: display(base.displayLarge, 52, FontWeight.w600),
      displayMedium: display(base.displayMedium, 42, FontWeight.w600),
      displaySmall: display(base.displaySmall, 34, FontWeight.w600),
      headlineLarge: display(base.headlineLarge, 30, FontWeight.w600, height: 1.2),
      headlineMedium: display(base.headlineMedium, 26, FontWeight.w600, height: 1.2),
      headlineSmall: display(base.headlineSmall, 22, FontWeight.w600, height: 1.25),
      titleLarge: base.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.2),
      titleMedium: base.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0),
      titleSmall: base.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.45, letterSpacing: 0),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.45, letterSpacing: 0),
      bodySmall: base.bodySmall?.copyWith(fontSize: 12.5, height: 1.4, color: scheme.onSurfaceVariant),
      labelLarge: base.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      labelMedium: base.labelMedium?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      labelSmall: base.labelSmall?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3),
    );
  }

  static ThemeData _build(ColorScheme scheme, FinanceColors finance) {
    final text = _textTheme(scheme);
    final card = cardBackground(scheme);
    final page = pageBackground(scheme);
    final roundedMd = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md));
    final stadium = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.pill));
    const buttonPadding = EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: text,
      fontFamily: bodyFont,
      scaffoldBackgroundColor: page,
      canvasColor: page,
      visualDensity: VisualDensity.standard,
      extensions: [finance],
      appBarTheme: AppBarTheme(
        backgroundColor: page,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineSmall,
      ),
      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: buttonPadding,
          shape: stadium,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: buttonPadding,
          shape: stadium,
          side: BorderSide(color: scheme.outline),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 44), shape: stadium, textStyle: text.labelLarge),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(44, 44))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.brightness == Brightness.light ? scheme.surfaceContainerLowest : scheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: text.labelMedium,
        backgroundColor: card,
        selectedColor: scheme.secondaryContainer,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
        elevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: page,
        indicatorColor: scheme.secondaryContainer,
        selectedLabelTextStyle: text.labelMedium?.copyWith(color: scheme.onSurface),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.secondaryContainer,
          selectedForegroundColor: scheme.onSecondaryContainer,
          textStyle: text.labelLarge,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        shape: roundedMd,
        width: 480,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
        titleTextStyle: text.headlineSmall,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
      ),
      listTileTheme: ListTileThemeData(
        shape: roundedMd,
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.7), space: 1, thickness: 1),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: BorderRadius.circular(Radii.sm)),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: stadium,
      ),
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? const Icon(Icons.check_rounded, size: 16) : null,
        ),
      ),
    );
  }
}
