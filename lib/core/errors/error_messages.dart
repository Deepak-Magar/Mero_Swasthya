import '../l10n/gen/app_localizations.dart';
import 'app_error.dart';

/// Spec §8: AppError.code -> localized message table.
///
/// [isWrite] distinguishes the two network messages the spec calls for:
/// "You are offline — saved locally" for writes, "No connection" for reads.
String localizedError(L l10n, Object error, {bool isWrite = false}) {
  if (error is! AppError) return l10n.commonSomethingWentWrong;
  return switch (error.code) {
    AppError.validationError => l10n.errorValidation,
    AppError.unauthenticated => l10n.errorUnauthenticated,
    AppError.forbidden => l10n.errorForbidden,
    AppError.grantExpired => l10n.errorGrantExpired,
    AppError.notFound => l10n.errorNotFound,
    AppError.versionConflict => l10n.errorVersionConflict,
    AppError.alreadyRedeemed => l10n.errorAlreadyRedeemed,
    AppError.ruleViolation => l10n.errorRuleViolation,
    AppError.rateLimited => l10n.errorRateLimited,
    AppError.internal => l10n.errorInternal,
    AppError.network => isWrite ? l10n.errorNetworkWrite : l10n.errorNetworkRead,
    _ => l10n.commonSomethingWentWrong,
  };
}
