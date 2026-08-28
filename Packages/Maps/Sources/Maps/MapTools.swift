import BlackoutCore
import BlackoutLocation
import BlackoutMesh
import DesignSystem
import SwiftUI

struct RadarView: View {
    @Bindable var location: LocationService
    @Bindable var mesh: MeshFacade
    var pack: MapPackSnapshot?

    var body: some View {
        VStack(spacing: 20) {
            ScreenHeader("Radar", subtitle: "Self-dot plus nearby mesh. Zero peers is success.")
            ZStack {
                Circle()
                    .stroke(BlackoutDS.Silver.edge.opacity(0.35), lineWidth: 0.5)
                    .frame(width: 260, height: 260)
                Circle()
                    .stroke(BlackoutDS.Silver.edge.opacity(0.2), lineWidth: 0.5)
                    .frame(width: 160, height: 160)
                Circle()
                    .fill(BlackoutDS.Semantic.info)
                    .frame(width: 14, height: 14)
                if mesh.nearbyPeerCount == 0 {
                    VStack {
                        Spacer()
                        Text("0 peers")
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(BlackoutDS.Silver.dim)
                            .padding(.bottom, 28)
                    }
                    .frame(width: 260, height: 260)
                }
            }
            MeshPill(nearbyCount: mesh.nearbyPeerCount)
            if location.authorization == .denied {
                PermissionDenied(
                    kind: .location,
                    reason: "Radar still shows a self-dot from last-known or a manual pin. It will not invent peers."
                )
            }
            Spacer()
        }
        .padding(20)
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
        .navigationTitle("Radar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TopographyView: View {
    @Bindable var location: LocationService
    var packService: FileMapPack

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader("Topography", subtitle: "GPS altitude plus bundled DEM. Generated sample, not USGS.")
                if let fix = location.navigationFix, fix.hasCoordinate {
                    HUDPanel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("GPS altitude: \(fix.altitudeMeters.map { "\(Int($0)) m" } ?? "unavailable")")
                            if let dem = packService.elevationMeters(latitude: fix.latitude!, longitude: fix.longitude!) {
                                Text("Pack DEM: \(Int(dem)) m")
                            } else {
                                Text("Pack DEM: outside sample window")
                                    .foregroundStyle(BlackoutDS.Silver.dim)
                            }
                        }
                    }
                } else if location.authorization == .denied || location.authorization == .restricted {
                    PermissionDenied(
                        kind: .location,
                        reason: "No live GPS altitude. DEM still samples last-known or a manual pin. Drop a pin on the map if you have no fix."
                    )
                } else {
                    Text("No coordinate yet. Drop a manual pin on the map or wait for a last-known fix. DEM stays local.")
                        .font(BlackoutDS.bodyFont())
                        .foregroundStyle(BlackoutDS.Silver.dim)
                }
                if let pack = packService.pack {
                    Text(pack.disclaimer)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.steel)
                }
            }
            .padding(20)
        }
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
        .navigationTitle("Topography")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FindCivilizationView: View {
    @Bindable var location: LocationService
    var pack: MapPackSnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader("Find civilization", subtitle: "Bundled POIs only. No geocoder, no network.")
                if location.authorization == .denied && location.navigationFix?.hasCoordinate != true {
                    PermissionDenied(
                        kind: .location,
                        reason: "Range to you needs last-known or a manual pin. Pack towns still list below. Long-press the map to drop a pin — no waiting on GPS."
                    )
                }
                ForEach(pack?.pois.filter(\.isCivilization) ?? []) { poi in
                    HUDPanel {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(poi.name)
                                Text(poi.kind.capitalized)
                                    .font(BlackoutDS.captionFont())
                                    .foregroundStyle(BlackoutDS.Silver.dim)
                            }
                            Spacer()
                            Text(distance(to: poi))
                                .font(BlackoutDS.captionFont())
                                .foregroundStyle(BlackoutDS.Silver.mid)
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 80)
        }
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
        .navigationTitle("Civilization")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func distance(to poi: MapPOI) -> String {
        guard let from = location.navigationFix, from.hasCoordinate else { return "no fix" }
        let meters = haversine(from.latitude!, from.longitude!, poi.latitude, poi.longitude)
        if meters > 1000 { return String(format: "%.1f km", meters / 1000) }
        return String(format: "%.0f m", meters)
    }
}
