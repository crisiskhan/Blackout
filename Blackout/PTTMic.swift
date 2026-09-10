import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Live hold and 15s clip live in the app, not in PTTAudio. The package
/// stays engine-free so NET · NONE cannot hang inside a hub.
final class PTTMic {
    static let shared = PTTMic()

    #if canImport(AVFoundation)
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private static var heldPlayer: AVAudioPlayer?
    #endif

    /// Never block the main thread waiting on the mic prompt. A semaphore here
    /// is how a live-PTT hub hung the phone.
    func arm(onReady: @escaping (Bool) -> Void) {
        #if canImport(AVFoundation)
        let go: (Bool) -> Void = { granted in
            DispatchQueue.main.async {
                onReady(granted ? self.beginRecorder() : false)
            }
        }
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            go(true)
        case .denied:
            go(false)
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                go(granted)
            }
        @unknown default:
            go(false)
        }
        #else
        onReady(false)
        #endif
    }

    func stop() -> Data {
        #if canImport(AVFoundation)
        recorder?.stop()
        recorder = nil
        defer { fileURL = nil }
        guard let url = fileURL else { return Data() }
        return pcm(from: url)
        #else
        return Data()
        #endif
    }

    func play(_ pcm: Data) {
        #if canImport(AVFoundation)
        guard !pcm.isEmpty else { return }
        let wav = Self.wav(pcm)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: wav)
            player.play()
            Self.heldPlayer = player
        } catch {
            return
        }
        #endif
    }

    #if canImport(AVFoundation)
    private func beginRecorder() -> Bool {
        recorder?.stop()
        recorder = nil
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            return false
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("blackout-ptt.caf")
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        recorder.prepareToRecord()
        guard recorder.record() else { return false }
        self.recorder = recorder
        fileURL = url
        return true
    }

    private func pcm(from url: URL) -> Data {
        guard let file = try? AVAudioFile(forReading: url) else { return Data() }
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              (try? file.read(into: buf)) != nil else { return Data() }
        if let ints = buf.int16ChannelData {
            return Data(bytes: ints[0], count: Int(buf.frameLength) * MemoryLayout<Int16>.size)
        }
        guard let floats = buf.floatChannelData else { return Data() }
        let n = Int(buf.frameLength)
        var out = Data(count: n * 2)
        out.withUnsafeMutableBytes { raw in
            let dest = raw.bindMemory(to: Int16.self)
            let src = floats[0]
            for i in 0..<n {
                let s = max(-1, min(1, src[i]))
                dest[i] = Int16(s * Float(Int16.max))
            }
        }
        return out
    }

    private static func wav(_ pcm: Data) -> Data {
        let rate: UInt32 = 16_000
        let ch: UInt16 = 1
        let bits: UInt16 = 16
        let byteRate = rate * UInt32(ch) * UInt32(bits / 8)
        var data = Data()
        func ascii(_ s: String) { data.append(contentsOf: s.utf8) }
        func u16(_ v: UInt16) {
            var x = v.littleEndian
            data.append(Data(bytes: &x, count: 2))
        }
        func u32(_ v: UInt32) {
            var x = v.littleEndian
            data.append(Data(bytes: &x, count: 4))
        }
        ascii("RIFF")
        u32(UInt32(36 + pcm.count))
        ascii("WAVE")
        ascii("fmt ")
        u32(16)
        u16(1)
        u16(ch)
        u32(rate)
        u32(byteRate)
        u16(ch * bits / 8)
        u16(bits)
        ascii("data")
        u32(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
    #endif
}
