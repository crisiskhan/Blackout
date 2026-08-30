import BlackoutCore
import BlackoutMesh
import DesignSystem
import Messaging
import SwiftUI
import VoicePTT

struct CommsRootView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case messages = "Messages"
        case ptt = "PTT"
        var id: String { rawValue }
    }

    let persistence: any PersistenceServing
    let crypto: any CryptoServing
    var mesh: MeshFacade
    @Bindable var roster: PartyRoster
    var extremeSaver: Bool
    @State private var segment: Segment = .messages

    var body: some View {
        VStack(spacing: 0) {
            Picker("Comms", selection: $segment) {
                ForEach(Segment.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            switch segment {
            case .messages:
                MessagingRootView(
                    persistence: persistence,
                    crypto: crypto,
                    mesh: mesh,
                    roster: roster
                )
            case .ptt:
                VoicePTTRootView(persistence: persistence, extremeSaver: extremeSaver)
            }
        }
        .background(BlackoutDS.Surface.base.ignoresSafeArea())
    }
}
