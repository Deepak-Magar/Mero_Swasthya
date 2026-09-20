import '../../../core/net/api_transport.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/models.dart';
import 'json.dart';

/// Spec A.4 "Reminders, facilities, code lists, config" — everything the app
/// caches rather than owns.
class ReferenceApi {
  const ReferenceApi(this._transport);

  final ApiTransport _transport;

  /// Feature flags. Also carries `rulesVersion` / `codelistVersion`, which is
  /// how the sync engine decides whether the cached copies are stale (spec §5).
  Future<AppConfigFlags> config() async {
    final data = await _transport.get('/config');
    return AppConfigFlags.fromJson(data);
  }

  /// The shared rule table. `data` *is* the RULES object, with no wrapper key,
  /// so it is returned raw for the rules loader to parse.
  Future<Map<String, dynamic>> rules() => _transport.get('/rules');

  Future<CodeListResponse> codelists({CodeListKind? kind}) async {
    final data = await _transport.get(
      '/codelists',
      query: kind == null ? null : {'kind': kind.wire},
    );
    return CodeListResponse.fromJson(data);
  }

  Future<List<Facility>> nearbyFacilities({
    required double lat,
    required double lng,
    bool birthingOnly = false,
    int limit = 5,
  }) async {
    final data = await _transport.get(
      '/facilities/nearby',
      query: {
        'lat': lat,
        'lng': lng,
        if (birthingOnly) 'birthing': true,
        'limit': limit,
      },
    );
    return data.itemsOf(Facility.fromJson);
  }

  /// The projector panel (spec §15). Unauthenticated, and only present while
  /// the backend runs with `SMS_MODE=mock`.
  Future<List<DemoSms>> demoSms() async {
    final data = await _transport.get('/demo/sms');
    return data.itemsOf(DemoSms.fromJson);
  }
}
