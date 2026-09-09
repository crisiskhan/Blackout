import Foundation

/// How to name a local PMTiles archive so MapLibre will read it.
///
/// MapLibre's PMTiles source strips the `pmtiles://` prefix and hands whatever
/// is left back to its own loader, so the tail has to be a URL that loader can
/// already fetch — the same `file://` form the glyphs use. Measured on a
/// simulator against a real archive rather than assumed:
///
///     pmtiles://file:///…/osm.pmtiles   999 features drawn
///     pmtiles:///…/osm.pmtiles            0 features drawn
public enum PMTilesURL {
    public static let scheme = "pmtiles://"

    /// The spelling the app ships.
    public static func shipped(for archive: URL) -> String {
        scheme + archive.absoluteString
    }

    /// True when a style source string is a PMTiles reference the resolver
    /// still needs to point at a real location on this phone.
    public static func isRelative(_ url: String) -> Bool {
        guard url.hasPrefix(scheme) else { return false }
        let tail = url.dropFirst(scheme.count)
        return !tail.contains("://") && !tail.hasPrefix("/")
    }

    /// Rewrite `pmtiles://osm.pmtiles` into an absolute reference inside a pack.
    public static func resolve(_ url: String, packRoot: URL) -> String {
        guard isRelative(url) else { return url }
        let relative = String(url.dropFirst(scheme.count))
        return shipped(for: packRoot.appendingPathComponent(relative))
    }
}
