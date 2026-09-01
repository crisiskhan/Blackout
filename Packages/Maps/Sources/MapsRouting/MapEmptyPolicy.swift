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

    /// Crisis override. `radarOn` never paints polar HUD / DBZ overlay on the Map tab.
    public static func showsRadar(
        packMounted: Bool,
        sosOnly: Bool,
        radarOn: Bool,
        extremeSaver: Bool
    ) -> Bool {
        _ = packMounted
        _ = sosOnly
        _ = radarOn
        _ = extremeSaver
        return false
    }

    /// Follow-puck stays on the covering pack. Recenter pins coverage, never a GPS void.
    public static func followGPS(pinToPack: Bool, packContainsSelf: Bool) -> Bool {
        !pinToPack && packContainsSelf
    }
}
