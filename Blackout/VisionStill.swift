import SwiftUI
import Tokens
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(CoreImage)
import CoreImage
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

    /// UI origin top-left, 0...1. Finder and the still well share this box.
    static func subjectNormalizedBox(from image: CGImage) -> CGRect? {
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
        return normalizedUIBox(box.boundingBox, pad: 0.12)
        #else
        return nil
        #endif
    }

    private static func subjectCrop(from image: CGImage) -> CGImage? {
        guard let n = subjectNormalizedBox(from: image) else { return nil }
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let r = CGRect(x: n.minX * w, y: n.minY * h, width: n.width * w, height: n.height * h)
        guard r.width >= 32, r.height >= 32 else { return nil }
        return image.cropping(to: r.integral)
    }

    /// Vision boxes are origin-bottom-left. The glass is origin-top-left.
    private static func normalizedUIBox(_ box: CGRect, pad: CGFloat) -> CGRect {
        let uiY = 1 - box.maxY
        let px = box.width * pad
        let py = box.height * pad
        let left = max(0, box.minX - px)
        let top = max(0, uiY - py)
        let right = min(1, box.maxX + px)
        let bottom = min(1, uiY + box.height + py)
        return CGRect(
            x: left,
            y: top,
            width: max(0, right - left),
            height: max(0, bottom - top)
        )
    }

    private static func centerCrop(_ image: CGImage, fraction: CGFloat = 0.55) -> CGImage? {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let cw = max(32, w * fraction)
        let ch = max(32, h * fraction)
        let rect = CGRect(x: (w - cw) / 2, y: (h - ch) / 2, width: cw, height: ch)
        return image.cropping(to: rect.integral)
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

    final class StillVC: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
        var onImage: ((CGImage) -> Void)?
        var onFail: (() -> Void)?
        var onCancel: (() -> Void)?
        private let session = AVCaptureSession()
        private let output = AVCapturePhotoOutput()
        private let videoOut = AVCaptureVideoDataOutput()
        private let sessionQueue = DispatchQueue(label: "blackout.vision.session")
        private let ci = CIContext(options: [.useSoftwareRenderer: false])
        private var lampButton: UIButton?
        private var statusLabel: UILabel?
        private var subjectBox: UIView?
        private var captureDevice: AVCaptureDevice?
        private var started = false
        private var finished = false
        private var denied = false
        private var lastBoxAt: CFTimeInterval = 0

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
                            self.denied = true
                            self.setStatus("CAMERA DENIED")
                        }
                    }
                }
            case .denied, .restricted:
                denied = true
                setStatus("CAMERA DENIED")
            @unknown default:
                denied = true
                setStatus("CAMERA DENIED")
            }
        }

        private func startSession() {
            guard !started else { return }
            started = true
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video)
            guard let device,
                  let input = try? AVCaptureDeviceInput(device: device) else {
                setStatus("WAIT")
                return
            }
            captureDevice = device
            sessionQueue.async {
                guard !self.finished else { return }
                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }
                guard self.session.canAddInput(input) else {
                    DispatchQueue.main.async { self.setStatus("WAIT") }
                    return
                }
                self.session.addInput(input)
                guard self.session.canAddOutput(self.output) else {
                    DispatchQueue.main.async { self.setStatus("WAIT") }
                    return
                }
                self.session.addOutput(self.output)
                if let connection = self.output.connection(with: .video), connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                self.videoOut.alwaysDiscardsLateVideoFrames = true
                self.videoOut.setSampleBufferDelegate(self, queue: self.sessionQueue)
                if self.session.canAddOutput(self.videoOut) {
                    self.session.addOutput(self.videoOut)
                    if let live = self.videoOut.connection(with: .video), live.isVideoOrientationSupported {
                        live.videoOrientation = .portrait
                    }
                }
            }
            sessionQueue.async {
                guard !self.finished else { return }
                self.session.startRunning()
                let running = self.session.isRunning
                DispatchQueue.main.async {
                    if !running {
                        self.setStatus("WAIT")
                    }
                }
            }
        }

        private func haltSession() {
            lampOff()
            sessionQueue.async { self.session.stopRunning() }
        }

        private func installChrome() {
            let silver = UIColor(white: 0.86, alpha: 1)
            let accent = UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
            let close = UIButton(type: .system)
            close.setTitle("CLOSE", for: .normal)
            close.titleLabel?.font = .systemFont(ofSize: 13, weight: .heavy)
            close.setTitleColor(silver, for: .normal)
            close.addTarget(self, action: #selector(cancel), for: .touchUpInside)
            close.translatesAutoresizingMaskIntoConstraints = false

            let lamp = UIButton(type: .system)
            lamp.setTitle("LAMP", for: .normal)
            lamp.titleLabel?.font = .systemFont(ofSize: 13, weight: .heavy)
            lamp.setTitleColor(silver, for: .normal)
            lamp.addTarget(self, action: #selector(lampTapped), for: .touchUpInside)
            lamp.translatesAutoresizingMaskIntoConstraints = false
            lampButton = lamp

            let capture = UIButton(type: .system)
            capture.setTitle("CAPTURE", for: .normal)
            capture.titleLabel?.font = .systemFont(ofSize: 18, weight: .heavy)
            capture.setTitleColor(silver, for: .normal)
            capture.backgroundColor = accent
            capture.layer.cornerRadius = 10
            capture.layer.borderWidth = 1
            capture.layer.borderColor = silver.withAlphaComponent(0.45).cgColor
            capture.addTarget(self, action: #selector(shoot), for: .touchUpInside)
            capture.translatesAutoresizingMaskIntoConstraints = false

            let status = UILabel()
            status.font = .systemFont(ofSize: 13, weight: .heavy)
            status.textColor = silver
            status.textAlignment = .center
            status.isHidden = true
            status.translatesAutoresizingMaskIntoConstraints = false
            statusLabel = status

            let reticle = UIView()
            reticle.isUserInteractionEnabled = false
            reticle.translatesAutoresizingMaskIntoConstraints = false
            reticle.accessibilityLabel = "RETICLE"
            reticle.layer.name = "reticle"
            let ring = UIView()
            ring.translatesAutoresizingMaskIntoConstraints = false
            ring.layer.borderColor = silver.withAlphaComponent(0.55).cgColor
            ring.layer.borderWidth = 1.7
            ring.backgroundColor = .clear
            let inner = UIView()
            inner.translatesAutoresizingMaskIntoConstraints = false
            inner.layer.borderColor = silver.withAlphaComponent(0.34).cgColor
            inner.layer.borderWidth = 1
            inner.backgroundColor = .clear
            let hairH = UIView()
            hairH.backgroundColor = silver.withAlphaComponent(0.55)
            hairH.translatesAutoresizingMaskIntoConstraints = false
            let hairV = UIView()
            hairV.backgroundColor = silver.withAlphaComponent(0.55)
            hairV.translatesAutoresizingMaskIntoConstraints = false
            reticle.addSubview(ring)
            reticle.addSubview(inner)
            reticle.addSubview(hairH)
            reticle.addSubview(hairV)

            let box = UIView()
            box.isUserInteractionEnabled = false
            box.isHidden = true
            box.layer.name = "subjectBox"
            box.layer.borderColor = accent.cgColor
            box.layer.borderWidth = 1
            box.backgroundColor = .clear
            box.translatesAutoresizingMaskIntoConstraints = true
            subjectBox = box

            view.addSubview(box)
            view.addSubview(reticle)
            view.addSubview(close)
            view.addSubview(lamp)
            view.addSubview(status)
            view.addSubview(capture)
            let shutter = CGFloat(BlackoutTokens.Chrome.visionShutterPoints)
            NSLayoutConstraint.activate([
                close.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                close.heightAnchor.constraint(equalToConstant: 44),
                close.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
                lamp.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                lamp.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                lamp.heightAnchor.constraint(equalToConstant: 44),
                lamp.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
                reticle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                reticle.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                reticle.widthAnchor.constraint(equalToConstant: 160),
                reticle.heightAnchor.constraint(equalToConstant: 160),
                ring.leadingAnchor.constraint(equalTo: reticle.leadingAnchor),
                ring.trailingAnchor.constraint(equalTo: reticle.trailingAnchor),
                ring.topAnchor.constraint(equalTo: reticle.topAnchor),
                ring.bottomAnchor.constraint(equalTo: reticle.bottomAnchor),
                inner.leadingAnchor.constraint(equalTo: reticle.leadingAnchor, constant: 8),
                inner.trailingAnchor.constraint(equalTo: reticle.trailingAnchor, constant: -8),
                inner.topAnchor.constraint(equalTo: reticle.topAnchor, constant: 8),
                inner.bottomAnchor.constraint(equalTo: reticle.bottomAnchor, constant: -8),
                hairH.centerYAnchor.constraint(equalTo: reticle.centerYAnchor),
                hairH.leadingAnchor.constraint(equalTo: reticle.leadingAnchor, constant: 18),
                hairH.trailingAnchor.constraint(equalTo: reticle.trailingAnchor, constant: -18),
                hairH.heightAnchor.constraint(equalToConstant: 1),
                hairV.centerXAnchor.constraint(equalTo: reticle.centerXAnchor),
                hairV.topAnchor.constraint(equalTo: reticle.topAnchor, constant: 18),
                hairV.bottomAnchor.constraint(equalTo: reticle.bottomAnchor, constant: -18),
                hairV.widthAnchor.constraint(equalToConstant: 1),
                status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                status.bottomAnchor.constraint(equalTo: capture.topAnchor, constant: -10),
                capture.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                capture.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                capture.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
                capture.heightAnchor.constraint(equalToConstant: shutter),
            ])
            ring.layer.cornerRadius = 80
            inner.layer.cornerRadius = 72
        }

        private func setStatus(_ text: String) {
            statusLabel?.text = text
            statusLabel?.isHidden = text.isEmpty
        }

        @objc private func cancel() {
            finish {
                self.haltSession()
                if self.denied {
                    self.onFail?()
                } else {
                    self.onCancel?()
                }
            }
        }

        @objc private func shoot() {
            if denied {
                setStatus("CAMERA DENIED")
                return
            }
            sessionQueue.async {
                guard self.session.isRunning,
                      self.output.connections.contains(where: \.isEnabled) else {
                    DispatchQueue.main.async { self.setStatus("WAIT") }
                    return
                }
                self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }

        @objc private func lampTapped() {
            guard let device = captureDevice ?? AVCaptureDevice.default(for: .video),
                  device.hasTorch
            else {
                setStatus("LAMP · NONE")
                return
            }
            do {
                try device.lockForConfiguration()
                if device.torchMode == .on {
                    device.torchMode = .off
                    lampButton?.backgroundColor = .clear
                } else if device.isTorchModeSupported(.on) {
                    try device.setTorchModeOn(level: 1)
                    lampButton?.backgroundColor = UIColor(red: 225.0 / 255.0, green: 6.0 / 255.0, blue: 0, alpha: 1)
                } else {
                    device.unlockForConfiguration()
                    setStatus("LAMP · NONE")
                    return
                }
                device.unlockForConfiguration()
            } catch {
                setStatus("LAMP · NONE")
            }
        }

        private func lampOff() {
            guard let device = captureDevice, device.hasTorch, device.torchMode == .on else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
            } catch {
                return
            }
        }

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            let now = CACurrentMediaTime()
            guard now - lastBoxAt > 0.25 else { return }
            lastBoxAt = now
            guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let image = ci.createCGImage(CIImage(cvPixelBuffer: pixel), from: CIImage(cvPixelBuffer: pixel).extent)
            guard let image, let box = SystemVision.subjectNormalizedBox(from: image) else {
                DispatchQueue.main.async { self.subjectBox?.isHidden = true }
                return
            }
            DispatchQueue.main.async { self.layoutSubjectBox(box) }
        }

        private func layoutSubjectBox(_ n: CGRect) {
            guard let box = subjectBox else { return }
            let frame = view.bounds
            box.frame = CGRect(
                x: n.minX * frame.width,
                y: n.minY * frame.height,
                width: n.width * frame.width,
                height: n.height * frame.height
            )
            box.isHidden = false
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
