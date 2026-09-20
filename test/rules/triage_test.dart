import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/domain/rules/rules.dart';
import 'package:mero_swasthya/domain/rules/triage.dart';

/// Spec A.6 cases 3–11, the shared triage tests. The backend runs the same
/// cases against its TypeScript implementation; if the two disagree, a health
/// worker in a village sees a different colour from the record on the server.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Rules rules;

  setUpAll(() async => rules = await Rules.loadFromAsset());

  Pregnancy pregnancy({List<String> riskFactors = const []}) => Pregnancy(
        id: 'pg1',
        patientId: 'p1',
        lmp: '2026-02-20',
        edd: '2026-11-27',
        riskFactors: riskFactors,
        riskLevel: riskLevelFor(riskFactors),
      );

  TriageResult run({
    Findings? findings,
    List<String> dangerSigns = const [],
    List<String> riskFactors = const [],
    int gestationalAgeDays = 210,
  }) {
    return triage(
      findings: findings,
      dangerSigns: dangerSigns,
      pregnancy: pregnancy(riskFactors: riskFactors),
      gestationalAgeDays: gestationalAgeDays,
      rules: rules,
    );
  }

  group('A.6 case 3 — BP 150/95 with severe headache', () {
    late TriageResult result;
    setUp(() {
      result = run(
        findings: const Findings(bpSys: 150, bpDia: 95),
        dangerSigns: const ['SEVERE_HEADACHE_BLURRED_VISION'],
      );
    });

    test('it is red', () => expect(result.level, TriageLevel.red));

    test('the reasons include the pre-eclampsia rule', () {
      expect(
        result.reasonsEn,
        contains(
          'BP ≥ 140/90 with proteinuria or severe headache — '
          'possible pre-eclampsia',
        ),
      );
    });

    test('the danger sign itself is also named', () {
      // It is red in the rule table on its own, so it appears first.
      expect(result.reasonsEn.first, 'Severe headache with blurred vision');
    });

    test('a referral is called for', () => expect(result.needsReferral, isTrue));
  });

  group('A.6 case 4 — BP 142/88, nothing else', () {
    late TriageResult result;
    setUp(() => result = run(findings: const Findings(bpSys: 142, bpDia: 88)));

    test('it is amber', () => expect(result.level, TriageLevel.amber));

    test('the only reason is the raised BP', () {
      expect(result.reasonsEn, ['Raised BP (≥140/90)']);
    });

    test('no referral is forced', () {
      expect(result.needsReferral, isFalse);
    });
  });

  group('A.6 case 5 — Hb 6.8', () {
    test('it is red for severe anaemia', () {
      final result = run(findings: const Findings(hbGdl: 6.8));

      expect(result.level, TriageLevel.red);
      expect(result.reasonsEn, contains('Severe anaemia (Hb < 7)'));
    });
  });

  group('A.6 case 6 — Hb 9.2', () {
    test('it is amber', () {
      final result = run(findings: const Findings(hbGdl: 9.2));

      expect(result.level, TriageLevel.amber);
      expect(result.reasonsEn, contains('Anaemia (Hb 7–9.9)'));
    });
  });

  group('A.6 case 7 — absent fetal movement at 150 days', () {
    test('it is red', () {
      final result = run(
        findings: const Findings(fetalMovement: FetalMovement.absent),
        gestationalAgeDays: 150,
      );

      expect(result.level, TriageLevel.red);
      expect(result.reasonsEn, contains('Absent fetal movement'));
    });
  });

  group('A.6 case 8 — absent fetal movement at 120 days', () {
    test('that rule does not fire before 20 weeks', () {
      // There is nothing to feel yet, so absence means nothing.
      final result = run(
        findings: const Findings(fetalMovement: FetalMovement.absent),
        gestationalAgeDays: 120,
      );

      expect(result.reasonsEn, isNot(contains('Absent fetal movement')));
      expect(result.level, TriageLevel.green);
    });

    test('the rest is still evaluated', () {
      final result = run(
        findings: const Findings(
          fetalMovement: FetalMovement.absent,
          bpSys: 145,
        ),
        gestationalAgeDays: 120,
      );

      expect(result.level, TriageLevel.amber);
      expect(result.reasonsEn, ['Raised BP (≥140/90)']);
    });

    test('exactly 140 days is the threshold, and it fires', () {
      expect(
        run(
          findings: const Findings(fetalMovement: FetalMovement.absent),
          gestationalAgeDays: 140,
        ).level,
        TriageLevel.red,
      );
      expect(
        run(
          findings: const Findings(fetalMovement: FetalMovement.absent),
          gestationalAgeDays: 139,
        ).level,
        TriageLevel.green,
      );
    });
  });

  group('A.6 case 9 — swelling of face and hands, no findings', () {
    test('it is amber from the danger-sign table', () {
      final result = run(dangerSigns: const ['SWELLING_FACE_HANDS']);

      expect(result.level, TriageLevel.amber);
      expect(result.reasonsEn, ['Swelling of face and hands']);
    });
  });

  group('A.6 case 10 — previous caesarean, nothing else', () {
    test('it is amber because the pregnancy is high risk', () {
      final result = run(riskFactors: const ['PREV_CS']);

      expect(result.level, TriageLevel.amber);
      expect(
        result.reasonsEn,
        contains('High-risk pregnancy (risk factors present)'),
      );
    });
  });

  group('A.6 case 11 — nothing at all', () {
    test('it is green with no reasons', () {
      final result = run();

      expect(result.level, TriageLevel.green);
      expect(result.reasonsEn, isEmpty);
      expect(result.needsReferral, isFalse);
    });

    test('empty findings are still green', () {
      final result = run(findings: const Findings());

      expect(result.level, TriageLevel.green);
      expect(result.reasonsEn, isEmpty);
    });
  });

  group('red suppresses the amber rules', () {
    test('a red pregnancy is not also told it is amber', () {
      // Spec §12: the amber block only runs when nothing red fired.
      final result = run(
        findings: const Findings(
          bpSys: 170,
          bpDia: 115,
          hbGdl: 8.5,
          urineProtein: UrineProtein.two,
        ),
        riskFactors: const ['PREV_CS'],
      );

      expect(result.level, TriageLevel.red);
      expect(result.reasonsEn, contains('Severe hypertension (≥160/110)'));
      expect(result.reasonsEn, isNot(contains('Anaemia (Hb 7–9.9)')));
      expect(result.reasonsEn, isNot(contains('Proteinuria')));
      expect(
        result.reasonsEn,
        isNot(contains('High-risk pregnancy (risk factors present)')),
      );
    });

    test('an amber danger sign is not added once something is red', () {
      final result = run(
        dangerSigns: const ['VAGINAL_BLEEDING', 'SWELLING_FACE_HANDS'],
      );

      expect(result.level, TriageLevel.red);
      expect(result.reasonsEn, ['Vaginal bleeding']);
    });
  });

  group('the individual thresholds', () {
    test('severe hypertension fires on either number alone', () {
      expect(
        run(findings: const Findings(bpSys: 160, bpDia: 80)).level,
        TriageLevel.red,
      );
      expect(
        run(findings: const Findings(bpSys: 120, bpDia: 110)).level,
        TriageLevel.red,
      );
      expect(
        run(findings: const Findings(bpSys: 159, bpDia: 109)).level,
        TriageLevel.amber,
      );
    });

    test('raised BP with proteinuria is red, without it amber', () {
      expect(
        run(
          findings: const Findings(
            bpSys: 145,
            bpDia: 92,
            urineProtein: UrineProtein.one,
          ),
        ).level,
        TriageLevel.red,
      );
      expect(
        run(findings: const Findings(bpSys: 145, bpDia: 92)).level,
        TriageLevel.amber,
      );
    });

    test('a trace of protein is not proteinuria', () {
      // Spec A.5 lists only "+", "++" and "+++".
      final result = run(
        findings: const Findings(
          bpSys: 145,
          urineProtein: UrineProtein.trace,
        ),
      );

      expect(result.level, TriageLevel.amber);
      expect(result.reasonsEn, ['Raised BP (≥140/90)']);
    });

    test('proteinuria on its own is amber', () {
      final result = run(
        findings: const Findings(urineProtein: UrineProtein.three),
      );

      expect(result.level, TriageLevel.amber);
      expect(result.reasonsEn, ['Proteinuria']);
    });

    test('the anaemia bands meet without a gap or an overlap', () {
      expect(run(findings: const Findings(hbGdl: 6.9)).level, TriageLevel.red);
      expect(run(findings: const Findings(hbGdl: 7)).level, TriageLevel.amber);
      expect(run(findings: const Findings(hbGdl: 9.9)).level, TriageLevel.amber);
      expect(run(findings: const Findings(hbGdl: 10)).level, TriageLevel.green);
    });

    test('an unmeasured haemoglobin is not anaemia', () {
      // The `?? 99` fallback: no reading must not read as zero and scream.
      final result = run(findings: const Findings(bpSys: 110, bpDia: 70));

      expect(result.level, TriageLevel.green);
      expect(result.reasonsEn, isEmpty);
    });

    test('reduced fetal movement is amber at any gestation', () {
      expect(
        run(
          findings: const Findings(fetalMovement: FetalMovement.reduced),
          gestationalAgeDays: 100,
        ).level,
        TriageLevel.amber,
      );
    });

    test('normal fetal movement adds nothing', () {
      expect(
        run(findings: const Findings(fetalMovement: FetalMovement.normal))
            .level,
        TriageLevel.green,
      );
    });
  });

  group('danger signs', () {
    test('every red code in the shipped table produces red', () {
      for (final sign in rules.dangerSigns.where((s) => s.isRed)) {
        expect(
          run(dangerSigns: [sign.code]).level,
          TriageLevel.red,
          reason: sign.code,
        );
      }
    });

    test('every amber code in the shipped table produces amber', () {
      for (final sign in rules.dangerSigns.where((s) => !s.isRed)) {
        expect(
          run(dangerSigns: [sign.code]).level,
          TriageLevel.amber,
          reason: sign.code,
        );
      }
    });

    test('a code this build has never heard of is ignored, not fatal', () {
      // A newer rule table on the server must not crash an older app.
      final result = run(dangerSigns: const ['SOMETHING_NEW_IN_2027']);

      expect(result.level, TriageLevel.green);
      expect(result.reasonsEn, isEmpty);
    });
  });

  group('reasons', () {
    test('every reason has a Nepali translation', () {
      // Spec §16: the red banner must be readable in Nepali.
      final result = run(
        findings: const Findings(bpSys: 150, bpDia: 95, hbGdl: 6.5),
        dangerSigns: const ['SEVERE_HEADACHE_BLURRED_VISION'],
      );

      expect(result.reasonsNp, hasLength(result.reasonsEn.length));
      for (var i = 0; i < result.reasonsNp.length; i++) {
        expect(
          result.reasonsNp[i],
          isNot(result.reasonsEn[i]),
          reason: 'untranslated: ${result.reasonsEn[i]}',
        );
      }
    });

    test('translateReason covers both the fixed rules and the table', () {
      expect(
        rules.translateReason('Severe anaemia (Hb < 7)'),
        isNot('Severe anaemia (Hb < 7)'),
      );
      expect(
        rules.translateReason('Vaginal bleeding'),
        isNot('Vaginal bleeding'),
      );
    });

    test('an unknown reason falls back to its English text', () {
      expect(rules.translateReason('Something else'), 'Something else');
    });

    test('the reason list is not mutable by the caller', () {
      final result = run(findings: const Findings(bpSys: 150));
      expect(
        () => result.reasons.add(
          const TriageReason(code: 'X', en: 'x', np: 'x'),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('riskLevelFor', () {
    test('any risk factor makes the pregnancy high risk', () {
      expect(riskLevelFor(const []), RiskLevel.normal);
      expect(riskLevelFor(const ['PREV_CS']), RiskLevel.high);
      expect(riskLevelFor(const ['AGE_LT_18', 'PREV_CS']), RiskLevel.high);
    });
  });
}
