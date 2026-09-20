import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Spec A.5 — the shared rule table, implemented in Dart here and in TypeScript
/// on the server from the same document.
///
/// The app ships `assets/rules.json` and overwrites it from `GET /rules` when
/// the server reports a newer version, so a protocol change is a data change on
/// both sides rather than a release. Everything the triage and schedule
/// functions need comes from here; nothing about ANC is hard-coded in a screen.
class Rules {
  Rules({
    required this.version,
    required this.ancSchedule,
    required this.dangerSigns,
    required this.riskFactors,
  })  : _dangerSignsByCode = {for (final s in dangerSigns) s.code: s},
        _riskFactorsByCode = {for (final f in riskFactors) f.code: f};

  final String version;
  final List<AncScheduleEntry> ancSchedule;
  final List<DangerSignRule> dangerSigns;
  final List<RiskFactorRule> riskFactors;

  final Map<String, DangerSignRule> _dangerSignsByCode;
  final Map<String, RiskFactorRule> _riskFactorsByCode;

  static const String assetPath = 'assets/rules.json';

  factory Rules.fromJson(Map<String, dynamic> json) {
    return Rules(
      version: '${json['version'] ?? ''}',
      ancSchedule: _list(json['ancSchedule'])
          .map(AncScheduleEntry.fromJson)
          .toList(growable: false),
      dangerSigns: _list(json['dangerSigns'])
          .map(DangerSignRule.fromJson)
          .toList(growable: false),
      riskFactors: _list(json['riskFactors'])
          .map(RiskFactorRule.fromJson)
          .toList(growable: false),
    );
  }

  static List<Map<String, dynamic>> _list(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
  }

  /// The copy that ships with the app, so the ANC checklist works on a phone
  /// that has never been online.
  static Future<Rules> loadFromAsset() async {
    return Rules.fromJson(
      jsonDecode(await rootBundle.loadString(assetPath))
          as Map<String, dynamic>,
    );
  }

  /// Returns [other] when the server's table is newer, otherwise this one.
  ///
  /// Versions are date-ordered strings (`2026-09-18.1`), so a plain string
  /// comparison is the right one — and an unparseable or older version is
  /// simply ignored rather than downgrading a working device.
  Rules preferNewer(Rules other) =>
      other.version.compareTo(version) > 0 ? other : this;

  DangerSignRule? dangerSign(String code) => _dangerSignsByCode[code];

  RiskFactorRule? riskFactor(String code) => _riskFactorsByCode[code];

  /// Danger signs the provider ticks in S12, red ones first so the list a
  /// health worker scans starts with what matters.
  List<DangerSignRule> get dangerSignsForChecklist => [
        ...dangerSigns.where((s) => s.level == 'red'),
        ...dangerSigns.where((s) => s.level != 'red'),
      ];

  AncScheduleEntry? contact(int contactNo) {
    for (final entry in ancSchedule) {
      if (entry.contactNo == contactNo) return entry;
    }
    return null;
  }

  /// Spec §12: `TriageResult.reasonsNp = reasons.map(r.translateReason)`.
  ///
  /// A reason with no translation falls back to the English text — a health
  /// worker reading English is better served than one reading a blank.
  String translateReason(String en) =>
      _reasonTranslations[en] ??
      _dangerSignNpByEn[en] ??
      _riskFactorNpByEn[en] ??
      en;

  late final Map<String, String> _dangerSignNpByEn = {
    for (final s in dangerSigns) s.en: s.np,
  };
  late final Map<String, String> _riskFactorNpByEn = {
    for (final f in riskFactors) f.en: f.np,
  };
}

class AncScheduleEntry {
  const AncScheduleEntry({
    required this.contactNo,
    required this.weekTarget,
    this.checklist = const [],
  });

  final int contactNo;
  final int weekTarget;

  /// Field keys S12 renders, e.g. `weight`, `bp`, `hb`, `birthPlan`.
  final List<String> checklist;

  factory AncScheduleEntry.fromJson(Map<String, dynamic> json) =>
      AncScheduleEntry(
        contactNo: (json['contactNo'] as num).toInt(),
        weekTarget: (json['weekTarget'] as num).toInt(),
        checklist: ((json['checklist'] as List?) ?? const [])
            .map((e) => '$e')
            .toList(growable: false),
      );
}

class DangerSignRule {
  const DangerSignRule({
    required this.code,
    required this.level,
    required this.en,
    required this.np,
  });

  final String code;

  /// `red` or `amber` (spec A.5).
  final String level;
  final String en;
  final String np;

  bool get isRed => level == 'red';

  factory DangerSignRule.fromJson(Map<String, dynamic> json) => DangerSignRule(
        code: '${json['code']}',
        level: '${json['level']}',
        en: '${json['en']}',
        np: '${json['np']}',
      );
}

class RiskFactorRule {
  const RiskFactorRule({
    required this.code,
    required this.en,
    required this.np,
  });

  final String code;
  final String en;
  final String np;

  factory RiskFactorRule.fromJson(Map<String, dynamic> json) => RiskFactorRule(
        code: '${json['code']}',
        en: '${json['en']}',
        np: '${json['np']}',
      );
}

/// Nepali for the reasons triage produces itself, as opposed to the ones it
/// copies out of the danger-sign table.
///
/// These live in Dart rather than in `rules.json` because they are generated by
/// the algorithm in spec §12, whose English wording the backend must match word
/// for word — changing one means changing both implementations, not the data.
const Map<String, String> _reasonTranslations = {
  'Severe hypertension (≥160/110)': 'अति उच्च रक्तचाप (≥१६०/११०)',
  'BP ≥ 140/90 with proteinuria or severe headache — possible pre-eclampsia':
      'रक्तचाप ≥ १४०/९० सँगै पिसाबमा प्रोटिन वा कडा टाउको दुखाइ — प्रि-एक्लाम्पसिया हुन सक्छ',
  'Severe anaemia (Hb < 7)': 'गम्भीर रक्तअल्पता (हेमोग्लोबिन ७ भन्दा कम)',
  'Absent fetal movement': 'बच्चा नचल्ने',
  'Raised BP (≥140/90)': 'उच्च रक्तचाप (≥१४०/९०)',
  'Anaemia (Hb 7–9.9)': 'रक्तअल्पता (हेमोग्लोबिन ७–९.९)',
  'Proteinuria': 'पिसाबमा प्रोटिन',
  'Reduced fetal movement': 'बच्चाको चाल कम',
  'High-risk pregnancy (risk factors present)':
      'जोखिमयुक्त गर्भावस्था (जोखिम कारक छन्)',
};
