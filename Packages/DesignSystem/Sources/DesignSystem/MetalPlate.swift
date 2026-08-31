import SwiftUI

/// Brushed metal plate. Mock rails / header / search. Not a system pill.
public struct MetalPlate: View {
    public enum Kind {
        case rail
        case bright
        case inset
    }

    public static let railCorner: CGFloat = 6
    public static let searchCorner: CGFloat = 8
    public static let headerCorner: CGFloat = 8

    private let kind: Kind
    private let cornerRadius: CGFloat

    public init(_ kind: Kind, cornerRadius: CGFloat) {
        self.kind = kind
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(fill)
            .overlay {
                shape.fill(brush).opacity(0.22)
            }
            .overlay(alignment: .top) {
                shape
                    .stroke(BlackoutDS.Silver.bright.opacity(highlight), lineWidth: 1)
                    .padding(.bottom, 2)
                    .clipped()
            }
            .overlay {
                shape.stroke(edge, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.42), radius: 3, x: 0, y: 2)
    }

    private var fill: LinearGradient {
        switch kind {
        case .rail:
            return LinearGradient(
                colors: [
                    BlackoutDS.Surface.overlay,
                    BlackoutDS.Surface.raised,
                    BlackoutDS.Surface.base
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .bright:
            return LinearGradient(
                colors: [
                    BlackoutDS.Silver.metal,
                    BlackoutDS.Silver.edge,
                    BlackoutDS.Silver.mid
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .inset:
            return LinearGradient(
                colors: [
                    BlackoutDS.Surface.sunken,
                    BlackoutDS.Surface.raised,
                    BlackoutDS.Surface.overlay
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var brush: LinearGradient {
        LinearGradient(
            colors: [
                BlackoutDS.Silver.steel.opacity(0.0),
                BlackoutDS.Silver.edge.opacity(0.35),
                BlackoutDS.Silver.steel.opacity(0.0),
                BlackoutDS.Silver.bright.opacity(0.18),
                BlackoutDS.Silver.steel.opacity(0.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var edge: Color {
        switch kind {
        case .bright:
            return BlackoutDS.Silver.steel
        case .rail, .inset:
            return BlackoutDS.Silver.edge
        }
    }

    private var highlight: Double {
        switch kind {
        case .bright: return 0.55
        case .rail: return 0.22
        case .inset: return 0.12
        }
    }
}

public extension View {
    func metalPlate(_ kind: MetalPlate.Kind, cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background { MetalPlate(kind, cornerRadius: cornerRadius) }
            .clipShape(shape)
    }
}
