import Foundation

/// Result of handing an envelope to the dumb pipe. Mesh does not inspect ciphertext.
public enum MeshSendResult: Equatable, Sendable {
    case sent
    case notRunning
    case noPeers
    case failed

    public var messageStatus: MessageStatus {
        switch self {
        case .sent:
            return .onMesh
        case .notRunning, .noPeers:
            return .queued
        case .failed:
            return .failed
        }
    }
}
