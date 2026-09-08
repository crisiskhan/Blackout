import DesignSystem
import SwiftUI

/// On-device GuidePack markdown. Not a website. Copy is unchanged; only hashes are styled.
struct GuideMarkdownView: View {
    var source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(GuideMarkdown.blocks(in: source).enumerated()), id: \.offset) { _, block in
                switch block {
                case let .heading(_, text):
                    Text(text)
                        .font(BlackoutDS.titleFont())
                        .foregroundStyle(BlackoutDS.Silver.bright)
                case let .paragraph(text):
                    Text(GuideMarkdown.attributed(text))
                        .font(BlackoutDS.bodyFont())
                        .foregroundStyle(BlackoutDS.Silver.mid)
                        .lineSpacing(6)
                case let .listItem(marker, text):
                    HStack(alignment: .top, spacing: 8) {
                        Text(marker)
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Silver.steel)
                            .frame(minWidth: 18, alignment: .leading)
                        Text(GuideMarkdown.attributed(text))
                            .font(BlackoutDS.bodyFont())
                            .foregroundStyle(BlackoutDS.Silver.mid)
                            .lineSpacing(6)
                    }
                }
            }
        }
    }
}

enum GuideMarkdown {
    enum Block: Equatable {
        case heading(Int, String)
        case paragraph(String)
        case listItem(String, String)
    }

    static func blocks(in source: String) -> [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        func flushParagraph() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                result.append(.paragraph(text))
            }
            paragraph.removeAll()
        }
        for raw in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                continue
            }
            if let heading = atx(line) {
                flushParagraph()
                result.append(.heading(heading.0, heading.1))
                continue
            }
            if let item = listItem(line) {
                flushParagraph()
                result.append(.listItem(item.0, item.1))
                continue
            }
            paragraph.append(line)
        }
        flushParagraph()
        return result
    }

    static func attributed(_ text: String) -> AttributedString {
        var output = AttributedString()
        var remainder = text[...]
        while let start = remainder.range(of: "**") {
            output.append(AttributedString(String(remainder[..<start.lowerBound])))
            remainder = remainder[start.upperBound...]
            if let end = remainder.range(of: "**") {
                var bold = AttributedString(String(remainder[..<end.lowerBound]))
                bold.font = BlackoutDS.bodyFont().weight(.semibold)
                output.append(bold)
                remainder = remainder[end.upperBound...]
            } else {
                output.append(AttributedString("**" + remainder))
                remainder = remainder[remainder.endIndex...]
            }
        }
        if !remainder.isEmpty {
            output.append(AttributedString(String(remainder)))
        }
        return output
    }

    private static func atx(_ line: String) -> (Int, String)? {
        var count = 0
        for character in line {
            if character == "#" {
                count += 1
                if count > 6 { return nil }
            } else {
                break
            }
        }
        guard count >= 1 else { return nil }
        let rest = line.dropFirst(count)
        guard rest.first == " " || rest.first == "\t" else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (count, text)
    }

    private static func listItem(_ line: String) -> (String, String)? {
        if line.hasPrefix("- ") {
            return ("•", String(line.dropFirst(2)))
        }
        if line.hasPrefix("* ") {
            return ("•", String(line.dropFirst(2)))
        }
        var index = line.startIndex
        var digits = 0
        while index < line.endIndex, line[index].isNumber {
            digits += 1
            index = line.index(after: index)
        }
        guard digits > 0, index < line.endIndex, line[index] == "." else { return nil }
        let afterDot = line.index(after: index)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        let marker = String(line[..<afterDot])
        let text = String(line[line.index(after: afterDot)...])
        return (marker, text)
    }
}
