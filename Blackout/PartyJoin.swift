import SwiftUI
#if canImport(CoreImage)
import CoreImage
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

enum PartyQR {
    static func parse(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("blackout:") { return String(t.dropFirst("blackout:".count)) }
        return t
    }

    #if canImport(CoreImage)
    static func cgImage(code: String) -> CGImage? {
        let payload = Data("blackout:\(code)".utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(payload, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = filter.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
    #endif
}

struct PartyQRImage: View {
    let code: String
    var body: some View {
        #if canImport(CoreImage) && canImport(UIKit)
        if let img = PartyQR.cgImage(code: code) {
            Image(uiImage: UIImage(cgImage: img))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)
                .padding(6)
                .background(Color.white)
        }
        #endif
    }
}

#if canImport(AVFoundation) && canImport(UIKit)
struct PartyQRScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onCode = onCode
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {
        uiViewController.onCode = onCode
    }

    final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var started = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.frame = view.bounds
            preview.videoGravity = .resizeAspectFill
            view.layer.addSublayer(preview)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if !started {
                started = true
                DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            view.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer }.forEach { $0.frame = view.bounds }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let raw = obj.stringValue else { return }
            session.stopRunning()
            onCode?(PartyQR.parse(raw))
        }
    }
}
#endif
