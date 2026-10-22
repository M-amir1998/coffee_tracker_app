import 'package:material_ui/material_ui.dart';

/// Semantic colors for money states. Text colors meet WCAG AA (4.5:1) on both
/// their container and the default card surface (verified in tests).
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({
    required this.owes,
    required this.owesContainer,
    required this.owed,
    required this.owedContainer,
    required this.pending,
    required this.pendingContainer,
    required this.settled,
    required this.settledContainer,
  });

  static const light = FinanceColors(
    owes: Color(0xFF9E3D37),
    owesContainer: Color(0xFFF9E3E0),
    owed: Color(0xFF3B6650),
    owedContainer: Color(0xFFDCEEE3),
    pending: Color(0xFF7D5124),
    pendingContainer: Color(0xFFF7E6D1),
    settled: Color(0xFF5C4D45),
    settledContainer: Color(0xFFF0E6DC),
  );

  static const dark = FinanceColors(
    owes: Color(0xFFF4BAB4),
    owesContainer: Color(0xFF4E2220),
    owed: Color(0xFFA3D2B5),
    owedContainer: Color(0xFF1D3B2C),
    pending: Color(0xFFEBC696),
    pendingContainer: Color(0xFF45311D),
    settled: Color(0xFFD6C3B7),
    settledContainer: Color(0xFF332924),
  );

  /// Member owes the group.
  final Color owes;
  final Color owesContainer;

  /// The group owes the member.
  final Color owed;
  final Color owedContainer;

  /// Awaiting confirmation; not final money.
  final Color pending;
  final Color pendingContainer;

  final Color settled;
  final Color settledContainer;

  static FinanceColors of(BuildContext context) => Theme.of(context).extension<FinanceColors>() ?? light;

  @override
  FinanceColors copyWith({
    Color? owes,
    Color? owesContainer,
    Color? owed,
    Color? owedContainer,
    Color? pending,
    Color? pendingContainer,
    Color? settled,
    Color? settledContainer,
  }) {
    return FinanceColors(
      owes: owes ?? this.owes,
      owesContainer: owesContainer ?? this.owesContainer,
      owed: owed ?? this.owed,
      owedContainer: owedContainer ?? this.owedContainer,
      pending: pending ?? this.pending,
      pendingContainer: pendingContainer ?? this.pendingContainer,
      settled: settled ?? this.settled,
      settledContainer: settledContainer ?? this.settledContainer,
    );
  }

  @override
  FinanceColors lerp(FinanceColors? other, double t) {
    if (other == null) return this;
    return FinanceColors(
      owes: Color.lerp(owes, other.owes, t)!,
      owesContainer: Color.lerp(owesContainer, other.owesContainer, t)!,
      owed: Color.lerp(owed, other.owed, t)!,
      owedContainer: Color.lerp(owedContainer, other.owedContainer, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      pendingContainer: Color.lerp(pendingContainer, other.pendingContainer, t)!,
      settled: Color.lerp(settled, other.settled, t)!,
      settledContainer: Color.lerp(settledContainer, other.settledContainer, t)!,
    );
  }
}
