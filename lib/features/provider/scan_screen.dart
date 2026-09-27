import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/share/offline_snapshot.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/remote/api/api.dart';
import '../../domain/models/enums.dart';
import '../shared/widgets/app_widgets.dart';
import 'pin_challenge_dialog.dart';

/// S20 — QR scanner: redeem a grant and cache the bundle.
///
/// Redeeming genuinely needs the network — the token is signed server-side and
/// the bundle comes back with it — so the offline case says so rather than
/// failing silently. Everything *after* the redeem works offline, which is the
/// point: scan once at the door, then work through the consultation with no
/// signal.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final values =
        capture.barcodes.map((b) => b.rawValue).whereType<String>().toList();
    if (values.isEmpty) return;

    // Prefer a code we can actually use when several are in frame; otherwise
    // hand the first one over so it is rejected with the same message.
    await _redeem(
      values.firstWhere(
        (value) =>
            value.startsWith(GrantsApi.qrPrefix) ||
            value.startsWith(OfflineSnapshot.prefix),
        orElse: () => values.first,
      ),
    );
  }

  /// The one redeem path, shared by the camera and by S20's manual fallback.
  ///
  /// Keeping them on the same method is the point: the demo fallback must not
  /// be a second, subtly different way into the record.
  ///
  /// [pin] is only ever set on a second pass: a printed card (A.7) is refused
  /// with `details.pin = "required"`, the provider asks the patient, and the
  /// same payload comes back through here with the four digits attached. The
  /// app never guesses — it waits to be told a PIN is needed, which is also
  /// what will happen against a real server that signs its own tokens.
  Future<void> _redeem(String payload, {String? pin}) async {
    if (_handling && pin == null) return;

    // A self-contained code needs no server at all: the record is inside it.
    if (payload.startsWith(OfflineSnapshot.prefix)) {
      await _openOfflineSnapshot(payload);
      return;
    }

    if (!payload.startsWith(GrantsApi.qrPrefix)) {
      // Spec S20: reject foreign QR codes instantly rather than sending them
      // to the server to be told no.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.of(context).providerScanInvalid)),
        );
      }
      return;
    }

    setState(() => _handling = true);
    await _controller.stop();

    try {
      final result = await ref.read(apiProvider).grants.redeem(payload, pin: pin);

      // Cache the whole bundle so the consultation can proceed offline.
      final db = ref.read(databaseProvider);
      await ref.read(patientRepoProvider).cacheGranted(
            result.patient,
            result.grant.accessUntil ??
                DateTime.now().toUtc().add(const Duration(hours: 24))
                    .toIso8601String(),
          );

      // A printed card hands over a `read` grant, and S21 has to be able to
      // tell — it hides the write actions and says why. It outlives this
      // screen, so it goes in `sync_meta` beside the rest of the device state
      // rather than in a field this widget owns.
      await db.syncMetaDao.setReadOnlyAccess(
        result.patient.id,
        value: result.grant.scope == GrantScope.read || result.grant.longLived,
      );

      // Tier 3: S21 has to show only what the patient agreed to share, and has
      // to keep doing so after the app is closed and reopened. The server has
      // already filtered the bundle; this is what lets the screen *say* which
      // sections it is looking at rather than leaving empty gaps.
      await db.syncMetaDao.setGrantSections(
        result.patient.id,
        result.grant.sections.map((s) => s.wire).toList(),
      );

      final pregnancy = result.pregnancy;
      if (pregnancy != null) {
        await db.pregnanciesDao.upsertPregnancy(pregnancy);
        await db.pregnanciesDao.upsertContacts(result.ancContacts);
      }
      for (final item in result.timeline) {
        await _cacheTimelineItem(item.kind.wire, item.payload);
      }

      if (!mounted) return;
      await _openRedeemed(result.patient.id);
    } on Object catch (error) {
      if (!mounted) return;

      // Not a refusal — a challenge. Ask for the four digits and come back.
      if (GrantsApi.isPinChallenge(error) || GrantsApi.isPinRejected(error)) {
        await _challengeForPin(payload, retry: GrantsApi.isPinRejected(error));
        return;
      }

      setState(() => _handling = false);
      await _controller.start();
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  /// Open an SWC2 snapshot: decode it here, cache it, show S21.
  ///
  /// The shape of this mirrors the grant redeem above on purpose — same cache
  /// writes, same 24-hour window, same destination — so a record that arrived
  /// offline behaves like any other from the moment it lands. What differs is
  /// where it came from, and S21 says so in a banner.
  Future<void> _openOfflineSnapshot(String payload) async {
    // Read before the first await: the controller stop below is an async gap,
    // and this context may be gone on the far side of it.
    final l10n = L.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _handling = true);
    await _controller.stop();

    OfflineSnapshot snapshot;
    try {
      snapshot = decodeOfflineSnapshot(payload);
    } on Object {
      setState(() => _handling = false);
      await _controller.start();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.providerScanInvalid)),
      );
      return;
    }

    // Ten minutes, checked on the reader as well as the writer. Nothing is
    // stored for an expired code: a record the patient did not mean to share
    // any more must not be left sitting on this phone.
    if (snapshot.isExpired(DateTime.now().toUtc())) {
      setState(() => _handling = false);
      await _controller.start();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.providerOfflineExpired)),
      );
      return;
    }

    try {
      final rules = ref.read(rulesProvider).valueOrNull;
      final bundle = bundleFromSnapshot(
        snapshot,
        scheduleWeeks: rules == null
            ? OfflineSnapshot.defaultScheduleWeeks
            : [for (final c in rules.ancSchedule) c.weekTarget],
      );

      final db = ref.read(databaseProvider);
      final until = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 24))
          .toIso8601String();

      await ref.read(patientRepoProvider).cacheGranted(bundle.patient, until);

      // A snapshot is a full-access hand-over, the same as a scanned grant:
      // the patient held their phone out. It is not the printed card.
      await db.syncMetaDao.setReadOnlyAccess(bundle.patient.id, value: false);
      await db.syncMetaDao.setGrantSections(bundle.patient.id, const []);

      // Where this record came from, and when. S21 draws a banner from it, and
      // it is what stops an offline summary being mistaken for a synced one.
      await db.syncMetaDao.setOfflineSnapshotAt(
        bundle.patient.id,
        snapshot.generatedAt.toIso8601String(),
      );

      final pregnancy = bundle.pregnancy;
      if (pregnancy != null) {
        await db.pregnanciesDao.upsertPregnancy(pregnancy);
        await db.pregnanciesDao.upsertContacts(bundle.ancContacts);
      }

      await ref
          .read(referenceRepoProvider)
          .recordOfflineSnapshot(bundle.patient.id);

      if (!mounted) return;
      await _openRedeemed(bundle.patient.id);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _handling = false);
      await _controller.start();
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  /// Ask the patient for the PIN their card tells the provider to ask for, then
  /// retry the same payload with it.
  ///
  /// Cancelling returns the scanner to where it was rather than leaving a
  /// half-redeemed screen: a card produced by mistake must be abandonable.
  Future<void> _challengeForPin(String payload, {required bool retry}) async {
    final pin = await showPinChallenge(context, retry: retry);

    if (!mounted) return;
    if (pin == null) {
      setState(() => _handling = false);
      await _controller.start();
      return;
    }

    await _redeem(payload, pin: pin);
  }

  /// The redeem bundle carries the timeline, and each entry's `payload` is the
  /// full entity — so the visits and documents can be cached without a second
  /// round trip.
  Future<void> _cacheTimelineItem(
    String kind,
    Map<String, dynamic> payload,
  ) async {
    final db = ref.read(databaseProvider);
    try {
      switch (kind) {
        case 'visit':
          await db.visitsDao.upsertFromServer(payload);
        case 'document':
          await db.documentsDao.upsertFromServer(payload);
      }
    } on Object {
      // A single unparseable row must not abort the redeem.
    }
  }

  /// Show the record this scan produced, then come back ready for the next one.
  ///
  /// `push`, not `pushReplacement`. The scanner is the provider shell's landing
  /// tab now rather than a screen pushed on top of a list, so replacing it would
  /// tear the tab out from under itself. Pushing means back from the summary
  /// lands on a live camera, which is also what a health worker seeing patients
  /// one after another wants.
  ///
  /// Nothing about the redeem, the decode or the caching above changes — this is
  /// the navigation verb and the camera restart, and that is all.
  Future<void> _openRedeemed(String patientId) async {
    await context.push('/provider/patient/$patientId');
    if (!mounted) return;
    setState(() => _handling = false);
    await _controller.start();
  }

  Future<void> _enterCodeManually() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const ManualCodeDialog(),
    );
    if (code != null) await _redeem(code);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final online =
        ref.watch(syncStatusProvider).valueOrNull?.online ?? true;

    // Full-bleed: the camera runs edge to edge behind a transparent app bar,
    // so the preview is as large as the phone allows. Everything drawn on top
    // of it is white on a dark scrim, because the ground is a photograph and no
    // theme colour can be trusted to stay legible against it.
    return Scaffold(
      backgroundColor: AppColors.cameraBackdrop,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.onBrand,
        title: Text(
          l10n.providerScanTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.onBrand,
              ),
        ),
        iconTheme: const IconThemeData(color: AppColors.onBrand),
        actions: [
          IconButton(
            icon: const Icon(Icons.flashlight_on_outlined),
            color: AppColors.onBrand,
            tooltip: l10n.scanTorch,
            onPressed: _controller.toggleTorch,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: !online
          ? EmptyState(
              icon: Icons.wifi_off_rounded,
              title: l10n.providerScanNeedsInternet,
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: EmptyState(
                      icon: Icons.no_photography_outlined,
                      title: l10n.providerScannerUnavailable,
                    ),
                  ),
                ),

                // The viewfinder: a rounded window cut out of a dark scrim.
                // It tells the provider where to aim without a frame of corner
                // brackets floating over a moving image.
                const _ViewfinderOverlay(),

                if (_handling)
                  ColoredBox(
                    color: AppColors.cameraBackdrop.withValues(alpha: 0.6),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.onBrand,
                      ),
                    ),
                  ),

                Positioned(
                  left: AppSpacing.gutter,
                  right: AppSpacing.gutter,
                  bottom: 40,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.gutter,
                          vertical: AppSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.cameraBackdrop
                              .withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          l10n.providerScanHint,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.onBrand,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.tight),
                      // A camera that will not focus on a screen, a cracked
                      // lens, a QR read off paper — the consultation should not
                      // stop for any of them. It is also the demo fallback.
                      // A text button under the hint, not a second big control:
                      // it is the exception, and the camera is the path.
                      TextButton(
                        onPressed: _enterCodeManually,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.onBrand,
                        ),
                        child: Text(
                          l10n.providerScanManual,
                          style: const TextStyle(
                            color: AppColors.onBrand,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.onBrand,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// The dark scrim with a rounded hole in the middle of it.
///
/// Painted rather than assembled from four `Container`s so the corners of the
/// window are genuinely rounded and the scrim has no seams where the pieces
/// meet — seams are very visible over a moving camera preview.
class _ViewfinderOverlay extends StatelessWidget {
  const _ViewfinderOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ViewfinderPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // A square window, 72 % of the narrow edge, sitting slightly above centre
    // so the hint and the fallback button below it are not covered.
    final side = size.shortestSide * 0.72;
    final window = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.44),
        width: side,
        height: side,
      ),
      const Radius.circular(28),
    );

    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(window),
    );

    canvas.drawPath(
      scrim,
      Paint()..color = AppColors.cameraBackdrop.withValues(alpha: 0.5),
    );

    canvas.drawRRect(
      window,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppColors.onBrand.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_ViewfinderPainter oldDelegate) => false;
}

/// S20's manual fallback: type the payload the QR would have carried.
///
/// It validates the `SWC1:` prefix with the same constant and the same message
/// the camera path uses, so a foreign code is refused identically whichever way
/// it arrived, and pops the payload only once it is worth sending.
class ManualCodeDialog extends StatefulWidget {
  const ManualCodeDialog({super.key});

  @override
  State<ManualCodeDialog> createState() => _ManualCodeDialogState();
}

class _ManualCodeDialogState extends State<ManualCodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final payload = _code.text.trim();

    // Both formats: the demo fallback has to be able to type whatever the
    // camera would have read, and offline codes are the longer of the two.
    if (!payload.startsWith(GrantsApi.qrPrefix) &&
        !payload.startsWith(OfflineSnapshot.prefix)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.of(context).providerScanInvalid)),
      );
      return;
    }

    Navigator.of(context).pop(payload);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    return AlertDialog(
      title: Text(l10n.providerScanManualTitle),
      content: TextField(
        controller: _code,
        autofocus: true,
        autocorrect: false,
        maxLines: 2,
        minLines: 1,
        decoration: InputDecoration(hintText: l10n.providerScanManualHint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.providerScanManualSubmit),
        ),
      ],
    );
  }
}
