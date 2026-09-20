import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether the device thinks it has a network.
///
/// Wrapped in an interface for two reasons: `connectivity_plus` needs a
/// platform channel, which a unit test does not have, and mock mode wants to be
/// permanently "online" without one either.
///
/// It reports *reachability of an interface*, not of the server. A phone on a
/// village Wi-Fi with no uplink still says online — which is fine, because the
/// sync engine treats a failed request as "stay queued and try again" rather
/// than as an error to show.
abstract interface class ConnectivityMonitor {
  Future<bool> isOnline();

  /// Fires on every transition. Spec §7 lists this as a sync trigger.
  Stream<bool> get onChanged;
}

class PluginConnectivityMonitor implements ConnectivityMonitor {
  PluginConnectivityMonitor([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async =>
      _isOnline(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get onChanged =>
      _connectivity.onConnectivityChanged.map(_isOnline).distinct();
}

/// For `MOCK_API=true` and for tests: there is nothing to be offline from.
class AlwaysOnline implements ConnectivityMonitor {
  const AlwaysOnline();

  @override
  Future<bool> isOnline() async => true;

  @override
  Stream<bool> get onChanged => const Stream<bool>.empty();
}
