import BlackoutCore
import DesignSystem
import SwiftUI
import UIKit

struct FieldPingGrid: View {
    var enabled: Bool
    var reduceMotion: Bool
    var onPing: (FieldPingID) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                chip(.rally)
                chip(.escort)
            }
            HStack(spacing: 8) {
                chip(.danger)
                chip(.down)
            }
        }
        .opacity(enabled ? 1 : BlackoutDS.Comms.dimmed)
        .allowsHitTesting(enabled)
    }

    private func chip(_ id: FieldPingID) -> some View {
        FieldSignalChip(
            title: FieldPing.label(id),
            hue: FieldPing.hue(id),
            enabled: enabled,
            reduceMotion: reduceMotion
        ) {
            onPing(id)
        }
    }
}

struct FieldReplyRow: View {
    var enabled: Bool
    var reduceMotion: Bool
    var onReply: (FieldReplyID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(FieldReplyID.allCases, id: \.self) { id in
                FieldSignalChip(
                    title: FieldPing.label(id),
                    hue: FieldPing.hue(id),
                    enabled: enabled,
                    reduceMotion: reduceMotion
                ) {
                    onReply(id)
                }
            }
        }
        .opacity(enabled ? 1 : BlackoutDS.Comms.dimmed)
        .allowsHitTesting(enabled)
    }
}

struct FieldSignalChip: View {
    var title: String
    var hue: FieldPingHue
    var enabled: Bool
    var reduceMotion: Bool
    var action: () -> Void

    var body: some View {
        Button {
            if enabled {
                FieldPingChrome.playHaptic(hue)
                action()
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(FieldPingChrome.color(hue))
                    .frame(width: FieldPing.pip, height: FieldPing.pip)
                Text(title)
                    .font(BlackoutDS.bodyFont())
                    .fontWeight(.semibold)
                    .foregroundStyle(FieldPingChrome.color(hue))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: BlackoutDS.Hit.sm, alignment: .leading)
            .background(BlackoutDS.Silver.metal)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BlackoutDS.Silver.edge, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
        .animation(reduceMotion ? nil : BlackoutDS.Motion.snap, value: enabled)
    }
}

struct FieldPingCard: View {
    var title: String
    var callsign: String
    var createdAt: Date
    var footnote: String
    var hue: FieldPingHue
    var status: MessageStatus
    var onTap: () -> Void
    var onRetry: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Circle()
                    .fill(FieldPingChrome.color(hue))
                    .frame(width: FieldPing.pip, height: FieldPing.pip)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(BlackoutDS.bodyFont())
                        .fontWeight(.semibold)
                        .foregroundStyle(FieldPingChrome.color(hue))
                    Text("\(callsign) · \(createdAt.formatted(.relative(presentation: .named)))")
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.dim)
                    Text(footnote)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.steel)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: BlackoutDS.Comms.lockShield))
                        .foregroundStyle(BlackoutDS.Silver.steel)
                    Text(status.rawValue)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.dim)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: BlackoutDS.Hit.md, alignment: .leading)
            .background(BlackoutDS.Silver.metal)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BlackoutDS.Silver.edge, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            if let onRetry {
                Button(CommsCopy.retry, action: onRetry)
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.metal)
                    .padding(8)
            }
        }
    }
}

enum FieldPingChrome {
    static func color(_ hue: FieldPingHue) -> Color {
        switch hue {
        case .ok: return BlackoutDS.Semantic.ok
        case .warn: return BlackoutDS.Semantic.warn
        case .red: return BlackoutDS.Red.core
        }
    }

    static func playHaptic(_ hue: FieldPingHue, repeats: Int = 1) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch FieldPing.haptic(hue) {
        case .light: style = .light
        case .medium: style = .medium
        case .heavy: style = .heavy
        }
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.prepare()
        for index in 0..<max(1, repeats) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.12) {
                gen.impactOccurred()
            }
        }
    }
}
