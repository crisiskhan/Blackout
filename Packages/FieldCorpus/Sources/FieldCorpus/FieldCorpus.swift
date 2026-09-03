import Foundation

public struct FieldLoc: Codable, Equatable, Sendable {
    public var en: String
    public var es: String
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
}

public struct FieldBook: Codable, Equatable, Sendable {
    public var schema: String
    public var id: String
    public var cards: [FieldCard]
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
