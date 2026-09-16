import MapLibreMap
import Router
import SwiftUI
import UIKit
import WebKit

/// Cesium globe on glass. file:// only. MapLibre stays linked and off-canvas.
struct GlobeView: UIViewRepresentable {
    var packID: String
    var centerLat: Double
    var centerLon: Double
    var puckLat: Double
    var puckLon: Double
    var showYou: Bool
    var packSouth: Double
    var packWest: Double
    var packNorth: Double
    var packEast: Double
    var route: [(lat: Double, lon: Double)]
    var destination: (lat: Double, lon: Double)?
    var held: (lat: Double, lon: Double)?
    var fitToken: Int
    var interactive: Bool
    var onMapTap: ((Double, Double) -> Void)?
    var onMapHold: ((Double, Double, [String: String], Double) -> Void)?
    var onPersonHold: ((String, Double, Double) -> Void)?
    var onPersonTap: ((String, Double, Double) -> Void)?
    var onPersonDoubleTap: ((String, Double, Double) -> Void)?
    var onEmptyDoubleTap: ((Double, Double) -> Void)?
    var pips: [PartyBody]
    var youHeading: Double?
    var youEmblem: String
    var onPulse: (() -> Void)?
    var lockOn: Bool
    var godsEye: Bool
    var travelMode: TravelMode
    var sun: Bool
    var night: Bool
    var eyeLayers: [EyeDesk.Layer]
    var eyePalette: EyeDesk.Palette
    var eyeGround: EyeDesk.Ground
    var followID: String?
    var trails: [[(lat: Double, lon: Double)]]
    var rings: [EyeDesk.Ring]
    var frameExtra: [(lat: Double, lon: Double)]
    var aerialURL: URL?
    var demURL: URL?
    var waterURL: URL?
    var contoursURL: URL?
    var shadeURL: URL?
    var osmURL: URL?
    var khanURL: URL?
    var khan3dURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = false
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        config.setURLSchemeHandler(PackFileSchemeHandler(), forURLScheme: "packfile")
        let controller = config.userContentController
        controller.add(context.coordinator, name: "khan")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = true
        view.backgroundColor = UIColor(red: 74.0 / 255.0, green: 70.0 / 255.0, blue: 60.0 / 255.0, alpha: 1)
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isUserInteractionEnabled = interactive
        let credit = UILabel()
        credit.tag = 71
        credit.font = .systemFont(ofSize: 9, weight: .bold)
        credit.textColor = UIColor(red: 0.77, green: 0.80, blue: 0.84, alpha: 0.82)
        credit.text = OSMCredit.line
        credit.isHidden = !godsEye
        credit.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(credit)
        NSLayoutConstraint.activate([
            credit.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            credit.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
        context.coordinator.owner = self
        context.coordinator.webView = view
        installNetworkBlock(on: view)
        loadDesk(on: view)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.isUserInteractionEnabled = interactive
        uiView.accessibilityElementsHidden = !interactive
        if let credit = uiView.viewWithTag(71) as? UILabel {
            credit.text = OSMCredit.line
            credit.isHidden = !godsEye
        }
        context.coordinator.owner = self
        context.coordinator.pushSpec()
    }

    private func loadDesk(on view: WKWebView) {
        let root = AppRuntime.resourceRoot() ?? Bundle.main.resourceURL
        guard let root else { return }
        let page = root.appendingPathComponent("Globe/index.html")
        view.loadFileURL(page, allowingReadAccessTo: root)
    }

    private func installNetworkBlock(on view: WKWebView) {
        let json = """
        [{"trigger":{"url-filter":"https?://.*"},"action":{"type":"block"}}]
        """
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "blackout.globe.airplane",
            encodedContentRuleList: json
        ) { list, _ in
            guard let list else { return }
            view.configuration.userContentController.add(list)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var owner: GlobeView?
        weak var webView: WKWebView?
        var ready = false
        var lastJSON = ""

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.isFileURL || url.scheme == "about" || url.scheme == "blob" || url.scheme == "packfile" {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            pushSpec(force: true)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "khan" else { return }
            guard let body = message.body as? [String: Any] else { return }
            guard let type = GlobeMessage(rawValue: body["type"] as? String ?? "") else { return }
            let lat = body["lat"] as? Double
            let lon = body["lon"] as? Double
            let id = body["id"] as? String
            switch type {
            case .tap:
                if let lat, let lon { owner?.onMapTap?(lat, lon) }
            case .hold:
                if let lat, let lon {
                    owner?.onMapHold?(lat, lon, [:], PackCamera.openZoom)
                }
            case .personTap:
                if let id, let lat, let lon { owner?.onPersonTap?(id, lat, lon) }
            case .personHold:
                if let id, let lat, let lon { owner?.onPersonHold?(id, lat, lon) }
            case .personDoubleTap:
                if let id, let lat, let lon { owner?.onPersonDoubleTap?(id, lat, lon) }
            case .emptyDoubleTap:
                if let lat, let lon { owner?.onEmptyDoubleTap?(lat, lon) }
            case .pulse:
                owner?.onPulse?()
            }
        }

        func pushSpec(force: Bool = false) {
            guard ready, let owner, let webView else { return }
            guard let data = try? JSONSerialization.data(withJSONObject: owner.specObject(), options: []),
                  let json = String(data: data, encoding: .utf8)
            else { return }
            if json == lastJSON && !force { return }
            lastJSON = json
            webView.evaluateJavaScript("window.KHAN && window.KHAN.apply(\(json))") { _, _ in }
        }
    }
}

enum GlobeMessage: String {
    case tap
    case hold
    case personTap
    case personHold
    case personDoubleTap
    case emptyDoubleTap
    case pulse
}

private extension GlobeView {
    func specObject() -> [String: Any] {
        let height = PackCamera.openHeightMeters(lat: puckLat)
        let range: Double = {
            let box = PackCamera.bounds(
                south: packSouth,
                west: packWest,
                north: packNorth,
                east: packEast
            )
            let radius = PackCamera.packRadiusMeters(
                south: box.south,
                west: box.west,
                north: box.north,
                east: box.east
            )
            return PackCamera.godsEyeCameraDistance(
                gev: PackCamera.godsEyeDistance(radiusMeters: radius),
                hudFit: EyeDesk.soloMeters
            )
        }()
        let lamp: String
        if sun { lamp = "sun" }
        else if night { lamp = "night" }
        else { lamp = "off" }
        var puck: [String: Any] = [
            "lat": puckLat,
            "lon": puckLon,
            "show": showYou
        ]
        puck["emblem"] = youEmblem
        var obj: [String: Any] = [
            "packId": packID,
            "puck": puck,
            "home": ["lat": centerLat, "lon": centerLon],
            "bbox": [
                "south": packSouth,
                "west": packWest,
                "north": packNorth,
                "east": packEast
            ],
            "route": route.map { [$0.lat, $0.lon] },
            "pips": pips.map { pip -> [String: Any] in
                var row: [String: Any] = [
                    "id": pip.id,
                    "lat": pip.lat,
                    "lon": pip.lon,
                    "condition": pip.condition,
                    "ageTitle": pip.ageTitle,
                    "ageLabel": pip.ageLabel,
                    "lead": pip.lead,
                    "kid": pip.kid,
                    "ghost": pip.ghost,
                    "overdue": pip.overdue,
                    "markKind": pip.markKind
                ]
                if let heading = pip.headingDeg { row["heading"] = heading }
                if let meters = pip.rangeMeters { row["rangeMeters"] = meters }
                return row
            },
            "trails": trails.map { $0.map { [$0.lat, $0.lon] } },
            "rings": rings.map { [
                "lat": $0.lat,
                "lon": $0.lon,
                "meters": $0.meters,
                "overdue": $0.overdue
            ] as [String: Any] },
            "frameExtra": frameExtra.map { [$0.lat, $0.lon] },
            "layers": eyeLayers.map(\.rawValue),
            "palette": eyePalette.rawValue,
            "ground": eyeGround.rawValue,
            "lamp": lamp,
            "godsEye": godsEye,
            "lockOn": lockOn,
            "fitToken": fitToken,
            "range": range,
            "pitch": godsEye ? -90 : -55,
            "heading": godsEye ? PackCamera.godsEyeHeading : 0,
            "height": height,
            "fly": PackCamera.godsEyeFlySeconds,
            "travel": travelMode == .walk ? "walk" : "drive"
        ]
        if let destination { obj["dest"] = [destination.lat, destination.lon] }
        if let held { obj["held"] = [held.lat, held.lon] }
        if let followID { obj["followId"] = followID }
        if let path = packWebPath(aerialURL) { obj["aerialUrl"] = path }
        if let path = packWebPath(demURL) { obj["demUrl"] = path }
        if let path = packWebPath(waterURL) { obj["waterUrl"] = path }
        if let path = packWebPath(contoursURL) { obj["contoursUrl"] = path }
        // Pack ground is hillshade.png + osm.pmtiles + khan.pmtiles. Metro NAIP is extra.
        obj["shadeUrl"] = packWebPath(shadeURL) ?? "../Packs/\(packID)/hillshade.png"
        obj["osmUrl"] = packWebPath(osmURL) ?? "../Packs/\(packID)/osm.pmtiles"
        obj["khanUrl"] = packWebPath(khanURL) ?? "../Packs/\(packID)/khan.pmtiles"
        obj["khan3dUrl"] = packWebPath(khan3dURL) ?? "../Packs/\(packID)/desk3d.geojson"
        return obj
    }

    /// Globe/index.html stays file://. Pack archives are packfile://blackout/<pack>/<file>
    /// so the desk can read offset/length slices instead of the whole pmtiles into JS.
    func packWebPath(_ url: URL?) -> String? {
        guard let url else { return nil }
        let marker = "/Packs/\(packID)/"
        let path = url.path
        guard let range = path.range(of: marker) else { return url.absoluteString }
        return "packfile://blackout/\(packID)/\(path[range.upperBound...])"
    }
}

/// Serves bundled Packs/ bytes to the Cesium desk. PMTiles must pass offset and length.
final class PackFileSchemeHandler: NSObject, WKURLSchemeHandler {
    private let maxSlice = 8_000_000
    private static var archives: [String: Data] = [:]
    private static let archivesLock = NSLock()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        do {
            let data = try packBytes(for: urlSchemeTask.request)
            guard let url = urlSchemeTask.request.url else { throw URLError(.badURL) }
            let mime: String
            switch url.pathExtension {
            case "png":
                mime = "image/png"
            case "json":
                mime = "application/json"
            case "geojson":
                mime = "application/geo+json"
            default:
                mime = "application/octet-stream"
            }
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": mime,
                    "Content-Length": "\(data.count)",
                    "Cache-Control": "max-age=86400",
                    "Access-Control-Allow-Origin": "*"
                ]
            ) else { throw URLError(.cannotParseResponse) }
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func packBytes(for request: URLRequest) throws -> Data {
        guard let url = request.url else { throw URLError(.badURL) }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 2 else { throw URLError(.fileDoesNotExist) }
        let packId = parts[0]
        let name = parts[1]
        guard packId.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil,
              name.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
        else { throw URLError(.fileDoesNotExist) }
        let root = AppRuntime.resourceRoot() ?? Bundle.main.resourceURL
        guard let root else { throw URLError(.fileDoesNotExist) }
        let file = root.appendingPathComponent("Packs/\(packId)/\(name)")
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw URLError(.fileDoesNotExist)
        }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let offset = comps?.queryItems?.first(where: { $0.name == "offset" }).flatMap { Int($0.value ?? "") }
        let length = comps?.queryItems?.first(where: { $0.name == "length" }).flatMap { Int($0.value ?? "") }
        if file.pathExtension == "pmtiles" {
            guard let offset, let length, offset >= 0, length > 0 else {
                throw URLError(.dataNotAllowed)
            }
            return try readSlice(file: file, offset: offset, length: min(length, maxSlice))
        }
        if let offset, let length, offset >= 0, length > 0 {
            return try readSlice(file: file, offset: offset, length: min(length, maxSlice))
        }
        return try Data(contentsOf: file)
    }

    private func readSlice(file: URL, offset: Int, length: Int) throws -> Data {
        let data = try cachedFile(file)
        guard offset >= 0, offset < data.count else { return Data() }
        let end = min(offset + min(length, maxSlice), data.count)
        return data.subdata(in: offset..<end)
    }

    private func cachedFile(_ file: URL) throws -> Data {
        let key = file.path
        Self.archivesLock.lock()
        if let hit = Self.archives[key] {
            Self.archivesLock.unlock()
            return hit
        }
        Self.archivesLock.unlock()
        let data = try Data(contentsOf: file, options: [.mappedIfSafe])
        Self.archivesLock.lock()
        Self.archives[key] = data
        Self.archivesLock.unlock()
        return data
    }
}
