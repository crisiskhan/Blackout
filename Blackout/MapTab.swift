import SwiftUI
import MapLibreMap
import Search
import RegionalPacks

struct MapTab: View {
    @Bindable var runtime: AppRuntime
    @State private var query = ""
    @State private var hits: [SearchHit] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MAP").foregroundStyle(Color(white: 0.85))
                Spacer()
                Button("INSTRUMENTS") { runtime.showInstruments = true }
                Button(runtime.lockOn ? "LOCKED" : "LOCK-ON") { runtime.lockOn.toggle() }
            }
            TextField("Search FTS / semantic", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { search() }
            if let pack = runtime.packs?.active {
                Text("\(pack.name) · \(pack.bytes / 1024) KB · \(pack.state)")
                    .foregroundStyle(Color(white: 0.6))
                if let root = runtime.packs?.packURL("style.json")?.deletingLastPathComponent(),
                   let style = try? PackStyle.resolved(styleAt: root.appendingPathComponent("style.json"), packRoot: root) {
                    OfflineMapView(styleURL: style, centerLat: pack.center.lat, centerLon: pack.center.lon)
                        .frame(minHeight: 220)
                }
                ForEach(RegionalPacks.visible(state: pack.state)) { b in
                    Text(b.title[runtime.locale] ?? b.id).font(.caption).foregroundStyle(Color(white: 0.7))
                }
                Text("Style \(pack.id)/style.json · MapLibre Metal offline · no MapKit engine")
                    .font(.caption2).foregroundStyle(Color(white: 0.45))
            }
            ForEach(hits, id: \.name) { h in
                Text("\(h.name) · \(h.kind)").foregroundStyle(Color(white: 0.8))
            }
            ScrollView(.horizontal) {
                HStack {
                    ForEach(MapTool.allCases, id: \.self) { t in
                        Text(t.rawValue).font(.caption2).padding(6).background(Color(white: 0.12))
                    }
                }
            }
            Spacer()
        }
        .padding(12)
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
