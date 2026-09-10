import SwiftUI
import MapLibreMap
import Search
import Router
import Tokens

struct MapTab: View {
    @Bindable var runtime: AppRuntime
    @State private var query = ""
    @State private var hits: [SearchHit] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            actionRail
            TextField("Search this pack", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { search() }
            ForEach(hits, id: \.name) { h in
                Button("\(h.name) · \(h.kind)") {
                    runtime.pickDestination(lat: h.lat, lon: h.lon)
                }
                .foregroundStyle(Theme.silver)
            }
            if let pack = runtime.packs?.active, let style = styleURL() {
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
                )
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
                        onMapTap: { lat, lon in
                            runtime.pickDestination(lat: lat, lon: lon)
                        },
                        onMapHold: { lat, lon, tags in
                            runtime.holdInspect(lat: lat, lon: lon, tags: tags)
                        }
                    )
                    // The scrim already keeps a thumb off the canvas. This is
                    // the same thing for VoiceOver, and only the canvas: the
                    // tab bar stays reachable, because Comms is on it.
                    .accessibilityHidden(runtime.held != nil)
                    if runtime.held == nil {
                        canvasFooter(packName: pack.name, offPack: offPack == PackChrome.offPack)
                    }
                    if let held = runtime.held {
                        HoldCardView(
                            held: held,
                            onField: { runtime.openFieldFromHold() },
                            onMark: { runtime.markHeld() },
                            onClose: { runtime.closeHold() }
                        )
                    }
                }
                .overlay(alignment: .topLeading) {
                    // The card takes the bottom of the canvas and the footer's
                    // credit with it, but the top half is still drawing OSM's
                    // map. The line has to stay wherever the map is, so it
                    // moves up above the scrim rather than going away.
                    if runtime.held != nil {
                        Text(OSMCredit.line)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(white: 0.75))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.void.opacity(0.66))
                            .padding(6)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .animation(.spring(response: 0.28, dampingFraction: 0.9), value: runtime.held)
            } else {
                Text("Packs missing from bundle — honest empty.").foregroundStyle(Color(white: 0.5))
                Spacer()
            }
            fieldChrome
            instrumentRow
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// SPEAK / INSTRUMENTS / LOCK-ON at their full width. When the line runs out the rail
    /// wraps instead of letting SwiftUI tail-truncate the longest word.
    private var actionRail: some View {
        ChromeRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
            Button("SPEAK") { runtime.speakMap() }
                .buttonStyle(MapActionChipButtonStyle())
            Button("INSTRUMENTS") { runtime.showInstruments = true }
                .buttonStyle(MapActionChipButtonStyle())
            Button(runtime.lockOn ? "LOCKED" : "LOCK-ON") {
                runtime.toggleLockOn()
            }
            .buttonStyle(MapActionChipButtonStyle())
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
                        .foregroundStyle(Color.orange)
                }
                Text(packName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.silver)
                Text(OSMCredit.line)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(white: 0.7))
            }
            Spacer()
            Button("FIT PACK") { runtime.fitPack() }
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.silver)
                .frame(minWidth: 72, minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .background(Theme.void.opacity(0.66))
    }

    /// Up to three short deduped lines, printed where the thumb already is. Lock, the
    /// answer to the last chip tap and the tool readout share the first line; the
    /// heading gets the second; Speak reports one status line on the third.
    private var fieldChrome: some View {
        ForEach(
            MapFieldChrome.lines(
                lock: runtime.lockChrome,
                route: runtime.routeChrome,
                tool: runtime.toolChrome,
                bearingDeg: runtime.headingDeg,
                speak: runtime.speechChrome
            )
        ) { line in
            Text(line.text)
                .font(.caption.weight(line.warn ? .bold : .semibold))
                .foregroundStyle(line.warn ? Color.orange : Theme.silver)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Bottom chip bar. Nothing here is ever disabled — a tap draws, or it says why not.
    private var instrumentRow: some View {
        HStack(spacing: 4) {
            Button("MARK") { runtime.dropMark() }
                .buttonStyle(MapChipButtonStyle())
            Button("WALK") { runtime.navigate(mode: .walk) }
                .buttonStyle(MapChipButtonStyle())
            Button("DRIVE") { runtime.navigate(mode: .drive) }
                .buttonStyle(MapChipButtonStyle())
            Button("RULER") { runtime.tapRuler() }
                .buttonStyle(MapChipButtonStyle())
            Button("USNG") { runtime.tapUSNG() }
                .buttonStyle(MapChipButtonStyle())
            Button("MAG/TRUE") { runtime.tapMagTrue() }
                .buttonStyle(MapChipButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                return ["name": props["name"] as? String ?? props["amenity"] as? String ?? "poi", "kind": props["amenity"] as? String ?? props["natural"] as? String ?? "poi", "lat": coords[1], "lon": coords[0]]
            }
            hits = SearchIndex(pois: pois).fts(query)
            if hits.isEmpty { hits = SearchIndex(pois: pois).semantic(query) }
        } else {
            hits = idx.fts(query)
        }
    }
}

private struct MapChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let hit = BlackoutTokens.Chrome.mapChipHitPoints
        return configuration.label
            .font(.system(size: 10, weight: .bold))
            .lineLimit(2)
            .minimumScaleFactor(0.55)
            .multilineTextAlignment(.center)
            .frame(width: hit, height: hit)
            .contentShape(Rectangle())
            .background(Theme.raised)
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

/// Header chip that keeps its whole label. Fixed point size and `fixedSize` mean the
/// title can never be tail-truncated; the rail wraps the chip to the next line instead.
private struct MapActionChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let hit = BlackoutTokens.Chrome.mapChipHitPoints
        return configuration.label
            .font(.system(size: BlackoutTokens.Chrome.mapActionChipTextPoints, weight: .bold))
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, BlackoutTokens.Chrome.mapActionChipGutterPoints)
            .frame(minWidth: hit, minHeight: hit)
            .contentShape(Rectangle())
            .background(Theme.raised)
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

/// Left-aligned rail that moves a control to the next line when the current one is full.
private struct ChromeRail: Layout {
    var spacing: CGFloat

    init(spacing: Double) {
        self.spacing = CGFloat(spacing)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = rowsFitting(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY
        for row in rowsFitting(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rowsFitting(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, width > maxWidth {
                rows.append(row)
                row = Row(indices: [index], width: size.width, height: size.height)
            } else {
                row.indices.append(index)
                row.width = width
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
