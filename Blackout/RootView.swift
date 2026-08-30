import BlackoutBattery
import BlackoutCore
import BlackoutLocation
import BlackoutPacks
import DesignSystem
import Expeditions
import Field
import Maps
import Messaging
import Settings
import SOS
import SwiftUI
import VoicePTT

enum AppDestination: String, Hashable, CaseIterable, Identifiable {
    case map
    case comms
    case field
    case expedition

    var id: String { rawValue }

    var title: String {
        switch self {
        case .map: return "Map"
        case .comms: return "Comms"
        case .field: return "Field"
        case .expedition: return "Expedition"
        }
    }

    var symbol: String {
        switch self {
        case .map: return "map"
        case .comms: return "antenna.radiowaves.left.and.right"
        case .field: return "leaf"
        case .expedition: return "flag"
        }
    }
}

struct RootView: View {
    @Bindable var container: AppContainer
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var destination: AppDestination = .map
    @State private var showSettings = false
    @State private var pendingDM: BlackoutID?
    @State private var pendingPingNav: FieldPingNav?
    @State private var pendingGuideJob: GuideMapJob?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            BlackoutDS.Surface.void.ignoresSafeArea()
            if container.lock.isEnabled && !container.lock.isUnlocked {
                LockGateView(lock: container.lock)
            } else {
                chrome
                // SOS stays a ZStack sibling of TabView (`RootChromeLock.sosPlacement`).
                // Tab switches must not remount the 88pt disk.
                if let bootError = container.bootError {
                    VStack {
                        StoreFailure(bootError)
                            .padding(.horizontal, 16)
                            .padding(.top, sizeClass == .regular ? 12 : 72)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
                sosOverlay
                CameraControlPTTCatcher()
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                if container.showRadioBanner {
                    radioBannerOverlay
                }
                if sizeClass != .regular, !container.battery.isCritical {
                    settingsOverlay
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: container.nightRed) { _, _ in
            // Night red is not light mode. Scheme stays dark.
        }
        .sheet(isPresented: settingsSheetBinding) {
            SettingsRootView(
                battery: container.battery,
                location: container.location,
                mesh: container.mesh,
                lock: container.lock,
                callsign: container.party.identity.callsign,
                onFieldPacks: {
                    showSettings = false
                    destination = .expedition
                }
            )
            .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                container.lock.lock()
            }
            if phase == .active {
                syncSensorsToBattery()
                container.refreshRadiosBanner()
                container.refreshLiveActivity()
                container.applyIdleTimer()
            }
        }
        .onChange(of: container.battery.isCritical) { _, _ in
            syncSensorsToBattery()
        }
        .onChange(of: container.sosCoverOpen) { _, _ in
            container.applyIdleTimer()
        }
        .onChange(of: container.ptt.isTransmitting) { _, _ in
            container.applyIdleTimer()
        }
        .onChange(of: container.ptt.lastHeardAt) { _, _ in
            container.applyIdleTimer()
        }
        .onChange(of: container.radios.cannotRun) { _, _ in
            container.refreshRadiosBanner()
        }
        .onChange(of: container.mesh.nearbyPeerCount) { _, _ in
            container.refreshLiveActivity()
        }
        .onOpenURL { url in
            if let next = container.applyDeepLink(url) {
                destination = next
            }
        }
        .onAppear {
            syncSensorsToBattery()
            container.refreshRadiosBanner()
            container.refreshLiveActivity()
            container.applyIdleTimer()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                container.expireInboundIfNeeded()
                container.refreshLiveActivity()
                container.applyIdleTimer()
            }
        }
    }

    private var radioBannerOverlay: some View {
        VStack {
            MeshRadioBannerView(
                title: container.radioBanner.title,
                bodyText: container.radioBanner.body,
                onOpenSettings: { AppSettingsLink.open() },
                onDismiss: { container.dismissRadioBanner() }
            )
            .padding(.horizontal, 16)
            .padding(.top, sizeClass == .regular ? 12 : 72)
            Spacer()
        }
        .allowsHitTesting(true)
    }

    /// QA Residual A: RootView reads `battery.isCritical` and unmounts Map / Comms / Field / Expedition.
    /// No TabView tabs, no iPad sidebar destinations, no gear overlay, no Settings sheet from this shell.
    @ViewBuilder
    private var chrome: some View {
        if container.battery.isCritical {
            CriticalSOSShell(container: container)
        } else if sizeClass == .regular {
            iPadSplit
        } else {
            iPhoneTabs
        }
    }

    private func syncSensorsToBattery() {
        if container.battery.isCritical {
            showSettings = false
            container.setLeaveBehindRelay(false)
            container.location.stopUpdating()
            container.mesh.stop()
            container.ptt.stop()
        } else {
            container.location.startUpdating()
            container.location.applyPolicy(container.battery.policy)
            container.ptt.extremeSaver = container.battery.isExtremeSaver
            container.syncMeshToParty()
        }
    }

    private var settingsSheetBinding: Binding<Bool> {
        Binding(
            get: { showSettings && !container.battery.isCritical },
            set: { showSettings = $0 }
        )
    }

    private var iPhoneTabs: some View {
        TabView(selection: $destination) {
            mapDestination
                .tabItem { Label(AppDestination.map.title, systemImage: AppDestination.map.symbol) }
                .tag(AppDestination.map)
            commsDestination
                .tabItem { Label(AppDestination.comms.title, systemImage: AppDestination.comms.symbol) }
                .tag(AppDestination.comms)
            fieldDestination
                .tabItem { Label(AppDestination.field.title, systemImage: AppDestination.field.symbol) }
                .tag(AppDestination.field)
            expeditionDestination
                .tabItem { Label(AppDestination.expedition.title, systemImage: AppDestination.expedition.symbol) }
                .tag(AppDestination.expedition)
        }
        .toolbarBackground(BlackoutDS.Surface.base, for: .tabBar)
        .tint(BlackoutDS.Silver.metal)
    }

    /// iOS `List(selection:)` takes `Binding<SelectionValue?>`. Keep `destination` non-optional for TabView.
    private var sidebarSelection: Binding<AppDestination?> {
        Binding(
            get: { destination },
            set: { if let value = $0 { destination = value } }
        )
    }

    private var iPadSplit: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                ForEach(AppDestination.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
            .navigationTitle("Blackout")
            .navigationSplitViewColumnWidth(min: 320, ideal: 320, max: 320)
            .swiftUIToolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BlackoutDS.Surface.base)
        } detail: {
            detail
                .swiftUIToolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detail: some View {
        switch destination {
        case .map: mapDestination
        case .comms: commsDestination
        case .field: fieldDestination
        case .expedition: expeditionDestination
        }
    }

    private var mapDestination: some View {
        MapsRootView(
            location: container.location,
            mesh: container.mesh,
            battery: container.battery,
            persistence: container.persistence,
            packService: container.pack,
            coverageRegions: container.packs.coverageRegions(bundled: container.pack.bundledRegion),
            installedPackRoots: container.packs.readyRoots,
            packReady: container.packs.readySnapshot,
            onOpenFieldPacks: { destination = .expedition },
            externalSheetOpen: showSettings,
            sosCoverOpen: container.sosCoverOpen,
            roster: container.party,
            onMessagePeer: { id in
                pendingDM = id
                destination = .comms
            },
            pendingPingNav: $pendingPingNav,
            latestInbound: container.latestInbound,
            onPingReply: { container.replyToLatest($0) },
            onNavLockChange: { on in
                container.navLockActive = on
                container.applyIdleTimer()
            },
            fieldMode: $container.fieldMode,
            nightRed: $container.nightRed,
            sharedTrack: container.sharedTrack,
            onShareTrack: { container.sendFollowTrack($0) },
            onSendPack: { container.relayPack($0) },
            onOpenGuide: { id in
                container.inboundGuideID = id
                destination = .field
            },
            onNightRedChange: { container.setNightRed($0) },
            pendingGuideJob: $pendingGuideJob
        )
        .swiftUIToolbar {
            if sizeClass != .regular {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .foregroundStyle(BlackoutDS.Silver.metal)
                }
            }
        }
    }

    private var commsDestination: some View {
        CommsRootView(
            outbox: container.outbox,
            mesh: container.mesh,
            roster: container.party,
            location: container.location,
            ptt: container.ptt,
            onOpenExpedition: { destination = .expedition },
            onNavigatePing: { nav in
                pendingPingNav = nav
                destination = .map
            },
            onPingReplied: { container.acknowledgeLatestPing() },
            pendingDM: $pendingDM
        )
        .swiftUIToolbar {
            if sizeClass != .regular {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    private var fieldDestination: some View {
        FieldRootView(
            location: container.location,
            battery: container.battery,
            packURL: container.guidePackURL,
            sosArmed: UserDefaults.standard.bool(forKey: BlackoutKeys.sosArmed),
            packReady: container.packs.readySnapshot,
            partySize: 1 + container.party.peerCount,
            openExpeditionID: container.openExpeditionID,
            inboundArticleID: container.inboundGuideID,
            inboundMissing: container.inboundGuideMissing,
            nearbyPeerCount: container.mesh.nearbyPeerCount,
            onSendArticle: { container.sendGuideCard($0) },
            onStartMode: { mode in
                container.startFieldMode(mode)
                destination = .map
            },
            onRelayPack: { container.relayPack($0) },
            onOpenMapJob: { job in
                pendingGuideJob = job
                destination = .map
            }
        )
    }

    private var expeditionDestination: some View {
        ExpeditionsRootView(
            persistence: container.persistence,
            location: container.location,
            roster: container.party,
            onBroadcast: { container.sendPartyStatus($0) },
            onCommitCallsign: { container.commitCallsign($0) },
            onCreateParty: { container.createParty() },
            onJoinParty: { container.joinParty($0) },
            onLeaveParty: { container.leaveParty() },
            leaveBehindOn: container.leaveBehindRelay,
            nightRed: container.nightRed,
            onLeaveBehind: { container.setLeaveBehindRelay($0) },
            onNightRed: { container.setNightRed($0) },
            onStartFieldMode: { mode in
                container.startFieldMode(mode)
                destination = .map
            }
        ) {
            FieldPackCatalogList(
                store: container.packs,
                nearbyCount: container.mesh.nearbyPeerCount,
                onSendToPeer: { container.relayPack($0) }
            )
        }
    }

    private var sosOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                SOSFab(
                    location: container.location,
                    persistence: container.persistence,
                    mesh: container.mesh,
                    battery: container.battery,
                    roster: container.party,
                    presentConfirm: $container.sosConfirmRequested,
                    coverOpen: $container.sosCoverOpen
                )
                .padding(.trailing, 16)
                .padding(.bottom, fabBottomPadding)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(true)
    }

    /// Same 88pt SOS on Map / Comms / Field / Expedition — RootView sibling, not inside TabView.
    /// Not Map-only, not a nav-bar chip, not a tab. `RootChromeLock.sosIsRootViewSibling`.
    /// Compact 4-tab: 8pt above the tab bar, 16pt trailing. Critical / iPad: 8pt above home indicator.
    /// Never recedes with Map HUD. Last-2% CriticalSOSShell still shows the FAB.
    private var fabBottomPadding: CGFloat {
        let hasTabBar = sizeClass != .regular && !container.battery.isCritical
        return BlackoutDS.Vitals.sosGap
            + (hasTabBar ? BlackoutDS.Vitals.tabBar : 0)
            + BlackoutDS.Vitals.homeIndicator
    }

    private var settingsOverlay: some View {
        VStack {
            HStack {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(BlackoutDS.Silver.metal)
                        .frame(width: BlackoutDS.Hit.sm, height: BlackoutDS.Hit.sm)
                        .background(BlackoutDS.Surface.raised.opacity(0.82))
                        .overlay(Circle().stroke(BlackoutDS.Silver.edge, lineWidth: 0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.top, 8)
                Spacer()
            }
            Spacer()
        }
        .allowsHitTesting(true)
    }
}

/// Last-2% shell. Does not construct OfflineMapView, tiles, radar, DR HUD, GPS chip,
/// Guide ask, Messages, PTT, breadcrumbs, tracking, or missed-check-in UI.
private struct CriticalSOSShell: View {
    @Bindable var container: AppContainer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CRITICAL · SOS only")
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Red.hot)
            Text("Charge to restore Map, Comms, Field, Expedition.")
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.mid)
            lastKnownOrDropPin
            Spacer()
        }
        .padding(24)
        .padding(.bottom, 120)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BlackoutDS.Surface.void.ignoresSafeArea())
    }

    @ViewBuilder
    private var lastKnownOrDropPin: some View {
        if let line = lastKnownLine {
            Text(line)
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.mid)
        } else {
            Button("Drop pin") {
                dropPinWithoutMap()
            }
            .font(BlackoutDS.bodyFont())
            .foregroundStyle(BlackoutDS.Silver.metal)
            .buttonStyle(.plain)
        }
    }

    private var lastKnownLine: String? {
        let fix: LocationFix?
        if let last = container.location.lastKnown, last.hasCoordinate {
            fix = last
        } else if let pin = container.location.manualPin, pin.hasCoordinate {
            fix = pin
        } else {
            fix = nil
        }
        guard let fix, let lat = fix.latitude, let lon = fix.longitude else { return nil }
        let coord = String(format: "%.5f, %.5f", lat, lon)
        let age = fix.timestamp.formatted(.relative(presentation: .named))
        return "Last-known \(coord) · \(age)"
    }

    /// Writes the existing manual-pin store. Does not paint OfflineMapView / tiles.
    private func dropPinWithoutMap() {
        let lat = container.pack.pack?.region.centerLatitude ?? 39.74
        let lon = container.pack.pack?.region.centerLongitude ?? -105.25
        container.location.dropManualPin(latitude: lat, longitude: lon)
    }
}
