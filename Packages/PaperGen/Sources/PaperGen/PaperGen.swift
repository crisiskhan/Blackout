import Foundation
import TripBrief
import RosterRoles

public enum PaperGen {
    public static func export(trip: TripSheet, roster: PartyRoster, packName: String) -> String {
        var lines = ["BLACKOUT PAPER", packName, trip.brief, "due \(trip.dueBack)", "roster:"]
        lines += roster.members.map { "\($0.role.rawValue) \($0.name)" }
        return lines.joined(separator: "\n")
    }
}
