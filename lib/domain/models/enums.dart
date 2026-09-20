import 'package:json_annotation/json_annotation.dart';

/// Enums from Part A.2. Every `@JsonValue` is the exact wire string — changing
/// one breaks the contract with the backend (spec §19 rule 1).

enum UserRole {
  @JsonValue('patient')
  patient,
  @JsonValue('provider')
  provider,
  @JsonValue('fchv')
  fchv,
  @JsonValue('admin')
  admin;

  String get wire => switch (this) {
        UserRole.patient => 'patient',
        UserRole.provider => 'provider',
        UserRole.fchv => 'fchv',
        UserRole.admin => 'admin',
      };

  static UserRole fromWire(String? value) => switch (value) {
        'provider' => UserRole.provider,
        'fchv' => UserRole.fchv,
        'admin' => UserRole.admin,
        _ => UserRole.patient,
      };

  /// Providers and FCHVs land on S19; everyone else on S06.
  bool get isHealthWorker => this == UserRole.provider || this == UserRole.fchv;
}

enum Sex {
  @JsonValue('female')
  female,
  @JsonValue('male')
  male,
  @JsonValue('other')
  other;

  String get wire => switch (this) {
        Sex.female => 'female',
        Sex.male => 'male',
        Sex.other => 'other',
      };

  static Sex fromWire(String? value) => switch (value) {
        'male' => Sex.male,
        'other' => Sex.other,
        _ => Sex.female,
      };
}

enum GrantScope {
  @JsonValue('read')
  read,
  @JsonValue('append')
  append;

  String get wire => this == GrantScope.append ? 'append' : 'read';
}

/// Tier 3 — the parts of a record a QR grant can cover.
///
/// Additive to Part A. A grant with no sections covers everything, which is
/// what every grant meant before this existed; see
/// `docs/CONTRACT_ADDENDUM.md`.
enum GrantSection {
  @JsonValue('summary')
  summary,
  @JsonValue('visits')
  visits,
  @JsonValue('documents')
  documents,
  @JsonValue('pregnancy')
  pregnancy,
  @JsonValue('child')
  child,
  @JsonValue('audit')
  audit;

  String get wire => switch (this) {
        GrantSection.summary => 'summary',
        GrantSection.visits => 'visits',
        GrantSection.documents => 'documents',
        GrantSection.pregnancy => 'pregnancy',
        GrantSection.child => 'child',
        GrantSection.audit => 'audit',
      };

  static GrantSection? fromWire(String value) {
    for (final s in GrantSection.values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

enum PrescriptionFrequency {
  @JsonValue('OD')
  od,
  @JsonValue('BD')
  bd,
  @JsonValue('TDS')
  tds,
  @JsonValue('QID')
  qid,
  @JsonValue('SOS')
  sos,
  @JsonValue('HS')
  hs;

  String get wire => switch (this) {
        PrescriptionFrequency.od => 'OD',
        PrescriptionFrequency.bd => 'BD',
        PrescriptionFrequency.tds => 'TDS',
        PrescriptionFrequency.qid => 'QID',
        PrescriptionFrequency.sos => 'SOS',
        PrescriptionFrequency.hs => 'HS',
      };
}

enum ReferralUrgency {
  @JsonValue('routine')
  routine,
  @JsonValue('urgent')
  urgent;

  String get wire => this == ReferralUrgency.urgent ? 'urgent' : 'routine';
}

enum DocumentType {
  @JsonValue('prescription')
  prescription,
  @JsonValue('lab')
  lab,
  @JsonValue('discharge')
  discharge,
  @JsonValue('referral')
  referral,
  @JsonValue('other')
  other;

  String get wire => switch (this) {
        DocumentType.prescription => 'prescription',
        DocumentType.lab => 'lab',
        DocumentType.discharge => 'discharge',
        DocumentType.referral => 'referral',
        DocumentType.other => 'other',
      };
}

enum DocumentStatus {
  @JsonValue('pending_upload')
  pendingUpload,
  @JsonValue('uploaded')
  uploaded;

  String get wire =>
      this == DocumentStatus.uploaded ? 'uploaded' : 'pending_upload';
}

enum AiSummaryStatus {
  @JsonValue('none')
  none,
  @JsonValue('queued')
  queued,
  @JsonValue('done')
  done,
  @JsonValue('failed')
  failed;

  String get wire => switch (this) {
        AiSummaryStatus.none => 'none',
        AiSummaryStatus.queued => 'queued',
        AiSummaryStatus.done => 'done',
        AiSummaryStatus.failed => 'failed',
      };
}

enum RiskLevel {
  @JsonValue('normal')
  normal,
  @JsonValue('high')
  high;

  String get wire => this == RiskLevel.high ? 'high' : 'normal';
}

enum PregnancyStatus {
  @JsonValue('active')
  active,
  @JsonValue('delivered')
  delivered,
  @JsonValue('ended')
  ended;

  String get wire => switch (this) {
        PregnancyStatus.active => 'active',
        PregnancyStatus.delivered => 'delivered',
        PregnancyStatus.ended => 'ended',
      };
}

enum UrineProtein {
  @JsonValue('neg')
  neg,
  @JsonValue('trace')
  trace,
  @JsonValue('+')
  one,
  @JsonValue('++')
  two,
  @JsonValue('+++')
  three;

  String get wire => switch (this) {
        UrineProtein.neg => 'neg',
        UrineProtein.trace => 'trace',
        UrineProtein.one => '+',
        UrineProtein.two => '++',
        UrineProtein.three => '+++',
      };

  /// Spec A.5 triage: proteinuria means one of "+", "++", "+++".
  bool get isProteinuria =>
      this == UrineProtein.one || this == UrineProtein.two || this == UrineProtein.three;
}

enum FetalMovement {
  @JsonValue('normal')
  normal,
  @JsonValue('reduced')
  reduced,
  @JsonValue('absent')
  absent;

  String get wire => switch (this) {
        FetalMovement.normal => 'normal',
        FetalMovement.reduced => 'reduced',
        FetalMovement.absent => 'absent',
      };
}

enum TriageLevel {
  @JsonValue('green')
  green,
  @JsonValue('amber')
  amber,
  @JsonValue('red')
  red;

  String get wire => switch (this) {
        TriageLevel.green => 'green',
        TriageLevel.amber => 'amber',
        TriageLevel.red => 'red',
      };

  static TriageLevel? fromWire(String? value) => switch (value) {
        'green' => TriageLevel.green,
        'amber' => TriageLevel.amber,
        'red' => TriageLevel.red,
        _ => null,
      };
}

enum DeliveryPlace {
  @JsonValue('home')
  home,
  @JsonValue('birthing_centre')
  birthingCentre,
  @JsonValue('hospital')
  hospital,
  @JsonValue('on_the_way')
  onTheWay;

  String get wire => switch (this) {
        DeliveryPlace.home => 'home',
        DeliveryPlace.birthingCentre => 'birthing_centre',
        DeliveryPlace.hospital => 'hospital',
        DeliveryPlace.onTheWay => 'on_the_way',
      };
}

enum DeliveryMode {
  @JsonValue('normal')
  normal,
  @JsonValue('assisted')
  assisted,
  @JsonValue('cs')
  cs;

  String get wire => switch (this) {
        DeliveryMode.normal => 'normal',
        DeliveryMode.assisted => 'assisted',
        DeliveryMode.cs => 'cs',
      };
}

enum DeliveryOutcome {
  @JsonValue('live_birth')
  liveBirth,
  @JsonValue('stillbirth')
  stillbirth;

  String get wire =>
      this == DeliveryOutcome.stillbirth ? 'stillbirth' : 'live_birth';
}

enum ReminderKind {
  @JsonValue('anc_due')
  ancDue,
  @JsonValue('anc_missed')
  ancMissed,
  @JsonValue('follow_up')
  followUp,
  @JsonValue('medicine')
  medicine;

  String get wire => switch (this) {
        ReminderKind.ancDue => 'anc_due',
        ReminderKind.ancMissed => 'anc_missed',
        ReminderKind.followUp => 'follow_up',
        ReminderKind.medicine => 'medicine',
      };
}

enum ReminderChannel {
  @JsonValue('sms')
  sms,
  @JsonValue('push')
  push;

  String get wire => this == ReminderChannel.push ? 'push' : 'sms';
}

enum RecipientRole {
  @JsonValue('patient')
  patient,
  @JsonValue('family')
  family;

  String get wire => this == RecipientRole.family ? 'family' : 'patient';
}

enum ReminderStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('sent')
  sent,
  @JsonValue('failed')
  failed;

  String get wire => switch (this) {
        ReminderStatus.pending => 'pending',
        ReminderStatus.sent => 'sent',
        ReminderStatus.failed => 'failed',
      };
}

enum FacilityType {
  @JsonValue('health_post')
  healthPost,
  @JsonValue('phcc')
  phcc,
  @JsonValue('hospital')
  hospital,
  @JsonValue('birthing_centre')
  birthingCentre;

  String get wire => switch (this) {
        FacilityType.healthPost => 'health_post',
        FacilityType.phcc => 'phcc',
        FacilityType.hospital => 'hospital',
        FacilityType.birthingCentre => 'birthing_centre',
      };
}

enum AuditAction {
  @JsonValue('grant_created')
  grantCreated,
  @JsonValue('grant_redeemed')
  grantRedeemed,
  @JsonValue('record_viewed')
  recordViewed,
  @JsonValue('visit_added')
  visitAdded,
  @JsonValue('contact_recorded')
  contactRecorded,
  @JsonValue('document_added')
  documentAdded,
  @JsonValue('grant_revoked')
  grantRevoked;

  String get wire => switch (this) {
        AuditAction.grantCreated => 'grant_created',
        AuditAction.grantRedeemed => 'grant_redeemed',
        AuditAction.recordViewed => 'record_viewed',
        AuditAction.visitAdded => 'visit_added',
        AuditAction.contactRecorded => 'contact_recorded',
        AuditAction.documentAdded => 'document_added',
        AuditAction.grantRevoked => 'grant_revoked',
      };
}

enum CodeListKind {
  @JsonValue('complaint')
  complaint,
  @JsonValue('diagnosis')
  diagnosis,
  @JsonValue('drug')
  drug,
  @JsonValue('dangerSign')
  dangerSign,
  @JsonValue('riskFactor')
  riskFactor;

  String get wire => switch (this) {
        CodeListKind.complaint => 'complaint',
        CodeListKind.diagnosis => 'diagnosis',
        CodeListKind.drug => 'drug',
        CodeListKind.dangerSign => 'dangerSign',
        CodeListKind.riskFactor => 'riskFactor',
      };

  static CodeListKind fromWire(String value) => switch (value) {
        'diagnosis' => CodeListKind.diagnosis,
        'drug' => CodeListKind.drug,
        'dangerSign' => CodeListKind.dangerSign,
        'riskFactor' => CodeListKind.riskFactor,
        _ => CodeListKind.complaint,
      };
}

enum TimelineKind {
  @JsonValue('visit')
  visit,
  @JsonValue('document')
  document,
  @JsonValue('pregnancy_registered')
  pregnancyRegistered,
  @JsonValue('anc_contact')
  ancContact,
  @JsonValue('delivery')
  delivery,
  // Tier 3, additive. A server that never emits these is unaffected.
  @JsonValue('immunisation')
  immunisation,
  @JsonValue('growth')
  growth;

  String get wire => switch (this) {
        TimelineKind.visit => 'visit',
        TimelineKind.document => 'document',
        TimelineKind.pregnancyRegistered => 'pregnancy_registered',
        TimelineKind.ancContact => 'anc_contact',
        TimelineKind.delivery => 'delivery',
        TimelineKind.immunisation => 'immunisation',
        TimelineKind.growth => 'growth',
      };
}

/// Sync push result status (spec A.4 POST /sync/push).
enum SyncOpStatus {
  @JsonValue('applied')
  applied,
  @JsonValue('conflict')
  conflict,
  @JsonValue('rejected')
  rejected,
  @JsonValue('duplicate')
  duplicate;

  String get wire => switch (this) {
        SyncOpStatus.applied => 'applied',
        SyncOpStatus.conflict => 'conflict',
        SyncOpStatus.rejected => 'rejected',
        SyncOpStatus.duplicate => 'duplicate',
      };
}
