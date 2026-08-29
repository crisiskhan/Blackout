import BlackoutCore
import Foundation

/// GitHub Releases host for optional region packs. Bundle ID stays
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
        id: "us-tx",
        title: "Texas",
        summary: "Bundled. Ready. Statewide Texas. Works airplane.",
        downloadURL: releaseBase.appendingPathComponent("texas.pack.zip"),
        sha256: "dc74d8069ca161f0c818dcfb760037d79ae96c9da777b550f095cf0b9569bbfb",
        byteCount: 208_461_647,
        assetReady: true,
        isBundled: true,
        region: MapRegion(
            name: "Texas",
            centerLatitude: 31.17,
            centerLongitude: -100.08,
            spanLatitude: 10.6636,
            spanLongitude: 13.1378,
            minZoom: 8,
            maxZoom: 12
        )
    )

    public static let newMexico = FieldPackDescriptor(
        id: "us-nm",
        title: "New Mexico",
        summary: "Bundled. Ready. Statewide New Mexico. Works airplane.",
        downloadURL: releaseBase.appendingPathComponent("new-mexico.pack.zip"),
        sha256: "2e605b0a386c6fbfa1288e5bea4ef96f42ddd5c60633f954b42c8c0e7665a4a8",
        byteCount: 77_478_829,
        assetReady: true,
        isBundled: true,
        region: MapRegion(
            name: "New Mexico",
            centerLatitude: 34.17,
            centerLongitude: -106.03,
            spanLatitude: 5.6681,
            spanLongitude: 6.0483,
            minZoom: 8,
            maxZoom: 12
        )
    )

    public static let florida = FieldPackDescriptor(
        id: "us-fl",
        title: "Florida",
        summary: "Bundled. Ready. Statewide Florida. Works airplane.",
        downloadURL: releaseBase.appendingPathComponent("florida.pack.zip"),
        sha256: "49d27c808c49fc894a1ba1021f951966560408c1ebe808f4c0d158e0c238b62d",
        byteCount: 79_093_063,
        assetReady: true,
        isBundled: true,
        region: MapRegion(
            name: "Florida",
            centerLatitude: 27.6986,
            centerLongitude: -83.8046,
            spanLatitude: 6.6047,
            spanLongitude: 7.6606,
            minZoom: 8,
            maxZoom: 12
        )
    )

    public static let newYork = FieldPackDescriptor(
        id: "us-ny",
        title: "New York",
        summary: "Bundled. Ready. Statewide New York. Works airplane.",
        downloadURL: releaseBase.appendingPathComponent("new-york.pack.zip"),
        sha256: "928034851277ab8628521f5bfd7f2f06e6bfed5b588d58f9b46033bae5e64500",
        byteCount: 130_327_390,
        assetReady: true,
        isBundled: true,
        region: MapRegion(
            name: "New York",
            centerLatitude: 42.7466,
            centerLongitude: -75.7569,
            spanLatitude: 4.5385,
            spanLongitude: 8.0114,
            minZoom: 8,
            maxZoom: 12
        )
    )

    public static let elPaso = FieldPackDescriptor(
        id: "el-paso",
        title: "El Paso",
        summary: "USGS topo, 158 tiles z10–z12. Download on Wi-Fi, then airplane.",
        downloadURL: releaseBase.appendingPathComponent("el-paso.pack.zip"),
        sha256: "60ce5dd4297058e17c4a8a7992525cd363b74c1879aadda25bd1dcfcaa8b0236",
        byteCount: 8_568_180,
        assetReady: true,
        isBundled: false,
        region: MapRegion(
            name: "El Paso",
            centerLatitude: 31.7619,
            centerLongitude: -106.485,
            spanLatitude: 0.8,
            spanLongitude: 0.8,
            minZoom: 10,
            maxZoom: 12
        )
    )

    public static let lasCruces = FieldPackDescriptor(
        id: "las-cruces",
        title: "Las Cruces",
        summary: "USGS topo, 124 tiles z10–z12. Download on Wi-Fi, then airplane.",
        downloadURL: releaseBase.appendingPathComponent("las-cruces.pack.zip"),
        sha256: "ca4f180f6cacb3d32a063b01ee97249b9f6b3f704c1fad5150604a55c626c23a",
        byteCount: 8_050_812,
        assetReady: true,
        isBundled: false,
        region: MapRegion(
            name: "Las Cruces",
            centerLatitude: 32.3199,
            centerLongitude: -106.7637,
            spanLatitude: 0.7,
            spanLongitude: 0.7,
            minZoom: 10,
            maxZoom: 12
        )
    )

    public static let albuquerque = FieldPackDescriptor(
        id: "albuquerque",
        title: "Albuquerque",
        summary: "USGS topo, 138 tiles z10–z12. Download on Wi-Fi, then airplane.",
        downloadURL: releaseBase.appendingPathComponent("albuquerque.pack.zip"),
        sha256: "519a413785f8036860b806ce9c81c880e7f87ef301e156d378a80d9e75e945f6",
        byteCount: 12_266_566,
        assetReady: true,
        isBundled: false,
        region: MapRegion(
            name: "Albuquerque",
            centerLatitude: 35.0844,
            centerLongitude: -106.6504,
            spanLatitude: 0.7,
            spanLongitude: 0.7,
            minZoom: 10,
            maxZoom: 12
        )
    )

    /// IPA-ready statewide packs. Archive fetches these; compile does not.
    public static let bundledStatewide: [FieldPackDescriptor] = [
        florida, texas, newYork, newMexico
    ]

    /// Optional extras. User-initiated download or 1/N radio only.
    public static let remotePacks: [FieldPackDescriptor] = [
        elPaso, lasCruces, albuquerque
    ]

    public static let installablePacks: [FieldPackDescriptor] = bundledStatewide + remotePacks
    public static let all: [FieldPackDescriptor] = [denver] + installablePacks

    /// v1 radio relay. Statewide packs stay bundled, not radio-sent.
    public static let cityRelayIDs: Set<String> = ["el-paso", "las-cruces", "albuquerque"]

    public static func isCityRelay(_ id: String) -> Bool {
        cityRelayIDs.contains(id)
    }

    public static func descriptor(id: String) -> FieldPackDescriptor? {
        all.first(where: { $0.id == id })
    }
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
    case available
    case ready
    case failed
    case skip
}
