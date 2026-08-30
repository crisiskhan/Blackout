import Foundation

/// Sealed Guide card over mesh. Id only — never a rewritten body, never a WAN fetch.
public enum GuideCardWire {
    public static let envelopeKind = PayloadKind.guideCard
    public static let missingCopy = "Card not on this pack"
    public static let sendLabel = "Send to party"

    public static func encode(articleID: String) -> Data {
        let id = articleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = Wire(v: 1, articleID: id)
        return (try? JSONEncoder().encode(body)) ?? Data(id.utf8)
    }

    public static func decode(_ data: Data) -> String? {
        if let body = try? JSONDecoder().decode(Wire.self, from: data) {
            let id = body.articleID.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : id
        }
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    public static func envelope(articleID: String, sender: BlackoutID, recipient: BlackoutID) -> Envelope {
        Envelope(
            kind: envelopeKind,
            ciphertext: encode(articleID: articleID),
            sender: sender,
            recipient: recipient
        )
    }

    public static func isIdOnly(_ data: Data, expectedID: String) -> Bool {
        guard let id = decode(data) else { return false }
        let blob = String(data: data, encoding: .utf8) ?? ""
        return id == expectedID && !blob.contains("###") && !blob.contains("Situation")
    }

    private struct Wire: Codable {
        var v: Int
        var articleID: String
    }
}

/// Shareable breadcrumb track. Party mesh only — not a GPX cloud.
public enum FollowTrackWire {
    public static let envelopeKind = PayloadKind.followTrack
    public static let emptyReason = "No track yet."
    public static let shareLabel = "Share track"
    public static let disabledOpacity = 0.38

    public struct Point: Hashable, Codable, Sendable {
        public var latitude: Double
        public var longitude: Double
        public var estimated: Bool

        public init(latitude: Double, longitude: Double, estimated: Bool = false) {
            self.latitude = latitude
            self.longitude = longitude
            self.estimated = estimated
        }
    }

    public static func points(from crumbs: [BreadcrumbRecordDTO]) -> [Point] {
        crumbs.compactMap { crumb in
            guard crumb.hasCoordinate, let lat = crumb.latitude, let lon = crumb.longitude else {
                return nil
            }
            return Point(latitude: lat, longitude: lon, estimated: crumb.estimated)
        }
    }

    public static func canShare(crumbs: [BreadcrumbRecordDTO]) -> Bool {
        points(from: crumbs).count >= 2
    }

    public static func encode(_ points: [Point]) -> Data {
        (try? JSONEncoder().encode(Wire(v: 1, points: points))) ?? Data()
    }

    public static func decode(_ data: Data) -> [Point]? {
        (try? JSONDecoder().decode(Wire.self, from: data))?.points
    }

    public static func envelope(points: [Point], sender: BlackoutID, recipient: BlackoutID) -> Envelope {
        Envelope(
            kind: envelopeKind,
            ciphertext: encode(points),
            sender: sender,
            recipient: recipient
        )
    }

    private struct Wire: Codable {
        var v: Int
        var points: [Point]
    }
}

/// Map overlay search. Clamped to the pack bbox. Never auto-SOS.
public enum SearchPatternKind: String, Codable, Sendable, CaseIterable {
    case expandingSquare
    case contour
    case trackCrawl

    public var title: String {
        switch self {
        case .expandingSquare: return "Expanding square"
        case .contour: return "Contour"
        case .trackCrawl: return "Track crawl"
        }
    }
}

public enum SearchPattern {
    public static let controlHeight: Double = 56
    public static let autoSOS = false

    public static func clamp(
        latitude: Double,
        longitude: Double,
        region: MapRegion
    ) -> (Double, Double) {
        (
            min(max(latitude, region.south), region.north),
            min(max(longitude, region.west), region.east)
        )
    }

    public static func polyline(
        kind: SearchPatternKind,
        originLatitude: Double,
        originLongitude: Double,
        region: MapRegion,
        stepMeters: Double = 80
    ) -> [(Double, Double)] {
        let origin = clamp(latitude: originLatitude, longitude: originLongitude, region: region)
        let raw: [(Double, Double)]
        switch kind {
        case .expandingSquare:
            raw = expandingSquare(origin: origin, stepMeters: stepMeters)
        case .contour:
            raw = contour(origin: origin, stepMeters: stepMeters)
        case .trackCrawl:
            raw = trackCrawl(origin: origin, stepMeters: stepMeters)
        }
        return raw.map { clamp(latitude: $0.0, longitude: $0.1, region: region) }
    }

    public static func staysInPackBBox(
        points: [(Double, Double)],
        region: MapRegion
    ) -> Bool {
        points.allSatisfy { region.contains(latitude: $0.0, longitude: $0.1) }
    }

    private static func expandingSquare(
        origin: (Double, Double),
        stepMeters: Double
    ) -> [(Double, Double)] {
        var points = [origin]
        var lat = origin.0
        var lon = origin.1
        var leg = 1
        var heading = 0
        for _ in 0..<10 {
            let meters = stepMeters * Double(leg)
            let dest = offset(latitude: lat, longitude: lon, meters: meters, bearing: Double(heading))
            points.append(dest)
            lat = dest.0
            lon = dest.1
            heading = (heading + 90) % 360
            if heading == 0 || heading == 180 {
                leg += 1
            }
        }
        return points
    }

    private static func contour(
        origin: (Double, Double),
        stepMeters: Double
    ) -> [(Double, Double)] {
        var points: [(Double, Double)] = [origin]
        for ring in 1...4 {
            let radius = stepMeters * Double(ring)
            for i in 0..<12 {
                let bearing = Double(i) * 30
                points.append(offset(latitude: origin.0, longitude: origin.1, meters: radius, bearing: bearing))
            }
            points.append(offset(latitude: origin.0, longitude: origin.1, meters: radius, bearing: 0))
        }
        return points
    }

    private static func trackCrawl(
        origin: (Double, Double),
        stepMeters: Double
    ) -> [(Double, Double)] {
        var points: [(Double, Double)] = [origin]
        for i in 0..<8 {
            let along = stepMeters * Double(i + 1)
            let side = (i % 2 == 0) ? 90.0 : 270.0
            let mid = offset(latitude: origin.0, longitude: origin.1, meters: along, bearing: 0)
            points.append(mid)
            points.append(offset(latitude: mid.0, longitude: mid.1, meters: stepMeters, bearing: side))
        }
        return points
    }

    private static func offset(
        latitude: Double,
        longitude: Double,
        meters: Double,
        bearing: Double
    ) -> (Double, Double) {
        let r = 6_371_000.0
        let brng = bearing * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(meters / r) + cos(lat1) * sin(meters / r) * cos(brng))
        let lon2 = lon1 + atan2(
            sin(brng) * sin(meters / r) * cos(lat1),
            cos(meters / r) - sin(lat1) * sin(lat2)
        )
        return (lat2 * 180 / .pi, lon2 * 180 / .pi)
    }
}

/// Leave-behind relay. Mesh stays up; 2% and Leave/End stop it.
public enum LeaveBehindRelayPolicy {
    public static let control = "Stay as relay"
    public static let banner = "Relay on. Mesh stays up."

    public static func isActive(
        enabled: Bool,
        expeditionOpen: Bool,
        batteryCritical: Bool
    ) -> Bool {
        enabled && expeditionOpen && !batteryCritical
    }

    public static func shouldStop(leaveOrEnd: Bool, batteryCritical: Bool) -> Bool {
        leaveOrEnd || batteryCritical
    }
}

/// Night red-light. Not light mode. Surfaces stay dark; chrome/type go red.core / red.sun.
public enum NightRedMode {
    public static let isLightMode = false
    public static let preferredSchemeDark = true
    public static let raisesBrightness = false

    public static func chromeColor(on: Bool) -> (red: Double, green: Double, blue: Double) {
        if on { return (1, 43 / 255, 43 / 255) }
        return (197 / 255, 205 / 255, 214 / 255)
    }

    public static func typeColor(on: Bool) -> (red: Double, green: Double, blue: Double) {
        if on { return (1, 74 / 255, 74 / 255) }
        return (232 / 255, 237 / 255, 242 / 255)
    }
}

/// Party-split / kid cards as a Map mode plate. Not a fifth tab. Not SOS.
public enum FieldJobMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case partySplit = "party-split"
    case kidLost = "kid-lost"
    case kidHeat = "kid-heat"
    case kidBite = "kid-bite"

    public var id: String { rawValue }
    public var articleID: String { rawValue }

    public var title: String {
        switch self {
        case .partySplit: return "Party split"
        case .kidLost: return "Kid lost"
        case .kidHeat: return "Kid heat"
        case .kidBite: return "Kid bite"
        }
    }

    public var steps: [String] {
        switch self {
        case .partySplit:
            return [
                "Stop the group. Mark this spot.",
                "Write last seen, clothing, heading.",
                "Three whistle blasts. Wait before you chase.",
            ]
        case .kidLost:
            return [
                "Sit. The child stays with an adult.",
                "Name the last sure point.",
                "Stay and signal. Adults move.",
            ]
        case .kidHeat:
            return [
                "Shade now. Pack off.",
                "Sip small if they can keep it down.",
                "Watch quiet, cranky, or wobbly.",
            ]
        case .kidBite:
            return [
                "Move away from the animal. Do not hunt it.",
                "Sit. Keep the limb still.",
                "Get to care. This is not SOS auto-arm.",
            ]
        }
    }

    public static let replacesSOS = false

    public static func from(articleID: String) -> FieldJobMode? {
        FieldJobMode(rawValue: articleID)
    }
}

/// Dead-reckon honesty. Estimated crumbs are never GPS-quality.
public enum DeadReckoningHonesty {
    public static let chip = "Dead reckoning, GPS lost."
    public static let motionDeniedCopy = "Motion denied. Last-known and compass only."

    public static func chipVisible(gpsLive: Bool, isDeadReckoning: Bool) -> Bool {
        isDeadReckoning && !gpsLive
    }

    public static func canDeadReckon(motionDenied: Bool) -> Bool {
        !motionDenied
    }

    public static func isEstimated(source: LocationFixSource) -> Bool {
        source == .deadReckoning
    }

    public static func drawnAsGPS(source: LocationFixSource) -> Bool {
        source == .gps
    }

    public static func crumbEstimated(fix: LocationFix?) -> Bool {
        guard let fix else { return false }
        return fix.source == .deadReckoning
    }
}

/// Pack zip names the radio will carry. Mesh does not parse zip bytes.
public enum PackRelayPolicy {
    public static let sendLabel = "Send pack"
    public static let receivingCopy = "Receiving from nearby phone…"
    public static let readyCopy = "Ready"

    public static func isRelayable(_ id: String) -> Bool {
        switch id {
        case "el-paso", "las-cruces", "albuquerque", "us-tx", "us-nm", "us-fl", "us-ny":
            return true
        default:
            return false
        }
    }

    public static func sendEnabled(nearbyPeerCount: Int) -> Bool {
        nearbyPeerCount >= 1
    }
}

/// Viewshed empty / deny. Airplane uses on-disk DEM.
public enum ViewshedPolicy {
    public static let noDEM = "No DEM."
    public static let sampleQuality = "Sample-quality viewshed. Not USGS."

    public static func toggleEnabled(hasDEM: Bool) -> Bool {
        hasDEM
    }

    public static func origin(
        locationDenied: Bool,
        navigationFix: LocationFix?,
        droppedPin: LocationFix?
    ) -> LocationFix? {
        if locationDenied {
            return droppedPin?.hasCoordinate == true ? droppedPin : nil
        }
        if let navigationFix, navigationFix.hasCoordinate { return navigationFix }
        return droppedPin?.hasCoordinate == true ? droppedPin : nil
    }
}
