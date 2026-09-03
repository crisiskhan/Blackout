import Foundation

public enum PartyRole: String, CaseIterable, Sendable {
    case lead, medic, nav, tail, guest
}

public struct PartyMember: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var role: PartyRole
    public init(id: String, name: String, role: PartyRole) {
        self.id = id
        self.name = name
        self.role = role
    }
}

public struct PartyRoster: Equatable, Sendable {
    public var code: String
    public var members: [PartyMember]
    public init(code: String, members: [PartyMember]) {
        self.code = code
        self.members = members
    }
    public static func create(lead: String, code: String? = nil) -> PartyRoster {
        let raw = (code ?? UUID().uuidString).replacingOccurrences(of: "-", with: "")
        return PartyRoster(
            code: String(raw.prefix(6)).uppercased(),
            members: [PartyMember(id: "lead", name: lead, role: .lead)]
        )
    }
    public func setting(code: String) -> PartyRoster {
        let cleaned = String(code.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
        var copy = self
        if !cleaned.isEmpty { copy.code = cleaned }
        return copy
    }
    public func joining(_ name: String, role: PartyRole) -> PartyRoster {
        var copy = self
        copy.members.append(PartyMember(id: UUID().uuidString, name: name, role: role))
        return copy
    }
}
