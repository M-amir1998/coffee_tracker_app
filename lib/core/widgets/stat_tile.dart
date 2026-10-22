import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/money_text.dart';
import 'package:material_ui/material_ui.dart';

/// A labelled figure for overview grids.
class StatTile extends StatelessWidget {
  const StatTile({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
    this.caption,
    this.valueColor,
    this.emphasis = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? caption;
  final Color? valueColor;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(Spacing.md),
      color: emphasis ? scheme.secondaryContainer : null,
      semanticLabel: [label, value, ?caption].join('. '),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: emphasis ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: emphasis ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? (emphasis ? scheme.onSecondaryContainer : null),
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 2),
              Text(caption!, style: theme.textTheme.bodySmall, maxLines: 2),
            ],
          ],
        ),
      ),
    );
  }
}
