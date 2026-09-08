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
            instrumentRow
            fieldChrome
            TextField("Search FTS / semantic", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { search() }
            ForEach(hits, id: \.name) { h in
                Button("\(h.name) · \(h.kind)") {
                    runtime.pickDestination(lat: h.lat, lon: h.lon)
                }
                .foregroundStyle(Theme.silver)
            }
            if let pack = runtime.packs?.active, let style = styleURL() {
                let you = UserPuck.coordinate(
                    lastKnown: runtime.lastKnownFix,
                    packCenter: (pack.center.lat, pack.center.lon),
                    packSouth: pack.bbox.south,
                    packWest: pack.bbox.west,
                    packNorth: pack.bbox.north,
                    packEast: pack.bbox.east
                )
                let offPack = PackChrome.banner(
                    fix: runtime.lastKnownFix,
                    bbox: (pack.bbox.south, pack.bbox.west, pack.bbox.north, pack.bbox.east)
                )
                Text("\(pack.name) · \(pack.bytes / 1024) KB · \(pack.state)")
                    .foregroundStyle(Color(white: 0.6))
                Text(OSMCredit.line)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(white: 0.7))
                if offPack == PackChrome.offPack {
                    Text(PackChrome.offPack).font(.caption.weight(.bold)).foregroundStyle(Color.orange)
                }
                ZStack(alignment: .bottomLeading) {
                    OfflineMapView(
                        styleURL: style,
                        centerLat: pack.center.lat,
                        centerLon: pack.center.lon,
                        puckLat: you.lat,
                        puckLon: you.lon,
                        packSouth: pack.bbox.south,
                        packWest: pack.bbox.west,
                        packNorth: pack.bbox.north,
                        packEast: pack.bbox.east,
                        route: runtime.routeCoords,
                        onMapTap: { lat, lon in
                            runtime.pickDestination(lat: lat, lon: lon)
                        }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                ForEach(runtime.marks) { m in
                    Button("MARK \(m.label) \(String(format: "%.4f", m.lat)), \(String(format: "%.4f", m.lon))") {
                        runtime.pickDestination(lat: m.lat, lon: m.lon)
                    }
                    .font(.caption).foregroundStyle(Color(white: 0.75))
                }
            } else {
                Text("Packs missing from bundle — honest empty.").foregroundStyle(Color(white: 0.5))
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// SPEAK / INSTRUMENTS / LOCK-ON at their full width. When the line runs out the rail
    /// wraps instead of letting SwiftUI tail-truncate the longest word.
    private var actionRail: some View {
        ChromeRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
            Text("MAP")
                .font(.system(size: BlackoutTokens.Chrome.mapActionChipTextPoints, weight: .heavy))
                .foregroundStyle(Theme.silver)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
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

    /// Up to three short deduped lines. `OFF GRAPH` twice, a bare `TRUE`, DEST, BEARING
    /// and a full turn-by-turn script used to spray the field; Speak now reports one
    /// status line here and leaves the script to the voice and the cyan route.
    private var fieldChrome: some View {
        ForEach(
            MapFieldChrome.lines(
                lock: runtime.lockChrome,
                route: runtime.routeChrome,
                tool: runtime.toolChrome,
                dest: runtime.routeTarget,
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

    private var instrumentRow: some View {
        HStack(spacing: 4) {
            Button("MARK") { runtime.dropMark() }
                .buttonStyle(MapChipButtonStyle())
            Button("WALK") { runtime.navigate(mode: .walk) }
                .disabled(!runtime.walkDriveEnabled)
                .buttonStyle(MapChipButtonStyle())
            Button("DRIVE") { runtime.navigate(mode: .drive) }
                .disabled(!runtime.walkDriveEnabled)
                .buttonStyle(MapChipButtonStyle())
            Button("RULER") { runtime.tapRuler() }
                .buttonStyle(MapChipButtonStyle())
            Button("USNG") { runtime.tapUSNG() }
                .buttonStyle(MapChipButtonStyle())
            Button("MAG/TRUE") { runtime.tapMagTrue() }
                .buttonStyle(MapChipButtonStyle())
        }
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
        let rows = rows(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY
        for row in rows(maxWidth: bounds.width, subviews: subviews) {
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

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
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
