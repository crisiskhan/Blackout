import Foundation
@testable import MapsRouting

enum ToyRouting {
    static let n0 = RoutingCoordinate(latitude: 31.7619, longitude: -106.4850)
    static let n1 = RoutingCoordinate(latitude: 31.7620, longitude: -106.4840)
    static let n2 = RoutingCoordinate(latitude: 31.7629, longitude: -106.4830)

    static func writePack(to root: URL, onewayFirstEdge: Bool = false, badGraphMagic: Bool = false) throws {
        let fm = FileManager.default
        let routing = root.appendingPathComponent("routing", isDirectory: true)
        try fm.createDirectory(at: routing, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "name": "Toy",
            "routing": "routing/routing.json"
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: root.appendingPathComponent("manifest.json"))

        let routingJSON: [String: Any] = [
            "format": RoutingLayout.format,
            "profiles": ["walk", "drive"],
            "bbox": [
                "west": RoutingLayout.ElPaso.west,
                "south": RoutingLayout.ElPaso.south,
                "east": RoutingLayout.ElPaso.east,
                "north": RoutingLayout.ElPaso.north
            ],
            "center": ["lat": RoutingLayout.ElPaso.centerLat, "lon": RoutingLayout.ElPaso.centerLon],
            "packId": RoutingLayout.ElPaso.packId,
            "nodeCount": 3,
            "edgeCount": 2,
            "nameCount": 3,
            "bidirectionalIfNotOneway": true,
            "attribution": "© OpenStreetMap contributors"
        ]
        try JSONSerialization.data(withJSONObject: routingJSON).write(
            to: routing.appendingPathComponent("routing.json")
        )

        var flags0: UInt16 = RoutingLayout.walkFlag | RoutingLayout.driveFlag
        if onewayFirstEdge { flags0 |= RoutingLayout.onewayFlag }
        let nodes = [
            RoutingNode(lonE7: n0.lonE7, latE7: n0.latE7),
            RoutingNode(lonE7: n1.lonE7, latE7: n1.latE7),
            RoutingNode(lonE7: n2.lonE7, latE7: n2.latE7)
        ]
        let edges = [
            RoutingEdge(from: 0, to: 1, nameId: 1, flags: flags0, lengthCm: 8_000, walkMs: 1_000, driveMs: 200),
            RoutingEdge(
                from: 1,
                to: 2,
                nameId: 2,
                flags: RoutingLayout.walkFlag,
                lengthCm: 12_000,
                walkMs: 1_500,
                driveMs: 0
            )
        ]
        var graph = RoutingBinary.writeGraph(nodes: nodes, edges: edges)
        if badGraphMagic {
            graph.replaceSubrange(0..<8, with: Array("XXXX0001".utf8))
        }
        try graph.write(to: routing.appendingPathComponent("graph.bin"))
        try RoutingBinary.writeNames(["", "Mesa Street", "Arroyo Path"])
            .write(to: routing.appendingPathComponent("names.bin"))
        try RoutingBinary.writeGeometry([
            [n0, n1],
            [n1, n2]
        ]).write(to: routing.appendingPathComponent("geometry.bin"))
    }
}
