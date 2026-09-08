import Foundation

enum ManeuverBuilder {
    static func make(
        nodeIds: [UInt32],
        edgeIndexes: [Int],
        reversed: [Bool],
        pack: RoutingPack
    ) -> [Maneuver] {
        guard let lastNode = nodeIds.last, let arriveAt = pack.node(at: lastNode)?.coordinate else { return [] }
        if edgeIndexes.isEmpty {
            return [Maneuver(kind: .arrive, streetName: nil, distanceMeters: 0, coordinate: arriveAt)]
        }

        var maneuvers: [Maneuver] = []
        guard let firstEdge = pack.edge(at: edgeIndexes[0]),
              let startCoord = pack.node(at: nodeIds[0])?.coordinate else { return [] }
        let firstName = pack.name(for: firstEdge.nameId)
        var sinceMeters = 0.0
        maneuvers.append(
            Maneuver(kind: .depart, streetName: firstName, distanceMeters: 0, coordinate: startCoord)
        )

        for i in 0..<edgeIndexes.count {
            guard let edge = pack.edge(at: edgeIndexes[i]) else { continue }
            sinceMeters += Double(edge.lengthCm) / 100
            let outgoingName = i + 1 < edgeIndexes.count ? pack.edge(at: edgeIndexes[i + 1]).flatMap { pack.name(for: $0.nameId) } : nil
            if i + 1 >= edgeIndexes.count {
                continue
            }
            guard i < reversed.count, i + 1 < reversed.count else { continue }
            let headingIn = heading(edgeIndex: edgeIndexes[i], reverse: reversed[i], pack: pack)
            let headingOut = heading(edgeIndex: edgeIndexes[i + 1], reverse: reversed[i + 1], pack: pack)
            let kind = classify(Geo.turnDelta(incoming: headingIn, outgoing: headingOut))
            if kind == .straight, pack.name(for: edge.nameId) == outgoingName {
                continue
            }
            guard i + 1 < nodeIds.count, let at = pack.node(at: nodeIds[i + 1])?.coordinate else { continue }
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
        guard let edge = pack.edge(at: edgeIndex),
              let a = pack.node(at: reverse ? edge.to : edge.from)?.coordinate,
              let b = pack.node(at: reverse ? edge.from : edge.to)?.coordinate else {
            return 0
        }
        return Geo.bearing(a, b)
    }
}
