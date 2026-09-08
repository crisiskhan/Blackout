import AVKit
import SwiftUI
import UIKit

/// iPhone Camera Control click (public `AVCaptureEventInteraction`). Press-and-hold = live PTT.
/// Hardware volume-up stays blocked (private API).
struct CameraControlPTTCatcher: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        let interaction = AVCaptureEventInteraction { event in
            Task { @MainActor in
                switch event.phase {
                case .began:
                    _ = PTTIntentBridge.begin()
                case .ended:
                    PTTIntentBridge.end()
                @unknown default:
                    PTTIntentBridge.end()
                }
            }
        }
        view.addInteraction(interaction)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
