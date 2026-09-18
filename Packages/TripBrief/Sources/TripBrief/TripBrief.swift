import Foundation

public enum DiaryMark: String, Equatable, Sendable, Codable {
    case here = "HERE"
    case silent = "SILENT"
}

public struct DiaryAttend: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var mark: DiaryMark

    public init(id: String, name: String, mark: DiaryMark) {
        self.id = id
        self.name = name
        self.mark = mark
    }
}

public struct DiaryLine: Equatable, Sendable, Identifiable, Codable {
    public static let maxChars = 80

    public var id: String
    public var from: String
    public var name: String
    public var text: String
    public var at: Date

    public init(id: String = UUID().uuidString, from: String, name: String, text: String, at: Date = Date()) {
        self.id = id
        self.from = from
        self.name = name
        self.text = Self.clean(text)
        self.at = at
    }

    public static func clean(_ raw: String) -> String {
        String(
            raw.replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maxChars)
        )
    }
}

public struct DiaryLog: Equatable, Sendable, Codable {
    public var lines: [DiaryLine]

    public init(lines: [DiaryLine] = []) {
        self.lines = Self.ordered(lines)
    }

    public mutating func upsert(_ line: DiaryLine) {
        guard !line.text.isEmpty else { return }
        if let i = lines.firstIndex(where: { $0.id == line.id }) {
            lines[i] = line
        } else {
            lines.append(line)
        }
        lines = Self.ordered(lines)
    }

    public func feed() -> [DiaryLine] {
        lines
    }

    public func attend(
        roster: [(id: String, name: String)],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DiaryAttend] {
        let here = Set(
            lines.filter { calendar.isDate($0.at, inSameDayAs: now) }.map(\.from)
        )
        return roster.map { row in
            DiaryAttend(
                id: row.id,
                name: row.name,
                mark: here.contains(row.id) ? .here : .silent
            )
        }
    }

    public static func ordered(_ lines: [DiaryLine]) -> [DiaryLine] {
        lines.sorted {
            if $0.at != $1.at { return $0.at > $1.at }
            return $0.id > $1.id
        }
    }
}
