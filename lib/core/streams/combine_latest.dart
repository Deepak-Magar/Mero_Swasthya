import 'dart:async';

/// Combines four streams into one that emits whenever any of them emits, once
/// all four have produced a first value.
///
/// Drift gives one stream per query, but several screens are fed by more than
/// one table — S13 reads pregnancies, anc_contacts, deliveries and reminders and
/// must repaint when any of them changes. This is the rxdart `combineLatest4`
/// behaviour, written out so the project does not take a dependency for one
/// function.
///
/// Errors from any source are forwarded. The combined stream closes when every
/// source has closed, and cancelling it cancels all four subscriptions.
Stream<R> combineLatest4<A, B, C, D, R>(
  Stream<A> streamA,
  Stream<B> streamB,
  Stream<C> streamC,
  Stream<D> streamD,
  R Function(A a, B b, C c, D d) combine,
) {
  late final StreamController<R> controller;
  final subscriptions = <StreamSubscription<void>>[];

  late A latestA;
  late B latestB;
  late C latestC;
  late D latestD;
  var hasA = false;
  var hasB = false;
  var hasC = false;
  var hasD = false;
  var openSources = 4;

  void emit() {
    if (hasA && hasB && hasC && hasD) {
      controller.add(combine(latestA, latestB, latestC, latestD));
    }
  }

  void onSourceDone() {
    if (--openSources == 0 && !controller.isClosed) controller.close();
  }

  controller = StreamController<R>(
    onListen: () {
      subscriptions.addAll([
        streamA.listen(
          (value) {
            latestA = value;
            hasA = true;
            emit();
          },
          onError: controller.addError,
          onDone: onSourceDone,
        ),
        streamB.listen(
          (value) {
            latestB = value;
            hasB = true;
            emit();
          },
          onError: controller.addError,
          onDone: onSourceDone,
        ),
        streamC.listen(
          (value) {
            latestC = value;
            hasC = true;
            emit();
          },
          onError: controller.addError,
          onDone: onSourceDone,
        ),
        streamD.listen(
          (value) {
            latestD = value;
            hasD = true;
            emit();
          },
          onError: controller.addError,
          onDone: onSourceDone,
        ),
      ]);
    },
    onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
    },
  );

  return controller.stream;
}

/// Two streams, same contract as [combineLatest4].
///
/// Exists because the local timeline outgrew four sources when Tier 3 added
/// immunisations and growth: the four clinical streams combine into one, the
/// two child-health streams into another, and these two combine again.
Stream<R> combineLatest2<A, B, R>(
  Stream<A> streamA,
  Stream<B> streamB,
  R Function(A a, B b) combine,
) {
  late final StreamController<R> controller;
  final subscriptions = <StreamSubscription<void>>[];

  late A latestA;
  late B latestB;
  var hasA = false;
  var hasB = false;
  var openSources = 2;

  void emit() {
    if (hasA && hasB) controller.add(combine(latestA, latestB));
  }

  void onSourceDone() {
    if (--openSources == 0 && !controller.isClosed) controller.close();
  }

  controller = StreamController<R>(
    onListen: () {
      subscriptions.addAll([
        streamA.listen(
          (value) {
            latestA = value;
            hasA = true;
            emit();
          },
          onError: controller.addError,
          onDone: onSourceDone,
        ),
        streamB.listen(
          (value) {
            latestB = value;
            hasB = true;
            emit();
          },
          onError: controller.addError,
          onDone: onSourceDone,
        ),
      ]);
    },
    onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
    },
  );

  return controller.stream;
}
