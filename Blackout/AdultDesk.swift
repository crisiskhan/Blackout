import Foundation

/// Adult directory for N/A after the 10s hold. JSON only. No player.
enum AdultDesk {
    static let cap = 48
    static let origin = "https://lovescape.cam"
    static let tags = ["girls", "couples", "men", "trans"]
    static let agent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static let blocked = [
        "teen",
        "underage",
        "child",
        "loli",
        "shota",
        "jailbait",
        "preteen",
        "pedo",
        "minor",
        "under18",
        "younggirl",
    ]

    struct Room: Identifiable, Equatable, Sendable {
        var id: String
        var name: String
        var url: String
        var viewers: Int
    }

    static func directory(tag: String) -> String {
        "\(origin)/api/front/models?primaryTag=\(tag)&limit=24"
    }

    static func parse(_ data: Data) -> [Room] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return rooms(from: models(from: obj))
    }

    static func merge(_ batches: [[Room]]) -> [Room] {
        var byID: [String: Room] = [:]
        for room in batches.joined() {
            if let old = byID[room.id], old.viewers >= room.viewers { continue }
            byID[room.id] = room
        }
        return Array(byID.values)
            .sorted { lhs, rhs in
                if lhs.viewers != rhs.viewers { return lhs.viewers > rhs.viewers }
                return lhs.name < rhs.name
            }
            .prefix(cap)
            .map { $0 }
    }

    static func playlist(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme?.lowercased() == "https" else { return nil }
        var out = text
        if let range = out.range(of: #"_\d+p\.m3u8$"#, options: [.regularExpression, .caseInsensitive]) {
            out.replaceSubrange(range, with: ".m3u8")
        } else if let range = out.range(of: #"_high\.m3u8$"#, options: [.regularExpression, .caseInsensitive]) {
            out.replaceSubrange(range, with: ".m3u8")
        }
        guard let parsed = URL(string: out), parsed.scheme?.lowercased() == "https" else { return nil }
        return out
    }

    static func allows(_ name: String) -> Bool {
        let blob = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if blob.isEmpty { return false }
        return !blocked.contains { blob.contains($0) }
    }

    private static func models(from obj: Any) -> [[String: Any]] {
        if let list = obj as? [[String: Any]] { return list }
        guard let dict = obj as? [String: Any] else { return [] }
        if let nested = dict["models"] {
            let again = models(from: nested)
            if !again.isEmpty { return again }
        }
        if let nested = dict["items"] {
            return models(from: nested)
        }
        return []
    }

    private static func rooms(from models: [[String: Any]]) -> [Room] {
        var seen: Set<String> = []
        var rows: [Room] = []
        for model in models {
            guard isLive(model) else { continue }
            let status = string(model["status"]).lowercased()
            guard status == "public" else { continue }
            let named = string(model["username"]).isEmpty
                ? string(model["alias"])
                : string(model["username"])
            guard allows(named) else { continue }
            let token = identity(model, name: named)
            guard !token.isEmpty else { continue }
            let rid = "adult-\(token)"
            guard !seen.contains(rid) else { continue }
            let raw = firstString(model, keys: ["hlsPlaylist", "hlsStreamUrl", "streamUrl"])
            guard let url = playlist(raw) else { continue }
            seen.insert(rid)
            rows.append(
                Room(
                    id: rid,
                    name: named.uppercased(),
                    url: url,
                    viewers: viewers(model)
                )
            )
        }
        return rows
    }

    private static func isLive(_ model: [String: Any]) -> Bool {
        if let flag = model["isLive"] as? Bool { return flag }
        if let flag = model["isLive"] as? Int { return flag != 0 }
        if let flag = model["isLive"] as? Double { return flag != 0 }
        let token = string(model["isLive"]).lowercased()
        return token == "true" || token == "1"
    }

    private static func viewers(_ model: [String: Any]) -> Int {
        if let n = model["viewersCount"] as? Int { return n }
        if let n = model["viewers"] as? Int { return n }
        if let n = model["viewersCount"] as? Double { return Int(n) }
        if let n = model["viewers"] as? Double { return Int(n) }
        if let n = Int(string(model["viewersCount"])) { return n }
        if let n = Int(string(model["viewers"])) { return n }
        return 0
    }

    private static func identity(_ model: [String: Any], name: String) -> String {
        if let n = model["id"] as? Int { return String(n) }
        if let n = model["id"] as? Double { return String(Int(n)) }
        let token = string(model["id"])
        if !token.isEmpty { return token }
        return name
    }

    private static func firstString(_ model: [String: Any], keys: [String]) -> String {
        for key in keys {
            let value = string(model[key])
            if !value.isEmpty { return value }
        }
        return ""
    }

    private static func string(_ value: Any?) -> String {
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
}
