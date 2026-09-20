import '../../../core/errors/app_error.dart';
import '../../../core/net/api_transport.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/models.dart';
import 'json.dart';

/// Spec A.4 "Access grants (QR)".
class GrantsApi {
  const GrantsApi(this._transport);

  /// The QR string is the token with this prefix (spec A.4 / §14).
  static const String qrPrefix = 'SWC1:';

  final ApiTransport _transport;

  /// S17 share sheet. Default TTL is the ten minutes the spec's demo uses.
  /// [sections] is Tier 3's fine-grained consent (additive, optional). Empty
  /// means the whole record — which is what every grant meant before it
  /// existed — and the field is then omitted from the body entirely, so a
  /// backend that has not implemented it never sees it.
  Future<GrantCreateResult> create({
    required String patientId,
    GrantScope scope = GrantScope.append,
    int ttlMinutes = 10,
    List<GrantSection> sections = const [],
  }) async {
    final data = await _transport.post(
      '/grants',
      body: {
        'patientId': patientId,
        'scope': scope.wire,
        'ttlMinutes': ttlMinutes,
        if (sections.isNotEmpty)
          'sections': sections.map((s) => s.wire).toList(),
      },
    );
    return GrantCreateResult.fromJson(data);
  }

  /// A.7's printed fallback card: a year-long read-only grant whose QR can be
  /// printed once and kept in the patient's own hands.
  static const int printedCardTtlMinutes = 525600;

  /// S20 after a scan. The response is the whole bundle, which the provider app
  /// caches so the visit can be recorded with no network afterwards.
  ///
  /// [pin] is the patient's four digits, required only for a long-lived
  /// printed-card grant (A.7). The server answers `403 FORBIDDEN` with
  /// `details.pin = "required"` when it wants one and `"invalid"` when the one
  /// it got was wrong, so the caller can tell a challenge from a refusal.
  Future<RedeemResult> redeem(String qrPayload, {String? pin}) async {
    final data = await _transport.post(
      '/grants/redeem',
      body: {
        'qrPayload': qrPayload,
        if (pin != null && pin.isNotEmpty) 'pin': pin,
      },
    );
    return RedeemResult.fromJson(data);
  }

  /// True when [error] is the server asking for the patient's PIN rather than
  /// refusing the grant outright.
  static bool isPinChallenge(Object error) =>
      error is AppError &&
      error.code == AppError.forbidden &&
      error.details?['pin'] == 'required';

  /// True when a PIN was supplied and the server did not accept it.
  static bool isPinRejected(Object error) =>
      error is AppError &&
      error.code == AppError.forbidden &&
      error.details?['pin'] == 'invalid';

  Future<AccessGrant> revoke(String grantId) async {
    final data = await _transport.post('/grants/$grantId/revoke');
    return data.objectOf('grant', AccessGrant.fromJson);
  }
}
