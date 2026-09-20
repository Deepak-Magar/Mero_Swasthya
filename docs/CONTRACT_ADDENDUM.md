# Contract addendum — Tier 3

Everything Tier 3 added to the API contract, in the form the backend developer
needs to implement it.

**The rule this document exists to enforce: every change here is ADDITIVE.**
Nothing in Part A was renamed, removed, retyped or made stricter. A backend that
implements none of this still works with the Tier 1 and Tier 2 app, and an app
that meets a backend which implements none of this behaves exactly as it did
before. Every new field is optional, every new table is new, and every new
enum value is one a client is expected to skip if it does not recognise it.

Contract version this extends: **2026-09-18.1** (Part A, byte-identical in both
spec documents).

Where a shape is shown, it is what goes **inside `data`** — the `{ok, data}`
envelope of A.1 is unchanged.

---

## 1. New syncable table: `immunisations`

One row per scheduled dose on the national EPI schedule. Rows exist from the
moment a child is registered, with `givenAt` null. That is the point: the
question a health worker asks is "what is this child missing", and a schedule
that only records what already happened cannot answer it.

### Entity

| Field | Type | Notes |
|---|---|---|
| `id` | string (uuid v5) | **Deterministic on both sides** — see below |
| `patientId` | string | the child |
| `vaccineCode` | string | `BCG`, `OPV`, `PENTA`, `PCV`, `ROTA`, `FIPV`, `MR`, `JE`, `TCV` |
| `doseNo` | integer | 1-based within the vaccine |
| `dueAt` | string (`YYYY-MM-DD`) | derived from the child's date of birth |
| `givenAt` | string (ISO) \| null | null until somebody gives the dose |
| `givenByUserId` | string \| null | |
| `batchNo` | string \| null | trimmed; empty becomes null |
| `version` | integer | |
| `updatedAt` | string (ISO) | |
| `deleted` | boolean | |

### The deterministic id — the part that must match exactly

```
id = uuidv5(namespace "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
            patientId + ":" + vaccineCode + ":" + doseNo)
```

The same namespace A.8.15 already uses for ANC contacts, and for the same
reason. Both sides generate the schedule from the child's date of birth; if the
ids disagree, a child registered offline ends up with **two of every vaccine**
the moment the server's own schedule arrives.

`doseNo` is formatted as a plain decimal integer with no padding — `"...:MR:2"`,
never `"...:MR:02"`.

**The id does not depend on the date of birth.** Correcting a mistyped birth
date moves every `dueAt` without orphaning a single row.

### Example

```json
{
  "id": "0f3b7f1e-...-uuidv5",
  "patientId": "p_a1a1a1a1-0000-4000-8000-000000000006",
  "vaccineCode": "MR",
  "doseNo": 2,
  "dueAt": "2024-10-14",
  "givenAt": null,
  "givenByUserId": null,
  "batchNo": null,
  "version": 1,
  "updatedAt": "2026-09-19T09:12:03.114Z",
  "deleted": false
}
```

### The schedule itself is not pushed

Like A.8.15's eight ANC contacts, **the app does not enqueue the thirty-odd
placeholder rows it generates**. The server derives the same schedule from the
same date of birth with the same ids. Only a dose that is actually given (or
un-given) is pushed. Thirty empty rows would be thirty ops that say nothing.

The schedule the app generates is in `assets/epi_schedule.json`, with the
week/month offsets per dose and a `verification` block recording what it was
checked against.

**The rows, as of the 2026-09-19 cross-check:**

| Vaccine | Doses | Ages |
|---|---|---|
| BCG | 1 | birth |
| OPV | 3 | 6, 10, 14 weeks |
| Pentavalent | 3 | 6, 10, 14 weeks |
| PCV | 3 | 6, 10 weeks, **9 months** |
| Rotavirus | 2 | 6, 10 weeks |
| **fIPV** | 2 | **14 weeks, 9 months** |
| MR | 2 | 9, 15 months |
| JE | 1 | 12 months (nationwide since July 2016) |
| TCV | 1 | 15 months |

Eighteen doses across **exactly seven visits** — birth, 6, 10, 14 weeks, 9, 12,
15 months — which is the structural check the sources state plainly and which
the app's tests assert.

**fIPV is the row to look at twice.** It is at **14 weeks and 9 months**, not 6
and 14 weeks: Nepal replaced the single full IPV dose introduced at 14 weeks in
2014 with two fractional intradermal doses. The app had this wrong until
2026-09-19 and the correction is recorded in the asset's
`verification.corrections`.

This is **not** a check against the official Ministry of Health and Population /
Family Welfare Division publication, and the asset says so. The backend should
treat the official schedule as the source of truth. If the backend's copy and
the asset ever disagree, the ids will still match (they do not depend on the
dates) but **the due dates will differ, and the app will show a child as overdue
on the wrong day** — so the two copies must be reconciled, not left to drift.

---

## 2. New syncable table: `growth_measurements`

| Field | Type | Notes |
|---|---|---|
| `id` | string (uuid v4) | client-generated, like a Visit |
| `patientId` | string | |
| `measuredAt` | string (ISO) | |
| `weightKg` | number | the only required measurement |
| `heightCm` | number \| null | |
| `muacCm` | number \| null | mid-upper-arm circumference |
| `version` | integer | |
| `updatedAt` | string (ISO) | |
| `deleted` | boolean | |

```json
{
  "id": "0d9c0a1e-2a4b-4c8d-9e1f-3a5b7c9d1e2f",
  "patientId": "p_a1a1a1a1-0000-4000-8000-000000000006",
  "measuredAt": "2026-07-21T04:15:00.000Z",
  "weightKg": 13.1,
  "heightCm": null,
  "muacCm": null,
  "version": 1,
  "updatedAt": "2026-07-21T04:15:00.000Z",
  "deleted": false
}
```

Append-only in practice: a conflict can only happen on an id collision.

### The reference curve is not part of this contract — and should not be re-typed

The app plots these measurements against the **WHO Child Growth Standards**,
weight-for-age z-scores, birth to five years, held client-side in
`assets/who_wfa.json`. Nothing about the band crosses the wire, so the backend
needs to do nothing here.

It is written down anyway because of how this asset got to be right. It started
as a hand-fitted curve that looked plausible and was out by up to **1.7 kg** —
enough to draw a healthy one-year-old below the −2 SD line and a genuinely
underweight two-year-old above it. It is now machine-parsed from WHO's own
published tables, which are kept alongside the parser in `docs/reference/`.

So: if the backend ever grows a z-score or an "underweight" flag of its own,
**take the numbers from WHO's published tables, not from a transcription**, and
keep one copy. This is the same lesson §1 records about the immunisation
schedule, learned twice in the same module.

---

## 3. Both tables in `/sync/push` and `/sync/pull`

**A.8's table whitelist gains two entries.** It becomes:

```
patients, visits, documents, pregnancies, anc_contacts, deliveries,
immunisations, growth_measurements
```

Reminders, audit entries, facilities and codelists remain server-owned and
pull-only.

### Push

Identical to every other table — `{opId, table, op, rowId, baseVersion,
payload}`, `applied` / `duplicate` / `conflict` / `rejected`, `version + 1` on
apply.

```json
{
  "opId": "9c1f...",
  "table": "immunisations",
  "op": "upsert",
  "rowId": "0f3b7f1e-...",
  "baseVersion": 1,
  "payload": { "...": "the entity above" }
}
```

### Pull

`GET /sync/pull` must return both tables for every patient the account can see,
under the same visibility rule as the rest: owned, or an unexpired grant.

```json
{ "table": "immunisations", "row": { "...": "..." } }
{ "table": "growth_measurements", "row": { "...": "..." } }
```

**This is the single easiest thing to get wrong**, and it has already caused one
outage in this project: the bug that opened session 2 was a pull that returned
patients only. A child whose schedule does not come down on the first pull shows
an empty immunisation card on a fresh install.

### New timeline kinds

`GET /patients/:id/timeline` may now emit two more `kind` values:

| kind | `at` | `payload` |
|---|---|---|
| `immunisation` | the dose's `givenAt` | the whole `Immunisation` |
| `growth` | `measuredAt` | the whole `GrowthMeasurement` |

**Only doses that were actually given** belong on the timeline. A scheduled dose
has not happened; the child-health screen is where a plan lives. (The same rule
the existing code already applies to the five pending ANC contacts.)

A client that does not recognise a `kind` skips the row rather than failing the
page, so emitting these against an older app is safe.

### Backend tasks

- Two Prisma models with the field lists above; unique index on `id`.
- The uuid v5 helper, matching the namespace and the `patientId:code:doseNo`
  string byte for byte.
- Schedule generation from `dob` on patient create when the patient is under
  five, and on a correction to `dob`. **Use the table above**, and keep a
  single source of truth rather than a second hand-typed copy — the app had a
  duplicated copy in its mock and that is exactly how the fIPV error survived
  undetected.
- Add both tables to the sync push whitelist and the pull query.
- Two new `kind` values in the timeline serializer.
- Seed **Aarav Chaudhary** — see §7.

---

## 4. `sections` on grants — fine-grained consent

### `POST /grants` request

One **optional** field:

```json
{
  "patientId": "p_...",
  "scope": "read",
  "ttlMinutes": 10,
  "sections": ["summary", "pregnancy"]
}
```

`sections` is a `string[]` drawn from:

```
summary, visits, documents, pregnancy, child, audit
```

**Omitted, or an empty array, means the whole record** — which is what every
grant meant before this existed. The app omits the key entirely when the patient
has not narrowed the share, so a backend that has not implemented this never
sees it.

### The grant entity

`Grant` gains one optional field, `sections: string[]`, echoed on create,
redeem and revoke. A server that never sends it leaves the client with an empty
list, which the client reads as "everything".

### `POST /grants/redeem` — the server filters the bundle

This is the part that matters. **The filtering must happen on the server.**
Consent a client enforces is not consent: a provider with a debugger would still
have the whole record.

| Section | What it controls in the redeem bundle |
|---|---|
| `summary` | the `summary` object |
| `visits` | timeline entries of kind `visit` |
| `documents` | timeline entries of kind `document` |
| `pregnancy` | `pregnancy`, `ancContacts`, and timeline kinds `pregnancy_registered`, `anc_contact`, `delivery` |
| `child` | timeline kinds `immunisation`, `growth` |
| `audit` | reserved — the audit list is a separate endpoint and is not in the bundle today |

**Two rules that are not negotiable:**

1. **The `patient` row always travels, whatever the sections say.** It carries
   `allergies`, and hiding a sulpha allergy because somebody ticked only
   "pregnancy" would be a consent feature that could kill a patient. A summary
   with no name on it is also not a record, it is a puzzle.
2. **A withheld `summary` is sent empty, never null.** A.4 types `summary` as
   required and withholding a section must not change the shape of the
   envelope:

```json
{
  "activeProblems": [],
  "currentMedicines": [],
  "allergies": [],
  "lastVitals": null,
  "activePregnancy": null,
  "lastVisitAt": null,
  "visitCount": 0
}
```

### Backend tasks

- `sections String[]` on the Grant model (Postgres array or a join table).
- Validate against the six values; reject unknown ones with `400
  VALIDATION_ERROR` and `details.sections`.
- Filter the redeem bundle as above, honouring both rules.
- Echo `sections` on every grant response.

---

## 5. `notesText` inside `AncContact.findings`

S13 gained an optional free-text note, dictated or typed.

**It lives inside `findings`, not on `AncContact`.** `AncContact` is pinned by
Part A; `findings` is already a free-form JSON object on both sides, which is
exactly what it is for.

```json
{
  "findings": {
    "weightKg": 58.0,
    "bpSys": 124,
    "bpDia": 80,
    "notesText": "पेट अलि दुखेको भन्नुभयो, आराम गर्न सल्लाह दिइयो।"
  }
}
```

A server that does not know the field round-trips it (if `findings` is stored
as JSON) or drops it (if it is destructured into columns). **Dropping it is
acceptable and loses only the note**; nothing else changes and no triage input
depends on it.

### Backend task

If `findings` is destructured into columns rather than stored as JSON, add a
nullable `notes_text` text column and round-trip it. Otherwise: nothing.

---

## 6. Three new `GET /config` flags

```json
{
  "smsMode": "mock",
  "aiSummaryEnabled": true,
  "otpDemo": true,
  "rulesVersion": "2026-09-18.1",
  "codelistVersion": "2026-09-18.1",

  "nidEnabled": false,
  "hmisExportEnabled": false,
  "councilVerifyEnabled": false
}
```

All three default to **false** and the mock reports false. They exist so the
three Settings rows — National ID verification, HMIS/DHIS2 export, Provider
council verification — can light up the day somebody actually has the API
access, **with no app change**.

Until then the rows say "Not connected — requires government API access",
explain in Nepali and English what the integration would do and what the app
does instead, and the Connect button is disabled. There are no mock success
states anywhere in this feature, deliberately: a green tick for "National ID
verified" would be a lie told to the one audience most likely to check it.

A client reading a config response without these keys gets `false` from its own
defaults, so an older backend is fine.

### Backend task

Three booleans in the config handler, wired to whatever environment variable
eventually carries the real credential.

---

## 7. Mock-only seed data the backend should mirror

The app's mock (`lib/core/net/mock_api.dart`) seeds these so the demo has
something to show. The backend spec §10 seed should match, because the demo
script names them.

**Aarav Chaudhary** — `p_a1a1a1a1-0000-4000-8000-000000000006`, male, owned by
the same account as Sita and Ram, **three years and two months old**. His
schedule is generated from that date of birth and everything up to and including
the 12-month JE was given on time; the **15-month MR booster (dose 2) and the
15-month TCV were not**, so the card has two overdue rows to point at. Three
growth measurements at roughly 18, 9 and 2 months ago (10.4, 11.8, 13.1 kg).

Already seeded in Tier 2 and still required: the three women the health-post
dashboard counts (Gita Tharu, Maya B.K., Parbati Chaudhary), reached through
already-redeemed grants, and Ram's "Bharatpur Hospital discharge sheet".

**One trap.** Seeded rows must carry `updatedAt` = *now*, not a date in the
past. `updatedAt` is the pull cursor, and a phone that has synced before is
already past any past timestamp — a row seeded backwards never reaches an
existing install. This cost real debugging time in Tier 2 when a seeded document
refused to appear.

---

## 8. Summary of every change, for a checklist

| # | Change | Kind | Backend must |
|---|---|---|---|
| 1 | `immunisations` table | new | model, uuid v5 ids, schedule generation, sync |
| 2 | `growth_measurements` table | new | model, sync |
| 3 | sync push/pull whitelist | additive | two entries |
| 4 | timeline kinds `immunisation`, `growth` | additive | serializer |
| 5 | `sections` on `POST /grants` | optional field | store, validate |
| 6 | `sections` on the Grant entity | additive | echo |
| 7 | redeem bundle filtering | new behaviour | filter, keep patient row, empty summary |
| 8 | `findings.notesText` | additive | round-trip, or ignore |
| 9 | `nidEnabled`, `hmisExportEnabled`, `councilVerifyEnabled` | additive | three booleans |
| 10 | Aarav seed | seed | §7 |

Nothing in Part A changed.
