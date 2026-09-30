import Foundation
import MapLibreMap
import MeshDTN
import Router
import Tokens

/// One camera language on the packed desk and on EXPEDITION TV.
enum CamDesk {
    /// How often TV pulls the same one-shot SNAP while a pipe exists.
    static let watchSeconds: TimeInterval = 12
    /// N/A stays closed until this hold. A tap is HOLD 10, not a dead chip.
    static let naHoldSeconds: TimeInterval = 10

    enum Kind: String, CaseIterable {
        case traffic = "TRAFFIC"
        case bridge = "BRIDGE"
        case airport = "AIRPORT"
        case venue = "VENUE"
        case na = "N/A"
        case hop = "HOP"
    }

    struct Feed: Identifiable, Equatable {
        var id: String
        var name: String
        var lat: Double
        var lon: Double
        var provider: String
        var meters: Double
        var range: String
        var kind: Kind
    }

    struct Section: Identifiable, Equatable {
        var kind: Kind
        var feeds: [Feed]
        var id: String { kind.rawValue }
    }

    /// Packed cameras plus hop cameras the mesh can reach. Pack wins a shared id.
    static func reachable(pack: [PackCam], hops: [MeshCamRecord]) -> [PackCam] {
        var byID: [String: PackCam] = [:]
        for cam in pack {
            let id = cam.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, cam.lat.isFinite, cam.lon.isFinite else { continue }
            byID[id] = cam
        }
        for hop in MeshCamPaint.visible(packIDs: Set(byID.keys), hops: hops) {
            let id = hop.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            let named = hop.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let provider = hop.provider.trimmingCharacters(in: .whitespacesAndNewlines)
            byID[id] = PackCam(
                id: id,
                url: hop.url,
                lat: hop.lat,
                lon: hop.lon,
                name: named.isEmpty ? id : named,
                ink: "blue",
                provider: provider.isEmpty ? "HOP" : provider
            )
        }
        return Array(byID.values)
    }

    static func marks(pack: [PackCam], hops: [MeshCamRecord]) -> [CctvMark] {
        reachable(pack: pack, hops: hops).map { CctvMark(id: $0.id, lat: $0.lat, lon: $0.lon) }
    }

    static func naUnlocks(elapsed: TimeInterval) -> Bool {
        elapsed >= naHoldSeconds
    }

    /// HOP first. N/A is provider N/A only. BOTA / PASO DEL NORTE are BRIDGE.
    /// AIRPORT is AIRPORT. Zaragoza streets and Paseo Del Norte stay TRAFFIC.
    static func kind(_ cam: PackCam) -> Kind {
        let provider = cam.provider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if provider == "HOP" { return .hop }
        if provider == "N/A" || provider == "NA" { return .na }
        let named = cam.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = (named.isEmpty ? cam.id : named).uppercased()
        if token.contains("BOTA") || token.contains("PASO DEL NORTE") {
            return .bridge
        }
        if token.contains("AIRPORT") {
            return .airport
        }
        return .traffic
    }

    static func feeds(
        pack: [PackCam],
        hops: [MeshCamRecord],
        lat: Double,
        lon: Double
    ) -> [Feed] {
        reachable(pack: pack, hops: hops)
            .map { cam in
                let meters = GraphRouter.haversine(lat, lon, cam.lat, cam.lon)
                let named = cam.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return Feed(
                    id: cam.id,
                    name: named.isEmpty ? cam.id : named,
                    lat: cam.lat,
                    lon: cam.lon,
                    provider: cam.provider,
                    meters: meters,
                    range: BlackoutTokens.Distance.hud(meters),
                    kind: kind(cam)
                )
            }
            .sorted { $0.meters < $1.meters }
    }

    static func sections(
        pack: [PackCam],
        hops: [MeshCamRecord],
        lat: Double,
        lon: Double
    ) -> [Section] {
        let all = feeds(pack: pack, hops: hops, lat: lat, lon: lon)
        return Kind.allCases.compactMap { kind in
            if kind == .na { return nil }
            let rows = all.filter { $0.kind == kind }
            return rows.isEmpty ? nil : Section(kind: kind, feeds: rows)
        }
    }

    static func naFeeds(
        pack: [PackCam],
        hops: [MeshCamRecord],
        lat: Double,
        lon: Double
    ) -> [Feed] {
        feeds(pack: pack, hops: hops, lat: lat, lon: lon).filter { $0.kind == .na }
    }
}
