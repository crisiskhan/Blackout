import SwiftUI
import UIKit
import MapLibreMap
import Tokens

/// Glass record for a packed CCTV still. UPDATE SNAPs the latest frame.
struct CamHoldCard: View {
    @Bindable var runtime: AppRuntime
    let cam: HeldCam

    var body: some View {
        HoldGlassShell(onClose: { runtime.closeHold() }) {
            VStack(alignment: .leading, spacing: 10) {
                headline
                Rectangle()
                    .fill(Theme.silver.opacity(0.22))
                    .frame(height: 1)
                actions
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        stillWell
                        rows
                    }
                }
                .holdScroll()
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cam.name)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("CAMERA")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.silver)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var stillWell: some View {
        ZStack {
            Theme.void
            if let still {
                Image(uiImage: still)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 180)
            } else {
                Text("NO STILL")
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
        .accessibilityLabel(still == nil ? "NO STILL" : "STILL")
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(key: "FROM", value: fromLine)
            row(key: "COORDINATES", value: MapFieldChrome.destValue(point: (cam.lat, cam.lon)))
            if !runtime.updateSocket.pipe {
                row(key: "PIPE", value: "NO PIPE")
            }
        }
    }

    private var fromLine: String {
        let provider = cam.provider.trimmingCharacters(in: .whitespacesAndNewlines)
        return provider.isEmpty ? "—" : provider.uppercased()
    }

    private var still: UIImage? {
        _ = runtime.updateSocket.updatedAt
        _ = runtime.updateSocket.busy
        let url = SnapManifest.folder().appendingPathComponent("cam-\(cam.id).jpg")
        return UIImage(contentsOfFile: url.path)
    }

    private func row(key: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver.opacity(0.75))
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        Button("TAP UPDATE") { runtime.tapUpdate() }
            .buttonStyle(HoldActionStyle(filled: runtime.updateSocket.busy, expand: true))
    }
}
