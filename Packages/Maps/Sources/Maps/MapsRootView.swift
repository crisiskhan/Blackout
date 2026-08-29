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
    @Bindable var packService: FileMapPack
    var coverageRegions: [MapRegion]
    var installedPackRoots: [URL]
    var onOpenFieldPacks: (() -> Void)?
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var tool: MapTool?
    @State private var crumbs: [BreadcrumbRecordDTO] = []
    @State private var outsidePack = false
    @State private var resetToken = 0
    @State private var centerToken = 0
    @State private var radarOn = true
    @State private var headingUp = UserDefaults.standard.bool(forKey: BlackoutKeys.radarHeadingUp)
    @State private var sweepAudio = UserDefaults.standard.bool(forKey: BlackoutKeys.radarSweepAudio)
    @State private var showViewshed = UserDefaults.standard.bool(forKey: BlackoutKeys.mapViewshed)
    @State private var showSlope = UserDefaults.standard.bool(forKey: BlackoutKeys.mapSlope)
    @State private var selectedPeer: RadarBlip?
    @State private var showLiDAR = false
    @State private var showLayers = false
    @State private var viewshedRays: [ViewshedRay] = []
    @State private var slopeSamples: [SlopeSample] = []
    @State private var pinnedToPackCoverage = false

    public init(
        location: LocationService,
        mesh: MeshFacade,
        battery: BatteryService,
        persistence: any PersistenceServing,
        packService: FileMapPack,
        coverageRegions: [MapRegion] = [],
        installedPackRoots: [URL] = [],
        onOpenFieldPacks: (() -> Void)? = nil
    ) {
        self.location = location
        self.mesh = mesh
        self.battery = battery
        self.persistence = persistence
        self.packService = packService
        self.coverageRegions = coverageRegions
        self.installedPackRoots = installedPackRoots
        self.onOpenFieldPacks = onOpenFieldPacks
    }

    private var sosOnly: Bool { battery.isCritical }
    private var extremeSaver: Bool { battery.isExtremeSaver }
    private var extrasOn: Bool { !sosOnly && !extremeSaver }
    private var peers: [RadarBlip] { [] }
    private var locationDenied: Bool {
        location.authorization == .denied || location.authorization == .restricted
    }
    private var locationOutsideCoverage: Bool {
        guard let fix = location.navigationFix, fix.hasCoordinate else { return false }
        let regions = coverageRegions.isEmpty ? [packService.pack?.region].compactMap { $0 } : coverageRegions
        return !regions.contains { $0.contains(latitude: fix.latitude!, longitude: fix.longitude!, padFraction: 0.08) }
    }
    private var showLocationEmptyState: Bool {
        packService.pack != nil && locationOutsideCoverage && !pinnedToPackCoverage
    }
    /// One raised card for a missing pack, GPS deny, or no tiles.
    /// Never a watermark and never stacked HUD warnings.
    private var showEmptyCard: Bool {
        packService.pack == nil || locationDenied || showLocationEmptyState
    }
    private var radarVisible: Bool {
        if sosOnly || showEmptyCard { return false }
        if extremeSaver { return true }
        return radarOn
    }
    private var showChipRow: Bool {
        packService.pack != nil && !showEmptyCard && !sosOnly
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
                .id(pack.rootURL.standardizedFileURL.path)
                .rotationEffect(.degrees(radarVisible && headingUp ? -(location.headingDegrees ?? 0) : 0))
                .ignoresSafeArea()
                if radarVisible {
                    RadarHUDView(
                        headingUp: headingUp,
                        headingDegrees: location.headingDegrees,
                        peers: peers,
                        sweepAudio: sweepAudio,
                        onSelectPeer: { selectedPeer = $0 },
                        onSelectSelf: { selectedPeer = nil }
                    )
                    .padding(.top, 80)
                    .padding(.bottom, 180)
                    .allowsHitTesting(true)
                }
            }
            if showEmptyCard {
                MapEmptyCard(
                    title: emptyCardTitle,
                    detail: emptyCardDetail,
                    showRecenter: packService.pack != nil,
                    onRecenter: packService.pack == nil ? nil : recenterToPack,
                    onOpenFieldPacks: onOpenFieldPacks
                )
            }
            VStack(spacing: 0) {
                MapLockHUD(
                    accuracyMeters: gpsAccuracyMeters,
                    headingDegrees: location.headingDegrees,
                    onNorthUp: {
                        headingUp = false
                        UserDefaults.standard.set(false, forKey: BlackoutKeys.radarHeadingUp)
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, sizeClass == .regular ? 8 : 64)
                Spacer()
                if showChipRow {
                    HStack(spacing: 8) {
                        MetalButton("Recenter", height: BlackoutDS.Hit.md, action: recenterToPack)
                        MetalButton("Layers", height: BlackoutDS.Hit.md) { showLayers = true }
                        MetalButton("Packs", height: BlackoutDS.Hit.md) { onOpenFieldPacks?() }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 120)
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
        .sheet(isPresented: $showLayers) {
            MapLayersSheet(
                radarOn: $radarOn,
                headingUp: $headingUp,
                sweepAudio: $sweepAudio,
                showSlope: $showSlope,
                showViewshed: $showViewshed,
                extrasOn: extrasOn,
                navigateEnabled: battery.coarseNavigateEnabled,
                lidarSupported: LiDARAvailability.isSupported,
                onToggleSlope: {
                    UserDefaults.standard.set(showSlope, forKey: BlackoutKeys.mapSlope)
                    refreshTerrain()
                },
                onToggleViewshed: {
                    UserDefaults.standard.set(showViewshed, forKey: BlackoutKeys.mapViewshed)
                    refreshTerrain()
                },
                onToggleHeading: {
                    UserDefaults.standard.set(headingUp, forKey: BlackoutKeys.radarHeadingUp)
                    if headingUp, !pinnedToPackCoverage {
                        centerToken += 1
                    }
                },
                onToggleAudio: {
                    UserDefaults.standard.set(sweepAudio, forKey: BlackoutKeys.radarSweepAudio)
                },
                onOpenLiDAR: {
                    showLayers = false
                    showLiDAR = true
                },
                onOpenTool: { item in
                    showLayers = false
                    tool = item
                }
            )
            .presentationDetents([.medium])
            .preferredColorScheme(.dark)
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
            resolvePaintPack()
            if showViewshed { refreshTerrain() }
        }
        .onChange(of: location.navigationFix?.longitude) { _, _ in
            resolvePaintPack()
        }
        .onChange(of: installedPackRoots) { _, _ in
            resolvePaintPack()
        }
        .onChange(of: pinnedToPackCoverage) { _, _ in
            resolvePaintPack()
        }
        .onChange(of: battery.isCritical) { _, critical in
            if critical {
                tool = nil
                showLiDAR = false
                showLayers = false
                selectedPeer = nil
            }
        }
        .onAppear {
            if extremeSaver { radarOn = true }
            resolvePaintPack()
            refreshTerrain()
            location.startUpdating()
        }
    }

    private var emptyCardTitle: String {
        if packService.pack == nil { return "No map pack" }
        if locationDenied { return "GPS denied" }
        return "No tiles here"
    }

    private var emptyCardDetail: String {
        if packService.pack == nil {
            return "Download a Field Pack for dusk tiles."
        }
        if locationDenied {
            return "Recenter to pack coverage, or open Field Packs."
        }
        return "Recenter to the Denver sample, or download a Field Pack."
    }

    private var gpsAccuracyMeters: Double? {
        guard let fix = location.navigationFix, fix.hasCoordinate,
              let meters = fix.horizontalAccuracyMeters,
              meters >= 0, meters.isFinite else { return nil }
        return meters
    }

    private func recenterToPack() {
        pinnedToPackCoverage = true
        resolvePaintPack()
        resetToken += 1
    }

    private func resolvePaintPack() {
        packService.replaceInstalledRoots(installedPackRoots)
        let before = packService.pack?.rootURL.standardizedFileURL.path
        let fix = location.navigationFix
        packService.resolve(
            latitude: fix?.hasCoordinate == true ? fix?.latitude : nil,
            longitude: fix?.hasCoordinate == true ? fix?.longitude : nil,
            pinToBundled: pinnedToPackCoverage
        )
        let after = packService.pack?.rootURL.standardizedFileURL.path
        if before != after {
            refreshTerrain()
            if !pinnedToPackCoverage {
                centerToken += 1
            }
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
        } catch {
            crumbs = []
        }
    }
}

enum MapTool: String, Identifiable {
    case navigate, radar, topo, civilization
    var id: String { rawValue }
}

/// 56h GPS lock + accuracy, and a compass that taps to north-up. No grid-ref.
struct MapLockHUD: View {
    var accuracyMeters: Double?
    var headingDegrees: Double?
    var onNorthUp: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: accuracyMeters == nil ? "lock.open" : "lock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accuracyMeters == nil ? BlackoutDS.Silver.steel : BlackoutDS.Semantic.ok)
                Text(accuracyLabel)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.bright)
                    .accessibilityLabel(accuracyMeters == nil ? "NO FIX" : accuracyLabel)
            }
            Spacer(minLength: 8)
            Button(action: onNorthUp) {
                HStack(spacing: 6) {
                    Image(systemName: "location.north.line")
                        .font(.system(size: 18, weight: .semibold))
                        .rotationEffect(.degrees(-(headingDegrees ?? 0)))
                    Text(headingDegrees.map { "\(Int($0.rounded()))°" } ?? "—")
                        .font(BlackoutDS.captionFont())
                }
                .foregroundStyle(BlackoutDS.Silver.metal)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("North-up")
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: BlackoutDS.Hit.sm)
        .background(BlackoutDS.Surface.raised.opacity(0.82))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var accuracyLabel: String {
        guard let meters = accuracyMeters else { return "NO FIX" }
        return "\(Int(meters.rounded())) m"
    }
}

/// One raised card. Two actions max: Recenter, Field Packs.
struct MapEmptyCard: View {
    var title: String
    var detail: String
    var showRecenter: Bool
    var onRecenter: (() -> Void)?
    var onOpenFieldPacks: (() -> Void)?

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(BlackoutDS.titleFont())
                    .foregroundStyle(BlackoutDS.Silver.bright)
                Text(detail)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.mid)
                    .fixedSize(horizontal: false, vertical: true)
                if showRecenter, let onRecenter {
                    MetalButton("Recenter", height: BlackoutDS.Hit.md, action: onRecenter)
                }
                if let onOpenFieldPacks {
                    GhostButton("Field Packs", height: BlackoutDS.Hit.md, action: onOpenFieldPacks)
                }
            }
            .padding(20)
            .frame(maxWidth: 400, alignment: .leading)
            .background(BlackoutDS.Surface.raised)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)
            Spacer()
        }
        .padding(.bottom, 100)
    }
}

struct MapLayersSheet: View {
    @Binding var radarOn: Bool
    @Binding var headingUp: Bool
    @Binding var sweepAudio: Bool
    @Binding var showSlope: Bool
    @Binding var showViewshed: Bool
    var extrasOn: Bool
    var navigateEnabled: Bool
    var lidarSupported: Bool
    var onToggleSlope: () -> Void
    var onToggleViewshed: () -> Void
    var onToggleHeading: () -> Void
    var onToggleAudio: () -> Void
    var onOpenLiDAR: () -> Void
    var onOpenTool: (MapTool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ScreenHeader("Layers")
                    layerToggle("Radar", on: $radarOn, enabled: extrasOn, persist: {})
                    layerToggle("Slope", on: $showSlope, enabled: extrasOn, persist: onToggleSlope)
                    layerToggle("Viewshed", on: $showViewshed, enabled: extrasOn, persist: onToggleViewshed)
                    if lidarSupported, extrasOn {
                        GhostButton("LiDAR", height: BlackoutDS.Hit.md, action: onOpenLiDAR)
                    }
                    if navigateEnabled {
                        GhostButton("Navigate", height: BlackoutDS.Hit.md) { onOpenTool(.navigate) }
                    }
                    if extrasOn {
                        GhostButton("Topo", height: BlackoutDS.Hit.md) { onOpenTool(.topo) }
                        GhostButton("Towns", height: BlackoutDS.Hit.md) { onOpenTool(.civilization) }
                    }
                    layerToggle("Heading-up", on: $headingUp, enabled: true, persist: onToggleHeading)
                    layerToggle("Sweep audio", on: $sweepAudio, enabled: extrasOn, persist: onToggleAudio)
                }
                .padding(20)
            }
            .background(BlackoutDS.Surface.base.ignoresSafeArea())
            .navigationTitle("Layers")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func layerToggle(
        _ title: String,
        on: Binding<Bool>,
        enabled: Bool,
        persist: @escaping () -> Void
    ) -> some View {
        Button {
            guard enabled else { return }
            on.wrappedValue.toggle()
            persist()
        } label: {
            HStack {
                Text(title)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(enabled ? BlackoutDS.Silver.bright : BlackoutDS.Silver.steel)
                Spacer()
                Text(on.wrappedValue ? "On" : "Off")
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(on.wrappedValue && enabled ? BlackoutDS.Semantic.ok : BlackoutDS.Silver.mid)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: BlackoutDS.Hit.md)
            .background(BlackoutDS.Surface.raised.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }
}
