import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the database file lives on the device.
const String databaseFileName = 'mero_swasthya.sqlite';

/// Opens the app database lazily, on a background isolate.
///
/// No `applyWorkaroundToOpenSqlite3OnOldAndroidVersions()` call: `sqlite3` 3.x
/// bundles the native library itself, which is why `sqlite3_flutter_libs` is
/// pinned at its no-op 0.6.0+eol release.
///
/// Spec §6.1 asks for SQLCipher with a PBKDF2-derived key. Session 1 ships the
/// plain build — the spec explicitly allows that fallback — so this is the
/// single call site that has to change later: swap
/// [NativeDatabase.createInBackground] for the SQLCipher factory and pass
/// `KeyDerivation.deriveDbKeyHex(pin, salt)` as `PRAGMA key`. The derivation
/// itself already exists in core/crypto/key_derivation.dart.
QueryExecutor openAppDatabase() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, databaseFileName));
    return NativeDatabase.createInBackground(file);
  });
}
