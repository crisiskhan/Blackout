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

    @State private var segment: Segment = .guide
    @State private var pack: GuidePackSnapshot?

    public init(
        location: LocationService,
        battery: BatteryService,
        packURL: URL?,
        sosArmed: Bool
    ) {
        self.location = location
        self.battery = battery
        self.packURL = packURL
        self.sosArmed = sosArmed
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
                        ScreenHeader("Field guide", subtitle: "Ask first. Pack only. Not a website.")
                        GuideAskView(
                            pack: pack,
                            context: guideContext,
                            extremeSaver: battery.tightensToSOSNavRadar
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
                    .padding(.bottom, 120)
                }
            case .skills:
                FieldCopyView(title: "Primitive skills", paragraphs: FieldManual.skills)
            case .vision:
                if battery.tightensToSOSNavRadar {
                    VStack(alignment: .leading, spacing: 16) {
                        ScreenHeader("Field Vision", subtitle: "Paused in Extreme Saver / critical battery. SOS stays up.")
                        Text("Camera stills pause so the radio stays SOS, coarse nav, and radar HUD.")
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Silver.mid)
                        Spacer()
                    }
                    .padding(20)
                } else {
                    FieldVisionView()
                }
            }
        }
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
        .onAppear {
            pack = GuidePackLoader.load(rootURL: packURL)
        }
    }

    private var guideContext: GuideQueryContext {
        let hour = Calendar.current.component(.hour, from: Date())
        return GuideQueryContext(
            hour: hour,
            elevationMeters: location.navigationFix?.altitudeMeters,
            batteryLevel: battery.level,
            sosArmed: sosArmed,
            partySize: 1,
            extremeSaver: battery.tightensToSOSNavRadar
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
            .padding(.bottom, 120)
        }
    }
}

struct FieldVisionView: View {
    @State private var showCamera = false
    @State private var denied = false
    @State private var unavailable = false
    @State private var label: String = "Unknown"
    @State private var detail: String = "Capture a still. Unknown is a valid result."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader("Field Vision", subtitle: "On-device still. Unknown is valid.")
                HUDPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(label)
                            .font(BlackoutDS.titleFont())
                        Text(detail)
                            .foregroundStyle(BlackoutDS.Silver.mid)
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
                MetalButton("Capture still", height: BlackoutDS.Hit.lg) {
                    requestAndOpen()
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(
                onImage: { image in
                    let result = FieldVisionClassifier.classify(image)
                    label = result.label
                    detail = result.detail
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
            label = "Unknown"
            detail = "No camera hardware. Unknown is valid."
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
    struct Result {
        var label: String
        var detail: String
    }

    static func classify(_ image: UIImage) -> Result {
        guard let samples = average(image) else {
            return Result(label: "Unknown", detail: "The still could not be sampled.")
        }
        let (r, g, b, luma) = samples
        if luma > 0.82 && abs(r - g) < 0.08 {
            return Result(label: "Snow / high albedo", detail: "Bright, low-chroma field. Unknown remains valid if you disagree.")
        }
        if b > r + 0.12 && b > g + 0.05 && luma > 0.35 {
            return Result(label: "Sky / open", detail: "Blue-dominant field. Not a weather forecast.")
        }
        if b > 0.28 && b >= g && luma < 0.45 {
            return Result(label: "Water-like", detail: "Cool, darker field. Not a depth or potability reading.")
        }
        if g > r + 0.05 && g > b {
            return Result(label: "Vegetation", detail: "Green-dominant field. No use statement is attached.")
        }
        if luma < 0.28 && abs(r - g) < 0.1 {
            return Result(label: "Rock / mineral", detail: "Low, even chroma. Texture is not identified.")
        }
        return Result(label: "Unknown", detail: "No local class won. Unknown is a valid field result.")
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
