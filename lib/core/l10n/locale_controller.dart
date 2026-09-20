import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

/// Spec §13: default locale = device locale if ne/en, else ne. The toggle in
/// S23 (and on the phone-entry screen) overrides it and the choice is persisted.
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() {
    final code = ref.read(appConfigProvider).localeCode;
    return code == null ? null : Locale(code);
  }

  /// null restores "follow the device".
  Future<void> setLocale(Locale? locale) async {
    await ref.read(appConfigProvider).setLocaleCode(locale?.languageCode);
    state = locale;
  }

  Future<void> toggle() async {
    final current = state?.languageCode ?? resolveDeviceLocale().languageCode;
    await setLocale(Locale(current == 'ne' ? 'en' : 'ne'));
  }

  /// The locale actually in force, with the spec's ne fallback applied.
  static Locale resolveDeviceLocale() {
    final device = PlatformDispatcher.instance.locale.languageCode;
    return Locale(device == 'en' ? 'en' : 'ne');
  }
}

final localeControllerProvider =
    NotifierProvider<LocaleController, Locale?>(LocaleController.new);

/// The effective locale: explicit choice, else the device-derived fallback.
final effectiveLocaleProvider = Provider<Locale>((ref) {
  return ref.watch(localeControllerProvider) ??
      LocaleController.resolveDeviceLocale();
});
