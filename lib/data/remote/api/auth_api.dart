import '../../../core/net/api_transport.dart';
import '../../../domain/models/models.dart';

/// Spec A.4 "Auth".
class AuthApi {
  const AuthApi(this._transport);

  final ApiTransport _transport;

  Future<OtpRequestResult> requestOtp(String phone) async {
    final data = await _transport.post(
      '/auth/otp/request',
      body: {'phone': phone},
    );
    return OtpRequestResult.fromJson(data);
  }

  Future<OtpVerifyResult> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    final data = await _transport.post(
      '/auth/otp/verify',
      body: {'phone': phone, 'otp': otp},
    );
    return OtpVerifyResult.fromJson(data);
  }

  /// Creates the account if new. Authenticates with the ten-minute `tempToken`
  /// from [verifyOtp], not with the stored access token.
  Future<AuthSession> setPin({
    required String tempToken,
    required String pin,
    required String name,
  }) async {
    final data = await _transport.post(
      '/auth/pin/set',
      body: {'pin': pin, 'name': name},
      bearer: tempToken,
    );
    return AuthSession.fromJson(data);
  }

  Future<AuthSession> loginWithPin({
    required String phone,
    required String pin,
  }) async {
    final data = await _transport.post(
      '/auth/pin/login',
      body: {'phone': phone, 'pin': pin},
    );
    return AuthSession.fromJson(data);
  }

  /// Normally driven by the auth interceptor; exposed for the bootstrap path.
  Future<RefreshResult> refresh(String refreshToken) async {
    final data = await _transport.post(
      '/auth/refresh',
      body: {'refreshToken': refreshToken},
    );
    return RefreshResult.fromJson(data);
  }

  /// S18: upgrade to provider/fchv with an invite code.
  Future<User> activateProvider(String inviteCode) async {
    final data = await _transport.post(
      '/auth/provider/activate',
      body: {'inviteCode': inviteCode},
    );
    return User.fromJson((data['user'] as Map).cast<String, dynamic>());
  }

  Future<User> me() async {
    final data = await _transport.get('/me');
    return User.fromJson((data['user'] as Map).cast<String, dynamic>());
  }
}
