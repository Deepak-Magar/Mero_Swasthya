import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/config/app_config.dart';
import 'package:mero_swasthya/core/net/api_client.dart';
import 'package:mero_swasthya/core/net/mock_api.dart';
import 'package:mero_swasthya/core/providers.dart';
import 'package:mero_swasthya/data/sync/connectivity.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Spec Session 3 step 9: one APK, switchable at runtime.
///
/// The demo runs on the mock; when the backend comes up the switch goes off and
/// the *same build* talks to it. So the thing under test is the routing
/// decision — which transport comes out of the container for a given flag, and
/// that flipping the flag actually replaces it rather than leaving a stale
/// client behind.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> containerWith({bool? persisted}) async {
    SharedPreferences.setMockInitialValues({
      'use_mock_server': ?persisted,
      'api_base_url': 'https://real.test/api/v1',
    });

    final container = ProviderContainer(
      overrides: [appConfigProvider.overrideWithValue(await AppConfig.load())],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('the routing decision', () {
    test('a stored true routes to the mock', () async {
      final container = await containerWith(persisted: true);

      expect(container.read(apiTransportProvider), isA<MockApi>());
    });

    test('a stored false routes to the real Dio client', () async {
      final container = await containerWith(persisted: false);

      expect(container.read(apiTransportProvider), isA<ApiClient>());
    });

    test('with nothing stored it follows the build-time default', () async {
      // `MOCK_API` is not defined when the tests run, so the default is false.
      final container = await containerWith();

      expect(AppConfig.mockApiDefault, isFalse);
      expect(container.read(useMockServerProvider), isFalse);
      expect(container.read(apiTransportProvider), isA<ApiClient>());
    });
  });

  group('flipping the switch', () {
    test('replaces the transport rather than reusing it', () async {
      final container = await containerWith(persisted: true);
      final before = container.read(apiTransportProvider);
      expect(before, isA<MockApi>());

      container.read(useMockServerProvider.notifier).state = false;

      final after = container.read(apiTransportProvider);
      expect(after, isA<ApiClient>());
      expect(identical(before, after), isFalse);
    });

    test('and back again restores the mock', () async {
      final container = await containerWith(persisted: false);
      expect(container.read(apiTransportProvider), isA<ApiClient>());

      container.read(useMockServerProvider.notifier).state = true;

      expect(container.read(apiTransportProvider), isA<MockApi>());
    });

    test('the real client points at the saved address', () async {
      final container = await containerWith(persisted: false);

      final client = container.read(apiTransportProvider) as ApiClient;
      expect(client.baseUrl(), 'https://real.test/api/v1');
    });

    test('a base-URL change is picked up without rebuilding the client',
        () async {
      // Spec §5: read per request, so S23 can repoint at a new tunnel.
      final container = await containerWith(persisted: false);
      final client = container.read(apiTransportProvider) as ApiClient;

      await container.read(appConfigProvider).setBaseUrl('https://other.test');

      expect(client.baseUrl(), 'https://other.test');
    });
  });

  group('what else follows the switch', () {
    test('connectivity is the device own answer on both transports', () async {
      // It used to be `AlwaysOnline` on the mock, which made spec §17 item 3
      // — airplane mode, pending icon, network back, synced — impossible to
      // show on a demo build, since the demo runs on the mock.
      final container = await containerWith(persisted: true);
      expect(
        container.read(connectivityProvider),
        isA<PluginConnectivityMonitor>(),
      );

      container.read(useMockServerProvider.notifier).state = false;
      expect(
        container.read(connectivityProvider),
        isA<PluginConnectivityMonitor>(),
      );
    });

    test('the api wrapper follows the transport', () async {
      final container = await containerWith(persisted: true);
      final before = container.read(apiProvider);

      container.read(useMockServerProvider.notifier).state = false;

      expect(identical(before, container.read(apiProvider)), isFalse);
    });
  });

  group('persistence', () {
    test('the choice survives a restart', () async {
      final container = await containerWith(persisted: true);
      await container.read(appConfigProvider).setUseMockServer(false);

      // A fresh container over the same preferences stands in for a relaunch.
      final restarted = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(await AppConfig.load()),
        ],
      );
      addTearDown(restarted.dispose);

      expect(restarted.read(useMockServerProvider), isFalse);
      expect(restarted.read(apiTransportProvider), isA<ApiClient>());
    });

    test('the stored flag beats the build-time default', () async {
      final container = await containerWith(persisted: true);

      expect(AppConfig.mockApiDefault, isFalse);
      expect(
        container.read(useMockServerProvider),
        isTrue,
        reason: 'what the user chose in S23 wins over how it was built',
      );
    });
  });
}
