import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/net/mock_api.dart';
import 'package:mero_swasthya/data/remote/api/api.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/domain/rules/provider_dashboard.dart';

/// The three extra women the mock seeds for the Tier-2 dashboard.
///
/// Mock-only data, but the demo depends on it: every tile has to have somebody
/// in it, and none of the numbers may look like a bug.
void main() {
  test('the seeded health post fills every dashboard tile', () async {
    final now = DateTime.utc(2026, 9, 19, 10);
    final api = Api(MockApi(clock: () => now));

    // Everything the device would hold after a first sync.
    final pulled = await api.sync.pull(since: '', deviceId: 'dev1');

    final patients = <Patient>[];
    final pregnancies = <Pregnancy>[];
    final contacts = <AncContact>[];
    final deliveries = <Delivery>[];

    for (final change in pulled.changes) {
      switch (change.table) {
        case 'patients':
          patients.add(Patient.fromJson(change.row));
        case 'pregnancies':
          pregnancies.add(Pregnancy.fromJson(change.row));
        case 'anc_contacts':
          contacts.add(AncContact.fromJson(change.row));
        case 'deliveries':
          deliveries.add(Delivery.fromJson(change.row));
      }
    }

    expect(
      patients.map((p) => p.name),
      containsAll(['Gita Tharu', 'Maya B.K.', 'Parbati Chaudhary']),
      reason: 'the pull has to carry patients reached through a grant',
    );

    final board = buildProviderDashboard(
      patients: patients,
      pregnancies: pregnancies,
      contacts: contacts,
      deliveries: deliveries,
      now: now,
      monthStart: DateTime.utc(2026, 9, 1),
      monthEnd: DateTime.utc(2026, 9, 30, 23, 59, 59),
    );

    expect(board.count(DashboardBucket.trimester1), 1);
    expect(board.count(DashboardBucket.trimester2), 1);
    // Sita is at week 30 and Maya at 37.
    expect(board.count(DashboardBucket.trimester3), 2);

    // Exactly one woman has been missed. Six or eight would read as a bug.
    expect(board.count(DashboardBucket.overdueContacts), 1);
    expect(
      board.of(DashboardBucket.overdueContacts).single.patient.name,
      'Parbati Chaudhary',
    );

    final flagged = board.of(DashboardBucket.recentTriage);
    expect(flagged, hasLength(1));
    expect(flagged.single.contact!.triageLevel, TriageLevel.amber);
  });
}
