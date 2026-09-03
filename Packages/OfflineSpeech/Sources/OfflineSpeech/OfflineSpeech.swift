import Foundation
import BlackBox

public final class SpeechEngine: @unchecked Sendable {
    public private(set) var lastUtterance: String = ""
    private let box: EventLog
    public init(box: EventLog) { self.box = box }
    public func speak(_ text: String, locale: String) {
        lastUtterance = "\(locale):\(text)"
        box.log("speech", lastUtterance)
    }
}
