import Foundation
import FieldCorpus

public struct StepperState: Equatable, Sendable {
    public var card: FieldCard
    public var index: Int
    public var speaking: Bool
    public var sentToParty: Bool

    public init(card: FieldCard, index: Int, speaking: Bool, sentToParty: Bool) {
        self.card = card
        self.index = index
        self.speaking = speaking
        self.sentToParty = sentToParty
    }

    public var step: FieldStep {
        if card.steps.indices.contains(index) {
            return card.steps[index]
        }
        if let first = card.steps.first {
            return first
        }
        return FieldStep(
            do: FieldLoc(en: "", es: ""),
            why: FieldLoc(en: "", es: ""),
            child: FieldLoc(en: "", es: ""),
            stop: FieldLoc(en: "", es: ""),
            image: ""
        )
    }
    public var isLast: Bool {
        card.steps.count <= 1 || index >= card.steps.count - 1
    }
    public mutating func next() { if !isLast { index += 1 } }
    public mutating func speak() { speaking = card.speak }
    public mutating func send() { sentToParty = card.sendToParty }
}
