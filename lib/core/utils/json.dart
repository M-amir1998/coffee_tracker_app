typedef Json = Map<String, dynamic>;

/// Typed accessors for JSON returned by the database functions.
extension JsonRead on Json {
  String str(String key) => this[key] as String;

  String? strOrNull(String key) => this[key] as String?;

  int integer(String key) => (this[key] as num).toInt();

  int intOr(String key, [int fallback = 0]) => (this[key] as num?)?.toInt() ?? fallback;

  int? intOrNull(String key) => (this[key] as num?)?.toInt();

  bool boolOr(String key, [bool fallback = false]) => this[key] as bool? ?? fallback;

  DateTime date(String key) => DateTime.parse(this[key] as String);

  DateTime? dateOrNull(String key) {
    final value = this[key] as String?;
    return value == null ? null : DateTime.parse(value);
  }

  Json obj(String key) => asJson(this[key]);

  Json? objOrNull(String key) => this[key] == null ? null : asJson(this[key]);

  List<Json> list(String key) => asJsonList(this[key]);
}

Json asJson(Object? value) => (value as Map).cast<String, dynamic>();

List<Json> asJsonList(Object? value) =>
    ((value as List?) ?? const <Object?>[]).map(asJson).toList(growable: false);
