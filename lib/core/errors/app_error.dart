/// The error half of the response envelope (spec A.1 / A.3).
///
///   { "ok": false, "error": { "code": "...", "message": "...", "details": {...} } }
class AppError implements Exception {
  const AppError({
    required this.code,
    required this.message,
    this.details,
    this.httpStatus,
  });

  final String code;
  final String message;
  final Map<String, dynamic>? details;
  final int? httpStatus;

  /// Codes from spec A.3.
  static const String validationError = 'VALIDATION_ERROR';
  static const String unauthenticated = 'UNAUTHENTICATED';
  static const String forbidden = 'FORBIDDEN';
  static const String grantExpired = 'GRANT_EXPIRED';
  static const String notFound = 'NOT_FOUND';
  static const String versionConflict = 'VERSION_CONFLICT';
  static const String alreadyRedeemed = 'ALREADY_REDEEMED';
  static const String ruleViolation = 'RULE_VIOLATION';
  static const String rateLimited = 'RATE_LIMITED';
  static const String internal = 'INTERNAL';

  /// Not from the server — raised by the client when the request never landed.
  static const String network = 'NETWORK';

  factory AppError.fromEnvelope(Map<String, dynamic> error, {int? httpStatus}) {
    return AppError(
      code: (error['code'] as String?) ?? internal,
      message: (error['message'] as String?) ?? 'Unexpected error',
      details: (error['details'] as Map?)?.cast<String, dynamic>(),
      httpStatus: httpStatus,
    );
  }

  factory AppError.networkError([String? message]) => AppError(
        code: network,
        message: message ?? 'No connection',
      );

  /// True when the request never reached the server, so a write can safely be
  /// left in the outbox and retried (spec §8 error mapping).
  bool get isNetwork => code == network;

  /// Per-field messages for VALIDATION_ERROR (`details = { field: message }`).
  Map<String, String> get fieldErrors {
    if (code != validationError || details == null) return const {};
    return details!.map((k, v) => MapEntry(k, '$v'));
  }

  @override
  String toString() => 'AppError($code, $message)';
}
