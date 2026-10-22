import 'package:material_ui/material_ui.dart';

/// Brand palette. Accessible text pairings are defined in the color schemes;
/// use these raw values only for illustrations and accents.
abstract final class Palette {
  static const espresso = Color(0xFF3E2723);
  static const deepCoffee = Color(0xFF241A17);
  static const cream = Color(0xFFFFF8F0);
  static const warmBeige = Color(0xFFF2E8DC);
  static const caramel = Color(0xFFC58B55);
  static const softGreen = Color(0xFF5E8A70);
  static const mutedRed = Color(0xFFC45B54);
  static const latte = Color(0xFFE9D9C9);
  static const foam = Color(0xFFFFFDF9);

  // Medal tones for Coffee Heroes: muted metals that fit the coffee palette.
  static const gold = Color(0xFFC9A04B);
  static const silver = Color(0xFFA9A9A4);
  static const bronze = Color(0xFFB07A4F);
}

abstract final class Spacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

abstract final class Radii {
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 22.0;
  static const xl = 28.0;
  static const pill = 999.0;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 450);
  static const emphasized = Curves.easeOutCubic;

  /// Honors the platform "reduce motion" setting.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// Material 3 window size classes.
enum WindowSize {
  compact,
  medium,
  expanded,
  large;

  static WindowSize of(BuildContext context) => fromWidth(MediaQuery.sizeOf(context).width);

  static WindowSize fromWidth(double width) {
    if (width < 600) return WindowSize.compact;
    if (width < 840) return WindowSize.medium;
    if (width < 1200) return WindowSize.expanded;
    return WindowSize.large;
  }

  bool get isCompact => this == WindowSize.compact;
  bool get isAtLeastMedium => index >= WindowSize.medium.index;
  bool get isAtLeastExpanded => index >= WindowSize.expanded.index;
}
