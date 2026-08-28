import BlackoutCore
import Foundation

/// GitHub Releases host for optional region packs. CoS replaces `sha256` and
/// sets `assetReady` when `packs-v1` assets exist. Bundle ID stays
/// `com.crisiskhan.blackout`. No Blackout cloud.
public enum FieldPackCatalog {
    public static let releaseTag = "packs-v1"
    public static let releaseBase = URL(
        string: "https://github.com/crisiskhan/Blackout/releases/download/\(releaseTag)/"
    )!

    public static let denver = FieldPackDescriptor(
        id: "denver-front-range",
        title: "Denver / Front Range",
        summary: "Bundled sample. Always on disk. Works airplane.",
        downloadURL: nil,
        sha256: nil,
        byteCount: nil,
        assetReady: true,
        isBundled: true,
        region: MapRegion(
            name: "Front Range sample",
            centerLatitude: 39.74,
            centerLongitude: -105.3,
            spanLatitude: 0.32,
            spanLongitude: 0.5,
            minZoom: 10,
            maxZoom: 12
        )
    )

    public static let texas = FieldPackDescriptor(
        id: "texas",
        title: "Texas",
        summary: "Download on Wi-Fi, then airplane.",
        downloadURL: releaseBase.appendingPathComponent("texas.pack.zip"),
        sha256: "0000000000000000000000000000000000000000000000000000000000000000",
        byteCount: nil,
        assetReady: false,
        isBundled: false,
        region: MapRegion(
            name: "Texas",
            centerLatitude: 31.0,
            centerLongitude: -99.9,
            spanLatitude: 10.5,
            spanLongitude: 13.5,
            minZoom: 8,
            maxZoom: 12
        )
    )

    public static let newMexico = FieldPackDescriptor(
        id: "new-mexico",
        title: "New Mexico",
        summary: "Download on Wi-Fi, then airplane.",
        downloadURL: releaseBase.appendingPathComponent("new-mexico.pack.zip"),
        sha256: "0000000000000000000000000000000000000000000000000000000000000000",
        byteCount: nil,
        assetReady: false,
        isBundled: false,
        region: MapRegion(
            name: "New Mexico",
            centerLatitude: 34.3,
            centerLongitude: -106.0,
            spanLatitude: 6.4,
            spanLongitude: 6.8,
            minZoom: 8,
            maxZoom: 12
        )
    )

    public static let remotePacks: [FieldPackDescriptor] = [texas, newMexico]
    public static let all: [FieldPackDescriptor] = [denver] + remotePacks
}

public struct FieldPackDescriptor: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var downloadURL: URL?
    public var sha256: String?
    public var byteCount: Int?
    public var assetReady: Bool
    public var isBundled: Bool
    public var region: MapRegion
}

public enum FieldPackRowState: String, Sendable {
    case noWifi
    case downloading
    case ready
    case failed
    case skip
}
