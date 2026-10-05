import CryptoParty
import Foundation

/// Local N/A shelf. Playable HTTPS only. Airplane keeps the last list.
enum AdultKeep {
    static let key = "adult.keep.v1"
    static let openKey = "adult.na.open.v1"
    static let cap = 64
    static let byteCap = 256_000

    private struct Item: Codable, Equatable {
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

    static func opened() -> Bool {
        UserDefaults.standard.bool(forKey: openKey)
    }

    static func setOpened(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: openKey)
    }

    static func load() -> [AdultDesk.Room] {
        guard let data = SealedPersist.get(forKey: key),
              data.count <= byteCap,
              let items = try? JSONDecoder().decode([Item].self, from: data)
        else { return [] }
        var seen: Set<String> = []
        return items.compactMap { item in
            guard let room = room(item), seen.insert(room.id).inserted else { return nil }
            return room
        }
    }

    static func has(_ id: String) -> Bool {
        let token = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return false }
        return load().contains { $0.id == token }
    }

    static func take(_ room: AdultDesk.Room) -> [AdultDesk.Room] {
        let id = room.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let handle = room.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !handle.isEmpty, let play = AdultDesk.playlist(room.url) else {
            return load()
        }
        var rows = load().filter { $0.id != id }
        var next = room
        next.id = id
        next.handle = handle
        next.url = play
        next.kinds = mark(next.kinds)
        rows.insert(next, at: 0)
        if rows.count > cap {
            rows = Array(rows.prefix(cap))
        }
        save(rows)
        return rows
    }

    static func drop(_ id: String) -> [AdultDesk.Room] {
        let token = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = load().filter { $0.id != token }
        save(rows)
        return rows
    }

    static func mark(_ kinds: [String]) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for kind in [AdultDesk.keepChip] + kinds {
            let chip = kind.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !chip.isEmpty, seen.insert(chip).inserted else { continue }
            out.append(chip)
        }
        return out
    }

    private static func room(_ item: Item) -> AdultDesk.Room? {
        let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, AdultDesk.playlist(item.url) != nil else { return nil }
        let handle = item.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !handle.isEmpty else { return nil }
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return AdultDesk.Room(
            id: id,
            name: name.isEmpty ? handle.uppercased() : name,
            handle: handle,
            url: item.url,
            viewers: max(0, item.viewers),
            image: item.image,
            kinds: mark(item.kinds),
            seek: item.seek,
            seconds: max(0, item.seconds)
        )
    }

    private static func save(_ rooms: [AdultDesk.Room]) {
        let items = rooms.compactMap { room -> Item? in
            let id = room.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let handle = room.handle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !handle.isEmpty, let play = AdultDesk.playlist(room.url) else {
                return nil
            }
            return Item(
                id: id,
                name: room.name,
                handle: handle,
                url: play,
                viewers: room.viewers,
                image: room.image,
                kinds: mark(room.kinds),
                seek: room.seek,
                seconds: room.seconds
            )
        }
        if let data = try? JSONEncoder().encode(items) {
            SealedPersist.put(data, forKey: key)
        }
    }
}
