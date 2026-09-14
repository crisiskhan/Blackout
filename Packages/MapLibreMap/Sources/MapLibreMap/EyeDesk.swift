import Foundation
import Router

/// MAP camera + layer desk. Not a tab. Pack and phone only.
public enum EyeDesk {
    public static let persistKey = "hud.eye"
    public static let layerKey = "hud.eye.layers"
    public static let paletteKey = "hud.eye.palette"
    public static let sceneKey = "hud.eye.scenes"
    public static let soloMeters: Double = 400
    public static let lastAfterSeconds: Double = 30
    public static let lostAfterSeconds: Double = 120
    public static let trailSeconds: Double = 20 * 60
    public static let deadReckonSeconds: Double = 60
    public static let bleRingMaxMeters: Double = 200
    public static let noCard = "NO CARD · DON'T GUESS"
    public static let offAerial = "OFF AERIAL"
    public static let packStamp = "PACK"
    public static let rallyTitle = "RALLY"
    public static let calBad = "CAL BAD"
    public static let noFix = "NO FIX"
    public static let puckTitle = "PUCK"
    public static let overdueTitle = "OVERDUE"
    public static let lockTitle = "LOCK"
    public static let tailsLayerID = "eye-tails-line"
    public static let ringsLayerID = "eye-rings-line"

    public enum Age: String, Sendable {
        case live
        case last
        case lost
    }

    public enum Palette: String, CaseIterable, Sendable, Hashable {
        case streets
        case packIR
        case nvg

        public var title: String {
            switch self {
            case .streets:
                return "STREETS"
            case .packIR:
                return "PACK IR"
            case .nvg:
                return "NVG"
            }
        }
    }

    public enum Layer: String, CaseIterable, Sendable, Hashable {
        case aerial
        case shade
        case water
        case party
        case marks
        case tails

        public var title: String {
            switch self {
            case .aerial:
                return "AERIAL"
            case .shade:
                return "SHADE"
            case .water:
                return "WATER"
            case .party:
                return "PARTY"
            case .marks:
                return "MARKS"
            case .tails:
                return "TAILS"
            }
        }
    }

    public enum Ground: String, CaseIterable, Sendable {
        case streets
        case aerial
        case hybrid

        public var title: String {
            switch self {
            case .streets:
                return "STREETS"
            case .aerial:
                return "AERIAL"
            case .hybrid:
                return "HYBRID"
            }
        }
    }

    public enum Voice: Equatable, Sendable {
        case eyeOn
        case eyeOff
        case markWater
        case frame(name: String)
    }

    public enum MarkKind: String, CaseIterable, Sendable, Hashable {
        case rally = "RALLY"
        case down = "DOWN"
        case water = "WATER"
        case avoid = "AVOID"
        case hold = "HOLD"
        case formUp = "FORM-UP"
        case lostKid = "LOST KID"

        public var title: String { rawValue }

        public static func parse(_ raw: String?) -> MarkKind? {
            let key = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return MarkKind(rawValue: key)
        }
    }

    public enum Condition: String, Sendable {
        case green
        case yellow
        case red
    }

    public struct Ring: Equatable, Sendable {
        public var lat: Double
        public var lon: Double
        public var meters: Double
        public var overdue: Bool

        public init(lat: Double, lon: Double, meters: Double, overdue: Bool = false) {
            self.lat = lat
            self.lon = lon
            self.meters = meters
            self.overdue = overdue
        }
    }

    public struct Scene: Equatable, Sendable, Codable {
        public var name: String
        public var lat: Double
        public var lon: Double
        public var layers: [String]
        public var palette: String

        public init(name: String, lat: Double, lon: Double, layers: [String], palette: String) {
            self.name = name
            self.lat = lat
            self.lon = lon
            self.layers = layers
            self.palette = palette
        }
    }

    public static let sceneNames = ["CAMP", "RIDGE", "TRUCK"]

    public static func load(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: persistKey)
    }

    public static func save(_ on: Bool, defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: persistKey)
    }

    public static func loadPalette(defaults: UserDefaults = .standard) -> Palette {
        Palette(rawValue: defaults.string(forKey: paletteKey) ?? "") ?? .streets
    }

    public static func savePalette(_ palette: Palette, defaults: UserDefaults = .standard) {
        defaults.set(palette.rawValue, forKey: paletteKey)
    }

    public static func loadLayers(defaults: UserDefaults = .standard) -> [Layer] {
        let raw = defaults.stringArray(forKey: layerKey) ?? Layer.allCases.map(\.rawValue)
        let parsed = raw.compactMap(Layer.init(rawValue:))
        return parsed.isEmpty ? Layer.allCases : parsed
    }

    public static func saveLayers(_ layers: [Layer], defaults: UserDefaults = .standard) {
        defaults.set(layers.map(\.rawValue), forKey: layerKey)
    }

    public static func layerOn(_ layer: Layer, in layers: [Layer]) -> Bool {
        layers.contains(layer)
    }

    public static func shows(_ layer: Layer, aerial: Bool, shade: Bool, water: Bool) -> Bool {
        switch layer {
        case .aerial:
            return aerial
        case .shade:
            return shade
        case .water:
            return water
        case .party, .marks, .tails:
            return true
        }
    }

    public static func toggling(_ layer: Layer, in layers: [Layer]) -> [Layer] {
        if layers.contains(layer) {
            return layers.filter { $0 != layer }
        }
        return Layer.allCases.filter { $0 == layer || layers.contains($0) }
    }

    public static func framePoints(
        you: (lat: Double, lon: Double)?,
        party: [(lat: Double, lon: Double)],
        marks: [(lat: Double, lon: Double)],
        water: [(lat: Double, lon: Double)] = []
    ) -> [(lat: Double, lon: Double)] {
        var points: [(lat: Double, lon: Double)] = []
        if let you, you.lat.isFinite, you.lon.isFinite {
            points.append(you)
        }
        points.append(contentsOf: party.filter { $0.lat.isFinite && $0.lon.isFinite })
        points.append(contentsOf: marks.filter { $0.lat.isFinite && $0.lon.isFinite })
        points.append(contentsOf: water.filter { $0.lat.isFinite && $0.lon.isFinite })
        return points
    }

    public static func bounds(
        points: [(lat: Double, lon: Double)],
        soloMeters: Double = soloMeters
    ) -> (south: Double, west: Double, north: Double, east: Double)? {
        guard !points.isEmpty else { return nil }
        var south = points[0].lat
        var north = points[0].lat
        var west = points[0].lon
        var east = points[0].lon
        for point in points {
            south = min(south, point.lat)
            north = max(north, point.lat)
            west = min(west, point.lon)
            east = max(east, point.lon)
        }
        let span = GraphRouter.haversine(south, west, north, east)
        if points.count == 1 || span < soloMeters {
            let midLat = (south + north) / 2
            let latPad = soloMeters / 111_320
            let cosLat = max(cos(midLat * .pi / 180), 0.2)
            let lonPad = soloMeters / (111_320 * cosLat)
            return (midLat - latPad, (west + east) / 2 - lonPad, midLat + latPad, (west + east) / 2 + lonPad)
        }
        return (south, west, north, east)
    }

    public static func clampToPack(
        desk: (south: Double, west: Double, north: Double, east: Double),
        pack: (south: Double, west: Double, north: Double, east: Double)
    ) -> (south: Double, west: Double, north: Double, east: Double) {
        let box = PackCamera.bounds(
            south: pack.south,
            west: pack.west,
            north: pack.north,
            east: pack.east
        )
        let south = max(desk.south, box.south)
        let west = max(desk.west, box.west)
        let north = min(desk.north, box.north)
        let east = min(desk.east, box.east)
        if south < north, west < east {
            return (south, west, north, east)
        }
        return box
    }

    public static func age(seconds: Double) -> Age {
        if seconds < lastAfterSeconds { return .live }
        if seconds < lostAfterSeconds { return .last }
        return .lost
    }

    public static func ageTitle(_ age: Age) -> String {
        switch age {
        case .live:
            return ""
        case .last:
            return "LAST"
        case .lost:
            return "LOST"
        }
    }

    public static func ageLabel(seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds.rounded()))s" }
        return "\(Int((seconds / 60).rounded()))m"
    }

    public static func netChrome(peers: Int) -> String {
        "NET · \(max(peers, 0))"
    }

    public static func aerialChrome(hasPackAerial: Bool) -> String? {
        hasPackAerial ? nil : offAerial
    }

    public static func hasPackAerial(packRoot: URL) -> Bool {
        let names = ["aerial.pmtiles", "naip.png", "naip.jpg", "aerial.png"]
        if names.contains(where: { FileManager.default.fileExists(atPath: packRoot.appendingPathComponent($0).path) }) {
            return true
        }
        return styleHasSource(packRoot: packRoot, ids: ["aerial", "naip"])
    }

    public static func hasPackShade(packRoot: URL) -> Bool {
        if FileManager.default.fileExists(atPath: packRoot.appendingPathComponent("hillshade.png").path) {
            return true
        }
        return styleHasSource(packRoot: packRoot, ids: ["hillshade"])
    }

    public static func hasPackWater(packRoot: URL) -> Bool {
        let names = ["layers/water.bin", "layers/water.geojson", "water.geojson"]
        return names.contains { FileManager.default.fileExists(atPath: packRoot.appendingPathComponent($0).path) }
    }

    public static func powerChrome(_ mode: String) -> String {
        switch mode {
        case "quiet":
            return "QUIET"
        case "search":
            return "SEARCH"
        default:
            return "NORMAL"
        }
    }

    public static func parseVoice(_ raw: String) -> Voice? {
        let key = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if key == "eye on" { return .eyeOn }
        if key == "eye off" { return .eyeOff }
        if key == "mark water" { return .markWater }
        if key.hasPrefix("frame ") {
            let name = String(key.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return .frame(name: name) }
        }
        return nil
    }

    public static func hudLine(tag: String, text: String) -> String {
        "\(tag) \(text)"
    }

    public static func compassChrome(headingDeg: Double?, accuracy: Double?) -> String {
        if let accuracy, accuracy < 0 { return calBad }
        guard let headingDeg, headingDeg >= 0, headingDeg.isFinite else { return calBad }
        return String(format: "%.0f°", headingDeg)
    }

    public static func fixChrome(ageSeconds: Double?, hasFix: Bool) -> String {
        if hasFix { return "" }
        guard let ageSeconds, ageSeconds.isFinite, ageSeconds >= 0 else { return noFix }
        if ageSeconds <= deadReckonSeconds { return "—" }
        return noFix
    }

    public static func condition(status: String) -> Condition {
        switch status.lowercased() {
        case "okay", "wait", "yellow":
            return .yellow
        case "bad", "water", "emergency", "emergency!", "down", "red":
            return .red
        default:
            return .green
        }
    }

    public static func kidMark(name: String, kind: String = "") -> Bool {
        let blob = (name + " " + kind).uppercased()
        return blob.contains("CHILD") || blob.contains("INFANT") || blob.contains("KID") || blob.contains("LOST KID")
    }

    public static func leadScale(isLead: Bool) -> Double {
        isLead ? 1.18 : 1.0
    }

    public static func stackOffset(
        index: Int,
        shared: Int
    ) -> (lat: Double, lon: Double) {
        guard shared > 1 else { return (0, 0) }
        let step = 0.00008
        return (0, Double(index) * step)
    }

    public static func stacked(
        _ points: [(id: String, lat: Double, lon: Double)]
    ) -> [String: (lat: Double, lon: Double)] {
        var groups: [String: [(id: String, lat: Double, lon: Double)]] = [:]
        for point in points {
            let key = String(format: "%.5f,%.5f", point.lat, point.lon)
            groups[key, default: []].append(point)
        }
        var out: [String: (lat: Double, lon: Double)] = [:]
        for bunch in groups.values {
            for (index, point) in bunch.enumerated() {
                let pad = stackOffset(index: index, shared: bunch.count)
                out[point.id] = (point.lat + pad.lat, point.lon + pad.lon)
            }
        }
        return out
    }

    public static func pruneTrail(
        points: [(lat: Double, lon: Double, at: Double)],
        now: Double,
        window: Double = trailSeconds
    ) -> [(lat: Double, lon: Double, at: Double)] {
        points.filter { now - $0.at <= window }
    }

    public static func trailSegments(
        points: [(lat: Double, lon: Double, at: Double)],
        gapSeconds: Double = lastAfterSeconds
    ) -> [[(lat: Double, lon: Double)]] {
        let ordered = points.sorted { $0.at < $1.at }
        var segments: [[(lat: Double, lon: Double)]] = []
        var current: [(lat: Double, lon: Double)] = []
        var lastAt: Double?
        for point in ordered {
            if let lastAt, point.at - lastAt > gapSeconds {
                if current.count >= 2 { segments.append(current) }
                current = []
            }
            current.append((point.lat, point.lon))
            lastAt = point.at
        }
        if current.count >= 2 { segments.append(current) }
        return segments
    }

    public static func rangeRingMeters(bleMeters: Double?) -> Double? {
        guard let bleMeters, bleMeters.isFinite, bleMeters > 0, bleMeters <= bleRingMaxMeters else {
            return nil
        }
        return bleMeters
    }

    public static func ringPoints(
        lat: Double,
        lon: Double,
        meters: Double,
        steps: Int = 48
    ) -> [(lat: Double, lon: Double)] {
        guard lat.isFinite, lon.isFinite, meters > 0, steps >= 8 else { return [] }
        let latPad = meters / 111_320
        let cosLat = max(cos(lat * .pi / 180), 0.2)
        let lonPad = meters / (111_320 * cosLat)
        return (0...steps).map { i in
            let rad = Double(i) / Double(steps) * 2 * .pi
            return (lat + sin(rad) * latPad, lon + cos(rad) * lonPad)
        }
    }

    public static func loadScenes(defaults: UserDefaults = .standard) -> [Scene] {
        guard let data = defaults.data(forKey: sceneKey),
              let loaded = try? JSONDecoder().decode([Scene].self, from: data)
        else { return [] }
        return loaded
    }

    public static func saveScenes(_ scenes: [Scene], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(scenes) {
            defaults.set(data, forKey: sceneKey)
        }
    }

    public static func upsertScene(
        _ scene: Scene,
        into scenes: [Scene]
    ) -> [Scene] {
        var next = scenes.filter { $0.name != scene.name }
        next.append(scene)
        next.sort { lhs, rhs in
            let order = sceneNames
            let li = order.firstIndex(of: lhs.name) ?? order.count
            let ri = order.firstIndex(of: rhs.name) ?? order.count
            return li < ri
        }
        return next
    }

    private static func styleHasSource(packRoot: URL, ids: [String]) -> Bool {
        let url = packRoot.appendingPathComponent("style.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sources = obj["sources"] as? [String: Any]
        else { return false }
        return ids.contains { sources[$0] != nil }
    }
}
