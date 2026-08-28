import AVFoundation
import BlackoutCore
import DesignSystem
import Speech
import SwiftUI

struct GuideAskView: View {
    var pack: GuidePackSnapshot?
    var context: GuideQueryContext
    var extremeSaver: Bool

    @State private var query = ""
    @State private var topic: GuideTopic?
    @State private var hits: [GuideHit] = []
    @State private var modelNote: String?
    @State private var listening = false
    @State private var micDenied = false
    @State private var micUnavailable = false
    @State private var error: String?
    @State private var recognizer: SFSpeechRecognizer?
    @State private var request: SFSpeechAudioBufferRecognitionRequest?
    @State private var task: SFSpeechRecognitionTask?
    @State private var engine = AVAudioEngine()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Ask the field guide", text: $query)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.bright)
                    .padding(14)
                    .frame(minHeight: BlackoutDS.Hit.sm)
                    .background(BlackoutDS.Surface.sunken)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(BlackoutDS.Silver.edge, lineWidth: 0.5)
                    )
                if !micUnavailable {
                    Button(action: toggleMic) {
                        Image(systemName: listening ? "mic.fill" : "mic")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(listening ? BlackoutDS.Red.hot : BlackoutDS.Silver.metal)
                            .frame(width: BlackoutDS.Hit.sm, height: BlackoutDS.Hit.sm)
                            .overlay(Circle().stroke(BlackoutDS.Silver.edge, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(listening ? "Stop mic" : "Speak")
                }
            }
            MetalButton("Ask", height: BlackoutDS.Hit.md, action: runAsk)
            if micDenied {
                PermissionDenied(kind: .microphone, reason: "Mic denied. Type the ask. Guide still works.")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    topicChip(nil, title: "All")
                    ForEach(GuideTopic.allCases) { item in
                        topicChip(item, title: item.title)
                    }
                }
            }
            if let error {
                StoreFailure(error)
            }
            if let modelNote {
                Text(modelNote)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.mid)
                    .lineSpacing(6)
            } else if GuideLanguageModel.isAvailable {
                Text("On-device model available. Pack snippets first; model is never first paint.")
                    .font(BlackoutDS.captionFont())
                    .foregroundStyle(BlackoutDS.Silver.steel)
            }
            ForEach(hits) { hit in
                HUDPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(hit.article.title)
                            .font(BlackoutDS.titleFont())
                        Text(hit.article.topic)
                            .font(BlackoutDS.captionFont())
                            .foregroundStyle(BlackoutDS.Silver.steel)
                        GuideMarkdownView(source: hit.article.body)
                    }
                }
            }
            if pack == nil {
                Text("GuidePack missing from the app bundle. Ask cannot retrieve.")
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Semantic.warn)
            }
        }
        .onAppear {
            micUnavailable = !onDeviceSpeechAvailable
        }
        .onChange(of: pack?.articles.count) { _, _ in
            if hits.isEmpty, let pack {
                hits = GuideSearch.retrieve(query: query, topic: topic, pack: pack, context: context)
            }
        }
        .onChange(of: topic) { _, _ in
            runAsk()
        }
    }

    private var onDeviceSpeechAvailable: Bool {
        let speech = SFSpeechRecognizer(locale: Locale.current)
        return speech?.supportsOnDeviceRecognition == true
    }

    private func topicChip(_ value: GuideTopic?, title: String) -> some View {
        let on = topic == value
        return Button {
            topic = value
        } label: {
            Text(title)
                .font(BlackoutDS.captionFont())
                .foregroundStyle(on ? BlackoutDS.Surface.void : BlackoutDS.Silver.bright)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(on ? BlackoutDS.Silver.metal : BlackoutDS.Surface.raised)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func runAsk() {
        guard let pack else {
            error = "GuidePack missing."
            hits = []
            return
        }
        let started = Date()
        hits = GuideSearch.retrieve(query: query, topic: topic, pack: pack, context: context)
        error = nil
        modelNote = nil
        let grounded = hits.prefix(5).map { $0.article.title + ". " + $0.article.body }.joined(separator: "\n")
        let elapsed = Date().timeIntervalSince(started)
        if elapsed > 2 {
            error = "Retrieve lagged. Showing pack hits anyway."
        }
        let snapshotQuery = query
        guard GuideLanguageModel.isAvailable, !snapshotQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            let text = await GuideLanguageModel.complete(query: snapshotQuery, grounded: grounded)
            await MainActor.run {
                if let text, !text.isEmpty {
                    modelNote = text
                }
            }
        }
    }

    private func toggleMic() {
        if listening {
            stopMic()
            return
        }
        guard onDeviceSpeechAvailable else {
            micUnavailable = true
            return
        }
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                switch status {
                case .authorized:
                    micDenied = false
                    startMic()
                case .denied, .restricted:
                    micDenied = true
                default:
                    micDenied = true
                }
            }
        }
    }

    private func startMic() {
        stopMic()
        let speech = SFSpeechRecognizer(locale: Locale.current)
        recognizer = speech
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        request = req
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            engine.prepare()
            try engine.start()
        } catch {
            micUnavailable = true
            stopMic()
            return
        }
        listening = true
        task = speech?.recognitionTask(with: req) { result, _ in
            Task { @MainActor in
                if let result {
                    query = result.bestTranscription.formattedString
                    if result.isFinal {
                        stopMic()
                        runAsk()
                    }
                }
            }
        }
    }

    private func stopMic() {
        listening = false
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
