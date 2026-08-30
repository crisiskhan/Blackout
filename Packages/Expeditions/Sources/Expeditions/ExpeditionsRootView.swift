import BlackoutCore
import BlackoutLocation
import DesignSystem
import SwiftUI

public struct ExpeditionsRootView<PacksPlate: View>: View {
    let persistence: any PersistenceServing
    @Bindable var location: LocationService
    @Bindable var roster: PartyRoster
    var onBroadcast: (Envelope) -> Void
    var onCommitCallsign: (String) -> Void
    var onCreateParty: () -> Void
    var onJoinParty: (String) -> Bool
    var onLeaveParty: () -> Void
    var leaveBehindOn: Bool
    var nightRed: Bool
    var onLeaveBehind: (Bool) -> Void
    var onNightRed: (Bool) -> Void
    var onStartFieldMode: (FieldJobMode) -> Void
    var packsPlate: PacksPlate

    @State private var items: [ExpeditionRecordDTO] = []
    @State private var editor: ExpeditionRecordDTO?
    @State private var crumbs: [BreadcrumbRecordDTO] = []
    @State private var tracking = false
    @State private var showAdmin = false
    @State private var showAbout = false
    @State private var storeError: String?

    public init(
        persistence: any PersistenceServing,
        location: LocationService,
        roster: PartyRoster,
        onBroadcast: @escaping (Envelope) -> Void = { _ in },
        onCommitCallsign: @escaping (String) -> Void = { _ in },
        onCreateParty: @escaping () -> Void = {},
        onJoinParty: @escaping (String) -> Bool = { _ in false },
        onLeaveParty: @escaping () -> Void = {},
        leaveBehindOn: Bool = false,
        nightRed: Bool = false,
        onLeaveBehind: @escaping (Bool) -> Void = { _ in },
        onNightRed: @escaping (Bool) -> Void = { _ in },
        onStartFieldMode: @escaping (FieldJobMode) -> Void = { _ in },
        @ViewBuilder packsPlate: () -> PacksPlate
    ) {
        self.persistence = persistence
        self.location = location
        self.roster = roster
        self.onBroadcast = onBroadcast
        self.onCommitCallsign = onCommitCallsign
        self.onCreateParty = onCreateParty
        self.onJoinParty = onJoinParty
        self.onLeaveParty = onLeaveParty
        self.leaveBehindOn = leaveBehindOn
        self.nightRed = nightRed
        self.onLeaveBehind = onLeaveBehind
        self.onNightRed = onNightRed
        self.onStartFieldMode = onStartFieldMode
        self.packsPlate = packsPlate()
        _tracking = State(initialValue: UserDefaults.standard.bool(forKey: BlackoutKeys.crumbsTracking))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(ExpeditionPauseCopy.title, subtitle: ExpeditionPauseCopy.subtitle)
                    if let storeError {
                        StoreFailure(storeError)
                    }
                    if LeaveBehindRelayPolicy.isActive(
                        enabled: leaveBehindOn,
                        expeditionOpen: items.contains(where: \.isOpen),
                        batteryCritical: false
                    ) {
                        Text(LeaveBehindRelayPolicy.banner)
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(BlackoutDS.Red.sun)
                    }
                    pausePanel("Roster") {
                        PartyVitalsPlate(
                            roster: roster,
                            fix: location.navigationFix,
                            onBroadcast: onBroadcast,
                            onCommitCallsign: onCommitCallsign,
                            onCreateParty: onCreateParty,
                            onJoinParty: onJoinParty,
                            onLeaveParty: {
                                onLeaveBehind(false)
                                onLeaveParty()
                            },
                            onStartFieldMode: onStartFieldMode
                        )
                    }
                    pausePanel("Gear") {
                        Text(ExpeditionPauseCopy.gearStub)
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Silver.dim)
                        Text(roster.identity.callsign)
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Silver.bright)
                            .accessibilityLabel("Callsign \(roster.identity.callsign)")
                        ForEach(DefaultOutingGear.items, id: \.self) { item in
                            Text(item)
                                .font(BlackoutDS.bodyFont())
                                .foregroundStyle(BlackoutDS.Silver.bright)
                        }
                    }
                    pausePanel("Packs") {
                        Text(ExpeditionPauseCopy.packsReady)
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Silver.dim)
                        packsPlate
                    }
                    pausePanel("Settings") {
                        Text("Breadcrumb tracking restores after kill while the expedition stays open. It is on-device; this pass does not use Background Modes.")
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(BlackoutDS.Silver.dim)
                        let relayOn = LeaveBehindRelayPolicy.isActive(
                            enabled: leaveBehindOn,
                            expeditionOpen: items.contains(where: \.isOpen),
                            batteryCritical: false
                        )
                        MetalButton(
                            relayOn ? "Relay on" : LeaveBehindRelayPolicy.control,
                            height: BlackoutDS.Hit.sm
                        ) {
                            onLeaveBehind(!leaveBehindOn)
                        }
                        .opacity(items.contains(where: \.isOpen) ? 1 : 0.38)
                        .disabled(!items.contains(where: \.isOpen))
                        MetalButton(nightRed ? "Night red on" : "Night red", height: BlackoutDS.Hit.sm) {
                            onNightRed(!nightRed)
                        }
                        MetalButton("New expedition", height: BlackoutDS.Hit.md) {
                            editor = ExpeditionRecordDTO(name: "Field \(items.count + 1)")
                        }
                        GhostButton(ExpeditionPauseCopy.about, height: BlackoutDS.Hit.sm) {
                            showAbout = true
                        }
                        GhostButton("Admin dashboard", height: BlackoutDS.Hit.sm) {
                            showAdmin = true
                        }
                        if items.isEmpty {
                            Text("No expeditions yet.")
                                .font(BlackoutDS.bodyFont())
                                .foregroundStyle(BlackoutDS.Silver.dim)
                        }
                        ForEach(items) { item in
                            Button {
                                editor = item
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.name)
                                        .font(BlackoutDS.bodyFont())
                                        .foregroundStyle(BlackoutDS.Silver.bright)
                                    Text(item.isOpen ? "Open" : "Closed")
                                        .font(BlackoutDS.captionFont())
                                        .foregroundStyle(item.isOpen ? BlackoutDS.Semantic.ok : BlackoutDS.Silver.dim)
                                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(BlackoutDS.captionFont())
                                        .foregroundStyle(BlackoutDS.Silver.steel)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 120)
            }
            .background(BlackoutDS.Surface.base.ignoresSafeArea())
            .colorMultiply(nightRed ? Color(red: 1, green: 0.55, blue: 0.55) : .white)
            .preferredColorScheme(.dark)
            .navigationTitle("Expedition")
            .swiftUIToolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let open = items.first(where: \.isOpen) {
                        Button(tracking ? "Stop crumbs" : "Start crumbs") {
                            toggleCrumbs(open)
                        }
                        .foregroundStyle(BlackoutDS.Silver.metal)
                    }
                }
            }
            .sheet(item: $editor) { item in
                ExpeditionEditor(record: item, persistence: persistence, location: location) {
                    reload()
                    editor = nil
                }
                .preferredColorScheme(.dark)
            }
            .navigationDestination(isPresented: $showAdmin) {
                AdminDashboardView(persistence: persistence)
            }
            .navigationDestination(isPresented: $showAbout) {
                AboutChromeView(callsign: roster.identity.callsign)
            }
            .task { reload() }
            .task(id: tracking) {
                guard tracking else { return }
                while tracking {
                    if let open = items.first(where: \.isOpen) {
                        dropCrumb(open)
                    }
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                }
            }
        }
    }

    private func pausePanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HUDPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(BlackoutDS.titleFont())
                    .foregroundStyle(BlackoutDS.Silver.bright)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }

    private func reload() {
        do {
            items = try persistence.expeditions()
            if let open = items.first(where: \.isOpen) {
                crumbs = try persistence.breadcrumbs(expeditionID: open.id)
                restoreTracking(for: open)
            } else {
                crumbs = []
                setTracking(false, expedition: nil)
                onLeaveBehind(false)
            }
            storeError = nil
        } catch {
            storeError = error.localizedDescription
        }
    }

    private func restoreTracking(for expedition: ExpeditionRecordDTO) {
        let stored = UserDefaults.standard.bool(forKey: BlackoutKeys.crumbsTracking)
        let id = UserDefaults.standard.string(forKey: BlackoutKeys.crumbsExpedition)
        tracking = stored && id == expedition.id.rawValue.uuidString && expedition.isOpen
    }

    private func toggleCrumbs(_ expedition: ExpeditionRecordDTO) {
        setTracking(!tracking, expedition: expedition)
        dropCrumb(expedition)
    }

    private func setTracking(_ value: Bool, expedition: ExpeditionRecordDTO?) {
        tracking = value
        UserDefaults.standard.set(value, forKey: BlackoutKeys.crumbsTracking)
        if let expedition, value {
            UserDefaults.standard.set(expedition.id.rawValue.uuidString, forKey: BlackoutKeys.crumbsExpedition)
        } else if !value {
            UserDefaults.standard.removeObject(forKey: BlackoutKeys.crumbsExpedition)
        }
    }

    private func dropCrumb(_ expedition: ExpeditionRecordDTO) {
        let fix = location.navigationFix
        let crumb = BreadcrumbRecordDTO(
            expeditionID: expedition.id,
            latitude: fix?.latitude,
            longitude: fix?.longitude,
            estimated: DeadReckoningHonesty.crumbEstimated(fix: fix)
        )
        do {
            try persistence.appendBreadcrumb(crumb)
            crumbs = try persistence.breadcrumbs(expeditionID: expedition.id)
            storeError = nil
        } catch {
            storeError = error.localizedDescription
            setTracking(false, expedition: expedition)
        }
    }
}

extension ExpeditionsRootView where PacksPlate == EmptyView {
    public init(
        persistence: any PersistenceServing,
        location: LocationService,
        roster: PartyRoster,
        onBroadcast: @escaping (Envelope) -> Void = { _ in },
        onCommitCallsign: @escaping (String) -> Void = { _ in },
        onCreateParty: @escaping () -> Void = {},
        onJoinParty: @escaping (String) -> Bool = { _ in false },
        onLeaveParty: @escaping () -> Void = {}
    ) {
        self.init(
            persistence: persistence,
            location: location,
            roster: roster,
            onBroadcast: onBroadcast,
            onCommitCallsign: onCommitCallsign,
            onCreateParty: onCreateParty,
            onJoinParty: onJoinParty,
            onLeaveParty: onLeaveParty,
            leaveBehindOn: false,
            nightRed: false,
            onLeaveBehind: { _ in },
            onNightRed: { _ in },
            onStartFieldMode: { _ in },
            packsPlate: { EmptyView() }
        )
    }
}

struct ExpeditionEditor: View {
    @State var record: ExpeditionRecordDTO
    let persistence: any PersistenceServing
    @Bindable var location: LocationService
    var onDone: () -> Void
    @State private var crumbs: [BreadcrumbRecordDTO] = []
    @State private var storeError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let storeError {
                        StoreFailure(storeError)
                    }
                    TextField("Name", text: $record.name)
                        .font(BlackoutDS.bodyFont())
                        .foregroundStyle(BlackoutDS.Silver.bright)
                        .padding(14)
                        .frame(height: BlackoutDS.Hit.sm)
                        .background(BlackoutDS.Surface.sunken)
                    Text(PartyIdentityCopy.outingNameHint)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.dim)
                    TextField("Notes", text: $record.notes, axis: .vertical)
                        .font(BlackoutDS.bodyFont())
                        .foregroundStyle(BlackoutDS.Silver.mid)
                        .padding(14)
                        .frame(minHeight: 88, alignment: .topLeading)
                        .background(BlackoutDS.Surface.sunken)
                    MetalButton("Save", action: save)
                    if record.isOpen {
                        GhostButton("Close expedition") {
                            record.closedAt = Date()
                            save()
                        }
                    }
                    GhostButton("Drop breadcrumb") {
                        drop()
                    }
                    Toggle(isOn: $record.checkInEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Missed check-in")
                                .foregroundStyle(BlackoutDS.Silver.bright)
                            Text("Default off. Local timer on the app container — visiting Expedition is not required. Miss opens SOS confirm. Never auto-arms, never auto-911, no mesh this pass.")
                                .font(BlackoutDS.captionFont())
                                .foregroundStyle(BlackoutDS.Silver.dim)
                        }
                    }
                    .tint(BlackoutDS.Silver.metal)
                    if record.checkInEnabled {
                        Stepper(
                            "Every \(max(1, record.checkInIntervalSeconds / 60)) min",
                            value: Binding(
                                get: { max(1, record.checkInIntervalSeconds / 60) },
                                set: { record.checkInIntervalSeconds = max(60, $0 * 60) }
                            ),
                            in: 5...180,
                            step: 5
                        )
                        .foregroundStyle(BlackoutDS.Silver.bright)
                        GhostButton("Check in now") {
                            record.lastCheckInAt = Date()
                            save()
                        }
                    }
                    ReturnToStartView(crumbs: crumbs, location: location)
                    Text("\(crumbs.count) breadcrumbs. Nil coordinates are stored when GPS is denied and no manual pin exists.")
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.steel)
                }
                .padding(20)
            }
            .background(BlackoutDS.Surface.base.ignoresSafeArea())
            .navigationTitle("Expedition")
            .task { loadCrumbs() }
        }
    }

    private func loadCrumbs() {
        do {
            crumbs = try persistence.breadcrumbs(expeditionID: record.id)
            storeError = nil
        } catch {
            storeError = error.localizedDescription
        }
    }

    private func save() {
        if record.startLatitude == nil, let fix = location.navigationFix, fix.hasCoordinate {
            record.startLatitude = fix.latitude
            record.startLongitude = fix.longitude
        }
        if record.checkInEnabled, record.lastCheckInAt == nil {
            record.lastCheckInAt = Date()
        }
        do {
            try persistence.upsertExpedition(record)
            storeError = nil
            onDone()
        } catch {
            storeError = error.localizedDescription
        }
    }

    private func drop() {
        let fix = location.navigationFix
        let crumb = BreadcrumbRecordDTO(
            expeditionID: record.id,
            latitude: fix?.latitude,
            longitude: fix?.longitude,
            estimated: DeadReckoningHonesty.crumbEstimated(fix: fix)
        )
        do {
            try persistence.appendBreadcrumb(crumb)
            crumbs = try persistence.breadcrumbs(expeditionID: record.id)
            if record.startLatitude == nil {
                record.startLatitude = crumb.latitude
                record.startLongitude = crumb.longitude
                try persistence.upsertExpedition(record)
            }
            storeError = nil
        } catch {
            storeError = error.localizedDescription
        }
    }
}

struct ReturnToStartView: View {
    var crumbs: [BreadcrumbRecordDTO]
    @Bindable var location: LocationService

    var body: some View {
        let start = crumbs.first(where: \.hasCoordinate)
        if let start, let here = location.navigationFix, here.hasCoordinate {
            let meters = haversineLocal(here.latitude!, here.longitude!, start.latitude!, start.longitude!)
            let brg = bearingLocal(here.latitude!, here.longitude!, start.latitude!, start.longitude!)
            HUDPanel {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Return to start")
                    Text(String(format: "%.0f m  ·  %d°", meters, Int(brg)))
                        .foregroundStyle(BlackoutDS.Silver.mid)
                    if location.lastKnown?.hasCoordinate != true, location.manualPin?.hasCoordinate == true {
                        Text("Using manual pin")
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(BlackoutDS.Semantic.warn)
                    }
                }
            }
        } else if location.authorization == .denied {
            PermissionDenied(
                kind: .location,
                reason: "Return-to-start uses last-known or a manual pin. Breadcrumbs without coordinates remain in the log. Long-press the map to drop a pin."
            )
        } else {
            Text("Return-to-start waits on a start fix or manual pin.")
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
        }
    }
}

public struct AdminDashboardView: View {
    let persistence: any PersistenceServing
    @State private var expeditions = 0
    @State private var open = 0
    @State private var sos = 0
    @State private var messages = 0
    @State private var crumbs = 0
    @State private var storeError: String?

    public init(persistence: any PersistenceServing) {
        self.persistence = persistence
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader("Admin", subtitle: "On-device only. No analytics.")
                if let storeError {
                    StoreFailure(storeError)
                }
                stat("Expeditions", "\(expeditions)")
                stat("Open", "\(open)")
                stat("SOS events", "\(sos)")
                stat("Sealed messages", "\(messages)")
                stat("Breadcrumbs", "\(crumbs)")
            }
            .padding(20)
        }
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
        .navigationTitle("Admin")
        .task {
            do {
                let ex = try persistence.expeditions()
                expeditions = ex.count
                open = ex.filter(\.isOpen).count
                sos = try persistence.sosEvents().count
                messages = try persistence.messages().count
                crumbs = try ex.reduce(0) { acc, item in
                    acc + (try persistence.breadcrumbs(expeditionID: item.id).count)
                }
                storeError = nil
            } catch {
                storeError = error.localizedDescription
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        HUDPanel {
            HStack {
                Text(title)
                Spacer()
                Text(value).foregroundStyle(BlackoutDS.Silver.metal)
            }
        }
    }
}

private func haversineLocal(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let r = 6_371_000.0
    let φ1 = lat1 * .pi / 180
    let φ2 = lat2 * .pi / 180
    let Δφ = (lat2 - lat1) * .pi / 180
    let Δλ = (lon2 - lon1) * .pi / 180
    let a = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
    return 2 * r * atan2(sqrt(a), sqrt(1 - a))
}

private func bearingLocal(_ fromLat: Double, _ fromLon: Double, _ toLat: Double, _ toLon: Double) -> Double {
    let φ1 = fromLat * .pi / 180
    let φ2 = toLat * .pi / 180
    let Δλ = (toLon - fromLon) * .pi / 180
    let y = sin(Δλ) * cos(φ2)
    let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
    let θ = atan2(y, x)
    return (θ * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
}
