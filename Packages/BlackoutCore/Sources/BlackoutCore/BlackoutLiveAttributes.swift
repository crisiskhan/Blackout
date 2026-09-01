#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Lock-screen Live Activity. Not a second SOS fire.
public struct BlackoutLiveAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var callsign: String
        public var lastPingLabel: String
        public var peerCount: Int
        public var openMap: Bool

        public init(
            callsign: String,
            lastPingLabel: String,
            peerCount: Int,
            openMap: Bool
        ) {
            self.callsign = callsign
            self.lastPingLabel = lastPingLabel
            self.peerCount = peerCount
            self.openMap = openMap
        }
    }

    public var title: String

    public init(title: String = "BLACKOUT") {
        self.title = title
    }
}

public enum BlackoutLiveLink {
    public static let map = URL(string: "blackout://map")!
    public static let comms = URL(string: "blackout://comms")!

    public static func url(openMap: Bool) -> URL {
        openMap ? map : comms
    }
}
#endif
