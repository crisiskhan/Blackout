import SwiftUI
import UIKit
import Tokens

/// EXPEDITION N/A. Dedicated theater after HOLD 10. SNAP stays on TV.
struct NaPlate: View {
    @Bindable var runtime: AppRuntime
    @State private var naPlayingID: String?
    @State private var naOffset = 0
    @State private var naKind = "ALL"
    @State private var naQuery = ""
    @State private var naPasteFailed = false
    @State private var naHuntNow = false
    @State private var naHuntTask: Task<Void, Never>?
    @State private var naPick: String?
    @State private var naChrome: String?
    @State private var naStillCache: [String: UIImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("N/A")
            HUDGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Button("TAP UPDATE") { pullNaHunt(now: true) }
                        .buttonStyle(HUDActionStyle(filled: runtime.updateSocket.busy))
                    if !runtime.updateSocket.pipe {
                        Text("NO PIPE")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.warn)
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                    }
                    naFindRail
                }
            }
            sectionLabel("WATCH")
            HUDGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    if let row = naStageRow {
                        NaLiveWell(
                            row: row,
                            pipe: runtime.updateSocket.pipe,
                            still: still(id: row.id),
                            playingID: $naPlayingID,
                            kept: runtime.heldNa(row.id),
                            canPrev: naHasPrev,
                            canNext: naHasNext,
                            onPlay: {
                                runtime.hushNa()
                                return await runtime.updateSocket.liveAdult($0)
                            },
                            onFull: { runtime.openLive($0, queue: naLiveRows) },
                            onKeep: { keepTapped($0) },
                            onPrev: { stepStage(-1) },
                            onNext: { stepStage(1) },
                            onWhy: { naChrome = $0 }
                        )
                        .id(row.id)
                    } else if runtime.updateSocket.adultReady {
                        Text(naEmptyChrome)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.silver)
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                    }
                    if let naChrome {
                        Text(naChrome)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.warn)
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                    }
                }
            }
            sectionLabel("BROWSE")
            HUDGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    if naPageRows.isEmpty {
                        if runtime.updateSocket.adultReady {
                            Text(naEmptyChrome)
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Theme.silver)
                                .textCase(.uppercase)
                                .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                        }
                    } else {
                        naBrowseStrip
                        naPageRail
                    }
                }
            }
        }
        .onAppear {
            runtime.updateSocket.adultRooms = AdultDesk.merge([
                AdultKeep.load(),
                runtime.updateSocket.adultRooms,
            ])
            pullNaHunt(now: true)
        }
        .onChange(of: runtime.updateSocket.adultRooms.count) { _, _ in
            clampNaOffset()
            clampNaPick()
        }
        .onChange(of: naPageKey) { _, _ in
            refreshNaStills()
            let rows = naPageRows
            Task { runtime.updateSocket.pullAdultStills(rows) }
            clampNaPick()
        }
        .onChange(of: runtime.updateSocket.updatedAt) { _, _ in
            refreshNaStills()
        }
        .onChange(of: runtime.naKeep.count) { _, _ in
            if naKind == AdultDesk.keepChip {
                clampNaPick()
            }
        }
    }

    private var naHuntKind: String {
        let query = naQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? naKind : query
    }

    private var naPicked: [AdultDesk.Room] {
        let query = naQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return AdultDesk.pick(runtime.updateSocket.adultRooms, kind: naHuntKind, query: query)
    }

    private var naLiveRows: [NaLive.Row] {
        NaLive.rows(naPicked)
    }

    private var naPageRows: [NaLive.Row] {
        NaLive.page(
            runtime.updateSocket.adultRooms,
            kind: naHuntKind,
            query: naQuery,
            offset: naOffset
        )
    }

    private var naPageKey: String {
        naPageRows.map(\.id).joined(separator: ",")
    }

    private var naKindChips: [String] {
        AdultDesk.rail(runtime.updateSocket.adultRooms)
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

    private var naStageRow: NaLive.Row? {
        if let id = naPick, let hit = naLiveRows.first(where: { $0.id == id }) {
            return hit
        }
        return naPageRows.first
    }

    private var naHasPrev: Bool {
        guard let row = naStageRow else { return false }
        return naLiveIndex(row) > 0
    }

    private var naHasNext: Bool {
        guard let row = naStageRow else { return false }
        let index = naLiveIndex(row)
        return index >= 0 && index + 1 < naLiveRows.count
    }

    private var naFindRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                HUDField("SEARCH",
                    text: $naQuery,
                    id: "na.search",
                    submit: "DONE",
                    pointSize: 16,
                    onSubmit: {
                        naHuntNow = true
                        takeNaQuery(naQuery)
                        resetNaPage()
                        pullNaHunt(now: true)
                        return true
                    }
                )
                Button("PASTE") { pasteNaSearch() }
                    .buttonStyle(HUDOverlayChipStyle())
            }
            if naPasteFailed {
                Text("NO PASTE")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.warn)
                    .textCase(.uppercase)
            }
            HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
                ForEach(naKindChips, id: \.self) { kind in
                    Button(kind) {
                        naQuery = ""
                        naPasteFailed = false
                        naKind = kind
                        naChrome = nil
                        resetNaPage()
                        runtime.updateSocket.pullAdult(topic: kind)
                    }
                    .buttonStyle(HUDOverlayChipStyle(filled: naKind == kind))
                }
            }
        }
        .onChange(of: naQuery) { _, _ in
            naPasteFailed = false
            if naOffset != 0 || naPlayingID != nil {
                resetNaPage()
            }
            if naHuntNow {
                naHuntNow = false
                return
            }
            pullNaHunt(now: false)
        }
    }

    private var naBrowseStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(naPageRows) { row in
                    naBrowseTile(row)
                }
            }
        }
    }

    private func naBrowseTile(_ row: NaLive.Row) -> some View {
        let picked = naStageRow?.id == row.id
        return Button {
            naChrome = nil
            naPick = row.id
            if naPlayingID != row.id {
                naPlayingID = nil
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Theme.void
                    if let image = still(id: row.id) {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    } else {
                        Text("NO STILL")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Theme.silver)
                    }
                }
                .frame(width: 132, height: 88)
                .clipped()
                .clipShape(Theme.plateRect())
                Text(row.name)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(width: 132, alignment: .leading)
                Text(row.range)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(minWidth: 132, maxWidth: 132, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
            .overlay {
                if picked {
                    Theme.plateRect()
                        .strokeBorder(Theme.accent, lineWidth: Theme.strokeWidth(1.5))
                } else {
                    Theme.plateRect()
                        .strokeBorder(Theme.metalStroke, lineWidth: Theme.strokeWidth(1))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.name)
        .accessibilityValue(row.range)
        .accessibilityHint("TAP")
        .accessibilityAddTraits(.isButton)
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
                    clampNaOffset()
                }
                .buttonStyle(HUDActionStyle(filled: false))
            }
        }
    }

    private func resetNaPage() {
        naPlayingID = nil
        naOffset = 0
        naPick = nil
        naChrome = nil
    }

    private func takeNaQuery(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = AdultDesk.pageName(text) {
            naQuery = name
        } else {
            naQuery = text
        }
    }

    /// HUD typewriter has no iPhone paste. PASTE is the only way a
    /// creator-page link lands on SEARCH.
    private func pasteNaSearch() {
        naPasteFailed = false
        let text = (UIPasteboard.general.string ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            naPasteFailed = true
            return
        }
        naHuntNow = true
        takeNaQuery(text)
        resetNaPage()
        pullNaHunt(now: true)
    }

    private func pullNaHunt(now: Bool) {
        naHuntTask?.cancel()
        let query = naQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            runtime.updateSocket.pullAdult(topic: naKind)
            return
        }
        if AdultDesk.huntNeedles(query) == nil {
            return
        }
        if now {
            runtime.updateSocket.pullAdult(topic: query)
            return
        }
        naHuntTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                runtime.updateSocket.pullAdult(topic: query)
            }
        }
    }

    private func clampNaOffset() {
        let total = naLiveRows.count
        let page = max(1, NaLive.screen)
        if total == 0 {
            naOffset = 0
            return
        }
        if naOffset >= total {
            naOffset = (max(0, total - 1) / page) * page
        }
    }

    private func clampNaPick() {
        if let id = naPick, naLiveRows.contains(where: { $0.id == id }) {
            return
        }
        naPick = naPageRows.first?.id
    }

    private func naLiveIndex(_ row: NaLive.Row) -> Int {
        naLiveRows.firstIndex(where: { $0.id == row.id }) ?? -1
    }

    private func stepStage(_ delta: Int) {
        let rows = naLiveRows
        guard let row = naStageRow else { return }
        let index = (rows.firstIndex(where: { $0.id == row.id }) ?? -1) + delta
        guard rows.indices.contains(index) else {
            naChrome = delta < 0 ? "FIRST" : "LAST"
            return
        }
        let next = rows[index]
        naChrome = nil
        naPick = next.id
        let page = (index / max(1, NaLive.screen)) * max(1, NaLive.screen)
        if page != naOffset {
            naOffset = page
        }
        if naPlayingID != nil {
            naPlayingID = next.id
        }
    }

    private func keepTapped(_ row: NaLive.Row) {
        naChrome = nil
        Task {
            let why = await runtime.toggleNa(row)
            await MainActor.run {
                naChrome = why
            }
        }
    }

    private func refreshNaStills() {
        var next: [String: UIImage] = [:]
        for row in naPageRows {
            if let image = NaWatch.still(id: row.id, maxEdge: NaWatch.wellStill) {
                next[row.id] = image
            }
        }
        naStillCache = next
    }

    private func still(id: String) -> UIImage? {
        if let hit = naStillCache[id] { return hit }
        _ = runtime.updateSocket.updatedAt
        _ = runtime.updateSocket.busy
        return NaWatch.still(id: id, maxEdge: NaWatch.wellStill)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Theme.silver.opacity(0.5))
    }
}
