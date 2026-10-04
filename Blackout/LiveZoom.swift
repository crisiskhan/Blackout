import AVFoundation
import CoreMedia
import SwiftUI
import Tokens
import UIKit

/// Full-field adult HLS. Pinch zooms the player. Watch chrome on glass.
struct LiveZoom: View {
    let row: NaLive.Row
    let pipe: Bool
    var kept: Bool = false
    var canPrev: Bool = false
    var canNext: Bool = false
    var onClose: () -> Void
    var onKeep: ((NaLive.Row) -> Void)?
    var onPrev: (() -> Void)?
    var onNext: (() -> Void)?
    @State private var player: AVPlayer?
    @State private var chrome: String?

    var body: some View {
        ZStack {
            Theme.void.ignoresSafeArea()
            well
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button("CLOSE") { stop(); onClose() }
                        .buttonStyle(HUDOverlayChipStyle(filled: true))
                    Spacer(minLength: 0)
                    Button(kept ? "DROP" : "KEEP") { onKeep?(row) }
                        .buttonStyle(HUDOverlayChipStyle(filled: kept))
                }
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    TimelineView(.periodic(from: .now, by: player == nil ? 60 : 1.0)) { _ in
                        Text(NaWatch.clock(player, seconds: row.seconds, armed: player != nil))
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.silver)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: BlackoutTokens.Chrome.mapChipHitPoints, alignment: .leading)
                HUDWrapRail(spacing: BlackoutTokens.Chrome.mapActionRailSpacingPoints) {
                    Button("PREV") { step(-1) }
                        .buttonStyle(HUDOverlayChipStyle())
                    Button("NEXT") { step(1) }
                        .buttonStyle(HUDOverlayChipStyle())
                    Button("REWIND 15") { jump(-Double(NaWatch.jump)) }
                        .buttonStyle(HUDOverlayChipStyle())
                    Button("AHEAD 15") { jump(Double(NaWatch.jump)) }
                        .buttonStyle(HUDOverlayChipStyle())
                }
                if let chrome {
                    Text(chrome)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.warn)
                        .textCase(.uppercase)
                }
                Spacer()
            }
            .padding(12)
        }
        .onAppear { start() }
        .onChange(of: pipe) { _, ok in
            if !ok { stop() }
        }
        .onChange(of: row.id) { _, _ in
            chrome = nil
            stop()
            start()
        }
        .onDisappear { stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.name)
        .accessibilityValue(pipe ? "LIVE" : "NO PIPE")
    }

    @ViewBuilder
    private var well: some View {
        if !pipe {
            Text("NO PIPE")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.warn)
        } else if let player {
            LiveZoomScroll(player: player)
                .ignoresSafeArea()
        } else {
            Text("NO STREAM")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.silver)
        }
    }

    private func start() {
        guard pipe, let play = AdultDesk.playlist(row.url),
              let url = URL(string: play), url.scheme == "https"
        else { return }
        player = NaWatch.play(url: url, headers: AdultDesk.playHeaders(play))
    }

    private func stop() {
        let old = player
        player = nil
        if let old {
            NaWatch.drop(old)
        }
    }

    private func jump(_ by: Double) {
        if let why = NaWatch.seek(player, url: row.url, by: by) {
            chrome = why
            return
        }
        chrome = nil
    }

    private func step(_ delta: Int) {
        if delta < 0, !canPrev {
            chrome = "FIRST"
            return
        }
        if delta > 0, !canNext {
            chrome = "LAST"
            return
        }
        chrome = nil
        if delta < 0 {
            onPrev?()
        } else {
            onNext?()
        }
    }
}

private struct LiveZoomScroll: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> ZoomView {
        ZoomView(player: player)
    }

    func updateUIView(_ uiView: ZoomView, context: Context) {
        uiView.apply(player)
    }

    static func dismantleUIView(_ uiView: ZoomView, coordinator: ()) {
        uiView.apply(nil)
    }

    final class ZoomView: UIScrollView, UIScrollViewDelegate {
        let host = PlayerHost()
        private var lastSize: CGSize = .zero

        init(player: AVPlayer) {
            super.init(frame: .zero)
            delegate = self
            backgroundColor = .clear
            minimumZoomScale = 1
            maximumZoomScale = 8
            showsHorizontalScrollIndicator = false
            showsVerticalScrollIndicator = false
            bouncesZoom = true
            contentInsetAdjustmentBehavior = .never
            host.player = player
            host.isUserInteractionEnabled = true
            addSubview(host)
            let tap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
            tap.numberOfTapsRequired = 2
            addGestureRecognizer(tap)
        }

        required init?(coder: NSCoder) { nil }

        func apply(_ player: AVPlayer?) {
            host.player = player
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            host
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerHost()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let size = bounds.size
            guard size.width > 1, size.height > 1 else { return }
            if size != lastSize {
                lastSize = size
                fit()
            }
            centerHost()
        }

        private func fit() {
            let size = bounds.size
            let ratio: CGFloat = 16.0 / 9.0
            var width = size.width
            var height = width / ratio
            if height > size.height {
                height = size.height
                width = height * ratio
            }
            zoomScale = 1
            host.frame = CGRect(origin: .zero, size: CGSize(width: width, height: height))
            contentSize = host.frame.size
            minimumZoomScale = 1
            maximumZoomScale = 8
        }

        private func centerHost() {
            let bounds = bounds.size
            let frame = host.frame
            let insetX = max(0, (bounds.width - frame.width) / 2)
            let insetY = max(0, (bounds.height - frame.height) / 2)
            contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
        }

        @objc private func toggleZoom(_ tap: UITapGestureRecognizer) {
            if zoomScale > 1.05 {
                setZoomScale(1, animated: true)
                return
            }
            let target = min(maximumZoomScale, max(2, maximumZoomScale / 2))
            let point = tap.location(in: host)
            let size = CGSize(
                width: bounds.width / target,
                height: bounds.height / target
            )
            let rect = CGRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            zoom(to: rect, animated: true)
        }
    }

    final class PlayerHost: UIView {
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
