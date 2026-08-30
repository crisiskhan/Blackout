import AVFoundation
import BlackoutCore
import Foundation
import Observation

/// Live half-duplex PTT. No clip list. No queued audio. Fail closed if the engine cannot start.
@MainActor
@Observable
public final class LivePTTHub {
    public private(set) var isTransmitting = false
    public private(set) var isReceiving = false
    public private(set) var microphoneAllowed = true
    public private(set) var lastRefusal: String?
    public var extremeSaver = false

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var sendFrame: ((Data) -> Bool)?

    public init() {}

    public func decision(nearbyPeerCount: Int, partyCode: String?, meshRunning: Bool) -> PTTDecision {
        PTTDecision.evaluate(
            nearbyPeerCount: nearbyPeerCount,
            partyCode: partyCode,
            meshRunning: meshRunning,
            microphoneAllowed: microphoneAllowed
        )
    }

    public func refreshMicrophone() async {
        microphoneAllowed = await requestMic()
    }

    public func bindSender(_ send: @escaping (Data) -> Bool) {
        sendFrame = send
    }

    public func noteRefusal(_ message: String?) {
        lastRefusal = message
    }

    public func pressBegan(decision: PTTDecision) -> Bool {
        lastRefusal = nil
        var unused: [Data] = []
        guard LivePTTLogic.beginTalk(decision: decision, buffer: &unused) else {
            lastRefusal = decision.pressMessage
            return false
        }
        guard !isReceiving else {
            lastRefusal = PTTCopy.noMeshPress
            return false
        }
        do {
            try startEngine(transmit: true)
            isTransmitting = true
            lastRefusal = nil
            return true
        } catch {
            stopEngine()
            isTransmitting = false
            lastRefusal = "PTT live path failed. Use text."
            return false
        }
    }

    public func pressEnded() {
        isTransmitting = false
        engine?.inputNode.removeTap(onBus: 0)
        if !isReceiving {
            stopEngine()
        }
    }

    public func receive(_ payload: Data) {
        guard !isTransmitting else { return }
        guard let packet = PTTAudioPacket.decode(payload) else { return }
        do {
            try startEngine(transmit: false)
            isReceiving = true
            let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: packet.sampleRate,
                channels: 1,
                interleaved: true
            )
            guard let format,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(packet.samples.count))
            else { return }
            buffer.frameLength = AVAudioFrameCount(packet.samples.count)
            packet.samples.withUnsafeBufferPointer { src in
                if let dest = buffer.int16ChannelData?[0] {
                    dest.update(from: src.baseAddress!, count: packet.samples.count)
                }
            }
            player?.scheduleBuffer(buffer) { [weak self] in
                Task { @MainActor in
                    self?.isReceiving = false
                }
            }
            if player?.isPlaying != true {
                player?.play()
            }
        } catch {
            isReceiving = false
            stopEngine()
        }
    }

    public func stop() {
        isTransmitting = false
        isReceiving = false
        engine?.inputNode.removeTap(onBus: 0)
        stopEngine()
    }

    private func startEngine(transmit: Bool) throws {
        if engine == nil {
            let next = AVAudioEngine()
            let node = AVAudioPlayerNode()
            next.attach(node)
            let rate = extremeSaver ? 8_000.0 : 16_000.0
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: rate,
                channels: 1,
                interleaved: true
            ) else {
                throw LivePTTError.engine
            }
            next.connect(node, to: next.mainMixerNode, format: format)
            engine = next
            player = node
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
        try session.setPreferredSampleRate(extremeSaver ? 8_000 : 16_000)
        try session.setActive(true)
        guard let engine else { throw LivePTTError.engine }
        if transmit {
            engine.inputNode.removeTap(onBus: 0)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
                self?.emit(buffer)
            }
        }
        if !engine.isRunning {
            try engine.start()
        }
    }

    private func emit(_ buffer: AVAudioPCMBuffer) {
        Task { @MainActor in
            guard isTransmitting else { return }
            guard let packet = PTTAudioPacket.encode(buffer, extremeSaver: extremeSaver) else { return }
            let decision = PTTDecision.evaluate(
                nearbyPeerCount: 1,
                partyCode: "LIVE",
                meshRunning: true,
                microphoneAllowed: true
            )
            guard let live = LivePTTLogic.liveFrame(decision: decision, transmitting: true, frame: packet) else {
                return
            }
            _ = sendFrame?(live)
        }
    }

    private func stopEngine() {
        engine?.stop()
        player?.stop()
        engine = nil
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestMic() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
    }
}

enum LivePTTError: Error {
    case engine
}

enum PTTAudioPacket {
    static func encode(_ buffer: AVAudioPCMBuffer, extremeSaver: Bool) -> Data? {
        let rate = UInt32(extremeSaver ? 8_000 : 16_000)
        var samples: [Int16] = []
        if let int16 = buffer.int16ChannelData?[0] {
            samples = Array(UnsafeBufferPointer(start: int16, count: Int(buffer.frameLength)))
        } else if let floats = buffer.floatChannelData?[0] {
            samples = (0..<Int(buffer.frameLength)).map { index in
                Int16(max(-1, min(1, floats[index])) * Float(Int16.max))
            }
        } else {
            return nil
        }
        var data = Data()
        var rateBE = rate.bigEndian
        withUnsafeBytes(of: &rateBE) { data.append(contentsOf: $0) }
        samples.withUnsafeBufferPointer { ptr in
            data.append(contentsOf: UnsafeRawBufferPointer(ptr))
        }
        return data
    }

    static func decode(_ data: Data) -> (sampleRate: Double, samples: [Int16])? {
        guard data.count >= 6 else { return nil }
        let rate: UInt32 = data.prefix(4).withUnsafeBytes { raw in
            var value: UInt32 = 0
            Swift.withUnsafeMutableBytes(of: &value) { dest in
                dest.copyBytes(from: raw.prefix(4))
            }
            return UInt32(bigEndian: value)
        }
        let sampleBytes = data.dropFirst(4)
        guard sampleBytes.count % 2 == 0 else { return nil }
        var samples = [Int16](repeating: 0, count: sampleBytes.count / 2)
        _ = samples.withUnsafeMutableBytes { dest in
            sampleBytes.copyBytes(to: dest)
        }
        return (Double(rate), samples)
    }
}
