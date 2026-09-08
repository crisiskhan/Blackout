import Foundation

/// GuidePack wire. Manifest `schema` is the working field — do not add schemaVersion.
public enum GuidePackSchema {
    public static let current = 1
    public static let tooNewCopy = "Guide schema too new."

    public enum Status: Equatable, Sendable {
        case compatible
        case tooNew
    }

    public static func schema(from json: [String: Any]) -> Int {
        if let value = json["schema"] as? Int { return value }
        if let value = json["schema"] as? Double { return Int(value) }
        return current
    }

    public static func inspect(
        manifest: [String: Any],
        articles: [[String: Any]],
        inverted: [String: Any]
    ) -> Status {
        if schema(from: manifest) != current { return .tooNew }
        for article in articles {
            if let value = article["schema"] as? Int, value != current { return .tooNew }
            if let value = article["schema"] as? Double, Int(value) != current { return .tooNew }
        }
        if let wrapped = inverted["schema"] as? Int, wrapped != current { return .tooNew }
        if let wrapped = inverted["schema"] as? Double, Int(wrapped) != current { return .tooNew }
        return .compatible
    }
}
