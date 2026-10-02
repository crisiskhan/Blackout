import Foundation

/// Adult directory for N/A after the 10s hold. Women and couples. JSON only. No player.
enum AdultDesk {
    static let cap = 800
    static let pageSize = 100
    static let pages = 8
    static let origin = "https://chaturbate.com"
    static let tags = ["f", "c"]
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
        "trans",
        "shemale",
        "ladyboy",
        "tgirl",
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
        ("couple", "COUPLE"),
        ("orgy", "ORGY"),
        ("gangbang", "ORGY"),
        ("threesome", "ORGY"),
        ("fff", "ORGY"),
        ("ffm", "ORGY"),
        ("group sex", "ORGY"),
        ("roleplay", "ROLEPLAY"),
        ("role-play", "ROLEPLAY"),
        ("role play", "ROLEPLAY"),
        ("roleplaying", "ROLEPLAY"),
        ("cosplay", "ROLEPLAY"),
        ("bdsm", "BDSM"),
        ("fetish", "FETISH"),
        ("bondage", "BDSM"),
        ("femdom", "BDSM"),
        ("oral", "ORAL"),
        ("blowjob", "ORAL"),
        ("deepthroat", "ORAL"),
        ("cuckold", "CUCKOLD"),
        ("shower", "SHOWER"),
        ("feet", "FEET"),
        ("smoking", "SMOKE"),
        ("lovense", "TOYS"),
        ("dildo", "TOYS"),
        ("masturbat", "SOLO"),
        ("braid", "BRAIDS"),
        ("cornrow", "BRAIDS"),
        ("sleep", "SLEEP"),
        ("asleep", "SLEEP"),
        ("somno", "SLEEP"),
        ("robbery", "ROBBERY"),
        ("robber", "ROBBERY"),
        ("burglar", "ROBBERY"),
        ("forced", "FORCED"),
        ("cnc", "FORCED"),
        ("noncon", "FORCED"),
        ("non-con", "FORCED"),
        ("pawn", "PAWN"),
        ("thief", "THIEF"),
        ("caught", "THIEF"),
        ("freeuse", "FREEUSE"),
        ("kidnap", "KIDNAP"),
        ("cop", "COP"),
        ("police", "COP"),
        ("maid", "MAID"),
        ("nurse", "NURSE"),
        ("hypno", "HYPNO"),
        ("cheating", "CHEAT"),
        ("hotwife", "CHEAT"),
        ("teacher", "TEACHER"),
        ("favor", "FAVORS"),
        ("favour", "FAVORS"),
        ("hostage", "HOSTAGE"),
        ("blackmail", "BLACKMAIL"),
        ("burglary", "ROBBERY"),
        ("invasion", "INVASION"),
        ("fulani", "BRAIDS"),
        ("knotless", "BRAIDS"),
        ("free use", "FREEUSE"),
        ("somnophilia", "SLEEP"),
    ]
    static let pin = [
        "COUPLE",
        "ORGY",
        "ROLEPLAY",
        "BRAIDS",
        "SLEEP",
        "ROBBERY",
        "FORCED",
        "PAWN",
        "THIEF",
        "FAVORS",
    ]
    static let faces: [(String, [String])] = [
        ("ITSSTEPHHONEY21", [
            "itsstephhoney21",
            "itsstephhoney",
            "stephhoney21",
            "stephhoney",
            "its steph honey",
            "steph honey 21",
        ]),
        ("MULAN VUITTON", ["mulanvuitton", "mulan_vuitton", "mulan vuitton", "mulanvuittontv"]),
    ]
    static let loveChip = "LOVESCAPE"
    static let loveOrigin = "https://lovescape.cam"
    static let loveTags = ["girls", "couples"]
    static let loveAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    struct Room: Identifiable, Equatable, Sendable {
        var id: String
        var name: String
        var handle: String
        var url: String
        var viewers: Int
        var image: String
        var kinds: [String]
        var seek: String
        var seconds: Int
    }

    static func directory(tag: String, offset: Int = 0, topic: String = "") -> String {
        let start = max(0, offset)
        var url =
            "\(origin)/api/public/affiliates/onlinerooms/?format=json&limit=\(pageSize)&offset=\(start)&client_ip=\(via)&wm=\(mark)&gender=\(tag)"
        let hashtag = topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !hashtag.isEmpty,
           let encoded = hashtag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        {
            url += "&tag=\(encoded)"
        }
        return url
    }

    static func topics(_ kind: String) -> [String] {
        if faceNeedles(kind) != nil || loveNeedles(kind) { return [] }
        switch kind.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "", "ALL":
            return []
        case "BRAIDS":
            return ["braids", "braid", "cornrows"]
        case "SLEEP":
            return ["sleeping", "sleep", "somno"]
        case "ROBBERY":
            return ["robbery", "robber"]
        case "FORCED":
            return ["cnc", "forced", "noncon"]
        case "PAWN":
            return ["pawn", "pawnshop"]
        case "THIEF":
            return ["thief", "caught"]
        case "FAVORS":
            return ["favors", "favour"]
        case "FREEUSE":
            return ["freeuse"]
        case "KIDNAP":
            return ["kidnap"]
        case "COP":
            return ["cop", "police"]
        case "MAID":
            return ["maid"]
        case "NURSE":
            return ["nurse"]
        case "HYPNO":
            return ["hypno"]
        case "CHEAT":
            return ["cheating", "hotwife"]
        case "TEACHER":
            return ["teacher"]
        case "HOSTAGE":
            return ["hostage"]
        case "BLACKMAIL":
            return ["blackmail"]
        case "INVASION":
            return ["invasion"]
        case "ROLEPLAY":
            return ["roleplay", "cosplay"]
        case "ORGY":
            return ["orgy", "gangbang", "threesome"]
        case "COUPLE":
            return ["couple"]
        default:
            let tag = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return tag.isEmpty ? [] : [tag]
        }
    }

    static func faceNeedles(_ kind: String) -> [String]? {
        let chip = kind.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        for pair in faces where pair.0 == chip {
            return pair.1
        }
        return nil
    }

    static func loveNeedles(_ kind: String) -> Bool {
        kind.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == loveChip
    }

    static func loveDirectory(tag: String, offset: Int = 0) -> String {
        let start = max(0, offset)
        let raw = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let token = loveTags.contains(raw) ? raw : loveTags[0]
        return "\(loveOrigin)/api/front/models?limit=\(pageSize)&offset=\(start)&primaryTag=\(token)"
    }

    static func userAgent(_ raw: String) -> String {
        let host = URL(string: raw)?.host?.lowercased() ?? ""
        if loveHost(raw) || host.contains("bornstar") { return loveAgent }
        return agent
    }

    static func referer(_ raw: String) -> String {
        if loveHost(raw) { return "\(loveOrigin)/" }
        let host = URL(string: raw)?.host?.lowercased() ?? ""
        if host.contains("eporner") { return "https://www.eporner.com/" }
        if host.contains("bornstar") { return "https://bornstar.co/" }
        return "\(origin)/"
    }

    static func loveHost(_ raw: String) -> Bool {
        let host = URL(string: raw)?.host?.lowercased() ?? ""
        if host == "lovescape.cam" || host.hasSuffix(".lovescape.cam") { return true }
        if host.contains("doppiocdn") { return true }
        if host.contains("strpst") { return true }
        return false
    }

    static func faceQueries(_ kind: String) -> [String] {
        guard let needles = faceNeedles(kind) else { return [] }
        var out: [String] = []
        var seen: Set<String> = []
        let chip = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for raw in [chip] + needles {
            let query = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if query.count < 6 { continue }
            if seen.insert(query).inserted {
                out.append(query)
            }
        }
        return out
    }

    static func faceSearch(_ query: String, page: Int = 1) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        let start = max(1, page)
        return "https://www.eporner.com/api/v2/video/search/?query=\(encoded)&per_page=30&page=\(start)&order=longest&format=json&gay=0"
    }

    static func starSearch(_ query: String, page: Int = 1) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        let start = max(1, page)
        return "https://bornstar.co/api/search?q=\(encoded)&page=\(start)"
    }

    static func faceHunt(_ kind: String) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for query in faceQueries(kind) {
            for page in 1...4 {
                if let path = faceSearch(query, page: page), seen.insert(path).inserted {
                    out.append(path)
                }
            }
            for page in 1...2 {
                if let path = starSearch(query, page: page), seen.insert(path).inserted {
                    out.append(path)
                }
            }
        }
        return out
    }

    static func faceFile(_ token: String) -> String? {
        let id = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return "https://www.eporner.com/dload/\(id)/720/video.mp4"
    }

    static func starFile(_ slug: String) -> String? {
        let id = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            return nil
        }
        return "https://cdn.bornstar.co/videos/\(id)/master.m3u8"
    }

    static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, rest)
        }
        return String(format: "%d:%02d", minutes, rest)
    }

    static func parseFace(_ data: Data, kind: String) -> [Room] {
        guard let needles = faceNeedles(kind) else { return [] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let list = obj["videos"] as? [[String: Any]] ?? []
        var seen: Set<String> = []
        var rows: [Room] = []
        for model in list {
            guard let room = starClip(model, needles: needles) ?? faceClip(model, needles: needles)
            else { continue }
            guard seen.insert(room.id).inserted else { continue }
            rows.append(room)
        }
        return rows.sorted { lhs, rhs in
            if lhs.seconds != rhs.seconds { return lhs.seconds > rhs.seconds }
            return lhs.name < rhs.name
        }
    }

    private static func faceClip(_ model: [String: Any], needles: [String]) -> Room? {
        let token = string(model["id"])
        let rawTitle = string(model["title"])
        if rawTitle.contains("\u{200B}") { return nil }
        guard let play = playlist(faceFile(token) ?? "") else { return nil }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let keys = string(model["keywords"])
        guard !title.isEmpty, allows(title), clean(title), clean(keys) else { return nil }
        guard !faceSpam(title), !faceSpam(keys) else { return nil }
        guard faceHit(title + " " + keys, needles: needles) else { return nil }
        var thumb = ""
        if let dict = model["default_thumb"] as? [String: Any] {
            thumb = still(string(dict["src"])) ?? ""
        }
        if thumb.isEmpty {
            thumb = still(string(model["default_thumb"])) ?? ""
        }
        let seconds = max(0, number(model["length_sec"]))
        guard seconds > 0 else { return nil }
        return Room(
            id: "adult-face-\(token.lowercased())",
            name: title.uppercased(),
            handle: token,
            url: play,
            viewers: number(model["views"]),
            image: thumb,
            kinds: [],
            seek: (title + " " + needles.joined(separator: " ")).lowercased(),
            seconds: seconds
        )
    }

    private static func starClip(_ model: [String: Any], needles: [String]) -> Room? {
        let slug = string(model["slug"]).isEmpty ? string(model["id"]) : string(model["slug"])
        guard let play = playlist(starFile(slug) ?? "") else { return nil }
        let rawTitle = string(model["title"])
        if rawTitle.contains("\u{200B}") { return nil }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let creator = string(model["creator"])
        guard !title.isEmpty, allows(title), clean(title), allows(creator) || creator.isEmpty, clean(creator)
        else { return nil }
        guard !faceSpam(title), !faceSpam(creator) else { return nil }
        let blob = title + " " + creator + " " + slug
        guard faceHit(blob, needles: needles) else { return nil }
        let seconds = max(0, number(model["durationSeconds"]))
        guard seconds > 0 else { return nil }
        return Room(
            id: "adult-face-star-\(slug.lowercased())",
            name: title.uppercased(),
            handle: slug,
            url: play,
            viewers: number(model["views"]),
            image: still(string(model["thumbnailUrl"])) ?? "",
            kinds: [],
            seek: (title + " " + creator + " " + needles.joined(separator: " ")).lowercased(),
            seconds: seconds
        )
    }

    private static func faceHit(_ blob: String, needles: [String]) -> Bool {
        let text = blob.lowercased()
        let compact = text.replacingOccurrences(of: " ", with: "")
        return needles.contains { needle in
            let token = needle.lowercased()
            if token.contains(" ") { return text.contains(token) }
            return text.contains(token) || compact.contains(token)
        }
    }

    private static func faceSpam(_ blob: String) -> Bool {
        let text = blob.lowercased()
        if text.contains("library") { return true }
        if text.contains("exclusive video") { return true }
        if text.contains("see everything") { return true }
        if text.contains("private content") { return true }
        if text.contains(".club") { return true }
        return false
    }

    private static func number(_ value: Any?) -> Int {
        if let n = value as? Int { return n }
        if let n = value as? Double { return Int(n) }
        if let n = Int(string(value)) { return n }
        return 0
    }

    static func faceRoom(handle: String, data: Data) -> Room? {
        guard let play = stream(data) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard woman(obj) else { return nil }
        if let years = age(obj), years < 18 { return nil }
        let named = string(obj["broadcaster_username"]).isEmpty
            ? handle
            : string(obj["broadcaster_username"])
        let title = string(obj["room_title"]).isEmpty
            ? string(obj["room_subject"])
            : string(obj["room_title"])
        guard allows(handle), allows(named), clean(title) else { return nil }
        return Room(
            id: "adult-\(handle.lowercased())",
            name: named.uppercased(),
            handle: handle,
            url: play,
            viewers: viewers(obj),
            image: image(obj),
            kinds: roomKinds(obj),
            seek: (handle + " " + title)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
            seconds: 0
        )
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
        if !low.contains(".m3u8") && !low.contains(".mp4") { return nil }
        return text
    }

    static func filePlay(_ raw: String) -> Bool {
        let low = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return low.contains(".mp4") && !low.contains(".m3u8")
    }

    static func livePlay(_ source: String, _ data: Data) -> String? {
        guard let play = playlist(source) else { return nil }
        let text = String(data: data, encoding: .utf8) ?? ""
        let low = text.lowercased()
        if low.contains("mouflon-advert") || low.contains("/cpa/") { return nil }
        if low.contains("#ext-x-stream-inf") { return nil }
        if low.contains("media.mp4") { return nil }
        if !low.contains("#extinf") { return nil }
        return play
    }

    static func loveVariant(_ source: String, _ data: Data) -> String? {
        guard playlist(source) != nil else { return nil }
        let text = String(data: data, encoding: .utf8) ?? ""
        let low = text.lowercased()
        if low.contains("mouflon-advert") || low.contains("/cpa/") { return nil }
        if !low.contains("#ext-x-stream-inf") { return nil }
        var psch = ""
        var pkey = ""
        var variants: [String] = []
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            let row = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if row.hasPrefix("#EXT-X-MOUFLON:PSCH:") {
                let parts = row.split(separator: ":").map(String.init)
                if parts.count >= 4 {
                    psch = parts[2]
                    pkey = parts[3]
                }
            }
            if row.lowercased().hasPrefix("https://"), let play = playlist(row) {
                variants.append(play)
            }
        }
        guard let pick = lovePick(variants) else { return nil }
        if psch.isEmpty || pkey.isEmpty { return pick }
        let sep = pick.contains("?") ? "&" : "?"
        return "\(pick)\(sep)psch=\(psch)&pkey=\(pkey)"
    }

    static func parseLove(_ data: Data) -> [Room] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let models = models(from: obj)
        var seen: Set<String> = []
        var rows: [Room] = []
        for model in models {
            guard flag(model, "isLive") else { continue }
            let status = string(model["status"]).lowercased()
            guard status == "public" else { continue }
            guard loveWoman(model) else { continue }
            if let years = age(model), years < 18 { continue }
            let handle = string(model["username"]).isEmpty
                ? string(model["slug"])
                : string(model["username"])
            let named = string(model["displayName"]).isEmpty ? handle : string(model["displayName"])
            guard !handle.isEmpty, allows(handle), allows(named) else { continue }
            let topic = string(model["groupShowTopic"])
            guard clean(topic) else { continue }
            let rid = "adult-love-\(handle.lowercased())"
            guard seen.insert(rid).inserted else { continue }
            let play = loveMaster(string(model["hlsPlaylist"])) ?? ""
            rows.append(
                Room(
                    id: rid,
                    name: named.uppercased(),
                    handle: handle,
                    url: play,
                    viewers: viewers(model),
                    image: loveImage(model),
                    kinds: loveKinds(model),
                    seek: loveSeek(model),
                    seconds: 0
                )
            )
        }
        return rows
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
        let faces = faceNeedles(chip)
        let love = loveNeedles(chip)
        let picked = rooms.filter { room in
            if let faces {
                let blob = ([room.name, room.handle, room.seek] + room.kinds)
                    .joined(separator: " ")
                    .lowercased()
                if !faces.contains(where: { blob.contains($0) }) {
                    return false
                }
            } else if love {
                if !room.kinds.contains(loveChip) {
                    return false
                }
            } else if !chip.isEmpty && chip != "ALL" && !room.kinds.contains(chip) {
                return false
            }
            if !needle.isEmpty {
                let blob = ([room.name, room.handle, room.seek] + room.kinds).joined(separator: " ").lowercased()
                if !blob.contains(needle) { return false }
            }
            return true
        }
        if faces == nil { return picked }
        return picked.sorted { lhs, rhs in
            if lhs.seconds != rhs.seconds { return lhs.seconds > rhs.seconds }
            if lhs.viewers != rhs.viewers { return lhs.viewers > rhs.viewers }
            return lhs.name < rhs.name
        }
    }

    static func kinds(_ rooms: [Room]) -> [String] {
        var seen: Set<String> = []
        for room in rooms {
            for kind in room.kinds {
                seen.insert(kind)
            }
        }
        let pinned = pin.filter { seen.contains($0) }
        let rest = seen.subtracting(pin).sorted()
        return pinned + rest
    }

    static func rail(_ rooms: [Room]) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for chip in ["ALL", loveChip] + faces.map(\.0) + pin + kinds(rooms) {
            if seen.insert(chip).inserted {
                out.append(chip)
            }
        }
        return out
    }

    static func woman(_ model: [String: Any]) -> Bool {
        var gender = string(model["gender"]).lowercased()
        if gender.isEmpty {
            gender = string(model["broadcaster_gender"]).lowercased()
        }
        if gender.isEmpty { return true }
        if [
            "m",
            "male",
            "s",
            "trans",
            "shemale",
            "tgirl",
            "transgender",
            "transsexual",
            "ts",
        ].contains(gender) {
            return false
        }
        return [
            "f",
            "female",
            "females",
            "w",
            "woman",
            "women",
            "c",
            "couple",
            "couples",
            "malefemale",
            "girl",
            "girls",
        ].contains(gender)
    }

    private static func loveWoman(_ model: [String: Any]) -> Bool {
        let group = string(model["genderGroup"]).lowercased()
        if ["m", "male", "t", "trans"].contains(group) { return false }
        let broadcast = string(model["broadcastGender"]).lowercased()
        if ["male", "men", "trans", "tranny"].contains(broadcast) { return false }
        return woman(model)
    }

    private static func loveMaster(_ raw: String) -> String? {
        guard let play = playlist(raw) else { return nil }
        return play.replacingOccurrences(of: "_240p.m3u8", with: "_auto.m3u8")
    }

    private static func lovePick(_ variants: [String]) -> String? {
        let ranked = variants.filter { row in
            let low = row.lowercased()
            return !low.contains("blur") && !low.contains("160p")
        }
        if let hit = ranked.first(where: { $0.lowercased().contains("_480p") }) { return hit }
        if let hit = ranked.first(where: { row in
            let low = row.lowercased()
            return low.contains("_auto") || !low.contains("_240p")
        }) {
            return hit
        }
        return ranked.first ?? variants.first
    }

    private static func loveImage(_ model: [String: Any]) -> String {
        if let hit = loveStill(string(model["previewUrlThumbSmall"])) { return hit }
        if let hit = still(string(model["avatarUrl"])) { return hit }
        return ""
    }

    private static func loveStill(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = text.lowercased()
        if low.hasSuffix("-thumb-small") {
            let stem = String(text.dropLast("-thumb-small".count))
            if let hit = still(stem) { return hit }
            if let hit = still(stem + "-thumb-big") { return hit }
        }
        return still(text)
    }

    private static func loveKinds(_ model: [String: Any]) -> [String] {
        var found = [loveChip]
        var seen: Set<String> = [loveChip]
        let gender = string(model["gender"]).lowercased()
        let broadcast = string(model["broadcastGender"]).lowercased()
        if [
            "c",
            "couple",
            "couples",
            "malefemale",
            "females",
        ].contains(gender) || broadcast == "group" {
            if seen.insert("COUPLE").inserted {
                found.append("COUPLE")
            }
        }
        if flag(model, "isNew"), seen.insert("NEW").inserted {
            found.append("NEW")
        }
        let blob = (string(model["groupShowTopic"]) + " " + string(model["username"])).lowercased()
        for pair in kindWords {
            if pair.0 == "new" { continue }
            if blob.contains(pair.0), clean(pair.1), seen.insert(pair.1).inserted {
                found.append(pair.1)
            }
        }
        return found
    }

    private static func loveSeek(_ model: [String: Any]) -> String {
        [
            string(model["username"]),
            string(model["displayName"]),
            string(model["gender"]),
            string(model["groupShowTopic"]),
            string(model["country"]),
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .lowercased()
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
                    kinds: roomKinds(model),
                    seek: seek(model),
                    seconds: 0
                )
            )
        }
        return rows
    }

    private static func seek(_ model: [String: Any]) -> String {
        (tags(model) + " " + string(model["room_subject"]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
        let gender = string(model["gender"]).lowercased()
        if ["c", "couple", "couples"].contains(gender)
            || tokens.contains("couple")
            || tokens.contains("couples")
        {
            if seen.insert("COUPLE").inserted {
                found.append("COUPLE")
            }
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
        if let n = model["num_viewers"] as? Int { return n }
        if let n = model["viewersCount"] as? Int { return n }
        if let n = model["viewers"] as? Int { return n }
        if let n = model["num_users"] as? Double { return Int(n) }
        if let n = model["num_viewers"] as? Double { return Int(n) }
        if let n = model["viewersCount"] as? Double { return Int(n) }
        if let n = model["viewers"] as? Double { return Int(n) }
        if let n = Int(string(model["num_users"])) { return n }
        if let n = Int(string(model["num_viewers"])) { return n }
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
