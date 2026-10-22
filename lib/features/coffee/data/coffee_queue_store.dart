import 'dart:convert';

import 'package:coffee_tracker/core/utils/json.dart';
import 'package:coffee_tracker/features/coffee/domain/pending_coffee.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the offline queue with shared_preferences, which is available on
/// every platform (NSUserDefaults, Android DataStore, localStorage on the web,
/// a JSON file on Windows/Linux). The queue is small and bounded.
class CoffeeQueueStore {
  CoffeeQueueStore(this._preferences);

  static const storageKey = 'pending_coffees_v1';

  final SharedPreferencesWithCache _preferences;

  List<PendingCoffee> load() {
    final raw = _preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      // Entries without an owner cannot be attributed to anyone, so they are never sent.
      return asJsonList(jsonDecode(raw))
          .where((json) => json['user_id'] is String)
          .map(PendingCoffee.fromJson)
          .toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> save(List<PendingCoffee> items) async {
    if (items.isEmpty) {
      await _preferences.remove(storageKey);
    } else {
      await _preferences.setString(storageKey, jsonEncode([for (final item in items) item.toJson()]));
    }
  }
}
