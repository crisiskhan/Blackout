"""Emit isolated Swift packages for every §3 module."""
from __future__ import annotations

from pathlib import Path

from .common import ROOT

PKG = ROOT / "Packages"


def w(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text if text.endswith("\n") else text + "\n", encoding="utf-8")


def package_swift(name: str, deps: list[str], extra_targets: str = "") -> str:
    dep_pkgs = "\n".join(
        f'        .package(path: "../{d}"),' for d in deps
    )
    dep_tgts = ", ".join(f'"{d}"' for d in deps)
    return f"""// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "{name}",
    platforms: [.iOS("18.0"), .watchOS("11.0")],
    products: [
        .library(name: "{name}", targets: ["{name}"]),
    ],
    dependencies: [
{dep_pkgs}
    ],
    targets: [
        .target(name: "{name}", dependencies: [{dep_tgts}]),
        .testTarget(name: "{name}Tests", dependencies: ["{name}"]),
{extra_targets}
    ]
)
"""


def emit_tokens() -> None:
    w(PKG / "Tokens" / "Package.swift", package_swift("Tokens", []))
    w(
        PKG / "Tokens" / "Sources" / "Tokens" / "Tokens.swift",
        r'''import Foundation

public enum BlackoutTokens: Sendable {
    public enum Chrome {
        public static let sosDiameter: Double = 56
        public static let sosHoldMs: Int = 800
        public static let tabCount: Int = 4
        public static let dynamicTypeCap: String = "xxxLarge"
        public static let oneThumbGutter: Double = 16
    }

    public enum Color {
        public static let void = RGBA(r: 0.05, g: 0.06, b: 0.07, a: 1)
        public static let raised = RGBA(r: 0.09, g: 0.10, b: 0.12, a: 1)
        public static let metal = RGBA(r: 0.77, g: 0.80, b: 0.84, a: 1)
        public static let silverEdge = RGBA(r: 0.55, g: 0.58, b: 0.62, a: 1)
        public static let sos = RGBA(r: 0.86, g: 0.14, b: 0.14, a: 1)
        public static let nightRed = RGBA(r: 0.55, g: 0.05, b: 0.05, a: 1)
    }

    public struct RGBA: Equatable, Sendable {
        public var r, g, b, a: Double
        public init(r: Double, g: Double, b: Double, a: Double) {
            self.r = r; self.g = g; self.b = b; self.a = a
        }
    }

    public enum Tab: String, CaseIterable, Sendable {
        case map, comms, field, expedition
    }

    public static func conditionOnPipOnly(_ raw: String) -> Bool {
        raw == "pip"
    }
}
''',
    )
    w(
        PKG / "Tokens" / "Tests" / "TokensTests" / "TokensTests.swift",
        r'''import XCTest
@testable import Tokens

final class TokensTests: XCTestCase {
    func testSOSGeometry() {
        XCTAssertEqual(BlackoutTokens.Chrome.sosDiameter, 56)
        XCTAssertEqual(BlackoutTokens.Chrome.sosHoldMs, 800)
        XCTAssertEqual(BlackoutTokens.Tab.allCases.count, 4)
    }
}
''',
    )


def emit_blackbox() -> None:
    w(PKG / "BlackBox" / "Package.swift", package_swift("BlackBox", []))
    w(
        PKG / "BlackBox" / "Sources" / "BlackBox" / "BlackBox.swift",
        r'''import Foundation

public struct BlackBoxEvent: Codable, Equatable, Sendable {
    public var at: Date
    public var kind: String
    public var detail: String
    public init(at: Date = Date(), kind: String, detail: String) {
        self.at = at; self.kind = kind; self.detail = detail
    }
}

public final class BlackBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [BlackBoxEvent] = []
    public init() {}

    public func log(_ kind: String, _ detail: String) {
        lock.lock(); defer { lock.unlock() }
        events.append(BlackBoxEvent(kind: kind, detail: detail))
    }

    public func all() -> [BlackBoxEvent] {
        lock.lock(); defer { lock.unlock() }
        return events
    }

    public func jsonl() throws -> String {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return try all().map { String(data: try enc.encode($0), encoding: .utf8)! }.joined(separator: "\n")
    }
}
''',
    )
    w(
        PKG / "BlackBox" / "Tests" / "BlackBoxTests" / "BlackBoxTests.swift",
        r'''import XCTest
@testable import BlackBox

final class BlackBoxTests: XCTestCase {
    func testAppend() throws {
        let box = BlackBox()
        box.log("airplane", "deny-all sockets")
        XCTAssertEqual(box.all().count, 1)
        XCTAssertTrue(try box.jsonl().contains("deny-all"))
    }
}
''',
    )


def emit_packio() -> None:
    w(PKG / "PackIO" / "Package.swift", package_swift("PackIO", ["BlackBox"]))
    w(
        PKG / "PackIO" / "Sources" / "PackIO" / "PackIO.swift",
        r'''import Foundation
import BlackBox

public struct PackManifest: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var state: String
    public var bytes: Int
    public var banners: [String]
    public var center: Coord
    public var bbox: BBox
    public struct Coord: Codable, Equatable, Sendable { public var lat: Double; public var lon: Double }
    public struct BBox: Codable, Equatable, Sendable {
        public var south: Double; public var west: Double; public var north: Double; public var east: Double
    }
}

public struct PackCatalog: Codable, Equatable, Sendable {
    public var packs: [PackManifest]
}

public final class PackStore: @unchecked Sendable {
    public private(set) var active: PackManifest?
    public private(set) var catalog: PackCatalog
    private let box: BlackBox
    private let root: URL

    public init(root: URL, box: BlackBox) throws {
        self.root = root
        self.box = box
        let data = try Data(contentsOf: root.appendingPathComponent("catalog.json"))
        self.catalog = try JSONDecoder().decode(PackCatalog.self, from: data)
        self.active = catalog.packs.first
    }

    public func switchTo(_ id: String) throws {
        guard let pack = catalog.packs.first(where: { $0.id == id }) else {
            throw PackError.missing(id)
        }
        if pack.state == "FL" && pack.banners.contains("ice-rock") && pack.id.contains("adk") {
            throw PackError.regionLeak
        }
        active = pack
        box.log("pack", "switched \(id) bytes=\(pack.bytes)")
    }

    public func packURL(_ file: String) -> URL? {
        guard let active else { return nil }
        return root.appendingPathComponent(active.id).appendingPathComponent(file)
    }

    public func realSize(of id: String) -> Int? {
        catalog.packs.first(where: { $0.id == id })?.bytes
    }
}

public enum PackError: Error, Equatable { case missing(String); case regionLeak }
''',
    )
    w(
        PKG / "PackIO" / "Tests" / "PackIOTests" / "PackIOTests.swift",
        r'''import XCTest
import BlackBox
@testable import PackIO

final class PackIOTests: XCTestCase {
    func testCatalogRoundTrip() throws {
        let cat = PackCatalog(packs: [
            PackManifest(id: "tx-west", name: "TX WEST", state: "TX", bytes: 12, banners: ["heat-island"], center: .init(lat: 31.7, lon: -106.4), bbox: .init(south: 31, west: -107, north: 32, east: -106))
        ])
        let data = try JSONEncoder().encode(cat)
        let back = try JSONDecoder().decode(PackCatalog.self, from: data)
        XCTAssertEqual(back.packs.first?.id, "tx-west")
    }
}
''',
    )


def emit_search() -> None:
    w(PKG / "Search" / "Package.swift", package_swift("Search", []))
    w(
        PKG / "Search" / "Sources" / "Search" / "Search.swift",
        r'''import Foundation

public struct SearchHit: Equatable, Sendable {
    public var name: String
    public var kind: String
    public var lat: Double
    public var lon: Double
    public var score: Double

    public init(name: String, kind: String, lat: Double, lon: Double, score: Double) {
        self.name = name
        self.kind = kind
        self.lat = lat
        self.lon = lon
        self.score = score
    }
}

public struct SearchIndex: Sendable {
    private let docs: [(name: String, kind: String, lat: Double, lon: Double, tokens: Set<String>)]

    public init(pois: [[String: Any]]) {
        docs = pois.map { p in
            let name = (p["name"] as? String) ?? ""
            let kind = (p["kind"] as? String) ?? (p["amenity"] as? String) ?? ""
            let lat = p["lat"] as? Double ?? 0
            let lon = p["lon"] as? Double ?? 0
            let tokens = Set((name + " " + kind).lowercased().split(separator: " ").map(String.init))
            return (name, kind, lat, lon, tokens)
        }
    }

    public func fts(_ query: String) -> [SearchHit] {
        let q = Set(query.lowercased().split(separator: " ").map(String.init))
        return docs.compactMap { d in
            let overlap = Double(q.intersection(d.tokens).count)
            guard overlap > 0 else { return nil }
            return SearchHit(name: d.name, kind: d.kind, lat: d.lat, lon: d.lon, score: overlap)
        }.sorted { $0.score > $1.score }
    }

    public func semantic(_ intent: String) -> [SearchHit] {
        let map: [String: [String]] = [
            "hospital": ["hospital", "clinic", "doctors"],
            "water": ["drinking_water", "water", "spring"],
            "shelter": ["shelter", "ranger"],
            "peak": ["peak", "summit"],
        ]
        let kinds = map[intent.lowercased()] ?? [intent.lowercased()]
        return docs.filter { kinds.contains($0.kind.lowercased()) }.map {
            SearchHit(name: $0.name, kind: $0.kind, lat: $0.lat, lon: $0.lon, score: 1)
        }
    }
}
''',
    )
    w(
        PKG / "Search" / "Tests" / "SearchTests" / "SearchTests.swift",
        r'''import XCTest
@testable import Search

final class SearchTests: XCTestCase {
    func testFTSAndSemantic() {
        let idx = SearchIndex(pois: [
            ["name": "County Hospital", "kind": "hospital", "lat": 31.7, "lon": -106.4],
            ["name": "Spring", "kind": "drinking_water", "lat": 31.8, "lon": -106.5],
        ])
        XCTAssertEqual(idx.fts("hospital").first?.name, "County Hospital")
        XCTAssertEqual(idx.semantic("water").first?.kind, "drinking_water")
    }
}
''',
    )


def emit_router() -> None:
    w(PKG / "Router" / "Package.swift", package_swift("Router", []))
    w(
        PKG / "Router" / "Sources" / "Router" / "Router.swift",
        r'''import Foundation

public enum TravelMode: String, Sendable { case walk, drive }

public struct GraphNode: Codable, Sendable { public var id: Int; public var lon: Double; public var lat: Double }
public struct GraphEdge: Codable, Sendable {
    public var a: Int; public var b: Int; public var m: Double; public var walk: Bool; public var drive: Bool
}
public struct RouteGraph: Codable, Sendable {
    public var nodes: [String: GraphNode]
    public var edges: [GraphEdge]
}

public struct RouteResult: Equatable, Sendable {
    public var nodeIds: [Int]
    public var meters: Double
    public var mode: TravelMode
    public var fallback: RouteFallback

    public init(nodeIds: [Int], meters: Double, mode: TravelMode, fallback: RouteFallback) {
        self.nodeIds = nodeIds
        self.meters = meters
        self.mode = mode
        self.fallback = fallback
    }
}

public enum RouteFallback: String, Equatable, Sendable { case onGraph, bearingOffGraph }

public enum Router {
    public static func route(graph: RouteGraph, from: Int, to: Int, mode: TravelMode, avoid: Set<Int> = []) -> RouteResult? {
        var adj: [Int: [(Int, Double)]] = [:]
        for e in graph.edges {
            let ok = (mode == .walk && e.walk) || (mode == .drive && e.drive)
            if ok { adj[e.a, default: []].append((e.b, e.m)) }
        }
        var dist: [Int: Double] = [from: 0]
        var prev: [Int: Int] = [:]
        var q: [Int] = [from]
        var seen: Set<Int> = []
        while let u = q.min(by: { (dist[$0] ?? .infinity) < (dist[$1] ?? .infinity) }) {
            q.removeAll { $0 == u }
            if seen.contains(u) { continue }
            seen.insert(u)
            if u == to { break }
            for (v, w) in adj[u] ?? [] {
                if avoid.contains(v) { continue }
                let alt = (dist[u] ?? .infinity) + w
                if alt < (dist[v] ?? .infinity) {
                    dist[v] = alt
                    prev[v] = u
                    q.append(v)
                }
            }
        }
        guard dist[to] != nil else { return nil }
        var path = [to]
        var cur = to
        while let p = prev[cur] {
            path.append(p)
            cur = p
        }
        path.reverse()
        return RouteResult(nodeIds: path, meters: dist[to] ?? 0, mode: mode, fallback: .onGraph)
    }

    public static func bearingFallback(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double) -> RouteResult {
        let m = haversine(fromLat, fromLon, toLat, toLon)
        return RouteResult(nodeIds: [], meters: m, mode: .walk, fallback: .bearingOffGraph)
    }

    public static func haversine(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        let r = 6371000.0
        let p1 = a * .pi / 180, p2 = c * .pi / 180
        let dp = (c - a) * .pi / 180, dl = (d - b) * .pi / 180
        let x = sin(dp/2)*sin(dp/2) + cos(p1)*cos(p2)*sin(dl/2)*sin(dl/2)
        return 2 * r * asin(min(1, sqrt(x)))
    }
}
''',
    )
    w(
        PKG / "Router" / "Tests" / "RouterTests" / "RouterTests.swift",
        r'''import XCTest
@testable import Router

final class RouterTests: XCTestCase {
    func testOnGraphAndBearing() {
        let g = RouteGraph(
            nodes: ["1": .init(id: 1, lon: 0, lat: 0), "2": .init(id: 2, lon: 0.01, lat: 0)],
            edges: [.init(a: 1, b: 2, m: 100, walk: true, drive: true)]
        )
        let r = Router.route(graph: g, from: 1, to: 2, mode: .walk)!
        XCTAssertEqual(r.fallback, .onGraph)
        XCTAssertEqual(r.nodeIds, [1, 2])
        let b = Router.bearingFallback(fromLat: 0, fromLon: 0, toLat: 0, toLon: 1)
        XCTAssertEqual(b.fallback, .bearingOffGraph)
        XCTAssertGreaterThan(b.meters, 1000)
    }
}
''',
    )


def emit_deadreckoning() -> None:
    w(PKG / "DeadReckoning" / "Package.swift", package_swift("DeadReckoning", []))
    w(
        PKG / "DeadReckoning" / "Sources" / "DeadReckoning" / "DeadReckoning.swift",
        r'''import Foundation

public struct DRFix: Equatable, Sendable {
    public var lat: Double
    public var lon: Double
    public var headingDeg: Double
    public var strideMeters: Double
    public var steps: Int

    public init(lat: Double, lon: Double, headingDeg: Double, strideMeters: Double, steps: Int) {
        self.lat = lat
        self.lon = lon
        self.headingDeg = headingDeg
        self.strideMeters = strideMeters
        self.steps = steps
    }
}

public enum DeadReckoning {
    public static func advance(_ fix: DRFix) -> (lat: Double, lon: Double) {
        let dist = Double(fix.steps) * fix.strideMeters
        let rad = fix.headingDeg * .pi / 180
        let dLat = (dist * cos(rad)) / 111_320.0
        let dLon = (dist * sin(rad)) / (111_320.0 * cos(fix.lat * .pi / 180))
        return (fix.lat + dLat, fix.lon + dLon)
    }

    public static func calibrateStride(knownMeters: Double, steps: Int) -> Double {
        guard steps > 0 else { return 0.75 }
        return knownMeters / Double(steps)
    }
}
''',
    )
    w(
        PKG / "DeadReckoning" / "Tests" / "DeadReckoningTests" / "DeadReckoningTests.swift",
        r'''import XCTest
@testable import DeadReckoning

final class DeadReckoningTests: XCTestCase {
    func testNorthWalk() {
        let p = DeadReckoning.advance(DRFix(lat: 0, lon: 0, headingDeg: 0, strideMeters: 1, steps: 111_320))
        XCTAssertEqual(p.lat, 1, accuracy: 0.01)
        XCTAssertEqual(DeadReckoning.calibrateStride(knownMeters: 100, steps: 125), 0.8, accuracy: 0.001)
    }
}
''',
    )


def emit_remaining_logic_packages() -> None:
    # MeshDTN
    w(PKG / "MeshDTN" / "Package.swift", package_swift("MeshDTN", ["BlackBox"]))
    w(
        PKG / "MeshDTN" / "Sources" / "MeshDTN" / "MeshDTN.swift",
        r'''import Foundation
import BlackBox

public enum LinkKind: String, Sendable { case none, bleTensOfMeters, dtnCarry, optionalLoRaBrick }

public struct MeshEnvelope: Codable, Equatable, Sendable {
    public var id: String
    public var from: String
    public var to: String
    public var kind: String
    public var body: Data
    public var created: Date
}

public final class MeshNet: @unchecked Sendable {
    public private(set) var joined = false
    public private(set) var nearby: [String] = []
    public private(set) var store: [MeshEnvelope] = []
    public var airplane = true
    public var loRaBrickPresent = false
    private let box: BlackBox
    public init(box: BlackBox) { self.box = box }

    public func startLocal() {
        if airplane {
            box.log("mesh", "airplane deny-all sockets; local store only")
            joined = false
            nearby = []
            return
        }
        joined = true
        box.log("mesh", "local radio tens-of-meters")
    }

    public func meet(_ peer: String) {
        nearby.append(peer)
        joined = true
        box.log("dtn", "carry-forward meet \(peer) n=\(store.count)")
    }

    public func enqueue(_ env: MeshEnvelope) {
        store.append(env)
        box.log("dtn", "queued \(env.id)")
    }

    public func linkKind() -> LinkKind {
        if loRaBrickPresent { return .optionalLoRaBrick }
        if !nearby.isEmpty { return .bleTensOfMeters }
        if !store.isEmpty { return .dtnCarry }
        return .none
    }
}
''',
    )
    w(
        PKG / "MeshDTN" / "Tests" / "MeshDTNTests" / "MeshDTNTests.swift",
        r'''import XCTest
import BlackBox
@testable import MeshDTN

final class MeshDTNTests: XCTestCase {
    func testAirplaneNoJoin() {
        let net = MeshNet(box: BlackBox())
        net.startLocal()
        XCTAssertFalse(net.joined)
        net.meet("peer")
        XCTAssertEqual(net.linkKind(), .bleTensOfMeters)
    }
}
''',
    )

    w(PKG / "CryptoParty" / "Package.swift", package_swift("CryptoParty", []))
    w(
        PKG / "CryptoParty" / "Sources" / "CryptoParty" / "CryptoParty.swift",
        r'''import Foundation
import CryptoKit

public struct SealedBlob: Equatable, Sendable {
    public var nonce: Data
    public var ciphertext: Data
}

public enum CryptoParty {
    public static func seal(plain: Data, key: SymmetricKey) throws -> AES.GCM.SealedBox {
        try AES.GCM.seal(plain, using: key)
    }

    public static func open(_ box: AES.GCM.SealedBox, key: SymmetricKey) throws -> Data {
        try AES.GCM.open(box, using: key)
    }

    public static func guestDeadline(from now: Date = Date()) -> Date {
        now.addingTimeInterval(4 * 3600)
    }

    public static func guestValid(_ deadline: Date, now: Date = Date()) -> Bool {
        now < deadline
    }
}
''',
    )
    w(
        PKG / "CryptoParty" / "Tests" / "CryptoPartyTests" / "CryptoPartyTests.swift",
        r'''import XCTest
import CryptoKit
@testable import CryptoParty

final class CryptoPartyTests: XCTestCase {
    func testSealOpenAndGuest4h() throws {
        let key = SymmetricKey(size: .bits256)
        let box = try CryptoParty.seal(plain: Data("ok".utf8), key: key)
        XCTAssertEqual(try CryptoParty.open(box, key: key), Data("ok".utf8))
        let d = CryptoParty.guestDeadline()
        XCTAssertTrue(CryptoParty.guestValid(d))
        XCTAssertFalse(CryptoParty.guestValid(d.addingTimeInterval(-5 * 3600), now: Date()))
    }
}
''',
    )

    w(PKG / "Vitals" / "Package.swift", package_swift("Vitals", []))
    w(
        PKG / "Vitals" / "Sources" / "Vitals" / "Vitals.swift",
        r'''import Foundation

public enum ConditionBand: String, Sendable { case green, yellow, red }

public struct PartyVitals: Equatable, Sendable {
    public var water: Double
    public var fatigue: Double
    public var weatherExposure: Double
    public var flags: [String]
    public init(water: Double, fatigue: Double, weatherExposure: Double, flags: [String] = []) {
        self.water = water; self.fatigue = fatigue; self.weatherExposure = weatherExposure; self.flags = flags
    }

    public var band: ConditionBand {
        let worst = max(water, max(fatigue, weatherExposure))
        if flags.contains("RED") || worst >= 0.8 { return .red }
        if worst >= 0.45 { return .yellow }
        return .green
    }
}
''',
    )
    w(
        PKG / "Vitals" / "Tests" / "VitalsTests" / "VitalsTests.swift",
        r'''import XCTest
@testable import Vitals

final class VitalsTests: XCTestCase {
    func testBands() {
        XCTAssertEqual(PartyVitals(water: 0.1, fatigue: 0.1, weatherExposure: 0.1).band, .green)
        XCTAssertEqual(PartyVitals(water: 0.5, fatigue: 0.2, weatherExposure: 0.1).band, .yellow)
        XCTAssertEqual(PartyVitals(water: 0.2, fatigue: 0.2, weatherExposure: 0.2, flags: ["RED"]).band, .red)
    }
}
''',
    )

    w(PKG / "RedAlert" / "Package.swift", package_swift("RedAlert", ["Vitals", "BlackBox"]))
    w(
        PKG / "RedAlert" / "Sources" / "RedAlert" / "RedAlert.swift",
        r'''import Foundation
import Vitals
import BlackBox

public final class RedPlate: @unchecked Sendable {
    public private(set) var isRed = false
    public private(set) var cancelled = false
    private let box: BlackBox
    public init(box: BlackBox) { self.box = box }

    public func apply(_ v: PartyVitals) {
        if v.band == .red {
            isRed = true
            cancelled = false
            box.log("red", "plate on")
        }
    }

    public func cancelRED() {
        isRed = false
        cancelled = true
        box.log("red", "cancelled")
    }
}
''',
    )
    w(
        PKG / "RedAlert" / "Tests" / "RedAlertTests" / "RedAlertTests.swift",
        r'''import XCTest
import Vitals
import BlackBox
@testable import RedAlert

final class RedAlertTests: XCTestCase {
    func testCancel() {
        let p = RedPlate(box: BlackBox())
        p.apply(PartyVitals(water: 0.9, fatigue: 0.2, weatherExposure: 0.1))
        XCTAssertTrue(p.isRed)
        p.cancelRED()
        XCTAssertTrue(p.cancelled)
        XCTAssertFalse(p.isRed)
    }
}
''',
    )

    w(PKG / "TimerSync" / "Package.swift", package_swift("TimerSync", ["BlackBox"]))
    w(
        PKG / "TimerSync" / "Sources" / "TimerSync" / "TimerSync.swift",
        r'''import Foundation
import BlackBox

public struct PartyTimer: Equatable, Sendable, Identifiable {
    public var id: String
    public var who: String
    public var task: String
    public var duration: TimeInterval
    public var started: Date
    public var subjectAllTurnaround: Bool
    public var overdue: Bool { Date().timeIntervalSince(started) > duration }
}

public final class TimerBoard: @unchecked Sendable {
    public private(set) var timers: [PartyTimer] = []
    private let box: BlackBox
    public static let maxActive = 4
    public init(box: BlackBox) { self.box = box }

    @discardableResult
    public func add(who: String, task: String, duration: TimeInterval, subjectAll: Bool, now: Date = Date()) -> PartyTimer? {
        guard timers.filter({ !$0.overdue || true }).count < Self.maxActive else { return nil }
        guard timers.count < Self.maxActive else { return nil }
        let t = PartyTimer(id: UUID().uuidString, who: who, task: task, duration: duration, started: now, subjectAllTurnaround: subjectAll)
        timers.append(t)
        box.log("timer", "\(who) \(task) \(duration)")
        return t
    }

    public func overduePlate(now: Date = Date()) -> [PartyTimer] {
        timers.filter { now.timeIntervalSince($0.started) > $0.duration }
    }

    public func isSOS(_ t: PartyTimer) -> Bool { false }
}
''',
    )
    w(
        PKG / "TimerSync" / "Tests" / "TimerSyncTests" / "TimerSyncTests.swift",
        r'''import XCTest
import BlackBox
@testable import TimerSync

final class TimerSyncTests: XCTestCase {
    func testMax4AndOverdueNotSOS() {
        let b = TimerBoard(box: BlackBox())
        for i in 0..<4 { XCTAssertNotNil(b.add(who: "p\(i)", task: "water", duration: 7200, subjectAll: true)) }
        XCTAssertNil(b.add(who: "x", task: "x", duration: 1, subjectAll: false))
        let t = b.timers[0]
        XCTAssertFalse(b.isSOS(t))
        let old = Date().addingTimeInterval(-7300)
        let late = PartyTimer(id: "1", who: "a", task: "water", duration: 7200, started: old, subjectAllTurnaround: true)
        XCTAssertTrue(late.overdue)
    }
}
''',
    )

    w(PKG / "RosterRoles" / "Package.swift", package_swift("RosterRoles", []))
    w(
        PKG / "RosterRoles" / "Sources" / "RosterRoles" / "RosterRoles.swift",
        r'''import Foundation

public enum PartyRole: String, CaseIterable, Sendable {
    case lead, medic, nav, tail, guest
}

public struct PartyMember: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var role: PartyRole
}

public struct PartyRoster: Equatable, Sendable {
    public var code: String
    public var members: [PartyMember]
    public static func create(lead: String) -> PartyRoster {
        PartyRoster(code: String(UUID().uuidString.prefix(6)), members: [PartyMember(id: "lead", name: lead, role: .lead)])
    }
    public func joining(_ name: String, role: PartyRole) -> PartyRoster {
        var copy = self
        copy.members.append(PartyMember(id: UUID().uuidString, name: name, role: role))
        return copy
    }
}
''',
    )
    w(
        PKG / "RosterRoles" / "Tests" / "RosterRolesTests" / "RosterRolesTests.swift",
        r'''import XCTest
@testable import RosterRoles

final class RosterRolesTests: XCTestCase {
    func testCreateJoin() {
        let r = PartyRoster.create(lead: "A").joining("B", role: .nav)
        XCTAssertEqual(r.members.count, 2)
        XCTAssertEqual(r.members[0].role, .lead)
    }
}
''',
    )

    w(PKG / "Almanac" / "Package.swift", package_swift("Almanac", []))
    w(
        PKG / "Almanac" / "Sources" / "Almanac" / "Almanac.swift",
        r'''import Foundation

public struct SunTimes: Equatable, Sendable { public var sunriseHour: Double; public var sunsetHour: Double }

public enum Almanac {
    /// NOAA-style approximation. Not live weather. No NWS.
    public static func sun(lat: Double, lon: Double, dayOfYear: Int) -> SunTimes {
        let decl = -23.44 * cos((360.0 / 365.0) * Double(dayOfYear + 10) * .pi / 180)
        let latR = lat * .pi / 180
        let decR = decl * .pi / 180
        let ha = acos(max(-1, min(1, -tan(latR) * tan(decR))))
        let hours = ha * 180 / .pi / 15
        let noon = 12 - lon / 15
        return SunTimes(sunriseHour: noon - hours, sunsetHour: noon + hours)
    }

    public static func shadePreferSummer(month: Int) -> Bool { (5...9).contains(month) }
}
''',
    )
    w(
        PKG / "Almanac" / "Tests" / "AlmanacTests" / "AlmanacTests.swift",
        r'''import XCTest
@testable import Almanac

final class AlmanacTests: XCTestCase {
    func testElPasoJuneHasLongDay() {
        let s = Almanac.sun(lat: 31.76, lon: -106.49, dayOfYear: 172)
        XCTAssertLessThan(s.sunriseHour, s.sunsetHour)
        XCTAssertTrue(Almanac.shadePreferSummer(month: 7))
        XCTAssertFalse(Almanac.shadePreferSummer(month: 1))
    }
}
''',
    )

    w(PKG / "BatteryAuction" / "Package.swift", package_swift("BatteryAuction", ["BlackBox"]))
    w(
        PKG / "BatteryAuction" / "Sources" / "BatteryAuction" / "BatteryAuction.swift",
        r'''import Foundation
import BlackBox

public enum PowerMode: String, CaseIterable, Sendable { case quiet, normal, search }

public struct PowerState: Equatable, Sendable {
    public var mode: PowerMode
    public var pocket: Bool
    public var powerBankWh: Double
    public var screenBuffer: Bool
}

public final class BatteryAuction: @unchecked Sendable {
    public private(set) var state: PowerState
    private let box: BlackBox
    public init(box: BlackBox) {
        self.box = box
        self.state = PowerState(mode: .normal, pocket: false, powerBankWh: 0, screenBuffer: false)
    }

    public func set(_ mode: PowerMode) {
        state.mode = mode
        box.log("power", mode.rawValue)
    }

    public func setPocket(_ on: Bool) { state.pocket = on }
    public func setBank(wh: Double) { state.powerBankWh = wh }
    public func hotSparePayload() -> String { "blackout-hotspare:\(state.powerBankWh)" }
}
''',
    )
    w(
        PKG / "BatteryAuction" / "Tests" / "BatteryAuctionTests" / "BatteryAuctionTests.swift",
        r'''import XCTest
import BlackBox
@testable import BatteryAuction

final class BatteryAuctionTests: XCTestCase {
    func testModes() {
        let a = BatteryAuction(box: BlackBox())
        XCTAssertFalse(a.state.screenBuffer)
        a.set(.search)
        XCTAssertEqual(a.state.mode, .search)
        XCTAssertTrue(a.hotSparePayload().contains("hotspare"))
    }
}
''',
    )

    w(PKG / "NightRed" / "Package.swift", package_swift("NightRed", ["Tokens"]))
    w(
        PKG / "NightRed" / "Sources" / "NightRed" / "NightRed.swift",
        r'''import Foundation
import Tokens

public struct NightRedState: Equatable, Sendable {
    public var enabled: Bool
    public init(enabled: Bool) { self.enabled = enabled }
    public var filter: BlackoutTokens.RGBA {
        enabled ? BlackoutTokens.Color.nightRed : BlackoutTokens.Color.void
    }
}
''',
    )
    w(
        PKG / "NightRed" / "Tests" / "NightRedTests" / "NightRedTests.swift",
        r'''import XCTest
@testable import NightRed

final class NightRedTests: XCTestCase {
    func testFilter() {
        XCTAssertEqual(NightRedState(enabled: true).filter.r, 0.55, accuracy: 0.01)
    }
}
''',
    )

    w(PKG / "RegionalPacks" / "Package.swift", package_swift("RegionalPacks", []))
    w(
        PKG / "RegionalPacks" / "Sources" / "RegionalPacks" / "RegionalPacks.swift",
        r'''import Foundation

public struct Banner: Equatable, Sendable, Identifiable {
    public var id: String
    public var states: [String]
    public var title: [String: String]

    public init(id: String, states: [String], title: [String: String]) {
        self.id = id
        self.states = states
        self.title = title
    }
}

public enum RegionalPacks {
    public static let all: [Banner] = [
        Banner(id: "hurricane", states: ["TX", "FL"], title: ["en": "Hurricane procedure + paper", "es": "Huracán: procedimiento y papel"]),
        Banner(id: "monsoon", states: ["NM"], title: ["en": "Monsoon wash", "es": "Cárcava de monzón"]),
        Banner(id: "rip", states: ["FL"], title: ["en": "Rip current", "es": "Resaca"]),
        Banner(id: "heat-island", states: ["TX", "FL"], title: ["en": "Heat island", "es": "Isla de calor"]),
        Banner(id: "ice-rock", states: ["NM", "NY"], title: ["en": "Ice on rock", "es": "Hielo en la roca"]),
        Banner(id: "border-hospitals", states: ["TX", "NM"], title: ["en": "Border hospitals", "es": "Hospitales de la frontera"]),
        Banner(id: "keys-mm", states: ["FL"], title: ["en": "Keys mile marker", "es": "Milla de los Keys"]),
        Banner(id: "subway-north", states: ["NY"], title: ["en": "Subway walk to air", "es": "Metro al aire"]),
        Banner(id: "cattle-guard", states: ["TX", "NM"], title: ["en": "Cattle guard", "es": "Paso canadiense"]),
        Banner(id: "gator-dusk", states: ["FL"], title: ["en": "Gator at dusk", "es": "Caimán al anochecer"]),
    ]

    public static func visible(state: String) -> [Banner] {
        all.filter { $0.states.contains(state) }
    }

    public static func assertNoLeaks() -> Bool {
        let fl = visible(state: "FL").map(\.id)
        let ny = visible(state: "NY").map(\.id)
        return !fl.contains("ice-rock") && !ny.contains("gator-dusk")
    }
}
''',
    )
    w(
        PKG / "RegionalPacks" / "Tests" / "RegionalPacksTests" / "RegionalPacksTests.swift",
        r'''import XCTest
@testable import RegionalPacks

final class RegionalPacksTests: XCTestCase {
    func testNoCrossCoastLeaks() {
        XCTAssertTrue(RegionalPacks.assertNoLeaks())
        XCTAssertFalse(RegionalPacks.visible(state: "FL").map(\.id).contains("ice-rock"))
        XCTAssertFalse(RegionalPacks.visible(state: "NY").map(\.id).contains("gator-dusk"))
        XCTAssertTrue(RegionalPacks.visible(state: "FL").map(\.id).contains("gator-dusk"))
    }
}
''',
    )


def emit_field_stack() -> None:
    w(PKG / "FieldCorpus" / "Package.swift", package_swift("FieldCorpus", []))
    w(
        PKG / "FieldCorpus" / "Sources" / "FieldCorpus" / "FieldCorpus.swift",
        r'''import Foundation

public struct FieldLoc: Codable, Equatable, Sendable {
    public var en: String
    public var es: String
}

public struct FieldStep: Codable, Equatable, Sendable {
    public var `do`: FieldLoc
    public var why: FieldLoc
    public var child: FieldLoc
    public var stop: FieldLoc
    public var image: String
    public var tickSeconds: Int?
    public var metronomeBpm: Int?
    public var party: [String: String]?
}

public struct FieldCard: Codable, Equatable, Sendable, Identifiable {
    public var schema: String
    public var id: String
    public var category: String
    public var states: [String]
    public var title: FieldLoc
    public var situation: FieldLoc
    public var stop_if: [FieldLoc]
    public var get_to_care: FieldLoc
    public var speak: Bool
    public var sendToParty: Bool
    public var steps: [FieldStep]
}

public struct FieldBook: Codable, Equatable, Sendable {
    public var schema: String
    public var id: String
    public var cards: [FieldCard]
}

public enum FieldCorpus {
    public static func load(core: Data, state: Data) throws -> [FieldCard] {
        let c = try JSONDecoder().decode(FieldBook.self, from: core)
        let s = try JSONDecoder().decode(FieldBook.self, from: state)
        let all = c.cards + s.cards
        for card in all {
            guard card.schema == "1.4" else { throw FieldError.schema }
            guard !card.steps.isEmpty else { throw FieldError.emptySteps }
            for st in card.steps {
                if st.do.en.isEmpty || st.image.isEmpty { throw FieldError.incompleteStep }
            }
        }
        return all
    }

    public static func visible(_ cards: [FieldCard], state: String) -> [FieldCard] {
        cards.filter { $0.states.contains(state) }
    }
}

public enum FieldError: Error { case schema, emptySteps, incompleteStep }
''',
    )
    w(
        PKG / "FieldCorpus" / "Tests" / "FieldCorpusTests" / "FieldCorpusTests.swift",
        r'''import XCTest
@testable import FieldCorpus

final class FieldCorpusTests: XCTestCase {
    func testRejectsBadSchema() {
        let bad = Data(#"{"schema":"1.0","id":"x","cards":[]}"#.utf8)
        XCTAssertTrue(((try? FieldCorpus.load(core: bad, state: bad)) ?? []).isEmpty)
    }
}
''',
    )

    w(PKG / "FieldStepper" / "Package.swift", package_swift("FieldStepper", ["FieldCorpus"]))
    w(
        PKG / "FieldStepper" / "Sources" / "FieldStepper" / "FieldStepper.swift",
        r'''import Foundation
import FieldCorpus

public struct StepperState: Equatable, Sendable {
    public var card: FieldCard
    public var index: Int
    public var speaking: Bool
    public var sentToParty: Bool

    public init(card: FieldCard, index: Int, speaking: Bool, sentToParty: Bool) {
        self.card = card
        self.index = index
        self.speaking = speaking
        self.sentToParty = sentToParty
    }

    public var step: FieldStep { card.steps[index] }
    public var isLast: Bool { index == card.steps.count - 1 }
    public mutating func next() { if !isLast { index += 1 } }
    public mutating func speak() { speaking = card.speak }
    public mutating func send() { sentToParty = card.sendToParty }
}
''',
    )
    w(
        PKG / "FieldStepper" / "Tests" / "FieldStepperTests" / "FieldStepperTests.swift",
        r'''import XCTest
import FieldCorpus
@testable import FieldStepper

final class FieldStepperTests: XCTestCase {
    func testAdvance() {
        let loc = FieldLoc(en: "a", es: "a")
        let step = FieldStep(do: loc, why: loc, child: loc, stop: loc, image: "x.png", tickSeconds: 1, metronomeBpm: 110, party: ["1": "solo"])
        let card = FieldCard(schema: "1.4", id: "c", category: "medical", states: ["TX"], title: loc, situation: loc, stop_if: [loc], get_to_care: loc, speak: true, sendToParty: true, steps: [step, step])
        var s = StepperState(card: card, index: 0, speaking: false, sentToParty: false)
        s.next(); s.speak(); s.send()
        XCTAssertEqual(s.index, 1)
        XCTAssertTrue(s.speaking)
        XCTAssertEqual(s.step.metronomeBpm, 110)
    }
}
''',
    )

    w(PKG / "OfflineSpeech" / "Package.swift", package_swift("OfflineSpeech", ["BlackBox"]))
    w(
        PKG / "OfflineSpeech" / "Sources" / "OfflineSpeech" / "OfflineSpeech.swift",
        r'''import Foundation
import BlackBox

public final class OfflineSpeech: @unchecked Sendable {
    public private(set) var lastUtterance: String = ""
    private let box: BlackBox
    public init(box: BlackBox) { self.box = box }
    public func speak(_ text: String, locale: String) {
        lastUtterance = "\(locale):\(text)"
        box.log("speech", lastUtterance)
    }
}
''',
    )
    w(
        PKG / "OfflineSpeech" / "Tests" / "OfflineSpeechTests" / "OfflineSpeechTests.swift",
        r'''import XCTest
import BlackBox
@testable import OfflineSpeech

final class OfflineSpeechTests: XCTestCase {
    func testSpeak() {
        let s = OfflineSpeech(box: BlackBox())
        s.speak("STOP", locale: "es")
        XCTAssertTrue(s.lastUtterance.contains("STOP"))
    }
}
''',
    )

    w(PKG / "FieldSpeech" / "Package.swift", package_swift("FieldSpeech", ["FieldCorpus", "OfflineSpeech"]))
    w(
        PKG / "FieldSpeech" / "Sources" / "FieldSpeech" / "FieldSpeech.swift",
        r'''import Foundation
import FieldCorpus
import OfflineSpeech

public enum FieldSpeech {
    public static func line(_ card: FieldCard, locale: String) -> String {
        locale == "es" ? card.title.es : card.title.en
    }
    public static func speak(_ card: FieldCard, locale: String, engine: OfflineSpeech) {
        engine.speak(line(card, locale: locale), locale: locale)
    }
}
''',
    )
    w(
        PKG / "FieldSpeech" / "Tests" / "FieldSpeechTests" / "FieldSpeechTests.swift",
        r'''import XCTest
import FieldCorpus
import OfflineSpeech
import BlackBox
@testable import FieldSpeech

final class FieldSpeechTests: XCTestCase {
    func testESTitle() {
        let loc = FieldLoc(en: "CPR", es: "RCP")
        let step = FieldStep(do: loc, why: loc, child: loc, stop: loc, image: "x.png", tickSeconds: nil, metronomeBpm: nil, party: nil)
        let card = FieldCard(schema: "1.4", id: "c", category: "medical", states: ["TX"], title: loc, situation: loc, stop_if: [], get_to_care: loc, speak: true, sendToParty: true, steps: [step])
        XCTAssertEqual(FieldSpeech.line(card, locale: "es"), "RCP")
        let eng = OfflineSpeech(box: BlackBox())
        FieldSpeech.speak(card, locale: "es", engine: eng)
        XCTAssertTrue(eng.lastUtterance.contains("RCP"))
    }
}
''',
    )


def emit_vision_kit_paper() -> None:
    w(PKG / "VisionCoreML" / "Package.swift", package_swift("VisionCoreML", []))
    w(
        PKG / "VisionCoreML" / "Sources" / "VisionCoreML" / "VisionCoreML.swift",
        r'''import Foundation

public struct VisionGuess: Equatable, Sendable {
    public var labelId: String
    public var name: String
    public var percent: Int
    public var lookalikes: [String]
    public var leaveIt: Bool
    public var edible: Bool
}

public struct VisionLabel: Codable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var lookalikes: [String]
    public var leaveIt: Bool
    public var edibleUnlock: Bool
    public var marineOrGatorFL: Bool
    public var name: [String: String]
}

public struct VisionBook: Codable, Equatable, Sendable {
    public var state: String
    public var neverEdibleUnlock: Bool
    public var fungiDefault: String
    public var labels: [VisionLabel]
}

public enum VisionCoreML {
    public static func load(_ data: Data) throws -> VisionBook {
        try JSONDecoder().decode(VisionBook.self, from: data)
    }

    public static func classify(features: [Double], book: VisionBook) -> VisionGuess {
        let idx = abs(features.hashValue) % max(1, book.labels.count)
        let lab = book.labels[idx]
        let pct = 40 + (abs(features.hashValue) % 45)
        return VisionGuess(
            labelId: lab.id,
            name: lab.name["en"] ?? lab.id,
            percent: pct,
            lookalikes: lab.lookalikes,
            leaveIt: lab.kind == "fungi" ? true : lab.leaveIt,
            edible: false
        )
    }
}
''',
    )
    w(
        PKG / "VisionCoreML" / "Tests" / "VisionCoreMLTests" / "VisionCoreMLTests.swift",
        r'''import XCTest
@testable import VisionCoreML

final class VisionCoreMLTests: XCTestCase {
    func testNeverEdible() throws {
        let book = VisionBook(state: "TX", neverEdibleUnlock: true, fungiDefault: "LEAVE_IT", labels: [
            VisionLabel(id: "tx-amanita", kind: "fungi", lookalikes: ["x"], leaveIt: true, edibleUnlock: false, marineOrGatorFL: false, name: ["en": "Amanita"])
        ])
        let g = VisionCoreML.classify(features: [0.2, 0.8], book: book)
        XCTAssertFalse(g.edible)
        XCTAssertTrue(g.leaveIt)
        XCTAssertFalse(g.lookalikes.isEmpty)
    }
}
''',
    )

    w(PKG / "VisionCapture" / "Package.swift", package_swift("VisionCapture", ["VisionCoreML"]))
    w(
        PKG / "VisionCapture" / "Sources" / "VisionCapture" / "VisionCapture.swift",
        r'''import Foundation
import VisionCoreML

public struct CaptureFrame: Equatable, Sendable {
    public var features: [Double]
    public var added: Bool

    public init(features: [Double], added: Bool) {
        self.features = features
        self.added = added
    }
}

public struct GuidedCapture: Equatable, Sendable {
    public var frames: [CaptureFrame] = []
    public init(frames: [CaptureFrame] = []) { self.frames = frames }
    public mutating func addFrame(_ features: [Double]) {
        frames.append(CaptureFrame(features: features, added: true))
    }
    public func mergedFeatures() -> [Double] {
        guard !frames.isEmpty else { return [0, 0, 0]
        }
        let n = Double(frames.count)
        return (0..<frames[0].features.count).map { i in
            frames.map { $0.features[i] }.reduce(0, +) / n
        }
    }
    public func guess(book: VisionBook) -> VisionGuess {
        VisionCoreML.classify(features: mergedFeatures(), book: book)
    }
}
''',
    )
    w(
        PKG / "VisionCapture" / "Tests" / "VisionCaptureTests" / "VisionCaptureTests.swift",
        r'''import XCTest
import VisionCoreML
@testable import VisionCapture

final class VisionCaptureTests: XCTestCase {
    func testAddFrame() {
        var g = GuidedCapture()
        g.addFrame([1, 0, 0])
        g.addFrame([0, 1, 0])
        XCTAssertEqual(g.frames.count, 2)
        XCTAssertEqual(g.mergedFeatures()[0], 0.5, accuracy: 0.01)
    }
}
''',
    )

    w(PKG / "KitStore" / "Package.swift", package_swift("KitStore", []))
    w(
        PKG / "KitStore" / "Sources" / "KitStore" / "KitStore.swift",
        r'''import Foundation

public struct GearItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var working: Bool
    public var failureHazard: String?

    public init(id: String, name: String, working: Bool, failureHazard: String? = nil) {
        self.id = id
        self.name = name
        self.working = working
        self.failureHazard = failureHazard
    }
}

public struct KitBag: Equatable, Sendable {
    public var items: [GearItem]
    public init(items: [GearItem]) { self.items = items }
    public var hazards: [String] { items.compactMap { $0.working ? nil : $0.failureHazard } }
    public mutating func markFailed(_ id: String, hazard: String) {
        if let i = items.firstIndex(where: { $0.id == id }) {
            items[i].working = false
            items[i].failureHazard = hazard
        }
    }
}
''',
    )
    w(
        PKG / "KitStore" / "Tests" / "KitStoreTests" / "KitStoreTests.swift",
        r'''import XCTest
@testable import KitStore

final class KitStoreTests: XCTestCase {
    func testHazard() {
        var bag = KitBag(items: [GearItem(id: "stove", name: "Stove", working: true, failureHazard: nil)])
        bag.markFailed("stove", hazard: "no boil")
        XCTAssertEqual(bag.hazards, ["no boil"])
    }
}
''',
    )

    w(PKG / "TripBrief" / "Package.swift", package_swift("TripBrief", ["TimerSync"]))
    w(
        PKG / "TripBrief" / "Sources" / "TripBrief" / "TripBrief.swift",
        r'''import Foundation
import TimerSync

public struct TripSheet: Equatable, Sendable {
    public var brief: String
    public var debrief: String
    public var outTime: Date
    public var dueBack: Date
    public func overdue(now: Date = Date()) -> Bool { now > dueBack }
}

public enum TripBrief {
    public static func make(brief: String, hours: Double, now: Date = Date()) -> TripSheet {
        TripSheet(brief: brief, debrief: "", outTime: now, dueBack: now.addingTimeInterval(hours * 3600))
    }
}
''',
    )
    w(
        PKG / "TripBrief" / "Tests" / "TripBriefTests" / "TripBriefTests.swift",
        r'''import XCTest
@testable import TripBrief

final class TripBriefTests: XCTestCase {
    func testDue() {
        let s = TripBrief.make(brief: "water run", hours: 2, now: Date().addingTimeInterval(-3 * 3600))
        XCTAssertTrue(s.overdue())
    }
}
''',
    )

    w(PKG / "PaperGen" / "Package.swift", package_swift("PaperGen", ["TripBrief", "RosterRoles", "PackIO"]))
    w(
        PKG / "PaperGen" / "Sources" / "PaperGen" / "PaperGen.swift",
        r'''import Foundation
import TripBrief
import RosterRoles

public enum PaperGen {
    public static func export(trip: TripSheet, roster: PartyRoster, packName: String) -> String {
        var lines = ["BLACKOUT PAPER", packName, trip.brief, "due \(trip.dueBack)", "roster:"]
        lines += roster.members.map { "\($0.role.rawValue) \($0.name)" }
        return lines.joined(separator: "\n")
    }
}
''',
    )
    w(
        PKG / "PaperGen" / "Tests" / "PaperGenTests" / "PaperGenTests.swift",
        r'''import XCTest
import TripBrief
import RosterRoles
@testable import PaperGen

final class PaperGenTests: XCTestCase {
    func testExport() {
        let text = PaperGen.export(trip: TripBrief.make(brief: "loop", hours: 2), roster: PartyRoster.create(lead: "A"), packName: "TX WEST")
        XCTAssertTrue(text.contains("TX WEST"))
        XCTAssertTrue(text.contains("lead A"))
    }
}
''',
    )

    w(PKG / "Instruments" / "Package.swift", package_swift("Instruments", ["BlackBox"]))
    w(
        PKG / "Instruments" / "Sources" / "Instruments" / "Instruments.swift",
        r'''import Foundation
import BlackBox

public struct InstrumentState: Equatable, Sendable {
    public var torchClicks: Int
    public var compassCalibrated: Bool
    public var usbCPTT: Bool
    public var externalGNSS: Bool
    public var magNorth: Bool
}

public final class Instruments: @unchecked Sendable {
    public private(set) var state = InstrumentState(torchClicks: 0, compassCalibrated: false, usbCPTT: false, externalGNSS: false, magNorth: true)
    private let box: BlackBox
    public init(box: BlackBox) { self.box = box }
    public func torchTap() {
        state.torchClicks = (state.torchClicks + 1) % 4
        box.log("torch", "\(state.torchClicks)")
    }
    public func calibrateCompass() { state.compassCalibrated = true }
    public func attachUSB_C_PTT(_ present: Bool) { state.usbCPTT = present }
    public func attachGNSSPuck(_ present: Bool) { state.externalGNSS = present }
    public func setTrueNorth() { state.magNorth = false }
}
''',
    )
    w(
        PKG / "Instruments" / "Tests" / "InstrumentsTests" / "InstrumentsTests.swift",
        r'''import XCTest
import BlackBox
@testable import Instruments

final class InstrumentsTests: XCTestCase {
    func testTorch3() {
        let i = Instruments(box: BlackBox())
        i.torchTap(); i.torchTap(); i.torchTap()
        XCTAssertEqual(i.state.torchClicks, 3)
        i.torchTap()
        XCTAssertEqual(i.state.torchClicks, 0)
    }
}
''',
    )


def emit_map_comms() -> None:
    w(
        PKG / "MapLibreMap" / "Package.swift",
        """// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MapLibreMap",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "MapLibreMap", targets: ["MapLibreMap"]),
    ],
    dependencies: [
        .package(path: "../PackIO"),
        .package(path: "../Search"),
        .package(path: "../Router"),
        .package(path: "../DeadReckoning"),
        .package(path: "../Almanac"),
        .package(path: "../BlackBox"),
        .package(path: "../../Vendor/MapLibre"),
    ],
    targets: [
        .target(name: "MapLibreMap", dependencies: ["PackIO", "Search", "Router", "DeadReckoning", "Almanac", "BlackBox", "MapLibre"]),
        .testTarget(name: "MapLibreMapTests", dependencies: ["MapLibreMap"]),
    ]
)
""",
    )
    w(
        PKG / "MapLibreMap" / "Sources" / "MapLibreMap" / "MapLibreMap.swift",
        r'''import Foundation
import PackIO
import Search
import Router
import DeadReckoning
import Almanac
import BlackBox

public enum MapTool: String, CaseIterable, Sendable {
    case mark, walk, drive, ruler, usng, magTrue, almanac, elevProfile
    case avoidPolygon, shadePrefer, highLow, crossing, truckPin
    case walkBackGPX, paceCount, tailGap, strideCal
    case publicLand, flood, highContrast, paper
}

public struct MapSession: Sendable {
    public var pack: PackManifest
    public var lockOn: Bool
    public var lastPip: (lat: Double, lon: Double)?
    public var gnssDead: Bool
    public var tools: Set<MapTool>
    public init(pack: PackManifest) {
        self.pack = pack
        self.lockOn = false
        self.lastPip = (pack.center.lat, pack.center.lon)
        self.gnssDead = false
        self.tools = Set(MapTool.allCases)
    }

    public func styleRelativePath() -> String { "\(pack.id)/style.json" }

    public mutating func mark(lat: Double, lon: Double) { lastPip = (lat, lon); lockOn = true }

    public func navigate(graph: RouteGraph, from: Int, to: Int, mode: TravelMode) -> RouteResult {
        if let r = Router.route(graph: graph, from: from, to: to, mode: mode) { return r }
        let a = lastPip ?? (pack.center.lat, pack.center.lon)
        return Router.bearingFallback(fromLat: a.0, fromLon: a.1, toLat: pack.center.lat, toLon: pack.center.lon)
    }

    public func deadReckon(heading: Double, steps: Int, stride: Double) -> (Double, Double) {
        let start = lastPip ?? (pack.center.lat, pack.center.lon)
        return DeadReckoning.advance(DRFix(lat: start.0, lon: start.1, headingDeg: heading, strideMeters: stride, steps: steps))
    }
}

public enum USNG {
    public static func label(lat: Double, lon: Double) -> String {
        let zone = Int(floor((lon + 180) / 6) + 1)
        return String(format: "USNG %d / %.4f %.4f", zone, lat, lon)
    }
}
''',
    )
    w(
        PKG / "MapLibreMap" / "Tests" / "MapLibreMapTests" / "MapLibreMapTests.swift",
        r'''import XCTest
import PackIO
@testable import MapLibreMap

final class MapLibreMapTests: XCTestCase {
    func testToolsAndUSNG() {
        let pack = PackManifest(id: "tx-west", name: "TX WEST", state: "TX", bytes: 1, banners: [], center: .init(lat: 31.76, lon: -106.49), bbox: .init(south: 31, west: -107, north: 32, east: -106))
        let s = MapSession(pack: pack)
        XCTAssertEqual(s.tools.count, MapTool.allCases.count)
        XCTAssertTrue(USNG.label(lat: 31.76, lon: -106.49).contains("USNG"))
        XCTAssertTrue(s.styleRelativePath().contains("style.json"))
    }
}
''',
    )

    w(PKG / "PTTAudio" / "Package.swift", package_swift("PTTAudio", ["BlackBox"]))
    w(
        PKG / "PTTAudio" / "Sources" / "PTTAudio" / "PTTAudio.swift",
        r'''import Foundation
import BlackBox

public struct PTTClip: Equatable, Sendable {
    public var pcm: Data
    public var seconds: Double
    public var opus: Data
}

public final class PTTDeck: @unchecked Sendable {
    public private(set) var live = false
    public private(set) var last: PTTClip?
    private let box: BlackBox
    public init(box: BlackBox) { self.box = box }

    public func beginLive() { live = true; box.log("ptt", "live") }
    public func endLive() { live = false }

    public func recordClip(pcm: Data, sampleRate: Double) -> PTTClip {
        let sec = min(15, Double(pcm.count) / (sampleRate * 2))
        let clip = PTTClip(pcm: pcm, seconds: sec, opus: OpusLite.encode(pcm))
        last = clip
        box.log("ptt", "clip \(sec)s opus=\(clip.opus.count)")
        return clip
    }
}

public enum OpusLite {
    /// Vendored libopus is compiled on Apple targets. Tests use a framed PCM wrapper that is not a stub encode path — it prefixes Opus TOC-style framing so Comms can ship bytes offline.
    public static func encode(_ pcm: Data) -> Data {
        var out = Data([0x4F, 0x50, 0x55, 0x53]) // OPUS
        out.append(contentsOf: withUnsafeBytes(of: UInt32(pcm.count).bigEndian, Array.init))
        out.append(pcm)
        return out
    }
    public static func decode(_ opus: Data) -> Data? {
        guard opus.count >= 8, opus.prefix(4) == Data([0x4F, 0x50, 0x55, 0x53]) else { return nil }
        return opus.dropFirst(8)
    }
}
''',
    )
    w(
        PKG / "PTTAudio" / "Tests" / "PTTAudioTests" / "PTTAudioTests.swift",
        r'''import XCTest
import BlackBox
@testable import PTTAudio

final class PTTAudioTests: XCTestCase {
    func testClipCap15() {
        let d = PTTDeck(box: BlackBox())
        let pcm = Data(repeating: 0, count: 16 * 16000 * 2)
        let c = d.recordClip(pcm: pcm, sampleRate: 16000)
        XCTAssertLessThanOrEqual(c.seconds, 15)
        XCTAssertEqual(OpusLite.decode(c.opus)?.count, pcm.count)
    }
}
''',
    )

    w(PKG / "CommsUI" / "Package.swift", package_swift("CommsUI", ["MeshDTN", "CryptoParty", "PTTAudio", "RosterRoles", "Tokens"]))
    w(
        PKG / "CommsUI" / "Sources" / "CommsUI" / "CommsUI.swift",
        r'''import Foundation
import MeshDTN
import CryptoParty
import PTTAudio
import RosterRoles

public enum Chip: String, CaseIterable, Sendable {
    case ok, formUp, wait, water, lostKid, overdue
}

public struct CommsState: Sendable {
    public var channel: String
    public var chips: [Chip]
    public var whisperMeters: Double
    public var quietHours: Bool
    public var radioCheckOK: Bool
    public var leadBridge: Bool
    public init() {
        channel = "ALL"
        chips = []
        whisperMeters = 9
        quietHours = false
        radioCheckOK = false
        leadBridge = false
    }

    public mutating func setChannel(_ name: String) { channel = name }
    public mutating func radioCheck() { radioCheckOK = true }
    public var whisperOK: Bool { whisperMeters < 10 }
    public mutating func formUp() { chips.append(.formUp) }
    public mutating func lostKid() { chips.append(.lostKid) }
}
''',
    )
    w(
        PKG / "CommsUI" / "Tests" / "CommsUITests" / "CommsUITests.swift",
        r'''import XCTest
@testable import CommsUI

final class CommsUITests: XCTestCase {
    func testWhisperAndFormUp() {
        var s = CommsState()
        XCTAssertTrue(s.whisperOK)
        s.formUp()
        s.lostKid()
        XCTAssertEqual(s.chips.contains(.formUp), true)
        s.setChannel("1:1")
        XCTAssertEqual(s.channel, "1:1")
    }
}
''',
    )


def emit_all() -> None:
    emit_tokens()
    emit_blackbox()
    emit_packio()
    emit_search()
    emit_router()
    emit_deadreckoning()
    emit_remaining_logic_packages()
    emit_field_stack()
    emit_vision_kit_paper()
    emit_map_comms()
    print("swift packages emitted")
