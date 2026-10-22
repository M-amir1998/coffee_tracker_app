import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/member_avatar.dart';
import 'package:coffee_tracker/features/leaderboard/domain/ranking.dart';
import 'package:material_ui/material_ui.dart';

/// Animated podium for the top three ranks, with titles and friendly messages.
class Podium extends StatelessWidget {
  const Podium({required this.entries, required this.seed, super.key});

  final List<RankedEntry> entries;

  /// Changes with the period so that messages rotate, but stays stable while
  /// the screen is open.
  final String seed;

  @override
  Widget build(BuildContext context) {
    final byRank = {for (final rank in [1, 2, 3]) rank: entries.where((e) => e.rank == rank).toList()};
    // Visual order: silver, gold, bronze.
    final columns = [2, 1, 3].where((rank) => byRank[rank]!.isNotEmpty).toList();
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [for (final rank in columns) Expanded(child: _PodiumColumn(rank: rank, entries: byRank[rank]!))],
        ),
        const SizedBox(height: Spacing.md),
        for (final entry in entries) _HeroMessage(entry: entry, seed: seed),
      ],
    );
  }
}

Color medalColor(Medal medal) => switch (medal) {
  Medal.gold => Palette.gold,
  Medal.silver => Palette.silver,
  Medal.bronze => Palette.bronze,
};

String heroTitle(AppLocalizations l10n, int rank) => switch (rank) {
  1 => l10n.heroTitleFirst,
  2 => l10n.heroTitleSecond,
  _ => l10n.heroTitleThird,
};

List<String> heroMessages(AppLocalizations l10n, int rank) => switch (rank) {
  1 => [l10n.heroFirst1, l10n.heroFirst2, l10n.heroFirst3, l10n.heroFirst4],
  2 => [l10n.heroSecond1, l10n.heroSecond2, l10n.heroSecond3, l10n.heroSecond4],
  _ => [l10n.heroThird1, l10n.heroThird2, l10n.heroThird3, l10n.heroThird4],
};

class _PodiumColumn extends StatelessWidget {
  const _PodiumColumn({required this.rank, required this.entries});

  final int rank;
  final List<RankedEntry> entries;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final medal = entries.first.medal!;
    final color = medalColor(medal);
    final height = switch (rank) {
      1 => 120.0,
      2 => 88.0,
      _ => 64.0,
    };
    final names = entries.map((e) => e.entry.displayName).join(' & ');
    final coffees = entries.first.entry.coffees;

    return Semantics(
      label: l10n.podiumSemantic(rank, names, coffees),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xxs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomRight,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 3)),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: MemberAvatar(name: entries.first.entry.displayName, radius: rank == 1 ? 30 : 24),
                  ),
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Icon(Icons.workspace_premium_rounded, color: color, size: rank == 1 ? 26 : 22),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(names, style: theme.textTheme.titleSmall, textAlign: TextAlign.center, maxLines: 2),
            Text(l10n.coffeesCount(coffees), style: theme.textTheme.bodySmall),
            const SizedBox(height: Spacing.xs),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: height),
              duration: Motion.of(context, Motion.slow * (rank == 1 ? 1.6 : 1.2)),
              curve: Motion.emphasized,
              builder: (context, value, child) => Container(
                height: value,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.md)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0.45)],
                  ),
                ),
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: child,
              ),
              child: Text(
                '$rank',
                style: theme.textTheme.headlineMedium?.copyWith(color: Palette.deepCoffee, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroMessage extends StatelessWidget {
  const _HeroMessage({required this.entry, required this.seed});

  final RankedEntry entry;
  final String seed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final messages = heroMessages(l10n, entry.rank);
    final message = messages[stableMessageIndex(count: messages.length, seed: '$seed-${entry.entry.userId}')];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.workspace_premium_rounded, size: 18, color: medalColor(entry.medal!)),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${heroTitle(l10n, entry.rank)} · ${entry.entry.displayName}: ',
                    style: theme.textTheme.labelLarge,
                  ),
                  TextSpan(text: message, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
