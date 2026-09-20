/// Spec §12 / A.5 — expected date of delivery.
///
/// Naegele's rule as the spec states it: a flat 280 days from the last menstrual
/// period. Every date here is a *calendar* date at UTC midnight, never a local
/// timestamp: a phone in Kathmandu (UTC+5:45) doing `DateTime.now()` arithmetic
/// on a local midnight lands a day out roughly a quarter of the time, and an
/// EDD that moves by a day breaks the shared test cases in A.6.
library;

const Duration gestationLength = Duration(days: 280);

/// `edd = lmp + 280 days`.
DateTime eddFromLmp(DateTime lmp) => dateOnly(lmp).add(gestationLength);

/// `lmp = edd - 280 days`. Used for scheduling when only the EDD is known —
/// spec A.6 case 2.
DateTime lmpFromEdd(DateTime edd) => dateOnly(edd).subtract(gestationLength);

/// How pregnant she is today, in days, derived from the EDD so it works whether
/// or not an LMP was ever recorded.
///
/// Negative before the derived LMP, and it keeps counting past the EDD — a
/// post-dates pregnancy is exactly when the number matters most.
int gestationalAgeDays(DateTime edd, DateTime today) =>
    dateOnly(today).difference(lmpFromEdd(edd)).inDays;

/// Completed weeks, which is how an ANC card is written: "30 weeks 2 days".
int gestationalAgeWeeks(DateTime edd, DateTime today) =>
    gestationalAgeDays(edd, today) ~/ 7;

/// The day part of [gestationalAgeWeeks].
int gestationalAgeRemainderDays(DateTime edd, DateTime today) =>
    gestationalAgeDays(edd, today) % 7;

/// Strips the time and the zone, leaving a UTC calendar date.
DateTime dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

/// `YYYY-MM-DD`, the form every date field in Part A uses.
String toIsoDate(DateTime value) =>
    dateOnly(value).toIso8601String().substring(0, 10);

/// Parses a `YYYY-MM-DD` (or full ISO) string as a UTC calendar date.
DateTime? parseIsoDate(String? value) {
  if (value == null || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  return parsed == null ? null : dateOnly(parsed);
}
