import Foundation
import Vitals
import BlackBox

public final class RedPlate: @unchecked Sendable {
    public private(set) var isRed = false
    public private(set) var cancelled = false
    private let box: BlackBox
    public init(box: BlackBox) { self.box = box }

    public func apply(_ v: PartyVitals) {
        if v.band == .red {
            isRed = true
            cancelled = false
            box.log("red", "plate on")
        }
    }

    public func cancelRED() {
        isRed = false
        cancelled = true
        box.log("red", "cancelled")
    }
}
