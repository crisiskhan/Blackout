import AVFoundation
import CoreMedia
import SwiftUI
import Tokens
import UIKit

/// Full-field adult HLS. Pinch zooms the player. Watch chrome sleeps off the picture.
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
    @State private var showChrome = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Theme.void.ignoresSafeArea()
            well
        }
        .overlay(alignment: .top) { topRail }
        .overlay(alignment: .bottom) { bottomRail }
        .animation(Theme.Motion.sleep, value: showChrome)
        .onAppear {
            start()
            wakeChrome()
        }
        .onChange(of: pipe) { _, ok in
            if !ok { stop() }
        }
        .onChange(of: row.id) { _, _ in
            chrome = nil
            start()
            wakeChrome()
        }
        .onChange(of: row.url) { _, _ in
            chrome = nil
            start()
            wakeChrome()
        }
        .onDisappear {
            hideTask?.cancel()
            stop()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.name)
        .accessibilityValue(pipe ? "LIVE" : "NO PIPE")
        .accessibilityHint(showChrome ? "CLOSE" : "TAP")
        .accessibilityAction(named: "CLOSE") { onClose() }
    }

    @ViewBuilder
    private var well: some View {
        if !pipe {
            Text("NO PIPE")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.warn)
        } else if let player {
            LiveZoomScroll(
                player: player,
                onFieldTap: toggleChrome,
                onFieldMove: sleepChrome
            )
            .ignoresSafeArea()
        } else {
            Text("NO STREAM")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.silver)
        }
    }

    private var topRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("CLOSE") { onClose() }
                    .buttonStyle(HUDOverlayChipStyle(filled: true))
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: player == nil ? 60 : 1.0)) { _ in
                    Text(NaWatch.clock(player, seconds: row.seconds, armed: player != nil))
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.silver)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Button(kept ? "DROP" : "KEEP") {
                    wakeChrome()
                    onKeep?(row)
                }
                .buttonStyle(HUDOverlayChipStyle(filled: kept))
            }
            Text(row.name)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.silver)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(edgeFade(top: true))
        .opacity(showChrome ? 1 : 0)
        .allowsHitTesting(showChrome)
        .accessibilityHidden(!showChrome)
    }

    private var bottomRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let chrome {
                Text(chrome)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.warn)
                    .textCase(.uppercase)
            }
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
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(edgeFade(top: false))
        .opacity(showChrome ? 1 : 0)
        .allowsHitTesting(showChrome)
        .accessibilityHidden(!showChrome)
    }

    private func edgeFade(top: Bool) -> some View {
        LinearGradient(
            colors: top
                ? [Theme.void.opacity(0.72), Theme.void.opacity(0)]
                : [Theme.void.opacity(0), Theme.void.opacity(0.72)],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    private func toggleChrome() {
        if showChrome {
            sleepChrome()
        } else {
            wakeChrome()
        }
    }

    private func wakeChrome() {
        hideTask?.cancel()
        showChrome = true
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(BlackoutTokens.Chrome.chromeIdleSeconds))
            if Task.isCancelled { return }
            if chrome != nil { return }
            showChrome = false
        }
    }

    private func sleepChrome() {
        hideTask?.cancel()
        showChrome = false
    }

    private func start() {
        guard pipe, let play = AdultDesk.playlist(row.url),
              let url = URL(string: play), url.scheme == "https"
        else {
            stop()
            return
        }
        player = NaWatch.play(url: url, headers: AdultDesk.playHeaders(play))
    }

    private func stop() {
        player?.pause()
        player = nil
    }

    private func jump(_ by: Double) {
        wakeChrome()
        if let why = NaWatch.seek(player, url: row.url, by: by) {
            chrome = why
            return
        }
        chrome = nil
    }

    private func step(_ delta: Int) {
        wakeChrome()
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
    var onFieldTap: () -> Void
    var onFieldMove: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFieldTap: onFieldTap, onFieldMove: onFieldMove)
    }

    func makeUIView(context: Context) -> ZoomView {
        let view = ZoomView(player: player)
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ZoomView, context: Context) {
        context.coordinator.onFieldTap = onFieldTap
        context.coordinator.onFieldMove = onFieldMove
        uiView.coordinator = context.coordinator
        uiView.apply(player)
    }

    static func dismantleUIView(_ uiView: ZoomView, coordinator: Coordinator) {
        uiView.coordinator = nil
        uiView.apply(nil)
    }

    final class Coordinator {
        var onFieldTap: () -> Void
        var onFieldMove: () -> Void

        init(onFieldTap: @escaping () -> Void, onFieldMove: @escaping () -> Void) {
            self.onFieldTap = onFieldTap
            self.onFieldMove = onFieldMove
        }
    }

    final class ZoomView: UIScrollView, UIScrollViewDelegate {
        let host = PlayerHost()
        var coordinator: Coordinator?
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
            let zoomTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
            zoomTap.numberOfTapsRequired = 2
            let fieldTap = UITapGestureRecognizer(target: self, action: #selector(tapField))
            fieldTap.numberOfTapsRequired = 1
            fieldTap.require(toFail: zoomTap)
            addGestureRecognizer(zoomTap)
            addGestureRecognizer(fieldTap)
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

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            coordinator?.onFieldMove()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            coordinator?.onFieldMove()
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

        @objc private func tapField() {
            coordinator?.onFieldTap()
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
