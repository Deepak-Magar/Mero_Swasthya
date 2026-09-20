import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_error.dart';
import '../../core/net/token_store.dart';
import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../domain/models/models.dart';

/// Spec §9 `authProvider` — `AuthState{user, tokens, unlocked}`.
///
/// Two independent facts, and the router needs both (spec §10):
///
///  * **session** — there is a signed-in user with tokens on this device;
///  * **unlocked** — the PIN has been entered *this run*, which is what opens
///    the database.
///
/// A phone that has been used before but not yet unlocked has the first and not
/// the second, and lands on S04 rather than S02.
class AuthState {
  const AuthState({
    this.user,
    this.unlocked = false,
    this.hasPin = false,
    this.pendingPhone,
    this.tempToken,
  });

  final User? user;
  final bool unlocked;
  final bool hasPin;

  /// Carried between S02 and S03/S05 so the OTP screen knows whose code it is.
  final String? pendingPhone;

  /// The ten-minute token from `POST /auth/otp/verify`, used only by S05.
  final String? tempToken;

  bool get hasSession => user != null;

  /// Spec §10: providers and FCHVs land on S19, everyone else on S06.
  bool get isHealthWorker => user?.role.isHealthWorker ?? false;

  AuthState copyWith({
    User? user,
    bool? unlocked,
    bool? hasPin,
    String? pendingPhone,
    String? tempToken,
    bool clearUser = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      unlocked: unlocked ?? this.unlocked,
      hasPin: hasPin ?? this.hasPin,
      pendingPhone: pendingPhone ?? this.pendingPhone,
      tempToken: tempToken ?? this.tempToken,
    );
  }
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  AppDatabase get _db => ref.read(databaseProvider);
  TokenStore get _tokens => ref.read(tokenStoreProvider);

  /// S01: work out where to send the user.
  Future<void> restore() async {
    final user = await _db.syncMetaDao.currentUser();
    final hasPin = await _tokens.hasPin();
    state = state.copyWith(user: user, hasPin: hasPin, unlocked: false);
  }

  /// Spec S01: "Refresh accessToken silently if < 1 h remaining."
  ///
  /// Doing it at bootstrap rather than waiting for a 401 means the first real
  /// request of the day does not pay for a round trip — and a health worker who
  /// opens the app in signal and then walks out of it carries a token good for
  /// the next twelve hours.
  ///
  /// Best-effort: a failure here is not an error the user should see, because
  /// the app works offline and the interceptor will refresh on demand anyway.
  Future<void> refreshTokenIfExpiringSoon() async {
    final refreshToken = await _tokens.refreshToken();
    if (refreshToken == null) return;

    final expiry = jwtExpiry(await _tokens.accessToken());
    // An opaque or unreadable token tells us nothing; leave it to the 401 path
    // rather than refreshing on every launch.
    if (expiry != null &&
        expiry.difference(DateTime.now().toUtc()) > const Duration(hours: 1)) {
      return;
    }
    if (expiry == null) return;

    try {
      final refreshed =
          await ref.read(apiProvider).auth.refresh(refreshToken);
      await _tokens.saveSession(
        accessToken: refreshed.accessToken,
        refreshToken: refreshed.refreshToken,
      );
    } on AppError {
      // Offline, or the refresh token is spent. The interceptor handles the
      // latter the next time a request actually needs a session.
    }
  }

  // -------------------------------------------------------------------------
  // S02 / S03 — phone and OTP
  // -------------------------------------------------------------------------

  Future<OtpRequestResult> requestOtp(String phone) async {
    final normalised = normalisePhone(phone);
    final result = await ref.read(apiProvider).auth.requestOtp(normalised);
    state = state.copyWith(pendingPhone: normalised);
    return result;
  }

  /// Returns true when the account already has a PIN, so S03 knows whether to
  /// go to S04 or S05.
  Future<bool> verifyOtp(String otp) async {
    final phone = state.pendingPhone;
    if (phone == null) {
      throw const AppError(
        code: AppError.validationError,
        message: 'Enter your phone number first',
      );
    }

    final result =
        await ref.read(apiProvider).auth.verifyOtp(phone: phone, otp: otp);
    state = state.copyWith(tempToken: result.tempToken, hasPin: result.hasPin);
    return result.hasPin;
  }

  // -------------------------------------------------------------------------
  // S04 / S05 — PIN
  // -------------------------------------------------------------------------

  /// First-time account creation.
  Future<void> setPin({required String pin, required String name}) async {
    final tempToken = state.tempToken;
    if (tempToken == null) {
      throw const AppError(
        code: AppError.unauthenticated,
        message: 'Verify your phone number again',
      );
    }

    final session = await ref
        .read(apiProvider)
        .auth
        .setPin(tempToken: tempToken, pin: pin, name: name);

    await _adoptSession(session);
    await _tokens.savePinVerifier(pin);
    state = state.copyWith(unlocked: true, hasPin: true);
  }

  /// Daily unlock (spec S04).
  ///
  /// The local verifier is checked **first**, so a health worker in a village
  /// with no signal still gets into the record. The network is only used to
  /// establish a session this device does not already have.
  Future<bool> unlock(String pin) async {
    if (await _tokens.hasPin()) {
      if (!await _tokens.verifyPin(pin)) return false;

      state = state.copyWith(unlocked: true);
      unawaited(_refreshUserInBackground());
      return true;
    }

    // No local verifier — first unlock on this install.
    final phone = state.pendingPhone ?? state.user?.phone;
    if (phone == null) return false;

    try {
      final session =
          await ref.read(apiProvider).auth.loginWithPin(phone: phone, pin: pin);
      await _adoptSession(session);
      await _tokens.savePinVerifier(pin);
      state = state.copyWith(unlocked: true, hasPin: true);
      return true;
    } on AppError {
      return false;
    }
  }

  /// S18: become a provider or FCHV.
  Future<User> activateProvider(String inviteCode) async {
    final user =
        await ref.read(apiProvider).auth.activateProvider(inviteCode.trim());
    await _db.syncMetaDao.setCurrentUser(user);
    state = state.copyWith(user: user);
    return user;
  }

  /// S23 logout. Spec: "wipes DB after confirmation".
  Future<void> signOut() async {
    await _tokens.clear();
    await _db.clearAll();
    // Otherwise the next account to sign in on this phone inherits the health
    // worker role the mock was told to remember.
    await ref.read(appConfigProvider).clearMockActivatedRole();
    await ref.read(appConfigProvider).clearMockUserName();
    state = const AuthState();
  }

  Future<void> _adoptSession(AuthSession session) async {
    await _tokens.saveSession(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    await _db.syncMetaDao.setCurrentUser(session.user);
    state = state.copyWith(user: session.user);
  }

  /// Best-effort: an offline unlock must not wait on it, and a role changed on
  /// another device should still land eventually.
  Future<void> _refreshUserInBackground() async {
    try {
      final user = await ref.read(apiProvider).auth.me();
      await _db.syncMetaDao.setCurrentUser(user);
      state = state.copyWith(user: user);
    } on Object {
      // Offline, or the session has gone. The interceptor handles the latter.
    }
  }

  /// Reads `exp` out of a JWT without verifying it — the app is not the party
  /// that validates this token, it only needs to know when to renew it.
  ///
  /// Returns null for anything that is not a readable JWT, which includes the
  /// opaque tokens the mock hands out.
  static DateTime? jwtExpiry(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;

    try {
      // base64Url in a JWT is unpadded; Dart's decoder insists on padding.
      final payload = parts[1].padRight((parts[1].length + 3) ~/ 4 * 4, '=');
      final decoded = jsonDecode(utf8.decode(base64Url.decode(payload)));
      final exp = (decoded as Map)['exp'];
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
    } on Object {
      return null;
    }
  }

  /// Spec S02: "Normalise to E.164."
  ///
  /// Nepali numbers are entered as ten digits starting `98`/`97`; the country
  /// code is added if it is missing rather than demanded of the user.
  static String normalisePhone(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('977')) return '+$digits';
    return '+977$digits';
  }

  /// Ten digits after the country code.
  static bool isValidPhone(String input) =>
      RegExp(r'^\+977\d{10}$').hasMatch(normalisePhone(input));
}

final authProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
