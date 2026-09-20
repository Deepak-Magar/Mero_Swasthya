# Flaky test investigation

## What prompted this

During session 1 a single `flutter test` run reported `+293 -1`. The failing
test name was not captured, and four runs immediately afterwards were clean, so
`docs/DEVICE_RUN_REPORT.md` recorded it as unexplained rather than dismissing it.

## Round 1 — session 2, 306 tests

Ten consecutive full-suite runs after the `/sync/pull` work:

```
for i in $(seq 1 10); do flutter test; done
```

All ten reported `+306: All tests passed!`.

## Round 2 — session 2 (continued), 339 tests

The suite grew by 33 tests after round 1 (the first-pull allergy assertions, the
mock role-persistence tests, the manual-code dialog tests and the reworked
transport-switch test), so the loop was run again against the current suite:

| Run | Result |
|---|---|
| 1 | `+339: All tests passed!` |
| 2 | `+339: All tests passed!` |
| 3 | `+339: All tests passed!` |
| 4 | `+339: All tests passed!` |
| 5 | `+339: All tests passed!` |
| 6 | `+339: All tests passed!` |
| 7 | `+339: All tests passed!` |
| 8 | `+339: All tests passed!` |
| 9 | `+339: All tests passed!` |
| 10 | `+339: All tests passed!` |

**It never failed.** Twenty for twenty across the two rounds, plus the four clean
runs at the end of session 1 — twenty-four consecutive green runs since the one
failure.

## Conclusion

No flaky test was reproduced, and no root cause was found, so nothing was
changed. That is a negative result, not a clean bill of health: one run did fail
and I cannot say why.

The most likely explanation, given what was happening at the time, is
interference rather than a test defect. The failing run was launched in the same
shell invocation as a Python script rewriting a file under `docs/`, and the
suite reads project files (`assets/rules.json`, `assets/codelists.json`) through
`rootBundle`. A concurrent write to the project tree during asset resolution
would produce exactly this shape: one test failing once, never again.

Runs 8–10 of round 2 took 13 s against 8 s for runs 1–7. That is the machine,
not the suite — a release APK build and an `adb` poll were competing for the
same cores. No test changed its result.

## If it comes back

Do this before assuming it is noise:

1. `flutter test --concurrency=1 --reporter expanded` and capture the **name**
   of the failing test — that is the piece that was missing last time.
2. Check whether anything else was writing into the project directory during the
   run (a doc generator, an editor autosave, a `build_runner` watch).
3. Re-run only that test file in a loop:
   `for i in $(seq 1 30); do flutter test test/<file>_test.dart; done`.

The tests most worth suspecting, because they involve real timing rather than
frozen clocks, are:

- `test/sync/sync_engine_test.dart` — "a kick during a cycle is not lost" uses a
  `Completer` gate and `pumpEventQueue`;
- `test/features/widgets_test.dart` — the stepper tests drive real taps;
- anything calling `Rules.loadFromAsset()`, which touches the asset bundle.

## Round 3 — session 4 (Tier 3), 521 tests

The same one-in-many failure appeared again, and was again not captured. During
the Tier 3 packaging loop:

| Run | Result |
|---|---|
| 1 | `+521: All tests passed!` |
| 2 | **`+520 -1: Some tests failed.`** |
| 3–5 | `+521: All tests passed!` |

The failing test name was not printed by the `tail -1` the loop used, which was
the mistake — the loop was rerun capturing full output and the failure did not
recur in **fourteen** consecutive runs afterwards.

Running total since the first sighting in session 1: **one failure in roughly
forty-five full-suite runs**, never reproduced, never identified.

### What is known

- It is not a Tier 3 regression: the same symptom predates Tier 3 by two
  sessions and the suite has roughly tripled since.
- It is a single test, not a cascade — `-1`, never more.
- It has never failed twice in a row, and has never failed in CI-style
  back-to-back loops of ten or more.

### What to do about it

**Capture the name next time.** Any loop that runs the suite repeatedly must
keep the full output of a failing run, not just the last line:

```sh
for i in $(seq 1 10); do
  out=$(flutter test 2>&1)
  echo "$out" | tail -1
  echo "$out" | grep -E '\[E\]' && break
done
```

Until the name is known this cannot be fixed, only watched. It has never
affected a build, a release APK or anything observed on the phone.
