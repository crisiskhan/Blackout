import SwiftUI

public struct StoreFailure: View {
    private let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STORE FAILED")
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Semantic.warn)
                .tracking(1.2)
            Text(message)
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
                .lineSpacing(7)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BlackoutDS.Surface.hazard)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
        )
    }
}
