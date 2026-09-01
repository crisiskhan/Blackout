import BlackoutBattery
import BlackoutCore
import BlackoutLocation
import BlackoutMesh
import BlackoutPacks
import DesignSystem
import Field
import Maps
import Messaging
import Settings
import SwiftUI
import VoicePTT

enum AppDestination: String, Hashable, CaseIterable, Identifiable {
    case map
    case comms
    case field
    case expedition

    var id: String { rawValue }

    static let tabs: [AppDestination] = [.map, .comms, .field]

    static func resolved(_ dest: AppDestination) -> AppDestination {
        dest == .expedition ? .map : dest
    }

    var title: String {
        switch self {
        case .map: return "Map"
        case .comms: return "Comms"
        case .field: return "Field"
        case .expedition: return "Map"
        }
    }

    var symbol: String {
        switch self {
        case .map: return MapChromeLock.mapTabSymbol
        case .comms: return "antenna.radiowaves.left.and.right"
        case .field: return "leaf"
        case .expedition: return MapChromeLock.mapTabSymbol
        }
    }
}

struct RootView: View {
    @Bindable var container: AppContainer
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var destination: AppDestination = .map
    @State private var showSettings = false
    @State private var showPacksSheet = false
    @State private var pendingDM: BlackoutID?
    @State private var pendingPingNav: FieldPingNav?
    @State private var pendingGuideJob: GuideMapJob?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        applyLifecycle(to: stackedChrome)
    }

    /// Keep `body` a one-line wrapper. Xcode 16 times out type-checking the
    /// sheet + onChange + task chain when it lives on `body` itself.
    private func applyLifecycle<Content: View>(to content: Content) -> some View {
        content
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
                        showPacksSheet = true
                    }
                )
                .preferredColorScheme(.dark)
            }
            .onChange(of: scenePhase) { _, phase in
                // container.lock.isUnlocked is applied inside applyScenePhase.
                // Never lock() here — remounting the lock gate off-scene is the 9:08 class.
                container.applyScenePhase(
                    Self.lockPolicyPhase(phase),
                    systemCoverPresented: SystemCoverProbe.isPresented()
                )
            }
            .onChange(of: container.lock.isUnlocked) { _, unlocked in
                if unlocked {
                    container.scheduleHardwareAfterFirstMapFrame()
                }
            }
            .onChange(of: container.battery.isCritical) { _, _ in
                if container.lock.isUnlocked, scenePhase == .active {
                    syncSensorsToBattery()
                }
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
            .onOpenURL { url in
                if let next = container.applyDeepLink(url) {
                    destination = AppDestination.resolved(next)
                }
            }
            .onChange(of: destination) { _, next in
                let resolved = AppDestination.resolved(next)
                if resolved != next { destination = resolved }
            }
            .sheet(isPresented: $showPacksSheet) {
                NavigationStack {
                    FieldPackCatalogList(
                        store: container.packs,
                        nearbyCount: container.mesh.nearbyPeerCount,
                        onSendToPeer: { container.relayPack($0) }
                    )
                    .navigationTitle("Packs")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .preferredColorScheme(.dark)
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                guard container.lock.isUnlocked else { return }
                guard scenePhase == .active else { return }
                syncSensorsToBattery()
                container.refreshRadiosBanner()
                container.applyIdleTimer()
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard container.lock.isUnlocked, scenePhase == .active else { continue }
                    container.expireInboundIfNeeded()
                    container.applyIdleTimer()
                }
            }
    }

    private var stackedChrome: some View {
        rootStack
    }

    @ViewBuilder
    private var rootStack: some View {
        ZStack {
            BlackoutDS.Surface.void.ignoresSafeArea()
            unlockedChrome
        }
    }

    @ViewBuilder
    private var unlockedChrome: some View {
        chrome
        if let bootError = container.bootError {
            VStack {
                StoreFailure(bootError)
                    .padding(.horizontal, 16)
                    .padding(.top, sizeClass == .regular ? 12 : 72)
                Spacer()
            }
            .allowsHitTesting(false)
        }
        CameraControlPTTCatcher()
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        if container.showRadioBanner {
            radioBannerOverlay
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
            Spacer().allowsHitTesting(false)
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private var chrome: some View {
        if sizeClass == .regular {
            iPadSplit
        } else {
            iPhoneTabs
        }
    }

    private static func lockPolicyPhase(_ phase: ScenePhase) -> SceneLockPolicy.Phase {
        switch phase {
        case .active: return .active
        case .inactive: return .inactive
        case .background: return .background
        @unknown default: return .inactive
        }
    }

    private func syncSensorsToBattery() {
        if container.battery.isCritical {
            showSettings = false
            container.setLeaveBehindRelay(false)
            container.packs.setDownloadsAllowed(false)
            container.location.stopUpdating()
            container.mesh.stop()
            container.ptt.stop()
        } else if container.sceneIsActive {
            container.packs.setDownloadsAllowed(true)
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
                .tabItem { mapFoldTab }
                .tag(AppDestination.map)
            commsDestination
                .tabItem { monochromeTab(AppDestination.comms) }
                .tag(AppDestination.comms)
            fieldDestination
                .tabItem { monochromeTab(AppDestination.field) }
                .tag(AppDestination.field)
        }
        .toolbarBackground(BlackoutDS.Surface.raised, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
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
                ForEach(AppDestination.tabs) { item in
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
                    if destination != .map {
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
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detail: some View {
        switch destination {
        case .map: mapDestination
        case .comms: commsDestination
        case .field: fieldDestination
        case .expedition: mapDestination
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
            installedPackRoots: container.packs.diskPackRoots,
            packReady: container.packs.readySnapshot,
            onOpenFieldPacks: { showPacksSheet = true },
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
    }

    private var commsDestination: some View {
        CommsRootView(
            outbox: container.outbox,
            mesh: container.mesh,
            roster: container.party,
            location: container.location,
            ptt: container.ptt,
            onBroadcast: { container.sendPartyStatus($0) },
            onCommitCallsign: { container.commitCallsign($0) },
            onCreateParty: { container.createParty() },
            onJoinParty: { container.joinParty($0) },
            onLeaveParty: { container.leaveParty() },
            onStartFieldMode: { mode in
                container.startFieldMode(mode)
                destination = .map
            },
            onNavigatePing: { nav in
                pendingPingNav = nav
                destination = .map
            },
            onPingReplied: { container.acknowledgeLatestPing() },
            pendingDM: $pendingDM,
            onOpenSettings: { showSettings = true }
        )
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
            },
            onOpenSettings: { showSettings = true }
        )
    }

    private var mapFoldTab: some View {
        Label(AppDestination.map.title, systemImage: MapChromeLock.mapTabSymbol)
            .symbolRenderingMode(.monochrome)
    }

    private func monochromeTab(_ item: AppDestination) -> some View {
        Label(item.title, systemImage: item.symbol)
            .symbolRenderingMode(.monochrome)
    }
}
