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

public struct VisionObservation: Equatable, Sendable {
    public var identifier: String
    public var confidence: Double

    public init(identifier: String, confidence: Double) {
        self.identifier = identifier
        self.confidence = confidence
    }
}

public struct VisionLabel: Codable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var lookalikes: [String]
    public var leaveIt: Bool
    public var edibleUnlock: Bool
    public var name: [String: String]

    public func displayName(_ locale: String) -> String {
        if locale == "es" { return name["es"] ?? name["en"] ?? id }
        return name["en"] ?? id
    }
}

public struct VisionBook: Codable, Equatable, Sendable {
    public var state: String
    public var neverEdibleUnlock: Bool
    public var fungiDefault: String
    public var labels: [VisionLabel]
}

public enum VisionCoreML {
    /// No compiled .mlmodel ships in this tree. Hash-to-label is not an ID.
    /// FIELD stills go through the system image classifier, then this matcher.
    public static let onDeviceModelPresent = false

    public static func load(_ data: Data) throws -> VisionBook {
        try JSONDecoder().decode(VisionBook.self, from: data)
    }

    public static func noModelGuess() -> VisionGuess {
        VisionGuess(
            labelId: "no-model",
            name: "NO VISION MODEL",
            percent: 0,
            lookalikes: [],
            leaveIt: true,
            edible: false,
            noModel: true
        )
    }

    public static func unknownGuess() -> VisionGuess {
        VisionGuess(
            labelId: "unknown",
            name: "UNKNOWN",
            percent: 0,
            lookalikes: [],
            leaveIt: true,
            edible: false,
            noModel: false
        )
    }

    /// Dummy features never become an ID. The still path uses observations.
    public static func classify(features: [Double], book: VisionBook) -> VisionGuess {
        _ = features
        _ = book
        return noModelGuess()
    }

    public static func classify(observations: [VisionObservation], book: VisionBook, locale: String = "en") -> VisionGuess {
        let usable = observations
            .filter { $0.confidence >= 0.2 }
            .sorted { $0.confidence > $1.confidence }
        for obs in usable {
            if let hit = match(obs.identifier, book: book, locale: locale) {
                return sealed(hit)
            }
        }
        return unknownGuess()
    }

    public static func lookalikeWord(_ raw: String) -> String {
        raw.replacingOccurrences(of: "-lookalike", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .uppercased()
    }

    private static func sealed(_ guess: VisionGuess) -> VisionGuess {
        var g = guess
        g.edible = false
        g.percent = 0
        if g.labelId.contains("fungi") || g.name == "FUNGI" {
            g.leaveIt = true
        }
        if g.labelId.contains("snake") || g.name == "SNAKE" {
            g.leaveIt = true
        }
        return g
    }

    private static func match(_ identifier: String, book: VisionBook, locale: String) -> VisionGuess? {
        let ident = normalize(identifier)
        if fungiNeedles.contains(where: { ident.contains($0) }) {
            return fungiGuess(book, locale: locale)
        }

        let species = book.labels.filter { label in
            if label.kind == "fungi" { return false }
            let names = label.name.values.map(normalize)
            let shortId = normalize(
                label.id
                    .replacingOccurrences(of: "tx-", with: "")
                    .replacingOccurrences(of: "nm-", with: "")
            )
            return names.contains(where: { !$0.isEmpty && (ident.contains($0) || $0.contains(ident) && ident.count >= 4) })
                || (!shortId.isEmpty && ident.contains(shortId))
        }
        if species.count == 1 {
            if species[0].kind == "snake" {
                return snakeGuess()
            }
            return speciesGuess(species[0], locale: locale)
        }
        if species.count > 1 {
            let kinds = Set(species.map(\.kind))
            if kinds.count == 1, let kind = kinds.first {
                if kind == "snake" { return snakeGuess() }
                return kindGuess(kind, labels: species, locale: locale)
            }
        }

        for (kind, needles) in kindNeedles {
            if needles.contains(where: { ident.contains($0) }) {
                if kind == "snake" {
                    return snakeGuess()
                }
                let labels = book.labels.filter { $0.kind == kind }
                if labels.count == 1 {
                    return speciesGuess(labels[0], locale: locale)
                }
                return kindGuess(kind, labels: labels, locale: locale)
            }
        }
        return nil
    }

    private static func speciesGuess(_ label: VisionLabel, locale: String) -> VisionGuess {
        VisionGuess(
            labelId: label.id,
            name: label.displayName(locale).uppercased(),
            percent: 0,
            lookalikes: label.lookalikes.map(lookalikeWord),
            leaveIt: label.leaveIt || label.kind == "fungi",
            edible: false,
            noModel: false
        )
    }

    private static func kindGuess(_ kind: String, labels: [VisionLabel], locale: String) -> VisionGuess {
        if kind == "fungi" {
            return fungiGuess(VisionBook(state: "", neverEdibleUnlock: true, fungiDefault: "LEAVE_IT", labels: labels), locale: locale)
        }
        let names = labels.map { $0.displayName(locale).uppercased() }
        let extras = labels.flatMap { $0.lookalikes.map(lookalikeWord) }
        var words: [String] = []
        for word in names + extras where !words.contains(word) {
            words.append(word)
        }
        return VisionGuess(
            labelId: "kind:\(kind)",
            name: kindWord(kind),
            percent: 0,
            lookalikes: Array(words.prefix(4)),
            leaveIt: labels.contains(where: \.leaveIt),
            edible: false,
            noModel: false
        )
    }

    private static func fungiGuess(_ book: VisionBook, locale: String) -> VisionGuess {
        let fungi = book.labels.filter { $0.kind == "fungi" }
        let names = fungi.map { $0.displayName(locale).uppercased() }
        return VisionGuess(
            labelId: "kind:fungi",
            name: "FUNGI",
            percent: 0,
            lookalikes: Array(names.prefix(4)),
            leaveIt: true,
            edible: false,
            noModel: false
        )
    }

    private static func snakeGuess() -> VisionGuess {
        VisionGuess(
            labelId: "kind:snake",
            name: "SNAKE",
            percent: 0,
            lookalikes: [],
            leaveIt: true,
            edible: false,
            noModel: false
        )
    }

    private static func kindWord(_ kind: String) -> String {
        switch kind {
        case "cactus": return "CACTUS"
        case "cacti_yucca": return "YUCCA"
        case "snake": return "SNAKE"
        case "mammal": return "MAMMAL"
        case "tree": return "TREE"
        case "fungi": return "FUNGI"
        default: return kind.uppercased()
        }
    }

    private static func normalize(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private static let fungiNeedles = [
        "mushroom", "fungus", "fungi", "toadstool", "morel", "amanita", "galerina",
    ]

    private static let kindNeedles: [(String, [String])] = [
        ("cactus", ["cactus", "cholla", "opuntia"]),
        ("cacti_yucca", ["yucca", "sotol", "agave"]),
        ("snake", ["rattlesnake", "copperhead", "cottonmouth", "snake", "viper"]),
        ("mammal", ["coyote", "javelina", "peccary", "deer", "elk", "bear", "hog"]),
        ("tree", ["oak", "mesquite", "elm", "pecan", "pine", "pinon", "juniper", "aspen", "cottonwood", "tree"]),
    ]
}
