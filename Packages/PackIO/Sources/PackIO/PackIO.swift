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
    public private(set) var active: PackManifest?
    public private(set) var catalog: PackCatalog
    private let box: BlackBox
    private let root: URL

    public init(root: URL, box: BlackBox) throws {
        self.root = root
        self.box = box
        let data = try Data(contentsOf: root.appendingPathComponent("catalog.json"))
        self.catalog = try JSONDecoder().decode(PackCatalog.self, from: data)
        self.active = catalog.packs.first
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

    public func realSize(of id: String) -> Int? {
        catalog.packs.first(where: { $0.id == id })?.bytes
    }
}

public enum PackError: Error, Equatable { case missing(String); case regionLeak }
