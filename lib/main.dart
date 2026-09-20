import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nepali_utils/nepali_utils.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/providers.dart';
import 'data/local/app_database.dart';

/// Spec §4: `runApp` with a `ProviderScope`; reads the dart-defines
/// `API_BASE_URL` and `MOCK_API`.
///
/// Two things are constructed here rather than in a provider, because both have
/// to exist before the first frame: the preferences the base URL lives in, and
/// the database.
///
/// Spec §6.1 would have the database key derived from the PIN. Session 1 ships
/// it unencrypted — the spec allows that fallback — so it can be opened here;
/// with SQLCipher this moves behind the unlock in S04, which is why the sync
/// engine is already started there rather than in `main`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = await AppConfig.load();
  final database = AppDatabase();

  // nepali_utils keeps a global language used by its formatters and by the
  // date picker; the locale controller overrides it when the user switches.
  NepaliUtils().language = Language.nepali;

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        databaseProvider.overrideWithValue(database),
      ],
      child: const MeroSwasthyaApp(),
    ),
  );
}
