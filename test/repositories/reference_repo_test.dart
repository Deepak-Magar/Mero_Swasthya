import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/net/mock_api.dart';
import 'package:mero_swasthya/data/local/app_database.dart';
import 'package:mero_swasthya/data/remote/api/api.dart';
import 'package:mero_swasthya/data/repositories/reference_repo.dart';
import 'package:mero_swasthya/domain/models/enums.dart';

import '../support/transports.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FlakyTransport transport;
  late ReferenceRepo repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    transport = FlakyTransport(MockApi(clock: () => DateTime.utc(2026, 9, 18)));
    repo = ReferenceRepo(db, Api(transport));
  });
  tearDown(() => db.close());

  group('reminders', () {
    test('a refresh fills the cache and the stream reflects it', () async {
      expect(await repo.refreshReminders(MockApi.sitaId), isTrue);

      final reminders = await repo.watchReminders(MockApi.sitaId).first;
      expect(reminders, hasLength(2));
      expect(reminders.first.kind, ReminderKind.ancDue);
    });

    test('going offline leaves the cached list untouched', () async {
      await repo.refreshReminders(MockApi.sitaId);
      transport.offline = true;

      expect(await repo.refreshReminders(MockApi.sitaId), isFalse);
      expect(await repo.watchReminders(MockApi.sitaId).first, hasLength(2));
    });
  });

  group('audit', () {
    test('pages merge rather than replacing', () async {
      await repo.refreshAudit(MockApi.sitaId);
      final before = await repo.watchAudit(MockApi.sitaId).first;

      // Something else happens to the record, then we refresh again.
      final api = Api(transport);
      final grant = await api.grants.create(patientId: MockApi.sitaId);
      await api.grants.redeem(grant.qrPayload);
      await repo.refreshAudit(MockApi.sitaId);

      final after = await repo.watchAudit(MockApi.sitaId).first;
      expect(after.length, greaterThan(before.length));
      expect(
        after.map((e) => e.id).toSet(),
        containsAll(before.map((e) => e.id)),
      );
    });

    test('an offline refresh does not clear the cache', () async {
      // A grant is what puts a row in the audit list in the first place.
      final api = Api(transport);
      final grant = await api.grants.create(patientId: MockApi.sitaId);
      await api.grants.redeem(grant.qrPayload);

      await repo.refreshAudit(MockApi.sitaId);
      expect(await repo.watchAudit(MockApi.sitaId).first, isNotEmpty);

      transport.offline = true;

      expect(await repo.refreshAudit(MockApi.sitaId), isFalse);
      expect(await repo.watchAudit(MockApi.sitaId).first, isNotEmpty);
    });
  });

  group('codelists', () {
    test('the shipped asset seeds the picklists with no network at all',
        () async {
      // Spec §4: the seed copy exists so S21 works before the first sync.
      transport.offline = true;

      await repo.seedFromAssetsIfEmpty();

      final complaints = await repo.watchCodelist(CodeListKind.complaint).first;
      expect(complaints, isNotEmpty);
      expect(complaints.first.labelNp, isNotEmpty);
      expect(
        await repo.watchCodelist(CodeListKind.dangerSign).first,
        isNotEmpty,
        reason: 'the ANC checklist reads danger signs from here',
      );
    });

    test('every kind in the asset parses into the enum', () async {
      // Guards the camelCase wire values in spec A.2 ("dangerSign", not
      // "danger_sign") across the asset, the enum and the database converter.
      await repo.seedFromAssetsIfEmpty();

      for (final kind in CodeListKind.values) {
        expect(
          await repo.watchCodelist(kind).first,
          isNotEmpty,
          reason: 'no seeded items for ${kind.wire}',
        );
      }
    });

    test('seeding twice does not duplicate or undo a refresh', () async {
      await repo.seedFromAssetsIfEmpty();
      final seeded = await db.cacheDao.codelistCount();

      await repo.seedFromAssetsIfEmpty();

      expect(await db.cacheDao.codelistCount(), seeded);
    });

    test('a matching version skips the network entirely', () async {
      await repo.seedFromAssetsIfEmpty();
      final seededVersion =
          await db.syncMetaDao.get(SyncMetaKeys.codelistVersion);
      transport.offline = true;

      expect(
        await repo.refreshCodelistsIfStale(seededVersion!),
        isFalse,
        reason: 'no request is made, so being offline cannot matter',
      );
    });

    test('a newer server version refreshes the cache', () async {
      await repo.seedFromAssetsIfEmpty();

      expect(await repo.refreshCodelistsIfStale('2099-01-01.1'), isTrue);
      expect(
        await db.syncMetaDao.get(SyncMetaKeys.codelistVersion),
        MockApi.configVersion,
      );
    });

    test('a stale version with no network keeps the seeded rows', () async {
      await repo.seedFromAssetsIfEmpty();
      final seeded = await db.cacheDao.codelistCount();
      transport.offline = true;

      expect(await repo.refreshCodelistsIfStale('2099-01-01.1'), isFalse);
      expect(await db.cacheDao.codelistCount(), seeded);
    });

    test('a code can be looked up by kind and code', () async {
      await repo.seedFromAssetsIfEmpty();

      final complaints = await repo.watchCodelist(CodeListKind.complaint).first;
      final item = await repo.findCode(
        CodeListKind.complaint,
        complaints.first.code,
      );
      expect(item?.code, complaints.first.code);
    });
  });

  group('facilities', () {
    test('the shipped asset seeds the referral picker', () async {
      transport.offline = true;

      await repo.seedFacilitiesFromAssetsIfEmpty();

      final facilities = await repo.watchFacilities().first;
      expect(facilities, isNotEmpty);
      expect(await repo.birthingCentres(), isNotEmpty);
    });

    test('nearby falls back to the cache when the request fails', () async {
      await repo.seedFacilitiesFromAssetsIfEmpty();
      transport.offline = true;

      final nearby = await repo.nearbyFacilities(lat: 28.03, lng: 82.49);

      expect(nearby, isNotEmpty, reason: 'a referral must still be possible');
    });

    test('a successful nearby call also refreshes the cache', () async {
      final nearby = await repo.nearbyFacilities(lat: 28.03, lng: 82.49);

      expect(nearby.first.distanceKm, isNotNull);
      expect(await repo.watchFacilities().first, hasLength(nearby.length));
    });
  });
}
