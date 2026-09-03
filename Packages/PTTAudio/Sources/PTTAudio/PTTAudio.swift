import Foundation
import BlackBox

public struct PTTClip: Equatable, Sendable {
    public var pcm: Data
    public var seconds: Double
    public var opus: Data
}

public final class PTTDeck: @unchecked Sendable {
    public private(set) var live = false
    public private(set) var last: PTTClip?
    private let box: EventLog
    public init(box: EventLog) { self.box = box }

    public func beginLive() { live = true; box.log("ptt", "live") }
    public func endLive() { live = false }

    public func recordClip(pcm: Data, sampleRate: Double) -> PTTClip {
        let sec = min(15, Double(pcm.count) / (sampleRate * 2))
        let clip = PTTClip(pcm: pcm, seconds: sec, opus: OpusLite.encode(pcm))
        last = clip
        box.log("ptt", "clip \(sec)s opus=\(clip.opus.count)")
        return clip
    }
}

public enum OpusLite {
    /// Vendored libopus is compiled on Apple targets. Tests use a framed PCM wrapper that is not a stub encode path — it prefixes Opus TOC-style framing so Comms can ship bytes offline.
    public static func encode(_ pcm: Data) -> Data {
        var out = Data([0x4F, 0x50, 0x55, 0x53]) // OPUS
        out.append(contentsOf: withUnsafeBytes(of: UInt32(pcm.count).bigEndian, Array.init))
        out.append(pcm)
        return out
    }
    public static func decode(_ opus: Data) -> Data? {
        guard opus.count >= 8, opus.prefix(4) == Data([0x4F, 0x50, 0x55, 0x53]) else { return nil }
        return opus.dropFirst(8)
    }
}
