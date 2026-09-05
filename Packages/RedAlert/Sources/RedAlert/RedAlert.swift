import Foundation
import Vitals
import BlackBox

public final class RedPlate: @unchecked Sendable {
    public private(set) var isRed = false
    public private(set) var cancelled = false
    private let box: EventLog
    public init(box: EventLog) { self.box = box }

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

    public func force(_ on: Bool) {
        isRed = on
        cancelled = !on
        box.log("red", on ? "plate on remote" : "cancelled remote")
    }

    public func isSOS() -> Bool { false }
}
