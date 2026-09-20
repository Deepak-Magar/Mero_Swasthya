import 'package:drift/drift.dart';

import '../../../core/streams/combine_latest.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/models.dart';
import '../app_database.dart';
import '../mappers.dart';

part 'pregnancies_dao.g.dart';

@DriftAccessor(tables: [Pregnancies, AncContacts, Deliveries, Reminders])
class PregnanciesDao extends DatabaseAccessor<AppDatabase>
    with _$PregnanciesDaoMixin {
  PregnanciesDao(super.db);

  // -------------------------------------------------------------------------
  // Pregnancies
  // -------------------------------------------------------------------------

  /// S08 shows a maternal card only while a pregnancy is active.
  Stream<Pregnancy?> watchActiveForPatient(String patientId) {
    return (select(pregnancies)
          ..where((t) =>
              t.patientId.equals(patientId) &
              t.status.equalsValue(PregnancyStatus.active) &
              t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.edd)])
          ..limit(1))
        .watchSingleOrNull()
        .map((row) => row?.toModel());
  }

  /// The newest pregnancy for a patient whatever its status.
  ///
  /// S06's badge needs this rather than [watchActiveForPatient]: recording a
  /// delivery flips the status, and a card that keys off "active" would simply
  /// drop the badge — the woman who gave birth last week would look exactly
  /// like the woman who has never been pregnant.
  Stream<Pregnancy?> watchLatestForPatient(String patientId) {
    return (select(pregnancies)
          ..where((t) =>
              t.patientId.equals(patientId) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.edd)])
          ..limit(1))
        .watchSingleOrNull()
        .map((row) => row?.toModel());
  }

  Stream<Pregnancy?> watchById(String id) {
    return (select(pregnancies)..where((t) => t.id.equals(id)))
        .watchSingleOrNull()
        .map((row) => row?.toModel());
  }

  Future<Pregnancy?> findById(String id) async {
    final row = await (select(pregnancies)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row?.toModel();
  }

  Future<void> upsertPregnancy(Pregnancy pregnancy) =>
      into(pregnancies).insertOnConflictUpdate(pregnancy.toCompanion());

  Future<void> upsertPregnancyFromServer(Map<String, dynamic> json) =>
      upsertPregnancy(Pregnancy.fromJson(json));

  Future<bool> upsertPregnancyIfNewer(Map<String, dynamic> json) async {
    final incoming = Pregnancy.fromJson(json);
    final local = await findById(incoming.id);
    if (local != null && incoming.version <= local.version) return false;
    await upsertPregnancy(incoming);
    return true;
  }

  // -------------------------------------------------------------------------
  // ANC contacts
  // -------------------------------------------------------------------------

  /// S12 checklist — the eight contacts in schedule order.
  Stream<List<AncContact>> watchContacts(String pregnancyId) {
    return (select(ancContacts)
          ..where((t) =>
              t.pregnancyId.equals(pregnancyId) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.contactNo)]))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  Future<AncContact?> findContact(String id) async {
    final row = await (select(ancContacts)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row?.toModel();
  }

  Future<AncContact?> findContactByNo(String pregnancyId, int contactNo) async {
    final row = await (select(ancContacts)
          ..where((t) =>
              t.pregnancyId.equals(pregnancyId) &
              t.contactNo.equals(contactNo)))
        .getSingleOrNull();
    return row?.toModel();
  }

  Future<void> upsertContact(AncContact contact) =>
      into(ancContacts).insertOnConflictUpdate(contact.toCompanion());

  Future<void> upsertContacts(List<AncContact> contacts) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(
        ancContacts,
        contacts.map((c) => c.toCompanion()).toList(),
      );
    });
  }

  Future<void> upsertContactFromServer(Map<String, dynamic> json) =>
      upsertContact(AncContact.fromJson(json));

  Future<bool> upsertContactIfNewer(Map<String, dynamic> json) async {
    final incoming = AncContact.fromJson(json);
    final local = await findContact(incoming.id);
    if (local != null && incoming.version <= local.version) return false;
    await upsertContact(incoming);
    return true;
  }

  // -------------------------------------------------------------------------
  // Deliveries
  // -------------------------------------------------------------------------

  Stream<Delivery?> watchDelivery(String pregnancyId) {
    return (select(deliveries)
          ..where((t) =>
              t.pregnancyId.equals(pregnancyId) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.deliveredAt)])
          ..limit(1))
        .watchSingleOrNull()
        .map((row) => row?.toModel());
  }

  Future<Delivery?> findDelivery(String id) async {
    final row = await (select(deliveries)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row?.toModel();
  }

  Future<void> upsertDelivery(Delivery delivery) =>
      into(deliveries).insertOnConflictUpdate(delivery.toCompanion());

  Future<void> upsertDeliveryFromServer(Map<String, dynamic> json) =>
      upsertDelivery(Delivery.fromJson(json));

  Future<bool> upsertDeliveryIfNewer(Map<String, dynamic> json) async {
    final incoming = Delivery.fromJson(json);
    final local = await findDelivery(incoming.id);
    if (local != null && incoming.version <= local.version) return false;
    await upsertDelivery(incoming);
    return true;
  }

  // -------------------------------------------------------------------------
  // Whole-device reads (the Tier-2 provider dashboard)
  // -------------------------------------------------------------------------
  //
  // The dashboard is an aggregate over everything cached on this phone, not
  // over one patient, so it needs the tables rather than a bundle. Nothing
  // here filters by patient: the pull only ever delivers rows the account may
  // see, so the local database already *is* the visible set.

  Stream<List<Pregnancy>> watchAllPregnancies() {
    return (select(pregnancies)..where((t) => t.deleted.equals(false)))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  Stream<List<AncContact>> watchAllContacts() {
    return (select(ancContacts)..where((t) => t.deleted.equals(false)))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  Stream<List<Delivery>> watchAllDeliveries() {
    return (select(deliveries)..where((t) => t.deleted.equals(false)))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  // -------------------------------------------------------------------------
  // Bundle
  // -------------------------------------------------------------------------

  /// S13 pregnancy dashboard. Four Drift streams combined into the same
  /// [PregnancyBundle] the server returns from `GET /pregnancies/:id`, so the
  /// screen cannot tell whether it is online.
  ///
  /// Emits nothing until the pregnancy row exists.
  Stream<PregnancyBundle> watchBundle(String pregnancyId) {
    final remindersStream = (select(reminders)
          ..where((t) => t.pregnancyId.equals(pregnancyId))
          ..orderBy([(t) => OrderingTerm.asc(t.dueAt)]))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());

    return combineLatest4<Pregnancy?, List<AncContact>, Delivery?,
        List<Reminder>, PregnancyBundle?>(
      watchById(pregnancyId),
      watchContacts(pregnancyId),
      watchDelivery(pregnancyId),
      remindersStream,
      (pregnancy, contacts, delivery, reminderList) {
        if (pregnancy == null) return null;
        return PregnancyBundle(
          pregnancy: pregnancy,
          ancContacts: contacts,
          delivery: delivery,
          reminders: reminderList,
        );
      },
    ).where((bundle) => bundle != null).cast<PregnancyBundle>();
  }
}
