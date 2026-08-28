import BlackoutCore
import SwiftUI
import UIKit

/// File-tile map. Does **not** create MKMapView, so Apple raster/CDN is not on first paint.
struct OfflineMapView: UIViewRepresentable {
    var pack: MapPackSnapshot
    var selfFix: LocationFix?
    var manualPin: LocationFix?
    var breadcrumbs: [BreadcrumbRecordDTO]
    var viewshed: [ViewshedRay]
    var slope: [SlopeSample]
    var showViewshed: Bool
    var showSlope: Bool
    var centerToken: Int
    /// When true, Recenter pinned the camera to pack coverage. GPS follow
    /// (El Paso 31.87,-106.60 etc.) must not yank the camera off Denver tiles.
    var pinCameraToPack: Bool
    var onDropPin: (Double, Double) -> Void
    var onOutsidePack: (Bool) -> Void
    var resetToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(onDropPin: onDropPin, onOutsidePack: onOutsidePack)
    }

    func makeUIView(context: Context) -> OfflineTileScrollView {
        let view = OfflineTileScrollView(pack: pack)
        view.coordinator = context.coordinator
        view.applyOverlays(
            selfFix: selfFix,
            manualPin: manualPin,
            breadcrumbs: breadcrumbs,
            viewshed: viewshed,
            slope: slope,
            showViewshed: showViewshed,
            showSlope: showSlope
        )
        return view
    }

    func updateUIView(_ view: OfflineTileScrollView, context: Context) {
        context.coordinator.onDropPin = onDropPin
        context.coordinator.onOutsidePack = onOutsidePack
        view.coordinator = context.coordinator
        view.applyOverlays(
            selfFix: selfFix,
            manualPin: manualPin,
            breadcrumbs: breadcrumbs,
            viewshed: viewshed,
            slope: slope,
            showViewshed: showViewshed,
            showSlope: showSlope
        )
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            view.recenterToPackCoverage()
        }
        if context.coordinator.lastCenterToken != centerToken {
            context.coordinator.lastCenterToken = centerToken
            // Heading-up / "center on me" only. Recenter to pack coverage
            // never uses this path — GPS outside the sample paints void.
            if !pinCameraToPack, let selfFix, selfFix.hasCoordinate {
                view.centerOn(latitude: selfFix.latitude!, longitude: selfFix.longitude!)
            }
        }
    }

    final class Coordinator {
        var onDropPin: (Double, Double) -> Void
        var onOutsidePack: (Bool) -> Void
        var lastResetToken = 0
        var lastCenterToken = 0

        init(onDropPin: @escaping (Double, Double) -> Void, onOutsidePack: @escaping (Bool) -> Void) {
            self.onDropPin = onDropPin
            self.onOutsidePack = onOutsidePack
        }
    }
}

final class OfflineTileScrollView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    weak var coordinator: OfflineMapView.Coordinator?
    private let pack: MapPackSnapshot
    private let overlay: BundledTileOverlay
    private let scroll = UIScrollView()
    private let canvas = TileCanvasLayer()
    private let x0: Int
    private let y0: Int
    private let zMax: Int
    private let zMin: Int
    private var lastOutside = false
    private var didFit = false

    init(pack: MapPackSnapshot) {
        self.pack = pack
        zMax = pack.region.maxZoom
        zMin = pack.region.minZoom
        overlay = BundledTileOverlay(
            packRoot: pack.rootURL,
            minZoom: pack.region.minZoom,
            maxZoom: pack.region.maxZoom
        )
        let west = pack.region.centerLongitude - pack.region.spanLongitude / 2
        let east = pack.region.centerLongitude + pack.region.spanLongitude / 2
        let south = pack.region.centerLatitude - pack.region.spanLatitude / 2
        let north = pack.region.centerLatitude + pack.region.spanLatitude / 2
        x0 = Int(floor(WebMercator.tileX(longitude: west, zoom: zMax)))
        let x1 = Int(floor(WebMercator.tileX(longitude: east, zoom: zMax)))
        y0 = Int(floor(WebMercator.tileY(latitude: north, zoom: zMax)))
        let y1 = Int(floor(WebMercator.tileY(latitude: south, zoom: zMax)))
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 7 / 255, green: 8 / 255, blue: 10 / 255, alpha: 1)
        scroll.delegate = self
        scroll.backgroundColor = backgroundColor
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.bounces = true
        scroll.bouncesZoom = true
        addSubview(scroll)
        canvas.overlay = overlay
        canvas.x0 = x0
        canvas.y0 = y0
        canvas.zMax = zMax
        canvas.zMin = zMin
        canvas.cols = max(1, x1 - x0 + 1)
        canvas.rows = max(1, y1 - y0 + 1)
        canvas.backgroundColor = backgroundColor
        canvas.frame = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(canvas.cols) * 256,
            height: CGFloat(canvas.rows) * 256
        )
        scroll.addSubview(canvas)
        scroll.contentSize = canvas.frame.size
        scroll.minimumZoomScale = 0.2
        scroll.maximumZoomScale = 4
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0.55
        canvas.addGestureRecognizer(press)
        canvas.isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        if !didFit, bounds.width > 0, canvas.bounds.width > 0 {
            didFit = true
            recenterToPackCoverage()
        }
        reportOutside()
    }

    func recenterToPackCoverage() {
        let fit = min(
            bounds.width / max(canvas.bounds.width, 1),
            bounds.height / max(canvas.bounds.height, 1)
        )
        scroll.minimumZoomScale = min(0.2, max(fit * 0.5, 0.05))
        scroll.setZoomScale(max(fit, scroll.minimumZoomScale), animated: false)
        centerPack()
        // Manifest center (Denver / Front Range). Never GPS / last-known.
        centerOn(latitude: pack.region.centerLatitude, longitude: pack.region.centerLongitude)
        lastOutside = false
        coordinator?.onOutsidePack(false)
        reportOutside()
    }

    func applyOverlays(
        selfFix: LocationFix?,
        manualPin: LocationFix?,
        breadcrumbs: [BreadcrumbRecordDTO],
        viewshed: [ViewshedRay],
        slope: [SlopeSample],
        showViewshed: Bool,
        showSlope: Bool
    ) {
        canvas.selfFix = selfFix
        canvas.manualPin = manualPin
        canvas.breadcrumbs = breadcrumbs
        canvas.viewshed = viewshed
        canvas.slope = slope
        canvas.showViewshed = showViewshed
        canvas.showSlope = showSlope
        canvas.setNeedsDisplay()
    }

    func centerOn(latitude: Double, longitude: Double) {
        let fix = LocationFix(latitude: latitude, longitude: longitude)
        guard let point = canvas.point(for: fix) else { return }
        let scaled = CGPoint(x: point.x * scroll.zoomScale, y: point.y * scroll.zoomScale)
        let x = scaled.x - scroll.bounds.width / 2 + scroll.contentInset.left
        let y = scaled.y - scroll.bounds.height / 2 + scroll.contentInset.top
        scroll.setContentOffset(CGPoint(x: max(-scroll.contentInset.left, x), y: max(-scroll.contentInset.top, y)), animated: false)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        canvas.zoomScale = scrollView.zoomScale
        canvas.setNeedsDisplay()
        reportOutside()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        canvas.zoomScale = scrollView.zoomScale
        canvas.setNeedsDisplay()
        reportOutside()
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: canvas)
        let lonlat = canvas.coordinate(at: point)
        coordinator?.onDropPin(lonlat.0, lonlat.1)
    }

    private func centerPack() {
        let extraX = max(0, (scroll.bounds.width - canvas.frame.width) / 2)
        let extraY = max(0, (scroll.bounds.height - canvas.frame.height) / 2)
        scroll.contentInset = UIEdgeInsets(top: extraY, left: extraX, bottom: extraY, right: extraX)
        let x = max(0, (scroll.contentSize.width - scroll.bounds.width) / 2)
        let y = max(0, (scroll.contentSize.height - scroll.bounds.height) / 2)
        scroll.contentOffset = CGPoint(x: x - scroll.contentInset.left, y: y - scroll.contentInset.top)
    }

    private func reportOutside() {
        let centerInScroll = CGPoint(x: scroll.bounds.midX, y: scroll.bounds.midY)
        let inCanvas = canvas.convert(centerInScroll, from: scroll)
        let coord = canvas.coordinate(at: inCanvas)
        let west = pack.region.centerLongitude - pack.region.spanLongitude / 2
        let east = pack.region.centerLongitude + pack.region.spanLongitude / 2
        let south = pack.region.centerLatitude - pack.region.spanLatitude / 2
        let north = pack.region.centerLatitude + pack.region.spanLatitude / 2
        let padLon = pack.region.spanLongitude * 0.08
        let padLat = pack.region.spanLatitude * 0.08
        let outside = coord.1 < west - padLon || coord.1 > east + padLon
            || coord.0 < south - padLat || coord.0 > north + padLat
            || scroll.zoomScale < scroll.minimumZoomScale * 1.01
        if outside != lastOutside {
            lastOutside = outside
            coordinator?.onOutsidePack(outside)
        }
    }
}

final class TileCanvasLayer: UIView {
    var overlay: BundledTileOverlay?
    var x0 = 0
    var y0 = 0
    var zMax = 12
    var zMin = 10
    var cols = 1
    var rows = 1
    var zoomScale: CGFloat = 1
    var selfFix: LocationFix?
    var manualPin: LocationFix?
    var breadcrumbs: [BreadcrumbRecordDTO] = []
    var viewshed: [ViewshedRay] = []
    var slope: [SlopeSample] = []
    var showViewshed = false
    var showSlope = false
    private let cache = NSCache<NSString, UIImage>()

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setFillColor(UIColor(red: 7 / 255, green: 8 / 255, blue: 10 / 255, alpha: 1).cgColor)
        ctx.fill(rect)
        let z = currentZoom()
        let factor = pow(2.0, Double(zMax - z))
        let tileSize = CGFloat(256.0 * factor)
        let lowCols = max(1, Int(ceil(Double(cols) / factor)))
        let lowRows = max(1, Int(ceil(Double(rows) / factor)))
        let minX = max(0, Int(floor(rect.minX / tileSize)))
        let maxX = min(lowCols - 1, Int(floor((rect.maxX - 1) / tileSize)))
        let minY = max(0, Int(floor(rect.minY / tileSize)))
        let maxY = min(lowRows - 1, Int(floor((rect.maxY - 1) / tileSize)))
        let shift = zMax - z
        let worldX0 = x0 >> shift
        let worldY0 = y0 >> shift
        for ty in minY...max(minY, maxY) {
            for tx in minX...max(minX, maxX) {
                let tileX = worldX0 + tx
                let tileY = worldY0 + ty
                let dest = CGRect(x: CGFloat(tx) * tileSize, y: CGFloat(ty) * tileSize, width: tileSize, height: tileSize)
                if let image = image(z: z, x: tileX, y: tileY) {
                    image.draw(in: dest)
                }
            }
        }
        drawMark(selfFix, color: UIColor(red: 110 / 255, green: 200 / 255, blue: 1, alpha: 1), in: ctx)
        drawMark(manualPin, color: UIColor(red: 244 / 255, green: 247 / 255, blue: 250 / 255, alpha: 1), in: ctx)
        for crumb in breadcrumbs where crumb.hasCoordinate {
            let fix = LocationFix(latitude: crumb.latitude, longitude: crumb.longitude)
            drawMark(fix, color: UIColor(red: 197 / 255, green: 205 / 255, blue: 214 / 255, alpha: 0.9), in: ctx, radius: 4)
        }
        if showSlope {
            drawSlope(in: ctx)
        }
        if showViewshed, let selfFix {
            drawViewshed(from: selfFix, in: ctx)
        }
    }

    func coordinate(at point: CGPoint) -> (Double, Double) {
        let tileX = Double(x0) + Double(point.x / 256)
        let tileY = Double(y0) + Double(point.y / 256)
        let lat = WebMercator.latitude(tileY: tileY, zoom: zMax)
        let lon = WebMercator.longitude(tileX: tileX, zoom: zMax)
        return (lat, lon)
    }

    func point(for fix: LocationFix) -> CGPoint? {
        guard let lat = fix.latitude, let lon = fix.longitude else { return nil }
        let px = (WebMercator.tileX(longitude: lon, zoom: zMax) - Double(x0)) * 256
        let py = (WebMercator.tileY(latitude: lat, zoom: zMax) - Double(y0)) * 256
        return CGPoint(x: px, y: py)
    }

    private func drawSlope(in ctx: CGContext) {
        for sample in slope {
            let fix = LocationFix(latitude: sample.latitude, longitude: sample.longitude)
            guard let point = point(for: fix) else { continue }
            let t = min(1, sample.degrees / 45)
            ctx.setFillColor(UIColor(red: t, green: 0.2, blue: 0.15, alpha: 0.22).cgColor)
            ctx.fill(CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16))
        }
    }

    private func drawViewshed(from origin: LocationFix, in ctx: CGContext) {
        guard let start = point(for: origin), origin.hasCoordinate else { return }
        ctx.setFillColor(UIColor(red: 197 / 255, green: 205 / 255, blue: 214 / 255, alpha: 0.12).cgColor)
        ctx.beginPath()
        ctx.move(to: start)
        for ray in viewshed {
            let dest = offset(latitude: origin.latitude!, longitude: origin.longitude!, meters: ray.visibleMeters, bearing: ray.bearingDegrees)
            let fix = LocationFix(latitude: dest.0, longitude: dest.1)
            if let p = point(for: fix) {
                ctx.addLine(to: p)
            }
        }
        ctx.closePath()
        ctx.fillPath()
        ctx.setStrokeColor(UIColor(red: 197 / 255, green: 205 / 255, blue: 214 / 255, alpha: 0.45).cgColor)
        ctx.setLineWidth(1)
        ctx.beginPath()
        ctx.move(to: start)
        for ray in viewshed {
            let dest = offset(latitude: origin.latitude!, longitude: origin.longitude!, meters: ray.visibleMeters, bearing: ray.bearingDegrees)
            let fix = LocationFix(latitude: dest.0, longitude: dest.1)
            if let p = point(for: fix) {
                ctx.addLine(to: p)
            }
        }
        ctx.closePath()
        ctx.strokePath()
    }

    private func offset(latitude: Double, longitude: Double, meters: Double, bearing: Double) -> (Double, Double) {
        let r = 6_371_000.0
        let brng = bearing * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(meters / r) + cos(lat1) * sin(meters / r) * cos(brng))
        let lon2 = lon1 + atan2(
            sin(brng) * sin(meters / r) * cos(lat1),
            cos(meters / r) - sin(lat1) * sin(lat2)
        )
        return (lat2 * 180 / .pi, lon2 * 180 / .pi)
    }

    private func drawMark(_ fix: LocationFix?, color: UIColor, in ctx: CGContext, radius: CGFloat = 7) {
        guard let fix, let point = point(for: fix) else { return }
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }

    private func currentZoom() -> Int {
        let z = zMax + Int(floor(log2(Double(max(zoomScale, 0.01)))))
        return min(zMax, max(zMin, z))
    }

    private func image(z: Int, x: Int, y: Int) -> UIImage? {
        let key = "\(z)/\(x)/\(y)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = overlay?.tileData(z: z, x: x, y: y), let image = UIImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }
}
