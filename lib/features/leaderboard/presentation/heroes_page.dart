import 'dart:async';

import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/tokens.dart';
import 'package:coffee_tracker/core/widgets/app_card.dart';
import 'package:coffee_tracker/core/widgets/feedback.dart';
import 'package:coffee_tracker/core/widgets/member_avatar.dart';
import 'package:coffee_tracker/core/widgets/page_layout.dart';
import 'package:coffee_tracker/core/widgets/states.dart';
import 'package:coffee_tracker/features/accounting/application/report_providers.dart';
import 'package:coffee_tracker/features/achievements/presentation/achievements_section.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/leaderboard/domain/leaderboard_models.dart';
import 'package:coffee_tracker/features/leaderboard/domain/ranking.dart';
import 'package:coffee_tracker/features/leaderboard/domain/streaks.dart';
import 'package:coffee_tracker/features/leaderboard/presentation/podium.dart';
import 'package:coffee_tracker/features/profile/application/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class HeroesPage extends ConsumerStatefulWidget {
  const HeroesPage({super.key});

  @override
  ConsumerState<HeroesPage> createState() => _HeroesPageState();
}

class _HeroesPageState extends ConsumerState<HeroesPage> {
  LeaderboardPeriod _period = LeaderboardPeriod.month;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final groupId = ref.watch(currentGroupIdProvider);
    if (groupId == null) return const SizedBox.shrink();
    final preferences = ref.watch(preferencesProvider);

    if (!preferences.gamificationEnabled) {
      return AppPage(
        title: l10n.navHeroes,
        body: EmptyState(
          icon: Icons.emoji_events_outlined,
          title: l10n.heroesHiddenTitle,
          message: l10n.heroesHiddenMessage,
          action: FilledButton(
            onPressed: () => unawaited(
              ref.read(preferencesProvider.notifier).update(preferences.copyWith(gamificationEnabled: true)),
            ),
            child: Text(l10n.heroesShow),
          ),
        ),
      );
    }

    final board = ref.watch(leaderboardProvider((groupId: groupId, period: _period)));
    final stats = ref.watch(myStatsProvider(groupId));
    final awards = ref.watch(monthlyAwardsProvider(groupId));

    return AppPage(
      title: l10n.navHeroes,
      subtitle: l10n.heroesSubtitle,
      onRefresh: () async => ref.read(dataRevisionProvider.notifier).bump(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<LeaderboardPeriod>(
              segments: [
                ButtonSegment(value: LeaderboardPeriod.week, label: Text(l10n.periodWeek)),
                ButtonSegment(value: LeaderboardPeriod.month, label: Text(l10n.periodMonth)),
                ButtonSegment(value: LeaderboardPeriod.cycle, label: Text(l10n.periodCycle)),
                ButtonSegment(value: LeaderboardPeriod.allTime, label: Text(l10n.periodAllTime)),
              ],
              selected: {_period},
              onSelectionChanged: (value) => setState(() => _period = value.first),
            ),
          ),
          const SizedBox(height: Spacing.md),
          ResponsiveColumns(
            minColumnWidth: 440,
            maxColumns: 2,
            children: [
              AsyncValueView(
                value: board,
                onRetry: () => ref.invalidate(leaderboardProvider((groupId: groupId, period: _period))),
                data: (data) => _Leaderboard(data: data),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (awards.value case final list? when list.isNotEmpty) ...[
                    _AwardBanner(award: list.first),
                    const SizedBox(height: Spacing.md),
                  ],
                  AsyncValueView(
                    value: stats,
                    data: (data) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FunStats(stats: data),
                        const SizedBox(height: Spacing.md),
                        AchievementsSection(stats: data),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Leaderboard extends StatelessWidget {
  const _Leaderboard({required this.data});

  final LeaderboardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final ranked = rankEntries(data.entries);
    final top = podium(ranked);
    final rest = ranked.where((r) => r.rank > 3).toList();
    final me = data.entries.where((e) => e.isMe).firstOrNull;

    if (ranked.isEmpty) {
      return AppCard(
        child: EmptyState(
          icon: Icons.emoji_events_outlined,
          title: l10n.heroesEmptyTitle,
          message: l10n.heroesEmptyMessage,
        ),
      );
    }

    final seed = '${data.period.wireName}-${data.periodStart?.toIso8601String() ?? ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Podium(entries: top, seed: seed),
        ),
        if (me != null && me.isHidden) ...[
          const SizedBox(height: Spacing.sm),
          Text(l10n.heroesYouAreHidden, style: theme.textTheme.bodySmall),
        ],
        if (rest.isNotEmpty) ...[
          const SizedBox(height: Spacing.md),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs, horizontal: Spacing.sm),
            child: Column(
              children: [
                for (final entry in rest)
                  ListTile(
                    leading: SizedBox(
                      width: 64,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            child: Text(
                              '${entry.rank}',
                              style: theme.textTheme.titleSmall,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 6),
                          MemberAvatar(name: entry.entry.displayName, radius: 16),
                        ],
                      ),
                    ),
                    title: Text(entry.entry.isMe ? l10n.youSuffix(entry.entry.displayName) : entry.entry.displayName),
                    trailing: Text(l10n.coffeesCount(entry.entry.coffees), style: theme.textTheme.titleSmall),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Spacing.sm),
        Text(l10n.heroesTotal(data.totalCoffees), style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
      ],
    );
  }
}

class _AwardBanner extends StatelessWidget {
  const _AwardBanner({required this.award});

  final MonthlyAward award;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final names = award.winners.map((w) => w.displayName).join(', ');
    final coffees = award.winners.firstOrNull?.coffees ?? 0;
    return AppCard(
      color: Palette.gold.withValues(alpha: theme.brightness == Brightness.light ? 0.18 : 0.22),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium_rounded, size: 40, color: Palette.gold),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.monthlyHeroTitle(context.monthYear(award.month)), style: theme.textTheme.labelLarge),
                Text(names, style: theme.textTheme.titleLarge),
                Text(l10n.coffeesCount(coffees), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FunStats extends ConsumerWidget {
  const _FunStats({required this.stats});

  final MyStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final streak = computeStreaks(stats.coffeeDates, DateTime.now());
    final share = sharePercent(stats.monthCoffees, stats.groupMonthCoffees);
    final preferences = ref.watch(preferencesProvider);

    final facts = [
      (Icons.local_fire_department_rounded, l10n.streakCurrent(streak.current), l10n.streakBest(streak.best)),
      (
        Icons.pie_chart_rounded,
        l10n.shareOfMonth(share),
        l10n.monthCoffees(stats.monthCoffees, stats.groupMonthCoffees),
      ),
      if (stats.favoriteHour != null)
        (Icons.schedule_rounded, l10n.favoriteHour(_hour(context, stats.favoriteHour!)), l10n.favoriteHourHint),
      if (stats.groupWeekBusiestHour != null)
        (Icons.groups_rounded, l10n.busiestHour(_hour(context, stats.groupWeekBusiestHour!)), l10n.busiestHourHint),
      if (stats.groupMonthBusiestWeekday != null)
        (
          Icons.calendar_month_rounded,
          l10n.busiestWeekday(context.weekdayName(stats.groupMonthBusiestWeekday!)),
          l10n.busiestWeekdayHint,
        ),
    ];

    return SectionCard(
      title: l10n.funStatsTitle,
      child: Column(
        children: [
          for (final (icon, title, subtitle) in facts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: theme.colorScheme.secondary),
              title: Text(title),
              subtitle: Text(subtitle),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.showMeOnHeroes),
            subtitle: Text(l10n.showMeOnHeroesHint),
            value: preferences.showOnLeaderboard,
            onChanged: (value) async {
              try {
                await ref.read(preferencesProvider.notifier).update(preferences.copyWith(showOnLeaderboard: value));
                ref.read(dataRevisionProvider.notifier).bump();
              } on Object catch (error) {
                if (context.mounted) showErrorToast(context, error);
              }
            },
          ),
        ],
      ),
    );
  }

  static String _hour(BuildContext context, int hour) => context.time(DateTime(2024, 1, 1, hour));
}
