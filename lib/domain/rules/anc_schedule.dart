import '../../core/ids/ids.dart';
import '../models/models.dart';
import 'edd.dart';
import 'rules.dart';

/// Spec §12 / A.5 — the eight-contact ANC schedule.
///
/// Every contact is generated up front, at registration, so the checklist has
/// something to show on a phone that has never synced. The ids are `uuid v5` of
/// `"<pregnancyId>:<contactNo>"` (A.8.15), which is what makes that safe: the
/// server generates the same eight rows from the same inputs, so the two sets
/// converge on one another instead of duplicating.
///
/// Contacts are scheduled from the LMP — derived from the EDD when only that was
/// recorded — because the week targets in the rule table are weeks of gestation.
List<AncContact> generateContacts(Pregnancy pregnancy, Rules rules) {
  final lmp = scheduleAnchor(pregnancy);

  return rules.ancSchedule
      .map(
        (entry) => AncContact(
          id: ancContactId(pregnancy.id, entry.contactNo),
          pregnancyId: pregnancy.id,
          contactNo: entry.contactNo,
          weekTarget: entry.weekTarget,
          dueAt: toIsoDate(lmp.add(Duration(days: entry.weekTarget * 7))),
        ),
      )
      .toList(growable: false);
}

/// The date the schedule counts from: the recorded LMP, or the one implied by
/// the EDD.
DateTime scheduleAnchor(Pregnancy pregnancy) {
  final lmp = parseIsoDate(pregnancy.lmp);
  if (lmp != null) return lmp;
  return lmpFromEdd(parseIsoDate(pregnancy.edd) ?? DateTime.now().toUtc());
}

/// When contact [contactNo] is due, without generating the whole schedule.
DateTime? contactDueDate(Pregnancy pregnancy, Rules rules, int contactNo) {
  final entry = rules.contact(contactNo);
  if (entry == null) return null;
  return scheduleAnchor(pregnancy).add(Duration(days: entry.weekTarget * 7));
}

/// The next contact a health worker should be chasing: the earliest one not yet
/// done. Null once all eight are recorded.
AncContact? nextContact(List<AncContact> contacts) {
  final pending = contacts.where((c) => c.doneAt == null && !c.deleted).toList()
    ..sort((a, b) => a.contactNo.compareTo(b.contactNo));
  return pending.isEmpty ? null : pending.first;
}

/// Contacts whose due date has passed with nothing recorded — the red-dot list
/// on S13 and what the server's `anc_missed` reminder is about.
List<AncContact> overdueContacts(
  List<AncContact> contacts, {
  DateTime? asOf,
}) {
  final today = dateOnly(asOf ?? DateTime.now().toUtc());

  return contacts.where((contact) {
    if (contact.doneAt != null || contact.deleted) return false;
    final due = parseIsoDate(contact.dueAt);
    return due != null && due.isBefore(today);
  }).toList(growable: false);
}

/// How far through the schedule she is, for the S13 progress bar.
({int done, int total}) scheduleProgress(List<AncContact> contacts) {
  final live = contacts.where((c) => !c.deleted);
  return (
    done: live.where((c) => c.doneAt != null).length,
    total: live.length,
  );
}
