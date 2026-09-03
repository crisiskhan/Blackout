import Foundation
import BlackBox

public final class OfflineSpeech: @unchecked Sendable {
    public private(set) var lastUtterance: String = ""
    private let box: BlackBox
    public init(box: BlackBox) { self.box = box }
    public func speak(_ text: String, locale: String) {
        lastUtterance = "\(locale):\(text)"
        box.log("speech", lastUtterance)
    }
}
