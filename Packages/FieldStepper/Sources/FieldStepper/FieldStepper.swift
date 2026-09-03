import Foundation
import FieldCorpus

public struct StepperState: Equatable, Sendable {
    public var card: FieldCard
    public var index: Int
    public var speaking: Bool
    public var sentToParty: Bool
    public var step: FieldStep { card.steps[index] }
    public var isLast: Bool { index == card.steps.count - 1 }
    public mutating func next() { if !isLast { index += 1 } }
    public mutating func speak() { speaking = card.speak }
    public mutating func send() { sentToParty = card.sendToParty }
}
