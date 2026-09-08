import SwiftUI
import MapLibreMap
import Search
import Router

struct MapTab: View {
    @Bindable var runtime: AppRuntime
    @State private var query = ""
    @State private var hits: [SearchHit] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MAP").foregroundStyle(Theme.silver)
                Spacer()
                Button("INSTRUMENTS") { runtime.showInstruments = true }
                Button(runtime.lockOn ? "LOCKED" : "LOCK-ON") {
                    runtime.toggleLockOn()
                }
            }
            HStack {
                Button("MARK") { runtime.dropMark() }
                Button("SPEAK") { runtime.speakMap() }
                Button("WALK") { runtime.navigate(mode: .walk) }
                Button("DRIVE") { runtime.navigate(mode: .drive) }
            }
            if !runtime.lockChrome.isEmpty {
                Text(runtime.lockChrome).font(.caption.weight(.bold)).foregroundStyle(Color.orange)
            }
            if !runtime.navChrome.isEmpty {
                Text(runtime.navChrome).font(.caption.weight(.bold)).foregroundStyle(Color.orange)
            }
            if let dest = runtime.routeTarget {
                Text(String(format: "DEST %.4f, %.4f", dest.lat, dest.lon))
                    .font(.caption).foregroundStyle(Theme.silver)
            }
            if let h = runtime.headingDeg {
                Text(String(format: "BEARING %.0f°", h)).font(.caption).foregroundStyle(Theme.silver)
            }
            if !runtime.speechChrome.isEmpty {
                Text(runtime.speechChrome).font(.caption.weight(.bold)).foregroundStyle(Color.orange)
            }
            TextField("Search FTS / semantic", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { search() }
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Style \(pack.id)/style.json · MapLibre Metal offline · no MapKit engine")
                            .font(.caption2).foregroundStyle(Color(white: 0.45))
                        Text(runtime.mesh.chromeNet).font(.caption2).foregroundStyle(Color(white: 0.55))
                        ForEach(runtime.marks) { m in
                            Button("MARK \(m.label) \(String(format: "%.4f", m.lat)), \(String(format: "%.4f", m.lon))") {
                                runtime.pickDestination(lat: m.lat, lon: m.lon)
                            }
                            .font(.caption).foregroundStyle(Color(white: 0.75))
                        }
                        ForEach(runtime.mesh.pips, id: \.from) { p in
                            Text("PIP \(p.from) \(String(format: "%.4f", p.lat)), \(String(format: "%.4f", p.lon))")
                                .font(.caption).foregroundStyle(Color(white: 0.7))
                        }
                        ForEach(hits, id: \.name) { h in
                            Button("\(h.name) · \(h.kind)") {
                                runtime.pickDestination(lat: h.lat, lon: h.lon)
                            }
                            .foregroundStyle(Theme.silver)
                        }
                    }
                    .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            } else {
                Text("Packs missing from bundle — honest empty.").foregroundStyle(Color(white: 0.5))
                Spacer()
            }
            ScrollView(.horizontal) {
                HStack {
                    ForEach(MapTool.allCases, id: \.self) { t in
                        switch t {
                        case .walk:
                            Button("WALK") { runtime.navigate(mode: .walk) }
                                .font(.caption2).padding(6).background(Theme.raised)
                        case .drive:
                            Button("DRIVE") { runtime.navigate(mode: .drive) }
                                .font(.caption2).padding(6).background(Theme.raised)
                        case .mark, .ruler, .usng, .magTrue, .almanac, .elevProfile,
                                .avoidPolygon, .shadePrefer, .highLow, .crossing, .truckPin,
                                .walkBackGPX, .paceCount, .tailGap, .strideCal,
                                .publicLand, .flood, .highContrast, .paper:
                            Text(t.rawValue).font(.caption2).padding(6).background(Theme.raised)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
