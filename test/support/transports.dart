import 'dart:async';

import 'package:mero_swasthya/core/errors/app_error.dart';
import 'package:mero_swasthya/core/net/api_transport.dart';
import 'package:mero_swasthya/data/sync/connectivity.dart';

/// Wraps another transport and starts failing on command, so "the request
/// failed, but nothing was lost" can actually be exercised.
class FlakyTransport implements ApiTransport {
  FlakyTransport(this._inner);

  final ApiTransport _inner;
  bool offline = false;

  Never _offline() => throw AppError.networkError('No connection');

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    String? bearer,
  }) =>
      offline ? _offline() : _inner.get(path, query: query, bearer: bearer);

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  }) =>
      offline ? _offline() : _inner.post(path, body: body, bearer: bearer);

  @override
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  }) =>
      offline ? _offline() : _inner.put(path, body: body, bearer: bearer);

  @override
  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  }) =>
      offline ? _offline() : _inner.patch(path, body: body, bearer: bearer);

  @override
  Future<void> uploadBytes(
    String url, {
    required List<int> bytes,
    required Map<String, String> headers,
    String method = 'PUT',
  }) =>
      offline
          ? _offline()
          : _inner.uploadBytes(url, bytes: bytes, headers: headers,
              method: method);
}

/// A transport that answers only `/sync/push` and `/sync/pull`, with the
/// answers under the test's control. Anything else is an error, so a test
/// cannot pass by accident on a path it never meant to exercise.
class FakeSyncTransport implements ApiTransport {
  bool offline = false;

  /// Every push body the engine sent, in order.
  final List<Map<String, dynamic>> pushRequests = [];

  /// Every pull query the engine sent, in order.
  final List<Map<String, dynamic>> pullRequests = [];

  String serverTime = '2026-09-18T05:10:00.000Z';

  /// Turns the changes the engine sent into the `results` array. The default
  /// applies everything at `baseVersion + 1`, which is what a healthy server
  /// does.
  List<Map<String, dynamic>> Function(List<Map<String, dynamic>> changes)
      onPush = defaultApplyAll;

  /// Consumed one per pull. When it runs out, the pull answers "nothing new".
  final List<Map<String, dynamic>> pullPages = [];

  /// When set, a push blocks on it. Lets a test hold a cycle open and observe
  /// what happens to work that arrives while it is running.
  Completer<void>? gate;

  static List<Map<String, dynamic>> defaultApplyAll(
    List<Map<String, dynamic>> changes,
  ) {
    return [
      for (final change in changes)
        {
          'opId': change['opId'],
          'status': 'applied',
          'row': applied(change),
        },
    ];
  }

  /// The row a server would echo back: the payload plus the fields it owns.
  static Map<String, dynamic> applied(
    Map<String, dynamic> change, {
    int? version,
  }) {
    return {
      ...(change['payload'] as Map).cast<String, dynamic>(),
      'id': change['rowId'],
      'version': version ?? (change['baseVersion'] as int) + 1,
      'updatedAt': '2026-09-18T05:10:00.000Z',
      'deleted': false,
    };
  }

  static Map<String, dynamic> page(
    List<Map<String, dynamic>> changes, {
    required String cursor,
    bool hasMore = false,
  }) =>
      {'changes': changes, 'cursor': cursor, 'hasMore': hasMore};

  static Map<String, dynamic> change(String table, Map<String, dynamic> row) =>
      {'table': table, 'row': row};

  Never _unhandled(String method, String path) => throw AppError(
        code: AppError.notFound,
        message: 'FakeSyncTransport was not expecting $method $path',
        httpStatus: 404,
      );

  Never _offline() => throw AppError.networkError('No connection');

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    String? bearer,
  }) async {
    if (offline) _offline();
    if (path != '/sync/pull') _unhandled('GET', path);

    pullRequests.add({...?query});
    if (pullPages.isEmpty) {
      return page(const [], cursor: serverTime);
    }
    return pullPages.removeAt(0);
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  }) async {
    if (offline) _offline();
    if (path != '/sync/push') _unhandled('POST', path);

    final request = {...?body};
    pushRequests.add(request);

    final gate = this.gate;
    if (gate != null) await gate.future;

    final changes = (request['changes'] as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();

    return {'results': onPush(changes), 'serverTime': serverTime};
  }

  @override
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  }) async =>
      _unhandled('PUT', path);

  @override
  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  }) async =>
      _unhandled('PATCH', path);

  @override
  Future<void> uploadBytes(
    String url, {
    required List<int> bytes,
    required Map<String, String> headers,
    String method = 'PUT',
  }) async {}
}

/// Connectivity the test drives by hand.
class FakeConnectivity implements ConnectivityMonitor {
  FakeConnectivity({bool online = true}) : _online = online;

  bool _online;
  final _controller = StreamController<bool>.broadcast();

  set online(bool value) {
    _online = value;
    _controller.add(value);
  }

  @override
  Future<bool> isOnline() async => _online;

  @override
  Stream<bool> get onChanged => _controller.stream;

  Future<void> dispose() => _controller.close();
}
