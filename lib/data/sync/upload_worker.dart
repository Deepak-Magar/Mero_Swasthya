import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_error.dart';
import '../local/app_database.dart';
import '../local/daos/documents_dao.dart';
import '../remote/api/api.dart';

/// Reads the captured image off disk. Injected so a test never touches a real
/// file system.
typedef FileBytesReader = Future<List<int>> Function(String path);

Future<List<int>> _readFile(String path) => File(path).readAsBytes();

/// Spec §7: for each pending document — `POST /documents/presign` → `PUT` the
/// bytes → `POST /documents/:id/complete`; on failure increment
/// `upload_attempts` and give up at five.
///
/// The three steps are separate requests, so the worker has to be safe to
/// interrupt at any point. It is, because the document id is client-generated
/// and presign is keyed on it: re-running a half-finished upload overwrites the
/// same object rather than creating a second one.
class UploadWorker {
  const UploadWorker({
    required this.db,
    required this.api,
    this.readFile = _readFile,
  });

  final AppDatabase db;
  final Api api;
  final FileBytesReader readFile;

  /// Uploads everything that is waiting. Returns how many completed.
  ///
  /// One document failing does not stop the rest — a photo that cannot be read
  /// should not hold up the queue behind it.
  Future<int> run() async {
    var uploaded = 0;
    for (final row in await db.documentsDao.pendingUploads()) {
      if (await _uploadOne(row)) uploaded++;
    }
    return uploaded;
  }

  Future<bool> _uploadOne(DocumentRow row) async {
    final path = row.localPath;
    if (path == null) return false;

    try {
      final bytes = await readFile(path);

      final presigned = await api.documents.presign(
        id: row.id,
        patientId: row.patientId,
        type: row.type.wire,
        title: row.title,
        takenAt: row.takenAt,
        contentType: _contentTypeFor(path),
        sizeBytes: bytes.length,
      );

      await api.documents.upload(presigned, bytes: bytes);
      final completed = await api.documents.complete(row.id);

      // Clears local_path, which is what takes the row out of the queue.
      await db.documentsDao.markUploaded(
        row.id,
        downloadUrl: completed.downloadUrl,
      );
      return true;
    } on AppError catch (e) {
      await _recordFailure(row, e.message);
      return false;
    } on FileSystemException catch (e) {
      // The photo is gone — the gallery was cleared, or the OS reclaimed the
      // cache. Retrying cannot help, so burn the attempts straight away rather
      // than waking up for it on every cycle forever.
      await _abandon(row, 'Image file missing: ${e.message}');
      return false;
    }
  }

  Future<void> _recordFailure(DocumentRow row, String reason) async {
    await db.documentsDao.recordUploadFailure(row.id);

    final attempts = row.uploadAttempts + 1;
    if (attempts >= DocumentsDao.maxUploadAttempts) {
      debugPrint(
        '[upload] giving up on ${row.id} after $attempts attempts: $reason',
      );
    }
  }

  Future<void> _abandon(DocumentRow row, String reason) async {
    debugPrint('[upload] abandoning ${row.id}: $reason');
    for (var i = row.uploadAttempts; i < DocumentsDao.maxUploadAttempts; i++) {
      await db.documentsDao.recordUploadFailure(row.id);
    }
  }

  /// The capture screen compresses to JPEG (spec §3), but a document imported
  /// from the gallery may not be.
  static String _contentTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
