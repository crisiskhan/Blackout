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
                held: runtime.held.map { (lat: $0.lat, lon: $0.lon) },
                fitToken: runtime.fitPackToken,
                interactive: MapCanvasHit.enabled(
                    onMap: runtime.tab == .map,
                    holding: runtime.held != nil,
                    arranging: runtime.hudLayoutMode
                ),
                onMapTap: { lat, lon in
                    runtime.pickDestination(lat: lat, lon: lon)
                    hits = []
                },
                onMapHold: { lat, lon, tags, zoom in
                    runtime.holdInspect(lat: lat, lon: lon, tags: tags, zoom: zoom)
                },
                pips: runtime.mesh.pips
                    .filter { $0.from != runtime.mesh.localID }
                    .map { (lat: $0.lat, lon: $0.lon) },
                onPulse: { runtime.pulse() },
                lockOn: runtime.lockOn,
                travelMode: runtime.travelMode
            )
            .ignoresSafeArea()
            // The scrim already keeps a thumb off the canvas. This is the
            // same thing for VoiceOver, and only the canvas: the tab bar
            // stays reachable, because Comms is on it.
            .accessibilityHidden(runtime.held != nil)
            if runtime.tab == .map, runtime.held == nil {
                hud(packName: pack.name, offPack: offPack)
                    .padding(hudReserve)
            }
            if runtime.tab == .map, let held = runtime.held {
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
        .overlay(alignment: .topLeading) {
            // The card takes the bottom of the canvas and the footer's credit
            // with it, but the top half is still drawing OSM's map. The line
            // has to stay wherever the map is.
            if runtime.tab == .map, runtime.held != nil {
                Text(OSMCredit.line)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.silver.opacity(0.75))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.void.opacity(0.66))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .animation(runtime.chromeAwake ? Theme.Motion.wake : Theme.Motion.sleep, value: runtime.chromeAwake)
        .animation(Theme.Motion.heavy, value: runtime.hudFocus)
        .animation(Theme.Motion.heavy, value: runtime.held)
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
            osmCredit
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var searchField: some View {
        TextField("SEARCH", text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.silver)
            .padding(.horizontal, 12)
            .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
            .background(Theme.glass())
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.silver.opacity(0.22), lineWidth: 1)
            )
            .onSubmit {
                runtime.touch(.search)
                search()
            }
            .onTapGesture { runtime.touch(.search) }
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
            ForEach(hits.prefix(BlackoutTokens.Chrome.mapSearchHitCap), id: \.name) { h in
                Button("\(h.name) · \(h.kind)") {
                    runtime.pickDestination(lat: h.lat, lon: h.lon)
                    hits = []
                    query = ""
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.silver)
                .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                .padding(.horizontal, 12)
            }
        }
        .background(Theme.glass())
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var markList: some View {
        let rows = Array(runtime.marks.suffix(BlackoutTokens.Chrome.mapSearchHitCap).reversed())
        return Group {
            if !rows.isEmpty {
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
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    /// Up to three short deduped lines, printed where the thumb already is.
    private var fieldChrome: some View {
        let lines = MapFieldChrome.lines(
            lock: runtime.lockChrome,
            route: runtime.routeChrome,
            tool: runtime.toolChrome,
            bearingDeg: MapFieldChrome.activeBearing(
                headingDeg: runtime.headingDeg,
                hasDestination: runtime.routeTarget != nil,
                lockOn: runtime.lockOn,
                hasRoute: !runtime.routeCoords.isEmpty
            ),
            speak: runtime.speechChrome
        )
        return Group {
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(.caption.weight(line.warn ? .bold : .semibold))
                            .foregroundStyle(line.warn ? Theme.warn : Theme.silver)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.glass(opacity: 0.62))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
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
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
        .background(Theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.silver.opacity(0.22), lineWidth: 1)
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

    /// Everything the canvas is allowed to say: which pack, who drew it, and
    /// one way back out to the whole region. No byte counts, no raw coordinates.
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

    /// License stays when chrome sleeps. Pack name can fade; this cannot.
    private var osmCredit: some View {
        Text(OSMCredit.line)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.silver.opacity(0.75))
            .allowsHitTesting(false)
    }

    private func styleURL() -> URL? {
        guard let style = runtime.packs?.packURL("style.json") else { return nil }
        let root = style.deletingLastPathComponent()
        return (try? PackStyle.resolved(styleAt: style, packRoot: root)) ?? style
    }

    private func search() {
        let idx = SearchIndex(pois: [["name": query, "kind": "place", "lat": 0.0, "lon": 0.0]])
        if let pack = runtime.packs?.packURL("pois.geojson"),
           let data = try? Data(contentsOf: pack),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let feats = obj["features"] as? [[String: Any]] {
            let pois: [[String: Any]] = feats.compactMap { f in
                guard let props = f["properties"] as? [String: Any],
                      let geom = f["geometry"] as? [String: Any],
                      let coords = geom["coordinates"] as? [Double], coords.count >= 2 else { return nil }
                return [
                    "name": props["name"] as? String ?? props["amenity"] as? String ?? "poi",
                    "kind": props["amenity"] as? String ?? props["natural"] as? String ?? "poi",
                    "lat": coords[1],
                    "lon": coords[0],
                ]
            }
            let found = SearchIndex(pois: pois)
            hits = found.fts(query)
            if hits.isEmpty { hits = found.semantic(query) }
        } else {
            hits = idx.fts(query)
        }
    }
}
