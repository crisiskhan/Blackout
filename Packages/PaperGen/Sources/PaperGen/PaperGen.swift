import Foundation
import TripBrief
import RosterRoles

public enum PaperGen {
    public static func export(
        diary: DiaryLog,
        roster: PartyRoster,
        packName: String,
        now: Date = Date()
    ) -> String {
        var lines = ["BLACKOUT PAPER", packName]
        let attend = diary.attend(
            roster: roster.members.map { ($0.id, $0.name) },
            now: now
        )
        lines += attend.map { "\($0.name) · \($0.mark.rawValue)" }
        for line in diary.feed() {
            lines.append("\(line.name) \(line.at)")
            lines.append(line.text)
        }
        lines.append("roster:")
        lines += roster.members.map { "\($0.role.title) \($0.name)" }
        return lines.joined(separator: "\n")
    }
}
