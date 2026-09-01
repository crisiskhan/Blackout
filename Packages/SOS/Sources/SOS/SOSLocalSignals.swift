import AVFoundation
import DesignSystem
import SwiftUI
import UIKit

/// Language-free SOS actions. Never auto-dials 911.
struct SOSPictogramBar: View {
    var onSiren: () -> Void
    var onStrobe: () -> Void
    var onSystemSOS: () -> Void
    var onCancel: () -> Void
    var sirenOn: Bool
    var strobeOn: Bool

    var body: some View {
        PictogramBar(items: [
            .init(id: "siren", systemName: "speaker.wave.3.fill", on: sirenOn, label: "Siren", action: onSiren),
            .init(id: "strobe", systemName: "flashlight.on.fill", on: strobeOn, label: "Strobe", action: onStrobe),
            .init(id: "ossos", systemName: "satellite.fill", on: false, label: "OS SOS", action: onSystemSOS),
            .init(id: "cancel", systemName: "xmark", on: false, label: "Cancel", action: onCancel)
        ])
    }
}

@MainActor
final class SOSLocalSignals {
    static let shared = SOSLocalSignals()
    private var sirenPlayer: AVAudioPlayer?
    private var strobeTimer: Timer?
    private var strobeOn = false
    private(set) var sirenRunning = false
    private(set) var strobeRunning = false
    var onStrobeTick: ((Bool) -> Void)?

    func toggleSiren() {
        if sirenRunning {
            sirenPlayer?.stop()
            sirenPlayer = nil
            sirenRunning = false
            return
        }
        sirenPlayer = Self.makeSirenPlayer()
        sirenPlayer?.numberOfLoops = -1
        sirenPlayer?.play()
        sirenRunning = sirenPlayer?.isPlaying == true
    }

    func toggleStrobe() {
        if strobeRunning {
            strobeTimer?.invalidate()
            strobeTimer = nil
            strobeRunning = false
            strobeOn = false
            torch(false)
            onStrobeTick?(false)
            return
        }
        strobeRunning = true
        strobeTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.strobeOn.toggle()
                self.torch(self.strobeOn)
                self.onStrobeTick?(self.strobeOn)
            }
        }
    }

    func stopAll() {
        if sirenRunning { toggleSiren() }
        if strobeRunning { toggleStrobe() }
    }

    private func torch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            _ = error
        }
    }

    private static func makeSirenPlayer() -> AVAudioPlayer? {
        let sampleRate = 22050
        let duration = 1
        let n = sampleRate * duration
        var data = Data()
        func append(_ value: UInt32) {
            var v = value.littleEndian
            Swift.withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            var v = value.littleEndian
            Swift.withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        append(UInt32(36 + n * 2))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45, 0x66, 0x6D, 0x74, 0x20])
        append(16)
        append16(1)
        append16(1)
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append16(2)
        append16(16)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        append(UInt32(n * 2))
        for i in 0..<n {
            let t = Double(i) / Double(sampleRate)
            let freq = t < 0.5 ? 880.0 : 600.0
            let sample = Int16(sin(2 * .pi * freq * t) * 12000)
            var v = UInt16(bitPattern: sample).littleEndian
            Swift.withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        return try? AVAudioPlayer(data: data)
    }
}
