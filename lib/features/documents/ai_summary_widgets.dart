import 'package:flutter/material.dart';

import '../../core/errors/error_messages.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/soft_card.dart';
import 'ai_summary.dart';

/// The warning that sits above every generated summary, in both languages.
///
/// Not localised to the app's current language, on purpose. This is the one
/// sentence that decides whether somebody takes a machine's reading of a
/// prescription as fact, and the person holding the phone is frequently not the
/// person the medicine is for. Both of them get to read it.
const String aiUnverifiedNp =
    'AI ले बनाएको, प्रमाणित छैन — स्वास्थ्यकर्मीसँग पक्का गर्नुहोस्';
const String aiUnverifiedEn =
    'AI-generated, unverified — confirm with a health worker';

/// S10's "Draft summary (AI)" section: the button, the wait, and the draft.
class AiSummarySection extends StatelessWidget {
  const AiSummarySection({
    super.key,
    required this.state,
    required this.onStart,
  });

  final AiSummaryState state;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    return switch (state.phase) {
      AiSummaryPhase.idle => FilledButton.tonalIcon(
          onPressed: onStart,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: Text(l10n.documentsAiDraftAction),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
      AiSummaryPhase.requesting || AiSummaryPhase.queued => Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                l10n.documentsAiDraftWorking,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
              ),
            ),
          ],
        ),
      AiSummaryPhase.done => _Draft(summary: state.summary ?? ''),
      AiSummaryPhase.failed || AiSummaryPhase.timedOut => _Failed(
          state: state,
          onRetry: onStart,
        ),
    };
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.state, required this.onRetry});

  final AiSummaryState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final error = state.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline,
              size: 18,
              color: AppColors.triageRed,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                // A server that refused outright says so in its own words; a
                // job that ran and produced nothing gets the plain sentence.
                error != null
                    ? localizedError(l10n, error)
                    : state.phase == AiSummaryPhase.timedOut
                        ? l10n.documentsAiDraftTimedOut
                        : l10n.documentsAiDraftFailed,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.dangerInkOf(context),
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(l10n.commonRetry),
        ),
      ],
    );
  }
}

class _Draft extends StatelessWidget {
  const _Draft({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.documentsAiDraftTitle),
        // The label is above the text, not below it: by the time somebody has
        // read a dose they have already acted on it. The amber edge is kept —
        // this is the other place in the app, alongside the triage banner,
        // where a border is doing safety work rather than decoration.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.triageAmberTint,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSpacing.radiusSm),
            ),
            border: Border.all(color: AppColors.triageAmber),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: AppColors.triageAmber,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      aiUnverifiedNp,
                      style: TextStyle(
                        color: AppColors.onTriageAmber,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      aiUnverifiedEn,
                      style: TextStyle(
                        color: AppColors.onTriageAmber,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(AppSpacing.radiusSm),
            ),
          ),
          child: SelectableText(
            summary,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
