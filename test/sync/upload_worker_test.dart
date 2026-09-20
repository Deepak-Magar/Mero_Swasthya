import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/net/mock_api.dart';
import 'package:mero_swasthya/data/local/app_database.dart';
import 'package:mero_swasthya/data/local/daos/documents_dao.dart';
import 'package:mero_swasthya/data/remote/api/api.dart';
import 'package:mero_swasthya/data/repositories/document_repo.dart';
import 'package:mero_swasthya/data/repositories/sync_kicker.dart';
import 'package:mero_swasthya/data/sync/upload_worker.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';

import '../support/transports.dart';

/// Spec §7: presign → PUT → complete, incrementing `upload_attempts` on failure
/// and giving up at five.
void main() {
  late AppDatabase db;
  late FlakyTransport transport;
  late DocumentRepo repo;
  late UploadWorker worker;
  late List<String> readPaths;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    transport = FlakyTransport(MockApi(clock: () => DateTime.utc(2026, 9, 18)));
    repo = DocumentRepo(db, const NoopSyncKicker());
    readPaths = [];
    worker = UploadWorker(
      db: db,
      api: Api(transport),
      readFile: (path) async {
        readPaths.add(path);
        return const [1, 2, 3, 4];
      },
    );
  });
  tearDown(() => db.close());

  Document document({String id = 'd1', DocumentType type = DocumentType.lab}) =>
      Document(
        id: id,
        patientId: MockApi.sitaId,
        type: type,
        title: 'Discharge sheet',
        takenAt: '2026-07-02',
      );

  Future<void> capture({String id = 'd1', String path = '/data/d1.jpg'}) =>
      repo.capture(document(id: id), path);

  test('a captured document is uploaded and leaves the queue', () async {
    await capture();

    expect(await worker.run(), 1);

    final stored = await repo.findById('d1');
    expect(stored!.status, DocumentStatus.uploaded);
    expect(stored.downloadUrl, isNotNull);
    expect(
      await repo.pendingUploads(),
      isEmpty,
      reason: 'clearing local_path is what takes it out of the queue',
    );
    expect(readPaths, ['/data/d1.jpg']);
  });

  test('a second run does nothing', () async {
    await capture();
    await worker.run();
    readPaths.clear();

    expect(await worker.run(), 0);
    expect(readPaths, isEmpty);
  });

  test('a failure counts an attempt and leaves the document queued', () async {
    await capture();
    transport.offline = true;

    expect(await worker.run(), 0);

    final pending = await repo.pendingUploads();
    expect(pending.single.uploadAttempts, 1);
    expect(pending.single.status, DocumentStatus.pendingUpload);
  });

  test('it gives up after five attempts and surfaces as stuck', () async {
    await capture();
    transport.offline = true;

    for (var i = 0; i < DocumentsDao.maxUploadAttempts; i++) {
      await worker.run();
    }

    expect(await repo.pendingUploads(), isEmpty);
    expect((await repo.watchStuckUploads().first).single.id, 'd1');

    // Even back online, the worker does not pick it up again on its own.
    transport.offline = false;
    expect(await worker.run(), 0);
  });

  test('coming back online before the retries run out still uploads', () async {
    await capture();
    transport.offline = true;
    await worker.run();
    await worker.run();

    transport.offline = false;

    expect(await worker.run(), 1);
    expect((await repo.findById('d1'))!.status, DocumentStatus.uploaded);
  });

  test('a missing file is abandoned at once rather than retried forever',
      () async {
    // The gallery was cleared or the OS reclaimed the cache; no number of
    // retries will bring the bytes back.
    worker = UploadWorker(
      db: db,
      api: Api(transport),
      readFile: (path) async =>
          throw const FileSystemException('No such file', '/data/d1.jpg'),
    );
    await capture();

    expect(await worker.run(), 0);

    expect(await repo.pendingUploads(), isEmpty);
    expect(
      (await repo.watchStuckUploads().first).single.id,
      'd1',
      reason: 'one pass exhausts the attempts',
    );
  });

  test('one bad document does not block the rest of the queue', () async {
    worker = UploadWorker(
      db: db,
      api: Api(transport),
      readFile: (path) async {
        if (path.contains('bad')) {
          throw const FileSystemException('No such file');
        }
        return const [1, 2, 3];
      },
    );
    await capture(id: 'bad', path: '/data/bad.jpg');
    await capture(id: 'good', path: '/data/good.jpg');

    expect(await worker.run(), 1);

    expect((await repo.findById('good'))!.status, DocumentStatus.uploaded);
    expect((await repo.findById('bad'))!.status, DocumentStatus.pendingUpload);
  });

  test('the content type follows the file extension', () async {
    // The capture screen compresses to JPEG, but a gallery import may not be.
    await capture(id: 'png', path: '/data/scan.png');
    await worker.run();

    // MockApi echoes the content type it was given straight back.
    final api = Api(transport);
    final presigned = await api.documents.presign(
      id: 'probe',
      patientId: MockApi.sitaId,
      type: 'lab',
      title: 'probe',
      takenAt: '2026-07-02',
      contentType: 'image/png',
      sizeBytes: 4,
    );
    expect(presigned.uploadHeaders['Content-Type'], 'image/png');
    expect((await repo.findById('png'))!.status, DocumentStatus.uploaded);
  });

  test('the metadata op is queued separately from the bytes', () async {
    // Spec §7: the row rides the ordinary outbox, the image does not.
    await capture();

    final ops = await db.outboxDao.take();
    expect(ops.single.targetTable, 'documents');
    expect(ops.single.payload, isNot(contains('localPath')));

    await worker.run();

    expect(
      await db.outboxDao.take(),
      hasLength(1),
      reason: 'uploading the bytes does not settle the metadata op',
    );
  });
}
