import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Vision)
import Vision
#endif

/// Do not import the VisionCoreML package here. Apple Vision plus the
/// matcher enum of the same name makes the pack observation type
/// unnameable in this file. FIELD maps these hits onto the matcher.
struct SystemVisionHit: Equatable, Sendable {
    var identifier: String
    var confidence: Double
}

enum SystemVision {
    static func observations(from image: CGImage) -> [SystemVisionHit]? {
        #if canImport(Vision)
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let results = request.results ?? []
        return results.prefix(8).map {
            SystemVisionHit(identifier: $0.identifier, confidence: Double($0.confidence))
        }
        #else
        return nil
        #endif
    }
}

#if canImport(AVFoundation) && canImport(UIKit)
struct VisionStill: UIViewControllerRepresentable {
    var onImage: (CGImage) -> Void
    var onFail: () -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> StillVC {
        let vc = StillVC()
        vc.onImage = onImage
        vc.onFail = onFail
        vc.onCancel = onCancel
        return vc
    }

    func updateUIViewController(_ uiViewController: StillVC, context: Context) {
        uiViewController.onImage = onImage
        uiViewController.onFail = onFail
        uiViewController.onCancel = onCancel
    }

    final class StillVC: UIViewController, AVCapturePhotoCaptureDelegate {
        var onImage: ((CGImage) -> Void)?
        var onFail: (() -> Void)?
        var onCancel: (() -> Void)?
        private let session = AVCaptureSession()
        private let output = AVCapturePhotoOutput()
        private var started = false
        private var finished = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.name = "preview"
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
                        if granted {
                            self.startSession()
                        } else {
                            self.failClosed()
                        }
                    }
                }
            case .denied, .restricted:
                failClosed()
            @unknown default:
                failClosed()
            }
        }

        private func startSession() {
            guard !started else { return }
            started = true
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video)
            guard let device,
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                failClosed()
                return
            }
            session.addInput(input)
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            if let connection = output.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
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

            let capture = UIButton(type: .system)
            capture.setTitle("CAPTURE", for: .normal)
            capture.titleLabel?.font = .systemFont(ofSize: 13, weight: .heavy)
            capture.setTitleColor(.white, for: .normal)
            capture.backgroundColor = UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
            capture.layer.cornerRadius = 10
            capture.addTarget(self, action: #selector(shoot), for: .touchUpInside)
            capture.translatesAutoresizingMaskIntoConstraints = false

            view.addSubview(close)
            view.addSubview(capture)
            NSLayoutConstraint.activate([
                close.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                close.heightAnchor.constraint(equalToConstant: 44),
                capture.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                capture.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                capture.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
                capture.heightAnchor.constraint(equalToConstant: 44),
            ])
        }

        @objc private func cancel() {
            finish {
                self.session.stopRunning()
                self.onCancel?()
            }
        }

        @objc private func shoot() {
            guard session.isRunning else {
                failClosed()
                return
            }
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }

        func photoOutput(
            _ output: AVCapturePhotoOutput,
            didFinishProcessingPhoto photo: AVCapturePhoto,
            error: Error?
        ) {
            DispatchQueue.main.async {
                self.session.stopRunning()
                guard error == nil,
                      let data = photo.fileDataRepresentation(),
                      let image = UIImage(data: data)?.cgImage else {
                    self.failClosed()
                    return
                }
                self.finish { self.onImage?(image) }
            }
        }

        private func failClosed() {
            finish {
                self.session.stopRunning()
                self.onFail?()
            }
        }

        private func finish(_ work: () -> Void) {
            guard !finished else { return }
            finished = true
            work()
        }
    }
}
#endif
