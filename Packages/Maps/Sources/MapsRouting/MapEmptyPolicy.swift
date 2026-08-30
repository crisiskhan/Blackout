import Foundation

/// Empty card replaces the tile canvas. Never a world basemap underneath.
public enum MapEmptyPolicy {
    public static func paintsCanvas(packMounted: Bool) -> Bool {
        packMounted
    }

    public static func showsEmptyCard(packMounted: Bool) -> Bool {
        !packMounted
    }

    public static func showsChips(packMounted: Bool, sosOnly: Bool) -> Bool {
        packMounted && !sosOnly
    }

    public static func showsRadar(
        packMounted: Bool,
        sosOnly: Bool,
        radarOn: Bool,
        extremeSaver: Bool
    ) -> Bool {
        if sosOnly || !packMounted { return false }
        if extremeSaver { return true }
        return radarOn
    }

    /// Follow-puck stays on the covering pack. Recenter pins coverage, never a GPS void.
    public static func followGPS(pinToPack: Bool, packContainsSelf: Bool) -> Bool {
        !pinToPack && packContainsSelf
    }
}
