import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/dates/bs_date.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers.dart';
import '../../data/remote/api/grants_api.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../shared/widgets/app_widgets.dart';

/// The one sentence that makes a printed card safe, in both languages.
///
/// Deliberately *not* localised: the card is a physical object that outlives
/// whichever language the phone happened to be in when it was printed, and the
/// health worker who picks it up may not read the same one as the patient who
/// carries it. So every copy carries both.
const String askForPinNp = 'बिरामीसँग ४ अंकको PIN सोध्नुहोस्';
const String askForPinEn = 'Ask the patient for their 4-digit PIN';

/// Spec A.7's printed fallback card.
///
/// The ten-minute QR of S08 assumes the patient has a charged phone with a
/// signal at the moment a health worker asks for the record. On a hill in Dang
/// neither is safe to assume, so this is the paper answer: one `read` grant
/// with a year's TTL, printed once, folded into the same plastic sleeve as the
/// immunisation card. Because it can be photographed off a wall it is worth
/// nothing on its own, which is why every copy asks for the patient's four
/// digits and why the redeem is refused until they arrive.
class PrintedCardScreen extends ConsumerStatefulWidget {
  const PrintedCardScreen({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<PrintedCardScreen> createState() => _PrintedCardScreenState();
}

class _PrintedCardScreenState extends ConsumerState<PrintedCardScreen> {
  final _boundary = GlobalKey();

  GrantCreateResult? _grant;
  Object? _error;
  bool _busy = true;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final grant = await ref.read(apiProvider).grants.create(
            patientId: widget.patientId,
            scope: GrantScope.read,
            ttlMinutes: GrantsApi.printedCardTtlMinutes,
          );
      if (!mounted) return;
      setState(() {
        _grant = grant;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _busy = false;
      });
    }
  }

  /// Rasterise the card exactly as drawn and hand the PNG to the share sheet,
  /// which is how it reaches a print shop, a chat app or the gallery.
  ///
  /// At 3x the 320 dp card comes out near 960 px wide — enough for the QR to
  /// survive being printed small and photographed back.
  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final object = _boundary.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) return;

      final image = await object.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return;

      await _shareBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } on Object catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareBytes(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/swasthya-card-${widget.patientId}.png';
    await File(path).writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(path, mimeType: 'image/png')]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final patient = ref.watch(patientProvider(widget.patientId)).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.printedCardTitle)),
      body: _buildBody(l10n, patient),
    );
  }

  Widget _buildBody(L l10n, Patient? patient) {
    if (_busy) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: EmptyState(
          icon: Icons.wifi_off_rounded,
          title: l10n.patientHomeShareNeedsInternet,
          body: l10n.printedCardNeedsInternet,
          action: FilledButton.tonal(
            onPressed: _create,
            child: Text(l10n.commonRetry),
          ),
        ),
      );
    }

    final grant = _grant;
    if (patient == null || grant == null) {
      return Center(child: Text(l10n.errorNotFound));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Center(
          child: RepaintBoundary(
            key: _boundary,
            child: PrintedCard(patient: patient, qrPayload: grant.qrPayload),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _sharing ? null : _share,
          icon: const Icon(Icons.ios_share_rounded),
          label: Text(l10n.printedCardShare),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(l10n.printedCardExplainer)),
          ],
        ),
      ],
    );
  }
}

/// The card itself, split out so it can be laid out in a test with no grant, no
/// network and no share sheet behind it.
class PrintedCard extends StatelessWidget {
  const PrintedCard({
    super.key,
    required this.patient,
    required this.qrPayload,
  });

  final Patient patient;
  final String qrPayload;

  /// Fixed, not from the theme: this is a picture of a printed card, and it has
  /// to come out the same whether the phone is in dark mode or not. The values
  /// live in `AppColors` under "Print" so the card's palette is named in the
  /// one place every other colour in the app is named.
  static const Color _ink = AppColors.printInk;
  static const Color _muted = AppColors.printMuted;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final dob = BsDate.parseAd(patient.dob);

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: AppColors.qrCanvas,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.printBorder, width: 2),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The card is printed and handed over, so it carries the full
              // lock-up rather than the app's own heading style. It is always
              // drawn on the white print ground, so the light variant is
              // right here whatever the phone's theme is.
              Image.asset(
                'assets/brand/logo_full.png',
                // The lock-up is nearly square, so height drives width: at 40
                // the wordmark came out about 11 px tall on the phone and
                // unreadable once printed. 72 is what makes "Mero swasthya"
                // legible on a card somebody keeps in a wallet.
                height: 72,
                fit: BoxFit.contain,
                semanticLabel: l10n.appTitle,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            patient.name,
            style: const TextStyle(
              color: _ink,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          if (dob != null)
            Text(
              '${l10n.patientFormDob}: ${BsDate.formatBoth(dob)}',
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          if (patient.bloodGroup != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${l10n.patientHomeBloodGroup}: ${patient.bloodGroup}',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Center(
            child: QrImageView(
              data: qrPayload,
              size: 220,
              backgroundColor: AppColors.qrCanvas,
              // A card lives in a pocket; a year of creasing eats modules, and
              // high correction is what buys them back.
              errorCorrectionLevel: QrErrorCorrectLevel.H,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.printNoticeBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.printNoticeBorder),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  askForPinNp,
                  style: TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  askForPinEn,
                  style: TextStyle(color: _ink, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
