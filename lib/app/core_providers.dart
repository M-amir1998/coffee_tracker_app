import 'package:coffee_tracker/core/config/app_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Overridden in `bootstrap.dart` (and in tests).
final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment());

/// Overridden in `bootstrap.dart` once Supabase is initialised.
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => throw StateError('Supabase has not been initialised'),
);

/// Device-local key/value storage. Overridden in `bootstrap.dart`.
final sharedPreferencesProvider = Provider<SharedPreferencesWithCache>(
  (ref) => throw StateError('SharedPreferences has not been initialised'),
);

/// Injectable clock so that time-dependent logic can be tested.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
