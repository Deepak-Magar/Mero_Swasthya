/// The complications a delivery is recorded with (spec S14).
///
/// A.2 types `Delivery.complications` as `string[]` — "free text items" — so
/// nothing in the contract names these. They are still a fixed list here rather
/// than a text field, because the person filling this in is often standing in a
/// birthing room at 3 a.m. and because "PPH", "pph" and "bleeding after birth"
/// are the same event that nobody will ever be able to count.
///
/// The codes are what travels, and they are deliberately not a `CodeListKind`:
/// adding one would change a Part A enum, and the contract says free text. A
/// backend that later grows a `complication` codelist can adopt these codes
/// unchanged.
library;

/// The codes offered as chips, in the order a birth attendant would meet them.
const List<String> deliveryComplicationCodes = [
  'PROLONGED_LABOUR',
  'OBSTRUCTED_LABOUR',
  'PPH',
  'RETAINED_PLACENTA',
  'PERINEAL_TEAR',
  'ECLAMPSIA',
  'SEPSIS',
  'CORD_PROLAPSE',
];

/// True when [code] is one this app offers, as opposed to one that arrived from
/// a server or an older build.
///
/// The UI keeps unknown codes visible rather than dropping them: a value this
/// version does not recognise is still something a clinician wrote down.
bool isKnownComplication(String code) =>
    deliveryComplicationCodes.contains(code);
