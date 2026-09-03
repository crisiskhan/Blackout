import Foundation

public enum PartyRole: String, CaseIterable, Sendable {
    case lead, medic, nav, tail, guest
}

public struct PartyMember: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var role: PartyRole
}

public struct PartyRoster: Equatable, Sendable {
    public var code: String
    public var members: [PartyMember]
    public static func create(lead: String) -> PartyRoster {
        PartyRoster(code: String(UUID().uuidString.prefix(6)), members: [PartyMember(id: "lead", name: lead, role: .lead)])
    }
    public func joining(_ name: String, role: PartyRole) -> PartyRoster {
        var copy = self
        copy.members.append(PartyMember(id: UUID().uuidString, name: name, role: role))
        return copy
    }
}
