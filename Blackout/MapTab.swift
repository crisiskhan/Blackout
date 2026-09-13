import SwiftUI
import MapLibreMap
import Search
import Router
import Tokens
import PackIO

struct MapTab: View {
    @Bindable var runtime: AppRuntime
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var packedIndex: SearchIndex?
    @State private var sayFailed = false
    @State private var searchGen: UInt64 = 0
    @State private var looking = false

    var body: some View {
        ZStack {
            Theme.void.ignoresSafeArea()
            if let pack = runtime.packs?.active, let style = styleURL() {
                canvas(pack: pack, style: style)
            } else {
                Text("Packs missing from bundle — honest empty.")
                    .foregroundStyle(Theme.silver.opacity(0.5))
                    .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: loadIndex)
        .onChange(of: runtime.packs?.active?.id) { _, _ in
            searchGen &+= 1
            looking = false
            query = ""
            hits = []
            sayFailed = false
            loadIndex()
        }
    }

    @ViewBuilder
    private func canvas(pack: PackManifest, style: URL) -> some View {
        let home = pack.home ?? pack.center
        let you = UserPuck.coordinate(
            lastKnown: runtime.lastKnownFix,
            packCenter: (home.lat, home.lon),
            packSouth: pack.bbox.south,
            packWest: pack.bbox.west,
            packNorth: pack.bbox.north,
            packEast: pack.bbox.east
        )
        let offPack = PackChrome.banner(
            fix: runtime.lastKnownFix,
            bbox: (pack.bbox.south, pack.bbox.west, pack.bbox.north, pack.bbox.east)
        ) == PackChrome.offPack
        ZStack(alignment: .bottomLeading) {
            OfflineMapView(
                styleURL: style,
                centerLat: you.lat,
                centerLon: you.lon,
                puckLat: you.lat,
                puckLon: you.lon,
                packSouth: pack.bbox.south,
                packWest: pack.bbox.west,
                packNorth: pack.bbox.north,
                packEast: pack.bbox.east,
                route: runtime.routeCoords,
                destination: runtime.routeTarget,
                held: runtime.held.map { (lat: $0.lat, lon: $0.lon) }
                    ?? runtime.heldAddress.map { (lat: $0.lat, lon: $0.lon) },
                fitToken: runtime.fitPackToken,
                interactive: MapCanvasHit.enabled(
                    onMap: runtime.tab == .map,
                    holding: runtime.held != nil || runtime.heldParty != nil || runtime.heldAddress != nil,
                    arranging: runtime.hudLayoutMode
                ),
                onMapTap: { lat, lon in
                    runtime.pickDestination(lat: lat, lon: lon)
                    hits = []
                },
                onMapHold: { lat, lon, tags, zoom in
                    runtime.holdInspect(lat: lat, lon: lon, tags: tags, zoom: zoom)
                },
                onPersonHold: { id, lat, lon in
                    runtime.holdParty(id: id, lat: lat, lon: lon)
                },
                pips: runtime.mesh.pips
                    .filter { $0.from != runtime.mesh.localID && $0.lat.isFinite && $0.lon.isFinite }
                    .map {
                        PartyBody(
                            id: $0.from,
                            lat: $0.lat,
                            lon: $0.lon,
                            headingDeg: $0.headingDeg,
                            emblem: $0.emblem
                        )
                    },
                youHeading: runtime.headingDeg,
                youEmblem: runtime.youEmblem.rawValue,
                onPulse: { runtime.pulse() },
                lockOn: runtime.lockOn,
                travelMode: runtime.travelMode
            )
            .ignoresSafeArea()
            // The scrim already keeps a thumb off the canvas. This is the
            // same thing for VoiceOver, and only the canvas: the tab bar
            // stays reachable, because Comms is on it.
            .accessibilityHidden(runtime.held != nil || runtime.heldParty != nil || runtime.heldAddress != nil)
            if runtime.tab == .map, runtime.held == nil, runtime.heldParty == nil, runtime.heldAddress == nil {
                hud(packName: pack.name, offPack: offPack)
                    .padding(hudReserve)
            }
            if runtime.tab == .map, let person = runtime.heldParty {
                PartyHoldCard(
                    person: person,
                    bearing: runtime.partyCourse(for: person),
                    coordinates: runtime.partyFix(person),
                    vitals: person.isYou ? runtime.vitals : person.vitals,
                    onName: { runtime.setYouName($0) },
                    onStatus: { runtime.setYouStatus($0) },
                    onVitals: { runtime.setYouVitals($0) },
                    onCall: { runtime.callHeldParty() },
                    onMessage: { runtime.messageHeldParty() },
                    onClose: { runtime.closeHold() },
                    onFaceHold: { runtime.openEmblemPick() }
                )
                .padding(hudReserve)
                if runtime.pickingEmblem {
                    EmblemPickCard(
                        selected: runtime.youEmblem,
                        onPick: { runtime.pickEmblem($0) },
                        onClose: { runtime.closeEmblemPick() }
                    )
                    .padding(hudReserve)
                }
            } else if runtime.tab == .map, let address = runtime.heldAddress {
                AddressHoldCard(
                    address: address,
                    bearing: runtime.addressCourse(lat: address.lat, lon: address.lon),
                    coordinates: runtime.addressFix(lat: address.lat, lon: address.lon),
                    onWalk: { runtime.walkHeldAddress() },
                    onMark: { runtime.markHeldAddress() },
                    onClose: { runtime.closeHold() }
                )
                .padding(hudReserve)
            } else if runtime.tab == .map, let held = runtime.held {
                HoldCardView(
                    held: held,
                    fieldBook: runtime.fieldBookIDs,
                    onField: { runtime.openFieldFromHold() },
                    onMark: { runtime.markHeld() },
                    onClose: { runtime.closeHold() }
                )
                .padding(hudReserve)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .animation(runtime.chromeAwake ? Theme.Motion.wake : Theme.Motion.sleep, value: runtime.chromeAwake)
        .animation(Theme.Motion.heavy, value: runtime.hudFocus)
        .animation(Theme.Motion.heavy, value: runtime.held)
        .animation(Theme.Motion.heavy, value: runtime.heldParty)
        .animation(Theme.Motion.heavy, value: runtime.heldAddress)
        .animation(Theme.Motion.heavy, value: runtime.pickingEmblem)
    }

    /// Everything that is not the map, sitting on the map. Search, lock and
    /// instruments at the top; status and the four thumb cells at the bottom.
    /// Ruler, grid and north live in Instruments — they are not a walk.
    private func hud(packName: String, offPack: Bool) -> some View {
        VStack(spacing: 8) {
            HUDPlaced(
                offset: runtime.hudLayout.search,
                arranging: runtime.hudLayoutMode,
                veil: runtime.chromeVeil,
                alive: runtime.alive(.search),
                onMove: { runtime.hudLayout.search = $0 },
                onStore: { runtime.hudLayout.save() }
            ) {
                searchField
            }
            HUDPlaced(
                offset: runtime.hudLayout.overlay,
                arranging: runtime.hudLayoutMode,
                veil: runtime.chromeVeil,
                alive: runtime.alive(.overlay),
                onMove: { runtime.hudLayout.overlay = $0 },
                onStore: { runtime.hudLayout.save() }
            ) {
                overlayRail
            }
            if !hits.isEmpty {
                hitList
                    .opacity(runtime.chromeVeil * runtime.alive(.search))
            }
            if hits.isEmpty {
                markList
                    .opacity(runtime.chromeVeil * runtime.alive(.search))
            }
            Spacer(minLength: 0)
            fieldChrome
                .opacity(runtime.chromeVeil)
                .allowsHitTesting(false)
            if runtime.hudCrisis {
                crisisStrip
            }
            HUDPlaced(
                offset: runtime.hudLayout.dock,
                arranging: runtime.hudLayoutMode,
                veil: runtime.chromeVeil,
                alive: runtime.alive(.dock),
                onMove: { runtime.hudLayout.dock = $0 },
                onStore: { runtime.hudLayout.save() }
            ) {
                dock
            }
            HUDPlaced(
                offset: runtime.hudLayout.footer,
                arranging: runtime.hudLayoutMode,
                veil: runtime.chromeVeil,
                alive: runtime.alive(.footer),
                onMove: { runtime.hudLayout.footer = $0 },
                onStore: { runtime.hudLayout.save() }
            ) {
                canvasFooter(packName: packName, offPack: offPack)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                TextField("SEARCH", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.silver)
                    .padding(.horizontal, 12)
                    .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                    .background(Theme.glass())
                    .clipShape(Theme.plateRect())
                    .overlay(
                        Theme.plateRect()
                            .strokeBorder(Theme.metalStroke, lineWidth: 1)
                    )
                    .onSubmit {
                        runtime.touch(.search)
                        search()
                    }
                    .onTapGesture { runtime.touch(.search) }
                    .onChange(of: query) { _, _ in
                        sayFailed = false
                        runtime.touch(.search)
                        search()
                    }
                Button("SAY") { say() }
                    .buttonStyle(HUDOverlayChipStyle())
            }
            if sayFailed {
                Text("SAY FAILED")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.warn)
            }
            if SearchIndex.asking(query), packedIndex != nil, !looking, hits.isEmpty {
                Text("NO MATCH")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.warn)
            }
        }
    }

    private var overlayRail: some View {
        HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
            Button(BlackoutTokens.MapOverlay.instrumentsTitle) {
                runtime.touch(.overlay)
                runtime.showInstruments = true
            }
            .buttonStyle(HUDOverlayChipStyle())
            Button(BlackoutTokens.MapOverlay.lockTitle(locked: runtime.lockOn)) {
                runtime.toggleLockOn()
            }
            .buttonStyle(HUDOverlayChipStyle())
        }
    }

    private var hitList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(hits.prefix(BlackoutTokens.Chrome.mapSearchHitCap).enumerated()), id: \.offset) { _, h in
                let word = SearchHUDWord.from(packed: h.kind).title
                let range = h.meters.map { SearchIndex.rangeLabel($0) }
                let label = [h.name, word, range].compactMap { $0 }.joined(separator: " · ")
                Button(label) {
                    if h.kind == "address" {
                        runtime.holdAddress(h)
                    } else {
                        runtime.pickDestination(lat: h.lat, lon: h.lon)
                    }
                    hits = []
                    query = ""
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.silver)
                .lineLimit(2)
                .minimumScaleFactor(1)
                .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                .padding(.horizontal, 12)
            }
        }
        .background(Theme.glass())
        .clipShape(Theme.plateRect())
    }

    private var markList: some View {
        let rows = Array(runtime.marks.suffix(BlackoutTokens.Chrome.mapSearchHitCap).reversed())
        return Group {
            if !SearchIndex.asking(query), !rows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { m in
                        Button(m.label) {
                            runtime.pickDestination(lat: m.lat, lon: m.lon)
                        }
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.silver)
                        .lineLimit(2)
                        .minimumScaleFactor(1)
                        .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                        .padding(.horizontal, 12)
                    }
                }
                .background(Theme.glass())
                .clipShape(Theme.plateRect())
            }
        }
    }

    /// Up to three short deduped lines, printed where the thumb already is.
    /// COORDINATES sit on void — no grey glass plate over the map.
    private var fieldChrome: some View {
        let dest = runtime.routeTarget
        let you = runtime.gnssYou
        let destActive = MapFieldChrome.destRailVisible(
            hasDestination: dest != nil,
            lockOn: runtime.lockOn,
            hasRoute: !runtime.routeCoords.isEmpty,
            hasYouFix: you != nil
        )
        let point = destActive ? (dest ?? you) : nil
        let lines = MapFieldChrome.lines(
            lock: runtime.lockChrome,
            route: runtime.routeChrome,
            tool: runtime.toolChrome,
            dest: dest,
            you: you,
            speak: runtime.speechChrome
        )
        return Group {
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        switch line.slot {
                        case .status, .speak:
                            Text(line.text)
                                .font(.caption.weight(line.warn ? .bold : .semibold))
                                .foregroundStyle(line.warn ? Theme.warn : Theme.silver)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .shadow(color: Theme.void.opacity(0.95), radius: 3)
                                .shadow(color: Theme.void.opacity(0.72), radius: 8)
                        case .dest:
                            MapFieldDestRail(dest: point)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }

    private struct MapFieldDestRail: View {
        var dest: (lat: Double, lon: Double)?
        @State private var beat: Double = 0.28

        var body: some View {
            let field = MapFieldChrome.destValue(point: dest)
            let fieldInk = destInk(MapFieldDestMode.coordinates)
            return VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: CGFloat(BlackoutTokens.Chrome.mapActionRailSpacingPoints)) {
                    chip(MapFieldDestMode.coordinates)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(field)
                    .font(.system(size: BlackoutTokens.Chrome.mapActionChipTextPoints, weight: .heavy))
                    .foregroundStyle(fieldInk)
                    .lineLimit(1)
                    .minimumScaleFactor(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .shadow(color: Theme.void.opacity(0.95), radius: 3)
                    .shadow(color: fieldInk.opacity(0.28 + 0.42 * beat), radius: 5 + 5 * beat)
                    .accessibilityLabel(MapFieldDestMode.coordinates.title)
                    .accessibilityValue(field)
            }
            .padding(.vertical, 6)
            .onAppear {
                withAnimation(Theme.Motion.beat) {
                    beat = 1
                }
            }
        }

        private func destInk(_ destMode: MapFieldDestMode) -> Color {
            switch destMode {
            case .coordinates:
                return Theme.fix
            }
        }

        private func chip(_ chipMode: MapFieldDestMode) -> some View {
            Button {
            } label: {
                Text(chipMode.title)
            }
            .buttonStyle(
                MapFieldDestChipStyle(ink: destInk(chipMode), expanded: true, beat: beat)
            )
            .layoutPriority(1)
            .accessibilityLabel(chipMode.title)
            .accessibilityAddTraits(.isSelected)
        }
    }

    /// The overlay tab strip (or left-hand column) sits on the canvas. HUD
    /// chrome has to stop short of it or MARK / FIELD land under a tab.
    private var hudReserve: EdgeInsets {
        if runtime.leftHand {
            return EdgeInsets(
                top: 0,
                leading: CGFloat(BlackoutTokens.Chrome.hudSideReservePoints),
                bottom: 0,
                trailing: 0
            )
        }
        return EdgeInsets(
            top: 0,
            leading: 0,
            bottom: CGFloat(BlackoutTokens.Chrome.hudTabReservePoints),
            trailing: 0
        )
    }

    /// SOS is a mesh event. This strip is the all-clear, not a second SOS.
    private var crisisStrip: some View {
        HStack(spacing: 8) {
            Text(L10n.t("sos.mesh", runtime.locale))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.accent)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
            Spacer(minLength: 8)
            Button(L10n.t("ok.chip", runtime.locale)) { runtime.iamOK() }
                .buttonStyle(HUDOverlayChipStyle())
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Theme.glass(opacity: 0.78))
        .clipShape(Theme.plateRect())
        .overlay(
            Theme.plateRect()
                .strokeBorder(Theme.accent.opacity(0.85), lineWidth: 1)
        )
    }

    /// Four cells, equal width, 44pt. Nothing here is ever disabled — a tap
    /// draws, or it says why not.
    private var dock: some View {
        HStack(spacing: 1) {
            ForEach(BlackoutTokens.MapDock.allCases, id: \.self) { cell in
                Button(cell.title) { tapDock(cell) }
                    .buttonStyle(HUDDockStyle())
            }
        }
        .background(Theme.glass())
        .clipShape(Theme.plateRect())
        .overlay(
            Theme.plateRect()
                .strokeBorder(Theme.metalStroke, lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
    }

    private func tapDock(_ cell: BlackoutTokens.MapDock) {
        runtime.touch(.dock)
        switch cell {
        case .mark:
            runtime.dropMark()
        case .walk:
            runtime.navigate(mode: .walk)
        case .drive:
            runtime.navigate(mode: .drive)
        case .speak:
            runtime.speakMap()
        }
    }

    /// Everything the canvas is allowed to say: which pack, and one way back
    /// out to the whole region. No byte counts, no raw coordinates, no vendor mark.
    private func canvasFooter(packName: String, offPack: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if offPack {
                    Text(PackChrome.offPack)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
                Text(packName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.silver)
            }
            Spacer()
            Button("FIT PACK") {
                runtime.touch(.footer)
                runtime.fitPack()
            }
                .buttonStyle(HUDOverlayChipStyle())
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    private func styleURL() -> URL? {
        guard let style = runtime.packs?.packURL("style.json") else { return nil }
        let root = style.deletingLastPathComponent()
        return (try? PackStyle.resolved(styleAt: style, packRoot: root)) ?? style
    }

    private func search() {
        guard SearchIndex.asking(query) else {
            searchGen &+= 1
            looking = false
            hits = []
            return
        }
        guard let idx = packedIndex else { return }
        searchGen &+= 1
        let gen = searchGen
        looking = true
        let asked = query
        let you = runtime.gnssYou
        let extra = runtime.marks.map {
            SearchExtra(name: $0.label, kind: "mark", lat: $0.lat, lon: $0.lon)
        }
        let cap = BlackoutTokens.Chrome.mapSearchHitCap
        Task.detached(priority: .userInitiated) {
            let found = idx.lookup(asked, you: you, extra: extra, cap: cap)
            await MainActor.run {
                applySearch(found, gen: gen)
            }
        }
    }

    private func applySearch(_ found: [SearchHit], gen: UInt64) {
        guard gen == searchGen else { return }
        hits = found
        looking = false
    }

    private func loadIndex() {
        let packID = runtime.packs?.active?.id
        let url = runtime.packs?.packURL("search.json")
            ?? runtime.packs?.packURL("pois.geojson")
        guard let url else {
            packedIndex = SearchIndex(pois: [])
            return
        }
        Task.detached(priority: .userInitiated) {
            let data = (try? Data(contentsOf: url)) ?? Data()
            let idx = SearchIndex.load(data: data)
            await MainActor.run {
                applyLoadedIndex(idx, packID: packID)
            }
        }
    }

    private func applyLoadedIndex(_ idx: SearchIndex, packID: String?) {
        guard runtime.packs?.active?.id == packID else { return }
        packedIndex = idx
        if SearchIndex.asking(query) {
            search()
        }
    }

    /// Spoken place uses the same lookup as type. Deny, PTT live, and
    /// a missing on-device recognizer are SAY FAILED — not a network model.
    private func say() {
        sayFailed = false
        if runtime.ptt.live || runtime.clipLive {
            sayFailed = true
            return
        }
        if runtime.speech.listening {
            runtime.speech.endListen()
            return
        }
        let started = runtime.speech.listen(locale: runtime.locale) { spoken in
            if spoken.isEmpty {
                sayFailed = true
                return
            }
            query = spoken
            search()
        }
        if !started {
            sayFailed = true
        }
    }
}
