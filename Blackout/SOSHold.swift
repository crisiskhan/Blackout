import SwiftUI
import Tokens
import CommsUI

struct SOSHold: View {
    @Bindable var runtime: AppRuntime
    @State private var holding = false
    @State private var armedLocal = false
    @State private var press = 0

    var body: some View {
        Text(L10n.t("sos.call", runtime.locale))
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.white)
            .frame(width: BlackoutTokens.Chrome.sosDiameter, height: BlackoutTokens.Chrome.sosDiameter)
            .background(Theme.accent)
            .clipShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !holding else { return }
                        holding = true
                        press &+= 1
                        // Tag the press. Tapping, letting go and pressing again left the
                        // first timer in flight; it saw the second press still holding and
                        // armed it early, so SOS could fire well short of its 800 ms.
                        let armed = press
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(BlackoutTokens.Chrome.sosHoldMs) / 1000.0) {
                            if holding, armed == press { armedLocal = true }
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
