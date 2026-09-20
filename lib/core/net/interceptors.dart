import 'dart:async';

import 'package:dio/dio.dart';

import '../errors/app_error.dart';
import 'token_store.dart';

/// Paths that must go out without an `Authorization` header (spec A.4).
const Set<String> unauthenticatedPaths = {
  '/auth/otp/request',
  '/auth/otp/verify',
  '/auth/pin/login',
  '/auth/refresh',
  '/codelists',
  '/rules',
  '/config',
  '/demo/sms',
};

/// Request-level override, set by `POST /auth/pin/set`, which authenticates
/// with the ten-minute tempToken rather than the stored access token.
const String bearerOverrideKey = 'bearerOverride';

/// Marks a request that has already been retried after a refresh, so one
/// expired token cannot start a loop.
const String _retriedKey = 'retriedAfterRefresh';

/// Interceptor 1 (spec §8): attaches the bearer token, and on a 401
/// `UNAUTHENTICATED` refreshes once and replays the request.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.tokens,
    required this.dio,
    required this.onSessionExpired,
  });

  final TokenStore tokens;
  final Dio dio;

  /// Called when the refresh itself fails — the router sends the user to S04.
  final void Function() onSessionExpired;

  /// Single-flight guard: several requests can fail at once when a token
  /// expires, and they must share one refresh rather than race.
  Future<bool>? _refreshing;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final override = options.extra[bearerOverrideKey] as String?;
    if (override != null) {
      options.headers['Authorization'] = 'Bearer $override';
      return handler.next(options);
    }

    if (!unauthenticatedPaths.contains(options.path)) {
      final token = await tokens.accessToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final isExpiredSession = err.response?.statusCode == 401 &&
        _envelopeCode(err.response?.data) == AppError.unauthenticated;
    final alreadyRetried = options.extra[_retriedKey] == true;
    final isRefreshCall = options.path == '/auth/refresh';

    if (!isExpiredSession || alreadyRetried || isRefreshCall) {
      return handler.next(err);
    }

    final refreshed = await _refreshOnce();
    if (!refreshed) {
      onSessionExpired();
      return handler.next(err);
    }

    try {
      final token = await tokens.accessToken();
      final replay = options
        ..extra[_retriedKey] = true
        ..headers['Authorization'] = 'Bearer $token';
      handler.resolve(await dio.fetch<dynamic>(replay));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<bool> _refreshOnce() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await tokens.refreshToken();
    if (refreshToken == null) return false;

    try {
      final response = await dio.post<dynamic>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      // The envelope interceptor has already unwrapped `data` by this point.
      final body = response.data;
      if (body is! Map) return false;

      await tokens.saveSession(
        accessToken: body['accessToken'] as String,
        refreshToken: body['refreshToken'] as String,
      );
      return true;
    } on DioException {
      await tokens.clear();
      return false;
    }
  }
}

/// Interceptor 2 (spec §8 / A.1): unwraps `{ok:true,data:…}` and turns
/// `{ok:false,error:…}` into an [AppError].
///
/// After this runs, nothing above the networking layer ever sees an envelope or
/// a [DioException] — only models or [AppError].
class EnvelopeInterceptor extends Interceptor {
  const EnvelopeInterceptor();

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final body = response.data;

    if (body is Map && body['ok'] == true) {
      response.data = body['data'];
      return handler.next(response);
    }

    if (body is Map && body['ok'] == false) {
      // A 200 carrying ok:false should still reach the caller as a failure.
      return handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: AppError.fromEnvelope(
            (body['error'] as Map?)?.cast<String, dynamic>() ?? const {},
            httpStatus: response.statusCode,
          ),
        ),
        true,
      );
    }

    // The upload PUT and any non-enveloped body pass through untouched.
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.error is AppError) return handler.next(err);

    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: _toAppError(err),
      ),
      true,
    );
  }

  AppError _toAppError(DioException err) {
    final body = err.response?.data;
    if (body is Map && body['error'] is Map) {
      return AppError.fromEnvelope(
        (body['error'] as Map).cast<String, dynamic>(),
        httpStatus: err.response?.statusCode,
      );
    }

    if (err.response == null) {
      // The request never landed, so a queued write is still safe where it is.
      return AppError.networkError(err.message);
    }

    return AppError(
      code: AppError.internal,
      message: err.message ?? 'Unexpected error',
      httpStatus: err.response?.statusCode,
    );
  }
}

/// Interceptor 3 (spec §8): retries a GET that never reached the server, twice,
/// after 1 s and 3 s.
///
/// Only GETs. Replaying a POST that may have been applied server-side is how
/// you end up with two visits for one consultation; writes have the outbox for
/// that, and it is idempotent by `opId`.
class RetryInterceptor extends Interceptor {
  RetryInterceptor(this.dio, {this.delays = const [
    Duration(seconds: 1),
    Duration(seconds: 3),
  ]});

  final Dio dio;
  final List<Duration> delays;

  static const String _attemptKey = 'retryAttempt';

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final attempt = (options.extra[_attemptKey] as int?) ?? 0;

    final isNetworkFailure = err.response == null;
    final isIdempotent = options.method.toUpperCase() == 'GET';

    if (!isNetworkFailure || !isIdempotent || attempt >= delays.length) {
      return handler.next(err);
    }

    await Future<void>.delayed(delays[attempt]);

    try {
      final replay = options..extra[_attemptKey] = attempt + 1;
      handler.resolve(await dio.fetch<dynamic>(replay));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

String? _envelopeCode(dynamic body) {
  if (body is Map && body['error'] is Map) {
    return (body['error'] as Map)['code'] as String?;
  }
  return null;
}
