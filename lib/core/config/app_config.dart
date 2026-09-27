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
  static const String _offlineShareKey = 'offline_share_mode';

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

  /// Which QR the share sheet draws: the server-issued grant (`SWC1`) or the
  /// self-contained offline snapshot (`SWC2`).
  ///
  /// Per device, not per patient — it is a property of where this phone is
  /// standing, not of whose record is open. Null means "never chosen", and the
  /// sheet then follows whether the mock is serving.
  bool? get offlineShareMode {
    if (!_prefs.containsKey(_offlineShareKey)) return null;
    return _prefs.getBool(_offlineShareKey);
  }

  Future<void> setOfflineShareMode({required bool value}) =>
      _prefs.setBool(_offlineShareKey, value);

  // -------------------------------------------------------------------------
  // First-run coach marks
  // -------------------------------------------------------------------------
  //
  // One boolean per tour, not a "seen the onboarding" flag: the patient tour
  // and the provider tour are shown at different times to the same person on a
  // dual-role phone, and a single flag would eat whichever came second.
  //
  // A preference rather than a table row, because it describes this handset
  // rather than the record — a reinstall should explain the app again.

  static const String _coachPrefix = 'coach_seen:';

  bool coachSeen(String tour) =>
      _prefs.getBool('$_coachPrefix$tour') ?? false;

  Future<void> setCoachSeen(String tour) =>
      _prefs.setBool('$_coachPrefix$tour', true);

  /// Used by the tests, and by nothing in the app: there is no "show me the
  /// tour again" button, because a first run only happens once.
  Future<void> clearCoachSeen(String tour) =>
      _prefs.remove('$_coachPrefix$tour');

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
