import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/features/shared/voice/speech_locale.dart';

/// Tier 3 — which recogniser locale a voice note uses.
///
/// The only part of dictation worth testing, and the part with consequences:
/// asking for `en-IN` when a Nepali recogniser is installed turns "पेट दुख्यो"
/// into gibberish, and asking for `ne-NP` when it is not produces silence.
void main() {
  group('choosing a locale', () {
    test('a Nepali recogniser wins', () {
      expect(
        chooseSpeechLocale(
          hasRecogniser: true,
          availableLocaleIds: const ['en_US', 'ne_NP', 'hi_IN'],
        ),
        SpeechLocaleChoice.nepali,
      );
    });

    test('it matches however the vendor spells the id', () {
      // Android reports `ne_NP`, other engines `ne-NP`, and case varies.
      for (final id in ['ne_NP', 'ne-NP', 'ne', 'NE_np']) {
        expect(
          chooseSpeechLocale(
            hasRecogniser: true,
            availableLocaleIds: [id],
          ),
          SpeechLocaleChoice.nepali,
          reason: id,
        );
      }
    });

    test('without Nepali it falls back rather than failing', () {
      expect(
        chooseSpeechLocale(
          hasRecogniser: true,
          availableLocaleIds: const ['en_US', 'hi_IN'],
        ),
        SpeechLocaleChoice.fallback,
      );
    });

    test('no recogniser at all means the button is hidden', () {
      expect(
        chooseSpeechLocale(
          hasRecogniser: false,
          availableLocaleIds: const ['ne_NP'],
        ),
        SpeechLocaleChoice.unavailable,
        reason: 'listed locales are worthless if it will not listen',
      );
    });

    test('a recogniser that names no locales still gets offered', () {
      // Some Android builds report nothing. The system default is usually
      // something, and hiding the button would be the worse guess.
      expect(
        chooseSpeechLocale(hasRecogniser: true, availableLocaleIds: const []),
        SpeechLocaleChoice.fallback,
      );
    });

    test('a language that merely starts with the same letters is not Nepali',
        () {
      // `nl` is Dutch. A prefix match on two letters has to be exact.
      expect(
        chooseSpeechLocale(
          hasRecogniser: true,
          availableLocaleIds: const ['nl_NL', 'new_IN'],
        ),
        SpeechLocaleChoice.fallback,
      );
    });
  });

  group('the id handed to the plugin', () {
    test('is the device\'s own spelling when it has one', () {
      // Some engines reject an id they did not themselves advertise.
      expect(
        localeIdFor(SpeechLocaleChoice.nepali, const ['ne-NP', 'en_US']),
        'ne-NP',
      );
    });

    test('falls back to the canonical id when the device named none', () {
      expect(localeIdFor(SpeechLocaleChoice.nepali, const []), nepaliLocale);
      expect(localeIdFor(SpeechLocaleChoice.fallback, const []), fallbackLocale);
    });

    test('prefers Indian English, then any English', () {
      expect(
        localeIdFor(SpeechLocaleChoice.fallback, const ['en_US', 'en_IN']),
        'en_IN',
      );
      expect(
        localeIdFor(SpeechLocaleChoice.fallback, const ['en_GB']),
        'en_GB',
      );
    });

    test('asks for nothing when there is nothing to ask for', () {
      expect(
        localeIdFor(SpeechLocaleChoice.unavailable, const ['ne_NP']),
        isNull,
      );
    });
  });
}
