import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../domain/models/models.dart';
import 'patient_pdf_service.dart';

/// S08's "Export PDF".
///
/// Hands the bytes to the platform's own print/share sheet, which on Android is
/// the same dialog that reaches a Bluetooth printer, Google Drive, WhatsApp or
/// a PDF viewer. That breadth is the point: the sheet has to be able to get to
/// wherever this particular family keeps things.
class ExportPdfButton extends ConsumerStatefulWidget {
  const ExportPdfButton({super.key, required this.patient});

  final Patient patient;

  @override
  ConsumerState<ExportPdfButton> createState() => _ExportPdfButtonState();
}

class _ExportPdfButtonState extends ConsumerState<ExportPdfButton> {
  bool _busy = false;

  Future<void> _export() async {
    final l10n = L.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      final bytes =
          await ref.read(patientPdfServiceProvider).build(widget.patient.id);
      if (!mounted) return;

      await Printing.sharePdf(
        bytes: bytes,
        filename: PatientPdfService.fileNameFor(widget.patient),
      );
    } on Object catch (error) {
      debugPrint('PDF export failed: $error');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.exportPdfFailed)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    return OutlinedButton.icon(
      onPressed: _busy ? null : _export,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.picture_as_pdf_outlined),
      label: Text(_busy ? l10n.exportPdfWorking : l10n.exportPdf),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    );
  }
}
