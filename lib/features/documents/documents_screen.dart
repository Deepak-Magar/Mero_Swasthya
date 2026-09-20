import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/dates/bs_date.dart';
import '../../core/ids/ids.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/app_database.dart';
import '../../data/local/daos/documents_dao.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../shared/widgets/soft_card.dart';
import '../shared/widgets/app_widgets.dart';
import '../shared/widgets/bs_date_field.dart';
import 'document_detail_screen.dart';

/// S10 — Documents: photograph paper records.
///
/// Capture writes the compressed file and the metadata row immediately and
/// returns; the bytes leave later, in the sync engine's upload worker. A health
/// worker photographing a discharge sheet in a corridor never waits on a
/// network.
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final documents = ref.watch(documentRowsProvider(patientId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.documentsTitle),
        actions: const [SyncChip()],
      ),
      body: asyncView(
        documents,
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.photo_library_outlined,
              title: l10n.documentsEmpty,
              action: FilledButton.icon(
                onPressed: () => _capture(context, ref, patientId),
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(l10n.documentsCapture),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.lg,
              AppSpacing.gutter,
              104,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.lg,
              crossAxisSpacing: AppSpacing.lg,
              childAspectRatio: 0.72,
            ),
            itemCount: list.length,
            itemBuilder: (context, index) =>
                _DocumentTile(row: list[index]),
          );
        },
      ),
      // The empty state already carries "Capture paper" as its primary action,
      // and two identical primary buttons on one screen is one too many. The
      // FAB appears once there is a grid to sit on top of.
      floatingActionButton: (documents.valueOrNull?.isEmpty ?? true)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _capture(context, ref, patientId),
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(l10n.documentsCapture),
            ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.row});

  final DocumentRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final stuck = row.status == DocumentStatus.pendingUpload &&
        row.uploadAttempts >= DocumentsDao.maxUploadAttempts;

    final (statusLabel, statusColour) = stuck
        ? (l10n.documentsUploadStuck, AppColors.dangerInkOf(context))
        : switch (row.status) {
            DocumentStatus.uploaded => (
                l10n.documentsUploaded,
                AppColors.successInkOf(context),
              ),
            DocumentStatus.pendingUpload => (
                l10n.documentsPendingUpload,
                AppColors.triageAmber,
              ),
          };

    final text = Theme.of(context).textTheme;

    return SoftCard(
      padding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DocumentDetailScreen(row: row),
        ),
      ),
      semanticLabel: row.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The photograph itself is most of the tile: a wall of identical
          // paper icons is unsearchable, and the thing somebody is looking for
          // is "the blue lab form", not "Lab report, Ashadh".
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                DocumentThumbnail(row: row),
                // The type chip floats on the photo rather than taking a line
                // of its own under it — the tile has three lines of text to
                // fit and the photo has room to spare.
                Positioned(
                  left: AppSpacing.sm,
                  top: AppSpacing.sm,
                  child: SoftPill(
                    icon: DocumentTileIcons.iconFor(row.type),
                    label: _typeLabel(l10n, row.type),
                    dense: true,
                    foreground: AppColors.brandOf(context),
                    background: AppColors.surface,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall,
                ),
                const SizedBox(height: AppSpacing.tight),
                BsDateText(
                  row.takenAt,
                  showAd: false,
                  style: text.bodySmall,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      row.status == DocumentStatus.uploaded
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_upload_outlined,
                      size: 14,
                      color: statusColour,
                    ),
                    const SizedBox(width: AppSpacing.tight),
                    Expanded(
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColour,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
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

/// Shared with the detail screen so a document looks the same in both places.
abstract final class DocumentTileIcons {
  static IconData iconFor(DocumentType type) => switch (type) {
        DocumentType.prescription => Icons.receipt_long_outlined,
        DocumentType.lab => Icons.science_outlined,
        DocumentType.discharge => Icons.local_hospital_outlined,
        DocumentType.referral => Icons.forward_to_inbox_outlined,
        DocumentType.other => Icons.description_outlined,
      };
}

/// Spec S10: compress to 1600 px / q80 before anything is stored, so a 4 MB
/// camera frame never becomes a 4 MB upload on a 2G link.
Future<void> _capture(
  BuildContext context,
  WidgetRef ref,
  String patientId,
) async {
  final l10n = L.of(context);

  final XFile? shot;
  try {
    shot = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
    );
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.documentsCameraUnavailable)),
      );
    }
    return;
  }
  if (shot == null || !context.mounted) return;

  final meta = await showModalBottomSheet<_DocumentMeta>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _MetaSheet(),
  );
  if (meta == null || !context.mounted) return;

  final id = newId();
  final path = await _compressTo(shot, id);

  await ref.read(documentRepoProvider).capture(
        Document(
          id: id,
          patientId: patientId,
          type: meta.type,
          title: meta.title,
          takenAt: BsDate.formatAd(meta.takenAt),
        ),
        path,
      );

  if (context.mounted) {
    showSaveResult(
      ScaffoldMessenger.of(context),
      L.of(context),
      ref.read(databaseProvider),
      rowId: id,
    );
  }
}

Future<String> _compressTo(XFile source, String id) async {
  final directory = await getApplicationDocumentsDirectory();
  final target = p.join(directory.path, 'documents', '$id.jpg');
  await Directory(p.dirname(target)).create(recursive: true);

  final compressed = await FlutterImageCompress.compressAndGetFile(
    source.path,
    target,
    quality: 80,
    minWidth: 1600,
    minHeight: 1600,
  );

  // If compression is unavailable the original still has to reach the server.
  if (compressed != null) return compressed.path;
  await File(source.path).copy(target);
  return target;
}

class _DocumentMeta {
  const _DocumentMeta({
    required this.type,
    required this.title,
    required this.takenAt,
  });

  final DocumentType type;
  final String title;
  final DateTime takenAt;
}

class _MetaSheet extends StatefulWidget {
  const _MetaSheet();

  @override
  State<_MetaSheet> createState() => _MetaSheetState();
}

class _MetaSheetState extends State<_MetaSheet> {
  final _title = TextEditingController();
  DocumentType _type = DocumentType.prescription;
  DateTime _takenAt = DateTime.now();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String _label(L l10n, DocumentType type) => switch (type) {
        DocumentType.prescription => l10n.documentsTypePrescription,
        DocumentType.lab => l10n.documentsTypeLab,
        DocumentType.discharge => l10n.documentsTypeDischarge,
        DocumentType.referral => l10n.documentsTypeReferral,
        DocumentType.other => l10n.documentsTypeOther,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.gutter,
        right: AppSpacing.gutter,
        top: AppSpacing.sm,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(l10n.documentsCapture),
          DropdownButtonFormField<DocumentType>(
            initialValue: _type,
            decoration: InputDecoration(labelText: l10n.documentsType),
            items: [
              for (final type in DocumentType.values)
                DropdownMenuItem(value: type, child: Text(_label(l10n, type))),
            ],
            onChanged: (value) =>
                setState(() => _type = value ?? DocumentType.other),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: l10n.documentsTitleLabel),
          ),
          const SizedBox(height: AppSpacing.lg),
          BsDateField(
            label: l10n.documentsTakenAt,
            value: _takenAt,
            lastDate: DateTime.now(),
            onChanged: (value) =>
                setState(() => _takenAt = value ?? DateTime.now()),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              _DocumentMeta(
                type: _type,
                title: _title.text.trim().isEmpty
                    ? _label(l10n, _type)
                    : _title.text.trim(),
                takenAt: _takenAt,
              ),
            ),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
  }
}
