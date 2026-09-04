import SwiftUI

struct CannotDoView: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WHAT WE CANNOT DO").font(.title2.weight(.semibold))
            Text("No 911 replacement. SOS offers system Emergency SOS only.")
            Text("No sat modem. No live weather. Hurricane card is procedure + paper.")
            Text("Mesh without LoRa is tens of meters plus DTN when people meet.")
            Text("Airplane: no sockets. Features work locally or log local.")
            Text("Vision is a guess. Fungi default LEAVE IT. Nothing unlocks edible.")
            Button("I UNDERSTAND") { runtime.acknowledgeCannotDo() }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(white: 0.18))
        }
        .foregroundStyle(Color(white: 0.86))
        .padding(24)
        .preferredColorScheme(.dark)
    }
}
