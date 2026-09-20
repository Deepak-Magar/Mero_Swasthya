import '../../../core/net/api_transport.dart';
import '../../../domain/models/models.dart';
import 'json.dart';

/// Spec A.4 "Documents (paper capture)" — the three-step upload handshake.
class DocumentsApi {
  const DocumentsApi(this._transport);

  final ApiTransport _transport;

  /// Step 1: register the metadata and get a place to put the bytes.
  Future<PresignResult> presign({
    required String id,
    required String patientId,
    required String type,
    required String title,
    required String takenAt,
    required String contentType,
    required int sizeBytes,
  }) async {
    final data = await _transport.post(
      '/documents/presign',
      body: {
        'id': id,
        'patientId': patientId,
        'type': type,
        'title': title,
        'takenAt': takenAt,
        'contentType': contentType,
        'sizeBytes': sizeBytes,
      },
    );
    return PresignResult.fromJson(data);
  }

  /// Step 2: the bytes themselves, straight to storage — no envelope, no token.
  Future<void> upload(
    PresignResult presigned, {
    required List<int> bytes,
  }) {
    return _transport.uploadBytes(
      presigned.uploadUrl,
      bytes: bytes,
      headers: presigned.uploadHeaders,
      method: presigned.uploadMethod,
    );
  }

  /// Step 3: tell the server the PUT landed.
  Future<Document> complete(String id) async {
    final data = await _transport.post('/documents/$id/complete');
    return data.objectOf('document', Document.fromJson);
  }

  /// Metadata plus a fresh one-hour download URL.
  Future<Document> find(String id) async {
    final data = await _transport.get('/documents/$id');
    return data.objectOf('document', Document.fromJson);
  }

  /// Tier 2. Hidden unless `GET /config` reports `aiSummaryEnabled`, and the
  /// backend may still answer 501.
  Future<Document> summarize(String id) async {
    final data = await _transport.post('/documents/$id/summarize');
    return data.objectOf('document', Document.fromJson);
  }
}
