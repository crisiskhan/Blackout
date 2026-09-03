import Foundation

public struct GearItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var working: Bool
    public var failureHazard: String?

    public init(id: String, name: String, working: Bool, failureHazard: String? = nil) {
        self.id = id
        self.name = name
        self.working = working
        self.failureHazard = failureHazard
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
}
