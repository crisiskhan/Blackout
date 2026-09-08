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
            HStack {
                Text("MAP").foregroundStyle(Theme.silver)
                Spacer()
                Button("SPEAK") { runtime.speakMap() }
                    .buttonStyle(MapChipButtonStyle())
                Button("INSTRUMENTS") { runtime.showInstruments = true }
                Button(runtime.lockOn ? "LOCKED" : "LOCK-ON") {
                    runtime.toggleLockOn()
                }
            }
            if !runtime.lockChrome.isEmpty {
                Text(runtime.lockChrome).font(.caption.weight(.bold)).foregroundStyle(Color.orange)
            }
            if let dest = runtime.routeTarget {
                Text(String(format: "DEST %.4f, %.4f", dest.lat, dest.lon))
                    .font(.caption).foregroundStyle(Theme.silver)
            }
            if let h = runtime.headingDeg {
                Text(String(format: "BEARING %.0f°", h)).font(.caption).foregroundStyle(Theme.silver)
            }
            if !runtime.speechChrome.isEmpty {
                Text(runtime.speechChrome)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
            chipAnswer
            instrumentRow
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The answer to the last chip tap, printed where the thumb already is.
    @ViewBuilder
    private var chipAnswer: some View {
        if !runtime.routeChrome.isEmpty {
            Text(runtime.routeChrome)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.orange)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if !runtime.toolChrome.isEmpty {
            Text(runtime.toolChrome)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.silver)
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
