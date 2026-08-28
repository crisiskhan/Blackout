import BlackoutBattery
import BlackoutLocation
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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            BlackoutDS.Surface.void.ignoresSafeArea()
            if container.lock.isEnabled && !container.lock.isUnlocked {
                LockGateView(lock: container.lock)
            } else {
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
                sosOverlay
                if sizeClass != .regular {
                    settingsOverlay
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsRootView(
                battery: container.battery,
                location: container.location,
                mesh: container.mesh,
                lock: container.lock
            )
            .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                container.lock.lock()
            }
            if phase == .active, container.location.authorization == .authorized {
                container.location.startUpdating()
                container.location.applyPolicy(container.battery.policy)
            }
        }
    }

    @ViewBuilder
    private var chrome: some View {
        if sizeClass == .regular {
            iPadSplit
        } else {
            iPhoneTabs
        }
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

    private var iPadSplit: some View {
        NavigationSplitView {
            List(AppDestination.allCases, selection: $destination) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationTitle("Blackout")
            .navigationSplitViewColumnWidth(min: 280, ideal: 280, max: 280)
            .toolbar {
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
                .toolbar {
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
            packService: container.pack
        )
        .toolbar {
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
            persistence: container.persistence,
            crypto: container.crypto,
            mesh: container.mesh,
            extremeSaver: container.battery.pausesCameraAndPTT
        )
        .toolbar {
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
        FieldRootView()
    }

    private var expeditionDestination: some View {
        ExpeditionsRootView(
            persistence: container.persistence,
            location: container.location
        )
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
                    battery: container.battery
                )
                .padding(.trailing, 18)
                .padding(.bottom, fabBottomPadding)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(true)
    }

    /// Measured from the physical bottom of the screen (overlay ignores the bottom safe area).
    /// Compact: 16pt gap above the tab bar (49pt) and home indicator (~34pt) — never under the tab bar.
    /// Regular iPad split has no tab bar: 16pt above the home indicator.
    private var fabBottomPadding: CGFloat {
        let home: CGFloat = 34
        let tab: CGFloat = sizeClass == .regular ? 0 : 49
        return 16 + tab + home
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
