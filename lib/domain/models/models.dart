import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'models.freezed.dart';
part 'models.g.dart';

/// Part A.2 entities. Field names map camelCase JSON <-> camelCase Dart 1:1
/// (spec §19 rule 7). Nothing here may be renamed.

// ---------------------------------------------------------------------------
// User
// ---------------------------------------------------------------------------

@freezed
abstract class User with _$User {
  const factory User({
    required String id,
    required String phone,
    required UserRole role,
    required String name,
    String? facilityId,
    String? facilityName,
    required String createdAt,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}

// ---------------------------------------------------------------------------
// Patient
// ---------------------------------------------------------------------------

@freezed
abstract class Patient with _$Patient {
  const factory Patient({
    required String id,
    required String ownerUserId,
    required String name,
    required Sex sex,
    required String dob,
    String? bloodGroup,
    int? ward,
    String? municipality,
    @Default(<String>[]) List<String> allergies,
    @Default(<String>[]) List<String> chronicConditions,
    String? emergencyContactPhone,
    @Default(0) int version,
    String? updatedAt,
    @Default(false) bool deleted,
  }) = _Patient;

  factory Patient.fromJson(Map<String, dynamic> json) => _$PatientFromJson(json);
}

// ---------------------------------------------------------------------------
// AccessGrant
// ---------------------------------------------------------------------------

@freezed
abstract class AccessGrant with _$AccessGrant {
  const factory AccessGrant({
    required String id,
    required String patientId,
    required GrantScope scope,
    String? token,
    required String expiresAt,
    String? redeemedByUserId,
    String? redeemedAt,
    String? revokedAt,
    String? accessUntil,

    /// A.7's printed fallback card: a year-long `read` grant that can only be
    /// redeemed with the patient's PIN beside it, and that grants a read-only
    /// view once redeemed. Additive — a server that does not send it leaves
    /// this false and the grant behaves exactly as before.
    @Default(false) bool longLived,

    /// Tier 3 — which parts of the record this grant covers.
    ///
    /// Additive and **optional**: omitted, or an empty list, means the whole
    /// record, which is what every grant issued before Tier 3 meant. See
    /// `docs/CONTRACT_ADDENDUM.md`.
    @Default(<GrantSection>[]) List<GrantSection> sections,
  }) = _AccessGrant;

  factory AccessGrant.fromJson(Map<String, dynamic> json) =>
      _$AccessGrantFromJson(json);
}

// ---------------------------------------------------------------------------
// Visit + nested value objects
// ---------------------------------------------------------------------------

@freezed
abstract class Vitals with _$Vitals {
  const factory Vitals({
    int? bpSys,
    int? bpDia,
    int? pulse,
    double? tempC,
    double? weightKg,
    int? spo2,
  }) = _Vitals;

  factory Vitals.fromJson(Map<String, dynamic> json) => _$VitalsFromJson(json);
}

@freezed
abstract class Referral with _$Referral {
  const factory Referral({
    String? facilityId,
    required String facilityName,
    required String reason,
    required ReferralUrgency urgency,
  }) = _Referral;

  factory Referral.fromJson(Map<String, dynamic> json) =>
      _$ReferralFromJson(json);
}

@freezed
abstract class Prescription with _$Prescription {
  const factory Prescription({
    required String id,
    required String drugCode,
    @Default('') String drugName,
    required String dose,
    required PrescriptionFrequency frequency,
    required int durationDays,
    String? instructionsNp,
  }) = _Prescription;

  factory Prescription.fromJson(Map<String, dynamic> json) =>
      _$PrescriptionFromJson(json);
}

@freezed
abstract class Visit with _$Visit {
  const factory Visit({
    required String id,
    required String patientId,
    @Default('') String providerUserId,
    @Default('') String providerName,
    String? facilityId,
    String? facilityName,
    required String visitAt,
    required String chiefComplaintCode,
    Vitals? vitals,
    @Default(<String>[]) List<String> diagnosisCodes,
    String? notes,
    String? advice,
    String? followUpAt,
    Referral? referral,
    @Default(<Prescription>[]) List<Prescription> prescriptions,
    String? supersedesId,
    @Default(0) int version,
    String? updatedAt,
    @Default(false) bool deleted,
  }) = _Visit;

  factory Visit.fromJson(Map<String, dynamic> json) => _$VisitFromJson(json);
}

// ---------------------------------------------------------------------------
// Document
// ---------------------------------------------------------------------------

@freezed
abstract class Document with _$Document {
  const factory Document({
    required String id,
    required String patientId,
    @Default('') String uploadedByUserId,
    required DocumentType type,
    required String title,
    required String takenAt,
    @Default(DocumentStatus.pendingUpload) DocumentStatus status,
    String? downloadUrl,
    String? aiSummary,
    @Default(AiSummaryStatus.none) AiSummaryStatus aiSummaryStatus,
    @Default(0) int version,
    String? updatedAt,
    @Default(false) bool deleted,
  }) = _Document;

  factory Document.fromJson(Map<String, dynamic> json) =>
      _$DocumentFromJson(json);
}

// ---------------------------------------------------------------------------
// Pregnancy
// ---------------------------------------------------------------------------

@freezed
abstract class BirthPlan with _$BirthPlan {
  const factory BirthPlan({
    String? facilityId,
    String? facilityName,
    String? transport,
    bool? moneySaved,
    String? bloodDonorName,
    String? bloodDonorPhone,
    String? companionName,
  }) = _BirthPlan;

  factory BirthPlan.fromJson(Map<String, dynamic> json) =>
      _$BirthPlanFromJson(json);
}

@freezed
abstract class Pregnancy with _$Pregnancy {
  const factory Pregnancy({
    required String id,
    required String patientId,
    String? lmp,
    required String edd,
    @Default(1) int gravida,
    @Default(0) int para,
    @Default(<String>[]) List<String> riskFactors,
    @Default(RiskLevel.normal) RiskLevel riskLevel,
    @Default(PregnancyStatus.active) PregnancyStatus status,
    BirthPlan? birthPlan,
    @Default('') String registeredByUserId,
    // Computed on read by the server; not stored (spec A.2).
    int? gestationalAgeDays,
    AncContact? nextContact,
    @Default(0) int version,
    String? updatedAt,
    @Default(false) bool deleted,
  }) = _Pregnancy;

  factory Pregnancy.fromJson(Map<String, dynamic> json) =>
      _$PregnancyFromJson(json);
}

// ---------------------------------------------------------------------------
// AncContact
// ---------------------------------------------------------------------------

@freezed
abstract class Findings with _$Findings {
  const factory Findings({
    double? weightKg,
    int? bpSys,
    int? bpDia,
    double? fundalHeightCm,
    int? fhrBpm,
    double? hbGdl,
    UrineProtein? urineProtein,
    bool? tdDoseGiven,
    bool? ifaGiven,
    bool? dewormingGiven,
    bool? calciumGiven,
    FetalMovement? fetalMovement,

    /// Tier 3 — free text the health worker dictated or typed on S13.
    ///
    /// Additive and **inside `findings`** on purpose: `AncContact` itself is
    /// pinned by Part A, and `findings` is already a free-form JSON object on
    /// both sides. A server that does not know this field round-trips it or
    /// drops it; either way nothing else changes. See
    /// `docs/CONTRACT_ADDENDUM.md`.
    String? notesText,
  }) = _Findings;

  factory Findings.fromJson(Map<String, dynamic> json) =>
      _$FindingsFromJson(json);
}

@freezed
abstract class AncContact with _$AncContact {
  const factory AncContact({
    required String id,
    required String pregnancyId,
    required int contactNo,
    required int weekTarget,
    required String dueAt,
    String? doneAt,
    String? providerUserId,
    Findings? findings,
    @Default(<String>[]) List<String> dangerSigns,
    TriageLevel? triageLevel,
    @Default(<String>[]) List<String> triageReasons,
    Referral? referral,
    @Default(0) int version,
    String? updatedAt,
    @Default(false) bool deleted,
  }) = _AncContact;

  factory AncContact.fromJson(Map<String, dynamic> json) =>
      _$AncContactFromJson(json);
}

// ---------------------------------------------------------------------------
// Delivery
// ---------------------------------------------------------------------------

@freezed
abstract class Delivery with _$Delivery {
  const factory Delivery({
    required String id,
    required String pregnancyId,
    required String deliveredAt,
    required DeliveryPlace place,
    required DeliveryMode mode,
    required DeliveryOutcome outcome,
    double? babyWeightKg,
    Sex? babySex,
    @Default(<String>[]) List<String> complications,
    @Default(0) int version,
    String? updatedAt,
    @Default(false) bool deleted,
  }) = _Delivery;

  factory Delivery.fromJson(Map<String, dynamic> json) =>
      _$DeliveryFromJson(json);
}

// ---------------------------------------------------------------------------
// Child health (Tier 3 — see docs/CONTRACT_ADDENDUM.md)
// ---------------------------------------------------------------------------

/// One scheduled or administered dose on the national EPI schedule.
///
/// Additive to Part A: a new syncable table, not a change to an existing one.
/// Ids are deterministic on both sides in the same style as A.8.15's ANC
/// contacts, so a schedule generated offline the day a child is registered
/// lands on the same rows the server generates rather than doubling them.
@freezed
abstract class Immunisation with _$Immunisation {
  const factory Immunisation({
    required String id,
    required String patientId,
    required String vaccineCode,
    required int doseNo,

    /// `YYYY-MM-DD`, derived from the child's date of birth.
    required String dueAt,

    /// ISO instant, null until somebody gives the dose.
    String? givenAt,
    String? givenByUserId,
    String? batchNo,
    @Default(0) int version,
    String? updatedAt,
    @Default(false) bool deleted,
  }) = _Immunisation;

  factory Immunisation.fromJson(Map<String, dynamic> json) =>
      _$ImmunisationFromJson(json);
}

/// One weight / height / MUAC measurement.
@freezed
abstract class GrowthMeasurement with _$GrowthMeasurement {
  const factory GrowthMeasurement({
    required String id,
    required String patientId,

    /// ISO instant.
    required String measuredAt,
    required double weightKg,
    double? heightCm,
    double? muacCm,
    @Default(0) int version,
    String? updatedAt,
    @Default(false) bool deleted,
  }) = _GrowthMeasurement;

  factory GrowthMeasurement.fromJson(Map<String, dynamic> json) =>
      _$GrowthMeasurementFromJson(json);
}

// ---------------------------------------------------------------------------
// Reminder / Facility / AuditEntry / CodeListItem — server-owned, read-only
// ---------------------------------------------------------------------------

@freezed
abstract class Reminder with _$Reminder {
  const factory Reminder({
    required String id,
    required String patientId,
    String? pregnancyId,
    required ReminderKind kind,
    required String dueAt,
    @Default(ReminderChannel.sms) ReminderChannel channel,
    @Default('') String recipientPhone,
    @Default(RecipientRole.patient) RecipientRole recipientRole,
    @Default('') String messageNp,
    @Default('') String messageEn,
    @Default(ReminderStatus.pending) ReminderStatus status,
    String? sentAt,
  }) = _Reminder;

  factory Reminder.fromJson(Map<String, dynamic> json) =>
      _$ReminderFromJson(json);
}

@freezed
abstract class Facility with _$Facility {
  const factory Facility({
    required String id,
    required String name,
    required FacilityType type,
    @Default(false) bool hasBirthingCentre,
    String? phone,
    @Default(0) double lat,
    @Default(0) double lng,
    @Default('') String municipality,
    double? distanceKm,
  }) = _Facility;

  factory Facility.fromJson(Map<String, dynamic> json) =>
      _$FacilityFromJson(json);
}

@freezed
abstract class AuditEntry with _$AuditEntry {
  const factory AuditEntry({
    required String id,
    required String patientId,
    required String actorUserId,
    @Default('') String actorName,
    String? actorFacilityName,
    required AuditAction action,
    required String at,
  }) = _AuditEntry;

  factory AuditEntry.fromJson(Map<String, dynamic> json) =>
      _$AuditEntryFromJson(json);
}

@freezed
abstract class CodeListItem with _$CodeListItem {
  const factory CodeListItem({
    required CodeListKind kind,
    required String code,
    required String labelEn,
    required String labelNp,
    Map<String, dynamic>? meta,
  }) = _CodeListItem;

  factory CodeListItem.fromJson(Map<String, dynamic> json) =>
      _$CodeListItemFromJson(json);
}

// ---------------------------------------------------------------------------
// TimelineItem + summary block
// ---------------------------------------------------------------------------

@freezed
abstract class TimelineItem with _$TimelineItem {
  const factory TimelineItem({
    required TimelineKind kind,
    required String at,
    required String title,
    String? subtitle,
    String? badge,
    required String refId,
    @Default(<String, dynamic>{}) Map<String, dynamic> payload,
  }) = _TimelineItem;

  factory TimelineItem.fromJson(Map<String, dynamic> json) =>
      _$TimelineItemFromJson(json);
}

@freezed
abstract class ActiveProblem with _$ActiveProblem {
  const factory ActiveProblem({
    required String code,
    @Default('') String labelEn,
    @Default('') String labelNp,
    String? since,
  }) = _ActiveProblem;

  factory ActiveProblem.fromJson(Map<String, dynamic> json) =>
      _$ActiveProblemFromJson(json);
}

@freezed
abstract class LastVitals with _$LastVitals {
  const factory LastVitals({
    int? bpSys,
    int? bpDia,
    double? weightKg,
    String? at,
  }) = _LastVitals;

  factory LastVitals.fromJson(Map<String, dynamic> json) =>
      _$LastVitalsFromJson(json);
}

@freezed
abstract class PatientSummary with _$PatientSummary {
  const factory PatientSummary({
    @Default(<ActiveProblem>[]) List<ActiveProblem> activeProblems,
    @Default(<Prescription>[]) List<Prescription> currentMedicines,
    @Default(<String>[]) List<String> allergies,
    LastVitals? lastVitals,
    Pregnancy? activePregnancy,
    String? lastVisitAt,
    @Default(0) int visitCount,
  }) = _PatientSummary;

  factory PatientSummary.fromJson(Map<String, dynamic> json) =>
      _$PatientSummaryFromJson(json);
}

// ---------------------------------------------------------------------------
// Config flags (GET /config)
// ---------------------------------------------------------------------------

@freezed
abstract class AppConfigFlags with _$AppConfigFlags {
  const factory AppConfigFlags({
    @Default('mock') String smsMode,
    @Default(false) bool aiSummaryEnabled,
    @Default(true) bool otpDemo,
    @Default('') String rulesVersion,
    @Default('') String codelistVersion,

    /// Tier 3 — integrations that need government API access (additive, all
    /// false until somebody has it). They exist so the Settings rows can light
    /// up without an app change; see `docs/CONTRACT_ADDENDUM.md`.
    @Default(false) bool nidEnabled,
    @Default(false) bool hmisExportEnabled,
    @Default(false) bool councilVerifyEnabled,
  }) = _AppConfigFlags;

  factory AppConfigFlags.fromJson(Map<String, dynamic> json) =>
      _$AppConfigFlagsFromJson(json);
}

// ---------------------------------------------------------------------------
// Auth payloads
// ---------------------------------------------------------------------------

@freezed
abstract class OtpRequestResult with _$OtpRequestResult {
  const factory OtpRequestResult({
    required String otpSentTo,
    @Default(300) int expiresInSec,
    String? demoOtp,
  }) = _OtpRequestResult;

  factory OtpRequestResult.fromJson(Map<String, dynamic> json) =>
      _$OtpRequestResultFromJson(json);
}

@freezed
abstract class OtpVerifyResult with _$OtpVerifyResult {
  const factory OtpVerifyResult({
    required String tempToken,
    @Default(false) bool hasPin,
    @Default(false) bool isNewUser,
  }) = _OtpVerifyResult;

  factory OtpVerifyResult.fromJson(Map<String, dynamic> json) =>
      _$OtpVerifyResultFromJson(json);
}

@freezed
abstract class AuthSession with _$AuthSession {
  const factory AuthSession({
    required String accessToken,
    required String refreshToken,
    required User user,
  }) = _AuthSession;

  factory AuthSession.fromJson(Map<String, dynamic> json) =>
      _$AuthSessionFromJson(json);
}

@freezed
abstract class RefreshResult with _$RefreshResult {
  const factory RefreshResult({
    required String accessToken,
    required String refreshToken,
  }) = _RefreshResult;

  factory RefreshResult.fromJson(Map<String, dynamic> json) =>
      _$RefreshResultFromJson(json);
}

// ---------------------------------------------------------------------------
// Grants / redeem bundle
// ---------------------------------------------------------------------------

@freezed
abstract class GrantCreateResult with _$GrantCreateResult {
  const factory GrantCreateResult({
    required AccessGrant grant,
    required String token,
    required String qrPayload,
  }) = _GrantCreateResult;

  factory GrantCreateResult.fromJson(Map<String, dynamic> json) =>
      _$GrantCreateResultFromJson(json);
}

@freezed
abstract class RedeemResult with _$RedeemResult {
  const factory RedeemResult({
    required AccessGrant grant,
    required Patient patient,
    required PatientSummary summary,
    @Default(<TimelineItem>[]) List<TimelineItem> timeline,
    Pregnancy? pregnancy,
    @Default(<AncContact>[]) List<AncContact> ancContacts,
  }) = _RedeemResult;

  factory RedeemResult.fromJson(Map<String, dynamic> json) =>
      _$RedeemResultFromJson(json);
}

// ---------------------------------------------------------------------------
// Bundles returned by read endpoints
// ---------------------------------------------------------------------------

@freezed
abstract class PatientDetail with _$PatientDetail {
  const factory PatientDetail({
    required Patient patient,
    required PatientSummary summary,
  }) = _PatientDetail;

  factory PatientDetail.fromJson(Map<String, dynamic> json) =>
      _$PatientDetailFromJson(json);
}

@freezed
abstract class PregnancyBundle with _$PregnancyBundle {
  const factory PregnancyBundle({
    required Pregnancy pregnancy,
    @Default(<AncContact>[]) List<AncContact> ancContacts,
    Delivery? delivery,
    @Default(<Reminder>[]) List<Reminder> reminders,
  }) = _PregnancyBundle;

  factory PregnancyBundle.fromJson(Map<String, dynamic> json) =>
      _$PregnancyBundleFromJson(json);
}

@freezed
abstract class PregnancyCreateResult with _$PregnancyCreateResult {
  const factory PregnancyCreateResult({
    required Pregnancy pregnancy,
    @Default(<AncContact>[]) List<AncContact> ancContacts,
  }) = _PregnancyCreateResult;

  factory PregnancyCreateResult.fromJson(Map<String, dynamic> json) =>
      _$PregnancyCreateResultFromJson(json);
}

@freezed
abstract class AncContactResult with _$AncContactResult {
  const factory AncContactResult({
    required AncContact ancContact,
    Facility? nearestReferral,
  }) = _AncContactResult;

  factory AncContactResult.fromJson(Map<String, dynamic> json) =>
      _$AncContactResultFromJson(json);
}

@freezed
abstract class DeliveryResult with _$DeliveryResult {
  const factory DeliveryResult({
    required Delivery delivery,
    required Pregnancy pregnancy,
  }) = _DeliveryResult;

  factory DeliveryResult.fromJson(Map<String, dynamic> json) =>
      _$DeliveryResultFromJson(json);
}

@freezed
abstract class TimelinePage with _$TimelinePage {
  const factory TimelinePage({
    @Default(<TimelineItem>[]) List<TimelineItem> items,
    String? nextBefore,
  }) = _TimelinePage;

  factory TimelinePage.fromJson(Map<String, dynamic> json) =>
      _$TimelinePageFromJson(json);
}

@freezed
abstract class CodeListResponse with _$CodeListResponse {
  const factory CodeListResponse({
    @Default('') String version,
    @Default(<CodeListItem>[]) List<CodeListItem> items,
  }) = _CodeListResponse;

  factory CodeListResponse.fromJson(Map<String, dynamic> json) =>
      _$CodeListResponseFromJson(json);
}

// ---------------------------------------------------------------------------
// Documents upload handshake
// ---------------------------------------------------------------------------

@freezed
abstract class PresignResult with _$PresignResult {
  const factory PresignResult({
    required Document document,
    required String uploadUrl,
    @Default('PUT') String uploadMethod,
    @Default(<String, String>{}) Map<String, String> uploadHeaders,
    @Default(900) int expiresInSec,
  }) = _PresignResult;

  factory PresignResult.fromJson(Map<String, dynamic> json) =>
      _$PresignResultFromJson(json);
}

// ---------------------------------------------------------------------------
// Sync protocol (A.4 /sync/push, /sync/pull)
// ---------------------------------------------------------------------------

@freezed
abstract class SyncChange with _$SyncChange {
  const factory SyncChange({
    required String opId,
    required String table,
    required String op,
    required String rowId,
    required int baseVersion,
    @Default(<String, dynamic>{}) Map<String, dynamic> payload,
  }) = _SyncChange;

  factory SyncChange.fromJson(Map<String, dynamic> json) =>
      _$SyncChangeFromJson(json);
}

@freezed
abstract class SyncOpError with _$SyncOpError {
  const factory SyncOpError({
    required String code,
    @Default('') String message,
  }) = _SyncOpError;

  factory SyncOpError.fromJson(Map<String, dynamic> json) =>
      _$SyncOpErrorFromJson(json);
}

@freezed
abstract class SyncPushResult with _$SyncPushResult {
  const factory SyncPushResult({
    required String opId,
    required SyncOpStatus status,
    Map<String, dynamic>? row,
    Map<String, dynamic>? current,
    SyncOpError? error,
  }) = _SyncPushResult;

  factory SyncPushResult.fromJson(Map<String, dynamic> json) =>
      _$SyncPushResultFromJson(json);
}

@freezed
abstract class SyncPushResponse with _$SyncPushResponse {
  const factory SyncPushResponse({
    @Default(<SyncPushResult>[]) List<SyncPushResult> results,
    required String serverTime,
  }) = _SyncPushResponse;

  factory SyncPushResponse.fromJson(Map<String, dynamic> json) =>
      _$SyncPushResponseFromJson(json);
}

@freezed
abstract class SyncPullChange with _$SyncPullChange {
  const factory SyncPullChange({
    required String table,
    @Default(<String, dynamic>{}) Map<String, dynamic> row,
  }) = _SyncPullChange;

  factory SyncPullChange.fromJson(Map<String, dynamic> json) =>
      _$SyncPullChangeFromJson(json);
}

@freezed
abstract class SyncPullResponse with _$SyncPullResponse {
  const factory SyncPullResponse({
    @Default(<SyncPullChange>[]) List<SyncPullChange> changes,
    required String cursor,
    @Default(false) bool hasMore,
  }) = _SyncPullResponse;

  factory SyncPullResponse.fromJson(Map<String, dynamic> json) =>
      _$SyncPullResponseFromJson(json);
}

// ---------------------------------------------------------------------------
// Demo SMS panel (GET /demo/sms)
// ---------------------------------------------------------------------------

@freezed
abstract class DemoSms with _$DemoSms {
  const factory DemoSms({
    required String to,
    required String text,
    required String sentAt,
  }) = _DemoSms;

  factory DemoSms.fromJson(Map<String, dynamic> json) => _$DemoSmsFromJson(json);
}
