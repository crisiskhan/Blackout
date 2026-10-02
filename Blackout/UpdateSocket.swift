import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import MapLibreMap
import Network
import Observation

/// The only network socket. Airplane keeps last SNAP. SNAP is never a live stream.
@MainActor
@Observable
final class UpdateSocket {
    var pipe = false
    var busy = false
    var chrome = EyeDesk.noPipe
    var updatedAt: Date?
    var offLabels: [String] = SnapKind.allCases.map(\.offTitle)
    var lastManifest: SnapManifest?
    var adultRooms: [AdultDesk.Room] = []
    var adultReady = false
    private var adultBusy = false
    private var adultStillBusy = false
    private var adultStillQueued: [NaLive.Row] = []
    private var adultPlay: [String: String] = [:]

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "blackout.update.path")
    private var session: URLSession?
    private var queued: SnapRequest?

    func start() {
        lastManifest = SnapManifest.load()
        if let loaded = lastManifest {
            updatedAt = loaded.at
            chrome = EyeDesk.updatedChrome(pipe: true, at: loaded.at)
            offLabels = loaded.off
        }
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.pipe = path.status == .satisfied
                guard let self else { return }
                if !self.pipe && !self.busy {
                    self.chrome = EyeDesk.noPipe
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func tap(
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        lat: Double,
        lon: Double,
        packRoot: URL?,
        extraCams: [PackCam] = [],
        hopStills: [(id: String, jpeg: Data)] = [],
        onSnapStill: ((String, Data) -> Void)? = nil
    ) {
        applyHopStills(hopStills)
        if !pipe {
            chrome = EyeDesk.noPipe
            queued = nil
            return
        }
        let request = SnapRequest(
            south: south,
            west: west,
            north: north,
            east: east,
            lat: lat,
            lon: lon,
            packRoot: packRoot,
            extraCams: extraCams,
            hopStills: hopStills,
            onSnapStill: onSnapStill
        )
        if busy {
            queued = request
            return
        }
        busy = true
        chrome = EyeDesk.updatingTitle
        Task {
            await burst(
                south: request.south,
                west: request.west,
                north: request.north,
                east: request.east,
                lat: request.lat,
                lon: request.lon,
                packRoot: request.packRoot,
                extraCams: request.extraCams,
                onSnapStill: request.onSnapStill
            )
            if let next = queued {
                queued = nil
                tap(
                    south: next.south,
                    west: next.west,
                    north: next.north,
                    east: next.east,
                    lat: next.lat,
                    lon: next.lon,
                    packRoot: next.packRoot,
                    extraCams: next.extraCams,
                    hopStills: next.hopStills,
                    onSnapStill: next.onSnapStill
                )
            }
        }
    }

    private struct SnapRequest {
        var south: Double
        var west: Double
        var north: Double
        var east: Double
        var lat: Double
        var lon: Double
        var packRoot: URL?
        var extraCams: [PackCam]
        var hopStills: [(id: String, jpeg: Data)]
        var onSnapStill: ((String, Data) -> Void)?
    }

    func pullAdult(topic: String = "") {
        guard pipe else { return }
        if adultBusy { return }
        adultBusy = true
        Task { await loadAdult(topic: topic) }
    }

    func pullAdultStills(_ rows: [NaLive.Row]) {
        guard pipe else { return }
        if adultStillBusy {
            adultStillQueued = rows
            return
        }
        let folder = SnapManifest.folder()
        let jobs = rows.compactMap { row -> (String, String)? in
            let dest = folder.appendingPathComponent("cam-\(row.id).jpg")
            if FileManager.default.fileExists(atPath: dest.path) { return nil }
            guard let image = AdultDesk.still(row.image) else { return nil }
            return (row.id, image)
        }
        guard !jobs.isEmpty else { return }
        adultStillBusy = true
        Task { await loadAdultStills(jobs) }
    }

    private func loadAdultStills(_ jobs: [(String, String)]) async {
        defer {
            adultStillBusy = false
            let queued = adultStillQueued
            adultStillQueued = []
            if !queued.isEmpty {
                pullAdultStills(queued)
            }
        }
        guard pipe else { return }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 16
        config.waitsForConnectivity = false
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        let session = URLSession(configuration: config)
        var wrote = false
        await withTaskGroup(of: (String, Data)?.self) { group in
            for job in jobs {
                group.addTask {
                    guard let data = await UpdateSocket.fetchAdult(session, job.1) else { return nil }
                    guard let jpeg = UpdateSocket.stillPreview(data), jpeg.count > 32 else { return nil }
                    return (job.0, jpeg)
                }
            }
            for await hit in group {
                guard let hit else { continue }
                write("cam-\(hit.0).jpg", hit.1)
                wrote = true
            }
        }
        session.invalidateAndCancel()
        if wrote {
            updatedAt = Date()
        }
    }

    private func loadAdult(topic: String = "") async {
        defer {
            adultBusy = false
            adultReady = true
        }
        guard pipe else { return }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 40
        config.waitsForConnectivity = false
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        let session = URLSession(configuration: config)
        var batches: [[AdultDesk.Room]] = []
        if AdultDesk.loveNeedles(topic) {
            batches = await fetchLovePages(session)
            adultRooms = AdultDesk.merge(batches)
        } else {
            batches = await fetchAdultPages(session, from: 0, count: 1)
            adultRooms = AdultDesk.merge(batches)
            if AdultDesk.pages > 1 {
                let rest = await fetchAdultPages(session, from: 1, count: AdultDesk.pages - 1)
                if !rest.isEmpty {
                    batches.append(contentsOf: rest)
                    adultRooms = AdultDesk.merge(batches)
                }
            }
            for hashtag in AdultDesk.topics(topic) {
                let extra = await fetchAdultPages(session, from: 0, count: 2, topic: hashtag)
                if !extra.isEmpty {
                    batches.append(contentsOf: extra)
                    adultRooms = AdultDesk.merge(batches)
                }
            }
            if let needles = AdultDesk.faceNeedles(topic) {
                let found = await fetchAdultFaces(session, needles)
                if !found.isEmpty {
                    batches.append(found)
                    adultRooms = AdultDesk.merge(batches)
                }
                let files = await fetchAdultFaceFiles(session, topic)
                if !files.isEmpty {
                    batches.append(files)
                    adultRooms = AdultDesk.merge(batches)
                }
            }
        }
        session.invalidateAndCancel()
        adultPlay = adultPlay.filter { key, _ in adultRooms.contains { $0.id == key } }
    }

    private func fetchLovePages(_ session: URLSession) async -> [[AdultDesk.Room]] {
        var batches: [[AdultDesk.Room]] = []
        await withTaskGroup(of: [AdultDesk.Room].self) { group in
            for tag in AdultDesk.loveTags {
                for page in 0..<AdultDesk.pages {
                    group.addTask {
                        let offset = page * AdultDesk.pageSize
                        guard let data = await UpdateSocket.fetchAdult(
                            session,
                            AdultDesk.loveDirectory(tag: tag, offset: offset)
                        ) else { return [] }
                        return await Task.detached(priority: .utility) {
                            AdultDesk.parseLove(data)
                        }.value
                    }
                }
            }
            for await batch in group {
                if !batch.isEmpty { batches.append(batch) }
            }
        }
        return batches
    }

    private func fetchAdultPages(
        _ session: URLSession,
        from start: Int,
        count: Int,
        topic: String = ""
    ) async -> [[AdultDesk.Room]] {
        let first = max(0, start)
        let last = first + max(0, count)
        var batches: [[AdultDesk.Room]] = []
        await withTaskGroup(of: [AdultDesk.Room].self) { group in
            for tag in AdultDesk.tags {
                for page in first..<last {
                    group.addTask {
                        let offset = page * AdultDesk.pageSize
                        guard let data = await UpdateSocket.fetchAdult(
                            session,
                            AdultDesk.directory(tag: tag, offset: offset, topic: topic)
                        ) else { return [] }
                        return await Task.detached(priority: .utility) {
                            AdultDesk.parse(data)
                        }.value
                    }
                }
            }
            for await batch in group {
                if !batch.isEmpty { batches.append(batch) }
            }
        }
        return batches
    }

    private func fetchAdultFaces(_ session: URLSession, _ needles: [String]) async -> [AdultDesk.Room] {
        var rooms: [AdultDesk.Room] = []
        await withTaskGroup(of: AdultDesk.Room?.self) { group in
            for needle in needles {
                guard let path = AdultDesk.context(needle) else { continue }
                group.addTask {
                    guard let data = await UpdateSocket.fetchAdult(session, path) else { return nil }
                    return AdultDesk.faceRoom(handle: needle, data: data)
                }
            }
            for await hit in group {
                if let hit { rooms.append(hit) }
            }
        }
        return rooms
    }

    private func fetchAdultFaceFiles(_ session: URLSession, _ kind: String) async -> [AdultDesk.Room] {
        var rooms: [AdultDesk.Room] = []
        await withTaskGroup(of: [AdultDesk.Room].self) { group in
            for path in AdultDesk.faceHunt(kind) {
                group.addTask {
                    guard let data = await UpdateSocket.fetchAdult(session, path) else { return [] }
                    return await Task.detached(priority: .utility) {
                        AdultDesk.parseFace(data, kind: kind)
                    }.value
                }
            }
            for await batch in group {
                if !batch.isEmpty { rooms.append(contentsOf: batch) }
            }
        }
        return rooms
    }

    func liveAdult(_ row: NaLive.Row) async -> String? {
        if let cached = adultPlay[row.id], AdultDesk.playlist(cached) != nil {
            return cached
        }
        if let ready = AdultDesk.playlist(row.url), AdultDesk.filePlay(ready) {
            adultPlay[row.id] = ready
            return ready
        }
        guard pipe else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        let session = URLSession(configuration: config)
        var url: String?
        if let ready = AdultDesk.playlist(row.url) {
            url = await Self.resolveAdult(session, ready)
        }
        if url == nil, !row.kinds.contains(AdultDesk.loveChip) {
            if let path = AdultDesk.context(row.handle),
               let data = await Self.fetchAdult(session, path)
            {
                url = AdultDesk.stream(data)
            }
            if url == nil, let edge = AdultDesk.edge(row.handle),
               let data = await Self.fetchAdultPost(session, edge.path, body: edge.body)
            {
                url = AdultDesk.stream(data)
            }
        }
        session.invalidateAndCancel()
        guard let url else { return nil }
        adultPlay[row.id] = url
        return url
    }

    nonisolated private static func resolveAdult(_ session: URLSession, _ raw: String) async -> String? {
        guard let play = AdultDesk.playlist(raw) else { return nil }
        guard let data = await fetchAdult(session, play) else { return nil }
        if let hit = AdultDesk.livePlay(play, data) { return hit }
        guard let next = AdultDesk.loveVariant(play, data) else { return nil }
        guard let more = await fetchAdult(session, next) else { return nil }
        return AdultDesk.livePlay(next, more)
    }

    func applyHopStills(_ hopStills: [(id: String, jpeg: Data)]) {
        var wrote = false
        for still in hopStills {
            let id = still.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, let jpeg = Self.stillJPEG(still.jpeg), jpeg.count > 32 else { continue }
            write("cam-\(id).jpg", jpeg)
            wrote = true
        }
        if wrote {
            updatedAt = Date()
        }
    }

    func burst(
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        lat: Double,
        lon: Double,
        packRoot: URL?,
        extraCams: [PackCam] = [],
        onSnapStill: ((String, Data) -> Void)? = nil
    ) async {
        defer { busy = false }
        guard pipe else {
            chrome = EyeDesk.noPipe
            return
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        let session = URLSession(configuration: config)
        self.session = session
        var off: [String] = []
        var files: [String] = []
        var camStill: [SnapCam] = []

        if let data = await get(
            session,
            "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,wind_speed_10m,weather_code&timezone=auto"
        ) {
            write("weather.json", data)
            files.append("weather.json")
        } else {
            off.append(SnapKind.weather.offTitle)
        }
        off.append(SnapKind.alerts.offTitle)

        off.append(SnapKind.firms.offTitle)

        if let data = await get(
            session,
            "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson"
        ) {
            let clipped = clipQuakes(data, south: south, west: west, north: north, east: east)
            write("quakes.geojson", clipped)
            files.append("quakes.geojson")
        } else {
            off.append(SnapKind.quakes.offTitle)
        }

        off.append(SnapKind.dot.offTitle)
        off.append(SnapKind.fire.offTitle)
        off.append(SnapKind.reservoir.offTitle)
        off.append(SnapKind.airQuality.offTitle)
        off.append(SnapKind.tle.offTitle)
        off.append(SnapKind.field.offTitle)
        off.append(SnapKind.mag.offTitle)
        off.append(SnapKind.air.offTitle)
        off.append(SnapKind.ais.offTitle)

        if let packRoot, let delta = await osmDelta(
            session,
            south: south,
            west: west,
            north: north,
            east: east
        ) {
            write("osm-delta.geojson", delta)
            files.append("osm-delta.geojson")
        } else {
            off.append(SnapKind.osmDelta.offTitle)
        }

        let targets = Self.snapTargets(pack: packCams(packRoot), extra: extraCams)
            .sorted { range2($0, lat: lat, lon: lon) < range2($1, lat: lat, lon: lon) }
        if targets.isEmpty {
            off.append(SnapKind.cams.offTitle)
        } else {
            session.invalidateAndCancel()
            let camConfig = URLSessionConfiguration.ephemeral
            camConfig.timeoutIntervalForRequest = 8
            camConfig.timeoutIntervalForResource = Self.snapResourceSeconds(count: targets.count)
            camConfig.waitsForConnectivity = false
            camConfig.allowsExpensiveNetworkAccess = true
            camConfig.allowsConstrainedNetworkAccess = true
            camConfig.tlsMinimumSupportedProtocolVersion = .TLSv12
            let camSession = URLSession(configuration: camConfig)
            self.session = camSession
            var byID: [String: SnapCam] = [:]
            if let old = lastManifest?.cams {
                for cam in old where !cam.id.isEmpty {
                    byID[cam.id] = cam
                }
            }
            var fetched: [(order: Int, cam: PackCam, data: Data?)] = []
            await withTaskGroup(of: (Int, PackCam, Data?).self) { group in
                var next = 0
                var inflight = 0
                func enqueue() {
                    while inflight < CctvMarks.snapAtOnce, next < targets.count {
                        let order = next
                        let cam = targets[order]
                        next += 1
                        inflight += 1
                        group.addTask {
                            let data = await UpdateSocket.fetch(camSession, cam.url)
                            return (order, cam, data)
                        }
                    }
                }
                enqueue()
                for await row in group {
                    fetched.append((order: row.0, cam: row.1, data: row.2))
                    inflight -= 1
                    enqueue()
                }
            }
            for row in fetched.sorted(by: { $0.order < $1.order }) {
                guard
                    let data = row.data,
                    let jpeg = Self.stillJPEG(data),
                    jpeg.count > 32
                else { continue }
                let name = "cam-\(row.cam.id).jpg"
                write(name, jpeg)
                files.append(name)
                byID[row.cam.id] = SnapCam(
                    id: row.cam.id,
                    lat: row.cam.lat,
                    lon: row.cam.lon,
                    file: name,
                    at: Date()
                )
                onSnapStill?(row.cam.id, jpeg)
            }
            camStill = Array(byID.values)
            for cam in camStill where !files.contains(cam.file) {
                files.append(cam.file)
            }
            if camStill.isEmpty { off.append(SnapKind.cams.offTitle) }
        }

        let clock = ISO8601DateFormatter().string(from: Date())
        write("clock.txt", Data(clock.utf8))
        files.append("clock.txt")

        if let packRoot, let style = try? Data(contentsOf: packRoot.appendingPathComponent("style.json")) {
            let digest = SHA256.hash(data: style)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            write("checksums.txt", Data("style.json \(hex)\n".utf8))
            files.append("checksums.txt")
        } else {
            off.append(SnapKind.checksums.offTitle)
        }
        off.append(SnapKind.highlights.offTitle)

        if self.session !== session {
            self.session?.invalidateAndCancel()
        }
        session.invalidateAndCancel()
        self.session = nil

        let at = Date()
        let manifest = SnapManifest(
            at: at,
            files: files,
            off: off,
            cams: camStill,
            stamp: EyeDesk.snapStamp
        )
        manifest.save()
        lastManifest = manifest
        updatedAt = at
        offLabels = off
        chrome = EyeDesk.updatedChrome(pipe: true, at: at)
    }

    static func snapTargets(pack: [PackCam], extra: [PackCam]) -> [PackCam] {
        var byID: [String: PackCam] = [:]
        for cam in pack where !cam.id.isEmpty && cam.url.hasPrefix("https://") {
            byID[cam.id] = cam
        }
        for cam in extra where !cam.id.isEmpty && cam.url.hasPrefix("https://") {
            if byID[cam.id] == nil { byID[cam.id] = cam }
        }
        return Array(byID.values)
    }

    static func snapResourceSeconds(count: Int, atOnce: Int = CctvMarks.snapAtOnce) -> TimeInterval {
        let n = max(0, count)
        let batch = max(1, atOnce)
        let batches = max(1, n == 0 ? 1 : (n + batch - 1) / batch)
        return TimeInterval(8 * batches + 30)
    }

    private func get(_ session: URLSession, _ raw: String) async -> Data? {
        await Self.fetch(session, raw)
    }

    nonisolated static func fetch(_ session: URLSession, _ raw: String) async -> Data? {
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https" else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    nonisolated static func fetchAdult(_ session: URLSession, _ raw: String) async -> Data? {
        await adultGet(session, raw)
    }

    nonisolated static func fetchAdultPost(_ session: URLSession, _ raw: String, body: String) async -> Data? {
        await adultPost(session, raw, body: body)
    }

    nonisolated private static func adultGet(_ session: URLSession, _ raw: String) async -> Data? {
        guard let request = adultRequest(raw) else { return nil }
        return await adultData(session, request)
    }

    nonisolated private static func adultPost(_ session: URLSession, _ raw: String, body: String) async -> Data? {
        guard var request = adultRequest(raw) else { return nil }
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)
        return await adultData(session, request)
    }

    nonisolated private static func adultRequest(_ raw: String) -> URLRequest? {
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https" else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8
        request.setValue(AdultDesk.userAgent(raw), forHTTPHeaderField: "User-Agent")
        request.setValue(AdultDesk.referer(raw), forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        return request
    }

    nonisolated private static func adultData(_ session: URLSession, _ request: URLRequest) async -> Data? {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func osmDelta(
        _ session: URLSession,
        south: Double,
        west: Double,
        north: Double,
        east: Double
    ) async -> Data? {
        let query = """
        [out:json][timeout:8];(way[\"highway\"](\(south),\(west),\(north),\(east)););out geom 40;
        """
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return await get(session, "https://overpass-api.de/api/interpreter?data=\(encoded)")
    }

    private func clipQuakes(
        _ data: Data,
        south: Double,
        west: Double,
        north: Double,
        east: Double
    ) -> Data {
        guard
            var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let features = json["features"] as? [[String: Any]]
        else { return data }
        let kept = features.filter { feature in
            guard
                let geom = feature["geometry"] as? [String: Any],
                let coords = geom["coordinates"] as? [Double],
                coords.count >= 2
            else { return false }
            let lon = coords[0]
            let lat = coords[1]
            return lat >= south && lat <= north && lon >= west && lon <= east
        }
        json["features"] = kept
        return (try? JSONSerialization.data(withJSONObject: json)) ?? data
    }

    private func packCams(_ packRoot: URL?) -> [PackCam] {
        guard let packRoot else { return [] }
        let url = packRoot.appendingPathComponent("cameras.json")
        guard
            let data = try? Data(contentsOf: url),
            let rows = try? JSONDecoder().decode([PackCam].self, from: data)
        else { return [] }
        return rows.filter { !$0.id.isEmpty && $0.url.hasPrefix("https://") }
    }

    /// Adult well still. JPEG only, down to a 640px edge so TV does not jet.
    nonisolated static func stillPreview(_ data: Data, maxEdge: Int = 640) -> Data? {
        guard let jpeg = stillJPEG(data), jpeg.count > 32 else { return nil }
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return jpeg }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxEdge),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return jpeg
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else {
            return jpeg
        }
        CGImageDestinationAddImage(
            dest,
            cg,
            [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else { return jpeg }
        let preview = out as Data
        return preview.count > 32 ? preview : jpeg
    }

    /// Raw JPEG, WebP converted to JPEG, or TxDOT JSON `{snippet: base64 jpeg}`.
    nonisolated static func stillJPEG(_ data: Data) -> Data? {
        if data.count >= 3, data[0] == 0xFF, data[1] == 0xD8 {
            return data
        }
        if data.count >= 12,
           data[0] == 0x52, data[1] == 0x49, data[2] == 0x46, data[3] == 0x46,
           data[8] == 0x57, data[9] == 0x45, data[10] == 0x42, data[11] == 0x50
        {
            return imageJPEG(data)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let snippet = (obj["snippet"] as? String) ?? (obj["Snippet"] as? String)
        guard let snippet, !snippet.isEmpty, let raw = Data(base64Encoded: snippet) else {
            return nil
        }
        if raw.count >= 3, raw[0] == 0xFF, raw[1] == 0xD8 {
            return raw
        }
        return nil
    }

    nonisolated private static func imageJPEG(_ data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(
            dest,
            cg,
            [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else { return nil }
        let jpeg = out as Data
        return jpeg.count > 32 ? jpeg : nil
    }

    private func range2(_ cam: PackCam, lat: Double, lon: Double) -> Double {
        let dlat = cam.lat - lat
        let dlon = (cam.lon - lon) * cos(lat * .pi / 180)
        return dlat * dlat + dlon * dlon
    }

    private func write(_ name: String, _ data: Data) {
        let dir = SnapManifest.folder()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }
}

enum SnapKind: String, CaseIterable, Sendable {
    case weather
    case alerts
    case firms
    case quakes
    case dot
    case fire
    case reservoir
    case airQuality
    case tle
    case field
    case cams
    case mag
    case clock
    case checksums
    case highlights
    case osmDelta
    case air
    case ais

    var offTitle: String {
        switch self {
        case .weather: return "OFF WEATHER"
        case .alerts: return "OFF ALERTS"
        case .firms: return "OFF FIRMS"
        case .quakes: return "OFF QUAKES"
        case .dot: return "OFF DOT"
        case .fire: return "OFF FIRE"
        case .reservoir: return "OFF RESERVOIR"
        case .airQuality: return "OFF AQI"
        case .tle: return "OFF TLE"
        case .field: return "OFF FIELD PACK"
        case .cams: return "OFF CAMS"
        case .mag: return "OFF MAG"
        case .clock: return "OFF CLOCK"
        case .checksums: return "OFF CHECKSUMS"
        case .highlights: return "OFF HIGHLIGHTS"
        case .osmDelta: return "OFF OSM DELTA"
        case .air: return "OFF AIR"
        case .ais: return "OFF AIS"
        }
    }
}

struct PackCam: Codable, Sendable {
    var id: String
    var url: String
    var lat: Double
    var lon: Double
    var name: String
    var ink: String
    var provider: String

    enum CodingKeys: String, CodingKey {
        case id, url, lat, lon, name, ink, provider
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        lat = try c.decode(Double.self, forKey: .lat)
        lon = try c.decode(Double.self, forKey: .lon)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        ink = try c.decodeIfPresent(String.self, forKey: .ink) ?? "blue"
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
    }

    init(
        id: String,
        url: String,
        lat: Double,
        lon: Double,
        name: String,
        ink: String,
        provider: String
    ) {
        self.id = id
        self.url = url
        self.lat = lat
        self.lon = lon
        self.name = name
        self.ink = ink
        self.provider = provider
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(url, forKey: .url)
        try c.encode(lat, forKey: .lat)
        try c.encode(lon, forKey: .lon)
        try c.encode(name, forKey: .name)
        try c.encode(ink, forKey: .ink)
        try c.encode(provider, forKey: .provider)
    }
}

struct SnapCam: Codable, Sendable {
    var id: String
    var lat: Double
    var lon: Double
    var file: String
    var at: Date
}

struct SnapManifest: Codable, Sendable {
    var at: Date
    var files: [String]
    var off: [String]
    var cams: [SnapCam]
    var stamp: String

    static func folder() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Blackout/SNAP", isDirectory: true)
    }

    func save() {
        let dir = Self.folder()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
        }
    }

    static func load() -> SnapManifest? {
        let url = folder().appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SnapManifest.self, from: data)
    }
}
