import CryptoKit
import Foundation
import MapLibreMap
import Network
import Observation

/// The only network socket. Airplane keeps last SNAP. Never a live stream.
@MainActor
@Observable
final class UpdateSocket {
    var pipe = false
    var busy = false
    var chrome = EyeDesk.noPipe
    var updatedAt: Date?
    var offLabels: [String] = SnapKind.allCases.map(\.offTitle)
    var lastManifest: SnapManifest?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "blackout.update.path")
    private var session: URLSession?

    func start() {
        lastManifest = SnapManifest.load()
        if let loaded = lastManifest {
            updatedAt = loaded.at
            chrome = EyeDesk.updatedChrome(pipe: true, at: loaded.at)
            offLabels = loaded.off
        }
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.pipe = path.status == .satisfied
                guard let self else { return }
                if !self.pipe && !self.busy {
                    self.chrome = EyeDesk.noPipe
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func tap(
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        lat: Double,
        lon: Double,
        packRoot: URL?
    ) {
        guard !busy else { return }
        if !pipe {
            chrome = EyeDesk.noPipe
            return
        }
        busy = true
        chrome = EyeDesk.updatingTitle
        Task {
            await burst(
                south: south,
                west: west,
                north: north,
                east: east,
                lat: lat,
                lon: lon,
                packRoot: packRoot
            )
        }
    }

    func burst(
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        lat: Double,
        lon: Double,
        packRoot: URL?
    ) async {
        defer { busy = false }
        guard pipe else {
            chrome = EyeDesk.noPipe
            return
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        let session = URLSession(configuration: config)
        self.session = session
        var off: [String] = []
        var files: [String] = []
        var camStill: [SnapCam] = []

        if let data = await get(
            session,
            "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,wind_speed_10m,weather_code&timezone=auto"
        ) {
            write("weather.json", data)
            files.append("weather.json")
        } else {
            off.append(SnapKind.weather.offTitle)
        }
        off.append(SnapKind.alerts.offTitle)

        off.append(SnapKind.firms.offTitle)

        if let data = await get(
            session,
            "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson"
        ) {
            let clipped = clipQuakes(data, south: south, west: west, north: north, east: east)
            write("quakes.geojson", clipped)
            files.append("quakes.geojson")
        } else {
            off.append(SnapKind.quakes.offTitle)
        }

        off.append(SnapKind.dot.offTitle)
        off.append(SnapKind.fire.offTitle)
        off.append(SnapKind.reservoir.offTitle)
        off.append(SnapKind.airQuality.offTitle)
        off.append(SnapKind.tle.offTitle)
        off.append(SnapKind.field.offTitle)
        off.append(SnapKind.mag.offTitle)
        off.append(SnapKind.air.offTitle)
        off.append(SnapKind.ais.offTitle)

        if let packRoot, let delta = await osmDelta(
            session,
            south: south,
            west: west,
            north: north,
            east: east
        ) {
            write("osm-delta.geojson", delta)
            files.append("osm-delta.geojson")
        } else {
            off.append(SnapKind.osmDelta.offTitle)
        }

        let packedCams = packCams(packRoot)
        if packedCams.isEmpty {
            off.append(SnapKind.cams.offTitle)
        } else {
            let nearest = packedCams
                .sorted { range2($0, lat: lat, lon: lon) < range2($1, lat: lat, lon: lon) }
                .prefix(CctvMarks.snapCap)
            var byID: [String: SnapCam] = [:]
            if let old = lastManifest?.cams {
                for cam in old where !cam.id.isEmpty {
                    byID[cam.id] = cam
                }
            }
            for cam in nearest {
                if let data = await get(session, cam.url),
                   let jpeg = Self.stillJPEG(data),
                   jpeg.count > 32
                {
                    let name = "cam-\(cam.id).jpg"
                    write(name, jpeg)
                    files.append(name)
                    byID[cam.id] = SnapCam(
                        id: cam.id,
                        lat: cam.lat,
                        lon: cam.lon,
                        file: name,
                        at: Date()
                    )
                }
            }
            camStill = Array(byID.values)
            for cam in camStill where !files.contains(cam.file) {
                files.append(cam.file)
            }
            if camStill.isEmpty { off.append(SnapKind.cams.offTitle) }
        }

        let clock = ISO8601DateFormatter().string(from: Date())
        write("clock.txt", Data(clock.utf8))
        files.append("clock.txt")

        if let packRoot, let style = try? Data(contentsOf: packRoot.appendingPathComponent("style.json")) {
            let digest = SHA256.hash(data: style)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            write("checksums.txt", Data("style.json \(hex)\n".utf8))
            files.append("checksums.txt")
        } else {
            off.append(SnapKind.checksums.offTitle)
        }
        off.append(SnapKind.highlights.offTitle)

        session.invalidateAndCancel()
        self.session = nil

        let at = Date()
        let manifest = SnapManifest(
            at: at,
            files: files,
            off: off,
            cams: camStill,
            stamp: EyeDesk.snapStamp
        )
        manifest.save()
        lastManifest = manifest
        updatedAt = at
        offLabels = off
        chrome = EyeDesk.updatedChrome(pipe: true, at: at)
    }

    private func get(_ session: URLSession, _ raw: String) async -> Data? {
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https" else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func osmDelta(
        _ session: URLSession,
        south: Double,
        west: Double,
        north: Double,
        east: Double
    ) async -> Data? {
        let query = """
        [out:json][timeout:8];(way[\"highway\"](\(south),\(west),\(north),\(east)););out geom 40;
        """
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return await get(session, "https://overpass-api.de/api/interpreter?data=\(encoded)")
    }

    private func clipQuakes(
        _ data: Data,
        south: Double,
        west: Double,
        north: Double,
        east: Double
    ) -> Data {
        guard
            var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let features = json["features"] as? [[String: Any]]
        else { return data }
        let kept = features.filter { feature in
            guard
                let geom = feature["geometry"] as? [String: Any],
                let coords = geom["coordinates"] as? [Double],
                coords.count >= 2
            else { return false }
            let lon = coords[0]
            let lat = coords[1]
            return lat >= south && lat <= north && lon >= west && lon <= east
        }
        json["features"] = kept
        return (try? JSONSerialization.data(withJSONObject: json)) ?? data
    }

    private func packCams(_ packRoot: URL?) -> [PackCam] {
        guard let packRoot else { return [] }
        let url = packRoot.appendingPathComponent("cameras.json")
        guard
            let data = try? Data(contentsOf: url),
            let rows = try? JSONDecoder().decode([PackCam].self, from: data)
        else { return [] }
        return rows.filter { !$0.id.isEmpty && $0.url.hasPrefix("https://") }
    }

    /// Raw JPEG, or TxDOT JSON `{snippet: base64 jpeg}`. Nothing else.
    static func stillJPEG(_ data: Data) -> Data? {
        if data.count >= 3, data[0] == 0xFF, data[1] == 0xD8 {
            return data
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let snippet = (obj["snippet"] as? String) ?? (obj["Snippet"] as? String)
        guard let snippet, !snippet.isEmpty, let raw = Data(base64Encoded: snippet) else {
            return nil
        }
        if raw.count >= 3, raw[0] == 0xFF, raw[1] == 0xD8 {
            return raw
        }
        return nil
    }

    private func range2(_ cam: PackCam, lat: Double, lon: Double) -> Double {
        let dlat = cam.lat - lat
        let dlon = (cam.lon - lon) * cos(lat * .pi / 180)
        return dlat * dlat + dlon * dlon
    }

    private func write(_ name: String, _ data: Data) {
        let dir = SnapManifest.folder()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }
}

enum SnapKind: String, CaseIterable, Sendable {
    case weather
    case alerts
    case firms
    case quakes
    case dot
    case fire
    case reservoir
    case airQuality
    case tle
    case field
    case cams
    case mag
    case clock
    case checksums
    case highlights
    case osmDelta
    case air
    case ais

    var offTitle: String {
        switch self {
        case .weather: return "OFF WEATHER"
        case .alerts: return "OFF ALERTS"
        case .firms: return "OFF FIRMS"
        case .quakes: return "OFF QUAKES"
        case .dot: return "OFF DOT"
        case .fire: return "OFF FIRE"
        case .reservoir: return "OFF RESERVOIR"
        case .airQuality: return "OFF AQI"
        case .tle: return "OFF TLE"
        case .field: return "OFF FIELD PACK"
        case .cams: return "OFF CAMS"
        case .mag: return "OFF MAG"
        case .clock: return "OFF CLOCK"
        case .checksums: return "OFF CHECKSUMS"
        case .highlights: return "OFF HIGHLIGHTS"
        case .osmDelta: return "OFF OSM DELTA"
        case .air: return "OFF AIR"
        case .ais: return "OFF AIS"
        }
    }
}

struct PackCam: Codable, Sendable {
    var id: String
    var url: String
    var lat: Double
    var lon: Double
    var name: String
    var ink: String
    var provider: String

    enum CodingKeys: String, CodingKey {
        case id, url, lat, lon, name, ink, provider
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        lat = try c.decode(Double.self, forKey: .lat)
        lon = try c.decode(Double.self, forKey: .lon)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        ink = try c.decodeIfPresent(String.self, forKey: .ink) ?? "blue"
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(url, forKey: .url)
        try c.encode(lat, forKey: .lat)
        try c.encode(lon, forKey: .lon)
        try c.encode(name, forKey: .name)
        try c.encode(ink, forKey: .ink)
        try c.encode(provider, forKey: .provider)
    }
}

struct SnapCam: Codable, Sendable {
    var id: String
    var lat: Double
    var lon: Double
    var file: String
    var at: Date
}

struct SnapManifest: Codable, Sendable {
    var at: Date
    var files: [String]
    var off: [String]
    var cams: [SnapCam]
    var stamp: String

    static func folder() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Blackout/SNAP", isDirectory: true)
    }

    func save() {
        let dir = Self.folder()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
        }
    }

    static func load() -> SnapManifest? {
        let url = folder().appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SnapManifest.self, from: data)
    }
}
