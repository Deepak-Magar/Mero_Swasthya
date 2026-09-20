import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/l10n/gen/app_localizations.dart';
import 'package:mero_swasthya/core/theme/app_theme.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/rules/triage.dart';
import 'package:mero_swasthya/features/shared/widgets/app_widgets.dart';
import 'package:mero_swasthya/shared/widgets/soft_card.dart';

/// The shared widgets carry two accessibility rules from spec §16 that are easy
/// to lose in a refactor, so they are pinned here.
Future<void> pumpIn(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) {
  return tester.pumpWidget(
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
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

void main() {
  group('TriageBanner', () {
    const red = TriageResult(
      level: TriageLevel.red,
      reasons: [
        TriageReason(
          code: 'SEVERE_ANAEMIA',
          en: 'Severe anaemia (Hb < 7)',
          np: 'गम्भीर रक्तअल्पता',
        ),
      ],
    );

    testWidgets('red uses colour AND an icon AND text', (tester) async {
      // Spec §16. Colour alone fails for a red-green colour deficiency, and
      // this banner decides whether somebody goes to hospital tonight.
      await pumpIn(tester, const TriageBanner(result: red));

      expect(find.byIcon(Icons.error), findsOneWidget);
      expect(
        find.textContaining('Refer NOW'),
        findsOneWidget,
        reason: 'the instruction must be in words',
      );
      expect(find.textContaining('Severe anaemia'), findsOneWidget);

      // Found on the phone in dark mode: the reason lines inherited the
      // theme's foreground and came out light grey on the banner's own pale
      // red. They have to carry the banner's colour, not the page's.
      //
      // They carry the darker `ink` of that level rather than the signal `fg`
      // the headline uses. #DC2626 on #FEF2F2 is 4.41:1 — fine for the bold
      // headline, short of the 4.5:1 body threshold for a wrapped sentence —
      // and these lines are the *reason* somebody is being sent to hospital.
      // Same hue, 7.60:1.
      final reason = tester.widget<Text>(find.textContaining('Severe anaemia'));
      expect(reason.style?.color, TriageColors.ink('red'));
      expect(
        reason.style?.color,
        isNot(Theme.of(tester.element(find.byType(TriageBanner)))
            .colorScheme
            .onSurface),
        reason: 'it must not fall back to the page foreground',
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(TriageBanner),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, TriageColors.redBg);
      expect((decoration.border! as Border).top.color, TriageColors.red);
    });

    testWidgets('green says so without shouting', (tester) async {
      await pumpIn(
        tester,
        const TriageBanner(result: TriageResult(level: TriageLevel.green)),
      );

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.textContaining('Routine'), findsOneWidget);
    });

    testWidgets('the reasons are shown in Nepali under the Nepali locale',
        (tester) async {
      await pumpIn(
        tester,
        const TriageBanner(result: red),
        locale: const Locale('ne'),
      );

      expect(find.textContaining('गम्भीर रक्तअल्पता'), findsOneWidget);
      expect(find.textContaining('Severe anaemia'), findsNothing);
    });
  });

  group('NumberStepper', () {
    testWidgets('it starts empty and never shows a fabricated zero',
        (tester) async {
      // An unmeasured haemoglobin must not read as 0 — triage treats that very
      // differently from "not taken".
      num? value;
      await pumpIn(
        tester,
        NumberStepper(
          label: 'Hb',
          value: null,
          min: 3,
          max: 20,
          onChanged: (v) => value = v,
        ),
      );

      expect(find.text('—'), findsOneWidget);
      expect(value, isNull);
    });

    testWidgets('the clinical thresholds are reachable by stepping',
        (tester) async {
      // Found on device: BP systolic (60..250 by 2) started at 155, so every
      // reachable value was odd and 140 / 150 / 160 — the exact numbers A.5
      // triages on — could not be entered at all.
      num? value;
      Widget stepper() => NumberStepper(
            label: 'BP systolic',
            value: value,
            min: 60,
            max: 250,
            step: 2,
            onChanged: (v) => value = v,
          );

      await pumpIn(tester, stepper());
      await tester.tap(find.byIcon(Icons.add_rounded));
      expect(value! % 2, 0, reason: 'the start must sit on the step grid');

      // Walk down to 150 and confirm it is hit exactly.
      var guard = 0;
      while (value! > 150 && guard++ < 100) {
        await pumpIn(tester, stepper());
        await tester.tap(find.byIcon(Icons.remove_rounded));
      }
      expect(value, 150);
    });

    testWidgets('BP diastolic can reach 90 and 110', (tester) async {
      num? value;
      Widget stepper() => NumberStepper(
            label: 'BP diastolic',
            value: value,
            min: 30,
            max: 160,
            step: 2,
            onChanged: (v) => value = v,
          );

      await pumpIn(tester, stepper());
      await tester.tap(find.byIcon(Icons.add_rounded));
      expect(value! % 2, 0);
    });

    testWidgets('a value off the step grid can still be typed in',
        (tester) async {
      // Spec §16 says never *require* typing, not that a value may be
      // unreachable: an odd diastolic of 95 is an ordinary reading.
      num? value;
      await pumpIn(
        tester,
        NumberStepper(
          label: 'BP diastolic',
          value: 96,
          min: 30,
          max: 160,
          step: 2,
          onChanged: (v) => value = v,
        ),
      );

      await tester.tap(find.text('96'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '95');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(value, 95);
    });

    testWidgets('a typed value outside the range is clamped, not dropped',
        (tester) async {
      num? value;
      await pumpIn(
        tester,
        NumberStepper(
          label: 'BP systolic',
          value: 120,
          min: 60,
          max: 250,
          step: 2,
          onChanged: (v) => value = v,
        ),
      );

      await tester.tap(find.text('120'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1500');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(value, 250);
    });

    testWidgets('the first tap lands in the middle of the range, not at zero',
        (tester) async {
      // Starting a weight stepper at 0 kg would need sixty taps to reach a
      // plausible number.
      num? value;
      await pumpIn(
        tester,
        NumberStepper(
          label: 'Weight',
          value: null,
          min: 25,
          max: 150,
          onChanged: (v) => value = v,
        ),
      );

      await tester.tap(find.byIcon(Icons.add_rounded));
      expect(value, greaterThan(25));
      expect(value, lessThan(150));
    });

    testWidgets('it will not step outside its range', (tester) async {
      num? value = 20;
      await pumpIn(
        tester,
        NumberStepper(
          label: 'Hb',
          value: 20,
          min: 3,
          max: 20,
          onChanged: (v) => value = v,
        ),
      );

      await tester.tap(find.byIcon(Icons.add_rounded));
      expect(value, 20, reason: 'the callback is not fired past the max');
    });

    testWidgets('a value can be cleared back to "not measured"',
        (tester) async {
      num? value = 9;
      var cleared = false;
      await pumpIn(
        tester,
        NumberStepper(
          label: 'Hb',
          value: value,
          min: 3,
          max: 20,
          onChanged: (v) {
            value = v;
            cleared = v == null;
          },
        ),
      );

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      expect(cleared, isTrue);
    });

    testWidgets('decimals are rendered to the requested precision',
        (tester) async {
      await pumpIn(
        tester,
        NumberStepper(
          label: 'Hb',
          value: 9.2,
          min: 3,
          max: 20,
          step: 0.1,
          decimals: 1,
          onChanged: (_) {},
        ),
      );

      expect(find.text('9.2'), findsOneWidget);
    });

    testWidgets('every control clears the 48 dp tap target', (tester) async {
      // Spec §16: minimum tap target 48 dp.
      await pumpIn(
        tester,
        NumberStepper(
          label: 'BP',
          value: 120,
          onChanged: (_) {},
        ),
      );

      for (final icon in [Icons.add_rounded, Icons.remove_rounded]) {
        final button = find.ancestor(
          of: find.byIcon(icon),
          matching: find.byType(IconButton),
        );
        final size = tester.getSize(button);
        expect(size.width, greaterThanOrEqualTo(AppTheme.minTapTarget));
        expect(size.height, greaterThanOrEqualTo(AppTheme.minTapTarget));
      }
    });
  });

  group('SoftCard', () {
    testWidgets('an accented card lays out inside an unbounded list',
        (tester) async {
      // Found on the phone, in a **release** build, on S09: every triaged
      // timeline row was invisible and the list scrolled through an empty
      // void, while untriaged rows rendered normally.
      //
      // The accent bar used to be a sibling in a `Row(crossAxisAlignment:
      // stretch)`, which asks the bar to match its sibling's height. A
      // `ListView` hands its children an unbounded height, so that resolves to
      // infinity — an assertion in debug, and silent garbage in release, which
      // is exactly why the widget tests of the day did not catch it.
      //
      // The card must therefore be measured in the shape that broke it: inside
      // a real scrollable, with a real height to report.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ListView(
              children: const [
                SoftCard(
                  accent: TriageColors.red,
                  child: Text('triaged row'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final size = tester.getSize(find.byType(SoftCard));
      expect(size.height.isFinite, isTrue, reason: 'an infinite row is the bug');
      expect(size.height, greaterThan(0));
      expect(size.height, lessThan(400), reason: 'one short row, not a void');
      expect(find.text('triaged row'), findsOneWidget);
    });

    testWidgets('an accented card is the same height as a plain one',
        (tester) async {
      // The accent is decoration, not layout: adding it must not change how
      // tall the row is, or a triaged item would sit out of rhythm with the
      // ones above and below it.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ListView(
              children: const [
                SoftCard(child: Text('plain')),
                SoftCard(accent: TriageColors.red, child: Text('accented')),
              ],
            ),
          ),
        ),
      );

      final heights = tester
          .widgetList<SoftCard>(find.byType(SoftCard))
          .map((card) => tester.getSize(find.byWidget(card)).height)
          .toList();

      expect(heights, hasLength(2));
      expect(heights[0], heights[1]);
    });
  });

  group('EmptyState', () {
    testWidgets('it shows a message and its primary action', (tester) async {
      await pumpIn(
        tester,
        EmptyState(
          icon: Icons.people_outline,
          title: 'No one here yet',
          body: 'Add a family member to begin',
          action: FilledButton(onPressed: () {}, child: const Text('Add')),
        ),
      );

      expect(find.text('No one here yet'), findsOneWidget);
      expect(find.text('Add a family member to begin'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add'), findsOneWidget);
    });
  });
}
