/// Straight-line distance, the way `GET /facilities/nearby` computes it (A.4:
/// "Nearest facilities by straight-line distance (Haversine)").
///
/// The app computes it as well as the server, because the map and the referral
/// list have to be right with the network off — which is when somebody is most
/// likely to be reading a paper card by torchlight and deciding where to walk.
library;

import 'dart:math' as math;

import '../models/models.dart';

const double _earthRadiusKm = 6371.0088;

double _radians(double degrees) => degrees * math.pi / 180;

/// Kilometres between two points on the sphere.
double haversineKm({
  required double lat1,
  required double lng1,
  required double lat2,
  required double lng2,
}) {
  final dLat = _radians(lat2 - lat1);
  final dLng = _radians(lng2 - lng1);

  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);

  return _earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// A point on the map, kept deliberately small so the domain does not depend on
/// `latlong2` and can be tested without Flutter.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  String toString() => 'GeoPoint($lat, $lng)';
}

/// [facilities] sorted nearest-first from [origin], each carrying its
/// `distanceKm`.
///
/// Returns a new list; the caller's is untouched. A facility whose coordinates
/// are missing (both zero, which is what the schema defaults to) sorts last
/// rather than appearing to be off the coast of Africa.
List<Facility> facilitiesByDistance(
  List<Facility> facilities,
  GeoPoint origin, {
  bool birthingOnly = false,
  int? limit,
}) {
  final located = <Facility>[];
  final unlocated = <Facility>[];

  for (final facility in facilities) {
    if (birthingOnly && !facility.hasBirthingCentre) continue;

    if (facility.lat == 0 && facility.lng == 0) {
      unlocated.add(facility.copyWith(distanceKm: null));
      continue;
    }

    located.add(
      facility.copyWith(
        distanceKm: haversineKm(
          lat1: origin.lat,
          lng1: origin.lng,
          lat2: facility.lat,
          lng2: facility.lng,
        ),
      ),
    );
  }

  located.sort((a, b) => a.distanceKm!.compareTo(b.distanceKm!));
  final all = [...located, ...unlocated];

  return limit == null || limit >= all.length
      ? all
      : all.sublist(0, limit);
}

/// Where to open the map when the device will not say where it is.
///
/// In order of preference: the middle of the facilities in the patient's own
/// municipality, then the middle of every facility on file. Both beat a
/// hard-coded capital city, which is what an app that guesses usually shows a
/// rural user.
GeoPoint mapCentre(List<Facility> facilities, {String? municipality}) {
  final located =
      facilities.where((f) => f.lat != 0 || f.lng != 0).toList(growable: false);
  if (located.isEmpty) return const GeoPoint(28.0334, 82.4874); // Ghorahi

  final local = municipality == null
      ? const <Facility>[]
      : located
          .where(
            (f) => f.municipality.toLowerCase() == municipality.toLowerCase(),
          )
          .toList(growable: false);

  final of = local.isNotEmpty ? local : located;
  return GeoPoint(
    of.map((f) => f.lat).reduce((a, b) => a + b) / of.length,
    of.map((f) => f.lng).reduce((a, b) => a + b) / of.length,
  );
}

/// "2.4 km" / "800 m" — the two forms anybody actually says out loud.
String formatDistance(double? km) {
  if (km == null) return '';
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(1)} km';
}
