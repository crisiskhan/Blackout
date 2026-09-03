import Foundation
import VisionCoreML

public struct CaptureFrame: Equatable, Sendable {
    public var features: [Double]
    public var added: Bool
}

public struct GuidedCapture: Equatable, Sendable {
    public var frames: [CaptureFrame] = []
    public mutating func addFrame(_ features: [Double]) {
        frames.append(CaptureFrame(features: features, added: true))
    }
    public func mergedFeatures() -> [Double] {
        guard !frames.isEmpty else { return [0, 0, 0]
        }
        let n = Double(frames.count)
        return (0..<frames[0].features.count).map { i in
            frames.map { $0.features[i] }.reduce(0, +) / n
        }
    }
    public func guess(book: VisionBook) -> VisionGuess {
        VisionCoreML.classify(features: mergedFeatures(), book: book)
    }
}
