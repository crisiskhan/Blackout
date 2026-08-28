import MapKit

/// Local file tiles only. Overrides loadTile so MapKit never hits the network downloader.
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
