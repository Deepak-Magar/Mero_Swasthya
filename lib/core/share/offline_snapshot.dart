import 'dart:convert';
import 'dart:io';

import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/edd.dart';
import '../ids/ids.dart';

/// SWC2 — a patient's record folded into a QR code, with no server anywhere.
///
/// The SWC1 flow hands over a *token*: a short opaque string the provider's
/// phone trades with the server for the record. That is the right design and it
/// is what production does. It also means that with no server — a health post
/// with no signal, a stage with no laptop, a patient created two minutes ago on
/// somebody's phone — there is nothing to trade the token with and the whole
/// flow stops.
///
/// SWC2 carries the record itself instead: a compact JSON summary, gzipped and
/// base64url'd behind a `SWC2:` prefix. The provider decodes it locally and
/// caches it exactly as if it had redeemed a grant.
///
/// **It is unsigned.** Anyone who can render a QR can render one of these, and
/// the receiving phone has no way to tell a real one from a forgery. That is
/// acceptable for a demo on two phones in one room and is not acceptable in
/// production, where the payload is signed with the server's key and the
/// provider's app verifies the signature before it believes a word of it. See
/// `docs/QR_OFFLINE.md`.
class OfflineSnapshot {
  const OfflineSnapshot({
    required this.patientId,
    required this.name,
    required this.sex,
    required this.dob,
    this.bloodGroup,
    this.allergies = const [],
    this.chronicConditions = const [],
    this.medicines = const [],
    this.lastVitals,
    this.pregnancy,
    required this.generatedAt,
    required this.expiresAt,
  });

  /// The payload prefix. Deliberately not `SWC1:` — a provider's phone has to
  /// be able to tell the two apart before it does anything with either.
  static const String prefix = 'SWC2:';

  /// Bumped if the shape below ever changes. A reader that does not know a
  /// version refuses the code rather than guessing at it.
  static const int formatVersion = 1;

  /// How long a code is good for, at both ends.
  static const Duration ttl = Duration(minutes: 10);

  /// Two phones are never quite on the same second. A minute either way is
  /// generous enough to absorb that and far too short to matter to the ten
  /// minutes the code is alive for.
  static const Duration clockSkew = Duration(seconds: 60);

  /// What a seeded patient should comfortably fit in.
  static const int targetBytes = 900;

  /// Above this the snapshot starts shedding detail rather than producing a QR
  /// too dense for a phone camera to read across a table.
  static const int maxBytes = 1500;

  /// How many medicines survive the first round of trimming.
  static const int trimmedMedicineCount = 5;

  /// The fixed ANC week targets, used to rebuild the schedule on the far side.
  ///
  /// The snapshot carries a contact's number, state and triage but not its week
  /// or due date: both are derivable, and 8 × 20 bytes of dates is a quarter of
  /// the budget. The provider's own rule table is preferred when it has one.
  static const List<int> defaultScheduleWeeks = [12, 20, 26, 30, 34, 36, 38, 40];

  final String patientId;
  final String name;
  final Sex sex;
  final String dob;
  final String? bloodGroup;
  final List<String> allergies;
  final List<String> chronicConditions;
  final List<SnapshotMedicine> medicines;
  final SnapshotVitals? lastVitals;
  final SnapshotPregnancy? pregnancy;
  final DateTime generatedAt;
  final DateTime expiresAt;

  /// True once [expiresAt] is behind [now], allowing for [clockSkew].
  bool isExpired(DateTime now) =>
      now.toUtc().isAfter(expiresAt.toUtc().add(clockSkew));

  Map<String, dynamic> toJson() => {
        'v': formatVersion,
        'id': patientId,
        'name': name,
        'sex': sex.wire,
        'dob': dob,
        if (bloodGroup != null && bloodGroup!.isNotEmpty) 'bg': bloodGroup,
        if (allergies.isNotEmpty) 'al': allergies,
        if (chronicConditions.isNotEmpty) 'cc': chronicConditions,
        if (medicines.isNotEmpty)
          'meds': [for (final m in medicines) m.toJson()],
        if (lastVitals != null) 'lv': lastVitals!.toJson(),
        if (pregnancy != null) 'preg': pregnancy!.toJson(),
        'gen': _iso(generatedAt),
        'exp': _iso(expiresAt),
      };

  static OfflineSnapshot fromJson(Map<String, dynamic> json) {
    final v = json['v'];
    if (v != formatVersion) {
      throw const FormatException('Unsupported snapshot version');
    }
    final gen = DateTime.tryParse('${json['gen']}');
    final exp = DateTime.tryParse('${json['exp']}');
    if (gen == null || exp == null) {
      throw const FormatException('Snapshot has no usable timestamps');
    }

    return OfflineSnapshot(
      patientId: '${json['id']}',
      name: '${json['name']}',
      sex: switch (json['sex']) {
        'male' => Sex.male,
        'other' => Sex.other,
        _ => Sex.female,
      },
      dob: '${json['dob']}',
      bloodGroup: json['bg'] as String?,
      allergies: _strings(json['al']),
      chronicConditions: _strings(json['cc']),
      medicines: [
        for (final m in (json['meds'] as List? ?? const []))
          SnapshotMedicine.fromJson((m as Map).cast<String, dynamic>()),
      ],
      lastVitals: json['lv'] == null
          ? null
          : SnapshotVitals.fromJson(
              (json['lv'] as Map).cast<String, dynamic>()),
      pregnancy: json['preg'] == null
          ? null
          : SnapshotPregnancy.fromJson(
              (json['preg'] as Map).cast<String, dynamic>()),
      generatedAt: gen.toUtc(),
      expiresAt: exp.toUtc(),
    );
  }

  OfflineSnapshot copyWith({
    List<SnapshotMedicine>? medicines,
    SnapshotPregnancy? pregnancy,
  }) =>
      OfflineSnapshot(
        patientId: patientId,
        name: name,
        sex: sex,
        dob: dob,
        bloodGroup: bloodGroup,
        allergies: allergies,
        chronicConditions: chronicConditions,
        medicines: medicines ?? this.medicines,
        lastVitals: lastVitals,
        pregnancy: pregnancy ?? this.pregnancy,
        generatedAt: generatedAt,
        expiresAt: expiresAt,
      );

  static List<String> _strings(Object? value) =>
      [for (final v in (value as List? ?? const [])) '$v'];

  /// Seconds, not milliseconds. Three digits of precision nobody reads cost
  /// eight bytes twice over, and the budget is 900.
  static String _iso(DateTime t) =>
      '${t.toUtc().toIso8601String().split('.').first}Z';
}

/// One prescription, as `{n: name, d: dose, f: frequency, np: instruction}`.
class SnapshotMedicine {
  const SnapshotMedicine({
    required this.name,
    required this.dose,
    required this.frequency,
    this.instructionsNp,
  });

  final String name;
  final String dose;
  final String frequency;
  final String? instructionsNp;

  Map<String, dynamic> toJson() => {
        'n': name,
        'd': dose,
        'f': frequency,
        if (instructionsNp != null && instructionsNp!.isNotEmpty)
          'np': instructionsNp,
      };

  static SnapshotMedicine fromJson(Map<String, dynamic> json) =>
      SnapshotMedicine(
        name: '${json['n']}',
        dose: '${json['d']}',
        frequency: '${json['f']}',
        instructionsNp: json['np'] as String?,
      );

  /// The same medicine with the Nepali instruction dropped — the first thing
  /// shed when a code is too dense to scan across a table.
  SnapshotMedicine get withoutInstruction =>
      SnapshotMedicine(name: name, dose: dose, frequency: frequency);
}

/// The last recorded vitals, as `{sys, dia, pulse, wt, at}`.
class SnapshotVitals {
  const SnapshotVitals({this.sys, this.dia, this.pulse, this.weightKg, this.at});

  final int? sys;
  final int? dia;
  final int? pulse;
  final double? weightKg;
  final String? at;

  bool get isEmpty =>
      sys == null && dia == null && pulse == null && weightKg == null;

  Map<String, dynamic> toJson() => {
        if (sys != null) 'sys': sys,
        if (dia != null) 'dia': dia,
        if (pulse != null) 'pulse': pulse,
        if (weightKg != null) 'wt': weightKg,
        if (at != null) 'at': at,
      };

  static SnapshotVitals fromJson(Map<String, dynamic> json) => SnapshotVitals(
        sys: (json['sys'] as num?)?.toInt(),
        dia: (json['dia'] as num?)?.toInt(),
        pulse: (json['pulse'] as num?)?.toInt(),
        weightKg: (json['wt'] as num?)?.toDouble(),
        at: json['at'] as String?,
      );
}

/// The pregnancy block, as `{edd, wk, risk, contacts, lastTri}`.
class SnapshotPregnancy {
  const SnapshotPregnancy({
    required this.edd,
    required this.week,
    this.risk = 'normal',
    this.contacts = const [],
    this.lastTriage,
  });

  final String edd;
  final int week;
  final String risk;
  final List<SnapshotContact> contacts;
  final String? lastTriage;

  Map<String, dynamic> toJson() => {
        'edd': edd,
        'wk': week,
        if (risk != 'normal') 'risk': risk,
        if (contacts.isNotEmpty)
          'contacts': [for (final c in contacts) c.toJson()],
        if (lastTriage != null) 'lastTri': lastTriage,
      };

  static SnapshotPregnancy fromJson(Map<String, dynamic> json) =>
      SnapshotPregnancy(
        edd: '${json['edd']}',
        week: (json['wk'] as num?)?.toInt() ?? 0,
        risk: '${json['risk'] ?? 'normal'}',
        contacts: [
          for (final c in (json['contacts'] as List? ?? const []))
            SnapshotContact.fromJson((c as Map).cast<String, dynamic>()),
        ],
        lastTriage: json['lastTri'] as String?,
      );

  SnapshotPregnancy get withoutContacts => SnapshotPregnancy(
        edd: edd,
        week: week,
        risk: risk,
        lastTriage: lastTriage,
      );
}

/// One ANC contact, as `{n: number, st: 'd'|'p', tri: 'g'|'a'|'r'}`.
class SnapshotContact {
  const SnapshotContact({required this.no, required this.done, this.triage});

  final int no;
  final bool done;
  final String? triage;

  Map<String, dynamic> toJson() => {
        'n': no,
        'st': done ? 'd' : 'p',
        if (triage != null) 'tri': triage![0],
      };

  static SnapshotContact fromJson(Map<String, dynamic> json) => SnapshotContact(
        no: (json['n'] as num?)?.toInt() ?? 0,
        done: json['st'] == 'd',
        triage: switch (json['tri']) {
          'g' => 'green',
          'a' => 'amber',
          'r' => 'red',
          _ => null,
        },
      );
}

/// The result of encoding: the payload, how big it came out, and what had to be
/// dropped to get there.
class EncodedSnapshot {
  const EncodedSnapshot({
    required this.payload,
    required this.bytes,
    this.trims = const [],
  });

  final String payload;
  final int bytes;

  /// Human-readable notes, one per reduction. The caller logs these; the codec
  /// stays pure so it can be tested without a logger.
  final List<String> trims;
}

/// Build a snapshot from what this device already holds.
OfflineSnapshot buildOfflineSnapshot({
  required Patient patient,
  PatientSummary? summary,
  Pregnancy? pregnancy,
  List<AncContact> contacts = const [],
  required DateTime now,
}) {
  final generatedAt = now.toUtc();
  final vitals = summary?.lastVitals;

  final snapVitals = vitals == null
      ? null
      : SnapshotVitals(
          sys: vitals.bpSys,
          dia: vitals.bpDia,
          weightKg: vitals.weightKg,
          at: vitals.at,
        );

  SnapshotPregnancy? snapPregnancy;
  if (pregnancy != null && pregnancy.status == PregnancyStatus.active) {
    final edd = parseIsoDate(pregnancy.edd);
    final ordered = [...contacts]
      ..sort((a, b) => a.contactNo.compareTo(b.contactNo));
    final lastDone = ordered.where((c) => c.doneAt != null).toList();

    snapPregnancy = SnapshotPregnancy(
      edd: pregnancy.edd,
      week: edd == null ? 0 : _weeksTo(edd, generatedAt),
      risk: pregnancy.riskLevel.wire,
      contacts: [
        for (final c in ordered)
          SnapshotContact(
            no: c.contactNo,
            done: c.doneAt != null,
            triage: c.triageLevel?.wire,
          ),
      ],
      lastTriage: lastDone.isEmpty ? null : lastDone.last.triageLevel?.wire,
    );
  }

  return OfflineSnapshot(
    patientId: patient.id,
    name: patient.name,
    sex: patient.sex,
    dob: patient.dob,
    bloodGroup: patient.bloodGroup,
    allergies: patient.allergies,
    chronicConditions: patient.chronicConditions,
    medicines: [
      for (final rx in summary?.currentMedicines ?? const <Prescription>[])
        SnapshotMedicine(
          name: rx.drugName.isEmpty ? rx.drugCode : rx.drugName,
          dose: rx.dose,
          frequency: rx.frequency.wire,
          instructionsNp: rx.instructionsNp,
        ),
    ],
    lastVitals: snapVitals != null && !snapVitals.isEmpty ? snapVitals : null,
    pregnancy: snapPregnancy,
    generatedAt: generatedAt,
    expiresAt: generatedAt.add(OfflineSnapshot.ttl),
  );
}

/// JSON → gzip → base64url → `SWC2:…`, shedding detail if it comes out too big.
///
/// A QR that is too dense is not a QR: a phone camera reading a phone screen
/// across a desk gives up long before the format's theoretical limit. So this
/// has a budget, and when a record blows it the snapshot loses the parts a
/// provider can ask about out loud — the sixth medicine, then the per-contact
/// detail — rather than producing something nobody can scan.
EncodedSnapshot encodeOfflineSnapshot(OfflineSnapshot snapshot) {
  final trims = <String>[];
  var current = snapshot;
  var payload = _encode(current);

  if (payload.length > OfflineSnapshot.maxBytes &&
      current.medicines.length > OfflineSnapshot.trimmedMedicineCount) {
    final dropped =
        current.medicines.length - OfflineSnapshot.trimmedMedicineCount;
    current = current.copyWith(
      medicines:
          current.medicines.take(OfflineSnapshot.trimmedMedicineCount).toList(),
    );
    payload = _encode(current);
    trims.add('dropped $dropped medicine(s) beyond '
        '${OfflineSnapshot.trimmedMedicineCount}');
  }

  if (payload.length > OfflineSnapshot.maxBytes &&
      (current.pregnancy?.contacts.isNotEmpty ?? false)) {
    final dropped = current.pregnancy!.contacts.length;
    current = current.copyWith(pregnancy: current.pregnancy!.withoutContacts);
    payload = _encode(current);
    trims.add('dropped $dropped ANC contact row(s)');
  }

  if (payload.length > OfflineSnapshot.maxBytes &&
      current.medicines.any((m) => m.instructionsNp != null)) {
    current = current.copyWith(
      medicines: [for (final m in current.medicines) m.withoutInstruction],
    );
    payload = _encode(current);
    trims.add('dropped the Nepali instructions from the medicines');
  }

  return EncodedSnapshot(
    payload: payload,
    bytes: payload.length,
    trims: trims,
  );
}

String _encode(OfflineSnapshot snapshot) {
  final json = jsonEncode(snapshot.toJson());
  final gzipped = gzip.encode(utf8.encode(json));
  // Unpadded: '=' carries no information and a QR charges for every byte.
  final b64 = base64Url.encode(gzipped).replaceAll('=', '');
  return '${OfflineSnapshot.prefix}$b64';
}

/// `SWC2:…` → a snapshot, or a [FormatException] if it is not one.
///
/// Expiry is *not* checked here: the caller decides what to say about a code
/// that decoded perfectly well and is simply too old, and that message is
/// different from "this is not a Swasthya code".
OfflineSnapshot decodeOfflineSnapshot(String payload) {
  if (!payload.startsWith(OfflineSnapshot.prefix)) {
    throw const FormatException('Not an offline snapshot');
  }

  var b64 = payload.substring(OfflineSnapshot.prefix.length);
  // Put back the padding base64Url.decode insists on.
  b64 = b64.padRight((b64.length + 3) ~/ 4 * 4, '=');

  final bytes = base64Url.decode(b64);
  final json = utf8.decode(gzip.decode(bytes));
  final decoded = jsonDecode(json);
  if (decoded is! Map) throw const FormatException('Snapshot is not an object');

  return OfflineSnapshot.fromJson(decoded.cast<String, dynamic>());
}

/// What the provider's screens need, rebuilt from a snapshot.
class OfflineBundle {
  const OfflineBundle({
    required this.patient,
    required this.summary,
    this.pregnancy,
    this.ancContacts = const [],
  });

  final Patient patient;
  final PatientSummary summary;
  final Pregnancy? pregnancy;
  final List<AncContact> ancContacts;
}

/// Rebuild the records S21 draws from a decoded snapshot.
///
/// The ids are deterministic — the patient's own id travels in the code, and
/// the pregnancy and contact ids are derived from it the same way the rest of
/// the app derives them — so a snapshot scanned twice updates one set of rows
/// instead of growing a second.
OfflineBundle bundleFromSnapshot(
  OfflineSnapshot snapshot, {
  List<int> scheduleWeeks = OfflineSnapshot.defaultScheduleWeeks,
}) {
  final patient = Patient(
    id: snapshot.patientId,
    // Not this device's user: the record belongs to whoever shared it, and
    // nothing here should look like a patient this phone owns.
    ownerUserId: '',
    name: snapshot.name,
    sex: snapshot.sex,
    dob: snapshot.dob,
    bloodGroup: snapshot.bloodGroup,
    allergies: snapshot.allergies,
    chronicConditions: snapshot.chronicConditions,
  );

  final summary = PatientSummary(
    allergies: snapshot.allergies,
    activeProblems: [
      for (final code in snapshot.chronicConditions)
        ActiveProblem(code: code, labelEn: code, labelNp: code),
    ],
    currentMedicines: [
      for (final (i, m) in snapshot.medicines.indexed)
        Prescription(
          id: '${snapshot.patientId}:offline-rx-$i',
          drugCode: m.name,
          drugName: m.name,
          dose: m.dose,
          frequency: PrescriptionFrequency.values.firstWhere(
            (f) => f.wire == m.frequency,
            orElse: () => PrescriptionFrequency.od,
          ),
          durationDays: 0,
          instructionsNp: m.instructionsNp,
        ),
    ],
    lastVitals: snapshot.lastVitals == null
        ? null
        : LastVitals(
            bpSys: snapshot.lastVitals!.sys,
            bpDia: snapshot.lastVitals!.dia,
            weightKg: snapshot.lastVitals!.weightKg,
            at: snapshot.lastVitals!.at,
          ),
  );

  final snapPreg = snapshot.pregnancy;
  if (snapPreg == null) {
    return OfflineBundle(patient: patient, summary: summary);
  }

  final pregnancyId = offlinePregnancyId(snapshot.patientId);
  final pregnancy = Pregnancy(
    id: pregnancyId,
    patientId: snapshot.patientId,
    edd: snapPreg.edd,
    riskLevel: snapPreg.risk == 'high' ? RiskLevel.high : RiskLevel.normal,
    gestationalAgeDays: snapPreg.week * 7,
  );

  final edd = parseIsoDate(snapPreg.edd);
  final contacts = <AncContact>[];
  for (final c in snapPreg.contacts) {
    final week = c.no >= 1 && c.no <= scheduleWeeks.length
        ? scheduleWeeks[c.no - 1]
        : 0;
    // The due date is not carried; it is the EDD counted back from week 40,
    // which is how the schedule was built in the first place.
    final due = edd?.subtract(Duration(days: (40 - week) * 7));
    contacts.add(
      AncContact(
        id: ancContactId(pregnancyId, c.no),
        pregnancyId: pregnancyId,
        contactNo: c.no,
        weekTarget: week,
        dueAt: due == null ? snapPreg.edd : toIsoDate(due),
        doneAt: c.done ? toIsoDate(due ?? DateTime.now().toUtc()) : null,
        triageLevel: TriageLevel.fromWire(c.triage),
      ),
    );
  }

  return OfflineBundle(
    patient: patient,
    summary: summary,
    pregnancy: pregnancy,
    ancContacts: contacts,
  );
}

int _weeksTo(DateTime edd, DateTime now) {
  final days = 280 - edd.difference(now).inDays;
  final weeks = days ~/ 7;
  return weeks.clamp(0, 45);
}
