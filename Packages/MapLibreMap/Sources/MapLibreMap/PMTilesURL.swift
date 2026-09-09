import Foundation

/// How to name a local PMTiles archive so MapLibre will read it.
///
/// MapLibre's PMTiles source strips the `pmtiles://` prefix and hands whatever
/// is left back to its own loader, so the tail has to be a URL that loader can
/// already fetch — the same `file://` form the glyphs use. The alternative
/// spelling (a bare absolute path) is kept only so the render probe can prove
/// which one the renderer honours instead of us assuming.
public enum PMTilesURL {
    public static let scheme = "pmtiles://"

    /// The spelling the app ships. Wraps the `file://` URL that this codebase
    /// already knows MapLibre resolves, because glyphs load the same way.
    public static func shipped(for archive: URL) -> String {
        scheme + archive.absoluteString
    }

    /// Every spelling worth testing, best guess first.
    public static func candidates(for archive: URL) -> [String] {
        [shipped(for: archive), scheme + archive.path]
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
