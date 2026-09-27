import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../core/share/offline_snapshot.dart';
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

  /// The self-contained code, when this sheet is in offline mode.
  ///
  /// Offline mode does not call the server at all: the record travels inside
  /// the QR. See [OfflineSnapshot].
  EncodedSnapshot? _offline;

  /// True when the sheet is drawing an SWC2 snapshot rather than a grant.
  ///
  /// The default follows where the phone is standing: with the mock serving
  /// there is no server to issue a grant that another phone could redeem, so
  /// offline is the only mode that actually works. The choice is then
  /// remembered per device.
  late bool _offlineMode = _restoreMode();

  bool _restoreMode() {
    final config = ref.read(appConfigProvider);
    return config.offlineShareMode ?? ref.read(useMockServerProvider);
  }

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

    if (_offlineMode) {
      await _createOffline();
      return;
    }

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

  /// Fold the record into a QR. No network, no grant, no server.
  Future<void> _createOffline() async {
    try {
      final patient = await ref.read(patientProvider(widget.patientId).future);
      if (patient == null) throw StateError('No such patient');

      final summary =
          await ref.read(patientSummaryProvider(widget.patientId).future);
      final pregnancy =
          await ref.read(activePregnancyProvider(widget.patientId).future);
      final contacts = pregnancy == null
          ? const <AncContact>[]
          : (await ref.read(pregnancyBundleProvider(pregnancy.id).future))
              .ancContacts;

      final snapshot = buildOfflineSnapshot(
        patient: patient,
        summary: summary,
        pregnancy: pregnancy,
        contacts: contacts,
        now: DateTime.now().toUtc(),
      );
      final encoded = encodeOfflineSnapshot(snapshot);

      // A code that had to shed detail is worth saying out loud: the provider
      // is about to read a record with pieces missing.
      for (final trim in encoded.trims) {
        debugPrint('[offline snapshot] ${snapshot.patientId}: $trim');
      }
      debugPrint(
        '[offline snapshot] ${snapshot.patientId}: ${encoded.bytes} bytes',
      );

      if (!mounted) return;
      setState(() {
        _offline = encoded;
        _grant = null;
        _busy = false;
        _error = null;
      });
      _startCountdown(snapshot.expiresAt.toIso8601String());
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _busy = false;
      });
    }
  }

  void _setMode({required bool offline}) {
    if (offline == _offlineMode) return;
    setState(() {
      _offlineMode = offline;
      _offline = null;
      _grant = null;
    });
    unawaited(
      ref.read(appConfigProvider).setOfflineShareMode(value: offline),
    );
    _create();
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

  /// What the QR carries, whichever mode the sheet is in.
  String? get _payload =>
      _offlineMode ? _offline?.payload : _grant?.qrPayload;

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
            const SizedBox(height: AppSpacing.lg),
            _ModeToggle(
              offline: _offlineMode,
              onChanged: (offline) => _setMode(offline: offline),
            ),
            const SizedBox(height: AppSpacing.lg),
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
            else if (_payload == null)
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
              //
              // An expired offline code is greyed rather than removed: the
              // patient is holding the phone out and needs to see that the
              // thing they are holding out has gone stale, not an empty box.
              GestureDetector(
                onTap: expired ? _create : null,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: expired ? 0.15 : 1,
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.qrCanvas,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radius),
                        ),
                        child: QrImageView(
                          data: _payload!,
                          size: 260,
                          backgroundColor: AppColors.qrCanvas,
                          // Level L on an offline code: the payload is an
                          // order of magnitude longer than a grant token, and
                          // every extra byte of error correction is another
                          // module for a phone camera to resolve across a
                          // desk. The screen is bright and the code is read
                          // from 20 cm, not off a creased printout.
                          errorCorrectionLevel: _offlineMode
                              ? QrErrorCorrectLevel.L
                              : QrErrorCorrectLevel.M,
                        ),
                      ),
                    ),
                    if (expired)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              size: 32,
                              color: AppColors.dangerInkOf(context),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              l10n.shareOfflineExpired,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: AppColors.dangerInkOf(context),
                                  ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_offlineMode && !expired) ...[
                Text(
                  l10n.shareOfflineNote,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Text(
                expired
                    ? (_offlineMode
                        ? l10n.shareOfflineExpired
                        : l10n.errorGrantExpired)
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
                    // Nothing to revoke offline: no server was told about this
                    // code, so there is nobody to tell to forget it. It dies
                    // on its own timer instead, and the tooltip says so rather
                    // than leaving a dead button unexplained.
                    child: Tooltip(
                      message: _offlineMode
                          ? l10n.shareRevokeOfflineHint
                          : l10n.patientHomeRevoke,
                      child: OutlinedButton.icon(
                        onPressed: (expired || _offlineMode) ? null : _revoke,
                        icon: const Icon(Icons.block_outlined, size: 18),
                        label: Text(l10n.patientHomeRevoke),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.dangerInkOf(context),
                          side: BorderSide(
                            color: AppColors.triageRed.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_offlineMode) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.shareRevokeOfflineHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// "Live (server)" / "Offline (no server)".
///
/// Two ways of sharing the same record that behave differently enough that the
/// patient has to be able to see which one is on: one hands over a token the
/// provider trades with a server, the other hands over the record itself.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.offline, required this.onChanged});

  final bool offline;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    return SegmentedButton<bool>(
      segments: [
        ButtonSegment(
          value: false,
          icon: const Icon(Icons.cloud_outlined, size: 18),
          label: Text(l10n.shareModeLive),
        ),
        ButtonSegment(
          value: true,
          icon: const Icon(Icons.cloud_off_outlined, size: 18),
          label: Text(l10n.shareModeOffline),
        ),
      ],
      selected: {offline},
      showSelectedIcon: false,
      onSelectionChanged: (value) => onChanged(value.first),
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
