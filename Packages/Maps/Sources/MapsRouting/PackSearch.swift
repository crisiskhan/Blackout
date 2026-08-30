import Foundation

public enum PackSearch {
    public static func query(
        _ raw: String,
        pack: RoutingPack?,
        pois: [RoutingPOI],
        addresses: [RoutingAddress] = [],
        limit: Int = 12
    ) -> (hits: [PackSearchHit], empty: NavigateEmpty?) {
        let needle = normalize(raw)
        if needle.isEmpty { return ([], nil) }

        var hits: [PackSearchHit] = []
        var seen = Set<String>()

        for poi in pois {
            if normalize(poi.name).contains(needle) {
                let id = "poi:\(poi.id)"
                if seen.insert(id).inserted {
                    hits.append(
                        PackSearchHit(id: id, title: poi.name, kind: poi.kind, coordinate: poi.coordinate)
                    )
                }
            }
            if hits.count >= limit { return (hits, nil) }
        }

        for address in addresses {
            if matchesAddress(needle, house: address.house, street: address.street) {
                let id = "addr:\(address.id)"
                if seen.insert(id).inserted {
                    hits.append(
                        PackSearchHit(
                            id: id,
                            title: address.title,
                            kind: "address",
                            coordinate: address.coordinate
                        )
                    )
                }
            }
            if hits.count >= limit { return (hits, nil) }
        }

        if let pack {
            for (nameId, name) in pack.names.enumerated() where nameId > 0 {
                if normalize(name).contains(needle) {
                    let id = "name:\(nameId)"
                    if seen.insert(id).inserted, let coord = coordinate(forNameId: UInt32(nameId), pack: pack) {
                        hits.append(
                            PackSearchHit(id: id, title: name, kind: "street", coordinate: coord)
                        )
                    }
                }
                if hits.count >= limit { break }
            }
        }

        if hits.isEmpty { return ([], .searchMiss) }
        return (hits, nil)
    }

    private static func matchesAddress(_ needle: String, house: String, street: String) -> Bool {
        let houseKey = normalize(house)
        let streetKey = normalize(street)
        let title = normalize("\(house) \(street)")
        if title.contains(needle) { return true }
        let parts = needle.split(separator: " ").map(String.init)
        if parts.count >= 2, parts[0] == houseKey {
            return streetKey.contains(parts.dropFirst().joined(separator: " "))
        }
        return streetKey.contains(needle) && needle.count >= 3
    }

    private static func coordinate(forNameId nameId: UInt32, pack: RoutingPack) -> RoutingCoordinate? {
        for (index, edge) in pack.edges.enumerated() where edge.nameId == nameId {
            let geom = pack.geometries[index]
            if let mid = geom[safe: geom.count / 2] { return mid }
            return pack.nodes[Int(edge.from)].coordinate
        }
        return nil
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
