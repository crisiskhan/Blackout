import AVFoundation
import BlackoutBattery
import BlackoutCore
import BlackoutLocation
import DesignSystem
import SwiftUI
import UIKit

public struct FieldRootView: View {
    public enum Segment: String, CaseIterable, Identifiable {
        case guide = "Guide"
        case skills = "Skills"
        case vision = "Vision"
        public var id: String { rawValue }
    }

    @Bindable var location: LocationService
    @Bindable var battery: BatteryService
    var packURL: URL?
    var sosArmed: Bool
    var packReady: PackReadySnapshot
    var partySize: Int
    var openExpeditionID: String?
    var inboundArticleID: String?
    var inboundMissing: Bool
    var nearbyPeerCount: Int
    var onSendArticle: (String) -> Void
    var onStartMode: (FieldJobMode) -> Void
    var onRelayPack: (String) -> Void
    var onOpenMapJob: (GuideMapJob) -> Void

    @State private var segment: Segment = .guide
    @State private var pack: GuidePackSnapshot?
    @State private var packTooNew = false

    public init(
        location: LocationService,
        battery: BatteryService,
        packURL: URL?,
        sosArmed: Bool,
        packReady: PackReadySnapshot = .empty,
        partySize: Int = 1,
        openExpeditionID: String? = nil,
        inboundArticleID: String? = nil,
        inboundMissing: Bool = false,
        nearbyPeerCount: Int = 0,
        onSendArticle: @escaping (String) -> Void = { _ in },
        onStartMode: @escaping (FieldJobMode) -> Void = { _ in },
        onRelayPack: @escaping (String) -> Void = { _ in },
        onOpenMapJob: @escaping (GuideMapJob) -> Void = { _ in }
    ) {
        self.location = location
        self.battery = battery
        self.packURL = packURL
        self.sosArmed = sosArmed
        self.packReady = packReady
        self.partySize = partySize
        self.openExpeditionID = openExpeditionID
        self.inboundArticleID = inboundArticleID
        self.inboundMissing = inboundMissing
        self.nearbyPeerCount = nearbyPeerCount
        self.onSendArticle = onSendArticle
        self.onStartMode = onStartMode
        self.onRelayPack = onRelayPack
        self.onOpenMapJob = onOpenMapJob
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Field", selection: $segment) {
                ForEach(Segment.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(16)
            switch segment {
            case .guide:
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ScreenHeader(
                            "Field guide",
                            subtitle: packReady.readyIDs.isEmpty
                                ? "Ask first. Pack only. Not a website."
                                : "Ask first. Pack only. \(packReady.readyIDs.count) field packs Ready."
                        )
                        if inboundMissing, let inboundArticleID {
                            HUDPanel {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(GuideCardWire.missingCopy)
                                        .font(BlackoutDS.titleFont())
                                    Text(inboundArticleID)
                                        .font(BlackoutDS.captionFont())
                                        .foregroundStyle(BlackoutDS.Silver.steel)
                                    if nearbyPeerCount >= 1 {
                                        MetalButton("Send pack", height: BlackoutDS.Hit.sm) {
                                            onRelayPack("el-paso")
                                        }
                                    }
                                }
                            }
                        }
                        GuideAskView(
                            pack: pack,
                            packTooNew: packTooNew,
                            context: guideContext,
                            extremeSaver: battery.isExtremeSaver,
                            focusArticleID: inboundArticleID,
                            onSendArticle: onSendArticle,
                            onStartMode: onStartMode,
                            onOpenMapJob: onOpenMapJob,
                            openExpeditionID: openExpeditionID
                        )
                        Text("Situation cards")
                            .font(BlackoutDS.titleFont())
                            .foregroundStyle(BlackoutDS.Silver.bright)
                        ForEach(FieldManual.guide) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title)
                                    .font(BlackoutDS.titleFont())
                                    .foregroundStyle(BlackoutDS.Silver.bright)
                                Text(section.body)
                                    .font(BlackoutDS.bodyFont())
                                    .foregroundStyle(BlackoutDS.Silver.mid)
                                    .lineSpacing(7)
                            }
                        }
                    }
                    .padding(20)
                    .padding(
                        .bottom,
                        CGFloat(MapChromeLock.fieldContentBottomClearance(hasTabBar: true))
                    )
                }
            case .skills:
                GuideSkillsView(pack: pack, onOpenMapJob: onOpenMapJob)
            case .vision:
                if battery.pausesCameraAndPTT {
                    VStack(alignment: .leading, spacing: 16) {
                        ScreenHeader(
                            "Field Vision",
                            subtitle: battery.isCritical
                                ? "Paused at ~2% battery. SOS stays up. Radar and coarse nav are off."
                                : "Paused in Extreme Saver. SOS, coarse nav, and radar stay up."
                        )
                        Text(
                            battery.isCritical
                                ? "Last-2% is SOS-only. The FAB stays. Camera stills wait until you charge."
                                : "Camera stills pause so Extreme Saver can keep SOS, coarse Navigate, and the radar HUD."
                        )
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Silver.mid)
                        Spacer()
                    }
                    .padding(20)
                } else {
                    FieldVisionView(biome: guideContext.biome, pack: pack)
                }
            }
        }
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
        .onAppear {
            packTooNew = GuidePackLoader.status(rootURL: packURL) == .tooNew
            pack = GuidePackLoader.load(rootURL: packURL)
        }
    }

    private var guideContext: GuideQueryContext {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let month = Calendar.current.component(.month, from: now)
        let fix = location.navigationFix
        return GuideQueryContext(
            hour: hour,
            elevationMeters: fix?.altitudeMeters,
            batteryLevel: battery.level,
            sosArmed: sosArmed,
            partySize: partySize,
            extremeSaver: battery.isExtremeSaver,
            month: month,
            latitude: fix?.hasCoordinate == true ? fix?.latitude : nil,
            longitude: fix?.hasCoordinate == true ? fix?.longitude : nil
        )
    }
}

struct FieldCopyView: View {
    var title: String
    var paragraphs: [FieldManual.Section]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title, subtitle: "Bundled on-device. Not a website.")
                ForEach(paragraphs) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(BlackoutDS.titleFont())
                            .foregroundStyle(BlackoutDS.Silver.bright)
                        Text(section.body)
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Silver.mid)
                            .lineSpacing(7)
                    }
                }
            }
            .padding(20)
            .padding(
                .bottom,
                CGFloat(MapChromeLock.fieldContentBottomClearance(hasTabBar: true))
            )
        }
    }
}

struct FieldVisionView: View {
    var biome: GuideBiome
    var pack: GuidePackSnapshot?

    @State private var showCamera = false
    @State private var denied = false
    @State private var unavailable = false
    @State private var reading: GuideVisionReading = GuideVisionID.unknownReading(biome: .unknown)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader("Field Vision", subtitle: "Two percents. Lookalike. Unknown is valid. No eat verdict.")
                HUDPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(reading.label)
                            .font(BlackoutDS.titleFont())
                        Text("ID \(reading.idPercent)%")
                            .font(BlackoutDS.titleFont())
                        Text("Lookalike \(reading.lookalikePercent)% · \(reading.lookalikeName)")
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Silver.mid)
                        if reading.isUnknown {
                            Text("Unknown is a valid field result.")
                                .font(BlackoutDS.captionFont())
                                .foregroundStyle(BlackoutDS.Silver.steel)
                        }
                        if biome == .unknown {
                            Text("Biome unknown. Four-state plant/tree ID needs FL/TX/NY/NM.")
                                .font(BlackoutDS.captionFont())
                                .foregroundStyle(BlackoutDS.Silver.dim)
                        }
                    }
                }
                if denied {
                    PermissionDenied(
                        kind: .camera,
                        reason: "Camera denied. Guide and Skills stay available. Vision will not guess from the network."
                    )
                }
                if unavailable {
                    Text("No camera on this device. Vision stays Unknown.")
                        .font(BlackoutDS.bodyFont())
                        .foregroundStyle(BlackoutDS.Silver.dim)
                }
                Text("No eat / don't-eat verdict. Specimen stays Unknown unless the still locks.")
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
                MetalButton("Capture still", height: BlackoutDS.Hit.lg) {
                    requestAndOpen()
                }
            }
            .padding(20)
            .padding(
                .bottom,
                CGFloat(MapChromeLock.fieldContentBottomClearance(hasTabBar: true))
            )
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(
                onImage: { image in
                    reading = FieldVisionClassifier.classify(image, biome: biome, pack: pack)
                    showCamera = false
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
    }

    private func requestAndOpen() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            unavailable = true
            reading = GuideVisionID.unknownReading(biome: biome)
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            denied = false
            showCamera = true
        case .denied, .restricted:
            denied = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        denied = false
                        showCamera = true
                    } else {
                        denied = true
                    }
                }
            }
        @unknown default:
            denied = true
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void
        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

enum FieldVisionClassifier {
    static func classify(_ image: UIImage, biome: GuideBiome, pack: GuidePackSnapshot?) -> GuideVisionReading {
        _ = average(image)
        if let prefix = GuideVisionID.deckPrefix(for: biome),
           let article = pack?.articles.first(where: { $0.id == "vision-\(prefix)-unknown" }),
           let parsed = GuideVisionID.parse(title: article.title, body: article.body) {
            return parsed
        }
        return GuideVisionID.unknownReading(biome: biome)
    }

    private static func average(_ image: UIImage) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
        guard let cg = image.cgImage else { return nil }
        let width = 16
        let height = 16
        let bytes = width * height * 4
        var data = [UInt8](repeating: 0, count: bytes)
        guard let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        let count = CGFloat(width * height)
        for i in stride(from: 0, to: bytes, by: 4) {
            r += CGFloat(data[i]) / 255
            g += CGFloat(data[i + 1]) / 255
            b += CGFloat(data[i + 2]) / 255
        }
        r /= count
        g /= count
        b /= count
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return (r, g, b, luma)
    }
}
