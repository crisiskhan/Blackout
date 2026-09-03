import Foundation

public struct VisionGuess: Equatable, Sendable {
    public var labelId: String
    public var name: String
    public var percent: Int
    public var lookalikes: [String]
    public var leaveIt: Bool
    public var edible: Bool
    public var noModel: Bool

    public init(
        labelId: String,
        name: String,
        percent: Int,
        lookalikes: [String],
        leaveIt: Bool,
        edible: Bool,
        noModel: Bool
    ) {
        self.labelId = labelId
        self.name = name
        self.percent = percent
        self.lookalikes = lookalikes
        self.leaveIt = leaveIt
        self.edible = edible
        self.noModel = noModel
    }
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
    /// No compiled .mlmodel ships in this tree. Hash-to-label is not an ID.
    public static let onDeviceModelPresent = false

    public static func load(_ data: Data) throws -> VisionBook {
        try JSONDecoder().decode(VisionBook.self, from: data)
    }

    public static func classify(features: [Double], book: VisionBook) -> VisionGuess {
        _ = features
        _ = book
        return VisionGuess(
            labelId: "no-model",
            name: "NO VISION MODEL",
            percent: 0,
            lookalikes: [],
            leaveIt: true,
            edible: false,
            noModel: true
        )
    }
}
