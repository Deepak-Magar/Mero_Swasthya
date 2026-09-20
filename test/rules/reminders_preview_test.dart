import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/domain/rules/reminders_preview.dart';

/// `RULES.reminders` in spec A.5. This is a preview only — the server is still
/// the only thing that sends an SMS.
void main() {
  AncContact contact({
    int contactNo = 1,
    String dueAt = '2026-10-16',
    String? doneAt,
    bool deleted = false,
  }) =>
      AncContact(
        id: 'ac$contactNo',
        pregnancyId: 'pg1',
        contactNo: contactNo,
        weekTarget: 34,
        dueAt: dueAt,
        doneAt: doneAt,
        deleted: deleted,
      );

  final asOf = DateTime.utc(2026, 9, 18);

  test('an upcoming contact previews one due and two missed reminders', () {
    final previews = previewAncReminders([contact()], asOf: asOf);

    expect(previews.map((p) => p.kind), [
      ReminderKind.ancDue,
      ReminderKind.ancMissed,
      ReminderKind.ancMissed,
    ]);
    expect(previews.every((p) => p.contactNo == 1), isTrue);
  });

  test('the due reminder is 09:00 Kathmandu the day before', () {
    // 09:00 at UTC+05:45 is 03:15 UTC.
    final previews = previewAncReminders([contact()], asOf: asOf);

    expect(previews.first.dueAt, DateTime.utc(2026, 10, 15, 3, 15));
  });

  test('the missed reminders land 3 and 7 days after the due date', () {
    final previews = previewAncReminders([contact()], asOf: asOf);

    expect(previews[1].dueAt, DateTime.utc(2026, 10, 19, 3, 15));
    expect(previews[2].dueAt, DateTime.utc(2026, 10, 23, 3, 15));
  });

  test('a recorded contact previews nothing', () {
    final previews = previewAncReminders(
      [contact(doneAt: '2026-10-16T04:00:00.000Z')],
      asOf: asOf,
    );

    expect(previews, isEmpty);
  });

  test('a deleted contact previews nothing', () {
    expect(
      previewAncReminders([contact(deleted: true)], asOf: asOf),
      isEmpty,
    );
  });

  test('sends whose moment has passed are not shown again', () {
    // Otherwise S13 would imply another SMS is still coming.
    final previews = previewAncReminders(
      [contact(dueAt: '2026-09-01')],
      asOf: asOf,
    );

    expect(previews, isEmpty);
  });

  test('a partly-past contact shows only what is still to come', () {
    // Due 2026-09-16: the "day before" send has gone, the +3 and +7 have not.
    final previews = previewAncReminders(
      [contact(dueAt: '2026-09-16')],
      asOf: asOf,
    );

    expect(previews.map((p) => p.kind),
        [ReminderKind.ancMissed, ReminderKind.ancMissed]);
  });

  test('several contacts come back in send order', () {
    final previews = previewAncReminders(
      [
        contact(contactNo: 2, dueAt: '2026-11-13'),
        contact(contactNo: 1, dueAt: '2026-10-16'),
      ],
      asOf: asOf,
    );

    final times = previews.map((p) => p.dueAt).toList();
    expect(times, List.of(times)..sort());
    expect(previews.first.contactNo, 1);
  });

  group('follow-up', () {
    Visit visit({String? followUpAt}) => Visit(
          id: 'v1',
          patientId: 'p1',
          visitAt: '2026-09-18T05:30:00.000Z',
          chiefComplaintCode: 'FEVER',
          followUpAt: followUpAt,
        );

    test('a visit with a follow-up previews one reminder the day before', () {
      final preview = previewFollowUp(visit(followUpAt: '2026-10-18'),
          asOf: asOf);

      expect(preview!.kind, ReminderKind.followUp);
      expect(preview.dueAt, DateTime.utc(2026, 10, 17, 3, 15));
      expect(preview.contactNo, isNull);
    });

    test('a visit without one previews nothing', () {
      expect(previewFollowUp(visit(), asOf: asOf), isNull);
    });

    test('a follow-up already in the past previews nothing', () {
      expect(
        previewFollowUp(visit(followUpAt: '2026-09-01'), asOf: asOf),
        isNull,
      );
    });
  });
}
