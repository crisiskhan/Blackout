import BlackoutCore
import Foundation

struct GuideArticle: Identifiable, Sendable {
    var id: String
    var title: String
    var topic: String
    var tags: [String]
    var body: String
}

struct GuideHit: Identifiable, Sendable {
    var id: String { article.id }
    var article: GuideArticle
    var score: Double
    var snippet: String
}

struct GuidePackSnapshot: Sendable {
    var articles: [GuideArticle]
    var index: [String: [String: Int]]
    var disclaimer: String
}

enum GuidePackLoader {
    static func load(rootURL: URL?) -> GuidePackSnapshot? {
        let candidates: [URL?] = [
            rootURL,
            Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "GuidePack")?.deletingLastPathComponent(),
            Bundle.main.resourceURL?.appendingPathComponent("GuidePack", isDirectory: true),
            Bundle.main.bundleURL.appendingPathComponent("GuidePack", isDirectory: true)
        ]
        for candidate in candidates {
            guard let candidate else { continue }
            if let snap = load(from: candidate) { return snap }
        }
        return nil
    }

    private static func load(from root: URL) -> GuidePackSnapshot? {
        let manifestURL = root.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let articlesURL = root.appendingPathComponent("articles.jsonl")
        guard let raw = try? String(contentsOf: articlesURL, encoding: .utf8) else { return nil }
        var articles: [GuideArticle] = []
        for line in raw.split(whereSeparator: \.isNewline) {
            guard let lineData = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let id = obj["id"] as? String,
                  let title = obj["title"] as? String,
                  let topic = obj["topic"] as? String,
                  let body = obj["body"] as? String else { continue }
            let tags = obj["tags"] as? [String] ?? []
            articles.append(GuideArticle(id: id, title: title, topic: topic, tags: tags, body: body))
        }
        guard !articles.isEmpty else { return nil }
        var index: [String: [String: Int]] = [:]
        let indexURL = root.appendingPathComponent("inverted.json")
        if let indexData = try? Data(contentsOf: indexURL),
           let obj = try? JSONSerialization.jsonObject(with: indexData) as? [String: [String: Int]] {
            index = obj
        }
        let disclaimer = json["disclaimer"] as? String ?? "On-device guide."
        return GuidePackSnapshot(articles: articles, index: index, disclaimer: disclaimer)
    }
}

enum GuideSearch {
    static func retrieve(
        query: String,
        topic: GuideTopic?,
        pack: GuidePackSnapshot,
        context: GuideQueryContext
    ) -> [GuideHit] {
        let terms = tokens(query)
        var scores: [String: Double] = [:]
        if terms.isEmpty, let topic {
            for article in pack.articles where article.topic == topic.rawValue {
                scores[article.id] = 1
            }
        } else {
            for term in terms {
                if let posting = pack.index[term] {
                    for (id, tf) in posting {
                        scores[id, default: 0] += Double(tf)
                    }
                }
                for article in pack.articles where article.topic.contains(term) || article.tags.contains(term) {
                    scores[article.id, default: 0] += 1.5
                }
            }
        }
        applyContext(context, to: &scores, pack: pack)
        if let topic {
            for article in pack.articles where article.topic == topic.rawValue {
                scores[article.id, default: 0] += 2.5
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: pack.articles.map { ($0.id, $0) })
        return scores.sorted { $0.value > $1.value }.prefix(8).compactMap { id, score in
            guard let article = byID[id] else { return nil }
            return GuideHit(
                article: article,
                score: score,
                snippet: snippet(article.body, terms: terms)
            )
        }
    }

    private static func applyContext(_ context: GuideQueryContext, to scores: inout [String: Double], pack: GuidePackSnapshot) {
        func boost(_ topic: String, _ amount: Double) {
            for article in pack.articles where article.topic == topic {
                scores[article.id, default: 0] += amount
            }
        }
        if context.isNight {
            boost("shelter", 2)
            boost("fire", 1.5)
            boost("signaling", 1.5)
        } else if context.hour >= 11 && context.hour <= 16 {
            boost("weather", 1.2)
            boost("water", 0.8)
        }
        if let elev = context.elevationMeters, elev > 2800 {
            boost("weather", 1.8)
            boost("shelter", 1.0)
            boost("first-aid", 0.6)
        }
        if context.batteryLevel >= 0, context.batteryLevel <= 0.15 {
            boost("signaling", 2)
            boost("navigation", 1.2)
        }
        if context.sosArmed {
            boost("signaling", 2.5)
            boost("first-aid", 1.5)
        }
        if context.partySize <= 1 {
            boost("signaling", 1)
            boost("navigation", 0.8)
            boost("bushcraft", 0.5)
        }
        if context.extremeSaver {
            boost("signaling", 1)
            boost("navigation", 1)
        }
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 1 }
    }

    private static func snippet(_ body: String, terms: [String]) -> String {
        let sentences = body.split(separator: ".")
        if let hit = sentences.first(where: { sentence in
            let lower = sentence.lowercased()
            return terms.contains { lower.contains($0) }
        }) {
            let text = hit.trimmingCharacters(in: .whitespacesAndNewlines) + "."
            return String(text.prefix(280))
        }
        return String(body.prefix(280))
    }
}
