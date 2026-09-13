import Foundation

public enum PartyRole: String, CaseIterable, Sendable {
    case lead, medic, nav, tail, guest

    public var title: String {
        switch self {
        case .lead:
            return "LEAD"
        case .medic:
            return "MEDIC"
        case .nav:
            return "NAV"
        case .tail:
            return "TAIL"
        case .guest:
            return "GUEST"
        default:
            let never: Never = Self.unexpected(self)
            switch never {}
        }
    }

    public var uniqueSeat: Bool {
        switch self {
        case .lead, .medic, .nav, .tail:
            return true
        case .guest:
            return false
        default:
            let never: Never = Self.unexpected(self)
            switch never {}
        }
    }

    public var next: PartyRole {
        switch self {
        case .lead:
            return .medic
        case .medic:
            return .nav
        case .nav:
            return .tail
        case .tail:
            return .guest
        case .guest:
            return .lead
        default:
            let never: Never = Self.unexpected(self)
            switch never {}
        }
    }

    public func nextOpen(taken: Set<PartyRole>) -> PartyRole {
        var role = next
        for _ in PartyRole.allCases {
            if !role.uniqueSeat || !taken.contains(role) {
                return role
            }
            role = role.next
        }
        return .guest
    }

    public static func parse(_ raw: String?) -> PartyRole? {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "lead":
            return .lead
        case "medic":
            return .medic
        case "nav":
            return .nav
        case "tail":
            return .tail
        case "guest":
            return .guest
        default:
            return nil
        }
    }

    private static func unexpected(_ role: PartyRole) -> Never {
        switch role {
        case .lead, .medic, .nav, .tail, .guest:
            preconditionFailure("PartyRole \(role.rawValue)")
        }
    }
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

public struct RosterPeer: Equatable, Sendable {
    public var id: String
    public var name: String
    public var emblem: String
    public var statusTitle: String
    public init(id: String, name: String, emblem: String, statusTitle: String) {
        self.id = id
        self.name = name
        self.emblem = emblem
        self.statusTitle = statusTitle
    }
}

public struct LiveRosterRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var role: PartyRole
    public var emblem: String
    public var statusTitle: String
    public init(id: String, name: String, role: PartyRole, emblem: String, statusTitle: String) {
        self.id = id
        self.name = name
        self.role = role
        self.emblem = emblem
        self.statusTitle = statusTitle
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
        if members.contains(where: { $0.role == role }) {
            return self
        }
        var copy = self
        copy.members.append(PartyMember(id: UUID().uuidString, name: name, role: role))
        return copy
    }

    public func rebindingLead(to id: String, name: String) -> PartyRoster {
        if members.contains(where: { $0.id == id }) { return self }
        var copy = self
        if let i = copy.members.firstIndex(where: { $0.role == .lead }) {
            copy.members[i].id = id
            if !name.isEmpty { copy.members[i].name = name }
        }
        return copy
    }

    public func seating(id: String, name: String, role: PartyRole) -> PartyRoster {
        if let existing = members.first(where: { $0.id == id }), existing.role == role {
            if name.isEmpty || existing.name == name { return self }
            var renamed = self
            if let i = renamed.members.firstIndex(where: { $0.id == id }) {
                renamed.members[i].name = name
            }
            return renamed
        }
        if role.uniqueSeat, members.contains(where: { $0.role == role && $0.id != id }) {
            return self
        }
        var copy = self
        if let i = copy.members.firstIndex(where: { $0.id == id }) {
            copy.members[i].role = role
            if !name.isEmpty { copy.members[i].name = name }
        } else {
            copy.members.append(PartyMember(id: id, name: name.isEmpty ? id : name, role: role))
        }
        return copy
    }

    public func upserting(id: String, name: String, role: PartyRole) -> PartyRoster {
        var copy = self
        if role.uniqueSeat {
            for i in copy.members.indices where copy.members[i].role == role && copy.members[i].id != id {
                copy.members[i].role = .guest
            }
        }
        if let i = copy.members.firstIndex(where: { $0.id == id }) {
            copy.members[i].role = role
            if !name.isEmpty { copy.members[i].name = name }
        } else {
            copy.members.append(PartyMember(id: id, name: name.isEmpty ? id : name, role: role))
        }
        return copy
    }

    public func cycling(id: String, name: String, from rows: [LiveRosterRow]) -> PartyRoster {
        let current = rows.first(where: { $0.id == id })?.role ?? .lead
        let taken = Set(rows.filter { $0.id != id && $0.role.uniqueSeat }.map(\.role))
        return seating(id: id, name: name, role: current.nextOpen(taken: taken))
    }

    public func live(
        youID: String,
        youName: String,
        youEmblem: String,
        youStatusTitle: String,
        peers: [RosterPeer]
    ) -> [LiveRosterRow] {
        let trimmed = youName.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? "YOU" : trimmed
        let youRole = members.first(where: { $0.id == youID })?.role ?? .lead
        var rows: [LiveRosterRow] = [
            LiveRosterRow(
                id: youID,
                name: label,
                role: youRole,
                emblem: youEmblem,
                statusTitle: youStatusTitle
            )
        ]
        var seen: Set<String> = [youID]
        for peer in peers {
            if peer.id == youID || seen.contains(peer.id) { continue }
            seen.insert(peer.id)
            let role = members.first(where: { $0.id == peer.id })?.role ?? .guest
            let name = peer.name.trimmingCharacters(in: .whitespacesAndNewlines)
            rows.append(
                LiveRosterRow(
                    id: peer.id,
                    name: name.isEmpty ? peer.id : name,
                    role: role,
                    emblem: peer.emblem,
                    statusTitle: peer.statusTitle
                )
            )
        }
        return rows
    }
}
