import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import 'speech_locale.dart';

/// Tier 3 — dictate a note in Nepali.
///
/// The transcript is **appended to the text field and left editable**: nothing
/// is saved that the person dictating has not had a chance to read. That is the
/// whole design. A recogniser that mishears a drug name is a certainty, and a
/// note that goes into a medical record without being read once would be worse
/// than no dictation at all.
///
/// Nothing about the payload changes — this writes into the same `notes` string
/// S22 has always had.
class VoiceNoteButton extends StatefulWidget {
  const VoiceNoteButton({
    super.key,
    required this.controller,
    this.speech,
  });

  /// The field the transcript is appended to.
  final TextEditingController controller;

  /// Injectable for tests; the real one is created lazily.
  final SpeechToText? speech;

  @override
  State<VoiceNoteButton> createState() => _VoiceNoteButtonState();
}

class _VoiceNoteButtonState extends State<VoiceNoteButton> {
  late final SpeechToText _speech = widget.speech ?? SpeechToText();

  SpeechLocaleChoice? _choice;
  List<String> _localeIds = const [];
  bool _listening = false;
  bool _initialising = true;

  /// So the "no Nepali voice" line is said once, not on every tap.
  bool _toldAboutFallback = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final available = await _speech.initialize(
        onError: (e) => debugPrint('Speech error: ${e.errorMsg}'),
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _listening = false);
          }
        },
      );

      final locales = available ? await _speech.locales() : <LocaleName>[];
      if (!mounted) return;

      setState(() {
        _localeIds = locales.map((l) => l.localeId).toList();
        _choice = chooseSpeechLocale(
          hasRecogniser: available,
          availableLocaleIds: _localeIds,
        );
        _initialising = false;
      });
    } on Object catch (error) {
      debugPrint('Speech unavailable: $error');
      if (!mounted) return;
      setState(() {
        _choice = SpeechLocaleChoice.unavailable;
        _initialising = false;
      });
    }
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    final choice = _choice;
    if (choice == null || choice == SpeechLocaleChoice.unavailable) return;

    if (choice == SpeechLocaleChoice.fallback && !_toldAboutFallback) {
      _toldAboutFallback = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.of(context).voiceNoteFallback)),
      );
    }

    setState(() => _listening = true);
    try {
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: localeIdFor(choice, _localeIds),
          // Partial results would rewrite the field on every syllable and make
          // it impossible to edit while talking.
          partialResults: false,
          listenMode: ListenMode.dictation,
        ),
        onResult: (result) {
          if (!result.finalResult) return;
          _append(result.recognizedWords);
        },
      );
    } on Object catch (error) {
      debugPrint('Speech listen failed: $error');
      if (!mounted) return;
      setState(() => _listening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.of(context).voiceNoteFailed)),
      );
    }
  }

  /// Append rather than replace, so dictating twice adds a second sentence and
  /// anything already typed survives.
  void _append(String words) {
    final text = words.trim();
    if (text.isEmpty) return;

    final existing = widget.controller.text.trimRight();
    final joined = existing.isEmpty ? text : '$existing $text';
    widget.controller
      ..text = joined
      ..selection = TextSelection.collapsed(offset: joined.length);
  }

  @override
  void dispose() {
    if (_listening) _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A button that does nothing is worse than no button: a phone with no
    // recogniser simply does not get one.
    if (_initialising || _choice == SpeechLocaleChoice.unavailable) {
      return const SizedBox.shrink();
    }

    final l10n = L.of(context);
    return IconButton(
      icon: Icon(_listening ? Icons.stop_circle_outlined : Icons.mic_none),
      color: _listening ? Theme.of(context).colorScheme.error : null,
      tooltip: _listening ? l10n.voiceNoteStop : l10n.voiceNoteStart,
      onPressed: _toggle,
    );
  }
}
