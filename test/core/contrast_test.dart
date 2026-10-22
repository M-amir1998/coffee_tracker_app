import 'dart:math' as math;

import 'package:coffee_tracker/core/theme/app_theme.dart';
import 'package:coffee_tracker/core/theme/finance_colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

double _channel(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color color) => 0.2126 * _channel(color.r) + 0.7152 * _channel(color.g) + 0.0722 * _channel(color.b);

/// WCAG 2.1 contrast ratio.
double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final (name, scheme, finance) in [
    ('light', AppTheme.lightScheme, FinanceColors.light),
    ('dark', AppTheme.darkScheme, FinanceColors.dark),
  ]) {
    group('$name theme meets WCAG AA', () {
      final card = AppTheme.cardBackground(scheme);
      final page = AppTheme.pageBackground(scheme);

      test('body text on page and cards', () {
        expect(contrast(scheme.onSurface, page), greaterThanOrEqualTo(4.5));
        expect(contrast(scheme.onSurface, card), greaterThanOrEqualTo(4.5));
        expect(contrast(scheme.onSurfaceVariant, card), greaterThanOrEqualTo(4.5));
      });

      test('buttons and containers', () {
        expect(contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(4.5));
        expect(contrast(scheme.onSecondaryContainer, scheme.secondaryContainer), greaterThanOrEqualTo(4.5));
        expect(contrast(scheme.onTertiary, scheme.tertiary), greaterThanOrEqualTo(4.5));
        expect(contrast(scheme.onError, scheme.error), greaterThanOrEqualTo(4.5));
        expect(contrast(scheme.onInverseSurface, scheme.inverseSurface), greaterThanOrEqualTo(4.5));
      });

      test('money states on cards and on their own containers', () {
        for (final (fg, bg) in [
          (finance.owes, finance.owesContainer),
          (finance.owed, finance.owedContainer),
          (finance.pending, finance.pendingContainer),
          (finance.settled, finance.settledContainer),
        ]) {
          expect(contrast(fg, card), greaterThanOrEqualTo(4.5), reason: '$fg on card');
          expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$fg on $bg');
        }
      });

      test('interactive outlines are visible (3:1)', () {
        expect(contrast(scheme.outline, card), greaterThanOrEqualTo(3));
        expect(contrast(scheme.primary, card), greaterThanOrEqualTo(3));
      });
    });
  }
}
