import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/domain/rules/geo.dart';

/// A.4 computes `distanceKm` with Haversine on the server. The app has to reach
/// the same answer with the network off, because "which facility is nearest" is
/// exactly the question somebody asks when there is no signal.
void main() {
  Facility facility(
    String id, {
    required double lat,
    required double lng,
    FacilityType type = FacilityType.healthPost,
    bool birthing = false,
    String municipality = 'Ghorahi',
  }) {
    return Facility(
      id: id,
      name: 'Facility $id',
      type: type,
      hasBirthingCentre: birthing,
      lat: lat,
      lng: lng,
      municipality: municipality,
    );
  }

  group('haversineKm', () {
    test('a point is zero from itself', () {
      expect(
        haversineKm(lat1: 28.03, lng1: 82.49, lat2: 28.03, lng2: 82.49),
        0,
      );
    });

    test('one degree of latitude is about 111 km', () {
      final km = haversineKm(lat1: 28, lng1: 82.49, lat2: 29, lng2: 82.49);
      expect(km, closeTo(111.2, 0.5));
    });

    test('Ghorahi to Tulsipur is about 22 km', () {
      // The two seeded municipalities, which is the distance the demo shows.
      final km = haversineKm(
        lat1: 28.0334,
        lng1: 82.4874,
        lat2: 28.13,
        lng2: 82.297,
      );
      expect(km, closeTo(22, 2));
    });

    test('it is symmetric', () {
      final there =
          haversineKm(lat1: 28.03, lng1: 82.49, lat2: 27.87, lng2: 82.54);
      final back =
          haversineKm(lat1: 27.87, lng1: 82.54, lat2: 28.03, lng2: 82.49);
      expect(there, closeTo(back, 1e-9));
    });
  });

  group('facilitiesByDistance', () {
    // Ghorahi, then Lamahi (~19 km south), then Tulsipur (~22 km north-west) —
    // the real seeded geography, so the ordering under test is the ordering the
    // demo shows.
    final near = facility('near', lat: 28.04, lng: 82.49);
    final lamahi = facility('lamahi', lat: 27.87, lng: 82.543, birthing: true);
    final tulsipur =
        facility('tulsipur', lat: 28.13, lng: 82.297, birthing: true);
    const origin = GeoPoint(28.0334, 82.4874);

    test('sorts nearest first and stamps each one with its distance', () {
      final sorted = facilitiesByDistance([tulsipur, near, lamahi], origin);

      expect(sorted.map((f) => f.id).toList(), ['near', 'lamahi', 'tulsipur']);
      expect(sorted.first.distanceKm, lessThan(sorted[1].distanceKm!));
      expect(sorted[1].distanceKm, lessThan(sorted.last.distanceKm!));
      expect(sorted.first.distanceKm, closeTo(0.7, 0.5));
    });

    test('leaves the caller\'s list alone', () {
      final input = [tulsipur, near, lamahi];
      facilitiesByDistance(input, origin);

      expect(input.map((f) => f.id).toList(), ['tulsipur', 'near', 'lamahi']);
      expect(input.first.distanceKm, isNull);
    });

    test('birthingOnly drops the rest', () {
      final sorted = facilitiesByDistance(
        [tulsipur, near, lamahi],
        origin,
        birthingOnly: true,
      );

      expect(sorted.map((f) => f.id).toList(), ['lamahi', 'tulsipur']);
    });

    test('limit takes the nearest n', () {
      final sorted =
          facilitiesByDistance([tulsipur, near, lamahi], origin, limit: 2);

      expect(sorted.map((f) => f.id).toList(), ['near', 'lamahi']);
      expect(
        facilitiesByDistance([tulsipur, near], origin, limit: 9),
        hasLength(2),
        reason: 'a limit larger than the list is not an error',
      );
    });

    test('a facility with no coordinates sorts last rather than off Africa',
        () {
      // 0,0 is the schema default. Treating it as a real point puts an
      // un-geocoded health post in the Gulf of Guinea, 6000 km away, which is
      // wrong in a way that looks plausible.
      final unlocated = facility('unknown', lat: 0, lng: 0);
      final sorted = facilitiesByDistance([unlocated, lamahi, near], origin);

      expect(sorted.map((f) => f.id).toList(), ['near', 'lamahi', 'unknown']);
      expect(sorted.last.distanceKm, isNull);
    });

    test('an empty list stays empty', () {
      expect(facilitiesByDistance(const [], origin), isEmpty);
    });
  });

  group('mapCentre', () {
    final ghorahi = facility('g', lat: 28.0334, lng: 82.4874);
    final tulsipur =
        facility('t', lat: 28.13, lng: 82.297, municipality: 'Tulsipur');

    test('prefers the patient\'s own municipality', () {
      final centre =
          mapCentre([ghorahi, tulsipur], municipality: 'Tulsipur');

      expect(centre.lat, closeTo(28.13, 1e-9));
      expect(centre.lng, closeTo(82.297, 1e-9));
    });

    test('matches the municipality case-insensitively', () {
      final centre = mapCentre([ghorahi, tulsipur], municipality: 'tulsipur');
      expect(centre.lat, closeTo(28.13, 1e-9));
    });

    test('falls back to the middle of everything it knows', () {
      final centre = mapCentre([ghorahi, tulsipur], municipality: 'Kathmandu');

      expect(centre.lat, closeTo((28.0334 + 28.13) / 2, 1e-9));
    });

    test('an empty list still gives somewhere in the district', () {
      final centre = mapCentre(const []);
      expect(centre.lat, closeTo(28.03, 0.1));
      expect(centre.lng, closeTo(82.49, 0.1));
    });

    test('facilities with no coordinates do not drag the centre to 0,0', () {
      final centre = mapCentre([ghorahi, facility('x', lat: 0, lng: 0)]);
      expect(centre.lat, closeTo(28.0334, 1e-9));
    });
  });

  group('formatDistance', () {
    test('under a kilometre reads in metres', () {
      expect(formatDistance(0.4), '400 m');
      expect(formatDistance(0.05), '50 m');
    });

    test('a kilometre or more reads in kilometres, one decimal', () {
      expect(formatDistance(2.44), '2.4 km');
      expect(formatDistance(22.0), '22.0 km');
    });

    test('an unknown distance says nothing at all', () {
      expect(formatDistance(null), '');
    });
  });
}
