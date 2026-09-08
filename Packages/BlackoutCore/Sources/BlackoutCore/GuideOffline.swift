import Foundation

/// On-device ask ranking. Last GPS + biome + calendar month. No WAN.
public enum GuideAskRanker {
    public static func honestyLine(_ context: GuideQueryContext) -> String {
        switch (context.gpsKnown, context.biome) {
        case (false, _):
            return "No GPS. Biome unknown. Month still applied."
        case (true, .unknown):
            return "GPS on. Biome unknown. Month still applied."
        case (true, _):
            return "GPS, biome, and month on this phone."
        }
    }

    public static func apply(
        _ context: GuideQueryContext,
        to scores: inout [String: Double],
        articles: [(id: String, topic: String, tags: [String])]
    ) {
        func boost(id: String, _ amount: Double) {
            scores[id, default: 0] += amount
        }
        func boostTopic(_ topic: String, _ amount: Double) {
            for article in articles where article.topic == topic {
                boost(id: article.id, amount)
            }
        }

        if context.isNight {
            boostTopic("shelter", 2)
            boostTopic("fire", 1.5)
            boostTopic("signaling", 1.5)
        } else if context.hour >= 11 && context.hour <= 16 {
            boostTopic("weather", 1.2)
            boostTopic("water", 0.8)
        }
        if let elev = context.elevationMeters, elev > 2800 {
            boostTopic("weather", 1.8)
            boostTopic("shelter", 1.0)
            boostTopic("first-aid", 0.6)
        }
        if context.batteryLevel >= 0, context.batteryLevel <= 0.15 {
            boostTopic("signaling", 2)
            boostTopic("navigation", 1.2)
        }
        if context.sosArmed {
            boostTopic("signaling", 2.5)
            boostTopic("first-aid", 1.5)
        }
        if context.partySize <= 1 {
            boostTopic("signaling", 1)
            boostTopic("navigation", 0.8)
            boostTopic("bushcraft", 0.5)
        }
        if context.extremeSaver {
            boostTopic("signaling", 1)
            boostTopic("navigation", 1)
        }

        if context.month >= 1, context.month <= 12 {
            switch context.month {
            case 6, 7, 8:
                boostTagged(articles, tokens: ["heat", "hot", "snake", "water", "shade"], amount: 2.2, scores: &scores)
                boostTopic("weather", 0.8)
            case 11, 12, 1, 2:
                boostTagged(articles, tokens: ["frost", "cold", "hypothermia", "snow", "ice"], amount: 2.4, scores: &scores)
                boostTopic("shelter", 1.6)
                boostTopic("fire", 1.2)
            case 3, 4, 5:
                boostTagged(articles, tokens: ["tick", "runoff", "flood"], amount: 1.6, scores: &scores)
                boostTopic("water", 0.8)
            case 9, 10:
                boostTopic("weather", 1.2)
                boostTopic("water", 0.6)
                boostTopic("shelter", 0.6)
            default:
                break
            }
        }

        if context.biome != .unknown {
            let tokens = context.biome.rankTokens
            for article in articles {
                let blob = (article.id + " " + article.tags.joined(separator: " ")).lowercased()
                if tokens.contains(where: { blob.contains($0) }) {
                    boost(id: article.id, 2.8)
                }
            }
        }
    }

    private static func boostTagged(
        _ articles: [(id: String, topic: String, tags: [String])],
        tokens: [String],
        amount: Double,
        scores: inout [String: Double]
    ) {
        for article in articles {
            let blob = (article.id + " " + article.topic + " " + article.tags.joined(separator: " ")).lowercased()
            if tokens.contains(where: { blob.contains($0) }) {
                scores[article.id, default: 0] += amount
            }
        }
    }
}

public enum GuideTriageEntry: String, Sendable {
    case adultKidPartySplit
    case searchBox
}

public enum GuideTriageChoice: String, Sendable, CaseIterable {
    case adult
    case kid
    case partySplit
}

public enum GuideTriageRoute: Equatable, Sendable {
    case adultTree
    case kidModes([FieldJobMode])
    case partySplit
}

/// First question on a medical/lost tree. Not a search box.
public enum GuideTriage {
    public static let entry: GuideTriageEntry = .adultKidPartySplit

    public static func isMedicalOrLost(id: String, topic: String, tags: [String]) -> Bool {
        let blob = ([id, topic] + tags).joined(separator: " ").lowercased()
        if topic == GuideTopic.firstAid.rawValue { return true }
        if id.hasPrefix("aid-") || id.hasPrefix("kid-") { return true }
        if id == "party-split" || id == "situation-lost" || id == "situation-injury" {
            return true
        }
        if id == "heat" || id.hasPrefix("situation-heat") || id.hasPrefix("situation-cold") {
            return true
        }
        return blob.contains("lost") || blob.contains("first-aid") || blob.contains("first aid")
            || blob.contains("bleed") || blob.contains("bite") || blob.contains("split")
    }

    public static func route(
        _ choice: GuideTriageChoice,
        treeID: String,
        tags: [String]
    ) -> GuideTriageRoute {
        switch choice {
        case .adult:
            return .adultTree
        case .partySplit:
            return .partySplit
        case .kid:
            let blob = ([treeID] + tags).joined(separator: " ").lowercased()
            if blob.contains("heat") || blob.contains("hot") {
                return .kidModes([.kidHeat])
            }
            if blob.contains("bite") || blob.contains("snake") || blob.contains("sting") {
                return .kidModes([.kidBite])
            }
            if blob.contains("lost") || blob.contains("split") {
                return .kidModes([.kidLost])
            }
            return .kidModes([.kidLost, .kidHeat, .kidBite])
        }
    }
}

public enum GuideSpeak {
    public static let controlNext = "Next"
    public static let controlStop = "Stop"
    public static let controlHeight: Double = 72

    public static func nextStepOnly(steps: [String], index: Int) -> String? {
        guard steps.indices.contains(index) else { return nil }
        return steps[index]
    }
}

public struct OutingMemory: Equatable, Codable, Sendable {
    public var outingID: String
    public var weightKg: Double?
    public var allergyNote: String?
    public var hasAllergyAnswer: Bool

    public static let shipsOffDevice = false

    public var shouldAskWeight: Bool { weightKg == nil }
    public var shouldAskAllergy: Bool { !hasAllergyAnswer }

    public init(outingID: String, weightKg: Double? = nil, allergyNote: String? = nil, hasAllergyAnswer: Bool = false) {
        self.outingID = outingID
        self.weightKg = weightKg
        self.allergyNote = allergyNote
        self.hasAllergyAnswer = hasAllergyAnswer
    }

    public mutating func rememberWeight(_ kg: Double) {
        weightKg = kg
    }

    public mutating func rememberAllergy(_ note: String) {
        allergyNote = note
        hasAllergyAnswer = true
    }
}

public enum OutingMemoryStore {
    public static func load(defaults: UserDefaults = .standard) -> OutingMemory {
        guard let data = defaults.data(forKey: BlackoutKeys.outingMemory),
              let memory = try? JSONDecoder().decode(OutingMemory.self, from: data) else {
            return OutingMemory(outingID: "")
        }
        return memory
    }

    public static func save(_ memory: OutingMemory, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(memory) {
            defaults.set(data, forKey: BlackoutKeys.outingMemory)
        }
    }

    public static func clearIfOutingEnded(openExpeditionID: String?, defaults: UserDefaults = .standard) {
        guard let openExpeditionID, !openExpeditionID.isEmpty else {
            defaults.removeObject(forKey: BlackoutKeys.outingMemory)
            return
        }
        var memory = load(defaults: defaults)
        if memory.outingID != openExpeditionID {
            defaults.removeObject(forKey: BlackoutKeys.outingMemory)
            memory = OutingMemory(outingID: openExpeditionID)
            save(memory, defaults: defaults)
        }
    }
}

public struct GuideCarePin: Equatable, Sendable {
    public var stopIf: String?
    public var getToCare: String?

    public var firstLine: String? {
        switch (stopIf, getToCare) {
        case let (stop?, care?):
            return "Stop if: \(stop)  Get to care: \(care)"
        case let (stop?, nil):
            return "Stop if: \(stop)"
        case let (nil, care?):
            return "Get to care: \(care)"
        case (nil, nil):
            return nil
        }
    }
}

public enum GuideCarePinParser {
    public static func parse(_ body: String) -> GuideCarePin {
        let stopHeading = section(named: ["Stop if", "Stop-if"], in: body)
        let careHeading = section(named: ["Get to care", "Get-to-care"], in: body)
        let stopIf = firstSentence(stopHeading) ?? firstCaution(in: body)
        let getToCare = firstSentence(careHeading) ?? firstGetToCare(in: body)
        return GuideCarePin(stopIf: stopIf, getToCare: getToCare)
    }

    private static func section(named names: [String], in body: String) -> String? {
        let lines = body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var capture: [String] = []
        var on = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let title = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if on { break }
                on = names.contains { title.compare($0, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
                continue
            }
            if on { capture.append(trimmed) }
        }
        let text = capture.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func firstCaution(in body: String) -> String? {
        guard let block = section(named: ["Cautions", "Caution"], in: body) else { return nil }
        return bulletOrSentence(block)
    }

    private static func firstGetToCare(in body: String) -> String? {
        let lower = body.lowercased()
        let keys = ["get to care", "get-to-care"]
        guard let range = keys.compactMap({ lower.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else {
            return nil
        }
        return sentence(at: range.lowerBound, in: body)
    }

    private static func firstSentence(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return bulletOrSentence(text)
    }

    private static func bulletOrSentence(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            let first = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
            return String(first.drop(while: { $0 == "-" || $0 == "*" || $0 == " " }))
                .trimmingCharacters(in: .whitespaces)
        }
        return sentence(at: trimmed.startIndex, in: trimmed)
    }

    private static func sentence(at index: String.Index, in text: String) -> String? {
        var start = index
        while start > text.startIndex {
            let prev = text.index(before: start)
            if text[prev] == "." || text[prev] == "\n" { break }
            start = prev
        }
        while start < text.endIndex, text[start].isWhitespace || text[start].isNewline || text[start] == "-" {
            start = text.index(after: start)
        }
        var end = start
        while end < text.endIndex, text[end] != "." {
            end = text.index(after: end)
        }
        if end < text.endIndex { end = text.index(after: end) }
        let slice = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return slice.isEmpty ? nil : slice
    }
}

public enum GuideTreeText {
    public static func doSteps(in body: String) -> [String] {
        numberedItems(in: section(named: "Do", in: body) ?? body)
    }

    public static func cautionItems(in body: String) -> [String] {
        let block = section(named: "Cautions", in: body) ?? ""
        return block.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") { return String(trimmed.dropFirst(2)) }
            if trimmed.hasPrefix("* ") { return String(trimmed.dropFirst(2)) }
            return nil
        }
    }

    private static func section(named name: String, in body: String) -> String? {
        let lines = body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var capture: [String] = []
        var on = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let title = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if on { break }
                on = title.compare(name, options: .caseInsensitive) == .orderedSame
                continue
            }
            if on { capture.append(line) }
        }
        let text = capture.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func numberedItems(in text: String) -> [String] {
        var items: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            var index = line.startIndex
            var digits = 0
            while index < line.endIndex, line[index].isNumber {
                digits += 1
                index = line.index(after: index)
            }
            guard digits > 0, index < line.endIndex, line[index] == "." else { continue }
            let after = line.index(after: index)
            guard after < line.endIndex, line[after] == " " else { continue }
            items.append(String(line[line.index(after: after)...]))
        }
        return items
    }
}

public struct OutingGearRoster: Equatable, Codable, Sendable {
    public var checked: Set<String>

    public var isEmpty: Bool { checked.isEmpty }

    public init(checked: Set<String> = []) {
        self.checked = Set(checked.map { Self.normalize($0) })
    }

    public func has(_ name: String) -> Bool {
        checked.contains(Self.normalize(name))
    }

    public mutating func set(_ name: String, on: Bool) {
        let key = Self.normalize(name)
        if on { checked.insert(key) } else { checked.remove(key) }
    }

    public static let namedKitItems = ["tourniquet", "gauze", "filter"]

    public static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public enum OutingGearStore {
    public static func load(defaults: UserDefaults = .standard) -> OutingGearRoster {
        guard let data = defaults.data(forKey: BlackoutKeys.outingGear),
              let roster = try? JSONDecoder().decode(OutingGearRoster.self, from: data) else {
            return OutingGearRoster()
        }
        return roster
    }

    public static func save(_ roster: OutingGearRoster, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(roster) {
            defaults.set(data, forKey: BlackoutKeys.outingGear)
        }
    }

    public static func clearIfOutingEnded(openExpeditionID: String?, defaults: UserDefaults = .standard) {
        if openExpeditionID == nil {
            defaults.removeObject(forKey: BlackoutKeys.outingGear)
        }
    }
}

public enum GuideGearBranch: String, Sendable {
    case kit
    case improvise
    case honestEmpty
}

public enum GuideGearAware {
    public static func select(steps: [String], gear: OutingGearRoster) -> (branch: GuideGearBranch, steps: [String]) {
        let named = OutingGearRoster.namedKitItems
        let missing = named.filter { !gear.has($0) }
        let branch: GuideGearBranch
        if gear.isEmpty {
            branch = .honestEmpty
        } else if missing.contains("tourniquet") || steps.contains(where: { isKit($0) && mentionsMissing($0, missing: missing) }) {
            branch = .improvise
        } else if steps.contains(where: { isKit($0) && !mentionsMissing($0, missing: missing) }) {
            branch = .kit
        } else {
            branch = missing.isEmpty ? .kit : .improvise
        }

        var kept: [String] = []
        for step in steps {
            if isKit(step), branch != .kit {
                continue
            }
            kept.append(step)
        }
        if branch != .kit, !kept.contains(where: { $0.lowercased().contains("improvise") }) {
            kept.insert("Improvise — no tourniquet on this outing list. Keep pressure and pack.", at: min(1, kept.count))
        }
        if branch == .honestEmpty, !kept.contains(where: { $0.lowercased().contains("gear list empty") }) {
            kept.insert("Gear list empty. Showing improvise steps.", at: 0)
        }
        return (branch, kept)
    }

    private static func isKit(_ step: String) -> Bool {
        let lower = step.lowercased()
        if lower.contains("improvise") { return false }
        return OutingGearRoster.namedKitItems.contains { lower.contains($0) }
    }

    private static func mentionsMissing(_ step: String, missing: [String]) -> Bool {
        let lower = step.lowercased()
        return missing.contains { lower.contains($0) }
    }
}

public struct GuideVisionReading: Equatable, Sendable {
    public var label: String
    public var idPercent: Int
    public var lookalikePercent: Int
    public var lookalikeName: String
    public var isUnknown: Bool
    public var eatVerdict: String?

    public init(
        label: String,
        idPercent: Int,
        lookalikePercent: Int,
        lookalikeName: String,
        isUnknown: Bool,
        eatVerdict: String? = nil
    ) {
        self.label = label
        self.idPercent = idPercent
        self.lookalikePercent = lookalikePercent
        self.lookalikeName = lookalikeName
        self.isUnknown = isUnknown
        self.eatVerdict = nil
    }
}

public enum GuideVisionID {
    public static let neverEatVerdict = true

    public static func parse(title: String, body: String) -> GuideVisionReading? {
        let pattern = #"ID confidence \(typical visual\):\s*(\d+)%\.\s*Runner-up/lookalike:\s*(\d+)%\s*\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: body, options: [], range: NSRange(body.startIndex..., in: body)),
              let idRange = Range(match.range(at: 1), in: body),
              let lookRange = Range(match.range(at: 2), in: body),
              let nameRange = Range(match.range(at: 3), in: body),
              let idPercent = Int(body[idRange]),
              let lookalikePercent = Int(body[lookRange]) else {
            return nil
        }
        let unknown = title.lowercased().contains("unknown")
        return GuideVisionReading(
            label: title,
            idPercent: idPercent,
            lookalikePercent: lookalikePercent,
            lookalikeName: String(body[nameRange]),
            isUnknown: unknown
        )
    }

    public static func unknownReading(biome: GuideBiome) -> GuideVisionReading {
        let lookalike: String
        switch biome {
        case .florida: lookalike = "saw palmetto"
        case .texas: lookalike = "creosote"
        case .newMexico: lookalike = "creosote"
        case .newYork: lookalike = "sugar maple"
        case .southernRockies: lookalike = "ponderosa"
        case .unknown: lookalike = "unknown"
        }
        return GuideVisionReading(
            label: "Unknown",
            idPercent: 8,
            lookalikePercent: 8,
            lookalikeName: lookalike,
            isUnknown: true
        )
    }

    public static func deckPrefix(for biome: GuideBiome) -> String? {
        switch biome {
        case .florida: return "fl"
        case .texas: return "tx"
        case .newMexico: return "nm"
        case .newYork: return "ny"
        case .southernRockies, .unknown: return nil
        }
    }
}

public struct GuidePictogram: Equatable, Sendable, Identifiable {
    public var id: String { systemName + spoken }
    public var systemName: String
    public var spoken: String
}

public enum GuidePictogramSteps {
    public static let usesSOSChrome = true
    public static let textStillAvailable = true

    public static func symbols(for steps: [String]) -> [GuidePictogram] {
        steps.map { step in
            GuidePictogram(systemName: symbol(for: step), spoken: step)
        }
    }

    public static func symbol(for step: String) -> String {
        let lower = step.lowercased()
        if lower.contains("whistle") || lower.contains("signal") || lower.contains("blast") {
            return "speaker.wave.3.fill"
        }
        if lower.contains("stop") || lower.contains("sit") || lower.contains("mark") || lower.contains("group") {
            return "hand.raised.fill"
        }
        if lower.contains("care") || lower.contains("hospital") {
            return "cross.case.fill"
        }
        if lower.contains("shade") || lower.contains("sun") {
            return "sun.max.fill"
        }
        if lower.contains("fire") || lower.contains("spark") || lower.contains("flame") {
            return "flame.fill"
        }
        if lower.contains("shelter") || lower.contains("tarp") || lower.contains("hut") {
            return "tent.fill"
        }
        if lower.contains("water") || lower.contains("sip") || lower.contains("bleed") || lower.contains("pressure") {
            return "drop.fill"
        }
        if lower.contains("walk") || lower.contains("descend") {
            return "figure.walk"
        }
        return "circle.fill"
    }
}

public enum GuideMapJob: String, Sendable, CaseIterable, Identifiable {
    case findWater
    case findCivilization
    case lastMark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .findWater: return "Find water"
        case .findCivilization: return "Find civilization"
        case .lastMark: return "Last MARK"
        }
    }

    public static func jobs(forArticleID id: String, tags: [String], topic: String) -> [GuideMapJob] {
        let blob = ([id, topic] + tags).joined(separator: " ").lowercased()
        var jobs: [GuideMapJob] = []
        if topic == "water" || blob.contains("find water") || blob.contains("creek") && topic == "water" {
            jobs.append(.findWater)
        } else if blob.contains("find water") {
            jobs.append(.findWater)
        }
        if blob.contains("lost") || blob.contains("civilization") || topic == "navigation" {
            jobs.append(.findCivilization)
        }
        if GuideTriage.isMedicalOrLost(id: id, topic: topic, tags: tags) || blob.contains("lost") {
            jobs.append(.lastMark)
        }
        return jobs
    }
}

public enum GuideDoAlongKind: String, Sendable {
    case fire
    case shelter
    case water
}

public enum GuideDoAlong {
    public static let isGame = false
    public static let awardsXP = false
    public static let hardStopCopy = "That's enough, walk."

    public static func classify(id: String, tags: [String], topic: String) -> GuideDoAlongKind? {
        let blob = ([id, topic] + tags).joined(separator: " ").lowercased()
        if blob.contains("knot") || blob.contains("bowline") || blob.contains("trucker") || blob.contains("cordage") {
            return nil
        }
        if topic == "fire" || blob.contains("ferro") || blob.contains("feather") || blob.contains("wet fire")
            || id.contains("fire") {
            return .fire
        }
        if topic == "shelter" || blob.contains("debris") || blob.contains("lean-to") || blob.contains("tarp")
            || blob.contains("snow trench") || id.contains("shelter") {
            return .shelter
        }
        if topic == "water" || blob.contains("boil") || blob.contains("prefilter") || id.contains("water") {
            return .water
        }
        return nil
    }

    public static func hardStopSeconds(for kind: GuideDoAlongKind) -> TimeInterval {
        switch kind {
        case .fire, .shelter, .water:
            return 600
        }
    }

    public static func shouldHardStop(elapsed: TimeInterval, kind: GuideDoAlongKind) -> Bool {
        elapsed >= hardStopSeconds(for: kind)
    }
}
