import Foundation

/// Pause stack copy. Honest empties. No XP. No invented roster.
public enum ExpeditionPauseCopy {
    public static let title = "Pause"
    public static let subtitle = "This outing. Local only."
    public static let rosterEmpty = "Solo outing. Roster is empty."
    public static let gearStub = "No custom kit. Default outing list."
    public static let packsReady = "Florida, Texas, New York, and New Mexico are Ready on this phone."
    public static let packManager = "Pack manager"
    public static let sections = ["Roster", "Gear", "Packs", "Settings"]
}

/// GuidePack tools cards that exist on disk. Not a 17-cell inventory grid.
public enum DefaultOutingGear {
    public static let items = [
        "Headlamp",
        "Knife",
        "Cordage",
        "Ferro rod",
        "Tarp kit",
        "Repair kit"
    ]
}
