import AVFoundation
import BlackoutCore
import Foundation
import MediaPlayer
import Observation
import UIKit

/// Live half-duplex PTT. No clip list. No queued audio. Fail closed if the engine cannot start.
@MainActor
@Observable
public final class LivePTTHub {
    public private(set) var isTransmitting = false
    public private(set) var isReceiving = false
    public private(set) var microphoneAllowed = true
    public private(set) var lastRefusal: String?
    public private(set) var lastHeardAt: Date?
    public var extremeSaver = false

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var sendFrame: ((Data) -> Bool)?
    private var remoteInstalled = false
    private var remoteDecision: (() -> PTTDecision)?

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
        lastHeardAt = Date()
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
        uninstallRemoteCommands()
    }

    /// Headset / lock-screen play-pause via `MPRemoteCommandCenter`.
    /// Hardware volume-up cannot be used as PTT without a private API
    /// (`SystemVolumeDidChange` / `MPVolumeView` hijack). Headset / remote only.
    public func installRemoteCommands(decision: @escaping () -> PTTDecision) {
        remoteDecision = decision
        guard !remoteInstalled else { return }
        remoteInstalled = true
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.isEnabled = true
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handleRemoteToggle() ?? .commandFailed
        }
        center.playCommand.addTarget { [weak self] _ in
            self?.handleRemoteBegin() ?? .commandFailed
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.handleRemoteEnd() ?? .commandFailed
        }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = "BLACKOUT PTT"
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    public func uninstallRemoteCommands() {
        guard remoteInstalled else { return }
        remoteInstalled = false
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.removeTarget(nil)
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        remoteDecision = nil
    }

    /// Action Button / Camera Control / App Intent. Same fail-fast as the 72 disk.
    @discardableResult
    public func toggleFromExternal() -> Bool {
        if isTransmitting {
            endFromExternal()
            return true
        }
        return beginFromExternal()
    }

    @discardableResult
    public func beginFromExternal() -> Bool {
        let decision = currentDecision()
        if !decision.allowsTransmit {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            lastRefusal = decision.pressMessage
            return false
        }
        let ok = pressBegan(decision: decision)
        UIImpactFeedbackGenerator(style: ok ? .medium : .rigid).impactOccurred()
        return ok
    }

    public func endFromExternal() {
        guard isTransmitting else { return }
        pressEnded()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func currentDecision() -> PTTDecision {
        remoteDecision?() ?? PTTDecision.evaluate(
            nearbyPeerCount: 0,
            partyCode: nil,
            meshRunning: false,
            microphoneAllowed: microphoneAllowed
        )
    }

    @discardableResult
    private func handleRemoteToggle() -> MPRemoteCommandHandlerStatus {
        if isTransmitting {
            return handleRemoteEnd()
        }
        return handleRemoteBegin()
    }

    @discardableResult
    private func handleRemoteBegin() -> MPRemoteCommandHandlerStatus {
        let decision = remoteDecision?() ?? PTTDecision.evaluate(
            nearbyPeerCount: 0,
            partyCode: nil,
            meshRunning: false,
            microphoneAllowed: microphoneAllowed
        )
        return pressBegan(decision: decision) ? .success : .commandFailed
    }

    @discardableResult
    private func handleRemoteEnd() -> MPRemoteCommandHandlerStatus {
        pressEnded()
        return .success
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
        let header = [UInt8](data.prefix(4))
        let rate = UInt32(header[0]) << 24
            | UInt32(header[1]) << 16
            | UInt32(header[2]) << 8
            | UInt32(header[3])
        let sampleBytes = data.dropFirst(4)
        guard sampleBytes.count % 2 == 0 else { return nil }
        var samples = [Int16](repeating: 0, count: sampleBytes.count / 2)
        _ = samples.withUnsafeMutableBytes { dest in
            sampleBytes.copyBytes(to: dest)
        }
        return (Double(rate), samples)
    }
}
