import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/domain/rules/provider_home.dart';

/// `buildProviderHome` — the numbers on the provider Home tab.
void main() {
  // A local morning. "Today" is the local calendar day throughout.
  final now = DateTime(2026, 9, 29, 10, 30);
  String at(DateTime local) => local.toUtc().toIso8601String();
  String day(DateTime local) =>
      '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';

  const sita = Patient(
    id: 'sita',
    ownerUserId: 'u',
    name: 'Sita',
    sex: Sex.female,
    dob: '1996-04-11',
    updatedAt: '2026-09-01T00:00:00Z',
  );
  const ram = Patient(
    id: 'ram',
    ownerUserId: 'u',
    name: 'Ram',
    sex: Sex.male,
    dob: '1988-01-20',
    updatedAt: '2026-09-02T00:00:00Z',
  );
  const gita = Patient(
    id: 'gita',
    ownerUserId: 'o',
    name: 'Gita',
    sex: Sex.female,
    dob: '1995-06-11',
    updatedAt: '2026-09-03T00:00:00Z',
  );

  const sitaPregnancy = Pregnancy(
    id: 'pg_sita',
    patientId: 'sita',
    lmp: '2026-02-01',
    edd: '2026-11-08',
  );
  const gitaPregnancy = Pregnancy(
    id: 'pg_gita',
    patientId: 'gita',
    lmp: '2026-05-01',
    edd: '2027-02-05',
  );

  AncContact contact(
    String pregnancyId,
    int no, {
    required String dueAt,
    String? doneAt,
    TriageLevel? level,
    List<String> reasons = const [],
  }) =>
      AncContact(
        id: '${pregnancyId}_$no',
        pregnancyId: pregnancyId,
        contactNo: no,
        weekTarget: no * 4,
        dueAt: dueAt,
        doneAt: doneAt,
        triageLevel: level,
        triageReasons: reasons,
      );

  group('today', () {
    test('a visit or a contact recorded today makes the patient "seen"', () {
      final home = buildProviderHome(
        patients: const [sita, ram, gita],
        pregnancies: const [sitaPregnancy],
        contacts: [
          contact(
            'pg_sita',
            4,
            dueAt: day(now.subtract(const Duration(days: 3))),
            doneAt: at(now.subtract(const Duration(hours: 2))),
            level: TriageLevel.green,
          ),
        ],
        visits: [
          Visit(
            id: 'v_today',
            patientId: 'ram',
            visitAt: at(now.subtract(const Duration(minutes: 5))),
            chiefComplaintCode: 'FEVER',
          ),
          Visit(
            id: 'v_yesterday',
            patientId: 'gita',
            visitAt: at(now.subtract(const Duration(days: 1))),
            chiefComplaintCode: 'FEVER',
          ),
        ],
        now: now,
      );

      expect(home.seenToday.map((p) => p.id), ['sita', 'ram']);
      expect(home.visitsToday.map((v) => v.visit.id), ['v_today']);
    });

    test('"today" is the local day, not the UTC one', () {
      // 01:00 local in Kathmandu is still the previous day in UTC.
      final smallHours = DateTime(2026, 9, 29, 1, 0);
      final home = buildProviderHome(
        patients: const [ram],
        pregnancies: const [],
        contacts: const [],
        visits: [
          Visit(
            id: 'v',
            patientId: 'ram',
            visitAt: at(smallHours.subtract(const Duration(minutes: 30))),
            chiefComplaintCode: 'FEVER',
          ),
        ],
        now: smallHours,
      );
      expect(home.visitsToday, hasLength(1));
    });

    test('a deleted visit does not count', () {
      final home = buildProviderHome(
        patients: const [ram],
        pregnancies: const [],
        contacts: const [],
        visits: [
          Visit(
            id: 'v',
            patientId: 'ram',
            visitAt: at(now),
            chiefComplaintCode: 'FEVER',
            deleted: true,
          ),
        ],
        now: now,
      );
      expect(home.visitsToday, isEmpty);
      expect(home.seenToday, isEmpty);
    });
  });

  group('contacts owed', () {
    test('sorts into overdue, due today and the next seven days', () {
      final home = buildProviderHome(
        patients: const [sita, gita],
        pregnancies: const [sitaPregnancy, gitaPregnancy],
        contacts: [
          contact('pg_gita', 2, dueAt: day(now.subtract(const Duration(days: 21)))),
          contact('pg_gita', 3, dueAt: day(now)),
          contact('pg_sita', 5, dueAt: day(now.add(const Duration(days: 7)))),
          // Day eight is next week's problem.
          contact('pg_sita', 6, dueAt: day(now.add(const Duration(days: 8)))),
          // Done, so not owed however late it was.
          contact(
            'pg_sita',
            4,
            dueAt: day(now.subtract(const Duration(days: 30))),
            doneAt: at(now.subtract(const Duration(days: 29))),
            level: TriageLevel.green,
          ),
        ],
        visits: const [],
        now: now,
      );

      expect(home.overdue.map((c) => c.contact.id), ['pg_gita_2']);
      expect(home.dueToday.map((c) => c.contact.id), ['pg_gita_3']);
      expect(home.upcoming.map((c) => c.contact.id), ['pg_sita_5']);
      expect(home.dueThisWeek.map((c) => c.contact.id), ['pg_gita_3', 'pg_sita_5']);
    });

    test('a delivered pregnancy owes nothing', () {
      final home = buildProviderHome(
        patients: const [sita],
        pregnancies: const [
          Pregnancy(
            id: 'pg_sita',
            patientId: 'sita',
            edd: '2026-09-01',
            status: PregnancyStatus.delivered,
          ),
        ],
        contacts: [
          contact('pg_sita', 8, dueAt: day(now.subtract(const Duration(days: 10)))),
        ],
        visits: const [],
        now: now,
      );
      expect(home.overdue, isEmpty);
      expect(home.attention, isEmpty);
      expect(home.pregnantPatientIds, isEmpty);
    });

    test('a contact for a patient this phone no longer holds is ignored', () {
      final home = buildProviderHome(
        patients: const [sita],
        pregnancies: const [gitaPregnancy],
        contacts: [contact('pg_gita', 2, dueAt: day(now))],
        visits: const [],
        now: now,
      );
      expect(home.dueToday, isEmpty);
    });
  });

  group('needs attention', () {
    test('red outranks amber outranks overdue, one row per patient', () {
      final home = buildProviderHome(
        patients: const [sita, gita, ram],
        pregnancies: const [sitaPregnancy, gitaPregnancy],
        contacts: [
          // Gita: amber a week ago *and* an overdue contact — one row, amber.
          contact(
            'pg_gita',
            1,
            dueAt: day(now.subtract(const Duration(days: 40))),
            doneAt: at(now.subtract(const Duration(days: 7))),
            level: TriageLevel.amber,
            reasons: const ['Raised BP (≥140/90)'],
          ),
          contact('pg_gita', 2, dueAt: day(now.subtract(const Duration(days: 3)))),
          // Sita: red this morning.
          contact(
            'pg_sita',
            4,
            dueAt: day(now.subtract(const Duration(days: 3))),
            doneAt: at(now.subtract(const Duration(hours: 1))),
            level: TriageLevel.red,
            reasons: const ['Severe hypertension (≥160/110)'],
          ),
        ],
        visits: const [],
        now: now,
      );

      expect(home.attention.map((a) => a.patient.id), ['sita', 'gita']);
      expect(home.attention[0].kind, AttentionKind.redTriage);
      expect(home.attention[1].kind, AttentionKind.amberTriage);
      expect(home.attention[1].contact.contactNo, 1);
    });

    test('a triage older than the window drops off, an overdue never does', () {
      final home = buildProviderHome(
        patients: const [sita, gita],
        pregnancies: const [sitaPregnancy, gitaPregnancy],
        contacts: [
          contact(
            'pg_sita',
            2,
            dueAt: day(now.subtract(const Duration(days: 60))),
            doneAt: at(now.subtract(const Duration(days: 31))),
            level: TriageLevel.red,
          ),
          contact('pg_gita', 1, dueAt: day(now.subtract(const Duration(days: 100)))),
        ],
        visits: const [],
        now: now,
      );

      expect(home.attention.map((a) => a.patient.id), ['gita']);
      expect(home.attention.single.kind, AttentionKind.overdueContact);
    });

    test('green is not attention', () {
      final home = buildProviderHome(
        patients: const [sita],
        pregnancies: const [sitaPregnancy],
        contacts: [
          contact(
            'pg_sita',
            4,
            dueAt: day(now),
            doneAt: at(now),
            level: TriageLevel.green,
          ),
        ],
        visits: const [],
        now: now,
      );
      expect(home.attention, isEmpty);
    });
  });

  group('recent patients', () {
    test('opened ones first, then the cache by last change, five at most', () {
      final more = [
        for (var i = 0; i < 6; i++)
          Patient(
            id: 'p$i',
            ownerUserId: 'o',
            name: 'P$i',
            sex: Sex.other,
            dob: '2000-01-01',
            updatedAt: '2026-08-0${i + 1}T00:00:00Z',
          ),
      ];

      final recent = recentPatientsFrom(
        [sita, ram, gita, ...more],
        const ['p2', 'ghost', 'sita', 'p2'],
      );

      expect(recent.map((p) => p.id), ['p2', 'sita', 'gita', 'ram', 'p5']);
    });

    test('the device state is laid over the records without recounting', () {
      final home = buildProviderHome(
        patients: const [sita, ram],
        pregnancies: const [],
        contacts: const [],
        visits: const [],
        now: now,
      ).withDeviceState(recentPatientIds: const ['sita'], pendingSync: 3);

      expect(home.recentPatients.map((p) => p.id), ['sita', 'ram']);
      expect(home.pendingSync, 3);
    });
  });

  group('firstReadableReason', () {
    test('prefers a sentence, maps the mock\'s stand-ins, skips codes', () {
      AncContact withReasons(List<String> reasons) => AncContact(
            id: 'c',
            pregnancyId: 'pg',
            contactNo: 1,
            weekTarget: 12,
            dueAt: '2026-01-01',
            triageReasons: reasons,
          );

      expect(
        firstReadableReason(withReasons(const ['Severe anaemia (Hb < 7)'])),
        'Severe anaemia (Hb < 7)',
      );
      expect(
        firstReadableReason(withReasons(const ['bp_high'])),
        'Raised BP (≥140/90)',
      );
      expect(
        firstReadableReason(withReasons(const ['danger_sign', 'Proteinuria'])),
        'Proteinuria',
      );
      expect(firstReadableReason(withReasons(const ['danger_sign'])), isNull);
      expect(firstReadableReason(withReasons(const [])), isNull);
    });
  });
}
