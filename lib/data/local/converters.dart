import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';

/// Drift type converters for the columns that spec §6 stores as TEXT.
///
/// Two shapes appear in the table list:
///
///  * enum columns — stored as the *wire* string from Part A.2, never the Dart
///    name, so a row read straight out of sqlite can be handed to the sync
///    payload builder without a translation table;
///  * "(JSON)" columns — nested objects and arrays serialised with the same
///    `toJson`/`fromJson` the network layer uses, so local and remote rows are
///    byte-identical.

/// `outbox.op` (spec §6). Device-only, so it does not live in the domain enums.
enum OutboxOp {
  upsert,
  delete;

  String get wire => this == OutboxOp.delete ? 'delete' : 'upsert';
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Maps an enum to its Part A wire string.
///
/// [_wireOf] is a top-level tear-off (a constant expression) so every converter
/// below can be `const`, which drift requires at the `map()` call site.
class EnumTextConverter<T extends Enum> extends TypeConverter<T, String> {
  const EnumTextConverter(this._values, this._wireOf, this._fallback);

  final List<T> _values;
  final String Function(T) _wireOf;

  /// Used when the server sends a value this build does not know yet. Showing
  /// the row under a known label beats dropping it.
  final T _fallback;

  @override
  String toSql(T value) => _wireOf(value);

  @override
  T fromSql(String fromDb) {
    for (final value in _values) {
      if (_wireOf(value) == fromDb) return value;
    }
    return _fallback;
  }
}

String _userRoleWire(UserRole v) => v.wire;
String _sexWire(Sex v) => v.wire;
String _documentTypeWire(DocumentType v) => v.wire;
String _documentStatusWire(DocumentStatus v) => v.wire;
String _aiSummaryStatusWire(AiSummaryStatus v) => v.wire;
String _riskLevelWire(RiskLevel v) => v.wire;
String _pregnancyStatusWire(PregnancyStatus v) => v.wire;
String _triageLevelWire(TriageLevel v) => v.wire;
String _deliveryPlaceWire(DeliveryPlace v) => v.wire;
String _deliveryModeWire(DeliveryMode v) => v.wire;
String _deliveryOutcomeWire(DeliveryOutcome v) => v.wire;
String _reminderKindWire(ReminderKind v) => v.wire;
String _reminderChannelWire(ReminderChannel v) => v.wire;
String _recipientRoleWire(RecipientRole v) => v.wire;
String _reminderStatusWire(ReminderStatus v) => v.wire;
String _facilityTypeWire(FacilityType v) => v.wire;
String _auditActionWire(AuditAction v) => v.wire;
String _codeListKindWire(CodeListKind v) => v.wire;
String _outboxOpWire(OutboxOp v) => v.wire;

const userRoleConverter =
    EnumTextConverter(UserRole.values, _userRoleWire, UserRole.patient);
const sexConverter = EnumTextConverter(Sex.values, _sexWire, Sex.female);
const documentTypeConverter = EnumTextConverter(
    DocumentType.values, _documentTypeWire, DocumentType.other);
const documentStatusConverter = EnumTextConverter(
    DocumentStatus.values, _documentStatusWire, DocumentStatus.pendingUpload);
const aiSummaryStatusConverter = EnumTextConverter(
    AiSummaryStatus.values, _aiSummaryStatusWire, AiSummaryStatus.none);
const riskLevelConverter =
    EnumTextConverter(RiskLevel.values, _riskLevelWire, RiskLevel.normal);
const pregnancyStatusConverter = EnumTextConverter(
    PregnancyStatus.values, _pregnancyStatusWire, PregnancyStatus.active);
const deliveryPlaceConverter = EnumTextConverter(
    DeliveryPlace.values, _deliveryPlaceWire, DeliveryPlace.home);
const deliveryModeConverter = EnumTextConverter(
    DeliveryMode.values, _deliveryModeWire, DeliveryMode.normal);
const deliveryOutcomeConverter = EnumTextConverter(
    DeliveryOutcome.values, _deliveryOutcomeWire, DeliveryOutcome.liveBirth);
const reminderKindConverter =
    EnumTextConverter(ReminderKind.values, _reminderKindWire, ReminderKind.ancDue);
const reminderChannelConverter = EnumTextConverter(
    ReminderChannel.values, _reminderChannelWire, ReminderChannel.sms);
const recipientRoleConverter = EnumTextConverter(
    RecipientRole.values, _recipientRoleWire, RecipientRole.patient);
const reminderStatusConverter = EnumTextConverter(
    ReminderStatus.values, _reminderStatusWire, ReminderStatus.pending);
const facilityTypeConverter = EnumTextConverter(
    FacilityType.values, _facilityTypeWire, FacilityType.healthPost);
const auditActionConverter =
    EnumTextConverter(AuditAction.values, _auditActionWire, AuditAction.recordViewed);
const codeListKindConverter = EnumTextConverter(
    CodeListKind.values, _codeListKindWire, CodeListKind.complaint);
const outboxOpConverter =
    EnumTextConverter(OutboxOp.values, _outboxOpWire, OutboxOp.upsert);

/// `anc_contacts.triage_level` and `deliveries.baby_sex` are nullable.
const nullableTriageLevelConverter = NullAwareTypeConverter.wrap(
  EnumTextConverter(TriageLevel.values, _triageLevelWire, TriageLevel.green),
);
const nullableSexConverter = NullAwareTypeConverter.wrap(
  EnumTextConverter(Sex.values, _sexWire, Sex.female),
);

// ---------------------------------------------------------------------------
// JSON columns
// ---------------------------------------------------------------------------

/// `allergies`, `chronic_conditions`, `diagnosis_codes`, `risk_factors`,
/// `danger_signs`, `triage_reasons`, `complications`.
class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  String toSql(List<String> value) => jsonEncode(value);

  @override
  List<String> fromSql(String fromDb) {
    final decoded = jsonDecode(fromDb);
    if (decoded is! List) return const <String>[];
    return decoded.map((e) => '$e').toList(growable: false);
  }
}

/// `outbox.payload` — always an object.
class JsonMapConverter extends TypeConverter<Map<String, dynamic>, String> {
  const JsonMapConverter();

  @override
  String toSql(Map<String, dynamic> value) => jsonEncode(value);

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    final decoded = jsonDecode(fromDb);
    if (decoded is! Map) return <String, dynamic>{};
    return decoded.cast<String, dynamic>();
  }
}

/// A nested freezed object stored as JSON text; `null` stays `null`.
class JsonObjectConverter<T> extends NullAwareTypeConverter<T, String> {
  const JsonObjectConverter(this._fromJson, this._toJson);

  final T Function(Map<String, dynamic>) _fromJson;
  final Map<String, dynamic> Function(T) _toJson;

  @override
  String requireToSql(T value) => jsonEncode(_toJson(value));

  @override
  T requireFromSql(String fromDb) =>
      _fromJson((jsonDecode(fromDb) as Map).cast<String, dynamic>());
}

Map<String, dynamic> _vitalsToJson(Vitals v) => v.toJson();
Map<String, dynamic> _referralToJson(Referral v) => v.toJson();
Map<String, dynamic> _findingsToJson(Findings v) => v.toJson();
Map<String, dynamic> _birthPlanToJson(BirthPlan v) => v.toJson();

const vitalsConverter = JsonObjectConverter(Vitals.fromJson, _vitalsToJson);
const referralConverter =
    JsonObjectConverter(Referral.fromJson, _referralToJson);
const findingsConverter =
    JsonObjectConverter(Findings.fromJson, _findingsToJson);
const birthPlanConverter =
    JsonObjectConverter(BirthPlan.fromJson, _birthPlanToJson);

/// `codelist_items.meta` — free-form object, kept as a map.
class NullableJsonMapConverter
    extends NullAwareTypeConverter<Map<String, dynamic>, String> {
  const NullableJsonMapConverter();

  @override
  String requireToSql(Map<String, dynamic> value) => jsonEncode(value);

  @override
  Map<String, dynamic> requireFromSql(String fromDb) =>
      (jsonDecode(fromDb) as Map).cast<String, dynamic>();
}

/// `visits.prescriptions` — spec §6 keeps prescriptions embedded, so there is
/// no separate table and no join on the device.
class PrescriptionListConverter
    extends TypeConverter<List<Prescription>, String> {
  const PrescriptionListConverter();

  @override
  String toSql(List<Prescription> value) =>
      jsonEncode(value.map((e) => e.toJson()).toList(growable: false));

  @override
  List<Prescription> fromSql(String fromDb) {
    final decoded = jsonDecode(fromDb);
    if (decoded is! List) return const <Prescription>[];
    return decoded
        .map((e) => Prescription.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }
}
