import BlackoutCore
import Foundation

/// GitHub Releases host for optional region packs. Bundle ID stays
/// `com.crisiskhan.blackout`. No Blackout cloud.
///
/// Pack-gap (50 recode, CPV stays 49): z16 town insets (TX/NM/FL) and statewide
/// `routing/graph.bin` are not in this tree. Catalog `maxZoom` stays 12. Chrome +
/// on-device routing must not stall generating those packs. Systems may add them
/// separately. Honest empty if `packService.routing` is nil.
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
        sha256: "6ff6c9a191fe5df8d3bf48abb360ad361990bc672c1c59bd0cf2e3a3d5d55ade",
        byteCount: 220_512_882,
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

    public static let elPaso = FieldPackDescriptor(
        id: "el-paso",
        title: "El Paso",
        summary: "USGS topo + OSM shops, civic, and field points. Download on Wi-Fi, then airplane.",
        downloadURL: releaseBase.appendingPathComponent("el-paso.pack.zip"),
        sha256: "883158ef09620500b06eaf564f43c02a95fbb71ac9bf11592e325e644c72f34b",
        byteCount: 20_215_735,
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
        summary: "USGS topo + OSM shops, civic, and field points. Download on Wi-Fi, then airplane.",
        downloadURL: releaseBase.appendingPathComponent("las-cruces.pack.zip"),
        sha256: "f26b8675adb9fe0e8b09161f28659f208e609d201104d4c185728060508ddad4",
        byteCount: 8_076_313,
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
        summary: "USGS topo + OSM shops, civic, and field points. Download on Wi-Fi, then airplane.",
        downloadURL: releaseBase.appendingPathComponent("albuquerque.pack.zip"),
        sha256: "29a8dc25e0d923df6845f26a30569393b707297a1ab73ea43f3d72e50756d01d",
        byteCount: 12_308_725,
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

    /// Designated statewide packs. Archive fetches these; compile does not.
    /// UI Ready is disk-only — see FieldPackHonesty.
    public static let bundledStatewide: [FieldPackDescriptor] = [
        florida, texas, newMexico
    ]

    /// Optional extras. User-initiated download or 1/N radio only.
    public static let remotePacks: [FieldPackDescriptor] = [
        elPaso, lasCruces, albuquerque
    ]

    public static let installablePacks: [FieldPackDescriptor] = bundledStatewide + remotePacks
    public static let all: [FieldPackDescriptor] = [denver] + installablePacks

    /// City extras plus statewide zips. Mesh carries opaque zip bytes only.
    public static let cityRelayIDs: Set<String> = ["el-paso", "las-cruces", "albuquerque"]

    public static func isCityRelay(_ id: String) -> Bool {
        cityRelayIDs.contains(id)
    }

    public static func isRelayable(_ id: String) -> Bool {
        PackRelayPolicy.isRelayable(id)
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

/// Three states on disk (FL / TX / NM). Skip and first-run available are gone.
public enum FieldPackRowState: String, Sendable, CaseIterable {
    case noWifi
    case downloading
    case ready
    case failed
}
