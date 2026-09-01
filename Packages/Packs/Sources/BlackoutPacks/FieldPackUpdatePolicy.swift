import Foundation

/// User-tapped map updates. Never silent, never on launch, never in the background.
public enum FieldPackUpdatePolicy {
    public static let updateMapsLabel = "Update maps"
    public static let useCellularLabel = "Use Cellular"
    public static let getLabel = "Get"
    public static let upToDateCopy = "Up to date"
    public static let nearbyGetCopy =
        "Get from nearby — ask a phone that has this pack to Send pack."
    public static let noPathCopy =
        "No network. Update maps is off. Tiles already on disk still work."
    public static let lastTwoPercentCopy = "Last 2%. No downloads."

    public static func batchTargets(
        from catalog: [FieldPackDescriptor] = FieldPackCatalog.installablePacks
    ) -> [FieldPackDescriptor] {
        catalog.filter { $0.downloadURL != nil && $0.assetReady }
    }

    public static func showsRowGet(
        isInstalled: Bool,
        isCityExtra: Bool,
        hasRemoteURL: Bool
    ) -> Bool {
        !isInstalled && isCityExtra && hasRemoteURL
    }

    public static func updateMapsEnabled(
        downloadsAllowed: Bool,
        pathSatisfied: Bool,
        batchRunning: Bool
    ) -> Bool {
        downloadsAllowed && pathSatisfied && !batchRunning
    }

    public static func needsCellularConfirm(pathSatisfied: Bool, onWiFi: Bool) -> Bool {
        pathSatisfied && !onWiFi
    }

    public static func shouldFetch(
        catalogSHA: String?,
        recordedSHA: String?,
        isInstalled: Bool = true
    ) -> Bool {
        guard let catalog = normalizedSHA(catalogSHA) else { return false }
        if !isInstalled { return true }
        guard let recorded = normalizedSHA(recordedSHA) else { return true }
        return recorded != catalog
    }

    public static func byteSizeLabel(_ bytes: Int?) -> String? {
        guard let bytes, bytes > 0 else { return nil }
        let mb = max(1, bytes / 1_000_000)
        return "\(mb) MB"
    }

    public static func normalizedSHA(_ value: String?) -> String? {
        guard let value else { return nil }
        let hex = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard hex.count == 64, hex.contains(where: { $0 != "0" }) else { return nil }
        return hex
    }
}
