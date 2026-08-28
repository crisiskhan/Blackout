import BlackoutCore
import SwiftUI
import UIKit

/// Shared deny UI. Features must not fork this.
public struct PermissionDenied: View {
    private let kind: PermissionKind
    private let reason: String

    public init(kind: PermissionKind, reason: String) {
        self.kind = kind
        self.reason = reason
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(kind.title.uppercased())
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
                .tracking(1.2)
            Text("Permission denied")
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            Text(reason)
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.mid)
                .lineSpacing(BlackoutDS.TypeMetrics.bodyLine - BlackoutDS.TypeMetrics.body)
            Text(localCopy)
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
                .lineSpacing(BlackoutDS.TypeMetrics.bodyLine - BlackoutDS.TypeMetrics.body)
            MetalButton("Open Settings", height: BlackoutDS.Hit.md) {
                openSettings()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BlackoutDS.Surface.raised)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var localCopy: String {
        switch kind {
        case .location:
            return "GPS is off for Blackout. Last-known and compass-only still work when the OS has them. Bundled map, Guide, Skills, messaging, and SOS stay available."
        case .camera:
            return "Field Vision needs the camera. Deny is a valid field state. Guide and Skills remain on-device."
        case .microphone:
            return "Voice PTT stays local when allowed. Deny leaves text comms and SOS intact."
        case .bluetooth:
            return "Mesh is a dumb pipe. Zero nearby peers is success. Deny does not block SOS arming."
        case .motion:
            return "Heading may be unavailable. Navigate falls back to last-known when present."
        case .localAuthentication:
            return "Optional on-device lock. Blackout never sends biometrics or analytics."
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
