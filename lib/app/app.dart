import 'dart:async';

import 'package:coffee_tracker/app/core_providers.dart';
import 'package:coffee_tracker/app/router.dart';
import 'package:coffee_tracker/core/l10n/l10n.dart';
import 'package:coffee_tracker/core/theme/app_theme.dart';
import 'package:coffee_tracker/features/coffee/application/coffee_queue.dart';
import 'package:coffee_tracker/features/groups/application/group_providers.dart';
import 'package:coffee_tracker/features/profile/application/profile_providers.dart';
import 'package:coffee_tracker/features/shell/presentation/setup_required_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class CoffeeTrackerApp extends ConsumerWidget {
  const CoffeeTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final preferences = ref.watch(preferencesProvider);

    if (!config.isValid) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        onGenerateTitle: (context) => context.l10n.appTitle,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: SetupRequiredPage(problems: config.problems),
      );
    }

    return _LifecycleRefresh(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        onGenerateTitle: (context) => context.l10n.appTitle,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: preferences.theme,
        locale: preferences.locale.locale,
        localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: ref.watch(routerProvider),
      ),
    );
  }
}

/// Refreshes data and flushes the offline queue when the app returns to the
/// foreground, as a fallback for missed realtime events.
class _LifecycleRefresh extends ConsumerStatefulWidget {
  const _LifecycleRefresh({required this.child});

  final Widget child;

  @override
  ConsumerState<_LifecycleRefresh> createState() => _LifecycleRefreshState();
}

class _LifecycleRefreshState extends ConsumerState<_LifecycleRefresh> {
  late final AppLifecycleListener _listener;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onHide: () => _pausedAt = ref.read(clockProvider)(),
      onShow: () {
        final pausedAt = _pausedAt;
        if (pausedAt != null && ref.read(clockProvider)().difference(pausedAt) > const Duration(seconds: 20)) {
          ref.read(dataRevisionProvider.notifier).bump();
        }
        unawaited(ref.read(coffeeQueueProvider.notifier).syncAll());
      },
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
