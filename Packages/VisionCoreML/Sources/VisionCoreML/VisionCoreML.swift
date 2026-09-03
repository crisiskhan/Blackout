import Foundation

public struct VisionGuess: Equatable, Sendable {
    public var labelId: String
    public var name: String
    public var percent: Int
    public var lookalikes: [String]
    public var leaveIt: Bool
    public var edible: Bool
}

public struct VisionLabel: Codable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var lookalikes: [String]
    public var leaveIt: Bool
    public var edibleUnlock: Bool
    public var marineOrGatorFL: Bool
    public var name: [String: String]
}

public struct VisionBook: Codable, Equatable, Sendable {
    public var state: String
    public var neverEdibleUnlock: Bool
    public var fungiDefault: String
    public var labels: [VisionLabel]
}

public enum VisionCoreML {
    public static func load(_ data: Data) throws -> VisionBook {
        try JSONDecoder().decode(VisionBook.self, from: data)
    }

    public static func classify(features: [Double], book: VisionBook) -> VisionGuess {
        let idx = abs(features.hashValue) % max(1, book.labels.count)
        let lab = book.labels[idx]
        let pct = 40 + (abs(features.hashValue) % 45)
        return VisionGuess(
            labelId: lab.id,
            name: lab.name["en"] ?? lab.id,
            percent: pct,
            lookalikes: lab.lookalikes,
            leaveIt: lab.kind == "fungi" ? true : lab.leaveIt,
            edible: false
        )
    }
}
