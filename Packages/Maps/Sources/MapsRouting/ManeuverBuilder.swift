import Foundation

enum ManeuverBuilder {
    static func make(
        nodeIds: [UInt32],
        edgeIndexes: [Int],
        reversed: [Bool],
        pack: RoutingPack
    ) -> [Maneuver] {
        guard let lastNode = nodeIds.last else { return [] }
        let arriveAt = pack.nodes[Int(lastNode)].coordinate
        if edgeIndexes.isEmpty {
            return [Maneuver(kind: .arrive, streetName: nil, distanceMeters: 0, coordinate: arriveAt)]
        }

        var maneuvers: [Maneuver] = []
        let firstEdge = pack.edges[edgeIndexes[0]]
        let firstName = pack.name(for: firstEdge.nameId)
        let startCoord = pack.nodes[Int(nodeIds[0])].coordinate
        var sinceMeters = 0.0
        maneuvers.append(
            Maneuver(kind: .depart, streetName: firstName, distanceMeters: 0, coordinate: startCoord)
        )

        for i in 0..<edgeIndexes.count {
            let edge = pack.edges[edgeIndexes[i]]
            sinceMeters += Double(edge.lengthCm) / 100
            let outgoingName = i + 1 < edgeIndexes.count ? pack.name(for: pack.edges[edgeIndexes[i + 1]].nameId) : nil
            if i + 1 >= edgeIndexes.count {
                continue
            }
            let headingIn = heading(edgeIndex: edgeIndexes[i], reverse: reversed[i], pack: pack)
            let headingOut = heading(edgeIndex: edgeIndexes[i + 1], reverse: reversed[i + 1], pack: pack)
            let kind = classify(Geo.turnDelta(incoming: headingIn, outgoing: headingOut))
            if kind == .straight, pack.name(for: edge.nameId) == outgoingName {
                continue
            }
            let at = pack.nodes[Int(nodeIds[i + 1])].coordinate
            maneuvers.append(
                Maneuver(
                    kind: kind,
                    streetName: outgoingName,
                    distanceMeters: sinceMeters,
                    coordinate: at
                )
            )
            sinceMeters = 0
        }

        maneuvers.append(
            Maneuver(kind: .arrive, streetName: nil, distanceMeters: sinceMeters, coordinate: arriveAt)
        )
        return maneuvers
    }

    static func classify(_ delta: Double) -> ManeuverKind {
        let absDelta = abs(delta)
        if absDelta < 20 { return .straight }
        if absDelta > 135 { return .uTurn }
        if delta > 0 {
            return absDelta < 45 ? .slightRight : .right
        }
        return absDelta < 45 ? .slightLeft : .left
    }

    private static func heading(edgeIndex: Int, reverse: Bool, pack: RoutingPack) -> Double {
        let points = pack.geometry(edgeIndex: edgeIndex, reverse: reverse)
        if points.count >= 2 {
            return Geo.bearing(points[points.count - 2], points[points.count - 1])
        }
        let edge = pack.edges[edgeIndex]
        let a = pack.nodes[Int(reverse ? edge.to : edge.from)].coordinate
        let b = pack.nodes[Int(reverse ? edge.from : edge.to)].coordinate
        return Geo.bearing(a, b)
    }
}
