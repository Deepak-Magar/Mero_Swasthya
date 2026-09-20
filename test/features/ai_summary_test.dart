import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/errors/app_error.dart';
import 'package:mero_swasthya/core/net/mock_api.dart';
import 'package:mero_swasthya/data/remote/api/api.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/features/documents/ai_summary.dart';
import 'package:mero_swasthya/features/documents/ai_summary_widgets.dart';

import 'harness.dart';

/// S10's draft summary. The interesting part is the waiting: the work happens
/// on a queue somewhere else, so the app's job is a loop with two ways out and
/// a budget, and all three are worth pinning down.
void main() {
  Document doc(AiSummaryStatus status, {String? summary}) => Document(
        id: 'd1',
        patientId: 'p1',
        type: DocumentType.discharge,
        title: 'Bharatpur Hospital discharge sheet',
        takenAt: '2026-09-06',
        aiSummary: summary,
        aiSummaryStatus: status,
      );

  /// Runs the machine with waiting removed, and records how long it asked to
  /// wait for so the interval is still checked.
  ({AiSummaryRun run, List<Duration> waits}) runner({
    required Future<Document> Function() summarize,
    required Future<Document> Function() fetch,
    Duration interval = const Duration(seconds: 3),
    Duration maxWait = const Duration(seconds: 60),
    void Function(Document)? onDocument,
  }) {
    final waits = <Duration>[];
    return (
      run: AiSummaryRun(
        summarize: summarize,
        fetch: fetch,
        interval: interval,
        maxWait: maxWait,
        onDocument: onDocument,
        sleep: (d) async => waits.add(d),
      ),
      waits: waits,
    );
  }

  group('the polling state machine', () {
    test('queued then done ends with the summary', () async {
      var polls = 0;
      final r = runner(
        summarize: () async => doc(AiSummaryStatus.queued),
        fetch: () async {
          polls++;
          return polls < 3
              ? doc(AiSummaryStatus.queued)
              : doc(AiSummaryStatus.done, summary: 'the draft');
        },
      );

      final states = await r.run.start().toList();

      expect(
        states.map((s) => s.phase).toList(),
        [
          AiSummaryPhase.requesting,
          AiSummaryPhase.queued, // the POST's own answer
          AiSummaryPhase.queued,
          AiSummaryPhase.queued,
          AiSummaryPhase.done,
        ],
      );
      expect(states.last.summary, 'the draft');
      expect(polls, 3, reason: 'it stops polling the moment it is done');
    });

    test('it waits the spec\'s three seconds between polls', () async {
      final r = runner(
        summarize: () async => doc(AiSummaryStatus.queued),
        fetch: () async => doc(AiSummaryStatus.done, summary: 'x'),
      );

      await r.run.start().toList();
      expect(r.waits, [const Duration(seconds: 3)]);
    });

    test('a status of failed stops the loop and offers a retry', () async {
      var polls = 0;
      final r = runner(
        summarize: () async => doc(AiSummaryStatus.queued),
        fetch: () async {
          polls++;
          return doc(AiSummaryStatus.failed);
        },
      );

      final states = await r.run.start().toList();

      expect(states.last.phase, AiSummaryPhase.failed);
      expect(states.last.canRetry, isTrue);
      expect(polls, 1);
    });

    test('it gives up after the sixty-second budget', () async {
      // Twenty polls at three seconds. The point is that it stops: a spinner
      // that never ends is the one outcome the screen must not have.
      final r = runner(
        summarize: () async => doc(AiSummaryStatus.queued),
        fetch: () async => doc(AiSummaryStatus.queued),
      );

      final states = await r.run.start().toList();

      expect(states.last.phase, AiSummaryPhase.timedOut);
      expect(states.last.canRetry, isTrue);
      expect(r.waits, hasLength(20));
    });

    test('a failed POST is reported as an error, not as a queued job', () async {
      const refused = AppError(
        code: AppError.internal,
        message: 'not implemented',
        httpStatus: 501,
      );

      final r = runner(
        summarize: () async => throw refused,
        fetch: () async => doc(AiSummaryStatus.queued),
      );

      final states = await r.run.start().toList();

      expect(states.map((s) => s.phase).toList(),
          [AiSummaryPhase.requesting, AiSummaryPhase.failed]);
      expect(states.last.error, refused);
      expect(r.waits, isEmpty, reason: 'nothing was queued, so nothing to poll');
    });

    test('one failed poll does not end the run', () async {
      // The phone moved between cells. The job is still running.
      var polls = 0;
      final r = runner(
        summarize: () async => doc(AiSummaryStatus.queued),
        fetch: () async {
          polls++;
          if (polls == 1) throw AppError.networkError();
          return doc(AiSummaryStatus.done, summary: 'the draft');
        },
      );

      final states = await r.run.start().toList();

      expect(states.last.phase, AiSummaryPhase.done);
      expect(states.last.summary, 'the draft');
      expect(polls, 2);
    });

    test('a status of none after the POST counts as still queued', () async {
      // A server that accepted the job but has not marked it yet must not be
      // read as a failure.
      final r = runner(
        summarize: () async => doc(AiSummaryStatus.none),
        fetch: () async => doc(AiSummaryStatus.done, summary: 'the draft'),
      );

      final states = await r.run.start().toList();

      expect(states[1].phase, AiSummaryPhase.queued);
      expect(states.last.phase, AiSummaryPhase.done);
    });

    test('every document it sees is handed back for caching', () async {
      final seen = <AiSummaryStatus>[];
      final r = runner(
        summarize: () async => doc(AiSummaryStatus.queued),
        fetch: () async => doc(AiSummaryStatus.done, summary: 'the draft'),
        onDocument: (d) => seen.add(d.aiSummaryStatus),
      );

      await r.run.start().toList();
      expect(seen, [AiSummaryStatus.queued, AiSummaryStatus.done]);
    });

    test('cancelling stops it talking to a screen that has gone', () async {
      var polls = 0;
      final r = runner(
        summarize: () async => doc(AiSummaryStatus.queued),
        fetch: () async {
          polls++;
          return doc(AiSummaryStatus.queued);
        },
      );

      final subscription = r.run.start().listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      final after = polls;
      await Future<void>.delayed(Duration.zero);

      expect(polls, after);
    });
  });

  group('the mock', () {
    late DateTime now;
    late Api api;

    setUp(() {
      now = DateTime.utc(2026, 9, 18, 5);
      api = Api(MockApi(clock: () => now));
    });

    test('reports the feature as available', () async {
      final config = await api.reference.config();
      expect(config.aiSummaryEnabled, isTrue);
    });

    test('summarize answers queued, and the draft appears about four seconds '
        'later', () async {
      final queued = await api.documents.summarize(MockApi.ramDischargeId);
      expect(queued.aiSummaryStatus, AiSummaryStatus.queued);
      expect(queued.aiSummary, isNull);

      // Still working.
      now = now.add(const Duration(seconds: 3));
      final polled = await api.documents.find(MockApi.ramDischargeId);
      expect(polled.aiSummaryStatus, AiSummaryStatus.queued);

      now = now.add(const Duration(seconds: 3));
      final done = await api.documents.find(MockApi.ramDischargeId);
      expect(done.aiSummaryStatus, AiSummaryStatus.done);
      expect(done.aiSummary, isNotNull);
    });

    test('the canned draft is bilingual and names two medicines with doses',
        () async {
      await api.documents.summarize(MockApi.ramDischargeId);
      now = now.add(MockApi.summaryDelay);
      final done = await api.documents.find(MockApi.ramDischargeId);

      final summary = done.aiSummary!;
      expect(summary, contains('Bharatpur Hospital'));
      expect(summary, contains('भरतपुर'));
      expect(summary, contains('Amoxicillin 500 mg'));
      expect(summary, contains('Paracetamol 500 mg'));
      expect(summary, contains('three times a day'));
      expect(summary, contains('एमोक्सिसिलिन'));
    });

    test('the discharge sheet the demo runs on is seeded', () async {
      final document = await api.documents.find(MockApi.ramDischargeId);
      expect(document.title, 'Bharatpur Hospital discharge sheet');
      expect(document.type, DocumentType.discharge);
      expect(document.patientId, MockApi.ramId);
    });
  });

  group('the section', () {
    testWidgets('a draft is shown under the unverified label, in both '
        'languages', (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          AiSummarySection(
            state: const AiSummaryState(
              AiSummaryPhase.done,
              summary: 'Amoxicillin 500 mg - 1 tablet three times a day',
            ),
            onStart: () {},
          ),
        ),
      );
      await settle(tester);

      expect(find.text(aiUnverifiedNp), findsOneWidget);
      expect(find.text(aiUnverifiedEn), findsOneWidget);
      expect(
        find.textContaining('Amoxicillin 500 mg'),
        findsOneWidget,
      );
    });

    testWidgets('a failed run offers a retry', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        wrapForTest(
          AiSummarySection(
            state: const AiSummaryState(AiSummaryPhase.failed),
            onStart: () => retried++,
          ),
        ),
      );
      await settle(tester);

      expect(find.textContaining('could not be made'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
      expect(retried, 1);
    });

    testWidgets('idle offers the button and nothing else', (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          AiSummarySection(
            state: const AiSummaryState.idle(),
            onStart: () {},
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Draft summary (AI)'), findsOneWidget);
      expect(find.text(aiUnverifiedEn), findsNothing);
    });
  });
}
