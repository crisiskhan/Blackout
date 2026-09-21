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
        var best: (VisionGuess, Int)?
        for obs in usable {
            guard let hit = match(obs.identifier, book: book, locale: locale) else { continue }
            let rank = specificity(hit)
            if let current = best {
                if rank > current.1 {
                    best = (hit, rank)
                }
            } else {
                best = (hit, rank)
            }
        }
        guard let picked = best?.0 else { return unknownGuess() }
        return sealed(picked)
    }

    public static func lookalikeWord(_ raw: String) -> String {
        raw.replacingOccurrences(of: "-lookalike", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .uppercased()
    }

    /// Apple's classifier often ranks Plant/Tree above Cactus or a mushroom
    /// on a log. A generic tree needle must not beat the book kind the still
    /// also named. Fungi, snake, sting, and gator stay leave-it even when
    /// tree scored higher. Water and cactus beat a lone tree on the same still.
    private static func specificity(_ guess: VisionGuess) -> Int {
        switch kindRank(guess) {
        case .fungi: return 50
        case .snake: return 40
        case .wound: return 39
        case .sting: return 38
        case .fire: return 37
        case .gator: return 36
        case .lizard: return 36
        case .frog: return 36
        case .cactus: return 35
        case .flood: return 34
        case .fish: return 33
        case .turtle: return 33
        case .lightning: return 32
        case .water: return 31
        case .smoke: return 30
        case .specific: return 29
        case .ice: return 28
        case .shelter: return 27
        case .bird: return 26
        case .tree: return 10
        }
    }

    private enum KindRank {
        case fungi
        case snake
        case wound
        case sting
        case fire
        case gator
        case lizard
        case frog
        case cactus
        case flood
        case lightning
        case water
        case smoke
        case specific
        case ice
        case shelter
        case bird
        case fish
        case turtle
        case tree
    }

    private enum MatchKind: String {
        case cactus
        case cactiYucca = "cacti_yucca"
        case snake
        case mammal
        case tree
        case fungi
        case sting
        case gator
        case water
        case fire
        case flood
        case ice
        case smoke
        case lightning
        case shelter
        case wound
        case bird
        case fish
        case lizard
        case turtle
        case frog
    }

    private static func kindRank(_ guess: VisionGuess) -> KindRank {
        let id = guess.labelId
        if guess.name == "FUNGI" || id.contains("fungi") || id.contains("amanita")
            || id.contains("galerina") || id.contains("morel") || id.hasSuffix("jack")
        {
            return .fungi
        }
        if guess.name == "SNAKE" || id.contains("snake") || id.contains("diamondback")
            || id.contains("rattler") || id.contains("copperhead") || id.contains("cottonmouth")
        {
            return .snake
        }
        if guess.name == "STING" || id.contains("sting") || id.contains("scorpion") {
            return .sting
        }
        if guess.name == "GATOR" || id.contains("gator") || id.contains("alligator")
            || id.contains("crocodile")
        {
            return .gator
        }
        if guess.name == "LIZARD" || id == "kind:lizard" || id.contains("gila") {
            return .lizard
        }
        if guess.name == "FROG" || id == "kind:frog" || id.contains("toad") {
            return .frog
        }
        if id == "kind:cactus" || id == "kind:cacti_yucca" || id.contains("cactus")
            || id.contains("prickly") || id.contains("cholla") || id.contains("yucca")
            || id.contains("sotol") || guess.name == "CACTUS" || guess.name == "YUCCA"
        {
            return .cactus
        }
        if guess.name == "WATER" || id == "kind:water" {
            return .water
        }
        if guess.name == "FIRE" || id == "kind:fire" || id.contains("wildfire") {
            return .fire
        }
        if guess.name == "FLOOD" || id == "kind:flood" {
            return .flood
        }
        if guess.name == "ICE" || id == "kind:ice" {
            return .ice
        }
        if guess.name == "SMOKE" || id == "kind:smoke" {
            return .smoke
        }
        if guess.name == "LIGHTNING" || id == "kind:lightning" {
            return .lightning
        }
        if guess.name == "SHELTER" || id == "kind:shelter" {
            return .shelter
        }
        if guess.name == "WOUND" || id == "kind:wound" || id.contains("bleed") {
            return .wound
        }
        if guess.name == "BIRD" || id == "kind:bird" || id.contains("turkey")
            || id.contains("quail") || id.contains("dove")
        {
            return .bird
        }
        if guess.name == "FISH" || id == "kind:fish" || id.contains("bass")
            || id.contains("catfish") || id.contains("trout")
        {
            return .fish
        }
        if guess.name == "TURTLE" || id == "kind:turtle" {
            return .turtle
        }
        if id == "kind:tree" || guess.name == "TREE" {
            return .tree
        }
        return .specific
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
        if g.labelId.contains("sting") || g.name == "STING" {
            g.leaveIt = true
        }
        if g.labelId.contains("gator") || g.name == "GATOR" {
            g.leaveIt = true
        }
        if g.labelId.contains("fire") || g.name == "FIRE" {
            g.leaveIt = true
        }
        if g.labelId.contains("smoke") || g.name == "SMOKE" {
            g.leaveIt = true
        }
        if g.labelId.contains("lightning") || g.name == "LIGHTNING" {
            g.leaveIt = true
        }
        if g.labelId.contains("wound") || g.name == "WOUND" {
            g.leaveIt = true
        }
        if g.labelId.contains("lizard") || g.labelId.contains("gila") || g.name == "LIZARD" {
            g.leaveIt = true
        }
        if g.labelId.contains("frog") || g.name == "FROG" || g.labelId.contains("toad") {
            g.leaveIt = true
        }
        return g
    }

    private static func match(_ identifier: String, book: VisionBook, locale: String) -> VisionGuess? {
        let ident = normalize(identifier)
        if fungiNeedles.contains(where: { hasPhrase(ident, $0) }) {
            return fungiGuess(book, locale: locale)
        }
        if ident.contains("javelina") || ident.contains("peccary") {
            if let javelina = book.labels.first(where: {
                $0.id.contains("javelina") || normalize($0.displayName("en")).contains("javelina")
            }) {
                return speciesGuess(javelina, locale: locale)
            }
        }

        let species = book.labels.filter { label in
            if label.kind == "fungi" { return false }
            if genericIdents.contains(ident) { return false }
            let names = label.name.values.map(normalize)
            let shortId = normalize(
                label.id
                    .replacingOccurrences(of: "tx-", with: "")
                    .replacingOccurrences(of: "nm-", with: "")
            )
            return names.contains(where: {
                !$0.isEmpty && (hasPhrase(ident, $0) || (hasPhrase($0, ident) && ident.count >= 4))
            })
                || (!shortId.isEmpty && hasPhrase(ident, shortId))
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
            if needles.contains(where: { hasPhrase(ident, $0) }) {
                switch kind {
                case .snake:
                    return snakeGuess()
                case .sting:
                    return stingGuess()
                case .gator:
                    return gatorGuess()
                case .water:
                    return waterGuess()
                case .fire:
                    return namedGuess("kind:fire", "FIRE", leaveIt: true)
                case .flood:
                    return namedGuess("kind:flood", "FLOOD", leaveIt: false)
                case .ice:
                    return namedGuess("kind:ice", "ICE", leaveIt: false)
                case .smoke:
                    return namedGuess("kind:smoke", "SMOKE", leaveIt: true)
                case .lightning:
                    return namedGuess("kind:lightning", "LIGHTNING", leaveIt: true)
                case .shelter:
                    return namedGuess("kind:shelter", "SHELTER", leaveIt: false)
                case .wound:
                    return namedGuess("kind:wound", "WOUND", leaveIt: true)
                case .bird:
                    return namedGuess("kind:bird", "BIRD", leaveIt: false)
                case .fish:
                    return namedGuess("kind:fish", "FISH", leaveIt: false)
                case .lizard:
                    return namedGuess("kind:lizard", "LIZARD", leaveIt: true)
                case .turtle:
                    return namedGuess("kind:turtle", "TURTLE", leaveIt: false)
                case .frog:
                    return namedGuess("kind:frog", "FROG", leaveIt: true)
                case .fungi:
                    return fungiGuess(book, locale: locale)
                case .cactus, .cactiYucca, .mammal, .tree:
                    let labels = book.labels.filter { $0.kind == kind.rawValue }
                    return kindGuess(kind, labels: labels, locale: locale)
                }
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
        if let match = MatchKind(rawValue: kind) {
            return kindGuess(match, labels: labels, locale: locale)
        }
        let names = labels.map { $0.displayName(locale).uppercased() }
        let extras = labels.flatMap { $0.lookalikes.map(lookalikeWord) }
        var words: [String] = []
        for word in names + extras where !words.contains(word) {
            words.append(word)
        }
        return VisionGuess(
            labelId: "kind:\(kind)",
            name: kind.uppercased(),
            percent: 0,
            lookalikes: Array(words.prefix(4)),
            leaveIt: labels.contains(where: \.leaveIt),
            edible: false,
            noModel: false
        )
    }

    private static func kindGuess(_ kind: MatchKind, labels: [VisionLabel], locale: String) -> VisionGuess {
        switch kind {
        case .fungi:
            return fungiGuess(
                VisionBook(state: "", neverEdibleUnlock: true, fungiDefault: "LEAVE_IT", labels: labels),
                locale: locale
            )
        case .snake:
            return snakeGuess()
        case .sting:
            return stingGuess()
        case .gator:
            return gatorGuess()
        case .water:
            return waterGuess()
        case .fire:
            return namedGuess("kind:fire", "FIRE", leaveIt: true)
        case .flood:
            return namedGuess("kind:flood", "FLOOD", leaveIt: false)
        case .ice:
            return namedGuess("kind:ice", "ICE", leaveIt: false)
        case .smoke:
            return namedGuess("kind:smoke", "SMOKE", leaveIt: true)
        case .lightning:
            return namedGuess("kind:lightning", "LIGHTNING", leaveIt: true)
        case .shelter:
            return namedGuess("kind:shelter", "SHELTER", leaveIt: false)
        case .wound:
            return namedGuess("kind:wound", "WOUND", leaveIt: true)
        case .bird:
            return namedGuess("kind:bird", "BIRD", leaveIt: false)
        case .fish:
            return namedGuess("kind:fish", "FISH", leaveIt: false)
        case .lizard:
            return namedGuess("kind:lizard", "LIZARD", leaveIt: true)
        case .turtle:
            return namedGuess("kind:turtle", "TURTLE", leaveIt: false)
        case .frog:
            return namedGuess("kind:frog", "FROG", leaveIt: true)
        case .cactus, .cactiYucca, .mammal, .tree:
            let names = labels.map { $0.displayName(locale).uppercased() }
            let extras = labels.flatMap { $0.lookalikes.map(lookalikeWord) }
            var words: [String] = []
            for word in names + extras where !words.contains(word) {
                words.append(word)
            }
            return VisionGuess(
                labelId: "kind:\(kind.rawValue)",
                name: kindWord(kind),
                percent: 0,
                lookalikes: Array(words.prefix(4)),
                leaveIt: labels.contains(where: \.leaveIt),
                edible: false,
                noModel: false
            )
        }
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

    private static func stingGuess() -> VisionGuess {
        VisionGuess(
            labelId: "kind:sting",
            name: "STING",
            percent: 0,
            lookalikes: [],
            leaveIt: true,
            edible: false,
            noModel: false
        )
    }

    private static func gatorGuess() -> VisionGuess {
        VisionGuess(
            labelId: "kind:gator",
            name: "GATOR",
            percent: 0,
            lookalikes: [],
            leaveIt: true,
            edible: false,
            noModel: false
        )
    }

    private static func waterGuess() -> VisionGuess {
        VisionGuess(
            labelId: "kind:water",
            name: "WATER",
            percent: 0,
            lookalikes: [],
            leaveIt: false,
            edible: false,
            noModel: false
        )
    }

    private static func namedGuess(_ id: String, _ name: String, leaveIt: Bool) -> VisionGuess {
        VisionGuess(
            labelId: id,
            name: name,
            percent: 0,
            lookalikes: [],
            leaveIt: leaveIt,
            edible: false,
            noModel: false
        )
    }

    private static func kindWord(_ kind: MatchKind) -> String {
        switch kind {
        case .cactus: return "CACTUS"
        case .cactiYucca: return "YUCCA"
        case .snake: return "SNAKE"
        case .mammal: return "MAMMAL"
        case .tree: return "TREE"
        case .fungi: return "FUNGI"
        case .sting: return "STING"
        case .gator: return "GATOR"
        case .water: return "WATER"
        case .fire: return "FIRE"
        case .flood: return "FLOOD"
        case .ice: return "ICE"
        case .smoke: return "SMOKE"
        case .lightning: return "LIGHTNING"
        case .shelter: return "SHELTER"
        case .wound: return "WOUND"
        case .bird: return "BIRD"
        case .fish: return "FISH"
        case .lizard: return "LIZARD"
        case .turtle: return "TURTLE"
        case .frog: return "FROG"
        }
    }

    private static func normalize(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    /// Unspaced needles are whole words. "hog" is not hedgehog, "pine" is not
    /// porcupine, "tree" is not street, "spring" is not springfield.
    private static func hasPhrase(_ hay: String, _ needle: String) -> Bool {
        if needle.contains(" ") {
            return hay.contains(needle)
        }
        var words: [String] = []
        var current = ""
        for ch in hay {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.contains(needle)
    }

    private static let genericIdents: Set<String> = [
        "wood", "plant", "animal", "flower", "leaf", "fruit", "food", "wildlife",
        "flora", "fauna", "nature", "street", "road",
    ]

    private static let fungiNeedles = [
        "mushroom", "fungus", "fungi", "toadstool", "morel", "amanita", "galerina",
        "puffball", "bracket",
    ]

    private static let kindNeedles: [(MatchKind, [String])] = [
        (.cactus, ["cactus", "cholla", "opuntia", "succulent", "saguaro", "nopal", "prickly pear"]),
        (.cactiYucca, ["yucca", "sotol", "agave"]),
        (.snake, ["rattlesnake", "copperhead", "cottonmouth", "snake", "viper", "serpent", "sidewinder", "rattler"]),
        (.sting, ["scorpion", "tarantula", "wasp", "bee", "hornet", "yellowjacket", "yellow jacket", "bumblebee"]),
        (.gator, ["alligator", "crocodile", "caiman", "gator"]),
        (.mammal, [
            "coyote", "javelina", "peccary", "deer", "elk", "bear", "hog", "boar",
            "fox", "bobcat", "cougar", "mountain lion", "puma", "raccoon", "skunk",
            "armadillo", "rabbit", "jackrabbit", "pronghorn", "wolf",
            "squirrel", "opossum", "beaver", "bison", "badger", "ringtail",
        ]),
        (.water, [
            "lake", "pond", "reservoir", "creek", "river", "spring", "waterfall",
            "lagoon", "stream", "ocean", "water",
        ]),
        (.fire, ["wildfire", "bushfire", "forest fire", "grass fire", "brush fire"]),
        (.flood, ["flood", "flash flood"]),
        (.ice, ["ice", "glacier", "frost"]),
        (.smoke, ["smoke", "smoke plume"]),
        (.lightning, ["lightning", "thunderstorm", "thunderbolt"]),
        (.shelter, ["tent", "campsite", "bivouac"]),
        (.wound, ["open wound", "bleeding wound", "laceration", "gash"]),
        (.tree, ["oak", "mesquite", "elm", "pecan", "pine", "pinon", "juniper", "aspen", "cottonwood", "tree"]),
        (.bird, [
            "turkey", "quail", "dove", "roadrunner", "hawk", "eagle", "owl",
            "duck", "goose", "vulture", "raven", "crow", "pigeon", "pheasant",
            "heron", "egret", "crane", "jay", "woodpecker", "hummingbird",
            "mockingbird", "cardinal", "sparrow", "wren", "swallow",
            "nighthawk", "chicken", "grouse", "teal", "pelican", "cormorant",
            "kingfisher", "sandpiper", "bird",
        ]),
        (.fish, [
            "bass", "catfish", "trout", "sunfish", "perch", "carp", "gar",
            "minnow", "crappie", "bluegill", "walleye", "drum", "shad",
            "bowfin", "tilapia", "fish",
        ]),
        (.lizard, [
            "gila monster", "gila", "horned lizard", "collared lizard",
            "whiptail", "gecko", "skink", "anole", "chuckwalla", "racerunner",
            "lizard",
        ]),
        (.turtle, [
            "softshell", "slider", "terrapin", "tortoise", "cooter",
            "snapping turtle", "box turtle", "mud turtle", "turtle",
        ]),
        (.frog, [
            "bullfrog", "toad", "treefrog", "tree frog", "spadefoot",
            "chorus frog", "leopard frog", "frog",
        ]),
    ]
}
