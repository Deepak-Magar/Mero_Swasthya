/// Spec §4 lists this as optional: a local preview of the reminders the server
/// will schedule, so S13 can say "her family gets an SMS on Sunday" while the
/// phone is offline and the real [Reminder] rows have not been pulled yet.
///
/// The server remains the only thing that *sends* anything. These rows are never
/// stored and never pushed — they carry no id, because inventing one would risk
/// colliding with the server's.
///
/// The schedule mirrors `RULES.reminders` in A.5:
///  * `anc_due` — one day before `dueAt`, 09:00 Asia/Kathmandu;
///  * `anc_missed` — three days after `dueAt` if still not recorded, repeated
///    once after seven;
///  * `follow_up` — one day before a visit's `followUpAt`.
library;

import '../models/enums.dart';
import '../models/models.dart';
import 'edd.dart';

/// Asia/Kathmandu is UTC+05:45, so 09:00 local is 03:15 UTC.
const Duration kathmanduOffset = Duration(hours: 5, minutes: 45);
const Duration _sendHour = Duration(hours: 9);

class ReminderPreview {
  const ReminderPreview({
    required this.kind,
    required this.dueAt,
    required this.contactNo,
  });

  final ReminderKind kind;

  /// UTC instant the server would send at.
  final DateTime dueAt;

  /// Which ANC contact this is about; null for a follow-up.
  final int? contactNo;

  @override
  String toString() =>
      'ReminderPreview(${kind.wire}, ${dueAt.toIso8601String()})';
}

/// What the family would be texted about [contacts], as of [asOf].
///
/// Only upcoming sends are returned — a reminder whose moment has passed is the
/// server's business, and showing it again would suggest another SMS is coming.
List<ReminderPreview> previewAncReminders(
  List<AncContact> contacts, {
  DateTime? asOf,
}) {
  final now = (asOf ?? DateTime.now()).toUtc();
  final previews = <ReminderPreview>[];

  for (final contact in contacts) {
    if (contact.deleted || contact.doneAt != null) continue;

    final due = parseIsoDate(contact.dueAt);
    if (due == null) continue;

    for (final (kind, offset) in const [
      (ReminderKind.ancDue, Duration(days: -1)),
      (ReminderKind.ancMissed, Duration(days: 3)),
      (ReminderKind.ancMissed, Duration(days: 7)),
    ]) {
      final sendAt = _atNineKathmandu(due.add(offset));
      if (sendAt.isAfter(now)) {
        previews.add(
          ReminderPreview(
            kind: kind,
            dueAt: sendAt,
            contactNo: contact.contactNo,
          ),
        );
      }
    }
  }

  previews.sort((a, b) => a.dueAt.compareTo(b.dueAt));
  return previews;
}

/// The single `follow_up` reminder a visit with a `followUpAt` would produce.
ReminderPreview? previewFollowUp(Visit visit, {DateTime? asOf}) {
  final followUp = parseIsoDate(visit.followUpAt);
  if (followUp == null) return null;

  final sendAt = _atNineKathmandu(followUp.subtract(const Duration(days: 1)));
  if (!sendAt.isAfter((asOf ?? DateTime.now()).toUtc())) return null;

  return ReminderPreview(
    kind: ReminderKind.followUp,
    dueAt: sendAt,
    contactNo: null,
  );
}

/// 09:00 on [day] in Kathmandu, expressed as a UTC instant.
DateTime _atNineKathmandu(DateTime day) =>
    dateOnly(day).add(_sendHour).subtract(kathmanduOffset);
