import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mero_swasthya/core/l10n/gen/app_localizations.dart';
import 'package:mero_swasthya/core/theme/app_theme.dart';

/// The minimum a Tier-2 widget needs around it: localisations, the app theme
/// and a `ProviderScope`.
///
/// Shared so a screen under test is wrapped the same way every time — a test
/// that quietly built a different `MaterialApp` would be testing a different
/// widget from the one that ships.
Widget wrapForTest(
  Widget child, {
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: locale,
      theme: AppTheme.light(),
      supportedLocales: L.supportedLocales,
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

/// The same shell, but hosting a full screen that brings its own `Scaffold`.
///
/// Screens under test push routes, so a `Navigator` has to be real — a
/// `MaterialApp` with the screen as `home` gives them one without dragging the
/// whole router and its auth redirect into the test.
Widget appShellForTest(Widget screen, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    theme: AppTheme.light(),
    supportedLocales: L.supportedLocales,
    localizationsDelegates: const [
      L.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: screen,
  );
}

/// Pump a bounded number of frames instead of `pumpAndSettle`.
///
/// Several screens keep a widget on-stage whose animation never comes to rest
/// (a progress indicator, a shimmer), and `pumpAndSettle` waits for a quiet
/// tree that will never arrive. A handful of frames is enough for the Drift
/// streams and the providers behind them to deliver.
Future<void> settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Unmount the tree inside the test body.
///
/// Disposing drift's stream store schedules a zero-duration timer; a test that
/// ends before it fires is reported as a leaked timer rather than a pass.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
}
