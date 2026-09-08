import Foundation

public enum RoadClass: String, Sendable {
    case trail
    case local
    case arterial
    case highway
}

public enum RoadLook {
    public static func classify(edge: RoutingEdge, name: String?) -> RoadClass {
        if edge.allowsWalk && !edge.allowsDrive { return .trail }
        if looksHighway(name) { return .highway }
        if looksArterial(name) { return .arterial }
        guard edge.allowsDrive, edge.driveMs > 0, edge.lengthCm > 0 else { return .local }
        let metersPerSecond = Double(edge.lengthCm) * 10.0 / Double(edge.driveMs)
        if metersPerSecond >= 22 { return .highway }
        if metersPerSecond >= 12 { return .arterial }
        return .local
    }

    public static func displayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let letters = trimmed.filter(\.isLetter)
        if !letters.isEmpty, letters.allSatisfy({ $0.isUppercase }) {
            return trimmed.localizedCapitalized
        }
        return trimmed
    }

    public static func shieldText(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(?:I|IH|US|SH|TX|NM|FM|Hwy|Highway|Loop|Interstate)\s*-?\s*(\d+[A-Z]?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let match = regex.firstMatch(in: name, options: [], range: range),
              let number = Range(match.range(at: 1), in: name) else {
            return nil
        }
        return String(name[number])
    }

    public static func looksHighway(_ name: String?) -> Bool {
        guard let name, !name.isEmpty else { return false }
        return shieldText(name) != nil
    }

    public static func looksArterial(_ name: String?) -> Bool {
        guard let name else { return false }
        let lower = name.lowercased()
        return lower.contains("blvd")
            || lower.contains("boulevard")
            || lower.contains("parkway")
            || lower.contains("pkwy")
    }

    public static func isActiveTurn(_ kind: ManeuverKind) -> Bool {
        switch kind {
        case .depart, .arrive:
            return false
        case .left, .right, .slightLeft, .slightRight, .uTurn, .straight:
            return true
        }
    }
}
