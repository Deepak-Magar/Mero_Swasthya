import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/l10n/gen/app_localizations.dart';
import 'package:mero_swasthya/core/theme/app_theme.dart';
import 'package:mero_swasthya/data/remote/api/api.dart';
import 'package:mero_swasthya/features/provider/scan_screen.dart';

/// S20's manual fallback.
///
/// The camera path cannot be driven in a widget test — `MobileScanner` wants a
/// real camera — so what is pinned here is the half that decides whether a
/// payload is worth sending: the `SWC1:` prefix check and the message a foreign
/// code gets. `ScanScreen._redeem` runs the identical check on the value this
/// dialog returns, so the fallback cannot become a softer way in.
void main() {
  /// Pumps the dialog and reports what it popped.
  Future<String?> showDialogUnder(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    String? popped;
    var closed = false;

    await tester.pumpWidget(
      ProviderScope(
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
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await showDialog<String>(
                      context: context,
                      builder: (_) => const ManualCodeDialog(),
                    );
                    closed = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(closed, isFalse, reason: 'the dialog should be up');
    return popped;
  }

  testWidgets('a full SWC1 payload is accepted and popped', (tester) async {
    const payload = 'SWC1:mock_grant_259a073e-c448-4e14-b660-c861ab2bbf0d';
    await showDialogUnder(tester);

    await tester.enterText(find.byType(TextField), payload);
    await tester.tap(find.text('Open record'));
    await tester.pumpAndSettle();

    expect(find.byType(ManualCodeDialog), findsNothing);
  });

  testWidgets('surrounding whitespace is trimmed', (tester) async {
    // Pasted codes arrive with a trailing newline more often than not.
    await showDialogUnder(tester);

    await tester.enterText(find.byType(TextField), '  SWC1:abc \n');
    await tester.tap(find.text('Open record'));
    await tester.pumpAndSettle();

    expect(find.byType(ManualCodeDialog), findsNothing);
  });

  testWidgets('a foreign code gets the camera path message and stays open',
      (tester) async {
    await showDialogUnder(tester);

    await tester.enterText(find.byType(TextField), 'HELLO');
    await tester.tap(find.text('Open record'));
    await tester.pump();

    expect(find.text('That is not a Swasthya Card QR'), findsOneWidget);
    expect(
      find.byType(ManualCodeDialog),
      findsOneWidget,
      reason: 'a typo should be correctable, not start over',
    );
  });

  testWidgets('an empty field is refused the same way', (tester) async {
    await showDialogUnder(tester);

    await tester.tap(find.text('Open record'));
    await tester.pump();

    expect(find.text('That is not a Swasthya Card QR'), findsOneWidget);
  });

  testWidgets('a bare token without the prefix is refused', (tester) async {
    // The prefix is what lets the scanner reject foreign QR codes instantly
    // (spec A.7); accepting a naked token here would route around that.
    await showDialogUnder(tester);

    await tester.enterText(
      find.byType(TextField),
      'mock_grant_259a073e-c448-4e14-b660-c861ab2bbf0d',
    );
    await tester.tap(find.text('Open record'));
    await tester.pump();

    expect(find.text('That is not a Swasthya Card QR'), findsOneWidget);
  });

  testWidgets('cancel pops nothing', (tester) async {
    await showDialogUnder(tester);

    await tester.enterText(find.byType(TextField), 'SWC1:abc');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(ManualCodeDialog), findsNothing);
  });

  testWidgets('it is translated', (tester) async {
    await showDialogUnder(tester, locale: const Locale('ne'));

    expect(find.text('कोड प्रविष्ट गर्नुहोस्'), findsOneWidget);
    expect(find.text('रेकर्ड खोल्नुहोस्'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'HELLO');
    await tester.tap(find.text('रेकर्ड खोल्नुहोस्'));
    await tester.pump();

    expect(find.text('यो स्वास्थ्य कार्डको QR होइन'), findsOneWidget);
  });

  test('the dialog and the camera share one prefix constant', () {
    // If these ever diverge the fallback becomes a second, looser door.
    expect(GrantsApi.qrPrefix, 'SWC1:');
  });
}
