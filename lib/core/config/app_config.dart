import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Spec §5: dart-defines plus a runtime base-URL override persisted in shared
/// preferences, so the tunnel URL can change without a rebuild.
class AppConfig {
  AppConfig._(this._prefs);

  static const String _baseUrlKey = 'api_base_url';
  static const String _localeKey = 'locale';
  static const String _useMockKey = 'use_mock_server';
  static const String _mockRoleKey = 'mock_activated_role';
  static const String _mockNameKey = 'mock_user_name';

  /// Spec §5 default targets the emulator loopback.
  static const String defaultBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:3000/api/v1');

  /// Spec §15: the build-time default for the mock transport.
  ///
  /// This only decides where [useMockServer] *starts*. Once the user touches
  /// the switch in S23 their choice is persisted and wins, so a single release
  /// APK can be demoed against the mock and then pointed at the real backend
  /// without a rebuild — which is the point of spec Session 3 step 9.
  static const bool mockApiDefault =
      bool.fromEnvironment('MOCK_API', defaultValue: false);

  final SharedPreferences _prefs;

  static Future<AppConfig> load() async =>
      AppConfig._(await SharedPreferences.getInstance());

  /// Read fresh on every request (spec §5) so a change in S23 takes effect at once.
  String get baseUrl => _prefs.getString(_baseUrlKey) ?? defaultBaseUrl;

  Future<void> setBaseUrl(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove(_baseUrlKey);
    } else {
      await _prefs.setString(_baseUrlKey, trimmed);
    }
  }

  /// Whether the in-memory mock is serving the API right now (spec §15).
  ///
  /// Read on every transport lookup, not captured at startup: flipping it has
  /// to take effect immediately, the same way the base URL does.
  bool get useMockServer => _prefs.getBool(_useMockKey) ?? mockApiDefault;

  Future<void> setUseMockServer(bool value) =>
      _prefs.setBool(_useMockKey, value);

  /// The role S18 last activated against the mock (spec §15), or null.
  ///
  /// The mock keeps everything in memory, so a relaunch built a fresh one that
  /// had never heard of the activation — and `GET /me` then replaced the
  /// health-worker role the device had already stored with the seeded patient.
  /// A real backend remembers; this is how the mock does.
  String? get mockActivatedRole => _prefs.getString(_mockRoleKey);

  Future<void> setMockActivatedRole(String role) =>
      _prefs.setString(_mockRoleKey, role);

  Future<void> clearMockActivatedRole() => _prefs.remove(_mockRoleKey);

  /// The name S05 last set against the mock, for the same reason as
  /// [mockActivatedRole].
  ///
  /// Without it a relaunch served the seeded account's name back through
  /// `GET /me`, so the health worker's phone greeted him as the demo
  /// patient and the lock screen read the wrong person's name.
  String? get mockUserName => _prefs.getString(_mockNameKey);

  Future<void> setMockUserName(String name) =>
      _prefs.setString(_mockNameKey, name);

  Future<void> clearMockUserName() => _prefs.remove(_mockNameKey);

  // -------------------------------------------------------------------------
  // Tier 3 — the last consent choice, per patient
  // -------------------------------------------------------------------------
  //
  // A preference, not a record: it is this phone remembering which chips the
  // patient last ticked so they do not have to tick them again, and it carries
  // no clinical meaning. The grant itself is the authority, and it lives on the
  // server.

  List<String> shareSections(String patientId) =>
      _prefs.getStringList('share_sections:$patientId') ?? const [];

  Future<void> setShareSections(String patientId, List<String> sections) =>
      _prefs.setStringList('share_sections:$patientId', sections);

  /// null = follow the device locale (spec §13: device locale if ne/en, else ne).
  String? get localeCode => _prefs.getString(_localeKey);

  Future<void> setLocaleCode(String? code) async {
    if (code == null) {
      await _prefs.remove(_localeKey);
    } else {
      await _prefs.setString(_localeKey, code);
    }
  }
}

/// Overridden in main() once the preferences are loaded.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden in main()'),
);
