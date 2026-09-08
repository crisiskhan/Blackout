import BlackoutCore
import DesignSystem
import SwiftUI
import UIKit

struct MeshRadioBannerView: View {
    var title: String
    var bodyText: String
    var onOpenSettings: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            Text(bodyText)
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.mid)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                MetalButton("Open Settings", height: BlackoutDS.Hit.sm, action: onOpenSettings)
                GhostButton("Dismiss", height: BlackoutDS.Hit.sm, action: onDismiss)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BlackoutDS.Surface.raised)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BlackoutDS.Silver.edge, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

enum AppSettingsLink {
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
