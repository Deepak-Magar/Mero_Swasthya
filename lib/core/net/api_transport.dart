/// What every endpoint class talks to.
///
/// The real implementation is `ApiClient` over Dio; `MockApi` implements the
/// same four methods against in-memory maps (spec §15). Because the seam sits
/// here rather than one level up, there is exactly one copy of each endpoint
/// method in the app, and mock mode cannot drift out of shape — it returns the
/// same JSON the interceptors would have unwrapped.
///
/// Every method returns the envelope's `data` object, already unwrapped, or
/// throws [AppError].
abstract interface class ApiTransport {
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    String? bearer,
  });

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  });

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  });

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  });

  /// The raw PUT of image bytes to the presigned storage URL (spec §7). It is
  /// not a `/api/v1` call: no envelope, no bearer, an absolute URL.
  Future<void> uploadBytes(
    String url, {
    required List<int> bytes,
    required Map<String, String> headers,
    String method = 'PUT',
  });
}
