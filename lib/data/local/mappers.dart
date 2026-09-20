import 'package:drift/drift.dart';

import '../../domain/models/models.dart';
import 'app_database.dart';

/// Row ↔ model mapping.
///
/// Drift row classes (`PatientRow`) are what sqlite holds; the freezed models
/// (`Patient`) are what every layer above the DAOs passes around. Field names
/// are identical on both sides, so these are pure copies with two rules:
///
///  * **Device-only columns never appear in a model.** `patients.access_until`,
///    `documents.local_path` and `documents.upload_attempts` are left
///    [Value.absent] by the model→companion direction, so writing a row that
///    came from the server cannot wipe them (drift only emits the columns a
///    companion actually carries).
///  * **Server-computed fields are never stored.** `Pregnancy.gestationalAgeDays`,
///    `Pregnancy.nextContact` and `Facility.distanceKm` are derived on read, so
///    the row→model direction leaves them null and the caller fills them in.

// ---------------------------------------------------------------------------
// User
// ---------------------------------------------------------------------------

extension UserRowMapper on UserRow {
  User toModel() => User(
        id: id,
        phone: phone,
        role: role,
        name: name,
        facilityId: facilityId,
        facilityName: facilityName,
        createdAt: createdAt,
      );
}

extension UserMapper on User {
  UsersCompanion toCompanion() => UsersCompanion(
        id: Value(id),
        phone: Value(phone),
        role: Value(role),
        name: Value(name),
        facilityId: Value(facilityId),
        facilityName: Value(facilityName),
        createdAt: Value(createdAt),
      );
}

// ---------------------------------------------------------------------------
// Patient
// ---------------------------------------------------------------------------

extension PatientRowMapper on PatientRow {
  Patient toModel() => Patient(
        id: id,
        ownerUserId: ownerUserId,
        name: name,
        sex: sex,
        dob: dob,
        bloodGroup: bloodGroup,
        ward: ward,
        municipality: municipality,
        allergies: allergies,
        chronicConditions: chronicConditions,
        emergencyContactPhone: emergencyContactPhone,
        version: version,
        updatedAt: updatedAt,
        deleted: deleted,
      );
}

extension PatientMapper on Patient {
  /// [accessUntil] is only passed when a QR redeem caches someone else's
  /// patient; every other write leaves the column untouched.
  PatientsCompanion toCompanion({
    Value<String?> accessUntil = const Value.absent(),
  }) =>
      PatientsCompanion(
        id: Value(id),
        ownerUserId: Value(ownerUserId),
        name: Value(name),
        sex: Value(sex),
        dob: Value(dob),
        bloodGroup: Value(bloodGroup),
        ward: Value(ward),
        municipality: Value(municipality),
        allergies: Value(allergies),
        chronicConditions: Value(chronicConditions),
        emergencyContactPhone: Value(emergencyContactPhone),
        version: Value(version),
        updatedAt: Value(updatedAt),
        deleted: Value(deleted),
        accessUntil: accessUntil,
      );
}

// ---------------------------------------------------------------------------
// Visit
// ---------------------------------------------------------------------------

extension VisitRowMapper on VisitRow {
  Visit toModel() => Visit(
        id: id,
        patientId: patientId,
        providerUserId: providerUserId,
        providerName: providerName,
        facilityId: facilityId,
        facilityName: facilityName,
        visitAt: visitAt,
        chiefComplaintCode: chiefComplaintCode,
        vitals: vitals,
        diagnosisCodes: diagnosisCodes,
        notes: notes,
        advice: advice,
        followUpAt: followUpAt,
        referral: referral,
        prescriptions: prescriptions,
        supersedesId: supersedesId,
        version: version,
        updatedAt: updatedAt,
        deleted: deleted,
      );
}

extension VisitMapper on Visit {
  VisitsCompanion toCompanion() => VisitsCompanion(
        id: Value(id),
        patientId: Value(patientId),
        providerUserId: Value(providerUserId),
        providerName: Value(providerName),
        facilityId: Value(facilityId),
        facilityName: Value(facilityName),
        visitAt: Value(visitAt),
        chiefComplaintCode: Value(chiefComplaintCode),
        vitals: Value(vitals),
        diagnosisCodes: Value(diagnosisCodes),
        notes: Value(notes),
        advice: Value(advice),
        followUpAt: Value(followUpAt),
        referral: Value(referral),
        prescriptions: Value(prescriptions),
        supersedesId: Value(supersedesId),
        version: Value(version),
        updatedAt: Value(updatedAt),
        deleted: Value(deleted),
      );
}

// ---------------------------------------------------------------------------
// Document
// ---------------------------------------------------------------------------

extension DocumentRowMapper on DocumentRow {
  Document toModel() => Document(
        id: id,
        patientId: patientId,
        uploadedByUserId: uploadedByUserId,
        type: type,
        title: title,
        takenAt: takenAt,
        status: status,
        downloadUrl: downloadUrl,
        aiSummary: aiSummary,
        aiSummaryStatus: aiSummaryStatus,
        version: version,
        updatedAt: updatedAt,
        deleted: deleted,
      );
}

extension DocumentMapper on Document {
  /// [localPath] and [uploadAttempts] belong to the upload worker, so a write
  /// coming from the server leaves them alone.
  DocumentsCompanion toCompanion({
    Value<String?> localPath = const Value.absent(),
    Value<int> uploadAttempts = const Value.absent(),
  }) =>
      DocumentsCompanion(
        id: Value(id),
        patientId: Value(patientId),
        uploadedByUserId: Value(uploadedByUserId),
        type: Value(type),
        title: Value(title),
        takenAt: Value(takenAt),
        status: Value(status),
        downloadUrl: Value(downloadUrl),
        aiSummary: Value(aiSummary),
        aiSummaryStatus: Value(aiSummaryStatus),
        version: Value(version),
        updatedAt: Value(updatedAt),
        deleted: Value(deleted),
        localPath: localPath,
        uploadAttempts: uploadAttempts,
      );
}

// ---------------------------------------------------------------------------
// Pregnancy
// ---------------------------------------------------------------------------

extension PregnancyRowMapper on PregnancyRow {
  /// `gestationalAgeDays` and `nextContact` are computed on read (spec A.2) and
  /// are deliberately left null here.
  Pregnancy toModel() => Pregnancy(
        id: id,
        patientId: patientId,
        lmp: lmp,
        edd: edd,
        gravida: gravida,
        para: para,
        riskFactors: riskFactors,
        riskLevel: riskLevel,
        status: status,
        birthPlan: birthPlan,
        registeredByUserId: registeredByUserId,
        version: version,
        updatedAt: updatedAt,
        deleted: deleted,
      );
}

extension PregnancyMapper on Pregnancy {
  PregnanciesCompanion toCompanion() => PregnanciesCompanion(
        id: Value(id),
        patientId: Value(patientId),
        lmp: Value(lmp),
        edd: Value(edd),
        gravida: Value(gravida),
        para: Value(para),
        riskFactors: Value(riskFactors),
        riskLevel: Value(riskLevel),
        status: Value(status),
        birthPlan: Value(birthPlan),
        registeredByUserId: Value(registeredByUserId),
        version: Value(version),
        updatedAt: Value(updatedAt),
        deleted: Value(deleted),
      );
}

// ---------------------------------------------------------------------------
// AncContact
// ---------------------------------------------------------------------------

extension AncContactRowMapper on AncContactRow {
  AncContact toModel() => AncContact(
        id: id,
        pregnancyId: pregnancyId,
        contactNo: contactNo,
        weekTarget: weekTarget,
        dueAt: dueAt,
        doneAt: doneAt,
        providerUserId: providerUserId,
        findings: findings,
        dangerSigns: dangerSigns,
        triageLevel: triageLevel,
        triageReasons: triageReasons,
        referral: referral,
        version: version,
        updatedAt: updatedAt,
        deleted: deleted,
      );
}

extension AncContactMapper on AncContact {
  AncContactsCompanion toCompanion() => AncContactsCompanion(
        id: Value(id),
        pregnancyId: Value(pregnancyId),
        contactNo: Value(contactNo),
        weekTarget: Value(weekTarget),
        dueAt: Value(dueAt),
        doneAt: Value(doneAt),
        providerUserId: Value(providerUserId),
        findings: Value(findings),
        dangerSigns: Value(dangerSigns),
        triageLevel: Value(triageLevel),
        triageReasons: Value(triageReasons),
        referral: Value(referral),
        version: Value(version),
        updatedAt: Value(updatedAt),
        deleted: Value(deleted),
      );
}

// ---------------------------------------------------------------------------
// Delivery
// ---------------------------------------------------------------------------

extension DeliveryRowMapper on DeliveryRow {
  Delivery toModel() => Delivery(
        id: id,
        pregnancyId: pregnancyId,
        deliveredAt: deliveredAt,
        place: place,
        mode: mode,
        outcome: outcome,
        babyWeightKg: babyWeightKg,
        babySex: babySex,
        complications: complications,
        version: version,
        updatedAt: updatedAt,
        deleted: deleted,
      );
}

extension DeliveryMapper on Delivery {
  DeliveriesCompanion toCompanion() => DeliveriesCompanion(
        id: Value(id),
        pregnancyId: Value(pregnancyId),
        deliveredAt: Value(deliveredAt),
        place: Value(place),
        mode: Value(mode),
        outcome: Value(outcome),
        babyWeightKg: Value(babyWeightKg),
        babySex: Value(babySex),
        complications: Value(complications),
        version: Value(version),
        updatedAt: Value(updatedAt),
        deleted: Value(deleted),
      );
}

extension ImmunisationRowMapper on ImmunisationRow {
  Immunisation toModel() => Immunisation(
        id: id,
        patientId: patientId,
        vaccineCode: vaccineCode,
        doseNo: doseNo,
        dueAt: dueAt,
        givenAt: givenAt,
        givenByUserId: givenByUserId,
        batchNo: batchNo,
        version: version,
        updatedAt: updatedAt,
        deleted: deleted,
      );
}

extension ImmunisationMapper on Immunisation {
  ImmunisationsCompanion toCompanion() => ImmunisationsCompanion(
        id: Value(id),
        patientId: Value(patientId),
        vaccineCode: Value(vaccineCode),
        doseNo: Value(doseNo),
        dueAt: Value(dueAt),
        givenAt: Value(givenAt),
        givenByUserId: Value(givenByUserId),
        batchNo: Value(batchNo),
        version: Value(version),
        updatedAt: Value(updatedAt),
        deleted: Value(deleted),
      );
}

extension GrowthMeasurementRowMapper on GrowthMeasurementRow {
  GrowthMeasurement toModel() => GrowthMeasurement(
        id: id,
        patientId: patientId,
        measuredAt: measuredAt,
        weightKg: weightKg,
        heightCm: heightCm,
        muacCm: muacCm,
        version: version,
        updatedAt: updatedAt,
        deleted: deleted,
      );
}

extension GrowthMeasurementMapper on GrowthMeasurement {
  GrowthMeasurementsCompanion toCompanion() => GrowthMeasurementsCompanion(
        id: Value(id),
        patientId: Value(patientId),
        measuredAt: Value(measuredAt),
        weightKg: Value(weightKg),
        heightCm: Value(heightCm),
        muacCm: Value(muacCm),
        version: Value(version),
        updatedAt: Value(updatedAt),
        deleted: Value(deleted),
      );
}

// ---------------------------------------------------------------------------
// Read-only caches
// ---------------------------------------------------------------------------

extension ReminderRowMapper on ReminderRow {
  Reminder toModel() => Reminder(
        id: id,
        patientId: patientId,
        pregnancyId: pregnancyId,
        kind: kind,
        dueAt: dueAt,
        channel: channel,
        recipientPhone: recipientPhone,
        recipientRole: recipientRole,
        messageNp: messageNp,
        messageEn: messageEn,
        status: status,
        sentAt: sentAt,
      );
}

extension ReminderMapper on Reminder {
  RemindersCompanion toCompanion() => RemindersCompanion(
        id: Value(id),
        patientId: Value(patientId),
        pregnancyId: Value(pregnancyId),
        kind: Value(kind),
        dueAt: Value(dueAt),
        channel: Value(channel),
        recipientPhone: Value(recipientPhone),
        recipientRole: Value(recipientRole),
        messageNp: Value(messageNp),
        messageEn: Value(messageEn),
        status: Value(status),
        sentAt: Value(sentAt),
      );
}

extension AuditEntryRowMapper on AuditEntryRow {
  AuditEntry toModel() => AuditEntry(
        id: id,
        patientId: patientId,
        actorUserId: actorUserId,
        actorName: actorName,
        actorFacilityName: actorFacilityName,
        action: action,
        at: at,
      );
}

extension AuditEntryMapper on AuditEntry {
  AuditEntriesCompanion toCompanion() => AuditEntriesCompanion(
        id: Value(id),
        patientId: Value(patientId),
        actorUserId: Value(actorUserId),
        actorName: Value(actorName),
        actorFacilityName: Value(actorFacilityName),
        action: Value(action),
        at: Value(at),
      );
}

extension FacilityRowMapper on FacilityRow {
  /// `distanceKm` comes from `/facilities/nearby` and is not cached.
  Facility toModel() => Facility(
        id: id,
        name: name,
        type: type,
        hasBirthingCentre: hasBirthingCentre,
        phone: phone,
        lat: lat,
        lng: lng,
        municipality: municipality,
      );
}

extension FacilityMapper on Facility {
  FacilitiesCompanion toCompanion() => FacilitiesCompanion(
        id: Value(id),
        name: Value(name),
        type: Value(type),
        hasBirthingCentre: Value(hasBirthingCentre),
        phone: Value(phone),
        lat: Value(lat),
        lng: Value(lng),
        municipality: Value(municipality),
      );
}

extension CodelistItemRowMapper on CodelistItemRow {
  CodeListItem toModel() => CodeListItem(
        kind: kind,
        code: code,
        labelEn: labelEn,
        labelNp: labelNp,
        meta: meta,
      );
}

extension CodeListItemMapper on CodeListItem {
  CodelistItemsCompanion toCompanion() => CodelistItemsCompanion(
        kind: Value(kind),
        code: Value(code),
        labelEn: Value(labelEn),
        labelNp: Value(labelNp),
        meta: Value(meta),
      );
}
