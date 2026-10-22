import 'dart:async';

import 'package:coffee_tracker/app/app.dart';
import 'package:coffee_tracker/app/core_providers.dart';
import 'package:coffee_tracker/core/config/app_config.dart';
import 'package:coffee_tracker/core/errors/app_failure.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Initialises platform services and starts the app.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter error: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    return true; // handled: keep the app running
  };

  final config = AppConfig.fromEnvironment();
  final preferences = await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());

  final overrides = [
    appConfigProvider.overrideWithValue(config),
    sharedPreferencesProvider.overrideWithValue(preferences),
  ];

  if (config.isValid) {
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    );
    overrides.add(supabaseClientProvider.overrideWithValue(Supabase.instance.client));
  }

  runApp(
    ProviderScope(
      overrides: overrides,
      // Network failures retry a few times with back-off; business errors are
      // shown immediately.
      retry: (count, error) => toFailure(error).isRetryable && count < 3 ? Duration(seconds: 1 << count) : null,
      child: const CoffeeTrackerApp(),
    ),
  );
}

void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (family, asset) in [
      ('Inter', 'assets/fonts/OFL-Inter.txt'),
      ('Fraunces', 'assets/fonts/OFL-Fraunces.txt'),
    ]) {
      final text = await rootBundle.loadString(asset);
      yield LicenseEntryWithLineBreaks([family], text);
    }
  });
}
