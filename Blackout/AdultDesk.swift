import Foundation

/// Adult directory for N/A after the 10s hold. Women only. JSON only. No player.
enum AdultDesk {
    static let cap = 600
    static let pageSize = 100
    static let pages = 6
    static let origin = "https://chaturbate.com"
    static let tags = ["f"]
    static let mark = "DkfRj"
    static let via = "8.8.8.8"
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

    static let kindWords: [(String, String)] = [
        ("new", "NEW"),
        ("dance", "DANCE"),
        ("blonde", "BLONDE"),
        ("brunette", "BRUNETTE"),
        ("redhead", "REDHEAD"),
        ("asian", "ASIAN"),
        ("latina", "LATINA"),
        ("ebony", "EBONY"),
        ("milf", "MILF"),
        ("petite", "PETITE"),
        ("curvy", "CURVY"),
        ("outdoor", "OUTDOOR"),
        ("toys", "TOYS"),
        ("squirt", "SQUIRT"),
        ("anal", "ANAL"),
        ("lesbian", "LESBIAN"),
    ]

    struct Room: Identifiable, Equatable, Sendable {
        var id: String
        var name: String
        var handle: String
        var url: String
        var viewers: Int
        var image: String
        var kinds: [String]
    }

    static func directory(tag: String, offset: Int = 0) -> String {
        let start = max(0, offset)
        return "\(origin)/api/public/affiliates/onlinerooms/?format=json&limit=\(pageSize)&offset=\(start)&client_ip=\(via)&wm=\(mark)&gender=\(tag)"
    }

    static func context(_ handle: String) -> String? {
        guard let token = token(handle) else { return nil }
        return "\(origin)/api/chatvideocontext/\(token)/"
    }

    static func edge(_ handle: String) -> (path: String, body: String)? {
        guard let token = token(handle) else { return nil }
        return ("\(origin)/get_edge_hls_url_ajax/", "room_slug=\(token)&bandwidth=high")
    }

    static func parse(_ data: Data) -> [Room] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return rooms(from: models(from: obj))
    }

    static func stream(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let status = string(obj["room_status"]).lowercased()
        guard status == "public" else { return nil }
        let raw = string(obj["hls_source"]).isEmpty ? string(obj["url"]) : string(obj["hls_source"])
        return playlist(raw)
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
        let low = text.lowercased()
        if low.contains("/cpa/") || low.contains("mouflon-advert") { return nil }
        if !low.contains(".m3u8") { return nil }
        return text
    }

    static func still(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme?.lowercased() == "https" else { return nil }
        let low = text.lowercased()
        if low.contains("/cpa/") || low.contains(".m3u8") { return nil }
        return text
    }

    static func pick(_ rooms: [Room], kind: String, query: String) -> [Room] {
        let chip = kind.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rooms.filter { room in
            if !chip.isEmpty && chip != "ALL" && !room.kinds.contains(chip) {
                return false
            }
            if !needle.isEmpty {
                let blob = ([room.name, room.handle] + room.kinds).joined(separator: " ").lowercased()
                if !blob.contains(needle) { return false }
            }
            return true
        }
    }

    static func kinds(_ rooms: [Room]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for room in rooms {
            for kind in room.kinds {
                if seen.insert(kind).inserted {
                    out.append(kind)
                }
            }
        }
        return out.sorted()
    }

    static func woman(_ model: [String: Any]) -> Bool {
        let gender = string(model["gender"]).lowercased()
        if gender.isEmpty { return true }
        if ["m", "male", "c", "couple", "couples", "s", "trans"].contains(gender) {
            return false
        }
        return ["f", "female", "w", "woman", "women"].contains(gender)
    }

    private static func token(_ handle: String) -> String? {
        let token = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return nil
        }
        return token
    }

    static func allows(_ name: String) -> Bool {
        let blob = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if blob.isEmpty { return false }
        return !blocked.contains { blob.contains($0) }
    }

    static func clean(_ blob: String) -> Bool {
        let text = blob.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty { return true }
        return !blocked.contains { text.contains($0) }
    }

    private static func models(from obj: Any) -> [[String: Any]] {
        if let list = obj as? [[String: Any]] { return list }
        guard let dict = obj as? [String: Any] else { return [] }
        if let nested = dict["results"] {
            let again = models(from: nested)
            if !again.isEmpty { return again }
        }
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
            let show = string(model["current_show"]).lowercased()
            let status = show.isEmpty ? string(model["status"]).lowercased() : show
            guard status == "public" else { continue }
            guard woman(model) else { continue }
            guard let years = age(model), years >= 18 else { continue }
            let handle = string(model["username"]).isEmpty
                ? string(model["slug"])
                : string(model["username"])
            let named = string(model["display_name"]).isEmpty ? handle : string(model["display_name"])
            guard !handle.isEmpty, allows(handle), allows(named) else { continue }
            guard clean(tags(model)), clean(string(model["room_subject"])) else { continue }
            let rid = "adult-\(handle.lowercased())"
            guard !seen.contains(rid) else { continue }
            seen.insert(rid)
            rows.append(
                Room(
                    id: rid,
                    name: named.uppercased(),
                    handle: handle,
                    url: "",
                    viewers: viewers(model),
                    image: image(model),
                    kinds: roomKinds(model)
                )
            )
        }
        return rows
    }

    private static func image(_ model: [String: Any]) -> String {
        if let hit = still(string(model["image_url_360p"])) { return hit }
        if let hit = still(string(model["image_url"])) { return hit }
        return ""
    }

    private static func roomKinds(_ model: [String: Any]) -> [String] {
        let blob = (tags(model) + " " + string(model["room_subject"])).lowercased()
        let tokens = Set(blob.split(whereSeparator: { $0.isWhitespace }).map(String.init))
        var found: [String] = []
        var seen: Set<String> = []
        if flag(model, "is_new") || tokens.contains("new") {
            seen.insert("NEW")
            found.append("NEW")
        }
        for pair in kindWords {
            if pair.0 == "new" { continue }
            if blob.contains(pair.0), clean(pair.1), seen.insert(pair.1).inserted {
                found.append(pair.1)
            }
        }
        return found
    }

    private static func flag(_ model: [String: Any], _ key: String) -> Bool {
        if let flag = model[key] as? Bool { return flag }
        let text = string(model[key]).lowercased()
        return text == "1" || text == "true" || text == "yes"
    }

    private static func age(_ model: [String: Any]) -> Int? {
        if let n = model["age"] as? Int { return n }
        if let n = model["age"] as? Double { return Int(n) }
        if let n = Int(string(model["age"])) { return n }
        return nil
    }

    private static func viewers(_ model: [String: Any]) -> Int {
        if let n = model["num_users"] as? Int { return n }
        if let n = model["viewersCount"] as? Int { return n }
        if let n = model["viewers"] as? Int { return n }
        if let n = model["num_users"] as? Double { return Int(n) }
        if let n = model["viewersCount"] as? Double { return Int(n) }
        if let n = model["viewers"] as? Double { return Int(n) }
        if let n = Int(string(model["num_users"])) { return n }
        if let n = Int(string(model["viewersCount"])) { return n }
        if let n = Int(string(model["viewers"])) { return n }
        return 0
    }

    private static func tags(_ model: [String: Any]) -> String {
        if let list = model["tags"] as? [String] {
            return list.joined(separator: " ")
        }
        if let list = model["tags"] as? [Any] {
            return list.compactMap { string($0) }.joined(separator: " ")
        }
        return string(model["tags"])
    }

    private static func string(_ value: Any?) -> String {
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
}
