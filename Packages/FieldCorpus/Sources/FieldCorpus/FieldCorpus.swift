import Foundation

// A struct's memberwise init is internal even when the struct is public, so
// these could be decoded from the shipped corpus but never built in code. That
// is what left the FieldSpeech and FieldStepper suites uncompilable, and so
// unrun.

public struct FieldLoc: Codable, Equatable, Sendable {
    public var en: String
    public var es: String

    public init(en: String, es: String) {
        self.en = en
        self.es = es
    }
}

public struct FieldStep: Codable, Equatable, Sendable {
    public var `do`: FieldLoc
    public var why: FieldLoc
    public var child: FieldLoc
    public var stop: FieldLoc
    public var image: String
    public var tickSeconds: Int?
    public var metronomeBpm: Int?
    public var party: [String: String]?

    public init(
        do doStep: FieldLoc,
        why: FieldLoc,
        child: FieldLoc,
        stop: FieldLoc,
        image: String,
        tickSeconds: Int? = nil,
        metronomeBpm: Int? = nil,
        party: [String: String]? = nil
    ) {
        self.do = doStep
        self.why = why
        self.child = child
        self.stop = stop
        self.image = image
        self.tickSeconds = tickSeconds
        self.metronomeBpm = metronomeBpm
        self.party = party
    }
}

public struct FieldCard: Codable, Equatable, Sendable, Identifiable {
    public var schema: String
    public var id: String
    public var category: String
    public var states: [String]
    public var title: FieldLoc
    public var situation: FieldLoc
    public var stop_if: [FieldLoc]
    public var get_to_care: FieldLoc
    public var speak: Bool
    public var sendToParty: Bool
    public var steps: [FieldStep]

    public init(
        schema: String,
        id: String,
        category: String,
        states: [String],
        title: FieldLoc,
        situation: FieldLoc,
        stop_if: [FieldLoc],
        get_to_care: FieldLoc,
        speak: Bool,
        sendToParty: Bool,
        steps: [FieldStep]
    ) {
        self.schema = schema
        self.id = id
        self.category = category
        self.states = states
        self.title = title
        self.situation = situation
        self.stop_if = stop_if
        self.get_to_care = get_to_care
        self.speak = speak
        self.sendToParty = sendToParty
        self.steps = steps
    }
}

public struct FieldBook: Codable, Equatable, Sendable {
    public var schema: String
    public var id: String
    public var cards: [FieldCard]

    public init(schema: String, id: String, cards: [FieldCard]) {
        self.schema = schema
        self.id = id
        self.cards = cards
    }
}

public enum FieldCorpus {
    public static func load(core: Data, state: Data) throws -> [FieldCard] {
        let c = try JSONDecoder().decode(FieldBook.self, from: core)
        let s = try JSONDecoder().decode(FieldBook.self, from: state)
        let all = c.cards + s.cards
        for card in all {
            guard card.schema == "1.4" else { throw FieldError.schema }
            guard !card.steps.isEmpty else { throw FieldError.emptySteps }
            for st in card.steps {
                if st.`do`.en.isEmpty || st.image.isEmpty { throw FieldError.incompleteStep }
            }
        }
        return all
    }

    public static func visible(_ cards: [FieldCard], state: String) -> [FieldCard] {
        cards.filter { $0.states.contains(state) }
    }
}

public enum FieldError: Error { case schema, emptySteps, incompleteStep }
