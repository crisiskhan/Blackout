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
            if let pack = runtime.packs?.active {
                canvas(pack: pack)
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
    private func canvas(pack: PackManifest) -> some View {
        let home = pack.home ?? pack.center
        let you = runtime.fieldYou
        let camera = UserPuck.coordinate(
            lastKnown: you,
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
            GlobeView(
                packID: pack.id,
                centerLat: camera.lat,
                centerLon: camera.lon,
                puckLat: you?.lat ?? camera.lat,
                puckLon: you?.lon ?? camera.lon,
                showYou: you != nil,
                packSouth: pack.bbox.south,
                packWest: pack.bbox.west,
                packNorth: pack.bbox.north,
                packEast: pack.bbox.east,
                route: runtime.routeCoords,
                destination: runtime.routeTarget,
                held: runtime.held.map { (lat: $0.lat, lon: $0.lon) }
                    ?? runtime.heldAddress.map { (lat: $0.lat, lon: $0.lon) }
                    ?? runtime.markDraft.map { (lat: $0.lat, lon: $0.lon) },
                fitToken: runtime.fitPackToken,
                interactive: MapCanvasHit.enabled(
                    onMap: runtime.tab == .map,
                    holding: coverUp,
                    arranging: runtime.hudLayoutMode
                ),
                onMapTap: { lat, lon in
                    runtime.pickDestination(lat: lat, lon: lon)
                    runtime.navigate(mode: runtime.travelMode)
                    hits = []
                },
                onMapHold: { lat, lon, tags, zoom in
                    runtime.holdInspect(lat: lat, lon: lon, tags: tags, zoom: zoom)
                },
                onPersonHold: { id, lat, lon in
                    runtime.holdParty(id: id, lat: lat, lon: lon)
                    runtime.eyeTap = nil
                },
                onPersonTap: { id, lat, lon in
                    runtime.tapEyeContact(id: id, lat: lat, lon: lon)
                },
                onPersonDoubleTap: { id, _, _ in
                    runtime.followEyeContact(id)
                },
                onEmptyDoubleTap: { lat, lon in
                    runtime.plantEyeMark(kind: .rally, lat: lat, lon: lon)
                },
                pips: runtime.eyeCanvasPips(),
                youHeading: runtime.headingDeg,
                youEmblem: runtime.youEmblem.rawValue,
                onPulse: { runtime.pulse() },
                lockOn: runtime.lockOn,
                godsEye: runtime.godsEye,
                travelMode: runtime.travelMode,
                sun: runtime.lamp == .sun,
                night: runtime.lamp == .night,
                eyeLayers: runtime.eyeLayers,
                eyePalette: runtime.eyePalette,
                eyeGround: runtime.eyeGround,
                followID: runtime.eyeFollowID,
                trails: runtime.godsEye ? runtime.eyeTrails() : [],
                rings: runtime.godsEye ? runtime.eyeRings() : [],
                frameExtra: runtime.godsEye ? runtime.eyeFrameWater() : [],
                aerialURL: packFile("aerial.pmtiles"),
                demURL: packFile("dem.json"),
                waterURL: packFile("layers/water.geojson"),
                contoursURL: packFile("contours.geojson"),
                shadeURL: packFile("hillshade.png"),
                osmURL: packFile("osm.pmtiles"),
                khanURL: packFile("khan.pmtiles")
            )
            .ignoresSafeArea()
            .transaction { $0.animation = nil }
            // The scrim already keeps a thumb off the canvas. This is the
            // same thing for VoiceOver, and only the canvas: the tab bar
            // stays reachable, because Comms is on it.
            .accessibilityHidden(coverUp)
            if runtime.tab == .map, !coverUp {
                hud(packName: pack.name, offPack: offPack)
                    .padding(hudReserve)
            }
            if runtime.tab == .map, runtime.godsEye, runtime.heldParty == nil, runtime.held == nil, runtime.markDraft == nil, let tap = runtime.eyeTap {
                EyeTapStrip(
                    person: tap,
                    onCall: { runtime.callEyeTap() },
                    onMessage: { runtime.messageEyeTap() },
                    onClose: { runtime.eyeTap = nil }
                )
                .padding(hudReserve)
            }
            if runtime.tab == .map, runtime.markDraft != nil {
                PlaceMarkCard(runtime: runtime)
                    .padding(hudReserve)
            } else if runtime.tab == .map, let person = runtime.heldParty {
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
                    onFaceHold: { runtime.openEmblemPick() },
                    timers: runtime.timers,
                    kit: runtime.kit,
                    timerSeq: runtime.timerSeq,
                    kitSeq: runtime.kitSeq,
                    onKitBump: { runtime.bumpKit($0, by: $1) }
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
                    onMark: { runtime.openHeldMark() },
                    onClose: { runtime.closeHold() }
                )
                .padding(hudReserve)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .animation(Theme.Motion.heavy, value: runtime.held)
        .animation(Theme.Motion.heavy, value: runtime.heldParty)
        .animation(Theme.Motion.heavy, value: runtime.heldAddress)
        .animation(Theme.Motion.heavy, value: runtime.pickingEmblem)
        .animation(Theme.Motion.heavy, value: runtime.markDraft)
        .animation(Theme.Motion.heavy, value: runtime.showSpeakTurns)
    }

    private var coverUp: Bool {
        runtime.held != nil
            || runtime.heldParty != nil
            || runtime.heldAddress != nil
            || runtime.markDraft != nil
            || runtime.heldMark != nil
    }

    /// Everything that is not the map, sitting on the map. Search, lock, UPDATE and
    /// instruments at the top; NIGHT / SUN / EYE and the four thumb cells at the bottom.
    /// KHAN EYE is the packed Cesium desk. LAYERS / LOOK / MARK / SCENE live in Instruments.
    /// Ruler, grid and north live in Instruments — they are not a walk.
    /// The spacer is a hole: pan, tap, and hold belong to the globe, not the HUD.
    private func hud(packName: String, offPack: Bool) -> some View {
        VStack(spacing: 8) {
            if !runtime.godsEye {
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
            if !runtime.godsEye, !hits.isEmpty {
                hitList
                    .opacity(runtime.chromeVeil * runtime.alive(.search))
            }
            if !runtime.godsEye, hits.isEmpty {
                markList
                    .opacity(runtime.chromeVeil * runtime.alive(.search))
            }
            Spacer(minLength: 0)
                .allowsHitTesting(false)
            if !runtime.godsEye {
                fieldChrome
                    .opacity(runtime.chromeVeil)
            }
            if runtime.hudCrisis {
                crisisStrip
            }
            if runtime.showSpeakTurns {
                SpeakTurnCard(
                    turns: runtime.speakHUDTurns,
                    onClose: { runtime.closeSpeakTurns() }
                )
            }
            HUDPlaced(
                offset: runtime.hudLayout.dock,
                arranging: runtime.hudLayoutMode,
                veil: runtime.chromeVeil,
                alive: runtime.alive(.dock),
                onMove: { runtime.hudLayout.dock = $0 },
                onStore: { runtime.hudLayout.save() }
            ) {
                VStack(spacing: 6) {
                    lampRail
                    dock
                }
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
        .animation(runtime.chromeAwake ? Theme.Motion.wake : Theme.Motion.sleep, value: runtime.chromeAwake)
        .animation(Theme.Motion.heavy, value: runtime.hudFocus)
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                HUDField("SEARCH",
                    text: $query,
                    id: "map.search",
                    submit: "DONE",
                    pointSize: 16,
                    onOpen: { runtime.touch(.search) },
                    onSubmit: {
                        runtime.touch(.search)
                        search()
                    }
                )
                Button("SAY") { say() }
                    .buttonStyle(HUDOverlayChipStyle())
            }
            .onChange(of: query) { _, _ in
                sayFailed = false
                runtime.touch(.search)
                search()
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
            Button(BlackoutTokens.MapOverlay.lockTitle(locked: PackCamera.liveLockOn(lockOn: runtime.lockOn, godsEye: runtime.godsEye) || runtime.eyeFollowID != nil)) {
                runtime.toggleLockOn()
            }
            .buttonStyle(HUDOverlayChipStyle(filled: PackCamera.liveLockOn(lockOn: runtime.lockOn, godsEye: runtime.godsEye) || runtime.eyeFollowID != nil))
            Button(BlackoutTokens.MapOverlay.updateTitle) {
                runtime.touch(.overlay)
                runtime.tapUpdate()
            }
            .buttonStyle(HUDOverlayChipStyle(filled: runtime.updateSocket.busy))
        }
        .animation(Theme.Motion.heavy, value: runtime.updateSocket.busy)
        .animation(Theme.Motion.heavy, value: runtime.lockOn)
    }

    private var lampRail: some View {
        HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
            Button("NIGHT") { runtime.tapLamp(.night) }
                .buttonStyle(HUDOverlayChipStyle(filled: runtime.lamp == .night))
            Button("SUN") { runtime.tapLamp(.sun) }
                .buttonStyle(HUDOverlayChipStyle(filled: runtime.lamp == .sun))
            Button(BlackoutTokens.MapOverlay.godsEyeTitle) {
                runtime.toggleGodsEye()
            }
            .buttonStyle(HUDOverlayChipStyle(filled: runtime.godsEye))
        }
        .animation(Theme.Motion.heavy, value: runtime.godsEye)
        .animation(Theme.Motion.heavy, value: runtime.lamp)
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
                        runtime.navigate(mode: runtime.travelMode)
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
                        Button(m.title) {
                            runtime.pickDestination(lat: m.lat, lon: m.lon)
                            runtime.navigate(mode: runtime.travelMode)
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
    /// COORDINATES numbers sit on void — no word in a box, no grey plate.
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
                            MapFieldDestRail(
                                dest: point,
                                nextTurn: runtime.speakNextHUD,
                                onTurns: { runtime.toggleSpeakTurns() }
                            )
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
        var nextTurn: String
        var onTurns: () -> Void
        @State private var beat: Double = 0.28

        var body: some View {
            let field = MapFieldChrome.destValue(point: dest)
            let fieldInk = destInk(MapFieldDestMode.coordinates)
            let turn = nextTurn.trimmingCharacters(in: .whitespacesAndNewlines)
            return VStack(alignment: .leading, spacing: 6) {
                if !turn.isEmpty {
                    chip(MapFieldDestMode.turns)
                }
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
                if !turn.isEmpty {
                    Text(turn)
                        .font(.system(size: BlackoutTokens.Chrome.mapActionChipTextPoints, weight: .heavy))
                        .foregroundStyle(destInk(MapFieldDestMode.turns))
                        .lineLimit(1)
                        .minimumScaleFactor(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .shadow(color: Theme.void.opacity(0.95), radius: 3)
                        .accessibilityLabel(MapFieldDestMode.turns.title)
                        .accessibilityValue(turn)
                }
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
            case .turns:
                return Theme.silver
            }
        }

        private func chip(_ chipMode: MapFieldDestMode) -> some View {
            Button {
                onTurns()
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
                .strokeBorder(Theme.accent.opacity(0.85), lineWidth: Theme.strokeWidth(1))
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
                .strokeBorder(Theme.metalStroke, lineWidth: Theme.strokeWidth(1))
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

    /// Pack name on the canvas. The globe opens on YOU at walking height.
    private func canvasFooter(packName: String, offPack: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if offPack {
                Text(PackChrome.offPack)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.accent)
            }
            Text(packName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.silver)
            if !runtime.godsEye {
                Text("TAP a street · WALK follows")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.silver)
            }
            ForEach(runtime.eyeHUDLines(), id: \.self) { line in
                Text(line)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.silver)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    private func packFile(_ name: String) -> URL? {
        guard let url = runtime.packs?.packURL(name) else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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
            SearchExtra(name: $0.title, kind: "mark", lat: $0.lat, lon: $0.lon)
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
            runtime.searchIndex = packedIndex
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
        runtime.searchIndex = idx
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
            if runtime.applyEyeVoice(spoken) {
                query = ""
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

private struct EyeTapStrip: View {
    let person: HeldPerson
    let onCall: () -> Void
    let onMessage: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name.isEmpty ? "PARTY" : person.name)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color.white)
                    Text(person.status.title)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.silver)
                }
                Spacer(minLength: 8)
                Button("PTT", action: onCall)
                    .buttonStyle(HoldActionStyle(filled: true))
                Button("MESSAGE", action: onMessage)
                    .buttonStyle(HoldActionStyle(filled: false))
                Button("CLOSE", action: onClose)
                    .buttonStyle(HoldActionStyle(filled: false))
            }
            .padding(12)
            .background(Theme.glass())
            .clipShape(Theme.plateRect())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
