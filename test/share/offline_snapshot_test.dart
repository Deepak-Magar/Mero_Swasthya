import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/share/offline_snapshot.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';

/// SWC2 — the server-free QR. The three things that matter are that a record
/// survives the round trip, that it fits in a code a phone camera can actually
/// read, and that it stops working after ten minutes.
void main() {
  final now = DateTime.utc(2026, 9, 20, 11, 0, 0);

  Patient patient({
    String id = 'p_a1a1a1a1-0000-4000-8000-000000000001',
    String name = 'Sita Chaudhary',
    Sex sex = Sex.female,
    List<String> allergies = const ['sulpha'],
    List<String> conditions = const [],
  }) =>
      Patient(
        id: id,
        ownerUserId: 'u_0001',
        name: name,
        sex: sex,
        dob: '2002-04-11',
        bloodGroup: 'B+',
        allergies: allergies,
        chronicConditions: conditions,
      );

  Prescription rx(String name, {String? np}) => Prescription(
        id: 'rx_$name',
        drugCode: name.toUpperCase(),
        drugName: name,
        dose: '1 tab',
        frequency: PrescriptionFrequency.bd,
        durationDays: 30,
        instructionsNp: np,
      );

  Pregnancy pregnancy() => const Pregnancy(
        id: 'preg_1',
        patientId: 'p_a1a1a1a1-0000-4000-8000-000000000001',
        edd: '2026-11-28',
        riskLevel: RiskLevel.normal,
      );

  List<AncContact> contacts({int done = 3}) => [
        for (var i = 1; i <= 8; i++)
          AncContact(
            id: 'c$i',
            pregnancyId: 'preg_1',
            contactNo: i,
            weekTarget: const [12, 20, 26, 30, 34, 36, 38, 40][i - 1],
            dueAt: '2026-0${i < 7 ? i + 3 : 9}-01',
            doneAt: i <= done ? '2026-08-01' : null,
            triageLevel: i <= done ? TriageLevel.green : null,
          ),
      ];

  group('round trip', () {
    test('a full record survives encode and decode', () {
      final snapshot = buildOfflineSnapshot(
        patient: patient(conditions: const ['E11']),
        summary: PatientSummary(
          allergies: const ['sulpha'],
          currentMedicines: [rx('Metformin 500 mg', np: 'खाना पछि')],
          lastVitals: const LastVitals(
            bpSys: 124,
            bpDia: 80,
            weightKg: 58,
            at: '2026-08-22',
          ),
        ),
        pregnancy: pregnancy(),
        contacts: contacts(),
        now: now,
      );

      final encoded = encodeOfflineSnapshot(snapshot);
      expect(encoded.payload, startsWith(OfflineSnapshot.prefix));
      expect(encoded.trims, isEmpty);

      final back = decodeOfflineSnapshot(encoded.payload);

      expect(back.patientId, snapshot.patientId);
      expect(back.name, 'Sita Chaudhary');
      expect(back.sex, Sex.female);
      expect(back.dob, '2002-04-11');
      expect(back.bloodGroup, 'B+');
      expect(back.allergies, ['sulpha']);
      expect(back.chronicConditions, ['E11']);
      expect(back.medicines, hasLength(1));
      expect(back.medicines.first.name, 'Metformin 500 mg');
      // Devanagari has to come back byte-identical: it is the one string on
      // the card the patient actually reads.
      expect(back.medicines.first.instructionsNp, 'खाना पछि');
      expect(back.lastVitals!.sys, 124);
      expect(back.lastVitals!.dia, 80);
      expect(back.pregnancy!.edd, '2026-11-28');
      expect(back.pregnancy!.contacts, hasLength(8));
      expect(back.pregnancy!.contacts.first.done, isTrue);
      expect(back.pregnancy!.contacts.first.triage, 'green');
      expect(back.pregnancy!.contacts.last.done, isFalse);
      expect(back.generatedAt, snapshot.generatedAt);
      expect(back.expiresAt, snapshot.expiresAt);
    });

    test('a patient with nothing on file still round-trips', () {
      final snapshot = buildOfflineSnapshot(
        patient: patient(name: 'Maya Chaudhary', allergies: const []),
        now: now,
      );

      final back = decodeOfflineSnapshot(
        encodeOfflineSnapshot(snapshot).payload,
      );

      expect(back.name, 'Maya Chaudhary');
      expect(back.allergies, isEmpty);
      expect(back.medicines, isEmpty);
      expect(back.pregnancy, isNull);
      expect(back.lastVitals, isNull);
    });

    test('the bundle rebuilt from a snapshot is what S21 draws', () {
      final snapshot = buildOfflineSnapshot(
        patient: patient(conditions: const ['E11']),
        summary: PatientSummary(
          currentMedicines: [rx('Metformin 500 mg', np: 'खाना पछि')],
          lastVitals: const LastVitals(bpSys: 124, bpDia: 80),
        ),
        pregnancy: pregnancy(),
        contacts: contacts(),
        now: now,
      );

      final bundle = bundleFromSnapshot(snapshot);

      expect(bundle.patient.name, 'Sita Chaudhary');
      expect(bundle.patient.allergies, ['sulpha']);
      // Not this device's account: the record belongs to whoever shared it.
      expect(bundle.patient.ownerUserId, isEmpty);
      expect(bundle.summary.activeProblems.single.code, 'E11');
      expect(bundle.summary.currentMedicines.single.drugName,
          'Metformin 500 mg');
      expect(bundle.summary.lastVitals!.bpSys, 124);
      expect(bundle.pregnancy!.edd, '2026-11-28');
      expect(bundle.ancContacts, hasLength(8));
      expect(bundle.ancContacts[3].weekTarget, 30);
      expect(bundle.ancContacts.where((c) => c.doneAt != null), hasLength(3));
    });

    test('scanning the same person twice lands on the same rows', () {
      final snapshot = buildOfflineSnapshot(
        patient: patient(),
        pregnancy: pregnancy(),
        contacts: contacts(),
        now: now,
      );

      final a = bundleFromSnapshot(snapshot);
      final b = bundleFromSnapshot(snapshot);

      expect(a.pregnancy!.id, b.pregnancy!.id);
      expect(a.ancContacts.map((c) => c.id), b.ancContacts.map((c) => c.id));
    });
  });

  group('size', () {
    int sizeOf(OfflineSnapshot s) => encodeOfflineSnapshot(s).bytes;

    test('Sita — pregnancy, eight contacts, an allergy — fits the budget', () {
      final bytes = sizeOf(
        buildOfflineSnapshot(
          patient: patient(),
          summary: PatientSummary(
            allergies: const ['sulpha'],
            lastVitals: const LastVitals(bpSys: 124, bpDia: 80, weightKg: 58),
          ),
          pregnancy: pregnancy(),
          contacts: contacts(),
          now: now,
        ),
      );

      expect(bytes, lessThan(OfflineSnapshot.targetBytes),
          reason: 'Sita came out at $bytes bytes');
    });

    test('Ram — two medicines, an allergy, a chronic condition — fits', () {
      final bytes = sizeOf(
        buildOfflineSnapshot(
          patient: patient(
            id: 'p_b2b2b2b2-0000-4000-8000-000000000002',
            name: 'Ram Bahadur Chaudhary',
            sex: Sex.male,
            allergies: const ['penicillin'],
            conditions: const ['E11'],
          ),
          summary: PatientSummary(
            currentMedicines: [
              rx('Metformin 500 mg', np: 'खाना पछि'),
              rx('Amlodipine 5 mg', np: 'सुत्ने बेला'),
            ],
            lastVitals: const LastVitals(bpSys: 138, bpDia: 86, weightKg: 71.5),
          ),
          now: now,
        ),
      );

      expect(bytes, lessThan(OfflineSnapshot.targetBytes),
          reason: 'Ram came out at $bytes bytes');
    });

    test('Aarav — a child with nothing but a name — fits', () {
      final bytes = sizeOf(
        buildOfflineSnapshot(
          patient: patient(
            id: 'p_c3c3c3c3-0000-4000-8000-000000000003',
            name: 'Aarav Chaudhary',
            sex: Sex.male,
            allergies: const [],
          ),
          now: now,
        ),
      );

      expect(bytes, lessThan(OfflineSnapshot.targetBytes),
          reason: 'Aarav came out at $bytes bytes');
    });

    test('a worst case sheds detail until it fits, and says what it dropped',
        () {
      final encoded = encodeOfflineSnapshot(
        buildOfflineSnapshot(
          patient: patient(
            name: 'Kamala Devi Bishwokarma Chaudhary Tharu',
            allergies: const [
              'sulphonamides',
              'penicillin',
              'aspirin',
              'iodinated contrast media',
              'latex',
            ],
            conditions: const [
              'type 2 diabetes mellitus',
              'chronic hypertension',
              'hypothyroidism',
              'chronic kidney disease stage 3',
            ],
          ),
          summary: PatientSummary(
            // Forty distinct, high-entropy names: gzip folds repetition, so a
            // worst case has to be one it cannot fold. Measured at 1,464 bytes
            // with 24 of these and over the limit at 40.
            currentMedicines: [
              for (var i = 0; i < 40; i++)
                rx(
                  'Zx${i}qv Rareword$i Brandname$i ${900 + i} mg',
                  np: 'निर्देशन$i ${String.fromCharCodes([
                        for (var j = 0; j < 44; j++) 0x0915 + (i * 13 + j * 5) % 60,
                      ])}',
                ),
            ],
            lastVitals: const LastVitals(bpSys: 150, bpDia: 96, weightKg: 82.5),
          ),
          pregnancy: pregnancy(),
          contacts: contacts(done: 8),
          now: now,
        ),
      );

      expect(encoded.bytes, lessThanOrEqualTo(OfflineSnapshot.maxBytes),
          reason: 'worst case came out at ${encoded.bytes} bytes');
      expect(encoded.trims, isNotEmpty);
      expect(encoded.trims.first, contains('medicine'));

      // Whatever was shed, what is left still has to decode.
      final back = decodeOfflineSnapshot(encoded.payload);
      expect(back.name, 'Kamala Devi Bishwokarma Chaudhary Tharu');
      expect(back.allergies, hasLength(5));
      expect(back.medicines.length,
          lessThanOrEqualTo(OfflineSnapshot.trimmedMedicineCount));
    });
  });

  group('expiry', () {
    test('a code is good for exactly ten minutes', () {
      final snapshot = buildOfflineSnapshot(patient: patient(), now: now);

      expect(
        snapshot.expiresAt.difference(snapshot.generatedAt),
        const Duration(minutes: 10),
      );
    });

    test('a fresh code is not expired', () {
      final snapshot = buildOfflineSnapshot(patient: patient(), now: now);

      expect(snapshot.isExpired(now), isFalse);
      expect(snapshot.isExpired(now.add(const Duration(minutes: 9))), isFalse);
    });

    test('a code past its expiry is rejected', () {
      final snapshot = buildOfflineSnapshot(patient: patient(), now: now);

      expect(
        snapshot.isExpired(now.add(const Duration(minutes: 11, seconds: 1))),
        isTrue,
      );
    });

    test('a minute of clock skew is forgiven, two are not', () {
      // The two phones are never on the same second, and a provider holding a
      // code that died half a second ago should not be told to start again.
      final snapshot = buildOfflineSnapshot(patient: patient(), now: now);

      expect(
        snapshot.isExpired(now.add(const Duration(minutes: 10, seconds: 30))),
        isFalse,
      );
      expect(
        snapshot.isExpired(now.add(const Duration(minutes: 10, seconds: 59))),
        isFalse,
      );
      expect(
        snapshot.isExpired(now.add(const Duration(minutes: 11, seconds: 30))),
        isTrue,
      );
    });

    test('expiry survives the round trip', () {
      final snapshot = buildOfflineSnapshot(patient: patient(), now: now);
      final back = decodeOfflineSnapshot(
        encodeOfflineSnapshot(snapshot).payload,
      );

      expect(
        back.expiresAt.difference(back.generatedAt),
        const Duration(minutes: 10),
      );
      expect(back.isExpired(now.add(const Duration(minutes: 12))), isTrue);
    });
  });

  group('rejection', () {
    test('a payload that is not SWC2 is refused', () {
      for (final bad in [
        'HELLO',
        'SWC1:mock_grant_3f2504e0-4f89-41d3-9a0c-0305e82c3301',
        'SWC2',
        '',
      ]) {
        expect(
          () => decodeOfflineSnapshot(bad),
          throwsA(isA<FormatException>()),
          reason: bad,
        );
      }
    });

    test('SWC2 with rubbish behind it is refused rather than half-read', () {
      expect(
        () => decodeOfflineSnapshot('SWC2:not-base64-at-all!!'),
        throwsA(isA<Object>()),
      );
    });

    test('a future format version is refused rather than guessed at', () {
      expect(
        () => OfflineSnapshot.fromJson({
          'v': 99,
          'id': 'x',
          'name': 'x',
          'sex': 'female',
          'dob': '2000-01-01',
          'gen': now.toIso8601String(),
          'exp': now.toIso8601String(),
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
