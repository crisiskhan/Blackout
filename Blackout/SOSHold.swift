import SwiftUI
import Tokens
import CommsUI

struct SOSHold: View {
    @Bindable var runtime: AppRuntime
    @State private var holding = false
    @State private var armedLocal = false

    var body: some View {
        Text(L10n.t("sos.call", runtime.locale))
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.white)
            .frame(width: BlackoutTokens.Chrome.sosDiameter, height: BlackoutTokens.Chrome.sosDiameter)
            .background(Color(red: 0.86, green: 0.14, blue: 0.14))
            .clipShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !holding {
                            holding = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + Double(BlackoutTokens.Chrome.sosHoldMs) / 1000.0) {
                                if holding { armedLocal = true }
                            }
                        }
                    }
                    .onEnded { _ in
                        holding = false
                        if armedLocal {
                            runtime.box.log("sos", "offer system Emergency SOS — does not replace 911")
                            armedLocal = false
                        }
                    }
            )
            .accessibilityLabel(L10n.t("sos.call", runtime.locale))
    }
}

struct IAMOKBar: View {
    @Bindable var runtime: AppRuntime
    var body: some View {
        VStack {
            HStack {
                Button(L10n.t("ok.chip", runtime.locale)) {
                    runtime.comms.chips.append(.ok)
                    runtime.mesh.sendChip(from: runtime.mesh.localID, chip: Chip.ok.rawValue)
                    runtime.box.log("ok", "I AM OK")
                }
                .padding(8)
                .background(Color(white: 0.15))
                Spacer()
            }
            Spacer()
        }
        .padding(12)
    }
}
