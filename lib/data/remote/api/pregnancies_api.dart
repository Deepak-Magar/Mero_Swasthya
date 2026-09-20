import '../../../core/net/api_transport.dart';
import '../../../domain/models/models.dart';

/// Spec A.4 "Maternal".
class PregnanciesApi {
  const PregnanciesApi(this._transport);

  final ApiTransport _transport;

  /// S11. The server computes `edd` from `lmp` when `edd` is null, derives
  /// `riskLevel`, and creates the eight contacts with the same deterministic
  /// ids the app generates (A.8.15).
  Future<PregnancyCreateResult> register(
    String patientId,
    Map<String, dynamic> payload,
  ) async {
    final data = await _transport.post(
      '/patients/$patientId/pregnancies',
      body: payload,
    );
    return PregnancyCreateResult.fromJson(data);
  }

  Future<PregnancyBundle> find(String id) async {
    final data = await _transport.get('/pregnancies/$id');
    return PregnancyBundle.fromJson(data);
  }

  /// Birth plan, risk factors, `status: ended`. `version` is required by the
  /// contract, so it is a named argument rather than something to forget in a
  /// payload map.
  Future<Pregnancy> update(
    String id, {
    required int version,
    required Map<String, dynamic> changes,
  }) async {
    final data = await _transport.patch(
      '/pregnancies/$id',
      body: {'version': version, ...changes},
    );
    return Pregnancy.fromJson(
      (data['pregnancy'] as Map).cast<String, dynamic>(),
    );
  }

  /// S12. The server recomputes triage from RULES and returns its own verdict;
  /// spec A.4 is explicit that the app must display the server's value if it
  /// differs from the one computed locally.
  Future<AncContactResult> recordContact(
    String pregnancyId,
    int contactNo,
    Map<String, dynamic> payload,
  ) async {
    final data = await _transport.put(
      '/pregnancies/$pregnancyId/contacts/$contactNo',
      body: payload,
    );
    return AncContactResult.fromJson(data);
  }

  /// S14. Closes the pregnancy and returns both updated rows.
  Future<DeliveryResult> recordDelivery(
    String pregnancyId,
    Map<String, dynamic> payload,
  ) async {
    final data = await _transport.post(
      '/pregnancies/$pregnancyId/delivery',
      body: payload,
    );
    return DeliveryResult.fromJson(data);
  }
}
