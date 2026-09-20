import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/gen/app_localizations.dart';
import 'core/l10n/locale_controller.dart';
import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'router.dart';

/// Spec §4: MaterialApp.router, theme, localization delegates.
class MeroSwasthyaApp extends ConsumerStatefulWidget {
  const MeroSwasthyaApp({super.key});

  @override
  ConsumerState<MeroSwasthyaApp> createState() => _MeroSwasthyaAppState();
}

class _MeroSwasthyaAppState extends ConsumerState<MeroSwasthyaApp> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();

    // Spec §7 lists "app resume" as a sync trigger, alongside connectivity, the
    // 60-second timer and a manual kick. Coming back to the app after a walk
    // between houses is exactly when there is signal again.
    //
    // The engine ignores a kick until `start()` has run at PIN unlock, so this
    // cannot fire a cycle against a locked database.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(syncEngineProvider).onResume(),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(effectiveLocaleProvider);

    return MaterialApp.router(
      title: 'Mero Swasthya',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: locale,
      supportedLocales: L.supportedLocales,
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      onGenerateTitle: (context) => L.of(context).appTitle,
    );
  }
}
