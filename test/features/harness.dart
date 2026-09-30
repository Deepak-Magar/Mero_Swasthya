import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mero_swasthya/core/l10n/gen/app_localizations.dart';
import 'package:mero_swasthya/core/theme/app_theme.dart';
import 'package:mero_swasthya/router.dart';

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

/// The same shell around a router, for the screens that only make sense
/// inside one — the provider shell's tabs, and anything that `context.go`es.
Widget routerAppForTest(GoRouter router, {Locale locale = const Locale('en')}) {
  return MaterialApp.router(
    routerConfig: router,
    locale: locale,
    theme: AppTheme.light(),
    supportedLocales: L.supportedLocales,
    localizationsDelegates: const [
      L.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
  );
}

/// The real provider shell — its four branches, paths and back behaviour —
/// with every screen it pushes replaced by a stub that names itself.
///
/// The scanner is the reason: `/provider/scan` is a live camera, which a
/// widget test has no plugin for. Each stub renders `stub:<name>` plus the
/// query string, so a test can assert both where it went and what it asked
/// for.
GoRouter providerRouterForTest({String initialLocation = '/provider'}) {
  GoRoute stub(String path, String name) => GoRoute(
        path: path,
        builder: (_, state) => _StubScreen(
          name: name,
          query: state.uri.query,
          id: state.pathParameters['id'],
        ),
      );

  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      providerShellRoute(),
      stub('/provider/scan', 'scan'),
      stub('/provider/patient/:id', 'patient'),
      stub('/provider/patient/:id/visit/new', 'visit'),
      stub('/provider/visits/today', 'visits'),
      stub('/provider/dashboard', 'dashboard'),
      stub('/patient/:id/pregnancy/new', 'pregnancy'),
      stub('/sync', 'sync'),
      stub('/settings', 'settings'),
      stub('/family', 'family'),
    ],
  );
}

class _StubScreen extends StatelessWidget {
  const _StubScreen({required this.name, required this.query, this.id});

  final String name;
  final String query;
  final String? id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'stub:$name'
          '${id == null ? '' : ' $id'}'
          '${query.isEmpty ? '' : ' ?$query'}',
        ),
      ),
    );
  }
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
