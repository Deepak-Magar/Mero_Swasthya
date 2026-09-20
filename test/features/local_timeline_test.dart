import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/features/timeline/local_timeline.dart';

/// Spec S09: the local union must produce the same `TimelineItem` shape the
/// server returns, so the screen cannot tell whether it is online.
void main() {
  Visit visit({String id = 'v1', String at = '2026-09-10T05:00:00.000Z'}) =>
      Visit(
        id: id,
        patientId: 'p1',
        visitAt: at,
        chiefComplaintCode: 'FEVER',
        vitals: const Vitals(bpSys: 130, bpDia: 85),
        diagnosisCodes: const ['URTI'],
        prescriptions: const [
          Prescription(
            id: 'rx1',
            drugCode: 'PARA500',
            dose: '500mg',
            frequency: PrescriptionFrequency.tds,
            durationDays: 3,
          ),
        ],
      );

  Document document({String id = 'd1', String at = '2026-09-12'}) => Document(
        id: id,
        patientId: 'p1',
        type: DocumentType.lab,
        title: 'CBC',
        takenAt: at,
      );

  AncContact contact({
    int contactNo = 4,
    String? doneAt,
    TriageLevel? triageLevel,
  }) =>
      AncContact(
        id: 'ac$contactNo',
        pregnancyId: 'pg1',
        contactNo: contactNo,
        weekTarget: 30,
        dueAt: '2026-09-15',
        doneAt: doneAt,
        triageLevel: triageLevel,
        findings: const Findings(bpSys: 150, bpDia: 95, hbGdl: 9.2),
      );

  const pregnancy = Pregnancy(
    id: 'pg1',
    patientId: 'p1',
    edd: '2026-11-27',
    updatedAt: '2026-09-01T00:00:00.000Z',
  );

  test('it merges every source, newest first', () {
    final items = buildTimeline(
      [visit()],
      [document()],
      pregnancy,
      [contact(doneAt: '2026-09-14T04:00:00.000Z')],
    );

    expect(items.map((i) => i.kind), [
      TimelineKind.ancContact,
      TimelineKind.document,
      TimelineKind.visit,
      TimelineKind.pregnancyRegistered,
    ]);

    final times = items.map((i) => i.at).toList();
    expect(times, List.of(times)..sort((a, b) => b.compareTo(a)));
  });

  test('an empty record produces an empty timeline', () {
    expect(buildTimeline(const [], const [], null, const []), isEmpty);
  });

  test('contacts that have not happened are left out', () {
    // The other seven are a schedule, not history; showing them would bury the
    // entries that are real.
    final items = buildTimeline(
      const [],
      const [],
      null,
      [contact(contactNo: 1), contact(contactNo: 2, doneAt: '2026-09-14')],
    );

    expect(items, hasLength(1));
    expect(items.single.title, contains('ANC contact 2'));
  });

  test('a visit row carries its vitals and prescription count', () {
    final item = buildTimeline([visit()], const [], null, const []).single;

    expect(item.subtitle, contains('BP 130/85'));
    expect(item.subtitle, contains('URTI'));
    expect(item.subtitle, contains('1 Rx'));
  });

  test('the payload round-trips back into the entity', () {
    // Spec A.2: "the full underlying entity so no second call is needed".
    final item = buildTimeline([visit()], const [], null, const []).single;

    final parsed = Visit.fromJson(item.payload);
    expect(parsed.id, 'v1');
    expect(parsed.prescriptions.single.drugCode, 'PARA500');
    expect(item.refId, 'v1');
  });

  test('a contact row carries its triage level as the badge', () {
    final item = buildTimeline(
      const [],
      const [],
      null,
      [contact(doneAt: '2026-09-14', triageLevel: TriageLevel.red)],
    ).single;

    expect(item.badge, 'red');
    expect(item.title, 'ANC contact 4 (week 30)');
    expect(item.subtitle, contains('BP 150/95'));
    expect(item.subtitle, contains('Hb 9.2'));
  });

  test('badge is only ever a triage level, never an upload state', () {
    // A.2 allows green/amber/red or null. The upload state has its own
    // indicator on S10 and its own row on S17; putting it in this field would
    // add a fourth colour to something the rest of the app reads as clinical
    // severity.
    for (final status in DocumentStatus.values) {
      final item = buildTimeline(
        const [],
        [document().copyWith(status: status)],
        null,
        const [],
      ).single;

      expect(item.badge, isNull, reason: status.wire);
      expect(item.title, 'CBC');
    }
  });

  test('every badge the builder emits is a legal A.2 value', () {
    final items = buildTimeline(
      [visit()],
      [document()],
      pregnancy,
      [contact(doneAt: '2026-09-14', triageLevel: TriageLevel.amber)],
    );

    for (final item in items) {
      expect(item.badge, anyOf(isNull, isIn(['green', 'amber', 'red'])));
    }
  });

  test('a visit title is pre-formatted, not a raw code', () {
    // A.2: "title: Pre-formatted, e.g. 'Visit — Ghorahi HP — E11 Diabetes'".
    final item = buildTimeline(
      [visit().copyWith(facilityName: 'Ghorahi HP')],
      const [],
      null,
      const [],
    ).single;

    expect(item.title, 'Visit — Ghorahi HP — URTI');
  });

  test('a visit with no facility or diagnosis still reads sensibly', () {
    final item = buildTimeline(
      [visit().copyWith(diagnosisCodes: const [])],
      const [],
      null,
      const [],
    ).single;

    expect(item.title, 'Visit — FEVER');
  });
  _mergeTests();
}

/// Spec S09's "replace with the server list" taken literally hides work the
/// device has not pushed yet. Found on the phone: a visit recorded in airplane
/// mode vanished from the timeline, because the in-process mock answered the
/// `/timeline` call even with the radio off and its list did not contain the
/// unsynced row.
void _mergeTests() {
  TimelineItem item(String refId, String at, {String title = 'x'}) =>
      TimelineItem(
        kind: TimelineKind.visit,
        at: at,
        title: title,
        refId: refId,
      );

  group('mergeTimeline', () {
    test('keeps a local row the server has never heard of', () {
      final merged = mergeTimeline(
        server: [item('v_server', '2026-09-10T00:00:00Z')],
        local: [
          item('v_server', '2026-09-10T00:00:00Z'),
          item('v_pending', '2026-09-18T00:00:00Z'),
        ],
      );

      expect(merged.map((i) => i.refId), ['v_pending', 'v_server']);
    });

    test('the server wins for a row both sides have', () {
      final merged = mergeTimeline(
        server: [item('v1', '2026-09-10T00:00:00Z', title: 'Visit — Ghorahi HP')],
        local: [item('v1', '2026-09-10T00:00:00Z', title: 'Visit')],
      );

      expect(merged, hasLength(1));
      expect(
        merged.single.title,
        'Visit — Ghorahi HP',
        reason: 'the server carries facility and diagnosis labels',
      );
    });

    test('the result is newest first across both sources', () {
      final merged = mergeTimeline(
        server: [
          item('a', '2026-09-01T00:00:00Z'),
          item('c', '2026-09-20T00:00:00Z'),
        ],
        local: [item('b', '2026-09-10T00:00:00Z')],
      );

      expect(merged.map((i) => i.refId), ['c', 'b', 'a']);
    });

    test('an empty local list leaves the server list alone', () {
      final server = [item('a', '2026-09-01T00:00:00Z')];

      expect(mergeTimeline(server: server, local: const []), server);
    });
  });
}
