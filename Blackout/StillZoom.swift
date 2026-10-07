import SwiftUI
import UIKit
import Tokens

/// Full-field packed JPEG. Pinch zooms the file on disk. CLOSE sleeps off the picture.
struct StillZoom: View {
    let name: String
    let onClose: () -> Void
    @State private var showChrome = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Theme.void.ignoresSafeArea()
            if let still {
                StillZoomScroll(
                    still: still,
                    onFieldTap: toggleChrome,
                    onFieldMove: sleepChrome
                )
                .ignoresSafeArea()
            } else {
                Text("NO STILL")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.silver)
            }
        }
        .overlay(alignment: .top) { topRail }
        .animation(Theme.Motion.sleep, value: showChrome)
        .onAppear { wakeChrome() }
        .onDisappear { hideTask?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(still == nil ? "NO STILL" : "STILL")
        .accessibilityHint(showChrome ? "CLOSE" : "TAP")
        .accessibilityAction(named: "CLOSE") { onClose() }
    }

    private var topRail: some View {
        HStack {
            Button("CLOSE") { onClose() }
                .buttonStyle(HUDOverlayChipStyle(filled: true))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .safeAreaPadding(.top)
        .safeAreaPadding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Theme.void.opacity(0.72), Theme.void.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
        .opacity(showChrome ? 1 : 0)
        .allowsHitTesting(showChrome)
        .accessibilityHidden(!showChrome)
    }

    private var still: UIImage? {
        let url = SnapManifest.folder().appendingPathComponent(name)
        return UIImage(contentsOfFile: url.path)
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
            showChrome = false
        }
    }

    private func sleepChrome() {
        hideTask?.cancel()
        showChrome = false
    }
}

private struct StillZoomScroll: UIViewRepresentable {
    let still: UIImage
    var onFieldTap: () -> Void
    var onFieldMove: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFieldTap: onFieldTap, onFieldMove: onFieldMove)
    }

    func makeUIView(context: Context) -> ZoomView {
        let view = ZoomView(still: still)
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ZoomView, context: Context) {
        context.coordinator.onFieldTap = onFieldTap
        context.coordinator.onFieldMove = onFieldMove
        uiView.coordinator = context.coordinator
        uiView.apply(still)
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
        let imageView = UIImageView()
        var coordinator: Coordinator?
        private var lastSize: CGSize = .zero

        init(still: UIImage) {
            super.init(frame: .zero)
            delegate = self
            backgroundColor = .clear
            minimumZoomScale = 1
            maximumZoomScale = 8
            showsHorizontalScrollIndicator = false
            showsVerticalScrollIndicator = false
            bouncesZoom = true
            contentInsetAdjustmentBehavior = .never
            imageView.image = still
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = false
            imageView.isUserInteractionEnabled = true
            addSubview(imageView)
            let zoomTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
            zoomTap.numberOfTapsRequired = 2
            let fieldTap = UITapGestureRecognizer(target: self, action: #selector(tapField))
            fieldTap.numberOfTapsRequired = 1
            fieldTap.require(toFail: zoomTap)
            addGestureRecognizer(zoomTap)
            addGestureRecognizer(fieldTap)
        }

        required init?(coder: NSCoder) { nil }

        func apply(_ still: UIImage) {
            if imageView.image !== still {
                imageView.image = still
                lastSize = .zero
                setNeedsLayout()
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage()
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
            centerImage()
        }

        private func fit() {
            guard let image = imageView.image else { return }
            let size = bounds.size
            let imageSize = image.size
            guard imageSize.width > 1, imageSize.height > 1 else { return }
            let scale = min(size.width / imageSize.width, size.height / imageSize.height)
            let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            zoomScale = 1
            imageView.frame = CGRect(origin: .zero, size: fitted)
            contentSize = fitted
            let native = max(imageSize.width / size.width, imageSize.height / size.height)
            minimumZoomScale = 1
            maximumZoomScale = max(4, native * 2)
        }

        private func centerImage() {
            let bounds = bounds.size
            let frame = imageView.frame
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
            let point = tap.location(in: imageView)
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
}
