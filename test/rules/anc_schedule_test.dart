import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/ids/ids.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/domain/rules/anc_schedule.dart';
import 'package:mero_swasthya/domain/rules/rules.dart';

/// Spec A.6 case 1 (contact due dates) plus the invariants the offline flow
/// depends on: eight contacts, generated at registration, with ids the server
/// derives independently and identically.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Rules rules;

  setUpAll(() async => rules = await Rules.loadFromAsset());

  Pregnancy pregnancy({String? lmp = '2026-02-20', String edd = '2026-11-27'}) =>
      Pregnancy(id: 'pg1', patientId: 'p1', lmp: lmp, edd: edd);

  group('the shipped rule table', () {
    test('it holds the eight-contact schedule from A.5', () {
      expect(rules.ancSchedule, hasLength(8));
      expect(
        rules.ancSchedule.map((e) => e.contactNo),
        [1, 2, 3, 4, 5, 6, 7, 8],
      );
      expect(
        rules.ancSchedule.map((e) => e.weekTarget),
        [12, 20, 26, 30, 34, 36, 38, 40],
      );
    });

    test('each contact carries the checklist S12 renders', () {
      expect(rules.contact(1)!.checklist, contains('bp'));
      expect(rules.contact(4)!.checklist, contains('birthPlan'));
      expect(rules.contact(8)!.checklist, contains('labourSigns'));
    });
  });

  group('A.6 case 1 — due dates from lmp 2026-02-20', () {
    test('contact 1 (week 12) is due 2026-05-15', () {
      final contacts = generateContacts(pregnancy(), rules);
      expect(contacts.first.contactNo, 1);
      expect(contacts.first.weekTarget, 12);
      expect(contacts.first.dueAt, '2026-05-15');
    });

    test('contact 5 (week 34) is due 2026-10-16', () {
      final contacts = generateContacts(pregnancy(), rules);
      final fifth = contacts[4];
      expect(fifth.contactNo, 5);
      expect(fifth.weekTarget, 34);
      expect(fifth.dueAt, '2026-10-16');
    });
  });

  group('generation', () {
    test('it produces one contact per rule entry, in order', () {
      final contacts = generateContacts(pregnancy(), rules);

      expect(contacts, hasLength(8));
      expect(contacts.map((c) => c.contactNo), [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(
        contacts.map((c) => c.dueAt).toList(),
        List.of(contacts.map((c) => c.dueAt))..sort(),
        reason: 'due dates run forward',
      );
    });

    test('every contact starts empty and unsynced', () {
      final contact = generateContacts(pregnancy(), rules).first;

      expect(contact.doneAt, isNull);
      expect(contact.findings, isNull);
      expect(contact.triageLevel, isNull);
      expect(contact.dangerSigns, isEmpty);
      expect(contact.triageReasons, isEmpty);
      expect(contact.referral, isNull);
      expect(contact.version, 0);
      expect(contact.deleted, isFalse);
    });

    test('ids are the deterministic v5 the server also derives', () {
      // A.8.15. This is what stops a pregnancy registered offline from
      // duplicating the server's own eight rows on the first sync.
      final contacts = generateContacts(pregnancy(), rules);

      for (final contact in contacts) {
        expect(contact.id, ancContactId('pg1', contact.contactNo));
      }
      expect(contacts.map((c) => c.id).toSet(), hasLength(8));
    });

    test('generating twice produces identical rows', () {
      final first = generateContacts(pregnancy(), rules);
      final second = generateContacts(pregnancy(), rules);

      expect(first.map((c) => c.id), second.map((c) => c.id));
      expect(first.map((c) => c.dueAt), second.map((c) => c.dueAt));
    });

    test('a pregnancy with only an edd is scheduled from the implied lmp', () {
      // A.6 case 2: the schedule must not need an LMP to exist.
      final fromEdd = generateContacts(pregnancy(lmp: null), rules);
      final fromLmp = generateContacts(pregnancy(), rules);

      expect(fromEdd.map((c) => c.dueAt), fromLmp.map((c) => c.dueAt));
    });
  });

  group('progress', () {
    List<AncContact> schedule() => generateContacts(pregnancy(), rules);

    test('the next contact is the earliest one not yet done', () {
      final contacts = [
        schedule()[0].copyWith(doneAt: '2026-05-15T04:00:00.000Z'),
        schedule()[1],
        schedule()[2],
      ];

      expect(nextContact(contacts)!.contactNo, 2);
    });

    test('there is no next contact once all eight are recorded', () {
      final contacts = [
        for (final c in schedule()) c.copyWith(doneAt: '2026-05-15T04:00:00.000Z'),
      ];

      expect(nextContact(contacts), isNull);
    });

    test('a deleted contact is not offered as next', () {
      final contacts = [
        schedule()[0].copyWith(deleted: true),
        schedule()[1],
      ];

      expect(nextContact(contacts)!.contactNo, 2);
    });

    test('overdue means past due with nothing recorded', () {
      final contacts = schedule();

      final overdue = overdueContacts(contacts, asOf: DateTime.utc(2026, 9, 18));

      // Weeks 12, 20 and 26 fall before 18 September; week 30 does not.
      expect(overdue.map((c) => c.contactNo), [1, 2, 3]);
    });

    test('a recorded contact is never overdue', () {
      final contacts = [
        for (final c in schedule())
          c.copyWith(doneAt: '2026-05-15T04:00:00.000Z'),
      ];

      expect(overdueContacts(contacts, asOf: DateTime.utc(2026, 9, 18)),
          isEmpty);
    });

    test('a contact due today is not yet overdue', () {
      final contacts = schedule();
      final firstDue = DateTime.parse(contacts.first.dueAt);

      expect(overdueContacts(contacts, asOf: firstDue), isEmpty);
    });

    test('scheduleProgress counts recorded against live contacts', () {
      final contacts = [
        schedule()[0].copyWith(doneAt: '2026-05-15T04:00:00.000Z'),
        schedule()[1].copyWith(doneAt: '2026-07-10T04:00:00.000Z'),
        schedule()[2],
        schedule()[3].copyWith(deleted: true),
      ];

      final progress = scheduleProgress(contacts);
      expect(progress.done, 2);
      expect(progress.total, 3);
    });
  });

  group('contactDueDate', () {
    test('it matches the generated schedule without generating it', () {
      final contacts = generateContacts(pregnancy(), rules);

      for (final contact in contacts) {
        expect(
          contactDueDate(pregnancy(), rules, contact.contactNo)!
              .toIso8601String()
              .substring(0, 10),
          contact.dueAt,
        );
      }
    });

    test('a contact number outside the schedule has no due date', () {
      expect(contactDueDate(pregnancy(), rules, 9), isNull);
      expect(contactDueDate(pregnancy(), rules, 0), isNull);
    });
  });
}
