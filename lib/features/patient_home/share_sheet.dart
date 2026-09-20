import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/soft_card.dart';
import '../shared/widgets/app_widgets.dart';

/// S08's QR sheet: `POST /grants` with a ten-minute TTL, rendered large, with a
/// live countdown and a revoke button.
///
/// This is the one patient-facing action that genuinely requires a network —
/// the token is signed by the server — so the offline case says so plainly
/// rather than showing a QR that cannot be redeemed.
Future<void> showShareSheet(BuildContext context, String patientId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ShareSheet(patientId: patientId),
  );
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.patientId});

  final String patientId;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  GrantCreateResult? _grant;
  Object? _error;
  bool _busy = true;
  Timer? _timer;
  Duration _remaining = Duration.zero;

  /// Tier 3 — which parts of the record this QR will carry.
  ///
  /// Empty means everything, which is what a grant meant before this existed.
  /// The last choice is remembered per patient so somebody who shares only
  /// their pregnancy every month does not re-tick six chips every time.
  late Set<GrantSection> _sections = _restoreSections();

  Set<GrantSection> _restoreSections() {
    final saved = ref.read(appConfigProvider).shareSections(widget.patientId);
    return saved
        .map(GrantSection.fromWire)
        .whereType<GrantSection>()
        .toSet();
  }

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final grant = await ref.read(apiProvider).grants.create(
            patientId: widget.patientId,
            scope: GrantScope.append,
            sections: _sections.toList(),
          );
      if (!mounted) return;
      setState(() {
        _grant = grant;
        _busy = false;
      });
      _startCountdown(grant.grant.expiresAt);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _busy = false;
      });
    }
  }

  void _startCountdown(String expiresAt) {
    final expiry = DateTime.tryParse(expiresAt);
    if (expiry == null) return;

    _timer?.cancel();
    void tick() {
      final left = expiry.difference(DateTime.now().toUtc());
      if (!mounted) return;
      setState(() => _remaining = left.isNegative ? Duration.zero : left);
      if (left.isNegative) _timer?.cancel();
    }

    tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> _revoke() async {
    final grant = _grant;
    if (grant == null) return;

    try {
      await ref.read(apiProvider).grants.revoke(grant.grant.id);
      if (!mounted) return;
      _timer?.cancel();
      setState(() {
        _grant = null;
        _remaining = Duration.zero;
      });
      showSavedSnackBar(context, synced: true);
    } on Object catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  String get _countdown {
    final minutes = _remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final expired = _remaining == Duration.zero;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.patientHomeShareTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            _SectionChips(
              selected: _sections,
              onChanged: (next) {
                setState(() => _sections = next);
                unawaited(
                  ref.read(appConfigProvider).setShareSections(
                        widget.patientId,
                        next.map((s) => s.wire).toList(),
                      ),
                );
                // The token encodes the consent, so changing it means a new
                // token. Regenerating immediately is also the honest thing to
                // show: the QR on screen is always the one that will be read.
                _create();
              },
            ),
            const SizedBox(height: 16),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              )
            else if (_error != null)
              EmptyState(
                icon: Icons.wifi_off_rounded,
                title: l10n.patientHomeShareNeedsInternet,
                action: FilledButton.tonal(
                  onPressed: _create,
                  child: Text(l10n.commonRetry),
                ),
              )
            else if (_grant == null)
              EmptyState(
                icon: Icons.lock_outline,
                title: l10n.patientHomeRevoked,
                action: FilledButton.tonal(
                  onPressed: _create,
                  child: Text(l10n.patientHomeRegenerate),
                ),
              )
            else ...[
              // Spec S08: at least 240 px, and on a white ground so a cheap
              // scanner in poor light still reads it.
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.qrCanvas,
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
                child: QrImageView(
                  data: _grant!.qrPayload,
                  size: 260,
                  backgroundColor: AppColors.qrCanvas,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                expired
                    ? l10n.errorGrantExpired
                    : l10n.patientHomeShareExpiresIn(_countdown),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: expired
                          ? AppColors.dangerInkOf(context)
                          : Theme.of(context).colorScheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _create,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(l10n.patientHomeRegenerate),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: expired ? null : _revoke,
                      icon: Icon(Icons.block_outlined, size: 18),
                      label: Text(l10n.patientHomeRevoke),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.dangerInkOf(context),
                        side: BorderSide(
                          color: AppColors.triageRed.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "What to share" — six chips and an "Everything" reset.
///
/// Nothing selected means everything, which is both the default and the least
/// surprising reading of an empty row. The chips are what the patient touches,
/// so they say what a patient would say — "Pregnancy", not "anc_contacts".
class _SectionChips extends StatelessWidget {
  const _SectionChips({required this.selected, required this.onChanged});

  final Set<GrantSection> selected;
  final ValueChanged<Set<GrantSection>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final everything = selected.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.shareWhatToShare),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            ChoiceChip(
              label: Text(l10n.shareAllSections),
              selected: everything,
              onSelected: (_) => onChanged(const {}),
            ),
            for (final section in GrantSection.values)
              FilterChip(
                label: Text(sectionLabel(l10n, section)),
                selected: selected.contains(section),
                onSelected: (on) {
                  final next = {...selected};
                  if (on) {
                    next.add(section);
                  } else {
                    next.remove(section);
                  }
                  onChanged(next);
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// The patient-facing name for a section, in either language.
String sectionLabel(L l10n, GrantSection section) => switch (section) {
      GrantSection.summary => l10n.shareSectionSummary,
      GrantSection.visits => l10n.shareSectionVisits,
      GrantSection.documents => l10n.shareSectionDocuments,
      GrantSection.pregnancy => l10n.shareSectionPregnancy,
      GrantSection.child => l10n.shareSectionChild,
      GrantSection.audit => l10n.shareSectionAudit,
    };
