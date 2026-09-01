import BlackoutCore
import XCTest
@testable import Field

final class GuideSchemaLoadTests: XCTestCase {
    func testCurrentV1ShapeLoads() throws {
        let root = try writePack(manifest: ["schema": 1], articles: [v1Article], inverted: ["water": ["a": 1]])
        XCTAssertEqual(GuidePackLoader.status(rootURL: root), .ready)
        let snap = try XCTUnwrap(GuidePackLoader.load(rootURL: root))
        XCTAssertEqual(snap.articles.map(\.id), ["a"])
    }

    func testMissingSchemaStillLoadsAsV1() throws {
        let root = try writePack(manifest: ["name": "core"], articles: [v1Article], inverted: ["water": ["a": 1]])
        XCTAssertEqual(GuidePackLoader.status(rootURL: root), .ready)
        XCTAssertNotNil(GuidePackLoader.load(rootURL: root))
    }

    func testNewerManifestFailsClosed() throws {
        let root = try writePack(manifest: ["schema": 2], articles: [v1Article], inverted: ["water": ["a": 1]])
        XCTAssertEqual(GuidePackLoader.status(rootURL: root), .tooNew)
        XCTAssertNil(GuidePackLoader.load(rootURL: root))
        XCTAssertEqual(GuidePackSchema.tooNewCopy, "Guide schema too new.")
    }

    func testNewerArticleFailsClosed() throws {
        var article = v1Article
        article["schema"] = 2
        let root = try writePack(manifest: ["schema": 1], articles: [article], inverted: ["water": ["a": 1]])
        XCTAssertEqual(GuidePackLoader.status(rootURL: root), .tooNew)
        XCTAssertNil(GuidePackLoader.load(rootURL: root))
    }

    func testNewerInvertedWrapperFailsClosed() throws {
        let root = try writePack(
            manifest: ["schema": 1],
            articles: [v1Article],
            inverted: ["schema": 2, "terms": ["water": ["a": 1]]]
        )
        XCTAssertEqual(GuidePackLoader.status(rootURL: root), .tooNew)
        XCTAssertNil(GuidePackLoader.load(rootURL: root))
    }

    private var v1Article: [String: Any] {
        ["id": "a", "title": "Water", "topic": "water", "body": "Treat it.", "tags": ["water"]]
    }

    private func writePack(
        manifest: [String: Any],
        articles: [[String: Any]],
        inverted: [String: Any]
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: manifest).write(to: root.appendingPathComponent("manifest.json"))
        let lines = try articles.map { article -> String in
            let data = try JSONSerialization.data(withJSONObject: article)
            return String(decoding: data, as: UTF8.self)
        }
        try (lines.joined(separator: "\n") + "\n").write(
            to: root.appendingPathComponent("articles.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try JSONSerialization.data(withJSONObject: inverted).write(to: root.appendingPathComponent("inverted.json"))
        return root
    }
}
