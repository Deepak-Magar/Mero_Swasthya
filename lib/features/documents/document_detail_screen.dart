import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/app_database.dart';
import '../../domain/models/enums.dart';
import '../shared/widgets/app_widgets.dart';
import 'ai_summary.dart';
import 'ai_summary_widgets.dart';
import 'documents_screen.dart' show DocumentTileIcons;

/// The captured image, wherever it currently lives.
///
/// Spec S10 shows a grid of thumbnails, and the picture is on the device from
/// the moment it is taken — long before the upload worker gets to it. So the
/// local file is preferred over `downloadUrl`: it is present sooner, costs no
/// data, and works with the network off, which is the whole premise of the app.
class DocumentThumbnail extends StatelessWidget {
  const DocumentThumbnail({super.key, required this.row, this.fit = BoxFit.cover});

  final DocumentRow row;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = _Placeholder(type: row.type);
    final localPath = row.localPath;

    if (localPath != null) {
      final file = File(localPath);
      return Image.file(
        file,
        fit: fit,
        width: double.infinity,
        // The file can be gone — the OS reclaims caches, and the upload worker
        // clears the path once the bytes are safely on the server.
        errorBuilder: (context, _, _) => _remoteOrPlaceholder(placeholder),
      );
    }

    return _remoteOrPlaceholder(placeholder);
  }

  Widget _remoteOrPlaceholder(Widget placeholder) {
    final url = row.downloadUrl;
    if (url == null) return placeholder;

    return Image.network(
      url,
      fit: fit,
      width: double.infinity,
      errorBuilder: (context, _, _) => placeholder,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.type});

  final DocumentType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        DocumentTileIcons.iconFor(type),
        size: 48,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

/// S10 detail: "full image (pinch zoom)", plus the Tier-2 AI draft summary.
///
/// A paper record is often a dense lab printout photographed at arm's length —
/// without zoom the screen is decorative rather than useful.
class DocumentDetailScreen extends ConsumerStatefulWidget {
  const DocumentDetailScreen({super.key, required this.row});

  final DocumentRow row;

  @override
  ConsumerState<DocumentDetailScreen> createState() =>
      _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  late AiSummaryState _summary = _initialSummary();
  StreamSubscription<AiSummaryState>? _run;

  /// A summary generated on an earlier visit is already on the device, so the
  /// screen opens showing it rather than offering to generate it again.
  AiSummaryState _initialSummary() {
    final existing = widget.row.aiSummary;
    if (widget.row.aiSummaryStatus == AiSummaryStatus.done &&
        existing != null) {
      return AiSummaryState(AiSummaryPhase.done, summary: existing);
    }
    return const AiSummaryState.idle();
  }

  @override
  void dispose() {
    _run?.cancel();
    super.dispose();
  }

  void _startSummary() {
    _run?.cancel();

    final api = ref.read(apiProvider).documents;
    final db = ref.read(databaseProvider);
    final id = widget.row.id;

    final run = AiSummaryRun(
      summarize: () => api.summarize(id),
      fetch: () => api.find(id),
      // Keep the draft: it cost a round trip and a model to produce, and the
      // next person to open this document may have no signal at all.
      onDocument: (document) =>
          unawaited(db.documentsDao.upsert(document).catchError((_) {})),
    );

    _run = run.start().listen((state) {
      if (mounted) setState(() => _summary = state);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final row = widget.row;
    final aiEnabled =
        ref.watch(configFlagsProvider).valueOrNull?.aiSummaryEnabled ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(row.title)),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: ColoredBox(
              // The photograph is the content; a dark ground is what stops the
              // page glowing around it.
              color: AppColors.cameraBackdrop,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 6,
                child: Center(
                  child: DocumentThumbnail(row: row, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          Flexible(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.lg,
                AppSpacing.gutter,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(DocumentTileIcons.iconFor(row.type), size: 18),
                      const SizedBox(width: 8),
                      Text(_typeLabel(l10n, row.type)),
                      const Spacer(),
                      _StatusChip(row: row),
                    ],
                  ),
                  const SizedBox(height: 8),
                  BsDateText(row.takenAt),
                  // Spec S10: the button exists only when `GET /config` says the
                  // backend can actually do this. A button that answers 501 is
                  // worse than no button.
                  if (aiEnabled) ...[
                    const SizedBox(height: 16),
                    AiSummarySection(
                      state: _summary,
                      onStart: _startSummary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _typeLabel(L l10n, DocumentType type) => switch (type) {
        DocumentType.prescription => l10n.documentsTypePrescription,
        DocumentType.lab => l10n.documentsTypeLab,
        DocumentType.discharge => l10n.documentsTypeDischarge,
        DocumentType.referral => l10n.documentsTypeReferral,
        DocumentType.other => l10n.documentsTypeOther,
      };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.row});

  final DocumentRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final uploaded = row.status == DocumentStatus.uploaded;

    return Chip(
      avatar: Icon(
        uploaded ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
        size: 16,
        color: uploaded ? TriageColors.green : TriageColors.amber,
      ),
      label: Text(
        uploaded ? l10n.documentsUploaded : l10n.documentsPendingUpload,
        style: const TextStyle(fontSize: 12),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
