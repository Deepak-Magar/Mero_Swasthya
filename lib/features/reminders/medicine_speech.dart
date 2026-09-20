import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// What happened when the app tried to read a prescription out loud.
enum SpeechResult {
  /// Spoken in Nepali, which is the point.
  nepali,

  /// The device has no Nepali voice; spoken in Indian English instead. The UI
  /// says so once rather than pretending.
  fallback,

  /// Nothing came out — no engine, or the platform refused.
  unavailable,
}

/// Tier 2 — read a prescription aloud (S22 / spec §16 "low literacy").
///
/// A printed dose is useless to somebody who cannot read it, and the person
/// most likely to be taking four tablets a day is the person least likely to
/// read the label. So the drug name and the Nepali instruction are spoken.
///
/// Nepali text-to-speech is not on every Android phone, and the honest
/// behaviour when it is missing is to say something in a language that *is*
/// installed and to admit the swap — not to fail silently, and certainly not
/// to crash.
class MedicineSpeech {
  MedicineSpeech({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  static const String nepali = 'ne-NP';

  /// Indian English: closer to how a Nepali speaker expects English words like
  /// drug names to be pronounced than the US voice most phones default to.
  static const String fallbackLocale = 'en-IN';

  final FlutterTts _tts;

  /// Cached so the "no Nepali voice" note is decided once rather than flashing
  /// on and off between rows.
  bool? _hasNepali;

  Future<bool> _nepaliAvailable() async {
    final cached = _hasNepali;
    if (cached != null) return cached;

    try {
      final available = await _tts.isLanguageAvailable(nepali);
      return _hasNepali = available == true;
    } on Object catch (error) {
      debugPrint('TTS language query failed: $error');
      return _hasNepali = false;
    }
  }

  /// Speak [drugName] and [instructionsNp].
  ///
  /// The drug name is said first because it is the thing being identified; the
  /// instruction follows, in Nepali, because that is the thing being acted on.
  Future<SpeechResult> speak({
    required String drugName,
    String? instructionsNp,
  }) async {
    final text = [
      drugName,
      if (instructionsNp != null && instructionsNp.isNotEmpty) instructionsNp,
    ].join('. ');
    if (text.trim().isEmpty) return SpeechResult.unavailable;

    final useNepali = await _nepaliAvailable();

    try {
      await _tts.stop();
      await _tts.setLanguage(useNepali ? nepali : fallbackLocale);
      // Slower than default: this is a dose, and the listener may be repeating
      // it back to themselves.
      await _tts.setSpeechRate(0.45);
      await _tts.speak(text);
      return useNepali ? SpeechResult.nepali : SpeechResult.fallback;
    } on Object catch (error) {
      debugPrint('TTS failed: $error');
      return SpeechResult.unavailable;
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object catch (error) {
      debugPrint('TTS stop failed: $error');
    }
  }
}
