import '../../domain/models/models.dart';

/// Builds the `payload` of a `/sync/push` change (spec A.4).
///
/// The contract says the payload is `<Entity fields as in POST …> + patientId`,
/// so three groups of keys are stripped from the model's JSON:
///
///  * `version` and `updatedAt` — assigned by the server, and echoing a stale
///    pair back would look like an edit;
///  * `deleted` — the op itself (`upsert` vs `delete`) carries that intent;
///  * server-computed reads — `gestationalAgeDays` and `nextContact` on
///    [Pregnancy] are derived per request and are not columns anywhere.
///
/// Nulls are kept: clearing a field offline has to survive the round trip.

const Set<String> _serverOwned = {'version', 'updatedAt', 'deleted'};

Map<String, dynamic> _payload(
  Map<String, dynamic> json, {
  Set<String> also = const {},
}) {
  return {
    for (final entry in json.entries)
      if (!_serverOwned.contains(entry.key) && !also.contains(entry.key))
        entry.key: entry.value,
  };
}

extension PatientSyncPayload on Patient {
  Map<String, dynamic> toSyncJson() => _payload(toJson());
}

extension VisitSyncPayload on Visit {
  Map<String, dynamic> toSyncJson() => _payload(toJson());
}

extension DocumentSyncPayload on Document {
  Map<String, dynamic> toSyncJson() => _payload(toJson());
}

extension PregnancySyncPayload on Pregnancy {
  Map<String, dynamic> toSyncJson() =>
      _payload(toJson(), also: const {'gestationalAgeDays', 'nextContact'});
}

extension AncContactSyncPayload on AncContact {
  Map<String, dynamic> toSyncJson() => _payload(toJson());
}

extension DeliverySyncPayload on Delivery {
  Map<String, dynamic> toSyncJson() => _payload(toJson());
}

// Tier 3, additive (docs/CONTRACT_ADDENDUM.md).

extension ImmunisationSyncPayload on Immunisation {
  Map<String, dynamic> toSyncJson() => _payload(toJson());
}

extension GrowthMeasurementSyncPayload on GrowthMeasurement {
  Map<String, dynamic> toSyncJson() => _payload(toJson());
}
