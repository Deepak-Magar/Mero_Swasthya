import 'dart:async';

import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';

/// Where a draft-summary request has got to (S10, spec §11).
///
/// `queued` and `failed` are the server's own `aiSummaryStatus` values (A.2);
/// `requesting` and `timedOut` are the two states only the client can be in —
/// the POST is in flight, or the answer never came.
enum AiSummaryPhase { idle, requesting, queued, done, failed, timedOut }

/// One frame of the state machine, which is what the screen renders.
class AiSummaryState {
  const AiSummaryState(this.phase, {this.summary, this.error});

  const AiSummaryState.idle() : this(AiSummaryPhase.idle);

  final AiSummaryPhase phase;

  /// The bilingual draft, present only in [AiSummaryPhase.done].
  final String? summary;

  /// What went wrong on the POST itself — a network failure, or a `501` from a
  /// backend that has not built this yet. Distinct from `failed`, which means
  /// the job ran and did not produce a summary.
  final Object? error;

  bool get isRunning =>
      phase == AiSummaryPhase.requesting || phase == AiSummaryPhase.queued;

  /// The three ends of the run, all of which offer a retry.
  bool get canRetry =>
      phase == AiSummaryPhase.failed ||
      phase == AiSummaryPhase.timedOut ||
      error != null;

  @override
  String toString() => 'AiSummaryState($phase, summary: $summary, $error)';
}

/// S10's "Draft summary (AI)": POST the request, then poll the document until
/// the job settles.
///
/// A summary is generated somewhere else and arrives whenever it arrives, so
/// there is no response to wait on — only a status to re-read. The loop is
/// written as a plain object with its waiting injected, because the thing worth
/// testing is exactly the sequence of states and the two ways it can stop, and
/// neither should need a real minute to exercise.
class AiSummaryRun {
  AiSummaryRun({
    required this.summarize,
    required this.fetch,
    this.interval = const Duration(seconds: 3),
    this.maxWait = const Duration(seconds: 60),
    Future<void> Function(Duration)? sleep,
    this.onDocument,
  }) : _sleep = sleep ?? _realSleep;

  /// `POST /documents/:id/summarize`.
  final Future<Document> Function() summarize;

  /// `GET /documents/:id`, called once every [interval].
  final Future<Document> Function() fetch;

  /// Spec: poll every three seconds, give up after sixty.
  final Duration interval;
  final Duration maxWait;

  /// Called with every document the run sees, so the caller can cache it. The
  /// summary is worth keeping: it was generated once, and the next person to
  /// open this document may have no signal at all.
  final void Function(Document)? onDocument;

  final Future<void> Function(Duration) _sleep;

  static Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

  /// Emits every state the run passes through and closes when it settles.
  ///
  /// The stream is single-subscription and the caller is expected to cancel it
  /// when the screen goes away; the loop checks for that between polls rather
  /// than carrying on talking to a dead widget.
  Stream<AiSummaryState> start() async* {
    yield const AiSummaryState(AiSummaryPhase.requesting);

    Document document;
    try {
      document = await summarize();
    } on Object catch (error) {
      // A backend that answers 501 lands here, which is the honest thing to
      // show: the feature was offered and the server declined it.
      yield AiSummaryState(AiSummaryPhase.failed, error: error);
      return;
    }

    onDocument?.call(document);
    var state = _fromDocument(document);
    yield state;
    if (!state.isRunning) return;

    // Whole intervals only: a budget of 60 s at 3 s apart is twenty polls, and
    // counting them is easier to reason about than comparing wall clocks in a
    // loop whose waiting is injected.
    final polls = maxWait.inMilliseconds ~/ interval.inMilliseconds;

    for (var i = 0; i < polls; i++) {
      await _sleep(interval);

      try {
        document = await fetch();
      } on Object {
        // One failed poll is not a failed job — the phone moved between cells.
        // Keep waiting; the budget still runs down.
        continue;
      }

      onDocument?.call(document);
      state = _fromDocument(document);
      yield state;
      if (!state.isRunning) return;
    }

    yield const AiSummaryState(AiSummaryPhase.timedOut);
  }

  static AiSummaryState _fromDocument(Document document) {
    return switch (document.aiSummaryStatus) {
      AiSummaryStatus.done => AiSummaryState(
          AiSummaryPhase.done,
          summary: document.aiSummary,
        ),
      AiSummaryStatus.failed => const AiSummaryState(AiSummaryPhase.failed),
      // `none` after a summarize call means the server took the request and has
      // not started yet; treating it as queued keeps the loop running rather
      // than reporting a failure that has not happened.
      AiSummaryStatus.none ||
      AiSummaryStatus.queued =>
        const AiSummaryState(AiSummaryPhase.queued),
    };
  }
}
