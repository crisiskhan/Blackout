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
    static let jump = 15
    static let peak: Double = 2_500_000
    static let wellStill = 640
    static let tileStill = 264

    @MainActor
    private static var pipe: AVPlayer?

    /// Movie playback. FIELD SAY / PTT leave the session in record —
    /// AVPlayer is then silent, or the audio unit crashes the phone.
    @MainActor
    static func hear() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    @MainActor
    static func play(url: URL, headers: [String: String]) -> AVPlayer {
        hear()
        drop()
        let item = AVPlayerItem(
            asset: AVURLAsset(
                url: url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
            )
        )
        item.preferredForwardBufferDuration = 4
        item.preferredPeakBitRate = peak
        let next = AVPlayer(playerItem: item)
        next.automaticallyWaitsToMinimizeStalling = true
        next.isMuted = false
        next.volume = 1
        next.play()
        pipe = next
        return next
    }

    @MainActor
    static func drop() {
        pipe?.pause()
        pipe?.replaceCurrentItem(with: nil)
        pipe = nil
    }

    static func still(id: String, maxEdge: Int) -> UIImage? {
        let token = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains("/"), !token.contains("\\"), !token.contains("..")
        else { return nil }
        let url = SnapManifest.folder().appendingPathComponent("cam-\(token).jpg")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let srcOpts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOpts as CFDictionary) else {
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

    static func seek(_ player: AVPlayer?, url: String, by: Double) -> String? {
        guard let player, player.currentItem != nil else { return "NO STREAM" }
        guard AdultDesk.filePlay(url) else { return "LIVE" }
        let now = player.currentTime().seconds
        guard now.isFinite else { return "NO STREAM" }
        var next = now + by
        if next < 0 { next = 0 }
        if let item = player.currentItem {
            let dur = item.duration.seconds
            if dur.isFinite, dur > 0 {
                next = min(next, max(0, dur - 0.25))
            }
        }
        player.seek(to: CMTime(seconds: next, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
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
    @State private var player: AVPlayer?
    @State private var dead = false
    @State private var paused = false
    @State private var playURL = ""
    @State private var playSeq = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.name)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
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
            watchRail
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: pipe) { _, ok in
            if !ok {
                stop()
                if playingID == row.id { playingID = nil }
            }
        }
        .onChange(of: playingID) { _, current in
            if current != row.id { stop() }
            else if player == nil, pipe { Task { await start() } }
        }
        .onChange(of: row.id) { _, _ in
            stop()
            dead = false
            if playingID == row.id {
                Task { await start() }
            }
        }
        .onDisappear {
            stop()
            if playingID == row.id { playingID = nil }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(playing ? "LIVE" : row.range)
        .accessibilityHint(pipe ? (playing ? "TAP FULL" : "TAP PLAY") : "NO PIPE")
    }

    private var playing: Bool { armed && !paused }

    private var armed: Bool { playingID == row.id && player != nil }

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
            Button("REWIND 15") { jump(-Double(NaWatch.jump)) }
                .buttonStyle(HUDOverlayChipStyle())
            Button("AHEAD 15") { jump(Double(NaWatch.jump)) }
                .buttonStyle(HUDOverlayChipStyle())
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
        stop()
        if playingID == row.id { playingID = nil }
        var next = row
        if AdultDesk.playlist(keep) != nil {
            next.url = keep
        }
        onFull(next)
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
        guard pipe, playingID == row.id else { return }
        guard let raw = await onPlay(row), let play = AdultDesk.playlist(raw),
              let url = URL(string: play), url.scheme == "https"
        else {
            guard seq == playSeq else { return }
            if playingID == row.id { playingID = nil }
            dead = true
            return
        }
        guard playingID == row.id, seq == playSeq else { return }
        playURL = play
        player = NaWatch.play(url: url, headers: AdultDesk.playHeaders(play))
        paused = false
    }

    private func stop() {
        playSeq += 1
        if player != nil {
            NaWatch.drop()
        }
        player = nil
        playURL = ""
        paused = false
    }

    private func jump(_ by: Double) {
        if let why = NaWatch.seek(player, url: playURL.isEmpty ? row.url : playURL, by: by) {
            onWhy?(why)
            return
        }
        onWhy?(nil)
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

private struct NaLiveLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
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
