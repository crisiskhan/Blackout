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
    /// Full frame plus the subject. Desert sky and the tree behind a
    /// cactus must not be the only words the matcher sees.
    static func observations(from image: CGImage) -> [SystemVisionHit]? {
        guard var hits = classify(image) else { return nil }
        if let crop = subjectCrop(from: image), let extra = classify(crop) {
            hits.append(contentsOf: extra)
        }
        if let mid = centerCrop(image), let extra = classify(mid) {
            hits.append(contentsOf: extra)
        }
        return merge(hits)
    }

    private static func classify(_ image: CGImage) -> [SystemVisionHit]? {
        #if canImport(Vision)
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let results = request.results ?? []
        return results
            .filter { $0.confidence >= 0.2 }
            .map {
                SystemVisionHit(identifier: $0.identifier, confidence: Double($0.confidence))
            }
        #else
        return nil
        #endif
    }

    private static func subjectCrop(from image: CGImage) -> CGImage? {
        #if canImport(Vision)
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let obs = (request.results as? [VNSaliencyImageObservation])?.first,
              let objects = obs.salientObjects,
              let box = objects.max(by: { $0.confidence < $1.confidence })
        else { return nil }
        return crop(image, normalized: box.boundingBox, pad: 0.12)
        #else
        return nil
        #endif
    }

    private static func centerCrop(_ image: CGImage, fraction: CGFloat = 0.55) -> CGImage? {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let cw = max(32, w * fraction)
        let ch = max(32, h * fraction)
        let rect = CGRect(x: (w - cw) / 2, y: (h - ch) / 2, width: cw, height: ch)
        return image.cropping(to: rect.integral)
    }

    /// Vision boxes are origin-bottom-left. CGImage crop is origin-top-left.
    private static func crop(_ image: CGImage, normalized box: CGRect, pad: CGFloat) -> CGImage? {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        var r = CGRect(
            x: box.minX * w,
            y: (1 - box.maxY) * h,
            width: box.width * w,
            height: box.height * h
        )
        r = r.insetBy(dx: -r.width * pad, dy: -r.height * pad)
        r = r.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard r.width >= 32, r.height >= 32 else { return nil }
        return image.cropping(to: r.integral)
    }

    private static func merge(_ hits: [SystemVisionHit]) -> [SystemVisionHit] {
        var best: [String: SystemVisionHit] = [:]
        for hit in hits {
            let key = hit.identifier.lowercased()
            if let current = best[key] {
                if hit.confidence > current.confidence {
                    best[key] = hit
                }
            } else {
                best[key] = hit
            }
        }
        return Array(best.values)
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
        private let sessionQueue = DispatchQueue(label: "blackout.vision.session")
        private var captureButton: UIButton?
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
            haltSession()
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
                  let input = try? AVCaptureDeviceInput(device: device) else {
                failClosed()
                return
            }
            sessionQueue.async {
                guard !self.finished else { return }
                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }
                guard self.session.canAddInput(input) else {
                    DispatchQueue.main.async { self.failClosed() }
                    return
                }
                self.session.addInput(input)
                guard self.session.canAddOutput(self.output) else {
                    DispatchQueue.main.async { self.failClosed() }
                    return
                }
                self.session.addOutput(self.output)
                if let connection = self.output.connection(with: .video), connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            sessionQueue.async {
                guard !self.finished else { return }
                self.session.startRunning()
                let running = self.session.isRunning
                DispatchQueue.main.async {
                    self.captureButton?.isEnabled = running
                    if !running {
                        self.failClosed()
                    }
                }
            }
        }

        private func haltSession() {
            sessionQueue.async { self.session.stopRunning() }
        }

        private func installChrome() {
            let silver = UIColor(white: 0.86, alpha: 1)
            let close = UIButton(type: .system)
            close.setTitle("CLOSE", for: .normal)
            close.titleLabel?.font = .systemFont(ofSize: 13, weight: .heavy)
            close.setTitleColor(silver, for: .normal)
            close.addTarget(self, action: #selector(cancel), for: .touchUpInside)
            close.translatesAutoresizingMaskIntoConstraints = false

            let capture = UIButton(type: .system)
            capture.setTitle("CAPTURE", for: .normal)
            capture.titleLabel?.font = .systemFont(ofSize: 13, weight: .heavy)
            capture.setTitleColor(silver, for: .normal)
            capture.backgroundColor = UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
            capture.layer.cornerRadius = 10
            capture.layer.borderWidth = 1
            capture.layer.borderColor = silver.withAlphaComponent(0.45).cgColor
            capture.addTarget(self, action: #selector(shoot), for: .touchUpInside)
            capture.translatesAutoresizingMaskIntoConstraints = false
            capture.isEnabled = false
            captureButton = capture

            view.addSubview(close)
            view.addSubview(capture)
            NSLayoutConstraint.activate([
                close.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                close.heightAnchor.constraint(equalToConstant: 44),
                close.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
                capture.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                capture.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                capture.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
                capture.heightAnchor.constraint(equalToConstant: 44),
            ])
        }

        @objc private func cancel() {
            finish {
                self.haltSession()
                self.onCancel?()
            }
        }

        @objc private func shoot() {
            sessionQueue.async {
                guard self.session.isRunning,
                      self.output.connections.contains(where: \.isEnabled) else { return }
                self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }

        func photoOutput(
            _ output: AVCapturePhotoOutput,
            didFinishProcessingPhoto photo: AVCapturePhoto,
            error: Error?
        ) {
            haltSession()
            DispatchQueue.main.async {
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
                self.haltSession()
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
