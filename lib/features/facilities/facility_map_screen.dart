import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/geo.dart';
import '../../shared/widgets/soft_card.dart';
import '../shared/widgets/app_widgets.dart';

/// Tier 2 — the nearest-facility map behind S13's referral and S12's birth
/// plan.
///
/// Two rules shape this screen. The markers come from the local database, which
/// is seeded from `assets/facilities.json`, so **the screen is never blank**:
/// losing the network costs you the street tiles underneath, not the answer to
/// "where is the nearest birthing centre". And the centre is derived from the
/// patient's own municipality rather than from a device fix, because this build
/// asks for no location permission at all — an app that demands GPS to show a
/// list of four health posts has mistaken what it is for.
class FacilityMapScreen extends ConsumerStatefulWidget {
  const FacilityMapScreen({
    super.key,
    this.patientId,
    this.birthingOnly = false,
    this.picking = false,
  });

  /// Used only to find the patient's municipality, which is where the map
  /// opens.
  final String? patientId;

  /// S12's birth plan and S13's red/amber referral both want a place that can
  /// actually deliver a baby.
  final bool birthingOnly;

  /// When true the sheet offers "Choose this facility" and pops it back to the
  /// caller, which is how the birth plan and the referral pick one.
  final bool picking;

  @override
  ConsumerState<FacilityMapScreen> createState() => _FacilityMapScreenState();
}

class _FacilityMapScreenState extends ConsumerState<FacilityMapScreen> {
  final _map = MapController();
  Facility? _selected;

  void _focus(Facility facility, GeoPoint centre) {
    setState(() => _selected = facility);
    _map.move(LatLng(facility.lat, facility.lng), 13);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final online = ref.watch(syncStatusProvider).valueOrNull?.online ?? true;
    final all = ref.watch(facilitiesProvider).valueOrNull ?? const <Facility>[];
    final patient = widget.patientId == null
        ? null
        : ref.watch(patientProvider(widget.patientId!)).valueOrNull;

    final centre = mapCentre(all, municipality: patient?.municipality);
    final nearest = facilitiesByDistance(
      all,
      centre,
      birthingOnly: widget.birthingOnly,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.facilityMapTitle),
        actions: const [SyncPill.compact()],
      ),
      body: Column(
        children: [
          if (!online)
            Material(
              color: TriageColors.amberBg,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.layers_clear_outlined,
                        size: 18, color: TriageColors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.facilityMapNoTiles,
                        style: const TextStyle(
                          color: TriageColors.amber,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            flex: 3,
            child: _Map(
              controller: _map,
              centre: centre,
              facilities: nearest,
              selected: _selected,
              online: online,
              onTapMarker: (facility) => _focus(facility, centre),
            ),
          ),
          Expanded(
            flex: 2,
            child: nearest.isEmpty
                ? EmptyState(
                    icon: Icons.location_off_outlined,
                    title: l10n.commonNotSet,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: nearest.length,
                    itemBuilder: (context, index) => _FacilityTile(
                      facility: nearest[index],
                      selected: nearest[index].id == _selected?.id,
                      picking: widget.picking,
                      onTap: () => _focus(nearest[index], centre),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The map itself.
///
/// Offline it drops the tile layer and keeps everything else. A blank grey
/// rectangle with no markers would be the worst of both worlds — it looks
/// broken *and* it withholds the four facts the screen exists to give.
class _Map extends StatelessWidget {
  const _Map({
    required this.controller,
    required this.centre,
    required this.facilities,
    required this.selected,
    required this.online,
    required this.onTapMarker,
  });

  final MapController controller;
  final GeoPoint centre;
  final List<Facility> facilities;
  final Facility? selected;
  final bool online;
  final ValueChanged<Facility> onTapMarker;

  /// Bounds around the centre marker and every facility, with enough padding
  /// that a pin at the edge is not half off the screen.
  ///
  /// Null when there is nothing to frame — `initialCenter` then stands.
  CameraFit? _fit(GeoPoint centre, List<Facility> facilities) {
    final points = [
      LatLng(centre.lat, centre.lng),
      for (final f in facilities)
        if (f.lat != 0 || f.lng != 0) LatLng(f.lat, f.lng),
    ];
    if (points.length < 2) return null;

    return CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: const EdgeInsets.all(56),
      maxZoom: 14,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: FlutterMap(
        mapController: controller,
        options: MapOptions(
          // Frame every facility rather than picking a zoom and hoping. The
          // screen is called "nearest facilities"; opening it with two of the
          // four outside the viewport makes a reachable birthing centre look
          // like it does not exist.
          initialCenter: LatLng(centre.lat, centre.lng),
          initialZoom: 11,
          initialCameraFit: _fit(centre, facilities),
          minZoom: 6,
          maxZoom: 17,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
        ),
        children: [
          if (online)
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.meroswasthya.app',
              // Nothing is cached to disk: the offline path is the markers, not
              // a stale basemap, and a tile cache is a surprising amount of
              // somebody's phone storage to spend without asking.
              retinaMode: false,
            ),
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(centre.lat, centre.lng),
                width: 28,
                height: 28,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary.withValues(alpha: 0.25),
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                ),
              ),
              for (final facility in facilities)
                Marker(
                  point: LatLng(facility.lat, facility.lng),
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: () => onTapMarker(facility),
                    child: Icon(
                      facilityIcon(facility),
                      size: facility.id == selected?.id ? 40 : 32,
                      color: facility.hasBirthingCentre
                          ? AppColors.triageRed
                          : AppColors.brandOf(context),
                      shadows: [
                        Shadow(blurRadius: 4, color: AppColors.markerShadow),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FacilityTile extends StatelessWidget {
  const _FacilityTile({
    required this.facility,
    required this.selected,
    required this.picking,
    required this.onTap,
  });

  final Facility facility;
  final bool selected;
  final bool picking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final phone = facility.phone;

    return SoftCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      // The chosen facility gets the brand edge rather than a border all round:
      // one card in the list is the answer, and the edge is what says which.
      accent: selected ? AppColors.brandOf(context) : null,
      padding: EdgeInsets.fromLTRB(
        selected ? AppSpacing.md : AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
          children: [
            Icon(
              facilityIcon(facility),
              size: 20,
              color: AppColors.textSecondaryOf(context),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      facility.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        facilityTypeLabel(l10n, facility.type),
                        formatDistance(facility.distanceKm),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            if (picking)
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(facility),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(l10n.facilityMapChoose),
              )
            else if (phone != null && phone.isNotEmpty)
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                icon: Icon(Icons.call_rounded, size: 18),
                label: Text(l10n.ancCall),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.dangerInkOf(context),
                ),
              ),
          ],
      ),
    );
  }
}

IconData facilityIcon(Facility facility) => switch (facility.type) {
      FacilityType.hospital => Icons.local_hospital_outlined,
      FacilityType.phcc => Icons.medical_services_outlined,
      FacilityType.birthingCentre => Icons.child_friendly_outlined,
      FacilityType.healthPost => Icons.health_and_safety_outlined,
    };

String facilityTypeLabel(L l10n, FacilityType type) => switch (type) {
      FacilityType.healthPost => l10n.facilityTypeHealthPost,
      FacilityType.phcc => l10n.facilityTypePhcc,
      FacilityType.hospital => l10n.facilityTypeHospital,
      FacilityType.birthingCentre => l10n.facilityTypeBirthingCentre,
    };
