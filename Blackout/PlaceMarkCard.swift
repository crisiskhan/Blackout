import SwiftUI
import MapLibreMap
import Tokens

/// Glass composer for a party place. NAME, NOTE, and FACE stay here until DROP.
struct PlaceMarkCard: View {
    @Bindable var runtime: AppRuntime

    private var nameText: Binding<String> {
        Binding(
            get: { runtime.markDraft?.name ?? "" },
            set: { next in
                guard var draft = runtime.markDraft else { return }
                draft.name = next
                runtime.markDraft = draft
            }
        )
    }

    private var noteText: Binding<String> {
        Binding(
            get: { runtime.markDraft?.note ?? "" },
            set: { next in
                guard var draft = runtime.markDraft else { return }
                draft.note = next
                runtime.markDraft = draft
            }
        )
    }

    private var selected: PersonEmblem {
        PersonEmblem.resolved(runtime.markDraft?.emblem)
    }

    var body: some View {
        HoldGlassShell(onClose: { runtime.closeMark() }) {
            VStack(alignment: .leading, spacing: 10) {
                headline
                Rectangle()
                    .fill(Theme.silver.opacity(0.22))
                    .frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HUDField("NAME",
                            text: nameText,
                            id: "mark.name",
                            locked: true,
                            pointSize: 20,
                            weight: .heavy,
                            ink: Color.white,
                            onOpen: { runtime.pulse() }
                        )
                        HUDField("NOTE",
                            text: noteText,
                            id: "mark.note",
                            pointSize: 15,
                            weight: .bold,
                            ink: Color.white,
                            onOpen: { runtime.pulse() }
                        )
                        faceGrid
                        row(key: "COORDINATES", value: coordinates)
                        Button("DROP") { runtime.commitMark() }
                            .buttonStyle(HoldActionStyle(filled: true, expand: true))
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MARK")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("PARTY")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.silver)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var faceGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FACE")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver.opacity(0.75))
            EmblemFaceGrid(
                selected: selected,
                onPick: pick,
                compact: true
            )
        }
    }

    private var coordinates: String {
        guard let draft = runtime.markDraft else { return MapFieldChrome.destValue(point: nil) }
        return MapFieldChrome.destValue(point: (draft.lat, draft.lon))
    }

    private func pick(_ emblem: PersonEmblem) {
        guard var draft = runtime.markDraft else { return }
        draft.emblem = emblem.rawValue
        runtime.markDraft = draft
        runtime.pulse()
    }

    private func row(key: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.silver.opacity(0.75))
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
