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
    @State private var outsidePack = false
    @State private var resetToken = 0
    @State private var storeError: String?

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
                    manualPin: location.manualPin,
                    breadcrumbs: crumbs,
                    onDropPin: { lat, lon in
                        location.dropManualPin(latitude: lat, longitude: lon)
                    },
                    onOutsidePack: { outside in
                        outsidePack = outside
                    },
                    resetToken: resetToken
                )
                .ignoresSafeArea()
                if outsidePack {
                    NoPackCanvas(
                        title: "Outside DefaultPack",
                        detail: "This is the honest no-pack canvas — not a MapKit spinner and not Apple tiles. Pinch/pan back, or return to the bundled region.",
                        location: location,
                        onReturn: { resetToken += 1 }
                    )
                }
            } else {
                NoPackCanvas(
                    title: "No map pack",
                    detail: "DefaultPack is missing from Blackout.app. This canvas is intentional — not a MapKit spinner waiting on WAN.",
                    location: location,
                    onReturn: nil
                )
            }
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        GPSChip(mode: gpsMode)
                        MeshPill(nearbyCount: mesh.nearbyPeerCount)
                        Text("file tiles · no Apple base map")
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(BlackoutDS.Silver.dim)
                    }
                    Spacer()
                    CompassRose(heading: location.headingDegrees)
                }
                .padding(.horizontal, 16)
                .padding(.top, sizeClass == .regular ? 8 : 64)
                if location.authorization == .denied || location.authorization == .restricted {
                    PermissionDenied(
                        kind: .location,
                        reason: "GPS denied. Long-press the map, or drop a pin at pack center, for Navigate, return-to-start, and Find Civilization. PermissionDenied stays; the app will not wait on a fix."
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                if location.manualPin?.hasCoordinate == true, location.lastKnown?.hasCoordinate != true {
                    HStack {
                        GhostButton("Clear pin", height: BlackoutDS.Hit.sm) {
                            location.clearManualPin()
                        }
                    }
                    .padding(.horizontal, 16)
                } else if location.navigationFix?.hasCoordinate != true,
                          location.authorization == .denied || location.authorization == .restricted,
                          let pack = packService.pack {
                    HStack {
                        GhostButton("Drop pin at pack center", height: BlackoutDS.Hit.sm) {
                            location.dropManualPin(
                                latitude: pack.region.centerLatitude,
                                longitude: pack.region.centerLongitude
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
                if let storeError {
                    StoreFailure(storeError)
                        .padding(.horizontal, 16)
                }
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
        .task { reloadCrumbs() }
    }

    private func reloadCrumbs() {
        do {
            let expeditions = try persistence.expeditions()
            if let open = expeditions.first(where: \.isOpen) {
                crumbs = try persistence.breadcrumbs(expeditionID: open.id)
            } else {
                crumbs = []
            }
            storeError = nil
        } catch {
            storeError = error.localizedDescription
        }
    }

    private var gpsMode: GPSChip.Mode {
        if location.lastKnown?.hasCoordinate == true {
            return location.authorization == .authorized ? .live : .lastKnown
        }
        if location.manualPin?.hasCoordinate == true { return .manual }
        switch location.authorization {
        case .denied, .restricted:
            return location.headingDegrees != nil ? .compass : .denied
        case .notDetermined:
            return .none
        case .authorized:
            return location.headingDegrees != nil ? .compass : .none
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
    var title: String
    var detail: String
    @Bindable var location: LocationService
    var onReturn: (() -> Void)?

    var body: some View {
        ZStack {
            BlackoutDS.Surface.void
            VStack(spacing: 16) {
                Image(systemName: "map")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(BlackoutDS.Silver.steel)
                Text(title)
                    .font(BlackoutDS.titleFont())
                    .foregroundStyle(BlackoutDS.Silver.bright)
                Text(detail)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                if let fix = location.navigationFix, fix.hasCoordinate {
                    Text("Anchor \(fix.latitude!.formatted(.number.precision(.fractionLength(4)))), \(fix.longitude!.formatted(.number.precision(.fractionLength(4))))")
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Semantic.info)
                }
                if let onReturn {
                    MetalButton("Return to pack", height: BlackoutDS.Hit.md, action: onReturn)
                        .padding(.horizontal, 32)
                }
                if location.authorization == .denied || location.authorization == .restricted,
                   location.navigationFix?.hasCoordinate != true {
                    Text("Long-press after Return to pack, or use Drop pin at pack center on the Map HUD.")
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.steel)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
        .ignoresSafeArea()
    }
}
