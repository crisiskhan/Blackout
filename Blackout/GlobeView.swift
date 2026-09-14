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
        let controller = config.userContentController
        controller.add(context.coordinator, name: "khan")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = true
        view.backgroundColor = .black
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
            if url.isFileURL || url.scheme == "about" || url.scheme == "blob" {
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
        if let youHeading {
            puck["heading"] = youHeading
        }
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
            "pitch": godsEye ? PackCamera.holdPitch(godsEye: true) - 90 : -90,
            "heading": godsEye ? PackCamera.godsEyeHeading : 0,
            "height": height,
            "fly": PackCamera.godsEyeFlySeconds,
            "travel": travelMode == .walk ? "walk" : "drive"
        ]
        if let destination { obj["dest"] = [destination.lat, destination.lon] }
        if let held { obj["held"] = [held.lat, held.lon] }
        if let followID { obj["followId"] = followID }
        if let aerialURL { obj["aerialUrl"] = aerialURL.absoluteString }
        if let demURL { obj["demUrl"] = demURL.absoluteString }
        if let waterURL { obj["waterUrl"] = waterURL.absoluteString }
        if let contoursURL { obj["contoursUrl"] = contoursURL.absoluteString }
        return obj
    }
}
