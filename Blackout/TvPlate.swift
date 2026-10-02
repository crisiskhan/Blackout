import SwiftUI
import UIKit
import Tokens

/// EXPEDITION TV. SNAP stills in TRAFFIC / BRIDGE / AIRPORT / VENUE / HOP.
/// Those sections never a live stream. N/A is a 10s hold, then adult HLS.
struct TvPlate: View {
    @Bindable var runtime: AppRuntime
    @State private var naUnlocked = false
    @State private var naHolding = false
    @State private var naPress = 0
    @State private var naStarted: Date?
    @State private var naChrome: String?
    @State private var naPlayingID: String?
    @State private var naOffset = 0
    @State private var naKind = "ALL"
    @State private var naQuery = ""
    @State private var naStillCache: [String: UIImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TV")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver.opacity(0.5))
            HUDGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Button("TAP UPDATE") {
                        runtime.pullMapSnap()
                        if naUnlocked { runtime.updateSocket.pullAdult() }
                    }
                    .buttonStyle(HUDActionStyle(filled: runtime.updateSocket.busy))
                    if !runtime.updateSocket.pipe {
                        Text("NO PIPE")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.warn)
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                    }
                    if feeds.isEmpty {
                        Text("NO CAMERAS")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.silver)
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                    }
                }
            }
            if naUnlocked { naGate }
            ForEach(openBlocks) { block in
                Text(block.kind.rawValue)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.silver.opacity(0.5))
                HUDGlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(block.feeds) { row in
                            feedRow(row)
                        }
                    }
                }
            }
            if !naUnlocked { naGate }
        }
        .onChange(of: naUnlocked) { _, ok in
            if ok {
                resetNaPage()
                runtime.updateSocket.pullAdult()
            }
        }
        .onChange(of: runtime.updateSocket.adultRooms.count) { _, _ in
            clampNaOffset()
        }
        .onChange(of: naPageKey) { _, _ in
            refreshNaStills()
            let rows = naPageRows
            Task { runtime.updateSocket.pullAdultStills(rows) }
        }
        .onChange(of: runtime.updateSocket.updatedAt) { _, _ in
            refreshNaStills()
        }
        .task {
            runtime.pullMapSnap()
            while !Task.isCancelled {
                let ns = UInt64(CamDesk.watchSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled else { return }
                if runtime.updateSocket.pipe, !runtime.updateSocket.busy {
                    runtime.pullMapSnap()
                }
            }
        }
    }

    private var you: (lat: Double, lon: Double)? {
        let pack = runtime.packs?.active
        let home = pack?.home ?? pack?.center
        return runtime.fieldYou ?? home.map { (lat: $0.lat, lon: $0.lon) }
    }

    private var feeds: [CamDesk.Feed] {
        guard let you else { return [] }
        return CamDesk.feeds(
            pack: runtime.packCams,
            hops: runtime.meshCams,
            lat: you.lat,
            lon: you.lon
        )
    }

    private var sections: [CamDesk.Section] {
        guard let you else { return [] }
        return CamDesk.sections(
            pack: runtime.packCams,
            hops: runtime.meshCams,
            lat: you.lat,
            lon: you.lon
        )
    }

    private var openBlocks: [CamDesk.Section] {
        sections
    }

    private var naFeeds: [CamDesk.Feed] {
        guard let you else { return [] }
        return CamDesk.naFeeds(
            pack: runtime.packCams,
            hops: runtime.meshCams,
            lat: you.lat,
            lon: you.lon
        )
    }

    private var naPicked: [AdultDesk.Room] {
        AdultDesk.pick(runtime.updateSocket.adultRooms, kind: naKind, query: naQuery)
    }

    private var naLiveRows: [NaLive.Row] {
        NaLive.rows(naPicked)
    }

    private var naPageRows: [NaLive.Row] {
        NaLive.page(
            runtime.updateSocket.adultRooms,
            kind: naKind,
            query: naQuery,
            offset: naOffset
        )
    }

    private var naPageKey: String {
        naPageRows.map(\.id).joined(separator: ",")
    }

    private var naKindChips: [String] {
        ["ALL"] + Array(AdultDesk.kinds(runtime.updateSocket.adultRooms).prefix(12))
    }

    private var naEmptyChrome: String {
        let query = naQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty || (naKind != "ALL" && !naKind.isEmpty) {
            return "NO MATCH"
        }
        return "NO CAMERAS"
    }

    private var naHasMore: Bool {
        naOffset + NaLive.screen < naLiveRows.count
    }

    private var naHasBack: Bool {
        naOffset > 0
    }

    private var naGate: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("N/A")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver.opacity(0.5))
            HUDGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    naHoldRow
                    if naUnlocked {
                        naFindRail
                        if naPageRows.isEmpty && naFeeds.isEmpty {
                            if runtime.updateSocket.adultReady {
                                Text(naEmptyChrome)
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(Theme.silver)
                                    .textCase(.uppercase)
                                    .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                            }
                        } else {
                            ForEach(naPageRows) { row in
                                NaLiveWell(
                                    row: row,
                                    pipe: runtime.updateSocket.pipe,
                                    still: still(id: row.id),
                                    playingID: $naPlayingID,
                                    onPlay: { await runtime.updateSocket.liveAdult($0) },
                                    onFull: { runtime.openLive($0) }
                                )
                            }
                            naPageRail
                            ForEach(naFeeds) { row in
                                feedRow(row)
                            }
                        }
                    }
                }
            }
        }
    }

    private var naFindRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HUDField("SEARCH",
                text: $naQuery,
                id: "tv.na.search",
                submit: "DONE",
                pointSize: 16,
                onSubmit: {
                    resetNaPage()
                    return true
                }
            )
            HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
                ForEach(naKindChips, id: \.self) { kind in
                    Button(kind) {
                        naKind = kind
                        resetNaPage()
                    }
                    .buttonStyle(HUDOverlayChipStyle(filled: naKind == kind))
                }
            }
        }
        .onChange(of: naQuery) { _, _ in
            if naOffset != 0 || naPlayingID != nil {
                resetNaPage()
            }
        }
    }

    private var naPageRail: some View {
        HStack(spacing: 8) {
            if naHasBack {
                Button("BACK") {
                    naPlayingID = nil
                    naOffset = max(0, naOffset - NaLive.screen)
                }
                .buttonStyle(HUDActionStyle(filled: false))
            }
            if naHasMore {
                Button("MORE") {
                    naPlayingID = nil
                    naOffset += NaLive.screen
                }
                .buttonStyle(HUDActionStyle(filled: false))
            }
        }
    }

    private func resetNaPage() {
        naPlayingID = nil
        naOffset = 0
    }

    private func clampNaOffset() {
        let total = naLiveRows.count
        if total == 0 {
            naOffset = 0
            return
        }
        if naOffset >= total {
            naOffset = (max(0, total - 1) / NaLive.screen) * NaLive.screen
        }
    }

    private var naHoldRow: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !naHolding || naUnlocked)) { context in
            Text(naHoldLabel(at: context.date))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(naUnlocked ? Color.white : Theme.warn)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !naUnlocked, !naHolding else { return }
                            naHolding = true
                            naChrome = nil
                            naPress &+= 1
                            let armed = naPress
                            let started = Date()
                            naStarted = started
                            DispatchQueue.main.asyncAfter(deadline: .now() + CamDesk.naHoldSeconds) {
                                let elapsed = Date().timeIntervalSince(started)
                                if naHolding, armed == naPress, CamDesk.naUnlocks(elapsed: elapsed) {
                                    naUnlocked = true
                                    naHolding = false
                                    naChrome = nil
                                }
                            }
                        }
                        .onEnded { _ in
                            if naUnlocked {
                                naHolding = false
                                return
                            }
                            naHolding = false
                            naStarted = nil
                            naChrome = "HOLD 10"
                        }
                )
                .accessibilityLabel("N/A")
                .accessibilityHint("HOLD 10")
                .accessibilityAddTraits(.isButton)
        }
    }

    private func naHoldLabel(at date: Date) -> String {
        if naUnlocked { return "N/A" }
        if naHolding, let started = naStarted {
            let left = max(0, CamDesk.naHoldSeconds - date.timeIntervalSince(started))
            if CamDesk.naUnlocks(elapsed: date.timeIntervalSince(started)) {
                return "N/A"
            }
            let seconds = max(1, Int(ceil(left)))
            return "HOLD \(seconds)"
        }
        return naChrome ?? "N/A"
    }

    private func feedRow(_ row: CamDesk.Feed) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.name)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(row.range)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
            if !row.provider.isEmpty {
                Text(row.provider.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.silver.opacity(0.7))
            }
            stillWell(id: row.id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(row.range)
    }

    private func stillWell(id: String) -> some View {
        ZStack {
            Theme.void
            if let still = still(id: id) {
                Image(uiImage: still)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 180)
            } else {
                Text("NO STILL")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 180)
        .clipShape(Theme.plateRect())
        .overlay(
            Theme.plateRect()
                .strokeBorder(Theme.metalStroke, lineWidth: Theme.strokeWidth(1))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if still(id: id) != nil {
                runtime.openStill(id: id)
            }
        }
        .accessibilityLabel(still(id: id) == nil ? "NO STILL" : "STILL")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("TAP")
    }

    private func refreshNaStills() {
        var next: [String: UIImage] = [:]
        let folder = SnapManifest.folder()
        for row in naPageRows {
            if let hit = naStillCache[row.id] {
                next[row.id] = hit
                continue
            }
            let url = folder.appendingPathComponent("cam-\(row.id).jpg")
            if let image = UIImage(contentsOfFile: url.path) {
                next[row.id] = image
            }
        }
        naStillCache = next
    }

    private func still(id: String) -> UIImage? {
        if let hit = naStillCache[id] { return hit }
        _ = runtime.updateSocket.updatedAt
        _ = runtime.updateSocket.busy
        let url = SnapManifest.folder().appendingPathComponent("cam-\(id).jpg")
        return UIImage(contentsOfFile: url.path)
    }
}
