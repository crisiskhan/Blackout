import Foundation

public struct GearItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var working: Bool
    public var failureHazard: String?
    public var count: Int
    public var assignedTo: String?

    public init(
        id: String,
        name: String,
        working: Bool,
        failureHazard: String? = nil,
        count: Int = 1,
        assignedTo: String? = nil
    ) {
        self.id = id
        self.name = name
        self.working = working
        self.failureHazard = failureHazard
        self.count = count
        self.assignedTo = assignedTo
    }
}

public struct KitBag: Equatable, Sendable {
    public var items: [GearItem]
    public init(items: [GearItem]) { self.items = items }
    public var hazards: [String] { items.compactMap { $0.working ? nil : $0.failureHazard } }

    public mutating func markFailed(_ id: String, hazard: String) {
        if let i = items.firstIndex(where: { $0.id == id }) {
            items[i].working = false
            items[i].failureHazard = hazard
        }
    }

    public mutating func setWorking(_ id: String, working: Bool) {
        if let i = items.firstIndex(where: { $0.id == id }) {
            items[i].working = working
        }
    }

    public mutating func bump(_ id: String, by: Int) {
        if let i = items.firstIndex(where: { $0.id == id }) {
            items[i].count = max(0, min(99, items[i].count + by))
        }
    }

    public mutating func assign(_ id: String, to: String) {
        if let i = items.firstIndex(where: { $0.id == id }) {
            let token = to.trimmingCharacters(in: .whitespacesAndNewlines)
            items[i].assignedTo = token.isEmpty ? nil : token
        }
    }

    public mutating func addNamed(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(
            GearItem(id: UUID().uuidString, name: trimmed, working: true, count: 1)
        )
    }

    public func assigned(to personID: String, name: String, isYou: Bool) -> [GearItem] {
        items.filter { item in
            guard let a = item.assignedTo, !a.isEmpty else { return false }
            if a == personID || a == name { return true }
            if isYou && a == "YOU" { return true }
            return false
        }
    }

    public mutating func upsert(_ item: GearItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            items[i] = item
        } else {
            items.append(item)
        }
    }
}
