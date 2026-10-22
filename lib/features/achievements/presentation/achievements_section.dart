import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/features/achievements/domain/achievements.dart';
import 'package:coffee_tracker/features/leaderboard/domain/leaderboard_models.dart';
import 'package:material_ui/material_ui.dart';

class AchievementsSection extends StatelessWidget {
  const AchievementsSection({required this.stats, super.key});

  final MyStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final achievements = evaluateAchievements(stats, DateTime.now());
    final unlocked = achievements.where((a) => a.unlocked).length;
    return SectionCard(
      title: l10n.achievementsTitle,
      trailing: Text(
        l10n.achievementsProgress(unlocked, achievements.length),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = (constraints.maxWidth / 220).floor().clamp(1, 3);
          final width = (constraints.maxWidth - (columns - 1) * Spacing.sm) / columns;
          return Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final a in achievements)
                SizedBox(
                  width: width,
                  child: _AchievementTile(progress: a),
                ),
            ],
          );
        },
      ),
    );
  }
}

(IconData, String, String) achievementText(AppLocalizations l10n, AchievementId id) => switch (id) {
  AchievementId.firstSip => (Icons.coffee_rounded, l10n.achFirstSip, l10n.achFirstSipDesc),
  AchievementId.earlyBird => (Icons.wb_twilight_rounded, l10n.achEarlyBird, l10n.achEarlyBirdDesc),
  AchievementId.nightOwl => (Icons.nightlight_round, l10n.achNightOwl, l10n.achNightOwlDesc),
  AchievementId.coffeeMarathon => (
    Icons.directions_run_rounded,
    l10n.achMarathon,
    l10n.achMarathonDesc(AchievementRules.marathonCoffees),
  ),
  AchievementId.consistencyChampion => (
    Icons.event_available_rounded,
    l10n.achConsistency,
    l10n.achConsistencyDesc(AchievementRules.consistencyDays),
  ),
  AchievementId.beanGuardian => (Icons.shield_rounded, l10n.achBeanGuardian, l10n.achBeanGuardianDesc),
  AchievementId.generousContributor => (Icons.volunteer_activism_rounded, l10n.achGenerous, l10n.achGenerousDesc),
  AchievementId.perfectlyBalanced => (Icons.balance_rounded, l10n.achBalanced, l10n.achBalancedDesc),
  AchievementId.coffeeVeteran => (
    Icons.military_tech_rounded,
    l10n.achVeteran,
    l10n.achVeteranDesc(AchievementRules.veteranDays),
  ),
};

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.progress});

  final AchievementProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, title, description) = achievementText(l10n, progress.id);
    final unlocked = progress.unlocked;
    return Semantics(
      label:
          '$title. $description. ${unlocked ? l10n.achievementUnlocked : l10n.achievementLocked(progress.current, progress.target)}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: unlocked ? scheme.secondaryContainer : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.sm),
          child: Row(
            children: [
              Icon(icon, color: unlocked ? Palette.gold : scheme.onSurfaceVariant.withValues(alpha: 0.6), size: 28),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    Text(description, style: theme.textTheme.bodySmall, maxLines: 2),
                    if (!unlocked && progress.target > 1) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: progress.fraction, borderRadius: BorderRadius.circular(4)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
