import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/errors/app_error.dart';
import 'package:mero_swasthya/core/net/api_client.dart';
import 'package:mero_swasthya/core/net/token_store.dart';

/// One canned answer for one request.
class FakeReply {
  FakeReply.json(this.body, {this.status = 200}) : throwsNetworkError = false;
  FakeReply.offline()
      : body = const {},
        status = 0,
        throwsNetworkError = true;

  final Map<String, dynamic> body;
  final int status;
  final bool throwsNetworkError;
}

/// Serves queued replies and records what was actually sent, so the tests can
/// assert on headers and ordering without a server.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this._replies);

  final List<FakeReply> _replies;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);

    if (_replies.isEmpty) {
      throw StateError('No reply queued for ${options.method} ${options.path}');
    }
    final reply = _replies.removeAt(0);

    if (reply.throwsNetworkError) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'No connection',
      );
    }

    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> ok(Map<String, dynamic> data) => {'ok': true, 'data': data};

Map<String, dynamic> fail(
  String code,
  String message, {
  Map<String, dynamic>? details,
}) =>
    {
      'ok': false,
      'error': {
        'code': code,
        'message': message,
        'details': ?details,
      },
    };

void main() {
  late InMemoryTokenStore tokens;
  late int expiredCount;

  setUp(() {
    tokens = InMemoryTokenStore();
    expiredCount = 0;
  });

  ({ApiClient client, FakeAdapter adapter}) build(
    List<FakeReply> replies, {
    String base = 'https://api.test/api/v1',
    String Function()? baseUrl,
  }) {
    final adapter = FakeAdapter(replies);
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ApiClient(
      baseUrl: baseUrl ?? () => base,
      tokens: tokens,
      onSessionExpired: () => expiredCount++,
      dio: dio,
      retryDelays: const [Duration.zero, Duration.zero],
      verbose: false,
    );
    return (client: client, adapter: adapter);
  }

  group('envelope', () {
    test('a success envelope is unwrapped to its data object', () async {
      final api = build([
        FakeReply.json(ok({'user': {'id': 'u1'}})),
      ]);

      expect(await api.client.get('/me'), {
        'user': {'id': 'u1'},
      });
    });

    test('an error envelope becomes an AppError with its code and details',
        () async {
      final api = build([
        FakeReply.json(
          fail(
            'VALIDATION_ERROR',
            'Phone is not valid',
            details: {'phone': 'Phone is not valid'},
          ),
          status: 400,
        ),
      ]);

      await expectLater(
        api.client.post('/auth/otp/request', body: {'phone': 'x'}),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', AppError.validationError)
              .having((e) => e.httpStatus, 'httpStatus', 400)
              .having(
                (e) => e.fieldErrors,
                'fieldErrors',
                {'phone': 'Phone is not valid'},
              ),
        ),
      );
    });

    test('a 200 carrying ok:false is still a failure', () async {
      final api = build([
        FakeReply.json(fail('RULE_VIOLATION', 'Patient is not female')),
      ]);

      await expectLater(
        api.client.post('/patients/p1/pregnancies'),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'RULE_VIOLATION')),
      );
    });

    test('a request that never landed is a network error, not INTERNAL',
        () async {
      // The distinction decides the message in spec §8: "You are offline —
      // saved locally" rather than a generic retry.
      final api = build([FakeReply.offline()]);

      await expectLater(
        api.client.post('/patients', body: const {}),
        throwsA(isA<AppError>().having((e) => e.isNetwork, 'isNetwork', true)),
      );
    });
  });

  group('auth', () {
    test('the access token is attached to an authenticated call', () async {
      await tokens.saveSession(accessToken: 'a1', refreshToken: 'r1');
      final api = build([FakeReply.json(ok(const {}))]);

      await api.client.get('/me');

      expect(api.adapter.requests.single.headers['Authorization'], 'Bearer a1');
    });

    test('public endpoints go out without an Authorization header', () async {
      await tokens.saveSession(accessToken: 'a1', refreshToken: 'r1');
      final api = build([FakeReply.json(ok(const {'smsMode': 'mock'}))]);

      await api.client.get('/config');

      expect(api.adapter.requests.single.headers, isNot(contains('Authorization')));
    });

    test('an explicit bearer overrides the stored token', () async {
      // POST /auth/pin/set authenticates with the ten-minute tempToken.
      await tokens.saveSession(accessToken: 'a1', refreshToken: 'r1');
      final api = build([FakeReply.json(ok(const {}))]);

      await api.client.post('/auth/pin/set', bearer: 'temp_token');

      expect(
        api.adapter.requests.single.headers['Authorization'],
        'Bearer temp_token',
      );
    });

    test('a 401 refreshes once and replays the request', () async {
      await tokens.saveSession(accessToken: 'stale', refreshToken: 'r1');
      final api = build([
        FakeReply.json(fail('UNAUTHENTICATED', 'Token expired'), status: 401),
        FakeReply.json(ok({'accessToken': 'fresh', 'refreshToken': 'r2'})),
        FakeReply.json(ok({'items': <dynamic>[]})),
      ]);

      final result = await api.client.get('/patients');

      expect(result, {'items': <dynamic>[]});
      expect(
        api.adapter.requests.map((r) => r.path),
        ['/patients', '/auth/refresh', '/patients'],
      );
      expect(
        api.adapter.requests.last.headers['Authorization'],
        'Bearer fresh',
        reason: 'the replay must carry the new token',
      );
      expect(await tokens.accessToken(), 'fresh');
      expect(expiredCount, 0);
    });

    test('a failed refresh ends the session and surfaces the original error',
        () async {
      await tokens.saveSession(accessToken: 'stale', refreshToken: 'r1');
      final api = build([
        FakeReply.json(fail('UNAUTHENTICATED', 'Token expired'), status: 401),
        FakeReply.json(fail('UNAUTHENTICATED', 'Refresh rejected'), status: 401),
      ]);

      await expectLater(
        api.client.get('/patients'),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', AppError.unauthenticated),
        ),
      );
      expect(expiredCount, 1);
      expect(await tokens.accessToken(), isNull, reason: 'tokens are cleared');
    });

    test('a second 401 after refreshing does not loop', () async {
      await tokens.saveSession(accessToken: 'stale', refreshToken: 'r1');
      final api = build([
        FakeReply.json(fail('UNAUTHENTICATED', 'Expired'), status: 401),
        FakeReply.json(ok({'accessToken': 'fresh', 'refreshToken': 'r2'})),
        FakeReply.json(fail('UNAUTHENTICATED', 'Still expired'), status: 401),
      ]);

      await expectLater(api.client.get('/patients'), throwsA(isA<AppError>()));

      expect(
        api.adapter.requests.map((r) => r.path),
        ['/patients', '/auth/refresh', '/patients'],
        reason: 'exactly one refresh and one replay',
      );
    });

    test('concurrent 401s share a single refresh', () async {
      await tokens.saveSession(accessToken: 'stale', refreshToken: 'r1');
      final api = build([
        FakeReply.json(fail('UNAUTHENTICATED', 'Expired'), status: 401),
        FakeReply.json(fail('UNAUTHENTICATED', 'Expired'), status: 401),
        FakeReply.json(ok({'accessToken': 'fresh', 'refreshToken': 'r2'})),
        FakeReply.json(ok(const {})),
        FakeReply.json(ok(const {})),
      ]);

      await Future.wait([
        api.client.get('/patients'),
        api.client.get('/me'),
      ]);

      expect(
        api.adapter.requests.where((r) => r.path == '/auth/refresh'),
        hasLength(1),
      );
    });

    test('a 403 is not treated as an expired session', () async {
      await tokens.saveSession(accessToken: 'a1', refreshToken: 'r1');
      final api = build([
        FakeReply.json(fail('FORBIDDEN', 'No active grant'), status: 403),
      ]);

      await expectLater(
        api.client.get('/patients/p1'),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
      expect(api.adapter.requests, hasLength(1));
      expect(expiredCount, 0);
    });
  });

  group('retry', () {
    test('a GET that never landed is retried twice, then gives up', () async {
      final api = build([
        FakeReply.offline(),
        FakeReply.offline(),
        FakeReply.offline(),
      ]);

      await expectLater(
        api.client.get('/patients'),
        throwsA(isA<AppError>().having((e) => e.isNetwork, 'isNetwork', true)),
      );
      expect(api.adapter.requests, hasLength(3));
    });

    test('a GET that succeeds on the second attempt returns normally',
        () async {
      final api = build([
        FakeReply.offline(),
        FakeReply.json(ok({'items': <dynamic>[]})),
      ]);

      expect(await api.client.get('/patients'), {'items': <dynamic>[]});
      expect(api.adapter.requests, hasLength(2));
    });

    test('a POST is never retried', () async {
      // Replaying a write that may already have been applied is how one
      // consultation becomes two visits; the outbox handles writes instead.
      final api = build([FakeReply.offline()]);

      await expectLater(
        api.client.post('/patients/p1/visits', body: const {}),
        throwsA(isA<AppError>()),
      );
      expect(api.adapter.requests, hasLength(1));
    });

    test('a GET that reached the server and failed is not retried', () async {
      final api = build([
        FakeReply.json(fail('NOT_FOUND', 'No such patient'), status: 404),
      ]);

      await expectLater(
        api.client.get('/patients/nope'),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'NOT_FOUND')),
      );
      expect(api.adapter.requests, hasLength(1));
    });
  });

  group('base url', () {
    test('it is read fresh on every request', () async {
      // Spec §5: S23 can repoint the app at a new tunnel without a rebuild.
      var base = 'https://first.test/api/v1';
      final api = build(
        [FakeReply.json(ok(const {})), FakeReply.json(ok(const {}))],
        baseUrl: () => base,
      );

      await api.client.get('/config');
      base = 'https://second.test/api/v1';
      await api.client.get('/config');

      expect(
        api.adapter.requests.map((r) => r.uri.host),
        ['first.test', 'second.test'],
      );
    });
  });
}
