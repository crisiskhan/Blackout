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

    @State private var tool: MapTool?
    @State private var crumbs: [BreadcrumbRecordDTO] = []
    @State private var outsidePack = false
    @State private var resetToken = 0
    @State private var centerToken = 0
    @State private var headingUp = UserDefaults.standard.bool(forKey: BlackoutKeys.radarHeadingUp)
    @State private var wasOffRoute = false
    @State private var offCourseHaptic = WalkOffCourseHaptic()
    @State private var sweepAudio = UserDefaults.standard.bool(forKey: BlackoutKeys.radarSweepAudio)
    @State private var showViewshed = MapChromeLock.initsViewshedOnLaunch
    @State private var showSlope = MapChromeLock.initsSlopeOnLaunch
    @State private var selectedPeer: RadarBlip?
    @State private var showLiDAR = MapChromeLock.initsLiDAROnLaunch
    @State private var showSatellite = MapChromeLock.aerialOverlayDefaultOn
    @State private var showSearchHits = false
    @State private var showSearchDropdown = false
    @State private var searchPickConsumed = false
    @FocusState private var searchFocused: Bool
    @State private var selectedPOI: RoutingPOI?
    @State private var jumpToken = 0
    @State private var jumpCoordinate: RoutingCoordinate?
    @State private var showStreets = MapChromeLock.streetsLayerDefaultOn
    @State private var showTopoTiles = MapChromeLock.contoursLayerDefaultOn
    @State private var showTrails = MapChromeLock.trailsLayerDefaultOn
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var navigate = NavigateSession()
    @State private var compass = CompassLockSession()
    @State private var viewshedRays: [ViewshedRay] = []
    @State private var slopeSamples: [SlopeSample] = []
    @State private var pinnedToPackCoverage = false
    @State private var userMovedCamera = false
    @State private var chrome = MapChromeRecede()
    @State private var metersPerPoint = 10.0
    @State private var openOutingName: String?
    @State private var outingStartLatitude: Double?
    @State private var outingStartLongitude: Double?
    @State private var toolHint: String?
    @State private var torch = MapTorchController()
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
            || showSearchHits
            || selectedPOI != nil
            || showLiDAR
            || selectedPeer != nil
            || showEmptyCard
            || navigate.phase == .preview
            || (navigate.empty != nil && navigate.empty != .searchMiss)
            || liveRec
            || compass.showMarkSheet
            || showSearchDropdown
            || MapPackSearchPolicy.holdChrome(
                existingHold: false,
                fieldFocused: searchFocused,
                searchMiss: navigate.empty == .searchMiss
            )
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
                resolvePaintPack()
                refreshGuidance()
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
            .sheet(isPresented: $showSearchHits, content: packSearchHitsSheet)
            .sheet(item: $selectedPOI, content: poiNameSheet)
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
            .onChange(of: searchFocused) { _, focused in
                if focused {
                    searchPickConsumed = false
                }
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
                    nearbyPeerCount: mesh.nearbyPeerCount,
                    sweepAudio: sweepAudio
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

    private func poiNameSheet(_ poi: RoutingPOI) -> some View {
        MapPOINameSheet(name: poi.name, kind: poi.kind)
            .presentationDetents([.height(120)])
            .presentationDragIndicator(.visible)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
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
            showViewshed: false,
            viewshedOrigin: viewshedOrigin,
            showSlope: false,
            centerToken: centerToken,
            pinCameraToPack: pinnedToPackCoverage,
            routing: packService.routing,
            routeLine: navigate.routePolyline,
            destination: navigate.destination ?? compass.lockCoordinate,
            showPackTiles: showSatellite,
            showStreets: showStreets,
            showTopoTiles: showTopoTiles,
            showTrails: showTrails,
            jumpToken: jumpToken,
            jumpCoordinate: jumpCoordinate,
            headingDegrees: location.headingDegrees,
            headingUp: MapChromeLock.appliesHeadingUp(
                walkActive: navigate.phase == .guidance,
                headingUp: headingUp
            ),
            outingStart: outingStart.map {
                RoutingCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            },
            accuracyMeters: gpsAccuracyMeters,
            packContainsSelf: packContainsSelf,
            activeManeuver: liveManeuver,
            inboundPing: openInboundPingFix,
            inboundPingHue: openInbound?.hue,
            searchPattern: [],
            sharedTrack: sharedTrack,
            amenityPins: amenityPinModels,
            markPins: destMarkSearchPins,
            onDropPin: { lat, lon in
                location.dropManualPin(latitude: lat, longitude: lon)
            },
            onTap: { lat, lon in
                noteMapActivity()
                guard MapChromeLock.tapPinShowsNameSheet else { return }
                if let poi = PackAmenityPolicy.pinHit(
                    latitude: lat,
                    longitude: lon,
                    pins: amenityPinModels,
                    zoom: 12
                ) {
                    selectedPOI = poi
                }
            },
            onUserInteract: {
                userMovedCamera = true
                pinnedToPackCoverage = false
                noteMapActivity()
            },
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
        } else if let empty = navigate.empty, navigate.phase != .guidance, empty != .searchMiss {
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

    private var routeInPlay: Bool {
        compass.isLocked
            || compass.target != nil
            || navigate.phase == .preview
            || navigate.phase == .guidance
    }

    private var lockOnHeading: Double? {
        CompassLockMath.lockHeading(
            origin: originCoordinate,
            dest: navigate.destination ?? compass.lockCoordinate,
            fallback: compass.headingDegrees ?? location.headingDegrees
        )
    }

    private var mapLockChrome: some View {
        VStack(spacing: 0) {
            lockHudStack
            if showChipRow, battery.coarseNavigateEnabled, showsNavigateBanner {
                navigateChrome
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            if MapChromeLock.paintsWalkScaleAndCompass, navigate.phase == .guidance {
                walkCompassScale
            }
            Spacer()
            if showChipRow, MapChromeLock.showsRightEdgeChips(searchFocused: searchFocused) {
                HStack(alignment: .bottom, spacing: 0) {
                    Spacer(minLength: 0)
                    rightEdgeStack
                }
                .padding(.trailing, 12)
                .padding(.bottom, CGFloat(MapChromeLock.sosDiameter) + BlackoutDS.Vitals.sosGap)
            }
            pingStrip
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
        VStack(spacing: 8) {
            receding(keepInteractive: searchFocused) {
                VStack(alignment: .leading, spacing: 8) {
                    if routeInPlay {
                        CompassLockOnHeader(headingDegrees: lockOnHeading)
                            .padding(.horizontal, -16)
                    } else {
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
                    }
                    if showChipRow, !(MapChromeLock.hidesSearchDuringWalk && navigate.phase == .guidance) {
                        mapPackSearch
                        if showSearchDropdown {
                            MapPackSearchDropdown(
                                hits: navigate.hits,
                                empty: navigate.empty,
                                onPick: { pickFound($0) },
                                onDismiss: dismissSearchResults
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var mapPackSearch: some View {
        MapPackSearchField(
            query: navQueryBinding,
            onSubmit: {
                searchDebounceTask?.cancel()
                runPackSearch(present: true)
            },
            onQueryChange: {
                if searchPickConsumed { return }
                guard searchFocused else { return }
                searchDebounceTask?.cancel()
                searchDebounceTask = Task { @MainActor in
                    let started = Date()
                    let nanos = UInt64(MapPackSearchPolicy.searchDebounceMilliseconds * 1_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                    guard !Task.isCancelled else { return }
                    let elapsedMs = Date().timeIntervalSince(started) * 1000
                    guard MapPackSearchPolicy.shouldRunQuerySearch(elapsedMs: elapsedMs) else { return }
                    runPackSearch(present: false)
                }
            },
            isFocused: $searchFocused
        )
    }

    private func runPackSearch(present: Bool) {
        noteMapActivity()
        navigate.search(
            pack: packService.routing,
            pois: packService.pack?.pois ?? [],
            addresses: packService.pack?.addresses ?? []
        )
        let hitCount = navigate.hits.count
        let empty = navigate.empty != nil
        if present {
            if MapPackSearchPolicy.shouldPickOnSubmit(hitCount: hitCount),
               let hit = navigate.hits.first {
                pickFound(hit)
                return
            }
            showSearchHits = false
            showSearchDropdown = MapPackSearchPolicy.presentsDropdown(
                query: navigate.query,
                hitCount: hitCount,
                empty: empty,
                submitted: true,
                picked: searchPickConsumed
            )
        } else {
            showSearchHits = false
            showSearchDropdown = MapPackSearchPolicy.presentsDropdown(
                query: navigate.query,
                hitCount: hitCount,
                empty: empty,
                submitted: false,
                picked: searchPickConsumed
            )
        }
    }

    private func dismissSearchResults() {
        searchDebounceTask?.cancel()
        showSearchHits = false
        showSearchDropdown = false
        searchFocused = false
    }

    private func packSearchHitsSheet() -> some View {
        MapPackSearchSheet(hits: navigate.hits, empty: navigate.empty, onPick: { hit in
            dismissSearchResults()
            pickFound(hit)
        })
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var rightEdgeStack: some View {
        receding {
            switch MapRightEdge.stack(routeInPlay: routeInPlay) {
            case .nav:
                CompassLockBar(
                    isLocked: compass.isLocked,
                    hasTarget: compass.target != nil,
                    onSpeak: {
                        noteMapActivity()
                        if navigate.phase == .guidance {
                            navigate.speakNow()
                        } else {
                            compass.speakOnce()
                        }
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
            case .chips:
                chipColumn
            }
        }
    }

    private var walkCompassScale: some View {
        receding {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    MapWalkCompass(headingDegrees: location.headingDegrees)
                    Text(
                        WalkChrome.scaleLine(
                            meters: MapScaleBarMath.niceMeters(metersPerPoint: metersPerPoint),
                            etaSeconds: navigate.tick?.etaSeconds ?? navigate.activeRoute?.etaSeconds ?? 0
                        )
                    )
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.bright)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
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

    private var chipColumn: some View {
        VStack(spacing: CGFloat(MapChromeLock.chipGap)) {
            MapHUDChip("Recenter", systemName: "location.north.line", action: recenterToPack)
                .opacity(
                    MapChromeLock.recenterOpacity(
                        onCenter: MapChromeLock.cameraIsOnCenter(
                            userMovedCamera: userMovedCamera,
                            gpsLocked: gpsAccuracyMeters != nil
                        )
                    )
                )
                .allowsHitTesting(
                    MapChromeLock.recenterOpacity(
                        onCenter: MapChromeLock.cameraIsOnCenter(
                            userMovedCamera: userMovedCamera,
                            gpsLocked: gpsAccuracyMeters != nil
                        )
                    ) > 0
                )
            MapHUDChip("Find civ", systemName: "building.2") {
                noteMapActivity()
                tool = .civilization
            }
            MapHUDChip("Water", systemName: "drop") {
                noteMapActivity()
                tool = .water
            }
            MapHUDChip("Packs", systemName: "shippingbox") {
                noteMapActivity()
                onOpenFieldPacks?()
            }
            MapHUDChip("Satellite", systemName: "globe") {
                noteMapActivity()
                showSatellite.toggle()
            }
        }
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

    private func receding<Content: View>(
        keepInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .modifier(
                RecedingMapChrome(
                    isReceded: chrome.isReceded,
                    reduceMotion: reduceMotion,
                    keepInteractive: keepInteractive
                )
            )
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
        searchPickConsumed = true
        tool = nil
        dismissSearchResults()
        pinnedToPackCoverage = false
        let origin = originCoordinate
        navigate.pick(hit, origin: origin, pack: packService.routing)
        let routed = navigate.phase == .preview
        if MapPackSearchPolicy.pickAutoStartsGuidance, navigate.preview != nil {
            headingUp = true
            UserDefaults.standard.set(true, forKey: BlackoutKeys.radarHeadingUp)
            UserDefaults.standard.set(true, forKey: BlackoutKeys.lastUsedTBT)
            navigate.start(canFollow: canFollowGuidance)
            refreshGuidance()
        } else if MapPackSearchPolicy.locksCompassWhenNoRoute(
            hasOrigin: origin != nil,
            hasGraphRoute: routed
        ) {
            let point = CompassLockWaypoint(
                id: hit.id,
                name: hit.title,
                latitude: hit.coordinate.latitude,
                longitude: hit.coordinate.longitude,
                kind: .poi
            )
            _ = compass.lockOn(point)
            applyLockHeading()
        }
        jumpCoordinate = hit.coordinate
        jumpToken += 1
        userMovedCamera = true
        reportNavLock()
    }

    private var amenityPinModels: [RoutingPOI] {
        let mapped = (packService.pack?.pois ?? []).compactMap { poi -> RoutingPOI? in
            guard PackAmenityPolicy.paintsOnMap(poi.kind) else { return nil }
            return RoutingPOI(
                id: poi.id,
                name: poi.name,
                kind: poi.kind,
                coordinate: RoutingCoordinate(latitude: poi.latitude, longitude: poi.longitude)
            )
        }
        return PackAmenityPolicy.cap(mapped)
    }

    /// Dest, MARK, and the last search pick. Pack pins only.
    private var destMarkSearchPins: [RoutingCoordinate] {
        var pins: [RoutingCoordinate] = []
        if let dest = navigate.destination ?? compass.lockCoordinate {
            pins.append(dest)
        }
        for mark in compass.marks {
            pins.append(mark.coordinate)
        }
        if let poi = selectedPOI {
            pins.append(poi.coordinate)
        }
        return pins
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
        navigate.phase == .preview || navigate.phase == .guidance || navigate.empty != nil
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
                if MapChromeLock.walkShowsEndUnderTurnPlate {
                    GhostButton("End", height: 36, action: { navigate.end() })
                }
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
            }
        }
    }

    private var navQueryBinding: Binding<String> {
        Binding(
            get: { navigate.query },
            set: { navigate.query = $0 }
        )
    }

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
        let nowOffRoute = navigate.phase == .guidance && navigate.tick?.offRoute == true
        if navigate.phase == .guidance {
            offCourseHaptic.prepare()
        }
        if MapChromeLock.shouldFireOffCourseHaptic(wasOffRoute: wasOffRoute, nowOffRoute: nowOffRoute) {
            offCourseHaptic.fire()
        }
        wasOffRoute = nowOffRoute
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
        userMovedCamera = false
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

    private func applySharedTrackIfNeeded() {
        guard sharedTrack.count >= 2, let last = sharedTrack.last else { return }
        lockOrRoute(latitude: last.latitude, longitude: last.longitude, label: "Shared track")
    }
}

@MainActor
final class WalkOffCourseHaptic {
    private let generator = UINotificationFeedbackGenerator()

    func prepare() {
        generator.prepare()
    }

    func fire() {
        generator.notificationOccurred(.warning)
        generator.prepare()
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
    var keepInteractive: Bool = false

    func body(content: Content) -> some View {
        let hittable = MapPackSearchPolicy.recedeAllowsHitTesting(
            isReceded: isReceded,
            fieldFocused: keepInteractive,
            reduceMotion: reduceMotion
        )
        let hide = isReceded && !reduceMotion && !keepInteractive
        content
            .opacity(hide ? 0 : 1)
            .allowsHitTesting(hittable)
            .animation(
                reduceMotion ? nil : (isReceded ? BlackoutDS.Motion.move : BlackoutDS.Motion.snap),
                value: isReceded
            )
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

/// Walk-only compass. Idle Map keeps the tiny GPS chip.
struct MapWalkCompass: View {
    var headingDegrees: Double?

    var body: some View {
        ZStack {
            Circle()
                .fill(BlackoutDS.Surface.raised.opacity(0.82))
                .overlay(Circle().stroke(BlackoutDS.Silver.edge, lineWidth: 0.5))
            VStack(spacing: 0) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
                Text("N")
                    .font(.system(size: 11, weight: .bold, design: .default))
            }
            .foregroundStyle(BlackoutDS.Silver.bright)
            .rotationEffect(.degrees(-(headingDegrees ?? 0)))
        }
        .frame(width: 36, height: 36)
        .accessibilityLabel("Compass")
    }
}

/// Tiny GPS accuracy + north-up. Not a full-width 56h bar.
struct MapLockHUD: View {
    var accuracyMeters: Double?
    var headingDegrees: Double?
    var onNorthUp: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: accuracyMeters == nil ? "location.slash" : "location.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accuracyMeters == nil ? BlackoutDS.Silver.steel : BlackoutDS.Semantic.ok)
            Text(accuracyLabel)
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
                .accessibilityLabel(accuracyMeters == nil ? "NO FIX" : accuracyLabel)
            Button(action: onNorthUp) {
                Image(systemName: "location.north.line")
                    .font(.system(size: 13, weight: .semibold))
                    .rotationEffect(.degrees(-(headingDegrees ?? 0)))
                    .foregroundStyle(BlackoutDS.Silver.metal)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("North-up")
        }
        .padding(.horizontal, 8)
        .frame(height: CGFloat(MapChromeLock.lockHUDPaintedHeight))
        .metalPlate(.inset, cornerRadius: MetalPlate.railCorner)
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

/// Compact pin name. Not a MetalButton slab.
struct MapPOINameSheet: View {
    var name: String
    var kind: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            if !kind.isEmpty {
                Text(kind)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BlackoutDS.Surface.raised)
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
