import 'package:uuid/uuid.dart';

/// Id generation.
///
/// Spec A.1: entities the app can create offline use CLIENT-generated UUID v4.
/// Spec A.8.15: AncContacts use deterministic ids on both sides so a pregnancy
/// created offline and its 8 contacts never duplicate the server-generated ones:
///
///   id = uuidv5(namespace "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
///               pregnancyId + ":" + contactNo)
const _uuid = Uuid();

/// The namespace named in spec A.8.15 (the RFC 4122 URL namespace).
const String ancContactNamespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

/// A fresh random id for a row this device is creating.
String newId() => _uuid.v4();

/// Deterministic AncContact id — must match the server byte for byte.
String ancContactId(String pregnancyId, int contactNo) =>
    _uuid.v5(ancContactNamespace, '$pregnancyId:$contactNo');

/// Deterministic id for the pregnancy rebuilt from an offline SWC2 snapshot.
///
/// The snapshot carries the patient's id but not the pregnancy's, and the
/// provider's phone has to land on the same row every time the same person is
/// scanned — otherwise a second scan grows a second pregnancy.
String offlinePregnancyId(String patientId) =>
    _uuid.v5(ancContactNamespace, '$patientId:offline-pregnancy');

/// Deterministic Immunisation id (Tier 3, same rule as A.8.15).
///
///   id = uuidv5(ns, patientId + ":" + vaccineCode + ":" + doseNo)
///
/// The schedule is a pure function of the child's date of birth, so both sides
/// generate the same rows. Without a deterministic id a child registered
/// offline would end up with two of every vaccine the moment the server's own
/// schedule arrived.
String immunisationId(String patientId, String vaccineCode, int doseNo) =>
    _uuid.v5(ancContactNamespace, '$patientId:$vaccineCode:$doseNo');

/// Outbox operation id. Local-only, never leaves the device except as `opId`.
String newOpId() => _uuid.v4();
