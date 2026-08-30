import CryptoKit
import Foundation

public final class RoutingPack: @unchecked Sendable {
    public let manifest: RoutingManifest
    public let nodes: [RoutingNode]
    public let edges: [RoutingEdge]
    public let names: [String]
    public let geometries: [[RoutingCoordinate]]
    public let outgoing: [[RoutingArc]]
    public let grid: EdgeGrid

    public init(
        manifest: RoutingManifest,
        nodes: [RoutingNode],
        edges: [RoutingEdge],
        names: [String],
        geometries: [[RoutingCoordinate]]
    ) {
        self.manifest = manifest
        self.nodes = nodes
        self.edges = edges
        self.names = names
        self.geometries = geometries
        self.outgoing = RoutingPack.buildOutgoing(
            nodeCount: nodes.count,
            edges: edges,
            bidirectionalIfNotOneway: manifest.bidirectionalIfNotOneway
        )
        self.grid = EdgeGrid(bbox: manifest.bbox, geometries: geometries)
    }

    public func name(for nameId: UInt32) -> String? {
        guard nameId > 0, nameId < names.count else { return nil }
        let value = names[Int(nameId)]
        return value.isEmpty ? nil : value
    }

    public func geometry(edgeIndex: Int, reverse: Bool) -> [RoutingCoordinate] {
        guard edgeIndex >= 0, edgeIndex < geometries.count else { return [] }
        let points = geometries[edgeIndex]
        return reverse ? points.reversed() : points
    }

    public func nearestNode(to coordinate: RoutingCoordinate, maxMeters: Double) -> UInt32? {
        var best: UInt32?
        var bestMeters = maxMeters
        for (index, node) in nodes.enumerated() {
            let meters = Geo.haversine(coordinate, node.coordinate)
            if meters <= bestMeters {
                bestMeters = meters
                best = UInt32(index)
            }
        }
        return best
    }

    private static func buildOutgoing(
        nodeCount: Int,
        edges: [RoutingEdge],
        bidirectionalIfNotOneway: Bool
    ) -> [[RoutingArc]] {
        var outgoing = Array(repeating: [RoutingArc](), count: nodeCount)
        for (index, edge) in edges.enumerated() {
            let from = Int(edge.from)
            let to = Int(edge.to)
            guard from >= 0, from < nodeCount, to >= 0, to < nodeCount else { continue }
            outgoing[from].append(RoutingArc(edgeIndex: index, toward: edge.to, reverse: false))
            if !edge.isOneway && bidirectionalIfNotOneway {
                outgoing[to].append(RoutingArc(edgeIndex: index, toward: edge.from, reverse: true))
            }
        }
        return outgoing
    }
}

public struct EdgeGrid: Sendable {
    private let bbox: RoutingBBox
    private let cols: Int
    private let rows: Int
    private let cells: [[Int]]

    public init(bbox: RoutingBBox, geometries: [[RoutingCoordinate]], cols: Int = 48, rows: Int = 48) {
        self.bbox = bbox
        self.cols = max(1, cols)
        self.rows = max(1, rows)
        var cells = Array(repeating: [Int](), count: self.cols * self.rows)
        let spanLon = max(bbox.east - bbox.west, 0.0001)
        let spanLat = max(bbox.north - bbox.south, 0.0001)
        for (edgeIndex, points) in geometries.enumerated() {
            var seen = Set<Int>()
            for point in points {
                let col = min(self.cols - 1, max(0, Int(((point.longitude - bbox.west) / spanLon) * Double(self.cols))))
                let row = min(self.rows - 1, max(0, Int(((point.latitude - bbox.south) / spanLat) * Double(self.rows))))
                let cell = row * self.cols + col
                if seen.insert(cell).inserted {
                    cells[cell].append(edgeIndex)
                }
            }
        }
        self.cells = cells
    }

    public func edges(in west: Double, south: Double, east: Double, north: Double) -> [Int] {
        let spanLon = max(bbox.east - bbox.west, 0.0001)
        let spanLat = max(bbox.north - bbox.south, 0.0001)
        let c0 = min(cols - 1, max(0, Int(((west - bbox.west) / spanLon) * Double(cols))))
        let c1 = min(cols - 1, max(0, Int(((east - bbox.west) / spanLon) * Double(cols))))
        let r0 = min(rows - 1, max(0, Int(((south - bbox.south) / spanLat) * Double(rows))))
        let r1 = min(rows - 1, max(0, Int(((north - bbox.south) / spanLat) * Double(rows))))
        var seen = Set<Int>()
        var out: [Int] = []
        for row in r0...r1 {
            for col in c0...c1 {
                for edge in cells[row * cols + col] where seen.insert(edge).inserted {
                    out.append(edge)
                }
            }
        }
        return out
    }
}

public enum RoutingPackLoader {
    /// Smallest mounted pack whose `routing/` bbox covers the coordinate.
    /// Painted DefaultPack / Recenter pin is ignored — Field Packs on disk only.
    public static func coveringRoot(
        among roots: [URL],
        latitude: Double,
        longitude: Double
    ) -> URL? {
        let coordinate = RoutingCoordinate(latitude: latitude, longitude: longitude)
        var ranked: [(url: URL, area: Double)] = []
        for root in roots {
            guard let manifest = peekManifest(packRoot: root) else { continue }
            guard manifest.format == RoutingLayout.format else { continue }
            guard manifest.bbox.contains(coordinate) else { continue }
            if manifest.checksums.isEmpty {
                guard binariesPresent(packRoot: root) else { continue }
            } else if !binariesReadable(packRoot: root, manifest: manifest) {
                continue
            }
            ranked.append((root.standardizedFileURL, manifest.bbox.area))
        }
        return ranked.min(by: { $0.area < $1.area })?.url
    }

    public static func loadCovering(
        among roots: [URL],
        latitude: Double,
        longitude: Double
    ) -> RoutingPack? {
        guard let root = coveringRoot(among: roots, latitude: latitude, longitude: longitude) else {
            return nil
        }
        return load(packRoot: root)
    }

    public static func peekManifest(packRoot: URL) -> RoutingManifest? {
        guard let urls = routingURLs(packRoot: packRoot) else { return nil }
        guard let manifest = readManifest(urls.json) else { return nil }
        if manifest.format != RoutingLayout.format { return nil }
        return manifest
    }

    public static func load(packRoot: URL) -> RoutingPack? {
        guard let urls = routingURLs(packRoot: packRoot) else { return nil }
        guard let manifest = readManifest(urls.json) else { return nil }
        if manifest.format != RoutingLayout.format { return nil }

        let graphURL = urls.dir.appendingPathComponent("graph.bin")
        let namesURL = urls.dir.appendingPathComponent("names.bin")
        let geometryURL = urls.dir.appendingPathComponent("geometry.bin")
        guard let graphData = try? Data(contentsOf: graphURL, options: [.mappedIfSafe]),
              let namesData = try? Data(contentsOf: namesURL, options: [.mappedIfSafe]),
              let geometryData = try? Data(contentsOf: geometryURL, options: [.mappedIfSafe]) else {
            return nil
        }
        if !checksumsMatch(manifest.checksums, files: [
            "graph.bin": graphData,
            "names.bin": namesData,
            "geometry.bin": geometryData
        ]) {
            return nil
        }
        do {
            let parsed = try RoutingBinary.read(graph: graphData, names: namesData, geometry: geometryData)
            if parsed.nodes.count != manifest.nodeCount || parsed.edges.count != manifest.edgeCount {
                return nil
            }
            return RoutingPack(
                manifest: manifest,
                nodes: parsed.nodes,
                edges: parsed.edges,
                names: parsed.names,
                geometries: parsed.geometries
            )
        } catch {
            return nil
        }
    }

    public static func readManifest(_ url: URL) -> RoutingManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parseManifest(data)
    }

    private static func routingURLs(packRoot: URL) -> (json: URL, dir: URL)? {
        let fm = FileManager.default
        let manifestURL = packRoot.appendingPathComponent("manifest.json")
        let relative: String
        if let data = try? Data(contentsOf: manifestURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let key = json["routing"] as? String, !key.isEmpty {
            relative = key
        } else {
            relative = RoutingLayout.defaultManifestKey
        }
        let routingJSON = packRoot.appendingPathComponent(relative)
        let routingDir = routingJSON.deletingLastPathComponent()
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: routingDir.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        guard fm.fileExists(atPath: routingJSON.path) else { return nil }
        return (routingJSON, routingDir)
    }

    private static func binariesPresent(packRoot: URL) -> Bool {
        guard let urls = routingURLs(packRoot: packRoot) else { return false }
        let fm = FileManager.default
        return fm.fileExists(atPath: urls.dir.appendingPathComponent("graph.bin").path)
            && fm.fileExists(atPath: urls.dir.appendingPathComponent("names.bin").path)
            && fm.fileExists(atPath: urls.dir.appendingPathComponent("geometry.bin").path)
    }

    private static func binariesReadable(packRoot: URL, manifest: RoutingManifest) -> Bool {
        guard let urls = routingURLs(packRoot: packRoot) else { return false }
        let files = [
            "graph.bin": urls.dir.appendingPathComponent("graph.bin"),
            "names.bin": urls.dir.appendingPathComponent("names.bin"),
            "geometry.bin": urls.dir.appendingPathComponent("geometry.bin")
        ]
        var blobs: [String: Data] = [:]
        for (name, url) in files {
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return false }
            blobs[name] = data
        }
        return checksumsMatch(manifest.checksums, files: blobs)
    }

    public static func parseManifest(_ data: Data) -> RoutingManifest? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let format = json["format"] as? String ?? ""
        let profilesRaw = json["profiles"] as? [String] ?? []
        let profiles = profilesRaw.compactMap(NavigateProfile.init(rawValue:))
        let bboxJSON = json["bbox"] as? [String: Any]
        let bbox = RoutingBBox(
            west: number(bboxJSON?["west"]) ?? 0,
            south: number(bboxJSON?["south"]) ?? 0,
            east: number(bboxJSON?["east"]) ?? 0,
            north: number(bboxJSON?["north"]) ?? 0
        )
        let checksums = (json["checksums"] as? [String: Any] ?? [:]).reduce(into: [String: String]()) { out, item in
            if let value = item.value as? String { out[item.key] = value.lowercased() }
        }
        return RoutingManifest(
            format: format,
            profiles: profiles,
            bbox: bbox,
            nodeCount: int(json["nodeCount"]) ?? 0,
            edgeCount: int(json["edgeCount"]) ?? 0,
            walkEdgeCount: int(json["walkEdgeCount"]),
            driveEdgeCount: int(json["driveEdgeCount"]),
            onewayEdgeCount: int(json["onewayEdgeCount"]),
            nameCount: int(json["nameCount"]),
            bidirectionalIfNotOneway: (json["bidirectionalIfNotOneway"] as? Bool) ?? true,
            attribution: json["attribution"] as? String,
            packId: json["packId"] as? String,
            checksums: checksums
        )
    }

    private static func checksumsMatch(_ expected: [String: String], files: [String: Data]) -> Bool {
        for (name, hex) in expected {
            guard let data = files[name] else { return false }
            if sha256Hex(data) != hex.lowercased() { return false }
        }
        return true
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? Double { return Int(n) }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }
}

public enum RoutingBinary {
    public struct Parsed: Sendable {
        public var nodes: [RoutingNode]
        public var edges: [RoutingEdge]
        public var names: [String]
        public var geometries: [[RoutingCoordinate]]
    }

    public static func read(graph: Data, names: Data, geometry: Data) throws -> Parsed {
        let nodesAndEdges = try readGraph(graph)
        let nameList = try readNames(names)
        let geoms = try readGeometry(geometry, edgeCount: nodesAndEdges.edges.count)
        return Parsed(nodes: nodesAndEdges.nodes, edges: nodesAndEdges.edges, names: nameList, geometries: geoms)
    }

    public static func readGraph(_ data: Data) throws -> (nodes: [RoutingNode], edges: [RoutingEdge]) {
        var reader = LEReader(data: data)
        guard try reader.magic8() == RoutingLayout.graphMagic else { throw RoutingReadError.magic }
        let nodeCount = Int(try reader.u32())
        let edgeCount = Int(try reader.u32())
        var nodes: [RoutingNode] = []
        nodes.reserveCapacity(nodeCount)
        for _ in 0..<nodeCount {
            let lon = try reader.i32()
            let lat = try reader.i32()
            nodes.append(RoutingNode(lonE7: lon, latE7: lat))
        }
        var edges: [RoutingEdge] = []
        edges.reserveCapacity(edgeCount)
        for _ in 0..<edgeCount {
            edges.append(
                RoutingEdge(
                    from: try reader.u32(),
                    to: try reader.u32(),
                    nameId: try reader.u32(),
                    flags: try reader.u16(),
                    lengthCm: try reader.u32(),
                    walkMs: try reader.u32(),
                    driveMs: try reader.u32()
                )
            )
        }
        if reader.remaining != 0 { throw RoutingReadError.count }
        return (nodes, edges)
    }

    public static func readNames(_ data: Data) throws -> [String] {
        var reader = LEReader(data: data)
        guard try reader.magic8() == RoutingLayout.namesMagic else { throw RoutingReadError.magic }
        let count = Int(try reader.u32())
        var names: [String] = []
        names.reserveCapacity(count)
        for _ in 0..<count {
            let len = Int(try reader.u16())
            let bytes = try reader.bytes(len)
            names.append(String(decoding: bytes, as: UTF8.self))
        }
        return names
    }

    public static func readGeometry(_ data: Data, edgeCount: Int) throws -> [[RoutingCoordinate]] {
        var reader = LEReader(data: data)
        guard try reader.magic8() == RoutingLayout.geometryMagic else { throw RoutingReadError.magic }
        let count = Int(try reader.u32())
        if count != edgeCount { throw RoutingReadError.count }
        var geoms: [[RoutingCoordinate]] = []
        geoms.reserveCapacity(count)
        for _ in 0..<count {
            let n = Int(try reader.u16())
            var points: [RoutingCoordinate] = []
            points.reserveCapacity(n)
            for _ in 0..<n {
                let lon = try reader.i32()
                let lat = try reader.i32()
                points.append(RoutingCoordinate(latE7: lat, lonE7: lon))
            }
            geoms.append(points)
        }
        return geoms
    }

    public static func writeGraph(nodes: [RoutingNode], edges: [RoutingEdge]) -> Data {
        var writer = LEWriter()
        writer.magic8(RoutingLayout.graphMagic)
        writer.u32(UInt32(nodes.count))
        writer.u32(UInt32(edges.count))
        for node in nodes {
            writer.i32(node.lonE7)
            writer.i32(node.latE7)
        }
        for edge in edges {
            writer.u32(edge.from)
            writer.u32(edge.to)
            writer.u32(edge.nameId)
            writer.u16(edge.flags)
            writer.u32(edge.lengthCm)
            writer.u32(edge.walkMs)
            writer.u32(edge.driveMs)
        }
        return writer.data
    }

    public static func writeNames(_ names: [String]) -> Data {
        var writer = LEWriter()
        writer.magic8(RoutingLayout.namesMagic)
        writer.u32(UInt32(names.count))
        for name in names {
            let bytes = Data(name.utf8)
            writer.u16(UInt16(bytes.count))
            writer.bytes(bytes)
        }
        return writer.data
    }

    public static func writeGeometry(_ geometries: [[RoutingCoordinate]]) -> Data {
        var writer = LEWriter()
        writer.magic8(RoutingLayout.geometryMagic)
        writer.u32(UInt32(geometries.count))
        for points in geometries {
            writer.u16(UInt16(points.count))
            for point in points {
                writer.i32(point.lonE7)
                writer.i32(point.latE7)
            }
        }
        return writer.data
    }
}
