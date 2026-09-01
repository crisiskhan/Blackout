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

enum GuidePackLoad: Equatable {
    case ready
    case missing
    case tooNew
}

enum GuidePackLoader {
    private static var memoKey: String?
    private static var memoInspect: Inspect?

    static func load(rootURL: URL?) -> GuidePackSnapshot? {
        switch inspect(rootURL: rootURL) {
        case .ready(let snap):
            return snap
        case .missing, .tooNew:
            return nil
        }
    }

    static func status(rootURL: URL?) -> GuidePackLoad {
        switch inspect(rootURL: rootURL) {
        case .ready:
            return .ready
        case .missing:
            return .missing
        case .tooNew:
            return .tooNew
        }
    }

    private enum Inspect {
        case ready(GuidePackSnapshot)
        case missing
        case tooNew
    }

    private static func inspect(rootURL: URL?) -> Inspect {
        let key = rootURL?.standardizedFileURL.path ?? "bundle"
        if memoKey == key, let memoInspect {
            return memoInspect
        }
        let candidates: [URL?] = [
            rootURL,
            Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "GuidePack")?.deletingLastPathComponent(),
            Bundle.main.resourceURL?.appendingPathComponent("GuidePack", isDirectory: true),
            Bundle.main.bundleURL.appendingPathComponent("GuidePack", isDirectory: true)
        ]
        var sawTooNew = false
        var result: Inspect = .missing
        for candidate in candidates {
            guard let candidate else { continue }
            switch inspect(from: candidate) {
            case .ready(let snap):
                result = .ready(snap)
                memoKey = key
                memoInspect = result
                return result
            case .tooNew:
                sawTooNew = true
            case .missing:
                continue
            }
        }
        result = sawTooNew ? .tooNew : .missing
        memoKey = key
        memoInspect = result
        return result
    }

    private static func inspect(from root: URL) -> Inspect {
        let manifestURL = root.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .missing
        }
        let articlesURL = root.appendingPathComponent("articles.jsonl")
        guard let raw = try? String(contentsOf: articlesURL, encoding: .utf8) else { return .missing }
        var articles: [GuideArticle] = []
        var records: [[String: Any]] = []
        for line in raw.split(whereSeparator: \.isNewline) {
            guard let lineData = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let id = obj["id"] as? String,
                  let title = obj["title"] as? String,
                  let topic = obj["topic"] as? String,
                  let body = obj["body"] as? String else { continue }
            records.append(obj)
            let tags = obj["tags"] as? [String] ?? []
            articles.append(GuideArticle(id: id, title: title, topic: topic, tags: tags, body: body))
        }
        guard !articles.isEmpty else { return .missing }
        var index: [String: [String: Int]] = [:]
        var invertedJSON: [String: Any] = [:]
        let indexURL = root.appendingPathComponent("inverted.json")
        if let indexData = try? Data(contentsOf: indexURL),
           let obj = try? JSONSerialization.jsonObject(with: indexData) as? [String: Any] {
            invertedJSON = obj
            if let postings = obj as? [String: [String: Int]] {
                index = postings
            } else if let terms = obj["terms"] as? [String: [String: Int]] {
                index = terms
            }
        }
        if GuidePackSchema.inspect(manifest: json, articles: records, inverted: invertedJSON) == .tooNew {
            return .tooNew
        }
        let disclaimer = json["disclaimer"] as? String ?? "On-device guide."
        return .ready(GuidePackSnapshot(articles: articles, index: index, disclaimer: disclaimer))
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
        let articles = pack.articles.map { (id: $0.id, topic: $0.topic, tags: $0.tags) }
        GuideAskRanker.apply(context, to: &scores, articles: articles)
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
