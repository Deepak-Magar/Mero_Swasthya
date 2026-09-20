import '../../../core/net/api_transport.dart';
import '../../../domain/models/models.dart';
import 'json.dart';

/// Spec A.4 "Patients", "Visits" and the two read-only lists hanging off a
/// patient (timeline, audit).
class PatientsApi {
  const PatientsApi(this._transport);

  final ApiTransport _transport;

  Future<List<Patient>> list() async {
    final data = await _transport.get('/patients');
    return data.itemsOf(Patient.fromJson);
  }

  /// Idempotent by id (spec A.4): sending the same client-generated id twice
  /// returns the existing row rather than creating a second one, which is what
  /// makes the outbox safe to replay.
  Future<Patient> create(Map<String, dynamic> payload) async {
    final data = await _transport.post('/patients', body: payload);
    return data.objectOf('patient', Patient.fromJson);
  }

  Future<Patient> update(String id, Map<String, dynamic> payload) async {
    final data = await _transport.patch('/patients/$id', body: payload);
    return data.objectOf('patient', Patient.fromJson);
  }

  /// S20 provider summary — the patient plus the computed summary block.
  Future<PatientDetail> detail(String id) async {
    final data = await _transport.get('/patients/$id');
    return PatientDetail.fromJson(data);
  }

  Future<TimelinePage> timeline(
    String id, {
    int limit = 50,
    String? before,
  }) async {
    final data = await _transport.get(
      '/patients/$id/timeline',
      query: {'limit': limit, 'before': ?before},
    );
    return TimelinePage.fromJson(data);
  }

  /// S16. Owner only — a provider asking for this gets 403.
  Future<List<AuditEntry>> audit(String id) async {
    final data = await _transport.get('/patients/$id/audit');
    return data.itemsOf(AuditEntry.fromJson);
  }

  Future<List<Visit>> visits(String id, {int limit = 50}) async {
    final data = await _transport.get(
      '/patients/$id/visits',
      query: {'limit': limit},
    );
    return data.itemsOf(Visit.fromJson);
  }

  Future<Visit> addVisit(String patientId, Map<String, dynamic> payload) async {
    final data =
        await _transport.post('/patients/$patientId/visits', body: payload);
    return data.objectOf('visit', Visit.fromJson);
  }

  Future<List<Reminder>> reminders(String id) async {
    final data = await _transport.get('/patients/$id/reminders');
    return data.itemsOf(Reminder.fromJson);
  }
}
