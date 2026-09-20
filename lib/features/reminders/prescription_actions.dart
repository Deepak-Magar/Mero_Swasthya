import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/medicine_schedule.dart';
import 'medicine_speech.dart';

/// Tier 2 — the two things somebody can do with a prescription that is already
/// written down: be reminded of it, and be told it out loud.
///
/// Both live here rather than in S21 so the provider screen stays a summary,
/// and so the pair can be dropped next to a prescription list anywhere else
/// they are wanted.
class PrescriptionActions extends ConsumerStatefulWidget {
  const PrescriptionActions({
    super.key,
    required this.patientId,
    required this.prescriptions,
  });

  final String patientId;
  final List<Prescription> prescriptions;

  @override
  ConsumerState<PrescriptionActions> createState() =>
      _PrescriptionActionsState();
}

class _PrescriptionActionsState extends ConsumerState<PrescriptionActions> {
  bool _busy = false;

  /// The result is shown inline rather than in a snackbar.
  ///
  /// Found on the phone: this widget also lives inside the visit sheet on the
  /// timeline, and a `SnackBar` from inside a modal bottom sheet is painted by
  /// the page's `Scaffold` — underneath the sheet, where nobody ever sees it.
  /// Inline also means "14 reminders set" is still on screen a minute later,
  /// which is when somebody thinks to check.
  String? _status;

  /// True once every prescription here is "when needed", in which case there is
  /// nothing to schedule and saying so beats an empty success message.
  bool get _nothingToSchedule => widget.prescriptions.every(
        (p) => (doseHours[p.frequency] ?? const []).isEmpty,
      );

  Future<void> _setReminders() async {
    final l10n = L.of(context);

    if (_nothingToSchedule) {
      setState(() => _status = l10n.medicineRemindersNone);
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });
    final notifications = ref.read(medicineNotificationsProvider);

    // Android 13+ shows nothing at all until this is granted, and the failure
    // is silent — so ask, and say plainly what a refusal costs.
    final granted = await notifications.requestPermission();
    if (!mounted) return;

    if (!granted) {
      setState(() {
        _busy = false;
        _status = l10n.medicineRemindersRefused;
      });
      return;
    }

    final count = await notifications.scheduleForVisit(
      patientId: widget.patientId,
      prescriptions: widget.prescriptions,
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = l10n.medicineRemindersSet(count);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    final status = _status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: _busy ? null : _setReminders,
            icon: const Icon(Icons.alarm_add_outlined, size: 18),
            label: Text(l10n.medicineSetReminders),
          ),
        ),
        if (status != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.alarm_on_outlined, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The "Speak" button on a single prescription row.
class SpeakPrescriptionButton extends ConsumerWidget {
  const SpeakPrescriptionButton({super.key, required this.prescription});

  final Prescription prescription;

  Future<void> _speak(BuildContext context, WidgetRef ref) async {
    final l10n = L.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final result = await ref.read(medicineSpeechProvider).speak(
          drugName: prescription.drugName.isEmpty
              ? prescription.drugCode
              : prescription.drugName,
          instructionsNp: prescription.instructionsNp,
        );

    // Only a swap or a failure is worth a line; a successful Nepali reading
    // announces itself.
    final message = switch (result) {
      SpeechResult.nepali => null,
      SpeechResult.fallback => l10n.medicineSpeakFallback,
      SpeechResult.unavailable => l10n.medicineSpeakUnavailable,
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.volume_up_outlined),
      tooltip: L.of(context).medicineSpeak,
      onPressed: () => _speak(context, ref),
    );
  }
}
