import BlackoutCore
import Foundation

/// Disk queue for sealed envelopes. Dedupe by id. Mesh does not inspect ciphertext.
public final class StoreAndForwardQueue: @unchecked Sendable {
    public static let designPeerLoad = 20
    public static let maxPending = 64
    public static let maxHops = 16

    public enum Inbound: Equatable {
        case duplicate
        case deliverAndForward(Envelope)
    }

    private let fileURL: URL
    private var seen: Set<String> = []
    private var pending: [Envelope] = []
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    public var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    public func hasSeen(_ id: BlackoutID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return seen.contains(id.rawValue.uuidString)
    }

    public func noteOutbound(_ envelope: Envelope) {
        lock.lock()
        seen.insert(envelope.id.rawValue.uuidString)
        enqueueLocked(envelope)
        persistLocked()
        lock.unlock()
    }

    public func acceptInbound(_ envelope: Envelope) -> Inbound {
        lock.lock()
        defer { lock.unlock() }
        let key = envelope.id.rawValue.uuidString
        if seen.contains(key) {
            return .duplicate
        }
        if envelope.hopCount >= Self.maxHops {
            seen.insert(key)
            persistLocked()
            return .duplicate
        }
        seen.insert(key)
        let next = envelope.forwarded()
        enqueueLocked(next)
        persistLocked()
        return .deliverAndForward(next)
    }

    public func flushPending() -> [Envelope] {
        lock.lock()
        defer { lock.unlock() }
        return pending
    }

    private func enqueueLocked(_ envelope: Envelope) {
        if pending.contains(where: { $0.id == envelope.id }) { return }
        pending.append(envelope)
        if pending.count > Self.maxPending {
            pending.removeFirst(pending.count - Self.maxPending)
        }
    }

    private struct DiskState: Codable {
        var seen: [String]
        var pending: [Envelope]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let state = try? decoder.decode(DiskState.self, from: data) else { return }
        seen = Set(state.seen)
        pending = state.pending
    }

    private func persistLocked() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let state = DiskState(seen: Array(seen), pending: pending)
        guard let data = try? encoder.encode(state) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
