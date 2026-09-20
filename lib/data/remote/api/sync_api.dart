import '../../../core/net/api_transport.dart';
import '../../../domain/models/models.dart';

/// Spec A.4 "Sync (offline-first)".
class SyncApi {
  const SyncApi(this._transport);

  final ApiTransport _transport;

  /// Each change is applied independently and the batch never fails as a whole,
  /// so the caller reads [SyncPushResponse.results] op by op.
  Future<SyncPushResponse> push({
    required String deviceId,
    required List<SyncChange> changes,
  }) async {
    final data = await _transport.post(
      '/sync/push',
      body: {
        'deviceId': deviceId,
        'changes': changes.map((c) => c.toJson()).toList(growable: false),
      },
    );
    return SyncPushResponse.fromJson(data);
  }

  Future<SyncPullResponse> pull({
    required String since,
    required String deviceId,
  }) async {
    final data = await _transport.get(
      '/sync/pull',
      query: {'since': since, 'deviceId': deviceId},
    );
    return SyncPullResponse.fromJson(data);
  }
}
