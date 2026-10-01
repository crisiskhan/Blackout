import AVFoundation
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
        var range: String
    }

    static let screen = 12

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
                range: "LIVE"
            )
        }
    }

    static func page(_ rooms: [AdultDesk.Room], offset: Int) -> [Row] {
        let start = max(0, offset)
        return Array(rows(rooms).dropFirst(start).prefix(screen))
    }
}

struct NaLiveWell: View {
    let row: NaLive.Row
    let pipe: Bool
    @Binding var playingID: String?
    var onPlay: (NaLive.Row) async -> String?
    var onFull: (NaLive.Row) -> Void
    @State private var player: AVPlayer?
    @State private var dead = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(row.name) { toggle() }
                .buttonStyle(HUDActionStyle(filled: playing))
            if playing {
                Button("TAP FULL") { goFull() }
                    .buttonStyle(HUDActionStyle(filled: true))
            }
            HStack {
                Text(row.range)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
            well
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: pipe) { _, ok in
            if !ok { stop() }
        }
        .onChange(of: playingID) { _, current in
            if current != row.id { stop() }
        }
        .onDisappear { stop() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.name)
        .accessibilityValue(playing ? "LIVE" : row.range)
        .accessibilityHint(pipe ? (playing ? "TAP FULL" : "TAP PLAY") : "NO PIPE")
    }

    private var playing: Bool { playingID == row.id && player != nil }

    @ViewBuilder
    private var well: some View {
        ZStack {
            Theme.void
            if !pipe {
                Text("NO PIPE")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.warn)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if let player, playing {
                NaLiveLayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: 180)
            } else if dead {
                Text("NO STREAM")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Text("TAP PLAY")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.silver)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 180)
        .clipShape(Theme.plateRect())
        .overlay(
            Theme.plateRect()
                .strokeBorder(Theme.metalStroke, lineWidth: Theme.strokeWidth(1))
        )
        .contentShape(Rectangle())
        .onTapGesture { tapWell() }
        .accessibilityLabel(pipe ? (playing ? "TAP FULL" : "TAP PLAY") : "NO PIPE")
    }

    private func tapWell() {
        if playing {
            goFull()
            return
        }
        toggle()
    }

    private func goFull() {
        stop()
        onFull(row)
    }

    private func toggle() {
        if playing {
            stop()
            return
        }
        guard pipe else { return }
        playingID = row.id
        dead = false
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
        let next = AVPlayer(url: url)
        next.automaticallyWaitsToMinimizeStalling = true
        next.play()
        player = next
    }

    private func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        if playingID == row.id { playingID = nil }
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
