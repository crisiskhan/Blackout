import MapKit

/// Local file tiles only. `canReplaceMapContent` is set so this overlay is a full
/// replacement, not an add-on to Apple raster. Blackout never installs it on MKMapView;
/// the offline canvas calls `tileData` / `loadTile` and reads `file://` itself.
public final class BundledTileOverlay: MKTileOverlay {
    private let packRoot: URL

    public init(packRoot: URL, minZoom: Int, maxZoom: Int) {
        self.packRoot = packRoot
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: 256, height: 256)
        minimumZ = minZoom
        maximumZ = maxZoom
        canReplaceMapContent = true
    }

    public override func url(forTilePath path: MKTileOverlayPath) -> URL {
        packRoot
            .appendingPathComponent("tiles", isDirectory: true)
            .appendingPathComponent("\(path.z)", isDirectory: true)
            .appendingPathComponent("\(path.x)", isDirectory: true)
            .appendingPathComponent("\(path.y).png")
    }

    public func tileData(z: Int, x: Int, y: Int) -> Data? {
        var path = MKTileOverlayPath()
        path.x = x
        path.y = y
        path.z = z
        path.contentScaleFactor = 1
        let fileURL = url(forTilePath: path)
        guard fileURL.isFileURL else { return nil }
        return try? Data(contentsOf: fileURL, options: [.mappedIfSafe])
    }

    public override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let fileURL = url(forTilePath: path)
        guard fileURL.isFileURL else {
            result(nil, nil)
            return
        }
        do {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            result(data, nil)
        } catch {
            result(nil, nil)
        }
    }
}
