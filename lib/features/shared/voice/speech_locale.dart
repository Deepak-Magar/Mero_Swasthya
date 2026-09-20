/// Tier 3 — which recogniser locale a voice note should use.
///
/// Split out as a pure function because it is the only part of dictation worth
/// testing: the rest is a platform plugin. The decision is small and the
/// consequences are not — picking `en-IN` when a Nepali recogniser is installed
/// would turn "पेट दुख्यो" into gibberish, and picking `ne-NP` when it is not
/// would silently produce nothing at all.
library;

/// What the app decided to do about dictation.
enum SpeechLocaleChoice {
  /// A Nepali recogniser is installed. Use it and say nothing.
  nepali,

  /// No Nepali, but some other recogniser exists. Use Indian English and tell
  /// the user once — a health worker who dictates in Nepali and gets English
  /// words back deserves to know why.
  fallback,

  /// Nothing to dictate with. Hide the microphone rather than offering a
  /// button that does nothing.
  unavailable,
}

/// The locale identifiers the app asks for, in order of preference.
const String nepaliLocale = 'ne_NP';
const String fallbackLocale = 'en_IN';

/// The decision, given what the device reports.
///
/// [availableLocaleIds] is whatever `speech_to_text` lists — the plugin returns
/// underscored ids on Android (`ne_NP`) and hyphenated ones elsewhere, and
/// different vendors disagree about case, so matching is deliberately loose.
/// [hasRecogniser] is the plugin's own "is speech available at all" answer; a
/// device can report locales and still refuse to listen.
SpeechLocaleChoice chooseSpeechLocale({
  required bool hasRecogniser,
  required List<String> availableLocaleIds,
}) {
  if (!hasRecogniser) return SpeechLocaleChoice.unavailable;

  if (_contains(availableLocaleIds, 'ne')) return SpeechLocaleChoice.nepali;

  // A recogniser exists but not a Nepali one. English is worth offering: a
  // health worker's notes are full of drug names and numbers, which survive
  // the wrong language better than prose does.
  if (availableLocaleIds.isNotEmpty) return SpeechLocaleChoice.fallback;

  // The plugin says it can listen but names no locales. Some Android builds do
  // this; treating it as English is better than hiding the button, because the
  // system default is usually something.
  return SpeechLocaleChoice.fallback;
}

/// The locale id to hand the plugin for a given choice, or null when there is
/// nothing to ask for.
///
/// Returns the device's *own* spelling where it has one, because some engines
/// reject an id they did not themselves advertise.
String? localeIdFor(
  SpeechLocaleChoice choice,
  List<String> availableLocaleIds,
) {
  return switch (choice) {
    SpeechLocaleChoice.nepali =>
      _match(availableLocaleIds, 'ne') ?? nepaliLocale,
    SpeechLocaleChoice.fallback =>
      _match(availableLocaleIds, 'en_IN') ??
          _match(availableLocaleIds, 'en') ??
          fallbackLocale,
    SpeechLocaleChoice.unavailable => null,
  };
}

/// True when any advertised id starts with [prefix], ignoring case and the
/// underscore/hyphen difference.
bool _contains(List<String> ids, String prefix) =>
    _match(ids, prefix) != null;

String? _match(List<String> ids, String prefix) {
  final wanted = _normalise(prefix);
  for (final id in ids) {
    final normalised = _normalise(id);
    if (normalised == wanted || normalised.startsWith('${wanted}_')) return id;
  }
  return null;
}

String _normalise(String id) => id.replaceAll('-', '_').toLowerCase();
