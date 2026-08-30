import BlackoutCore
import DesignSystem
import MapsRouting
import SwiftUI

struct CompassLockBar: View {
    var isLocked: Bool
    var hasTarget: Bool
    var onSpeak: () -> Void
    var onSteer: () -> Void
    var onMark: () -> Void
    var onLock: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            lockChip(CompassLockCopy.speak, lit: false, action: onSpeak)
            lockChip(CompassLockCopy.steer, lit: hasTarget && !isLocked, action: onSteer)
            lockChip(CompassLockCopy.mark, lit: false, action: onMark)
            lockChip(isLocked ? CompassLockCopy.locked : CompassLockCopy.lock, lit: isLocked, action: onLock)
        }
        .accessibilityElement(children: .contain)
    }

    private func lockChip(_ title: String, lit: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(BlackoutDS.captionFont())
                .fontWeight(.semibold)
                .foregroundStyle(lit ? BlackoutDS.Surface.void : BlackoutDS.Silver.bright)
                .frame(maxWidth: .infinity)
                .frame(height: BlackoutDS.Hit.sm)
                .background(lit ? BlackoutDS.Silver.metal : BlackoutDS.Surface.raised.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct CompassLockEmptyCard: View {
    var text: String

    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
                .padding(20)
                .frame(maxWidth: 400, alignment: .leading)
                .background(BlackoutDS.Surface.raised)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)
            Spacer()
        }
        .padding(.bottom, 100)
    }
}

struct CompassMarkSheet: View {
    @Bindable var session: CompassLockSession
    var peers: [RadarBlip]
    var fix: LocationFix?
    var onLocked: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ScreenHeader("MARK")
                    TextField("Name", text: $session.markName)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .font(BlackoutDS.bodyFont())
                        .foregroundStyle(BlackoutDS.Silver.bright)
                        .padding(.horizontal, 16)
                        .frame(height: BlackoutDS.Hit.md)
                        .background(BlackoutDS.Surface.raised.opacity(0.82))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    MetalButton(CompassLockCopy.saveCurrent, height: BlackoutDS.Hit.md) {
                        _ = session.saveCurrent(at: fix)
                    }
                    .opacity(nameReady ? 1 : 0.45)
                    .disabled(!nameReady)
                    ForEach(session.pickerRows(peers: peers)) { point in
                        markRow(point)
                    }
                }
                .padding(20)
            }
            .background(BlackoutDS.Surface.base.ignoresSafeArea())
            .navigationTitle("MARK")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private var nameReady: Bool {
        CompassLockMath.committedName(session.markName) != nil
    }

    private func markRow(_ point: CompassLockWaypoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(point.name)
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Silver.bright)
            HStack(spacing: 8) {
                GhostButton(CompassLockCopy.steer, height: BlackoutDS.Hit.sm) {
                    session.steer(point)
                    session.showMarkSheet = false
                }
                GhostButton(CompassLockCopy.locked, height: BlackoutDS.Hit.sm) {
                    _ = session.lockOn(point)
                    session.showMarkSheet = false
                    onLocked()
                }
                if point.canDelete {
                    GhostButton(CompassLockCopy.delete, height: BlackoutDS.Hit.sm) {
                        session.deleteMark(point)
                    }
                }
            }
        }
        .padding(12)
        .background(BlackoutDS.Surface.raised.opacity(0.82))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
