import AVFoundation
import Router
import SwiftUI
import Tokens
import UIKit

/// N/A live exception. Official City of El Paso / zoo HTTPS HLS only.
/// SNAP sections stay stills. AVPlayer layer only. No web view.
enum NaLive {
    struct Stream: Identifiable, Equatable {
        var id: String
        var name: String
        var url: String
        var lat: Double
        var lon: Double
    }

    struct Row: Identifiable, Equatable {
        var id: String
        var name: String
        var url: String
        var meters: Double
        var range: String
    }

    /// City bridge page plus the zoo host's own public cams. 404 Stanton 1/2 stay off.
    static let streams: [Stream] = [
        Stream(
            id: "na-stanton-3",
            name: "STANTON BRIDGE 3",
            url: "https://zoocams.elpasozoo.org/BridgeStanton3.m3u8",
            lat: 31.7598,
            lon: -106.4826
        ),
        Stream(
            id: "na-pdn-1",
            name: "PASO DEL NORTE 1",
            url: "https://zoocams.elpasozoo.org/bridgepdn1.m3u8",
            lat: 31.7580,
            lon: -106.4870
        ),
        Stream(
            id: "na-santa-fe-3",
            name: "SANTA FE 3",
            url: "https://zoocams.elpasozoo.org/bridgesantafe3.m3u8",
            lat: 31.7576,
            lon: -106.4874
        ),
        Stream(
            id: "na-santa-fe-4",
            name: "SANTA FE 4",
            url: "https://zoocams.elpasozoo.org/bridgesantafe4.m3u8",
            lat: 31.7574,
            lon: -106.4876
        ),
        Stream(
            id: "na-zaragoza-1",
            name: "ZARAGOZA 1",
            url: "https://zoocams.elpasozoo.org/BridgeZaragoza1.m3u8",
            lat: 31.6714,
            lon: -106.3378
        ),
        Stream(
            id: "na-zaragoza-2",
            name: "ZARAGOZA 2",
            url: "https://zoocams.elpasozoo.org/BridgeZaragoza2.m3u8",
            lat: 31.6712,
            lon: -106.3374
        ),
        Stream(
            id: "na-zaragoza-3",
            name: "ZARAGOZA 3",
            url: "https://zoocams.elpasozoo.org/BridgeZaragoza3.m3u8",
            lat: 31.6710,
            lon: -106.3370
        ),
        Stream(
            id: "na-zoo-gf",
            name: "ZOO GF",
            url: "https://zoocams.elpasozoo.org/ZOOGF.m3u8",
            lat: 31.7688,
            lon: -106.4434
        ),
        Stream(
            id: "na-zoo-m",
            name: "ZOO M",
            url: "https://zoocams.elpasozoo.org/ZooM.m3u8",
            lat: 31.7684,
            lon: -106.4430
        ),
    ]

    static func rows(lat: Double, lon: Double) -> [Row] {
        streams
            .compactMap { stream -> Row? in
                guard let parsed = URL(string: stream.url), parsed.scheme == "https" else { return nil }
                let meters = GraphRouter.haversine(lat, lon, stream.lat, stream.lon)
                return Row(
                    id: stream.id,
                    name: stream.name,
                    url: stream.url,
                    meters: meters,
                    range: BlackoutTokens.Distance.hud(meters)
                )
            }
            .sorted { $0.meters < $1.meters }
    }
}

struct NaLiveWell: View {
    let row: NaLive.Row
    let pipe: Bool
    @Binding var playingID: String?
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(row.name) { toggle() }
                .buttonStyle(HUDActionStyle(filled: playing))
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
        .accessibilityHint(pipe ? "TAP PLAY" : "NO PIPE")
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
            } else if URL(string: row.url) == nil {
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
        .onTapGesture { toggle() }
        .accessibilityLabel(pipe ? (playing ? "LIVE" : "TAP PLAY") : "NO PIPE")
    }

    private func toggle() {
        if playing {
            stop()
            return
        }
        guard pipe, let url = URL(string: row.url), url.scheme == "https" else { return }
        let next = AVPlayer(url: url)
        next.play()
        player = next
        playingID = row.id
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
