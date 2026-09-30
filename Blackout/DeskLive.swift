import Router
import Tokens

/// Official city / zoo HTTPS HLS on the open TV sections.
/// BRIDGE and VENUE only. N/A stays adult. SNAP stills stay stills.
enum DeskLive {
    struct Stream: Identifiable, Equatable {
        var id: String
        var name: String
        var url: String
        var lat: Double
        var lon: Double
        var kind: CamDesk.Kind
    }

    /// City bridge page plus the zoo host's own public cams. 404 Stanton 1/2 stay off.
    static let streams: [Stream] = [
        Stream(
            id: "desk-stanton-3",
            name: "STANTON BRIDGE 3",
            url: "https://zoocams.elpasozoo.org/BridgeStanton3.m3u8",
            lat: 31.7598,
            lon: -106.4826,
            kind: .bridge
        ),
        Stream(
            id: "desk-pdn-1",
            name: "PASO DEL NORTE 1",
            url: "https://zoocams.elpasozoo.org/bridgepdn1.m3u8",
            lat: 31.7580,
            lon: -106.4870,
            kind: .bridge
        ),
        Stream(
            id: "desk-santa-fe-3",
            name: "SANTA FE 3",
            url: "https://zoocams.elpasozoo.org/bridgesantafe3.m3u8",
            lat: 31.7576,
            lon: -106.4874,
            kind: .bridge
        ),
        Stream(
            id: "desk-santa-fe-4",
            name: "SANTA FE 4",
            url: "https://zoocams.elpasozoo.org/bridgesantafe4.m3u8",
            lat: 31.7574,
            lon: -106.4876,
            kind: .bridge
        ),
        Stream(
            id: "desk-zaragoza-1",
            name: "ZARAGOZA 1",
            url: "https://zoocams.elpasozoo.org/BridgeZaragoza1.m3u8",
            lat: 31.6714,
            lon: -106.3378,
            kind: .bridge
        ),
        Stream(
            id: "desk-zaragoza-2",
            name: "ZARAGOZA 2",
            url: "https://zoocams.elpasozoo.org/BridgeZaragoza2.m3u8",
            lat: 31.6712,
            lon: -106.3374,
            kind: .bridge
        ),
        Stream(
            id: "desk-zaragoza-3",
            name: "ZARAGOZA 3",
            url: "https://zoocams.elpasozoo.org/BridgeZaragoza3.m3u8",
            lat: 31.6710,
            lon: -106.3370,
            kind: .bridge
        ),
        Stream(
            id: "desk-zoo-gf",
            name: "ZOO GF",
            url: "https://zoocams.elpasozoo.org/ZOOGF.m3u8",
            lat: 31.7688,
            lon: -106.4434,
            kind: .venue
        ),
        Stream(
            id: "desk-zoo-m",
            name: "ZOO M",
            url: "https://zoocams.elpasozoo.org/ZooM.m3u8",
            lat: 31.7684,
            lon: -106.4430,
            kind: .venue
        ),
    ]

    static func rows(kind: CamDesk.Kind, lat: Double, lon: Double) -> [NaLive.Row] {
        switch kind {
        case .bridge:
            break
        case .venue:
            break
        case .traffic, .airport, .na, .hop:
            return []
        }
        return streams
            .filter { $0.kind == kind }
            .compactMap { stream -> NaLive.Row? in
                guard let parsed = URL(string: stream.url), parsed.scheme == "https" else { return nil }
                let meters = GraphRouter.haversine(lat, lon, stream.lat, stream.lon)
                return NaLive.Row(
                    id: stream.id,
                    name: stream.name,
                    url: stream.url,
                    meters: meters,
                    range: BlackoutTokens.Distance.hud(meters)
                )
            }
            .sorted { $0.meters < $1.meters }
    }
}
