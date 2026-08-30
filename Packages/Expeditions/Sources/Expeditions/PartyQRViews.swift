import AVFoundation
import BlackoutCore
import CoreImage.CIFilterBuiltins
import DesignSystem
import SwiftUI
import UIKit

struct PartyQRSheet: View {
    var code: String

    var body: some View {
        VStack(spacing: 16) {
            Text(code)
                .font(.system(size: 36, weight: .bold, design: .default))
                .foregroundStyle(BlackoutDS.Silver.bright)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let image = PartyQRImage.make(code) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 240)
                    .padding(16)
                    .background(BlackoutDS.Silver.metal)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Text("Local only. No account.")
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
        .navigationTitle(PartyQR.showTitle)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

enum PartyQRImage {
    static func make(_ code: String) -> UIImage? {
        let payload = PartyQR.payload(code: code)
        guard !payload.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct PartyQRScanSheet: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var denied = false

    var body: some View {
        ZStack {
            if denied {
                VStack(alignment: .leading, spacing: 12) {
                    Text(PartyQR.cameraDenied)
                        .font(BlackoutDS.bodyFont())
                        .foregroundStyle(BlackoutDS.Semantic.warn)
                    Spacer()
                }
                .padding(24)
            } else {
                QRScannerRepresentable { raw in
                    if let code = PartyQR.parse(raw) {
                        onCode(code)
                        dismiss()
                    }
                }
                .ignoresSafeArea()
            }
        }
        .background(BlackoutDS.Surface.void.ignoresSafeArea())
        .navigationTitle(PartyQR.scanTitle)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .denied || status == .restricted {
                denied = true
            } else if status == .notDetermined {
                denied = !(await AVCaptureDevice.requestAccess(for: .video))
            }
        }
    }
}

private struct QRScannerRepresentable: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {
        uiViewController.onCode = onCode
    }
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        if output.availableMetadataObjectTypes.contains(.qr) {
            output.metadataObjectTypes = [.qr]
        }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        session.stopRunning()
        onCode?(value)
    }
}
