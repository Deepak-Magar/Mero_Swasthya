/// Two shapes repeat across Part A's responses: `data.items` for a list, and
/// `data.<name>` for a single entity. These keep the endpoint classes down to
/// one readable line each and put the casts in one place.
extension ApiJson on Map<String, dynamic> {
  /// `{ "items": [ … ] }`. A missing or non-list `items` reads as empty rather
  /// than throwing: an empty list renders as an empty state, whereas a crash in
  /// a refresh would take out a screen that already has cached rows.
  List<T> itemsOf<T>(T Function(Map<String, dynamic> json) fromJson) {
    final items = this['items'];
    if (items is! List) return <T>[];
    return items
        .whereType<Map>()
        .map((e) => fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// `{ "<key>": { … } }` — required, because the caller asked for that entity.
  T objectOf<T>(String key, T Function(Map<String, dynamic> json) fromJson) {
    final value = this[key];
    if (value is! Map) {
      throw FormatException('Expected object "$key" in the response', this);
    }
    return fromJson(value.cast<String, dynamic>());
  }

  /// `{ "<key>": { … } | null }`.
  T? maybeObjectOf<T>(
    String key,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    final value = this[key];
    if (value is! Map) return null;
    return fromJson(value.cast<String, dynamic>());
  }
}
