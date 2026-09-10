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
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onCode = onCode
        vc.onCancel = onCancel
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {
        uiViewController.onCode = onCode
        uiViewController.onCancel = onCancel
    }

    final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        var onCancel: (() -> Void)?
        private let session = AVCaptureSession()
        private var started = false
        private var finished = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            view.layer.insertSublayer(preview, at: 0)
            installChrome()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            armCamera()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            session.stopRunning()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            view.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer }.forEach { $0.frame = view.bounds }
        }

        private func armCamera() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                startSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        if granted { self.startSession() }
                    }
                }
            case .denied, .restricted:
                break
            @unknown default:
                break
            }
        }

        private func startSession() {
            guard !started else { return }
            started = true
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
            }
            DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
        }

        private func installChrome() {
            let close = UIButton(type: .system)
            close.setTitle("CLOSE", for: .normal)
            close.titleLabel?.font = .systemFont(ofSize: 13, weight: .heavy)
            close.setTitleColor(.white, for: .normal)
            close.addTarget(self, action: #selector(cancel), for: .touchUpInside)
            close.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(close)
            NSLayoutConstraint.activate([
                close.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                close.heightAnchor.constraint(equalToConstant: 44),
            ])
        }

        @objc private func cancel() {
            guard !finished else { return }
            finished = true
            session.stopRunning()
            onCancel?()
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !finished,
                  let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let raw = obj.stringValue else { return }
            finished = true
            session.stopRunning()
            onCode?(PartyQR.parse(raw))
        }
    }
}
#endif
