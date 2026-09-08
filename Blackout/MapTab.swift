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
            HStack(spacing: 8) {
                Button("SPEAK") { runtime.speakMap() }
                    .buttonStyle(MapChipButtonStyle())
                Button("INSTRUMENTS") { runtime.showInstruments = true }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.silver)
                    .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
                Spacer()
                if let heading = runtime.headingDeg {
                    Text(String(format: "%.0f°", heading))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.silver)
                }
                Button(runtime.lockOn ? "LOCKED" : "LOCK-ON") {
                    runtime.toggleLockOn()
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(runtime.lockOn ? Theme.accent : Theme.silver)
                .frame(minHeight: BlackoutTokens.Chrome.mapChipHitPoints)
            }
            if !runtime.lockChrome.isEmpty {
                Text(runtime.lockChrome).font(.caption.weight(.bold)).foregroundStyle(Color.orange)
            }
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
                        fitToken: runtime.fitPackToken,
                        onMapTap: { lat, lon in
                            runtime.pickDestination(lat: lat, lon: lon)
                        }
                    )
                    canvasFooter(packName: pack.name, offPack: offPack == PackChrome.offPack)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
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
        if !runtime.speechChrome.isEmpty {
            Text(runtime.speechChrome)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.orange)
                .lineLimit(3)
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
