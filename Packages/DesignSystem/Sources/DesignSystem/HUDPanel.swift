import SwiftUI

public struct HUDPanel<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .font(BlackoutDS.bodyFont())
            .foregroundStyle(BlackoutDS.Silver.bright)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(BlackoutDS.Surface.raised.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
