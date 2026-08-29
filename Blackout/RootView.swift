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
                if sizeClass != .regular, !container.battery.isCritical {
                    settingsOverlay
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: settingsSheetBinding) {
            SettingsRootView(
                battery: container.battery,
                location: container.location,
                mesh: container.mesh,
                lock: container.lock,
                onFieldPacks: {
                    showSettings = false
                    container.showFieldPacks = true
                }
            )
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: fieldPacksSheetBinding) {
            FieldPacksView(store: container.packs) {
                skipFieldPacks()
            }
            .presentationDetents([.medium, .large])
            .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                container.lock.lock()
            }
            if phase == .active {
                syncSensorsToBattery()
            }
        }
        .onChange(of: container.battery.isCritical) { _, critical in
            if critical {
                container.showFieldPacks = false
            }
            syncSensorsToBattery()
        }
        .onAppear {
            syncSensorsToBattery()
            if !UserDefaults.standard.bool(forKey: BlackoutKeys.fieldPacksIntroCompleted),
               !container.battery.isCritical {
                container.showFieldPacks = true
            }
        }
    }

    private var fieldPacksSheetBinding: Binding<Bool> {
        Binding(
            get: {
                container.showFieldPacks
                    && !container.battery.isCritical
                    && !(container.lock.isEnabled && !container.lock.isUnlocked)
            },
            set: { newValue in
                if newValue {
                    container.showFieldPacks = true
                } else {
                    skipFieldPacks()
                }
            }
        )
    }

    private func skipFieldPacks() {
        container.packs.skipIntro()
        container.showFieldPacks = false
        destination = .map
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
            container.location.stopUpdating()
            container.mesh.stop()
        } else {
            container.location.startUpdating()
            container.location.applyPolicy(container.battery.policy)
            container.mesh.start()
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
            .navigationSplitViewColumnWidth(min: 280, ideal: 280, max: 280)
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
            installedPackRoots: container.packs.installedPackRoots,
            onOpenFieldPacks: { container.showFieldPacks = true }
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
            persistence: container.persistence,
            crypto: container.crypto,
            mesh: container.mesh,
            extremeSaver: container.battery.pausesCameraAndPTT
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
            sosArmed: UserDefaults.standard.bool(forKey: BlackoutKeys.sosArmed)
        )
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
                    battery: container.battery,
                    presentConfirm: $container.sosConfirmRequested
                )
                .padding(.trailing, 18)
                .padding(.bottom, fabBottomPadding)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(true)
    }

    /// Measured from the physical bottom of the screen (overlay ignores the bottom safe area).
    /// Compact 4-tab: 16pt above the tab bar (49pt) and home indicator (~34pt).
    /// Critical SOS-only and regular iPad split have no tab bar: 16pt above the home indicator.
    private var fabBottomPadding: CGFloat {
        let home: CGFloat = 34
        let tab: CGFloat = (sizeClass == .regular || container.battery.isCritical) ? 0 : 49
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
