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
    var coverageRegions: [MapRegion]
    var onOpenFieldPacks: (() -> Void)?
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var tool: MapTool?
    @State private var crumbs: [BreadcrumbRecordDTO] = []
    @State private var outsidePack = false
    @State private var resetToken = 0
    @State private var centerToken = 0
    @State private var storeError: String?
    @State private var radarOn = true
    @State private var headingUp = UserDefaults.standard.bool(forKey: BlackoutKeys.radarHeadingUp)
    @State private var sweepAudio = UserDefaults.standard.bool(forKey: BlackoutKeys.radarSweepAudio)
    @State private var showViewshed = UserDefaults.standard.bool(forKey: BlackoutKeys.mapViewshed)
    @State private var showSlope = UserDefaults.standard.bool(forKey: BlackoutKeys.mapSlope)
    @State private var selectedPeer: RadarBlip?
    @State private var showLiDAR = false
    @State private var viewshedRays: [ViewshedRay] = []
    @State private var slopeSamples: [SlopeSample] = []
    @State private var pinnedToPackCoverage = false
    @State private var packPaintLog = ""

    public init(
        location: LocationService,
        mesh: MeshFacade,
        battery: BatteryService,
        persistence: any PersistenceServing,
        packService: FileMapPack,
        coverageRegions: [MapRegion] = [],
        onOpenFieldPacks: (() -> Void)? = nil
    ) {
        self.location = location
        self.mesh = mesh
        self.battery = battery
        self.persistence = persistence
        self.packService = packService
        self.coverageRegions = coverageRegions
        self.onOpenFieldPacks = onOpenFieldPacks
    }

    private var sosOnly: Bool { battery.isCritical }
    private var extremeSaver: Bool { battery.isExtremeSaver }
    private var radarVisible: Bool {
        if sosOnly { return false }
        if extremeSaver { return true }
        return radarOn
    }
    private var extrasOn: Bool { !sosOnly && !extremeSaver }
    private var peers: [RadarBlip] { [] }
    private var locationOutsideCoverage: Bool {
        guard let fix = location.navigationFix, fix.hasCoordinate else { return false }
        let regions = coverageRegions.isEmpty ? [packService.pack?.region].compactMap { $0 } : coverageRegions
        return !regions.contains { $0.contains(latitude: fix.latitude!, longitude: fix.longitude!, padFraction: 0.08) }
    }
    private var showLocationEmptyState: Bool {
        packService.pack != nil && (outsidePack || (locationOutsideCoverage && !pinnedToPackCoverage))
    }

    public var body: some View {
        ZStack {
            BlackoutDS.Surface.void.ignoresSafeArea()
            if let pack = packService.pack {
                OfflineMapView(
                    pack: pack,
                    selfFix: location.navigationFix,
                    manualPin: location.manualPin,
                    breadcrumbs: crumbs,
                    viewshed: viewshedRays,
                    slope: slopeSamples,
                    showViewshed: showViewshed && extrasOn,
                    showSlope: showSlope && extrasOn,
                    centerToken: centerToken,
                    pinCameraToPack: pinnedToPackCoverage,
                    onDropPin: { lat, lon in
                        location.dropManualPin(latitude: lat, longitude: lon)
                    },
                    onOutsidePack: { outside in
                        outsidePack = outside
                    },
                    resetToken: resetToken
                )
                .rotationEffect(.degrees(radarVisible && headingUp ? -(location.headingDegrees ?? 0) : 0))
                .ignoresSafeArea()
                if radarVisible, !showLocationEmptyState {
                    RadarHUDView(
                        headingUp: headingUp,
                        headingDegrees: location.headingDegrees,
                        peers: peers,
                        sweepAudio: sweepAudio,
                        onToggleHeading: {
                            headingUp.toggle()
                            UserDefaults.standard.set(headingUp, forKey: BlackoutKeys.radarHeadingUp)
                            if !pinnedToPackCoverage {
                                centerToken += 1
                            }
                        },
                        onToggleAudio: {
                            sweepAudio.toggle()
                            UserDefaults.standard.set(sweepAudio, forKey: BlackoutKeys.radarSweepAudio)
                        },
                        onSelectPeer: { selectedPeer = $0 },
                        onSelectSelf: { selectedPeer = nil }
                    )
                    .padding(.top, 120)
                    .padding(.bottom, 160)
                }
                if showLocationEmptyState {
                    NoPackCanvas(
                        title: "No tiles for this location",
                        detail: "Texas and New Mexico packs download from Field Packs on Wi-Fi, then work airplane. Recenter jumps the camera to the bundled Denver sample center, not your GPS.",
                        location: location,
                        packRegion: pack.region,
                        recenterTitle: "Recenter to pack coverage",
                        onReturn: {
                            pinnedToPackCoverage = true
                            resetToken += 1
                            packPaintLog = "Recenter · \(packService.paintDiagnostic) · not GPS"
                        },
                        onOpenFieldPacks: onOpenFieldPacks
                    )
                }
            } else {
                NoPackCanvas(
                    title: "No map pack",
                    detail: "DefaultPack is missing from Blackout.app. This canvas is intentional — not a MapKit spinner waiting on WAN.",
                    location: location,
                    packRegion: nil,
                    onReturn: nil,
                    onOpenFieldPacks: onOpenFieldPacks
                )
            }
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        HUDPanel {
                            VStack(alignment: .leading, spacing: 8) {
                                GPSChip(mode: gpsMode)
                                MeshPill(nearbyCount: mesh.nearbyPeerCount)
                                Text("file tiles · no Apple base map")
                                    .font(BlackoutDS.captionFont())
                                    .foregroundStyle(BlackoutDS.Silver.bright)
                                if let pack = packService.pack {
                                    Text("pack center \(pack.region.centerLabel) · not GPS")
                                        .font(BlackoutDS.captionFont())
                                        .foregroundStyle(BlackoutDS.Semantic.info)
                                }
                                if !packPaintLog.isEmpty {
                                    Text(packPaintLog)
                                        .font(BlackoutDS.captionFont())
                                        .foregroundStyle(BlackoutDS.Semantic.info)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if sosOnly {
                                    Text("CRITICAL · SOS only")
                                        .font(BlackoutDS.captionFont())
                                        .foregroundStyle(BlackoutDS.Red.hot)
                                } else if extremeSaver {
                                    Text("Extreme Saver · SOS + coarse nav + radar")
                                        .font(BlackoutDS.captionFont())
                                        .foregroundStyle(BlackoutDS.Semantic.warn)
                                }
                            }
                        }
                    }
                    Spacer()
                    CompassRose(heading: location.headingDegrees)
                }
                .padding(.horizontal, 16)
                .padding(.top, sizeClass == .regular ? 8 : 64)
                if location.authorization == .denied || location.authorization == .restricted {
                    PermissionDenied(
                        kind: .location,
                        reason: "GPS denied. Dead reckoning uses compass + steps from last-known or a manual pin. PermissionDenied stays; the app will not wait on a fix."
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                if location.manualPin?.hasCoordinate == true, location.lastKnown?.source != .gps {
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
                if showSlope || showViewshed, extrasOn {
                    Text("Sample DEM · not USGS. Slope/viewshed are coarse.")
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.steel)
                        .padding(.horizontal, 16)
                }
                if let storeError {
                    StoreFailure(storeError)
                        .padding(.horizontal, 16)
                }
                Spacer()
                if extrasOn {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Layers")
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(BlackoutDS.Silver.mid)
                            .padding(.horizontal, 4)
                        HStack(spacing: 8) {
                            toggleChip("Radar", on: radarOn) { radarOn.toggle() }
                            toggleChip("Slope", on: showSlope) {
                                showSlope.toggle()
                                UserDefaults.standard.set(showSlope, forKey: BlackoutKeys.mapSlope)
                                refreshTerrain()
                            }
                            toggleChip("Viewshed", on: showViewshed) {
                                showViewshed.toggle()
                                UserDefaults.standard.set(showViewshed, forKey: BlackoutKeys.mapViewshed)
                                refreshTerrain()
                            }
                            if LiDARAvailability.isSupported {
                                Button {
                                    showLiDAR = true
                                } label: {
                                    Text("LiDAR")
                                        .font(BlackoutDS.captionFont())
                                        .foregroundStyle(BlackoutDS.Silver.bright)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: BlackoutDS.Hit.sm)
                                        .background(BlackoutDS.Surface.raised.opacity(0.82))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                if battery.coarseNavigateEnabled || extrasOn {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tools")
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(BlackoutDS.Silver.mid)
                            .padding(.horizontal, 4)
                        HStack(spacing: 8) {
                            if battery.coarseNavigateEnabled {
                                toolButton("Navigate", tool: .navigate)
                            }
                            if extrasOn {
                                toolButton("Topo", tool: .topo)
                                toolButton("Towns", tool: .civilization)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 108)
                }
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
        .sheet(item: $selectedPeer) { blip in
            RadarPeerSheet(
                blip: blip,
                onMessage: { selectedPeer = nil },
                onPTT: { selectedPeer = nil },
                onNavigate: {
                    selectedPeer = nil
                    if battery.coarseNavigateEnabled {
                        tool = .navigate
                    }
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showLiDAR) {
            LiDARRangeView(
                mapRangeMeters: lidarMapRange,
                pointName: lidarPointName
            )
            .presentationDetents([.large])
        }
        .onChange(of: outsidePack) { _, outside in
            if outside { pinnedToPackCoverage = false }
        }
        .task { reloadCrumbs() }
        .onChange(of: location.navigationFix?.latitude) { _, _ in
            if showViewshed { refreshTerrain() }
        }
        .onChange(of: battery.isCritical) { _, critical in
            if critical {
                tool = nil
                showLiDAR = false
                selectedPeer = nil
            }
        }
        .onAppear {
            if extremeSaver { radarOn = true }
            packPaintLog = packService.paintDiagnostic
            refreshTerrain()
            location.startUpdating()
        }
    }

    private var lidarMapRange: Double? {
        guard let from = location.navigationFix, from.hasCoordinate,
              let to = location.manualPin ?? packService.pack?.pois.first(where: { $0.kind == "summit" }).map({
                  LocationFix(latitude: $0.latitude, longitude: $0.longitude)
              }),
              to.hasCoordinate else { return nil }
        return haversine(from.latitude!, from.longitude!, to.latitude!, to.longitude!)
    }

    private var lidarPointName: String {
        if location.manualPin?.hasCoordinate == true { return "Manual pin" }
        if let peak = packService.pack?.pois.first(where: { $0.kind == "summit" }) {
            return peak.name
        }
        return "Map point"
    }

    private func refreshTerrain() {
        slopeSamples = showSlope ? packService.slopeSamples() : []
        if showViewshed, let fix = location.navigationFix, fix.hasCoordinate {
            viewshedRays = packService.viewshed(
                fromLatitude: fix.latitude!,
                fromLongitude: fix.longitude!,
                observerHeightMeters: 2
            )
        } else {
            viewshedRays = []
        }
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
        if location.isDeadReckoning, location.navigationFix?.hasCoordinate == true {
            return .deadReckoning
        }
        if location.lastKnown?.source == .gps, location.lastKnown?.hasCoordinate == true {
            return location.authorization == .authorized ? .live : .lastKnown
        }
        if location.lastKnown?.hasCoordinate == true {
            return .lastKnown
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

    private func toggleChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(BlackoutDS.captionFont())
                .foregroundStyle(on ? BlackoutDS.Surface.void : BlackoutDS.Silver.bright)
                .frame(maxWidth: .infinity)
                .frame(height: BlackoutDS.Hit.sm)
                .background(on ? BlackoutDS.Silver.metal : BlackoutDS.Surface.raised.opacity(0.82))
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
    var packRegion: MapRegion?
    var recenterTitle: String = "Recenter to pack coverage"
    var onReturn: (() -> Void)?
    var onOpenFieldPacks: (() -> Void)?

    var body: some View {
        ZStack {
            BlackoutDS.Surface.void.opacity(0.92)
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
                if let packRegion {
                    Text("Pack center \(packRegion.centerLabel)")
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Semantic.info)
                    Text(packRegion.name)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.mid)
                }
                if let fix = location.navigationFix, fix.hasCoordinate {
                    Text("GPS \(fix.latitude!.formatted(.number.precision(.fractionLength(2)))), \(fix.longitude!.formatted(.number.precision(.fractionLength(2)))) — not camera")
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.steel)
                }
                if location.isDeadReckoning {
                    Text("DEAD RECKONING")
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Semantic.warn)
                }
                if let onReturn {
                    MetalButton(recenterTitle, height: BlackoutDS.Hit.md, action: onReturn)
                        .padding(.horizontal, 32)
                }
                if let onOpenFieldPacks {
                    GhostButton("Field Packs", height: BlackoutDS.Hit.sm, action: onOpenFieldPacks)
                        .padding(.horizontal, 32)
                }
                if location.authorization == .denied || location.authorization == .restricted,
                   location.navigationFix?.hasCoordinate != true {
                    Text("Long-press after Recenter, or use Drop pin at pack center on the Map HUD.")
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
