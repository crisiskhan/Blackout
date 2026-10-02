import AVFoundation
import SwiftUI
import Tokens
import UIKit

/// Full-field adult HLS. Pinch zooms the player. No web view.
struct LiveZoom: View {
    let row: NaLive.Row
    let pipe: Bool
    let onClose: () -> Void
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Theme.void.ignoresSafeArea()
            well
            VStack {
                HStack {
                    Button("CLOSE") { stop(); onClose() }
                        .buttonStyle(HUDOverlayChipStyle(filled: true))
                    Spacer(minLength: 0)
                }
                .padding(12)
                Spacer()
            }
        }
        .onAppear { start() }
        .onChange(of: pipe) { _, ok in
            if !ok { stop() }
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
        guard pipe, let url = URL(string: row.url), url.scheme == "https" else { return }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 6
        item.preferredPeakBitRate = 0
        let next = AVPlayer(playerItem: item)
        next.automaticallyWaitsToMinimizeStalling = true
        next.play()
        player = next
    }

    private func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
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

        func apply(_ player: AVPlayer) {
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
