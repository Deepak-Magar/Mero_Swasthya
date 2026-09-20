import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart' as picker;
import 'package:nepali_utils/nepali_utils.dart';

import '../../../core/dates/bs_date.dart';
import '../../../core/l10n/gen/app_localizations.dart';

/// A date field that opens the Bikram Sambat picker and shows both calendars
/// (spec §13).
///
/// Rural users think in BS; the API speaks AD only. The conversion happens here
/// and nowhere else, so no screen has to remember which calendar it is holding.
class BsDateField extends ConsumerWidget {
  const BsDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.errorText,
    this.enabled = true,
  });

  final String label;

  /// Gregorian, as everything above this widget stores it.
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String? errorText;
  final bool enabled;

  Future<void> _pick(BuildContext context, bool nepali) async {
    final now = DateTime.now();
    final first = firstDate ?? DateTime(now.year - 100);
    final last = lastDate ?? DateTime(now.year + 2);
    final initial = value ?? (last.isBefore(now) ? last : now);

    // The picker reads its language from the global NepaliUtils singleton.
    NepaliUtils().language = nepali ? Language.nepali : Language.english;

    final picked = await picker.showNepaliDatePicker(
      context: context,
      initialDate: initial.toNepaliDateTime(),
      firstDate: first.toNepaliDateTime(),
      lastDate: last.toNepaliDateTime(),
    );

    if (picked != null) onChanged(picked.toDateTime());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final nepali = Localizations.localeOf(context).languageCode == 'ne';

    return InkWell(
      onTap: enabled ? () => _pick(context, nepali) : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          errorText: errorText,
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_outlined, size: 20)
              : IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 20),
                  tooltip: l10n.commonRemove,
                  onPressed: enabled ? () => onChanged(null) : null,
                ),
        ),
        child: Text(
          value == null
              ? l10n.commonNotSet
              : BsDate.formatBoth(value!, nepaliDigits: nepali),
          style: value == null
              ? TextStyle(color: Theme.of(context).hintColor)
              : null,
        ),
      ),
    );
  }
}
