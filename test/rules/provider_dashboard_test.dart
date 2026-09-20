import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/domain/rules/edd.dart';
import 'package:mero_swasthya/domain/rules/provider_dashboard.dart';

/// Tier 2 — the S19 health-post dashboard.
///
/// The aggregation is where a dashboard goes wrong quietly: a woman counted in
/// two trimesters, a contact still shown as overdue after the baby arrived, a
/// red flag from six weeks ago sitting in "last 7 days". Each of those is a
/// case here.
void main() {
  final now = DateTime.utc(2026, 9, 19, 10);
  final monthStart = DateTime.utc(2026, 9, 1);
  final monthEnd = DateTime.utc(2026, 9, 30, 23, 59, 59);

  Patient patient(String id, String name) => Patient(
        id: id,
        ownerUserId: 'u_other',
        name: name,
        sex: Sex.female,
        dob: '1996-05-05',
      );

  /// A pregnancy at [weeks] gestation as of [now].
  Pregnancy pregnancy(
    String id,
    String patientId, {
    required int weeks,
    PregnancyStatus status = PregnancyStatus.active,
  }) {
    final edd = now.add(Duration(days: (40 - weeks) * 7));
    return Pregnancy(
      id: id,
      patientId: patientId,
      edd: toIsoDate(edd),
      status: status,
    );
  }

  AncContact contact(
    String id,
    String pregnancyId, {
    required int contactNo,
    String? dueAt,
    String? doneAt,
    TriageLevel? triage,
  }) {
    return AncContact(
      id: id,
      pregnancyId: pregnancyId,
      contactNo: contactNo,
      weekTarget: contactNo * 4,
      dueAt: dueAt ?? '2026-10-01',
      doneAt: doneAt,
      triageLevel: triage,
    );
  }

  Delivery delivery(String id, String pregnancyId, DateTime at) => Delivery(
        id: id,
        pregnancyId: pregnancyId,
        deliveredAt: at.toIso8601String(),
        place: DeliveryPlace.birthingCentre,
        mode: DeliveryMode.normal,
        outcome: DeliveryOutcome.liveBirth,
      );

  ProviderDashboard build({
    List<Patient> patients = const [],
    List<Pregnancy> pregnancies = const [],
    List<AncContact> contacts = const [],
    List<Delivery> deliveries = const [],
  }) {
    return buildProviderDashboard(
      patients: patients,
      pregnancies: pregnancies,
      contacts: contacts,
      deliveries: deliveries,
      now: now,
      monthStart: monthStart,
      monthEnd: monthEnd,
    );
  }

  group('trimesters', () {
    test('sorts by gestational age at the WHO boundaries', () {
      final board = build(
        patients: [
          patient('p1', 'Gita'),
          patient('p2', 'Maya'),
          patient('p3', 'Parbati'),
        ],
        pregnancies: [
          pregnancy('pg1', 'p1', weeks: 10),
          pregnancy('pg2', 'p2', weeks: 22),
          pregnancy('pg3', 'p3', weeks: 37),
        ],
      );

      expect(board.count(DashboardBucket.trimester1), 1);
      expect(board.count(DashboardBucket.trimester2), 1);
      expect(board.count(DashboardBucket.trimester3), 1);
      expect(board.of(DashboardBucket.trimester3).single.patient.name,
          'Parbati');
    });

    test('week 13 is first, 14 is second, 27 is second, 28 is third', () {
      for (final (weeks, bucket) in [
        (13, DashboardBucket.trimester1),
        (14, DashboardBucket.trimester2),
        (27, DashboardBucket.trimester2),
        (28, DashboardBucket.trimester3),
      ]) {
        final board = build(
          patients: [patient('p1', 'Gita')],
          pregnancies: [pregnancy('pg1', 'p1', weeks: weeks)],
        );
        expect(
          board.count(bucket),
          1,
          reason: 'week $weeks should be in $bucket',
        );
      }
    });

    test('a delivered pregnancy is in no trimester at all', () {
      final board = build(
        patients: [patient('p1', 'Gita')],
        pregnancies: [
          pregnancy(
            'pg1',
            'p1',
            weeks: 39,
            status: PregnancyStatus.delivered,
          ),
        ],
      );

      expect(board.count(DashboardBucket.trimester3), 0);
    });

    test('a pregnancy whose patient is not cached here is not counted', () {
      // The tiles are about the records on this phone. Counting a pregnancy
      // whose patient row is missing would produce a number with no list.
      final board = build(pregnancies: [pregnancy('pg1', 'p-gone', weeks: 20)]);
      expect(board.isEmpty, isTrue);
    });
  });

  group('overdue contacts', () {
    test('counts a contact due in the past with nothing recorded', () {
      final board = build(
        patients: [patient('p1', 'Gita')],
        pregnancies: [pregnancy('pg1', 'p1', weeks: 22)],
        contacts: [
          contact('c1', 'pg1', contactNo: 2, dueAt: '2026-08-29'),
          contact('c2', 'pg1', contactNo: 3, dueAt: '2026-10-20'),
        ],
      );

      final rows = board.of(DashboardBucket.overdueContacts);
      expect(rows, hasLength(1));
      expect(rows.single.contact!.contactNo, 2);
    });

    test('a contact that was done is not overdue', () {
      final board = build(
        patients: [patient('p1', 'Gita')],
        pregnancies: [pregnancy('pg1', 'p1', weeks: 22)],
        contacts: [
          contact(
            'c1',
            'pg1',
            contactNo: 2,
            dueAt: '2026-08-29',
            doneAt: '2026-08-30T10:00:00.000Z',
          ),
        ],
      );

      expect(board.count(DashboardBucket.overdueContacts), 0);
    });

    test('a pregnancy that has ended stops producing overdue contacts', () {
      // The baby arrived at 37 weeks; contact 8 was never going to happen and
      // is not a woman anybody needs to chase.
      final board = build(
        patients: [patient('p1', 'Gita')],
        pregnancies: [
          pregnancy(
            'pg1',
            'p1',
            weeks: 41,
            status: PregnancyStatus.delivered,
          ),
        ],
        contacts: [contact('c1', 'pg1', contactNo: 8, dueAt: '2026-08-29')],
      );

      expect(board.count(DashboardBucket.overdueContacts), 0);
    });
  });

  group('recent red or amber', () {
    test('keeps flags inside the seven-day window', () {
      final board = build(
        patients: [patient('p1', 'Gita'), patient('p2', 'Maya')],
        pregnancies: [
          pregnancy('pg1', 'p1', weeks: 30),
          pregnancy('pg2', 'p2', weeks: 30),
        ],
        contacts: [
          contact(
            'c1',
            'pg1',
            contactNo: 3,
            doneAt: '2026-09-17T10:00:00.000Z',
            triage: TriageLevel.amber,
          ),
          contact(
            'c2',
            'pg2',
            contactNo: 3,
            doneAt: '2026-09-18T10:00:00.000Z',
            triage: TriageLevel.red,
          ),
        ],
      );

      final rows = board.of(DashboardBucket.recentTriage);
      expect(rows, hasLength(2));
      // Red first: it is the one that decides whether somebody travels tonight.
      expect(rows.first.contact!.triageLevel, TriageLevel.red);
    });

    test('drops a flag older than the window', () {
      final board = build(
        patients: [patient('p1', 'Gita')],
        pregnancies: [pregnancy('pg1', 'p1', weeks: 30)],
        contacts: [
          contact(
            'c1',
            'pg1',
            contactNo: 3,
            doneAt: '2026-08-01T10:00:00.000Z',
            triage: TriageLevel.red,
          ),
        ],
      );

      expect(board.count(DashboardBucket.recentTriage), 0);
    });

    test('green is not a flag', () {
      final board = build(
        patients: [patient('p1', 'Gita')],
        pregnancies: [pregnancy('pg1', 'p1', weeks: 30)],
        contacts: [
          contact(
            'c1',
            'pg1',
            contactNo: 3,
            doneAt: '2026-09-18T10:00:00.000Z',
            triage: TriageLevel.green,
          ),
        ],
      );

      expect(board.count(DashboardBucket.recentTriage), 0);
    });

    test('a contact with no doneAt is not a recent anything', () {
      final board = build(
        patients: [patient('p1', 'Gita')],
        pregnancies: [pregnancy('pg1', 'p1', weeks: 30)],
        contacts: [
          contact('c1', 'pg1', contactNo: 3, triage: TriageLevel.red),
        ],
      );

      expect(board.count(DashboardBucket.recentTriage), 0);
    });
  });

  group('deliveries this month', () {
    test('counts one inside the month and not one before it', () {
      final board = build(
        patients: [patient('p1', 'Gita'), patient('p2', 'Maya')],
        pregnancies: [
          pregnancy('pg1', 'p1', weeks: 40, status: PregnancyStatus.delivered),
          pregnancy('pg2', 'p2', weeks: 40, status: PregnancyStatus.delivered),
        ],
        deliveries: [
          delivery('d1', 'pg1', DateTime.utc(2026, 9, 10)),
          delivery('d2', 'pg2', DateTime.utc(2026, 8, 28)),
        ],
      );

      final rows = board.of(DashboardBucket.deliveriesThisMonth);
      expect(rows, hasLength(1));
      expect(rows.single.patient.name, 'Gita');
    });

    test('the last instant of the month still counts', () {
      final board = build(
        patients: [patient('p1', 'Gita')],
        pregnancies: [
          pregnancy('pg1', 'p1', weeks: 40, status: PregnancyStatus.delivered),
        ],
        deliveries: [
          delivery('d1', 'pg1', DateTime.utc(2026, 9, 30, 23, 59, 59)),
        ],
      );

      expect(board.count(DashboardBucket.deliveriesThisMonth), 1);
    });
  });

  group('the whole board', () {
    test('an empty device is empty rather than six zeroes with rows', () {
      expect(build().isEmpty, isTrue);
      for (final bucket in DashboardBucket.values) {
        expect(build().count(bucket), 0);
      }
    });

    test('one woman can be in a trimester and overdue at the same time', () {
      // These are different questions about the same person, and a dashboard
      // that made them exclusive would hide the one that matters.
      final board = build(
        patients: [patient('p1', 'Gita')],
        pregnancies: [pregnancy('pg1', 'p1', weeks: 22)],
        contacts: [contact('c1', 'pg1', contactNo: 2, dueAt: '2026-08-29')],
      );

      expect(board.count(DashboardBucket.trimester2), 1);
      expect(board.count(DashboardBucket.overdueContacts), 1);
      expect(board.isEmpty, isFalse);
    });
  });
}
