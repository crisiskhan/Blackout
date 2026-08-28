import BlackoutCore
import BlackoutLocation
import DesignSystem
import SwiftUI

public struct ExpeditionsRootView: View {
    let persistence: any PersistenceServing
    @Bindable var location: LocationService

    @State private var items: [ExpeditionRecordDTO] = []
    @State private var editor: ExpeditionRecordDTO?
    @State private var crumbs: [BreadcrumbRecordDTO] = []
    @State private var tracking = false
    @State private var showAdmin = false

    public init(persistence: any PersistenceServing, location: LocationService) {
        self.persistence = persistence
        self.location = location
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    MetalButton("New expedition", height: BlackoutDS.Hit.md) {
                        editor = ExpeditionRecordDTO(name: "Field \(items.count + 1)")
                    }
                    GhostButton("Admin dashboard", height: BlackoutDS.Hit.sm) {
                        showAdmin = true
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
                    }
                    .listRowBackground(BlackoutDS.Surface.raised)
                }
            }
            .scrollContentBackground(.hidden)
            .background(BlackoutDS.Surface.base.ignoresSafeArea())
            .navigationTitle("Expedition")
            .toolbar {
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

    private func reload() {
        items = (try? persistence.expeditions()) ?? []
        if let open = items.first(where: \.isOpen) {
            crumbs = (try? persistence.breadcrumbs(expeditionID: open.id)) ?? []
        }
    }

    private func toggleCrumbs(_ expedition: ExpeditionRecordDTO) {
        tracking.toggle()
        dropCrumb(expedition)
    }

    private func dropCrumb(_ expedition: ExpeditionRecordDTO) {
        let fix = location.lastKnown
        let crumb = BreadcrumbRecordDTO(
            expeditionID: expedition.id,
            latitude: fix?.latitude,
            longitude: fix?.longitude
        )
        try? persistence.appendBreadcrumb(crumb)
        crumbs = (try? persistence.breadcrumbs(expeditionID: expedition.id)) ?? []
    }
}

struct ExpeditionEditor: View {
    @State var record: ExpeditionRecordDTO
    let persistence: any PersistenceServing
    @Bindable var location: LocationService
    var onDone: () -> Void
    @State private var crumbs: [BreadcrumbRecordDTO] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Name", text: $record.name)
                        .font(BlackoutDS.bodyFont())
                        .foregroundStyle(BlackoutDS.Silver.bright)
                        .padding(14)
                        .frame(height: BlackoutDS.Hit.sm)
                        .background(BlackoutDS.Surface.sunken)
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
                    ReturnToStartView(crumbs: crumbs, location: location)
                    Text("\(crumbs.count) breadcrumbs. Nil coordinates are stored when GPS is denied.")
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.steel)
                }
                .padding(20)
            }
            .background(BlackoutDS.Surface.base.ignoresSafeArea())
            .navigationTitle("Expedition")
            .task {
                crumbs = (try? persistence.breadcrumbs(expeditionID: record.id)) ?? []
            }
        }
    }

    private func save() {
        if record.startLatitude == nil, let fix = location.lastKnown, fix.hasCoordinate {
            record.startLatitude = fix.latitude
            record.startLongitude = fix.longitude
        }
        try? persistence.upsertExpedition(record)
        onDone()
    }

    private func drop() {
        let fix = location.lastKnown
        let crumb = BreadcrumbRecordDTO(
            expeditionID: record.id,
            latitude: fix?.latitude,
            longitude: fix?.longitude
        )
        try? persistence.appendBreadcrumb(crumb)
        crumbs = (try? persistence.breadcrumbs(expeditionID: record.id)) ?? []
        if record.startLatitude == nil {
            record.startLatitude = crumb.latitude
            record.startLongitude = crumb.longitude
            try? persistence.upsertExpedition(record)
        }
    }
}

struct ReturnToStartView: View {
    var crumbs: [BreadcrumbRecordDTO]
    @Bindable var location: LocationService

    var body: some View {
        let start = crumbs.first(where: \.hasCoordinate)
        if let start, let here = location.lastKnown, here.hasCoordinate {
            let meters = haversineLocal(here.latitude!, here.longitude!, start.latitude!, start.longitude!)
            let brg = bearingLocal(here.latitude!, here.longitude!, start.latitude!, start.longitude!)
            HUDPanel {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Return to start")
                    Text(String(format: "%.0f m  ·  %d°", meters, Int(brg)))
                        .foregroundStyle(BlackoutDS.Silver.mid)
                }
            }
        } else if location.authorization == .denied {
            PermissionDenied(
                kind: .location,
                reason: "Return-to-start needs a coordinate. Breadcrumbs without GPS remain in the log."
            )
        } else {
            Text("Return-to-start waits on a start fix.")
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

    public init(persistence: any PersistenceServing) {
        self.persistence = persistence
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader("Admin", subtitle: "On-device only. No analytics.")
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
            let ex = (try? persistence.expeditions()) ?? []
            expeditions = ex.count
            open = ex.filter(\.isOpen).count
            sos = ((try? persistence.sosEvents()) ?? []).count
            messages = ((try? persistence.messages()) ?? []).count
            crumbs = ex.reduce(0) { acc, item in
                acc + ((try? persistence.breadcrumbs(expeditionID: item.id))?.count ?? 0)
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
