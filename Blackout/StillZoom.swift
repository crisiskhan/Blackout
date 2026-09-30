import SwiftUI
import UIKit
import Tokens

/// Full-field packed JPEG. Pinch zooms the file on disk. No recompress.
struct StillZoom: View {
    let name: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Theme.void.ignoresSafeArea()
            if let still {
                StillZoomScroll(still: still)
                    .ignoresSafeArea()
            } else {
                Text("NO STILL")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.silver)
            }
            VStack {
                HStack {
                    Button("CLOSE") { onClose() }
                        .buttonStyle(HUDOverlayChipStyle(filled: true))
                    Spacer(minLength: 0)
                }
                .padding(12)
                Spacer()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(still == nil ? "NO STILL" : "STILL")
    }

    private var still: UIImage? {
        let url = SnapManifest.folder().appendingPathComponent(name)
        return UIImage(contentsOfFile: url.path)
    }
}

private struct StillZoomScroll: UIViewRepresentable {
    let still: UIImage

    func makeUIView(context: Context) -> ZoomView {
        ZoomView(still: still)
    }

    func updateUIView(_ uiView: ZoomView, context: Context) {
        uiView.apply(still)
    }

    final class ZoomView: UIScrollView, UIScrollViewDelegate {
        let imageView = UIImageView()
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
            let tap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
            tap.numberOfTapsRequired = 2
            addGestureRecognizer(tap)
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
