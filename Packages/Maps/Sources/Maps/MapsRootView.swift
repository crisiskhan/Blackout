import BlackoutCore
import BlackoutBattery
import BlackoutLocation
import BlackoutMesh
import DesignSystem
import MapsChrome
import MapsRouting
import SwiftUI
import UIKit

public struct MapsRootView: View {
    @Bindable var location: LocationService
    @Bindable var mesh: MeshFacade
    @Bindable var battery: BatteryService
    let persistence: any PersistenceServing
    @Bindable var packService: FileMapPack
    var coverageRegions: [MapRegion]
    var installedPackRoots: [URL]
    var packReady: PackReadySnapshot
    var onOpenFieldPacks: (() -> Void)?
    var externalSheetOpen: Bool
    var sosCoverOpen: Bool
    @Bindable var roster: PartyRoster
    var onMessagePeer: ((BlackoutID) -> Void)?
    var pendingPingNav: Binding<FieldPingNav?>
    var latestInbound: LatestInboundPing?
    var onPingReply: ((FieldReplyID) -> Void)?
    var onNavLockChange: ((Bool) -> Void)?
    @Binding var fieldMode: FieldJobMode?
    @Binding var nightRed: Bool
    var sharedTrack: [FollowTrackWire.Point]
    var onShareTrack: (([BreadcrumbRecordDTO]) -> Void)?
    var onSendPack: ((String) -> Void)?
    var onOpenGuide: ((String) -> Void)?
    var onNightRedChange: ((Bool) -> Void)?
    @Binding var pendingGuideJob: GuideMapJob?
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
    @State private var showTopoTiles = UserDefaults.standard.bool(forKey: BlackoutKeys.mapTopoTiles)
    @State private var showTrails = UserDefaults.standard.bool(forKey: BlackoutKeys.mapTrails)
    @State private var navigate = NavigateSession()
    @State private var compass = CompassLockSession()
    @State private var viewshedRays: [ViewshedRay] = []
    @State private var slopeSamples: [SlopeSample] = []
    @State private var pinnedToPackCoverage = false
    @State private var chrome = MapChromeRecede()
    @State private var metersPerPoint = 10.0
    @State private var openOutingName: String?
    @State private var outingStartLatitude: Double?
    @State private var outingStartLongitude: Double?
    @State private var toolHint: String?
    @State private var torch = MapTorchController()
    @State private var searchKind: SearchPatternKind = .expandingSquare
    @State private var searchActive = false
    @State private var searchLine: [(Double, Double)] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        location: LocationService,
        mesh: MeshFacade,
        battery: BatteryService,
        persistence: any PersistenceServing,
        packService: FileMapPack,
        coverageRegions: [MapRegion] = [],
        installedPackRoots: [URL] = [],
        packReady: PackReadySnapshot = .empty,
        onOpenFieldPacks: (() -> Void)? = nil,
        externalSheetOpen: Bool = false,
        sosCoverOpen: Bool = false,
        roster: PartyRoster,
        onMessagePeer: ((BlackoutID) -> Void)? = nil,
        pendingPingNav: Binding<FieldPingNav?> = .constant(nil),
        latestInbound: LatestInboundPing? = nil,
        onPingReply: ((FieldReplyID) -> Void)? = nil,
        onNavLockChange: ((Bool) -> Void)? = nil,
        fieldMode: Binding<FieldJobMode?> = .constant(nil),
        nightRed: Binding<Bool> = .constant(false),
        sharedTrack: [FollowTrackWire.Point] = [],
        onShareTrack: (([BreadcrumbRecordDTO]) -> Void)? = nil,
        onSendPack: ((String) -> Void)? = nil,
        onOpenGuide: ((String) -> Void)? = nil,
        onNightRedChange: ((Bool) -> Void)? = nil,
        pendingGuideJob: Binding<GuideMapJob?> = .constant(nil)
    ) {
        self.location = location
        self.mesh = mesh
        self.battery = battery
        self.persistence = persistence
        self.packService = packService
        self.coverageRegions = coverageRegions
        self.installedPackRoots = installedPackRoots
        self.packReady = packReady
        self.onOpenFieldPacks = onOpenFieldPacks
        self.externalSheetOpen = externalSheetOpen
        self.sosCoverOpen = sosCoverOpen
        self.roster = roster
        self.onMessagePeer = onMessagePeer
        self.pendingPingNav = pendingPingNav
        self.latestInbound = latestInbound
        self.onPingReply = onPingReply
        self.onNavLockChange = onNavLockChange
        self._fieldMode = fieldMode
        self._nightRed = nightRed
        self.sharedTrack = sharedTrack
        self.onShareTrack = onShareTrack
        self.onSendPack = onSendPack
        self.onOpenGuide = onOpenGuide
        self.onNightRedChange = onNightRedChange
        self._pendingGuideJob = pendingGuideJob
    }

    private var sosOnly: Bool { battery.isCritical }
    private var extremeSaver: Bool { battery.isExtremeSaver }
    private var extrasOn: Bool { !sosOnly && !extremeSaver }
    private var peers: [RadarBlip] { roster.radarBlips(selfFix: location.navigationFix) }
    private var locationDenied: Bool {
        location.authorization == .denied || location.authorization == .restricted
    }
    private var viewshedOrigin: LocationFix? {
        ViewshedPolicy.origin(
            locationDenied: locationDenied,
            navigationFix: location.navigationFix,
            droppedPin: location.manualPin
        )
    }
    private var gpsLive: Bool {
        location.authorization == .authorized && location.navigationFix?.source == .gps
    }
    /// Live fix, else last-known. A covering pack paints; none cover is the empty card.
    private var resolveCoordinate: LocationFix? {
        if let live = location.navigationFix, live.hasCoordinate { return live }
        if let last = location.lastKnown, last.hasCoordinate { return last }
        return nil
    }
    /// One raised card. No file-tile canvas underneath. GPS deny stays Feature 1 “No GPS.”
    private var showEmptyCard: Bool {
        MapEmptyPolicy.showsEmptyCard(packMounted: packService.pack != nil)
    }
    private var radarVisible: Bool {
        MapEmptyPolicy.showsRadar(
            packMounted: packService.pack != nil,
            sosOnly: sosOnly,
            radarOn: radarOn,
            extremeSaver: extremeSaver
        )
    }
    private var showChipRow: Bool {
        MapEmptyPolicy.showsChips(packMounted: packService.pack != nil, sosOnly: sosOnly)
    }
    private var liveRec: Bool {
        UserDefaults.standard.bool(forKey: BlackoutKeys.crumbsTracking)
    }
    /// Sheets, dest preview, deny card, live Rec, SOS cover. Reduce Motion is separate.
    private var holdsChrome: Bool {
        externalSheetOpen
            || sosCoverOpen
            || tool != nil
            || showLayers
            || showLiDAR
            || selectedPeer != nil
            || showEmptyCard
            || navigate.phase == .preview
            || !navigate.hits.isEmpty
            || navigate.empty != nil
            || liveRec
            || compass.showMarkSheet
    }

    public var body: some View {
        mapWithSheets
            .modifier(
                MapPackLifecycleModifier(pack: packObservers, chrome: chromeObservers)
            )
            .onDisappear { torch.turnOff() }
    }

    private var packObservers: MapsPackObservers {
        MapsPackObservers(
            outsidePack: outsidePack,
            fixLatitude: location.navigationFix?.latitude,
            fixLongitude: location.navigationFix?.longitude,
            lastKnownLatitude: location.lastKnown?.latitude,
            authorization: location.authorization,
            profile: navigate.profile,
            installedPackRoots: installedPackRoots,
            pinnedToPackCoverage: pinnedToPackCoverage,
            headingDegrees: location.headingDegrees,
            isCritical: battery.isCritical,
            onOutsidePack: { outside in
                if outside { pinnedToPackCoverage = false }
            },
            onReloadCrumbs: reloadCrumbs,
            onFixLatitude: {
                resolvePaintPack()
                if showViewshed { refreshTerrain() }
                refreshGuidance()
            },
            onFixLongitude: {
                resolvePaintPack()
                refreshGuidance()
            },
            onHeading: refreshGuidance,
            onProfile: {
                navigate.refreshPreview(origin: originCoordinate, pack: packService.routing)
            },
            onAuthorization: refreshGuidance,
            onLastKnown: resolvePaintPack,
            onInstalledRoots: resolvePaintPack,
            onPinned: resolvePaintPack,
            onCritical: { critical in
                if critical {
                    tool = nil
                    showLiDAR = false
                    showLayers = false
                    selectedPeer = nil
                    navigate.end()
                    compass.end()
                }
            }
        )
    }

    private var chromeObservers: MapsChromeObservers {
        MapsChromeObservers(
            reduceMotion: reduceMotion,
            holdsChrome: holdsChrome,
            onAppearAction: {
                if extremeSaver { radarOn = true }
                resolvePaintPack()
                refreshTerrain()
                refreshGuidance()
                location.startUpdating()
                applyChrome {
                    $0.reduceMotion = reduceMotion
                    $0.hold = holdsChrome
                    $0.tick(at: nowOffset)
                }
            },
            onChromeInputs: {
                applyChrome {
                    $0.reduceMotion = reduceMotion
                    $0.hold = holdsChrome
                    $0.tick(at: nowOffset)
                }
            }
        )
    }

    private var mapRoot: some View {
        ZStack {
            BlackoutDS.Surface.void.ignoresSafeArea()
            mapCanvas
            emptyOverlay
                .colorMultiply(nightRed ? Color(red: 1, green: 0.55, blue: 0.55) : .white)
            mapLockChrome
                .colorMultiply(nightRed ? Color(red: 1, green: 0.55, blue: 0.55) : .white)
        }
        .preferredColorScheme(.dark)
    }

    private var mapWithSheets: some View {
        mapRoot
            .sheet(item: $tool, content: toolSheet)
            .sheet(isPresented: $showLayers, content: layersSheet)
            .sheet(item: $selectedPeer, content: peerSheet)
            .sheet(isPresented: $showLiDAR, content: lidarSheet)
            .sheet(isPresented: Bindable(compass).showMarkSheet, content: markSheet)
            .onChange(of: pendingPingNav.wrappedValue) { _, nav in
                consumePingNav(nav)
            }
            .onChange(of: pendingGuideJob) { _, job in
                consumeGuideJob(job)
            }
            .onAppear {
                consumePingNav(pendingPingNav.wrappedValue)
                consumeGuideJob(pendingGuideJob)
            }
    }

    private func consumeGuideJob(_ job: GuideMapJob?) {
        guard let job else { return }
        pendingGuideJob = nil
        switch job {
        case .findWater:
            tool = .water
        case .findCivilization:
            tool = .civilization
        case .lastMark:
            guard let mark = lastMark else {
                toolHint = MapQuickNav.lastMarkDisabledReason(hasMark: false)
                return
            }
            toolHint = nil
            lockOrRoute(latitude: mark.latitude, longitude: mark.longitude, label: mark.name)
        }
    }

    private func consumePingNav(_ nav: FieldPingNav?) {
        guard let nav else { return }
        pendingPingNav.wrappedValue = nil
        guard battery.coarseNavigateEnabled else { return }
        UserDefaults.standard.set(true, forKey: BlackoutKeys.lastUsedTBT)
        navigate.navigateToPeer(
            latitude: nav.latitude,
            longitude: nav.longitude,
            label: nav.label,
            origin: originCoordinate,
            pack: packService.routing
        )
    }

    @ViewBuilder
    private func toolSheet(_ item: MapTool) -> some View {
        NavigationStack {
            switch item {
            case .navigate:
                NavigateView(
                    location: location,
                    pack: packService.pack,
                    battery: battery,
                    packReady: packReady
                )
            case .radar:
                RadarView(
                    location: location,
                    pack: packService.pack,
                    roster: roster,
                    nearbyPeerCount: mesh.nearbyPeerCount
                )
            case .topo:
                TopographyView(location: location, packService: packService)
            case .civilization:
                PackFindSheet(
                    mode: .civilization,
                    origin: originCoordinate,
                    pack: packService.pack,
                    locationDenied: locationDenied,
                    onPick: pickFound
                )
            case .water:
                PackFindSheet(
                    mode: .water,
                    origin: originCoordinate,
                    pack: packService.pack,
                    locationDenied: locationDenied,
                    onPick: pickFound
                )
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private func layersSheet() -> some View {
        MapLayersSheet(
            radarOn: $radarOn,
            headingUp: $headingUp,
            sweepAudio: $sweepAudio,
            showSlope: $showSlope,
            showViewshed: $showViewshed,
            extrasOn: extrasOn,
            hasDEM: packService.hasDEM,
            nightRed: $nightRed,
            nearbyPeerCount: mesh.nearbyPeerCount,
            relayableReadyIDs: packReady.readyIDs.filter { PackRelayPolicy.isRelayable($0) },
            onToggleNightRed: {
                onNightRedChange?(nightRed)
            },
            onSendPack: onSendPack,
            showTopoTiles: $showTopoTiles,
            showTrails: $showTrails,
            hasRouting: packService.routing != nil,
            searchQuery: navQueryBinding,
            searchHits: navigate.hits,
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
            onToggleTopo: {
                UserDefaults.standard.set(showTopoTiles, forKey: BlackoutKeys.mapTopoTiles)
            },
            onToggleTrails: {
                UserDefaults.standard.set(showTrails, forKey: BlackoutKeys.mapTrails)
            },
            onSearch: {
                navigate.search(
                    pack: packService.routing,
                    pois: packService.pack?.pois ?? [],
                    addresses: packService.pack?.addresses ?? []
                )
            },
            onPickSearch: { hit in
                showLayers = false
                pickFound(hit)
            },
            onOpenLiDAR: {
                showLayers = false
                showLiDAR = true
            },
            onOpenTool: { item in
                showLayers = false
                tool = item
            },
            onFind: { mode in
                showLayers = false
                navigate.findPack(
                    mode: mode,
                    origin: originCoordinate,
                    bounds: packBounds,
                    pois: packService.pack?.pois ?? []
                )
            }
        )
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private func peerSheet(_ blip: RadarBlip) -> some View {
        RadarPeerSheet(
            blip: blip,
            onMessage: {
                selectedPeer = nil
                onMessagePeer?(blip.id)
            },
            onNavigate: {
                selectedPeer = nil
                navigateToPeer(blip)
            }
        )
        .presentationDetents([.medium])
    }

    private func navigateToPeer(_ blip: RadarBlip) {
        guard battery.coarseNavigateEnabled else { return }
        if let lat = blip.latitude, let lon = blip.longitude {
            navigate.navigateToPeer(
                latitude: lat,
                longitude: lon,
                label: blip.displayName ?? "Peer",
                origin: originCoordinate,
                pack: packService.routing
            )
        } else {
            navigate.markNoCoordinate()
        }
    }

    private func markSheet() -> some View {
        CompassMarkSheet(
            session: compass,
            peers: peers,
            fix: location.navigationFix,
            onLocked: applyLockHeading
        )
        .presentationDetents([.medium, .large])
    }

    private func lidarSheet() -> some View {
        LiDARRangeView(
            mapRangeMeters: lidarMapRange,
            pointName: lidarPointName
        )
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var mapCanvas: some View {
        if MapEmptyPolicy.paintsCanvas(packMounted: packService.pack != nil), let pack = packService.pack {
            offlineMap(pack)
                .id(pack.rootURL.standardizedFileURL.path)
                .rotationEffect(.degrees(radarVisible && fieldHeadingUp ? -(location.headingDegrees ?? 0) : 0))
                .ignoresSafeArea()
            if radarVisible {
                RadarHUDView(
                    headingUp: fieldHeadingUp,
                    headingDegrees: location.headingDegrees,
                    peers: peers,
                    sweepAudio: sweepAudio,
                    onSelectPeer: {
                        noteMapActivity()
                        selectedPeer = $0
                    },
                    onSelectSelf: {
                        noteMapActivity()
                        selectedPeer = nil
                    }
                )
                .padding(.top, 80)
                .padding(.bottom, 180)
                .allowsHitTesting(true)
            }
        }
    }

    private func offlineMap(_ pack: MapPackSnapshot) -> OfflineMapView {
        OfflineMapView(
            pack: pack,
            selfFix: location.navigationFix,
            manualPin: location.manualPin,
            breadcrumbs: crumbs,
            viewshed: viewshedRays,
            slope: slopeSamples,
            showViewshed: showViewshed && extrasOn && packService.hasDEM,
            viewshedOrigin: viewshedOrigin,
            showSlope: showSlope && extrasOn,
            centerToken: centerToken,
            pinCameraToPack: pinnedToPackCoverage,
            routing: packService.routing,
            routeLine: navigate.routePolyline,
            destination: navigate.destination ?? compass.lockCoordinate,
            showPackTiles: packService.routing == nil || showTopoTiles,
            showTrails: showTrails,
            headingDegrees: location.headingDegrees,
            accuracyMeters: gpsAccuracyMeters,
            packContainsSelf: packContainsSelf,
            activeManeuver: liveManeuver,
            inboundPing: openInboundPingFix,
            inboundPingHue: openInbound?.hue,
            searchPattern: searchActive ? searchLine : [],
            sharedTrack: sharedTrack,
            amenityPins: (packService.pack?.pois ?? []).map {
                RoutingPOI(
                    id: $0.id,
                    name: $0.name,
                    kind: $0.kind,
                    coordinate: RoutingCoordinate(latitude: $0.latitude, longitude: $0.longitude)
                )
            },
            onDropPin: { lat, lon in
                location.dropManualPin(latitude: lat, longitude: lon)
            },
            onTap: { lat, lon in
                noteMapActivity()
                guard battery.coarseNavigateEnabled, navigate.phase != .guidance else { return }
                navigate.pickMap(
                    latitude: lat,
                    longitude: lon,
                    origin: originCoordinate,
                    pack: packService.routing
                )
            },
            onUserInteract: noteMapActivity,
            onScaleChange: { metersPerPoint = $0 },
            onOutsidePack: { outside in
                outsidePack = outside
            },
            resetToken: resetToken
        )
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if packService.packTooNew {
            MapEmptyCard(kind: .packTooNew, onPacks: onOpenFieldPacks, onRecenter: recenterToPack)
        } else if showEmptyCard {
            MapEmptyCard(kind: .noPack, onPacks: onOpenFieldPacks, onRecenter: recenterToPack)
        } else if let kind = navigate.empty?.mapKind, navigate.phase != .guidance {
            MapEmptyCard(kind: kind)
        } else if let empty = navigate.empty, navigate.phase != .guidance {
            VStack {
                Spacer()
                NavigateEmptyCard(
                    empty: empty,
                    onBearing: { tool = .navigate },
                    onPacks: onOpenFieldPacks
                )
                .padding(.horizontal, 24)
                Spacer()
            }
            .padding(.bottom, 100)
        } else if let copy = compass.emptyCopy {
            CompassLockEmptyCard(text: copy)
        }
    }

    private var mapLockChrome: some View {
        VStack(spacing: 0) {
            lockHudStack
            if showChipRow, battery.coarseNavigateEnabled, showsNavigateBanner {
                navigateChrome
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            Spacer()
            if showChipRow, battery.coarseNavigateEnabled {
                receding {
                    CompassLockBar(
                        isLocked: compass.isLocked,
                        hasTarget: compass.target != nil,
                        onSpeak: {
                            noteMapActivity()
                            compass.speakOnce()
                        },
                        onSteer: {
                            noteMapActivity()
                            compass.openSteer()
                        },
                        onMark: {
                            noteMapActivity()
                            compass.openMark()
                        },
                        onLock: {
                            noteMapActivity()
                            compass.toggleLock()
                            if compass.isLocked { applyLockHeading() }
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
            if showChipRow {
                scaleBarRow
                quickNavRow
                chipRow
            }
            pingStrip
            vitalsRow
        }
        .onChange(of: compass.isLocked) { _, _ in reportNavLock() }
        .onChange(of: navigate.phase) { _, _ in reportNavLock() }
        .onAppear {
            reportNavLock()
            applySharedTrackIfNeeded()
        }
        .onChange(of: sharedTrack.count) { _, _ in
            applySharedTrackIfNeeded()
        }
    }

    private var lockHudStack: some View {
        receding {
            VStack(spacing: 8) {
                MapLockHUD(
                    accuracyMeters: gpsAccuracyMeters,
                    headingDegrees: location.headingDegrees,
                    onNorthUp: {
                        noteMapActivity()
                        guard !compass.isLocked else { return }
                        headingUp = false
                        UserDefaults.standard.set(false, forKey: BlackoutKeys.radarHeadingUp)
                    }
                )
                if DeadReckoningHonesty.chipVisible(gpsLive: gpsLive, isDeadReckoning: location.isDeadReckoning) {
                    Text(DeadReckoningHonesty.chip)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Semantic.warn)
                } else if location.motionDenied, !gpsLive {
                    Text(DeadReckoningHonesty.motionDeniedCopy)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Semantic.warn)
                }
                if showViewshed, !packService.hasDEM {
                    Text(ViewshedPolicy.noDEM)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.steel)
                }
                MapExpeditionBanner(title: openOutingName ?? "No open expedition")
                if let fieldMode {
                    fieldModePlate(fieldMode)
                }
                fieldToolsRow
            }
            .padding(.horizontal, 16)
            .padding(.top, sizeClass == .regular ? 8 : 64)
        }
    }

    /// Bottom-leading 56h metal chip. Same 8pt-above-tab-bar baseline as SOS.
    /// ≥8pt horizontal gap to the 88pt disk. Recedes with HUD. Reduce Motion: stays. Never a disk.
    private var vitalsRow: some View {
        receding {
            HStack(alignment: .bottom, spacing: 0) {
                VitalsChip(
                    isOKLatched: !roster.isRed,
                    isNotLatched: roster.isRed,
                    pending: roster.pending,
                    onOK: { commitVitals(.imOK) },
                    onNot: { commitVitals(.notOK) }
                )
                Spacer(minLength: BlackoutDS.Hit.sos + BlackoutDS.Vitals.sosGap)
            }
            .frame(minHeight: BlackoutDS.Vitals.sosClearance, alignment: .bottom)
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.bottom, BlackoutDS.Vitals.sosGap)
        }
    }

    private func commitVitals(_ action: PartyVitalAction) {
        noteMapActivity()
        if let envelope = roster.tap(action, fix: location.navigationFix) {
            mesh.send(envelope)
        }
    }

    private var scaleBarRow: some View {
        receding {
            HStack(alignment: .bottom, spacing: 8) {
                MapScaleBar(metersPerPoint: metersPerPoint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var chipRow: some View {
        receding {
            HStack(spacing: 8) {
                MetalButton("Recenter", height: BlackoutDS.Hit.md, action: recenterToPack)
                MetalButton("Layers", height: BlackoutDS.Hit.md) {
                    noteMapActivity()
                    showLayers = true
                }
                MetalButton("Packs", height: BlackoutDS.Hit.md) {
                    noteMapActivity()
                    onOpenFieldPacks?()
                }
                if MapTorchPolicy.showsControl(hasTorch: torch.hasHardware) {
                    flashlightButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private var flashlightButton: some View {
        Button {
            noteMapActivity()
            torch.toggle()
        } label: {
            HStack(spacing: 8) {
                if torch.isOn {
                    Circle()
                        .fill(BlackoutDS.Silver.bright)
                        .frame(width: BlackoutDS.Vitals.pip, height: BlackoutDS.Vitals.pip)
                }
                Text(ConvenienceCopy.flashlight)
                    .font(BlackoutDS.bodyFont())
                    .fontWeight(.semibold)
            }
            .foregroundStyle(BlackoutDS.Surface.void)
            .frame(maxWidth: .infinity)
            .frame(height: BlackoutDS.Hit.md)
            .background(BlackoutDS.Silver.metal)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ConvenienceCopy.flashlight)
        .accessibilityAddTraits(torch.isOn ? .isSelected : [])
        .accessibilityValue(torch.isOn ? "On" : "Off")
    }

    private var outingStart: (latitude: Double, longitude: Double)? {
        MapQuickNav.outingStart(
            crumbs: crumbs.map { ($0.latitude, $0.longitude) },
            startLatitude: outingStartLatitude,
            startLongitude: outingStartLongitude
        )
    }

    private var lastMark: CompassLockWaypoint? {
        compass.marks.last
    }

    private var openInbound: LatestInboundPing? {
        guard let latestInbound, latestInbound.showsMapStrip() else { return nil }
        return latestInbound
    }

    private var openInboundPingFix: LocationFix? {
        guard let openInbound, let lat = openInbound.latitude, let lon = openInbound.longitude else {
            return nil
        }
        return LocationFix(latitude: lat, longitude: lon)
    }

    private var quickNavRow: some View {
        receding {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    mapToolButton(ConvenienceCopy.shareCoords, enabled: true) {
                        shareCoords()
                    }
                    mapToolButton(
                        ConvenienceCopy.returnToStart,
                        enabled: MapQuickNav.returnEnabled(hasStart: outingStart != nil)
                    ) {
                        guard let start = outingStart else {
                            toolHint = MapQuickNav.returnDisabledReason(hasStart: false)
                            return
                        }
                        toolHint = nil
                        lockOrRoute(latitude: start.latitude, longitude: start.longitude, label: "Return")
                    }
                    mapToolButton(
                        ConvenienceCopy.lastMark,
                        enabled: MapQuickNav.lastMarkEnabled(hasMark: lastMark != nil)
                    ) {
                        guard let mark = lastMark else {
                            toolHint = MapQuickNav.lastMarkDisabledReason(hasMark: false)
                            return
                        }
                        toolHint = nil
                        lockOrRoute(latitude: mark.latitude, longitude: mark.longitude, label: mark.name)
                    }
                }
                if let toolHint {
                    Text(toolHint)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Semantic.warn)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func mapToolButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        MetalButton(title, height: BlackoutDS.Hit.sm) {
            noteMapActivity()
            action()
        }
        .opacity(enabled ? 1 : MapQuickNav.disabledOpacity)
        .disabled(false)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var pingStrip: some View {
        if let openInbound {
            let strip = HStack(spacing: 8) {
                MetalButton(ConvenienceCopy.coming, height: BlackoutDS.Hit.sm) {
                    noteMapActivity()
                    onPingReply?(.coming)
                }
                MetalButton(ConvenienceCopy.hold, height: BlackoutDS.Hit.sm) {
                    noteMapActivity()
                    onPingReply?(.hold)
                }
                MetalButton(ConvenienceCopy.navigate, height: BlackoutDS.Hit.sm) {
                    noteMapActivity()
                    if let nav = openInbound.navigation {
                        consumePingNav(nav)
                    } else {
                        toolHint = SOSConfirm.noFix
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            if openInbound.holdsMapChrome() {
                strip
            } else {
                receding { strip }
            }
        }
    }

    private func shareCoords() {
        let live = location.navigationFix?.source == .gps || location.navigationFix?.source == .deadReckoning
            ? location.navigationFix : nil
        let last = location.lastKnown
        let text = BlackoutCoordShare.message(live: live, lastKnown: last)
        if BlackoutCoordShare.shareFix(live: live, lastKnown: last) == nil {
            toolHint = ConvenienceCopy.noFixShare
        } else {
            toolHint = nil
        }
        UIPasteboard.general.string = text
        MapShareSheet.present(text)
    }

    private func lockOrRoute(latitude: Double, longitude: Double, label: String) {
        guard battery.coarseNavigateEnabled else { return }
        let lastTBT = UserDefaults.standard.bool(forKey: BlackoutKeys.lastUsedTBT)
        if lastTBT {
            navigate.navigateToPeer(
                latitude: latitude,
                longitude: longitude,
                label: label,
                origin: originCoordinate,
                pack: packService.routing
            )
            reportNavLock()
            return
        }
        UserDefaults.standard.set(false, forKey: BlackoutKeys.lastUsedTBT)
        navigate.end()
        let point = CompassLockWaypoint(
            id: "quick-\(label)",
            name: label,
            latitude: latitude,
            longitude: longitude,
            kind: .poi
        )
        _ = compass.lockOn(point)
        applyLockHeading()
        reportNavLock()
    }

    private func reportNavLock() {
        let on = compass.isLocked || navigate.phase == .guidance
        onNavLockChange?(on)
    }

    private func receding<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .modifier(RecedingMapChrome(isReceded: chrome.isReceded, reduceMotion: reduceMotion))
    }

    private var originCoordinate: RoutingCoordinate? {
        guard let fix = location.navigationFix, fix.hasCoordinate else { return nil }
        return RoutingCoordinate(latitude: fix.latitude!, longitude: fix.longitude!)
    }

    private var packBounds: RoutingBBox? {
        guard let region = packService.pack?.region else { return nil }
        return RoutingBBox(
            west: region.west,
            south: region.south,
            east: region.east,
            north: region.north
        )
    }

    private func pickFound(_ hit: PackSearchHit) {
        tool = nil
        showLayers = false
        compass.markSearchHit(hit)
        switch PackFind.action(
            destination: hit.coordinate,
            origin: originCoordinate,
            pack: packService.routing,
            profile: navigate.profile
        ) {
        case .route:
            compass.end()
            navigate.pick(hit, origin: originCoordinate, pack: packService.routing)
        case .lockOn:
            navigate.end()
            let point = CompassLockWaypoint(
                id: hit.id,
                name: hit.title,
                latitude: hit.coordinate.latitude,
                longitude: hit.coordinate.longitude,
                kind: .poi
            )
            UserDefaults.standard.set(false, forKey: BlackoutKeys.lastUsedTBT)
            _ = compass.lockOn(point)
            applyLockHeading()
            reportNavLock()
        }
    }

    private var canFollowGuidance: Bool {
        location.authorization == .authorized && location.navigationFix?.hasCoordinate == true
    }

    private var packContainsSelf: Bool {
        guard let pack = packService.pack, let fix = location.navigationFix, fix.hasCoordinate else {
            return false
        }
        return pack.region.contains(latitude: fix.latitude!, longitude: fix.longitude!)
    }

    private var liveManeuver: Maneuver? {
        guard navigate.phase == .guidance,
              let maneuver = navigate.tick?.nextManeuver,
              RoadLook.isActiveTurn(maneuver.kind) else {
            return nil
        }
        return maneuver
    }

    private var showsNavigateBanner: Bool {
        navigate.phase == .preview || navigate.phase == .guidance || navigate.empty != nil || !navigate.hits.isEmpty
    }

    @ViewBuilder
    private var navigateChrome: some View {
        let nav = Bindable(navigate)
        VStack(alignment: .leading, spacing: 8) {
            if navigate.phase == .guidance {
                NavigateGuidanceBar(
                    tick: navigate.tick,
                    route: navigate.activeRoute,
                    muted: navigate.muted,
                    noGPS: !canFollowGuidance,
                    onMute: { navigate.toggleMute() },
                    onEnd: { navigate.end() }
                )
            } else if navigate.phase == .preview, let route = navigate.preview {
                NavigatePreviewCard(
                    profile: nav.profile,
                    route: route,
                    label: navigate.destinationLabel ?? "Destination",
                    attribution: packService.routing?.manifest.attribution,
                    canStart: canFollowGuidance,
                    noGPS: location.authorization == .denied || location.authorization == .restricted,
                    onStart: {
                        headingUp = true
                        UserDefaults.standard.set(true, forKey: BlackoutKeys.radarHeadingUp)
                        UserDefaults.standard.set(true, forKey: BlackoutKeys.lastUsedTBT)
                        navigate.start(canFollow: canFollowGuidance)
                        refreshGuidance()
                        reportNavLock()
                    },
                    onCancel: { navigate.end() }
                )
            } else if !navigate.hits.isEmpty {
                NavigateHitsList(hits: navigate.hits, onPick: pickFound)
            }
        }
    }

    private var navQueryBinding: Binding<String> {
        Binding(
            get: { navigate.query },
            set: { navigate.query = $0 }
        )
    }

    private var fieldHeadingUp: Bool { headingUp || compass.isLocked }

    private func applyLockHeading() {
        headingUp = true
        UserDefaults.standard.set(true, forKey: BlackoutKeys.radarHeadingUp)
        if !pinnedToPackCoverage {
            centerToken += 1
        }
    }

    private func refreshGuidance() {
        navigate.update(
            position: originCoordinate,
            pack: packService.routing,
            canFollow: canFollowGuidance
        )
        compass.refreshFix(origin: originCoordinate, heading: location.headingDegrees)
        if navigate.phase == .guidance, packContainsSelf, !pinnedToPackCoverage {
            centerToken += 1
        }
    }

    private var gpsAccuracyMeters: Double? {
        guard let fix = location.navigationFix, fix.hasCoordinate,
              let meters = fix.horizontalAccuracyMeters,
              meters >= 0, meters.isFinite else { return nil }
        return meters
    }

    private var nowOffset: TimeInterval {
        Date().timeIntervalSinceReferenceDate
    }

    private func noteMapActivity() {
        applyChrome { $0.noteActivity(at: nowOffset) }
    }

    private func applyChrome(_ mutate: (inout MapChromeRecede) -> Void) {
        var next = chrome
        mutate(&next)
        if next != chrome {
            chrome = next
        }
    }

    private func recenterToPack() {
        noteMapActivity()
        pinnedToPackCoverage = true
        resolvePaintPack()
        resetToken += 1
    }

    private func resolvePaintPack() {
        packService.replaceInstalledRoots(installedPackRoots)
        let before = packService.pack?.rootURL.standardizedFileURL.path
        let fix = resolveCoordinate
        _ = coverageRegions
        packService.resolve(
            latitude: fix?.hasCoordinate == true ? fix?.latitude : nil,
            longitude: fix?.hasCoordinate == true ? fix?.longitude : nil
        )
        navigate.routingTooNew = packService.routingTooNew
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
        if showViewshed, packService.hasDEM, let fix = viewshedOrigin, fix.hasCoordinate {
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
                openOutingName = open.name
                outingStartLatitude = open.startLatitude
                outingStartLongitude = open.startLongitude
                crumbs = try persistence.breadcrumbs(expeditionID: open.id)
            } else {
                openOutingName = nil
                outingStartLatitude = nil
                outingStartLongitude = nil
                crumbs = []
            }
        } catch {
            openOutingName = nil
            outingStartLatitude = nil
            outingStartLongitude = nil
            crumbs = []
        }
    }

    private var fieldToolsRow: some View {
        HStack(spacing: 8) {
            let canShare = FollowTrackWire.canShare(crumbs: crumbs)
            MetalButton(FollowTrackWire.shareLabel, height: BlackoutDS.Hit.sm) {
                onShareTrack?(crumbs)
            }
            .disabled(!canShare)
            .opacity(canShare ? 1 : FollowTrackWire.disabledOpacity)
            MetalButton(searchKind.title, height: BlackoutDS.Hit.sm) {
                let all = SearchPatternKind.allCases
                if let idx = all.firstIndex(of: searchKind) {
                    searchKind = all[(idx + 1) % all.count]
                }
            }
            MetalButton(searchActive ? "Stop search" : "Start search", height: BlackoutDS.Hit.sm) {
                toggleSearch()
            }
            MetalButton(nightRed ? "Night on" : "Night red", height: BlackoutDS.Hit.sm) {
                nightRed.toggle()
                onNightRedChange?(nightRed)
            }
        }
    }

    private func fieldModePlate(_ mode: FieldJobMode) -> some View {
        HUDPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text(mode.title)
                    .font(BlackoutDS.titleFont())
                ForEach(mode.steps, id: \.self) { step in
                    Text(step)
                        .font(BlackoutDS.bodyFont())
                        .foregroundStyle(BlackoutDS.Silver.mid)
                }
                HStack(spacing: 8) {
                    MetalButton(FieldPing.label(.coming), height: BlackoutDS.Hit.sm) {
                        onPingReply?(.coming)
                    }
                    MetalButton(FieldPing.label(.hold), height: BlackoutDS.Hit.sm) {
                        onPingReply?(.hold)
                    }
                    MetalButton(FieldPing.label(.cant), height: BlackoutDS.Hit.sm) {
                        onPingReply?(.cant)
                    }
                }
                MetalButton("Navigate to last pin", height: BlackoutDS.Hit.sm) {
                    if let pin = location.manualPin ?? lastPeerPin, pin.hasCoordinate {
                        lockOrRoute(latitude: pin.latitude!, longitude: pin.longitude!, label: mode.title)
                    }
                }
                MetalButton("Field Guide", height: BlackoutDS.Hit.sm) {
                    onOpenGuide?(mode.articleID)
                }
                GhostButton("Exit", height: BlackoutDS.Hit.sm) {
                    fieldMode = nil
                }
            }
        }
    }

    private var lastPeerPin: LocationFix? {
        if let inbound = latestInbound, inbound.hasCoordinate {
            return LocationFix(latitude: inbound.latitude, longitude: inbound.longitude)
        }
        if let stale = roster.peers.first(where: { PartyThread.isStale(lastHeard: $0.updatedAt) }),
           stale.latitude != nil {
            return LocationFix(latitude: stale.latitude, longitude: stale.longitude)
        }
        return nil
    }

    private func toggleSearch() {
        if searchActive {
            searchActive = false
            searchLine = []
            return
        }
        guard let region = packService.pack?.region else { return }
        guard let origin = searchOrigin, origin.hasCoordinate else { return }
        searchLine = SearchPattern.polyline(
            kind: searchKind,
            originLatitude: origin.latitude!,
            originLongitude: origin.longitude!,
            region: region
        )
        searchActive = true
    }

    private var searchOrigin: LocationFix? {
        if let inbound = latestInbound, inbound.hasCoordinate {
            return LocationFix(latitude: inbound.latitude, longitude: inbound.longitude)
        }
        if let stale = roster.peers.first(where: { PartyThread.isStale(lastHeard: $0.updatedAt) }),
           let lat = stale.latitude, let lon = stale.longitude {
            return LocationFix(latitude: lat, longitude: lon)
        }
        if let pin = location.manualPin, pin.hasCoordinate { return pin }
        return location.navigationFix
    }

    private func applySharedTrackIfNeeded() {
        guard sharedTrack.count >= 2, let last = sharedTrack.last else { return }
        lockOrRoute(latitude: last.latitude, longitude: last.longitude, label: "Shared track")
    }
}

enum MapTool: String, Identifiable {
    case navigate, radar, topo, civilization, water
    var id: String { rawValue }
}

/// Fade chrome in place. Opacity only — VoiceOver keeps the controls in the tree.
private struct RecedingMapChrome: ViewModifier {
    var isReceded: Bool
    var reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isReceded && !reduceMotion ? 0 : 1)
            .allowsHitTesting(!(isReceded && !reduceMotion))
            .animation(
                reduceMotion ? nil : (isReceded ? BlackoutDS.Motion.move : BlackoutDS.Motion.snap),
                value: isReceded
            )
    }
}

/// Thin outing strip. Recedes with the GPS HUD. Members stay on Map radar.
struct MapExpeditionBanner: View {
    var title: String

    var body: some View {
        Text(title)
            .font(BlackoutDS.captionFont())
            .foregroundStyle(BlackoutDS.Silver.bright)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .frame(height: 28)
            .background(BlackoutDS.Surface.raised.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityLabel(title)
    }
}

struct MapScaleBar: View {
    var metersPerPoint: Double

    var body: some View {
        let meters = MapScaleBarMath.niceMeters(metersPerPoint: metersPerPoint)
        let width = CGFloat(meters / max(metersPerPoint, 0.001))
        VStack(alignment: .leading, spacing: 4) {
            Rectangle()
                .fill(BlackoutDS.Silver.edge)
                .frame(width: min(max(width, 24), 120), height: 2)
            Text(label)
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
        }
        .accessibilityLabel("Scale \(label)")
    }

    private var label: String {
        let meters = MapScaleBarMath.niceMeters(metersPerPoint: metersPerPoint)
        if meters >= 1_000 {
            return "\(Int((meters / 1_000).rounded())) km"
        }
        return "\(Int(meters.rounded())) m"
    }
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

/// Native metal notice. Eyebrow MAP. One card. Red-eye O only on no-pack. No Skip, no shadow.
struct MapEmptyCard: View {
    var kind: MapEmptyKind
    var onPacks: (() -> Void)? = nil
    var onRecenter: (() -> Void)? = nil
    var fillsSpace: Bool = true

    var body: some View {
        Group {
            if fillsSpace {
                VStack {
                    Spacer().allowsHitTesting(false)
                    plate
                    Spacer().allowsHitTesting(false)
                }
                .padding(.bottom, BlackoutDS.Hit.sos + BlackoutDS.Vitals.sosGap + 4)
            } else {
                plate
            }
        }
        .animation(nil, value: kind)
    }

    private var plate: some View {
        VStack(alignment: .leading, spacing: 12) {
            if kind.showsRedEyeO {
                RedEyeOMark(point: CGFloat(BrandChromeLock.noPackRedEye))
            }
            Text(MapEmptyCopy.eyebrow)
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
            Text(kind.title)
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
                .fixedSize(horizontal: false, vertical: true)
            if kind == .noPack || kind == .packTooNew {
                if kind == .noPack {
                    Text(MapEmptyCopy.noTiles)
                        .font(BlackoutDS.bodyFont())
                        .foregroundStyle(BlackoutDS.Silver.mid)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if let onRecenter {
                        MetalButton("Recenter", height: BlackoutDS.Hit.md, action: onRecenter)
                    }
                    if let onPacks {
                        MetalButton("Packs", height: BlackoutDS.Hit.md, action: onPacks)
                    }
                }
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
    }
}

struct MapLayersSheet: View {
    @Binding var radarOn: Bool
    @Binding var headingUp: Bool
    @Binding var sweepAudio: Bool
    @Binding var showSlope: Bool
    @Binding var showViewshed: Bool
    var extrasOn: Bool
    var hasDEM: Bool
    @Binding var nightRed: Bool
    var nearbyPeerCount: Int
    var relayableReadyIDs: [String]
    var onToggleNightRed: () -> Void
    var onSendPack: ((String) -> Void)?
    @Binding var showTopoTiles: Bool
    @Binding var showTrails: Bool
    var hasRouting: Bool
    @Binding var searchQuery: String
    var searchHits: [PackSearchHit]
    var navigateEnabled: Bool
    var lidarSupported: Bool
    var onToggleSlope: () -> Void
    var onToggleViewshed: () -> Void
    var onToggleHeading: () -> Void
    var onToggleAudio: () -> Void
    var onToggleTopo: () -> Void
    var onToggleTrails: () -> Void
    var onSearch: () -> Void
    var onPickSearch: (PackSearchHit) -> Void
    var onOpenLiDAR: () -> Void
    var onOpenTool: (MapTool) -> Void
    var onFind: (PackFindMode) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ScreenHeader("Layers")
                    layerToggle("Radar", on: $radarOn, enabled: extrasOn, persist: {})
                    layerToggle("Topo", on: $showTopoTiles, enabled: extrasOn && hasRouting, persist: onToggleTopo)
                    layerToggle("Trail", on: $showTrails, enabled: extrasOn && hasRouting, persist: onToggleTrails)
                    layerToggle("Slope", on: $showSlope, enabled: extrasOn, persist: onToggleSlope)
                    layerToggle("Viewshed", on: $showViewshed, enabled: extrasOn && hasDEM, persist: onToggleViewshed)
                    if extrasOn, !hasDEM {
                        Text(ViewshedPolicy.noDEM)
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(BlackoutDS.Silver.steel)
                    }
                    layerToggle("Night red", on: $nightRed, enabled: true, persist: onToggleNightRed)
                    if extrasOn, PackRelayPolicy.sendEnabled(nearbyPeerCount: nearbyPeerCount) {
                        ForEach(relayableReadyIDs, id: \.self) { id in
                            MetalButton("\(PackRelayPolicy.sendLabel) \(id)", height: BlackoutDS.Hit.sm) {
                                onSendPack?(id)
                            }
                        }
                    }
                    if extrasOn {
                        TextField("Search this pack", text: $searchQuery)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Silver.bright)
                            .submitLabel(.search)
                            .onSubmit(onSearch)
                            .padding(.horizontal, 16)
                            .frame(height: BlackoutDS.Hit.md)
                            .background(BlackoutDS.Surface.raised.opacity(0.82))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        if !searchHits.isEmpty {
                            NavigateHitsList(hits: searchHits, onPick: onPickSearch)
                        }
                    }
                    if lidarSupported, extrasOn {
                        GhostButton("LiDAR", height: BlackoutDS.Hit.md, action: onOpenLiDAR)
                    }
                    if navigateEnabled {
                        GhostButton("Navigate", height: BlackoutDS.Hit.md) { onOpenTool(.navigate) }
                    }
                    if extrasOn {
                        GhostButton("Topo", height: BlackoutDS.Hit.md) { onOpenTool(.topo) }
                        GhostButton(PackFindCopy.civilization, height: BlackoutDS.Hit.md) {
                            onFind(.civilization)
                        }
                        GhostButton(PackFindCopy.water, height: BlackoutDS.Hit.md) {
                            onFind(.water)
                        }
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

enum MapShareSheet {
    static func present(_ text: String) {
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.keyWindow?.rootViewController ?? scene.windows.first?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        if let pop = activity.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        }
        top.present(activity, animated: true)
    }
}
