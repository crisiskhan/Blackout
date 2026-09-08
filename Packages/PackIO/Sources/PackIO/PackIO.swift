import Foundation
import BlackBox

public struct PackManifest: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var state: String
    public var bytes: Int
    public var banners: [String]
    public var center: Coord
    public var bbox: BBox
    public struct Coord: Codable, Equatable, Sendable { public var lat: Double; public var lon: Double }
    public struct BBox: Codable, Equatable, Sendable {
        public var south: Double; public var west: Double; public var north: Double; public var east: Double
    }
}

public struct PackCatalog: Codable, Equatable, Sendable {
    public var packs: [PackManifest]
}

public final class PackStore: @unchecked Sendable {
    public static let defaultPackID = "tx-west"
    public static let osmAttribution = "© OpenStreetMap contributors"

    public private(set) var active: PackManifest?
    public private(set) var catalog: PackCatalog
    private let box: EventLog
    private let root: URL

    public init(root: URL, box: EventLog) throws {
        self.root = root
        self.box = box
        let data = try Data(contentsOf: root.appendingPathComponent("catalog.json"))
        let decoded = try JSONDecoder().decode(PackCatalog.self, from: data)
        self.catalog = PackCatalog(packs: Self.preferPrimary(decoded.packs))
        self.active = catalog.packs.first(where: { $0.id == Self.defaultPackID }) ?? catalog.packs.first
    }

    public static func preferPrimary(_ packs: [PackManifest]) -> [PackManifest] {
        let primary = packs.filter { $0.id == defaultPackID }
        let rest = packs.filter { $0.id != defaultPackID }
        return primary + rest
    }

    public func switchTo(_ id: String) throws {
        guard let pack = catalog.packs.first(where: { $0.id == id }) else {
            throw PackError.missing(id)
        }
        if pack.state == "FL" && pack.banners.contains("ice-rock") && pack.id.contains("adk") {
            throw PackError.regionLeak
        }
        active = pack
        box.log("pack", "switched \(id) bytes=\(pack.bytes)")
    }

    public func packURL(_ file: String) -> URL? {
        guard let active else { return nil }
        return root.appendingPathComponent(active.id).appendingPathComponent(file)
    }

    public func hasUsableGraph() -> Bool {
        guard let url = packURL("graph.json") else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let edges = obj["edges"] as? [Any] else { return false }
        return !edges.isEmpty
    }

    public func realSize(of id: String) -> Int? {
        catalog.packs.first(where: { $0.id == id })?.bytes
    }
}

public enum PackError: Error, Equatable { case missing(String); case regionLeak }
