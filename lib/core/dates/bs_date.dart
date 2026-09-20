import 'package:nepali_utils/nepali_utils.dart';

/// Bikram Sambat helpers.
///
/// Spec §13: the server stores AD only; the app converts for display.
/// Dates are shown BS primary, AD secondary, e.g. "२०८३ असोज २ (2026-09-18)".
class BsDate {
  const BsDate._();

  static const List<String> _monthsNp = [
    'बैशाख', 'जेठ', 'असार', 'श्रावण', 'भदौ', 'असोज',
    'कार्तिक', 'मंसिर', 'पुष', 'माघ', 'फाल्गुन', 'चैत',
  ];

  static const List<String> _monthsEn = [
    'Baishakh', 'Jestha', 'Ashar', 'Shrawan', 'Bhadra', 'Ashoj',
    'Kartik', 'Mangsir', 'Poush', 'Magh', 'Falgun', 'Chaitra',
  ];

  /// AD -> BS.
  static NepaliDateTime toBs(DateTime ad) => ad.toNepaliDateTime();

  /// BS -> AD.
  static DateTime toAd(NepaliDateTime bs) => bs.toDateTime();

  /// "२०८३ असोज २" (Nepali locale) or "2083 Ashoj 2" (English locale).
  static String formatBs(DateTime ad, {bool nepaliDigits = true}) {
    final bs = toBs(ad);
    final month = nepaliDigits ? _monthsNp[bs.month - 1] : _monthsEn[bs.month - 1];
    final year = nepaliDigits ? _toNepaliDigits('${bs.year}') : '${bs.year}';
    final day = nepaliDigits ? _toNepaliDigits('${bs.day}') : '${bs.day}';
    return '$year $month $day';
  }

  /// ISO calendar date, the wire format for dob/lmp/edd/dueAt/followUpAt/takenAt.
  static String formatAd(DateTime ad) =>
      '${ad.year.toString().padLeft(4, '0')}-'
      '${ad.month.toString().padLeft(2, '0')}-'
      '${ad.day.toString().padLeft(2, '0')}';

  /// Combined display form: "२०८३ असोज २ (2026-09-18)".
  static String formatBoth(DateTime ad, {bool nepaliDigits = true}) =>
      '${formatBs(ad, nepaliDigits: nepaliDigits)} (${formatAd(ad)})';

  /// Parses a wire "YYYY-MM-DD" into a local midnight DateTime.
  static DateTime? parseAd(String? ymd) {
    if (ymd == null || ymd.isEmpty) return null;
    final parts = ymd.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  /// Strips the time component so date-only comparisons are safe.
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Whole years between [dob] and [asOf]; used for the age chip.
  static int ageInYears(DateTime dob, {DateTime? asOf}) {
    final now = asOf ?? DateTime.now();
    var age = now.year - dob.year;
    final hadBirthday =
        now.month > dob.month || (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthday) age--;
    return age;
  }

  static const List<String> _npDigits = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];

  /// Spec §13: Nepali numerals for display; Latin digits stay in vitals inputs.
  static String toNepaliDigits(String input) => _toNepaliDigits(input);

  static String _toNepaliDigits(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final digit = int.tryParse(ch);
      buffer.write(digit == null ? ch : _npDigits[digit]);
    }
    return buffer.toString();
  }
}

/// The Bikram Sambat month [now] falls in, as an AD half-open-ish range.
///
/// A health post reports by the Nepali month, not the Gregorian one, so
/// "deliveries this month" has to be bounded this way or the number is simply
/// about a different fortnight. `end` is the last instant of the month, so a
/// delivery recorded at 23:59 on the last day still counts.
({DateTime start, DateTime end}) currentBsMonth(DateTime now) {
  final bs = BsDate.toBs(now);
  final start = BsDate.toAd(NepaliDateTime(bs.year, bs.month));

  final nextMonth = bs.month == 12
      ? NepaliDateTime(bs.year + 1, 1)
      : NepaliDateTime(bs.year, bs.month + 1);

  return (
    start: start,
    end: BsDate.toAd(nextMonth).subtract(const Duration(milliseconds: 1)),
  );
}
