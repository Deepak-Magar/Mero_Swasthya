import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../errors/app_error.dart';
import 'api_transport.dart';
import 'interceptors.dart';
import 'token_store.dart';

/// The real transport (spec §8).
///
/// Everything above this class deals in models and [AppError]; `Dio` and its
/// exceptions stop here.
class ApiClient implements ApiTransport {
  ApiClient({
    required this.baseUrl,
    required TokenStore tokens,
    required void Function() onSessionExpired,
    Dio? dio,
    List<Duration>? retryDelays,
    this.verbose = kDebugMode,
  }) : dio = dio ?? Dio() {
    this.dio.options
      ..connectTimeout = const Duration(seconds: 8)
      ..receiveTimeout = const Duration(seconds: 15)
      ..headers['Content-Type'] = 'application/json';
    // `validateStatus` is deliberately left at its default. A non-2xx has to
    // arrive as a DioException so it enters the *error* chain at interceptor 1,
    // where AuthInterceptor can see the 401 and refresh. Accepting every status
    // instead would make the envelope interceptor reject from the response
    // chain, which resumes after it and skips the refresh entirely.

    this.dio.interceptors.addAll([
      // Spec §5: read the base URL per request so changing it in S23 (or
      // pointing at a new tunnel) takes effect without a rebuild.
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.baseUrl = baseUrl();
          handler.next(options);
        },
      ),
      AuthInterceptor(
        tokens: tokens,
        dio: this.dio,
        onSessionExpired: onSessionExpired,
      ),
      const EnvelopeInterceptor(),
      RetryInterceptor(
        this.dio,
        delays: retryDelays ??
            const [Duration(seconds: 1), Duration(seconds: 3)],
      ),
      if (verbose)
        LogInterceptor(requestBody: true, responseBody: true, logPrint: _log),
    ]);
  }

  final Dio dio;

  /// Read per request (spec §5), so changing the address in S23 or pointing at
  /// a new tunnel takes effect without a rebuild.
  final String Function() baseUrl;

  /// Interceptor 4 (spec §8). On in debug builds; tests turn it off so the
  /// request dump does not bury the failure they are reporting.
  final bool verbose;

  static void _log(Object? message) => debugPrint('[api] $message');

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    String? bearer,
  }) {
    return _send(
      () => dio.get<dynamic>(
        path,
        queryParameters: query,
        options: _options(bearer),
      ),
    );
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  }) {
    return _send(
      () => dio.post<dynamic>(path, data: body, options: _options(bearer)),
    );
  }

  @override
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  }) {
    return _send(
      () => dio.put<dynamic>(path, data: body, options: _options(bearer)),
    );
  }

  @override
  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  }) {
    return _send(
      () => dio.patch<dynamic>(path, data: body, options: _options(bearer)),
    );
  }

  @override
  Future<void> uploadBytes(
    String url, {
    required List<int> bytes,
    required Map<String, String> headers,
    String method = 'PUT',
  }) async {
    try {
      final response = await dio.requestUri<dynamic>(
        Uri.parse(url),
        data: Stream<List<int>>.fromIterable([bytes]),
        options: Options(
          method: method,
          headers: {...headers, Headers.contentLengthHeader: bytes.length},
        ),
      );

      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        throw AppError(
          code: AppError.internal,
          message: 'Upload failed with status $status',
          httpStatus: status,
        );
      }
    } on DioException catch (e) {
      throw _asAppError(e);
    }
  }

  Options _options(String? bearer) {
    return Options(
      extra: bearer == null ? null : {bearerOverrideKey: bearer},
    );
  }

  /// Runs a request and normalises the two things a caller must never see: a
  /// [DioException], and a `data` that is not an object.
  Future<Map<String, dynamic>> _send(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      final response = await request();
      final data = response.data;
      if (data is Map) return data.cast<String, dynamic>();

      throw AppError(
        code: AppError.internal,
        message: 'Expected a JSON object in the response envelope',
        httpStatus: response.statusCode,
      );
    } on DioException catch (e) {
      throw _asAppError(e);
    }
  }

  AppError _asAppError(DioException e) {
    final error = e.error;
    if (error is AppError) return error;
    if (e.response == null) return AppError.networkError(e.message);
    return AppError(
      code: AppError.internal,
      message: e.message ?? 'Unexpected error',
      httpStatus: e.response?.statusCode,
    );
  }
}
