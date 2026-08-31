import BlackoutCore
import BlackoutLocation
import DesignSystem
import MapsRouting
import SwiftUI

struct RadarView: View {
    @Bindable var location: LocationService
    var pack: MapPackSnapshot?
    @Bindable var roster: PartyRoster
    var nearbyPeerCount: Int

    var sweepAudio: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            ScreenHeader("Radar", subtitle: "Self-dot plus nearby mesh. Zero peers is success.")
            RadarHUDView(
                headingUp: true,
                headingDegrees: location.headingDegrees,
                peers: roster.radarBlips(selfFix: location.navigationFix),
                sweepAudio: sweepAudio,
                onSelectPeer: { _ in },
                onSelectSelf: {}
            )
            .frame(height: CGFloat(MapChromeLock.radarSelfPoint))
            MeshPill(nearbyCount: nearbyPeerCount)
            if let footnote = roster.selfLabel.footnote {
                Text(footnote)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
            }
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

struct PackFindSheet: View {
    var mode: PackFindMode
    var origin: RoutingCoordinate?
    var pack: MapPackSnapshot?
    var locationDenied: Bool
    var onPick: (PackSearchHit) -> Void

    private var result: (hits: [PackSearchHit], empty: NavigateEmpty?) {
        let bounds = pack.map {
            RoutingBBox(
                west: $0.region.west,
                south: $0.region.south,
                east: $0.region.east,
                north: $0.region.north
            )
        }
        let pois = (pack?.pois ?? []).map {
            RoutingPOI(
                id: $0.id,
                name: $0.name,
                kind: $0.kind,
                coordinate: RoutingCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            )
        }
        return PackFind.query(mode: mode, origin: origin, packBounds: bounds, pois: pois)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title, subtitle: PackFindCopy.subtitle)
                if locationDenied, origin == nil {
                    PermissionDenied(
                        kind: .location,
                        reason: "Range to you needs last-known or a manual pin. Pack points still list when this pack has them. Long-press the map to drop a pin — no waiting on GPS."
                    )
                }
                if let kind = result.empty?.mapKind {
                    MapEmptyCard(kind: kind, fillsSpace: false)
                } else {
                    ForEach(result.hits) { hit in
                        Button {
                            onPick(hit)
                        } label: {
                            HUDPanel {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(hit.title)
                                            .foregroundStyle(BlackoutDS.Silver.bright)
                                        Text(hit.kind.capitalized)
                                            .font(BlackoutDS.captionFont())
                                            .foregroundStyle(BlackoutDS.Silver.dim)
                                    }
                                    Spacer()
                                    Text(distanceCopy(hit.meters))
                                        .font(BlackoutDS.captionFont())
                                        .foregroundStyle(BlackoutDS.Silver.mid)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 80)
        }
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        switch mode {
        case .civilization:
            return PackFindCopy.civilization
        case .water:
            return PackFindCopy.water
        }
    }

    private func distanceCopy(_ meters: Double?) -> String {
        guard let meters else { return "—" }
        return Formatters.distance(meters)
    }
}
