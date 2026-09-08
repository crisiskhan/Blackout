import ARKit
import BlackoutCore
import DesignSystem
import SceneKit
import SwiftUI
import UIKit

enum LiDARAvailability {
    static var isSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            || ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }
}

struct LiDARRangeView: View {
    var mapRangeMeters: Double?
    var pointName: String
    @Environment(\.dismiss) private var dismiss
    @State private var meters: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader("LiDAR range", subtitle: pointName)
            ZStack {
                LiDARCamera(meters: $meters)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(height: 320)
                VStack {
                    Spacer()
                    HUDPanel {
                        Text(meters.map { String(format: "LiDAR %.0f m" , $0) } ?? "Point at the feature")
                    }
                    .padding(12)
                }
            }
            if let mapRangeMeters {
                Text(String(format: "Map range to pin: %.0f m (geodesic, not LiDAR).", mapRangeMeters))
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.dim)
            }
            GhostButton("Close", height: BlackoutDS.Hit.sm) { dismiss() }
            Spacer()
        }
        .padding(20)
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

private struct LiDARCamera: UIViewRepresentable {
    @Binding var meters: Double?

    func makeCoordinator() -> Coordinator {
        Coordinator(meters: $meters)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.delegate = context.coordinator
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        view.session.run(config, options: [])
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.meters = $meters
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSCNViewDelegate {
        var meters: Binding<Double?>

        init(meters: Binding<Double?>) {
            self.meters = meters
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard let view = renderer as? ARSCNView else { return }
            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            guard let query = view.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .any) else {
                return
            }
            if let result = view.session.raycast(query).first {
                let t = result.worldTransform.columns.3
                let cam = view.pointOfView?.simdWorldPosition ?? SIMD3<Float>(0, 0, 0)
                let dx = t.x - cam.x
                let dy = t.y - cam.y
                let dz = t.z - cam.z
                let dist = Double(sqrt(dx * dx + dy * dy + dz * dz))
                DispatchQueue.main.async {
                    self.meters.wrappedValue = dist
                }
            }
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            _ = error
        }
    }
}
