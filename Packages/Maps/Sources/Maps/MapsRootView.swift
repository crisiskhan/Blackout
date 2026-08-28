import BlackoutCore
import BlackoutBattery
import BlackoutLocation
import BlackoutMesh
import DesignSystem
import SwiftUI

public struct MapsRootView: View {
    @Bindable var location: LocationService
    @Bindable var mesh: MeshFacade
    @Bindable var battery: BatteryService
    let persistence: any PersistenceServing
    let packService: FileMapPack
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var tool: MapTool?
    @State private var crumbs: [BreadcrumbRecordDTO] = []

    public init(
        location: LocationService,
        mesh: MeshFacade,
        battery: BatteryService,
        persistence: any PersistenceServing,
        packService: FileMapPack
    ) {
        self.location = location
        self.mesh = mesh
        self.battery = battery
        self.persistence = persistence
        self.packService = packService
    }

    public var body: some View {
        ZStack {
            BlackoutDS.Surface.void.ignoresSafeArea()
            if let pack = packService.pack {
                OfflineMapView(
                    pack: pack,
                    selfFix: location.lastKnown,
                    breadcrumbs: crumbs,
                    pois: pack.pois
                )
                .ignoresSafeArea()
            } else {
                NoPackCanvas(location: location)
            }
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        GPSChip(mode: gpsMode)
                        MeshPill(nearbyCount: mesh.nearbyPeerCount)
                    }
                    Spacer()
                    CompassRose(heading: location.headingDegrees)
                }
                .padding(.horizontal, 16)
                .padding(.top, sizeClass == .regular ? 8 : 64)
                Spacer()
                HStack(spacing: 8) {
                    toolButton("Navigate", tool: .navigate)
                    toolButton("Radar", tool: .radar)
                    toolButton("Topo", tool: .topo)
                    toolButton("Towns", tool: .civilization)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 108)
            }
        }
        .sheet(item: $tool) { item in
            NavigationStack {
                switch item {
                case .navigate:
                    NavigateView(location: location, pack: packService.pack, battery: battery)
                case .radar:
                    RadarView(location: location, mesh: mesh, pack: packService.pack)
                case .topo:
                    TopographyView(location: location, packService: packService)
                case .civilization:
                    FindCivilizationView(location: location, pack: packService.pack)
                }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.medium, .large])
        }
        .task {
            crumbs = loadCrumbs()
        }
    }

    private func loadCrumbs() -> [BreadcrumbRecordDTO] {
        guard let open = try? persistence.expeditions().first(where: \.isOpen) else { return [] }
        return (try? persistence.breadcrumbs(expeditionID: open.id)) ?? []
    }

    private var gpsMode: GPSChip.Mode {
        switch location.authorization {
        case .denied, .restricted:
            if location.lastKnown?.hasCoordinate == true { return .lastKnown }
            if location.headingDegrees != nil { return .compass }
            return .denied
        case .notDetermined:
            if location.lastKnown?.hasCoordinate == true { return .lastKnown }
            return .none
        case .authorized:
            if location.lastKnown?.hasCoordinate == true { return .live }
            if location.headingDegrees != nil { return .compass }
            return .none
        }
    }

    private func toolButton(_ title: String, tool: MapTool) -> some View {
        Button {
            self.tool = tool
        } label: {
            Text(title)
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
                .frame(maxWidth: .infinity)
                .frame(height: BlackoutDS.Hit.sm)
                .background(BlackoutDS.Surface.raised.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

enum MapTool: String, Identifiable {
    case navigate, radar, topo, civilization
    var id: String { rawValue }
}

struct CompassRose: View {
    var heading: Double?

    var body: some View {
        HUDPanel {
            VStack(spacing: 4) {
                Image(systemName: "location.north.line")
                    .font(.system(size: 22, weight: .semibold))
                    .rotationEffect(.degrees(-(heading ?? 0)))
                    .foregroundStyle(BlackoutDS.Silver.metal)
                Text(heading.map { "\(Int($0))°" } ?? "—")
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.mid)
            }
            .frame(width: 56)
        }
    }
}

struct NoPackCanvas: View {
    @Bindable var location: LocationService

    var body: some View {
        ZStack {
            BlackoutDS.Surface.void
            VStack(spacing: 16) {
                Image(systemName: "map")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(BlackoutDS.Silver.steel)
                Text("No map pack")
                    .font(BlackoutDS.titleFont())
                    .foregroundStyle(BlackoutDS.Silver.bright)
                Text("DefaultPack is missing from the bundle. This canvas is intentional — not a MapKit spinner.")
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                if let fix = location.lastKnown, fix.hasCoordinate {
                    Text("Last known \(fix.latitude!.formatted(.number.precision(.fractionLength(4)))), \(fix.longitude!.formatted(.number.precision(.fractionLength(4))))")
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Semantic.info)
                }
            }
        }
        .ignoresSafeArea()
    }
}
