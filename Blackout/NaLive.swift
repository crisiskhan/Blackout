import AVFoundation
import CoreMedia
import ImageIO
import SwiftUI
import Tokens
import UIKit

/// N/A is adult HTTPS HLS after the 10s hold. Open sections stay stills.
/// AVPlayer layer only. No web view.
enum NaLive {
    struct Row: Identifiable, Equatable {
        var id: String
        var name: String
        var handle: String
        var url: String
        var viewers: Int
        var image: String
        var kinds: [String]
        var range: String
        var seconds: Int
    }

    static let screen = 8

    static func rows(_ rooms: [AdultDesk.Room]) -> [Row] {
        var seen: Set<String> = []
        return rooms.compactMap { room in
            let id = room.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let handle = room.handle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !handle.isEmpty, seen.insert(id).inserted else { return nil }
            let named = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return Row(
                id: id,
                name: named.isEmpty ? handle.uppercased() : named,
                handle: handle,
                url: room.url,
                viewers: room.viewers,
                image: room.image,
                kinds: room.kinds,
                range: room.seconds > 0 ? AdultDesk.clock(room.seconds) : "LIVE",
                seconds: max(0, room.seconds)
            )
        }
    }

    static func page(
        _ rooms: [AdultDesk.Room],
        kind: String = "",
        query: String = "",
        offset: Int
    ) -> [Row] {
        let start = max(0, offset)
        return Array(rows(AdultDesk.pick(rooms, kind: kind, query: query)).dropFirst(start).prefix(screen))
    }
}

enum NaWatch {
    static let peak: Double = 2_500_000
    static let wellStill = 640
    static let tileStill = 264

    @MainActor
    private static var pipe: AVPlayer?
    @MainActor
    static var era: UInt = 0

    /// Movie playback. FIELD SAY / PTT leave the session in record —
    /// AVPlayer is then silent, or the audio unit crashes the phone.
    @MainActor
    static func hear() {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback {
            try? session.setCategory(.playback, mode: .moviePlayback)
        }
        try? session.setActive(true)
    }

    @MainActor
    static func play(url: URL, headers: [String: String]) -> AVPlayer {
        era &+= 1
        hear()
        if let current = pipe,
           let asset = current.currentItem?.asset as? AVURLAsset,
           asset.url.absoluteString == url.absoluteString
        {
            current.currentItem?.cancelPendingSeeks()
            current.isMuted = false
            current.volume = 1
            if current.rate == 0 {
                current.play()
            }
            return current
        }
        let item = AVPlayerItem(
            asset: AVURLAsset(
                url: url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
            )
        )
        item.preferredForwardBufferDuration = 4
        item.preferredPeakBitRate = peak
        if let current = pipe {
            current.currentItem?.cancelPendingSeeks()
            current.replaceCurrentItem(with: item)
            current.automaticallyWaitsToMinimizeStalling = true
            current.isMuted = false
            current.volume = 1
            current.play()
            return current
        }
        let next = AVPlayer(playerItem: item)
        next.automaticallyWaitsToMinimizeStalling = true
        next.isMuted = false
        next.volume = 1
        next.play()
        pipe = next
        return next
    }

    /// Detach first, then drop the item on the next turn so the layer
    /// is not sitting on a niled item (ASC 72 class). A later play()
    /// bumps era so CLOSE cannot nil a remounted item.
    @MainActor
    static func drop(_ victim: AVPlayer? = nil) {
        let old = victim ?? pipe
        guard let old else { return }
        let seen = era
        if pipe === old { pipe = nil }
        old.pause()
        old.currentItem?.cancelPendingSeeks()
        Task { @MainActor in
            await Task.yield()
            guard seen == era else { return }
            old.replaceCurrentItem(with: nil)
        }
    }

    @MainActor
    static func drop(ifEra seen: UInt) {
        guard seen == era else { return }
        drop()
    }

    static func still(id: String, maxEdge: Int) -> UIImage? {
        let token = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains("/"), !token.contains("\\"), !token.contains("..")
        else { return nil }
        let url = SnapManifest.folder().appendingPathComponent("cam-\(token).jpg")
        guard let data = try? Data(contentsOf: url),
              data.count > 32, data.count < 3_000_000,
              data[0] == 0xFF, data[1] == 0xD8
        else { return nil }
        let srcOpts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOpts as CFDictionary) else {
            return nil
        }
        let thumb: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxEdge),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumb as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    static func span(_ player: AVPlayer?, packed: Int) -> Double {
        if let item = player?.currentItem {
            let dur = item.duration.seconds
            if dur.isFinite, dur > 0 {
                return dur
            }
        }
        return packed > 0 ? Double(packed) : 0
    }

    static func unit(_ player: AVPlayer?) -> Double {
        guard let player else { return 0 }
        let now = player.currentTime().seconds
        guard now.isFinite, now >= 0 else { return 0 }
        return now
    }

    static func place(_ at: Double, span: Double) -> Double {
        guard at.isFinite else { return 0 }
        guard span.isFinite, span > 0 else { return 0 }
        let end = max(0, span - 0.25)
        return min(end, max(0, at))
    }

    @MainActor
    static func scrub(_ player: AVPlayer?, url: String, at: Double, packed _: Int) -> String? {
        guard let player, let item = player.currentItem else { return "NO STREAM" }
        guard AdultDesk.filePlay(url) else { return "LIVE" }
        guard item.status == .readyToPlay else { return "NO STREAM" }
        let duration = item.duration
        guard duration.isValid, duration.isNumeric else { return "NO STREAM" }
        let length = duration.seconds
        guard length.isFinite, length > 0 else { return "NO STREAM" }
        let next = place(at, span: length)
        guard next.isFinite else { return "NO STREAM" }
        let time = CMTime(seconds: next, preferredTimescale: 600)
        guard time.isValid, time.isNumeric else { return "NO STREAM" }
        item.cancelPendingSeeks()
        player.seek(to: time)
        return nil
    }

    static func clock(_ player: AVPlayer?, seconds: Int, armed: Bool) -> String {
        if armed, let player {
            let now = player.currentTime().seconds
            if now.isFinite, now >= 0 {
                let live = AdultDesk.clock(Int(now.rounded()))
                if seconds > 0 {
                    return "\(live) / \(AdultDesk.clock(seconds))"
                }
                return live
            }
        }
        return seconds > 0 ? AdultDesk.clock(seconds) : "LIVE"
    }
}

struct NaLiveWell: View {
    let row: NaLive.Row
    let pipe: Bool
    let still: UIImage?
    @Binding var playingID: String?
    var kept: Bool = false
    var canPrev: Bool = false
    var canNext: Bool = false
    var onPlay: (NaLive.Row) async -> String?
    var onFull: (NaLive.Row) -> Void
    var onKeep: ((NaLive.Row) -> Void)?
    var onPrev: (() -> Void)?
    var onNext: (() -> Void)?
    var onWhy: ((String?) -> Void)?
    var holdPipe: Bool = false
    var zoomLive: NaLive.Row? = nil
    @State private var player: AVPlayer?
    @State private var dead = false
    @State private var paused = false
    @State private var playURL = ""
    @State private var playSeq = 0
    @State private var lift = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.name)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
            TimelineView(.periodic(from: .now, by: armed ? 1.0 : 60)) { _ in
                HStack {
                    Text(NaWatch.clock(player, seconds: row.seconds, armed: armed))
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.silver)
                    Spacer(minLength: 8)
                    if row.viewers > 0 {
                        Text("\(row.viewers)")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.silver)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
            }
            if !row.kinds.isEmpty {
                Text(row.kinds.prefix(3).joined(separator: " · "))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.silver.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            well
            NaScrub(
                url: playURL.isEmpty ? row.url : playURL,
                seconds: row.seconds,
                player: player,
                armed: armed,
                onWhy: onWhy
            )
            watchRail
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: holdPipe) { _, held in
            if held { return }
            lift = false
            if playingID == row.id, player == nil, pipe {
                Task { await start() }
            }
        }
        .onChange(of: pipe) { _, ok in
            if !ok, zoomLive == nil, !holdPipe, !lift {
                stop()
                if playingID == row.id { playingID = nil }
            }
        }
        .onChange(of: playingID) { _, current in
            if current != row.id {
                if zoomLive == nil, !holdPipe, !lift { stop() }
            } else if player == nil, pipe, !lift { Task { await start() } }
        }
        .onChange(of: row.id) { _, _ in
            if zoomLive == nil, !holdPipe, !lift {
                stop()
            }
            dead = false
            if playingID == row.id, !lift {
                Task { await start() }
            }
        }
        .onDisappear {
            if zoomLive == nil, !holdPipe, !lift {
                stop()
                if playingID == row.id { playingID = nil }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(playing ? "LIVE" : row.range)
        .accessibilityHint(pipe ? (playing ? "TAP FULL" : "TAP PLAY") : "NO PIPE")
    }

    private var playing: Bool { armed && !paused }

    private var armed: Bool { playingID == row.id && player != nil && !lift }

    private var watchRail: some View {
        HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
            Button(playing ? "PAUSE" : "PLAY") { toggle() }
                .buttonStyle(HUDOverlayChipStyle(filled: playing))
            Button("PREV") { stepPrev() }
                .buttonStyle(HUDOverlayChipStyle())
            Button("NEXT") { stepNext() }
                .buttonStyle(HUDOverlayChipStyle())
            Button("TAP FULL") { goFull() }
                .buttonStyle(HUDOverlayChipStyle(filled: playing))
            Button(kept ? "DROP" : "KEEP") { onKeep?(row) }
                .buttonStyle(HUDOverlayChipStyle(filled: kept))
        }
    }

    @ViewBuilder
    private var well: some View {
        ZStack {
            Theme.void
            if !pipe {
                Text("NO PIPE")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.warn)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if let player, armed {
                NaLiveLayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: 420)
                if paused {
                    Text("PLAY")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.silver)
                        .shadow(color: Theme.void.opacity(0.85), radius: 6, y: 1)
                }
            } else if dead {
                stillPlate
                Text("NO STREAM")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                stillPlate
                Text("TAP PLAY")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                    .shadow(color: Theme.void.opacity(0.85), radius: 6, y: 1)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .bottom)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360, maxHeight: 420)
        .clipShape(Theme.plateRect())
        .overlay(
            Theme.plateRect()
                .strokeBorder(Theme.metalStroke, lineWidth: Theme.strokeWidth(1))
        )
        .contentShape(Rectangle())
        .onTapGesture { tapWell() }
        .accessibilityLabel(pipe ? (playing ? "TAP FULL" : "TAP PLAY") : "NO PIPE")
    }

    @ViewBuilder
    private var stillPlate: some View {
        if let still {
            Image(uiImage: still)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(maxWidth: .infinity, minHeight: 360, maxHeight: 420)
                .clipped()
        }
    }

    private func tapWell() {
        if playing {
            goFull()
            return
        }
        toggle()
    }

    private func goFull() {
        let keep = playURL
        playSeq += 1
        var next = row
        if AdultDesk.playlist(keep) != nil {
            next.url = keep
        }
        lift = true
        player = nil
        Task { @MainActor in
            await Task.yield()
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { cont.resume() }
            }
            guard lift else { return }
            onFull(next)
        }
    }

    private func toggle() {
        if armed {
            if paused {
                player?.play()
                paused = false
            } else {
                player?.pause()
                paused = true
            }
            return
        }
        guard pipe else {
            onWhy?("NO PIPE")
            return
        }
        playingID = row.id
        dead = false
        paused = false
        Task { await start() }
    }

    private func start() async {
        playSeq += 1
        let seq = playSeq
        guard !lift, zoomLive == nil, !holdPipe else { return }
        guard pipe, playingID == row.id else { return }
        guard let raw = await onPlay(row), let play = AdultDesk.playlist(raw),
              let url = URL(string: play), url.scheme == "https"
        else {
            guard seq == playSeq else { return }
            if playingID == row.id { playingID = nil }
            dead = true
            return
        }
        guard !lift, zoomLive == nil, !holdPipe, playingID == row.id, seq == playSeq else { return }
        playURL = play
        player = NaWatch.play(url: url, headers: AdultDesk.playHeaders(play))
        paused = false
    }

    private func stop() {
        playSeq += 1
        let old = player
        player = nil
        playURL = ""
        paused = false
        if let old {
            NaWatch.drop(old)
        }
    }

    private func stepPrev() {
        if !canPrev {
            onWhy?("FIRST")
            return
        }
        onPrev?()
    }

    private func stepNext() {
        if !canNext {
            onWhy?("LAST")
            return
        }
        onNext?()
    }
}

/// 44pt HUD film rail. Files drag. Live is a full accent bar that chromes LIVE.
/// Clocks tick inside TimelineView. The drag lives on the rail so a seek
/// cannot rebuild the gesture.
struct NaScrub: View {
    let url: String
    let seconds: Int
    let player: AVPlayer?
    let armed: Bool
    var onWhy: ((String?) -> Void)?
    var onDrag: (() -> Void)?
    @State private var held: Double?

    var body: some View {
        let hit = CGFloat(BlackoutTokens.Chrome.mapChipHitPoints)
        HStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: tick)) { _ in
                Text(leftStamp)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: 44, alignment: .leading)
            }
            GeometryReader { geo in
                TimelineView(.periodic(from: .now, by: tick)) { _ in
                    marks(width: geo.size.width, height: hit)
                }
                .frame(width: geo.size.width, height: hit)
                .contentShape(Rectangle())
                .onTapGesture(count: 1, coordinateSpace: .local) { point in
                    apply(x: point.x, width: geo.size.width)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 16)
                        .onChanged { gesture in
                            let dx = abs(gesture.translation.width)
                            let dy = abs(gesture.translation.height)
                            guard dx >= dy else { return }
                            apply(x: gesture.location.x, width: geo.size.width)
                        }
                        .onEnded { _ in
                            held = nil
                        }
                )
            }
            .frame(height: hit)
            TimelineView(.periodic(from: .now, by: tick)) { _ in
                if !rightStamp.isEmpty {
                    Text(rightStamp)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.silver)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(minWidth: 44, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: hit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SCRUB")
        .accessibilityValue(accessValue)
        .accessibilityAdjustableAction { direction in
            step(direction)
        }
        .onChange(of: url) { _, _ in
            held = nil
        }
    }

    private var live: Bool { !AdultDesk.filePlay(url) }

    private var tick: Double { armed && !live ? 0.2 : 60 }

    private var span: Double { NaWatch.span(player, packed: seconds) }

    private var now: Double { held ?? NaWatch.unit(player) }

    private var leftStamp: String { live ? "LIVE" : AdultDesk.clock(Int(now.rounded())) }

    private var rightStamp: String {
        let rest = max(0, span - now)
        return live || span <= 0 ? "" : AdultDesk.clock(Int(rest.rounded()))
    }

    private var accessValue: String {
        live ? "LIVE" : (span > 0 ? "\(leftStamp) / \(AdultDesk.clock(Int(span.rounded())))" : leftStamp)
    }

    private func marks(width: CGFloat, height: CGFloat) -> some View {
        let track: CGFloat = 10
        let head: CGFloat = 16
        let inset = head / 2
        let travel = max(0, width - head)
        let mark = live ? 1.0 : (span > 0 ? min(1, max(0, now / span)) : 0)
        let x = live ? width : (inset + CGFloat(mark) * travel)
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Theme.void)
                .frame(height: track)
            Capsule()
                .fill(Theme.accent)
                .frame(width: max(track, x), height: track)
            if !live {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: head, height: head)
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.metalStroke, lineWidth: Theme.strokeWidth(1))
                    )
                    .shadow(color: Theme.void.opacity(0.85), radius: 3, y: 1)
                    .offset(x: x - inset)
            }
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Theme.metalHigh.opacity(0.40),
                            Color.clear,
                            Color.clear,
                            Theme.metalLow.opacity(0.42),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: track)
                .allowsHitTesting(false)
            Capsule()
                .strokeBorder(Theme.metalStroke, lineWidth: Theme.strokeWidth(1.2))
                .frame(height: track)
        }
        .frame(width: width, height: height)
    }

    private func apply(x: CGFloat, width: CGFloat) {
        onDrag?()
        if live {
            onWhy?("LIVE")
            return
        }
        guard width > 0 else { return }
        let span = NaWatch.span(player, packed: seconds)
        let t = min(1, max(0, Double(x / width)))
        let at = NaWatch.place(t * span, span: span)
        held = at
        if let why = NaWatch.scrub(player, url: url, at: at, packed: seconds) {
            if why != "NO STREAM" {
                onWhy?(why)
            }
            return
        }
        onWhy?(nil)
    }

    private func step(_ direction: AccessibilityAdjustmentDirection) {
        onDrag?()
        if live {
            onWhy?("LIVE")
            return
        }
        let span = NaWatch.span(player, packed: seconds)
        let now = held ?? NaWatch.unit(player)
        let stride = max(1, span * 0.05)
        let delta: Double
        switch direction {
        case .increment:
            delta = stride
        case .decrement:
            delta = -stride
        @unknown default:
            return
        }
        let at = NaWatch.place(now + delta, span: span)
        held = at
        if let why = NaWatch.scrub(player, url: url, at: at, packed: seconds) {
            if why != "NO STREAM" {
                onWhy?(why)
            }
            return
        }
        onWhy?(nil)
    }
}

private struct NaLiveLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if uiView.player === player { return }
        uiView.player = player
    }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.player = nil
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        var player: AVPlayer? {
            get { (layer as? AVPlayerLayer)?.player }
            set {
                let layer = layer as? AVPlayerLayer
                layer?.player = newValue
                layer?.videoGravity = .resizeAspect
            }
        }
    }
}
