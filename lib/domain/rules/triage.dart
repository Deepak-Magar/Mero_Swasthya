import '../models/enums.dart';
import '../models/models.dart';
import 'rules.dart';

/// One line of the "why" behind a triage level.
///
/// Carries a code as well as the two translations so the UI can key off
/// something stable, while `AncContact.triageReasons` stores the English text
/// the contract specifies (spec A.2: "Human-readable reasons, from the rule
/// table").
class TriageReason {
  const TriageReason({required this.code, required this.en, required this.np});

  final String code;
  final String en;
  final String np;

  @override
  bool operator ==(Object other) =>
      other is TriageReason && other.code == code && other.en == en;

  @override
  int get hashCode => Object.hash(code, en);

  @override
  String toString() => 'TriageReason($code)';
}

class TriageResult {
  const TriageResult({required this.level, this.reasons = const []});

  final TriageLevel level;
  final List<TriageReason> reasons;

  /// What goes into `AncContact.triageReasons` and onto the wire.
  List<String> get reasonsEn =>
      reasons.map((r) => r.en).toList(growable: false);

  List<String> get reasonsNp =>
      reasons.map((r) => r.np).toList(growable: false);

  bool get isRed => level == TriageLevel.red;
  bool get isAmber => level == TriageLevel.amber;

  /// Spec A.5 `triage.action`: red means refer now.
  bool get needsReferral => isRed;

  @override
  String toString() => 'TriageResult(${level.wire}, ${reasonsEn.join(' | ')})';
}

/// Spec §12 / A.5 — danger-sign triage.
///
/// This function and its TypeScript twin on the server must produce identical
/// output for identical input; the sixteen cases in A.6 are the shared tests.
/// The server recomputes it on every `PUT …/contacts/:no` and, per A.4, **its**
/// answer is the one displayed if the two ever differ.
///
/// The structure follows the spec's listing exactly, including the order reasons
/// are appended, because that order is what a health worker reads first. Red is
/// evaluated fully before amber is considered at all: a pregnancy that is red
/// does not also need to be told it is amber.
TriageResult triage({
  required Findings? findings,
  required List<String> dangerSigns,
  required Pregnancy pregnancy,
  required int gestationalAgeDays,
  required Rules rules,
}) {
  final reasons = <TriageReason>[];
  var red = false;
  var amber = false;

  // 1. Any danger sign the rule table marks red.
  final redSigns =
      dangerSigns.map(rules.dangerSign).nonNulls.where((s) => s.isRed);
  if (redSigns.isNotEmpty) {
    red = true;
    reasons.addAll(redSigns.map(_fromDangerSign));
  }

  if (findings != null) {
    final systolic = findings.bpSys ?? 0;
    final diastolic = findings.bpDia ?? 0;
    final proteinuria = findings.urineProtein?.isProteinuria ?? false;
    // `?? 99` keeps an unmeasured haemoglobin out of both anaemia rules rather
    // than reading it as zero and screaming.
    final haemoglobin = findings.hbGdl ?? 99;

    if (systolic >= 160 || diastolic >= 110) {
      red = true;
      reasons.add(_severeHypertension);
    }

    if ((systolic >= 140 || diastolic >= 90) &&
        (proteinuria || dangerSigns.contains(_severeHeadacheCode))) {
      red = true;
      reasons.add(_preEclampsia);
    }

    if (haemoglobin < 7) {
      red = true;
      reasons.add(_severeAnaemia);
    }

    // Before 20 weeks there is nothing to feel, so absence means nothing.
    if (findings.fetalMovement == FetalMovement.absent &&
        gestationalAgeDays >= _fetalMovementFromDays) {
      red = true;
      reasons.add(_absentFetalMovement);
    }

    if (!red) {
      if (systolic >= 140 || diastolic >= 90) {
        amber = true;
        reasons.add(_raisedBp);
      }
      if (haemoglobin >= 7 && haemoglobin < 10) {
        amber = true;
        reasons.add(_anaemia);
      }
      if (proteinuria) {
        amber = true;
        reasons.add(_proteinuria);
      }
      if (findings.fetalMovement == FetalMovement.reduced) {
        amber = true;
        reasons.add(_reducedFetalMovement);
      }
    }
  }

  if (!red) {
    final amberSigns = dangerSigns
        .map(rules.dangerSign)
        .nonNulls
        .where((s) => !s.isRed);
    if (amberSigns.isNotEmpty) {
      amber = true;
      reasons.addAll(amberSigns.map(_fromDangerSign));
    }

    if (pregnancy.riskLevel == RiskLevel.high) {
      amber = true;
      reasons.add(_highRisk);
    }
  }

  return TriageResult(
    level: red
        ? TriageLevel.red
        : amber
            ? TriageLevel.amber
            : TriageLevel.green,
    reasons: List.unmodifiable(reasons),
  );
}

/// Spec A.5: `riskLevel` is high if any risk factor is present.
RiskLevel riskLevelFor(List<String> riskFactors) =>
    riskFactors.isEmpty ? RiskLevel.normal : RiskLevel.high;

TriageReason _fromDangerSign(DangerSignRule sign) =>
    TriageReason(code: sign.code, en: sign.en, np: sign.np);

/// 20 weeks, the point from which absent movement is a red flag.
const int _fetalMovementFromDays = 140;

const String _severeHeadacheCode = 'SEVERE_HEADACHE_BLURRED_VISION';

const _severeHypertension = TriageReason(
  code: 'SEVERE_HYPERTENSION',
  en: 'Severe hypertension (≥160/110)',
  np: 'अति उच्च रक्तचाप (≥१६०/११०)',
);

const _preEclampsia = TriageReason(
  code: 'PRE_ECLAMPSIA_SUSPECTED',
  en: 'BP ≥ 140/90 with proteinuria or severe headache — possible pre-eclampsia',
  np: 'रक्तचाप ≥ १४०/९० सँगै पिसाबमा प्रोटिन वा कडा टाउको दुखाइ — '
      'प्रि-एक्लाम्पसिया हुन सक्छ',
);

const _severeAnaemia = TriageReason(
  code: 'SEVERE_ANAEMIA',
  en: 'Severe anaemia (Hb < 7)',
  np: 'गम्भीर रक्तअल्पता (हेमोग्लोबिन ७ भन्दा कम)',
);

const _absentFetalMovement = TriageReason(
  code: 'ABSENT_FETAL_MOVEMENT',
  en: 'Absent fetal movement',
  np: 'बच्चा नचल्ने',
);

const _raisedBp = TriageReason(
  code: 'RAISED_BP',
  en: 'Raised BP (≥140/90)',
  np: 'उच्च रक्तचाप (≥१४०/९०)',
);

const _anaemia = TriageReason(
  code: 'ANAEMIA',
  en: 'Anaemia (Hb 7–9.9)',
  np: 'रक्तअल्पता (हेमोग्लोबिन ७–९.९)',
);

const _proteinuria = TriageReason(
  code: 'PROTEINURIA',
  en: 'Proteinuria',
  np: 'पिसाबमा प्रोटिन',
);

const _reducedFetalMovement = TriageReason(
  code: 'REDUCED_FETAL_MOVEMENT_FINDING',
  en: 'Reduced fetal movement',
  np: 'बच्चाको चाल कम',
);

const _highRisk = TriageReason(
  code: 'HIGH_RISK_PREGNANCY',
  en: 'High-risk pregnancy (risk factors present)',
  np: 'जोखिमयुक्त गर्भावस्था (जोखिम कारक छन्)',
);
