import AVFoundation
import CoreMedia
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
        rooms.compactMap { room in
            let handle = room.handle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !handle.isEmpty else { return nil }
            return Row(
                id: room.id,
                name: room.name,
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

    static func seek(_ player: AVPlayer?, url: String, by: Double) -> String? {
        guard let player else { return "NO STREAM" }
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
            if !ok { stop() }
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
        .onDisappear { stop() }
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
        guard pipe, playingID == row.id else { return }
        guard let raw = await onPlay(row), let url = URL(string: raw), url.scheme == "https" else {
            if playingID == row.id { playingID = nil }
            dead = true
            return
        }
        guard playingID == row.id else { return }
        playURL = raw
        let item = AVPlayerItem(
            asset: AVURLAsset(
                url: url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": AdultDesk.playHeaders(raw)]
            )
        )
        item.preferredForwardBufferDuration = 6
        item.preferredPeakBitRate = 0
        let next = AVPlayer(playerItem: item)
        next.automaticallyWaitsToMinimizeStalling = true
        next.play()
        player = next
        paused = false
    }

    private func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playURL = ""
        paused = false
        if playingID == row.id { playingID = nil }
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
