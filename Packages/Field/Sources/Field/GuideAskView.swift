import AVFoundation
import BlackoutCore
import DesignSystem
import Speech
import SwiftUI

struct GuideAskView: View {
    var pack: GuidePackSnapshot?
    var packTooNew = false
    var context: GuideQueryContext
    var extremeSaver: Bool
    var focusArticleID: String? = nil
    var onSendArticle: (String) -> Void = { _ in }
    var onStartMode: (FieldJobMode) -> Void = { _ in }
    var onOpenMapJob: (GuideMapJob) -> Void = { _ in }
    var openExpeditionID: String? = nil

    @State private var query = ""
    @State private var hits: [GuideHit] = []
    @State private var activeArticle: GuideArticle?
    @State private var browsing = false
    @State private var asked = false
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
            if let activeArticle {
                HUDPanel {
                    GuideTreePlate(
                        article: activeArticle,
                        onSendArticle: onSendArticle,
                        onStartMode: onStartMode,
                        onOpenMapJob: onOpenMapJob,
                        openExpeditionID: openExpeditionID,
                        onStop: returnToAsk
                    )
                    .id(activeArticle.id)
                }
            } else if browsing {
                browsePlate
            } else {
                askHome
            }
        }
        .onAppear {
            micUnavailable = !onDeviceSpeechAvailable
            if let pack { focusInbound(in: pack) }
        }
        .onChange(of: focusArticleID) { _, _ in
            if let pack { focusInbound(in: pack) }
        }
    }

    private var askHome: some View {
        VStack(alignment: .leading, spacing: 12) {
            askFieldRow
            MetalButton("Ask", height: BlackoutDS.Hit.md, action: runAsk)
            Text(GuideAskRanker.honestyLine(context))
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.steel)
            if micDenied {
                PermissionDenied(kind: .microphone, reason: "Mic denied. Type the ask. Guide still works.")
            }
            chipRow
            GhostButton(FieldAskHomeLock.browseLabel, height: BlackoutDS.Hit.sm, action: runBrowse)
            if let error {
                StoreFailure(error)
            }
            if asked, FieldAskHomeLock.presentsUnknown(hitCount: hits.count) {
                Text(FieldAskHomeLock.unknownCopy)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.mid)
                    .lineSpacing(6)
            }
            packStatus
        }
    }

    private var browsePlate: some View {
        VStack(alignment: .leading, spacing: 12) {
            askFieldRow
            MetalButton("Ask", height: BlackoutDS.Hit.md, action: runAsk)
            ForEach(hits) { hit in
                GhostButton(hit.article.title, height: BlackoutDS.Hit.sm) {
                    openArticle(hit.article)
                }
            }
            MetalButton(GuideSpeak.controlStop, height: BlackoutDS.Hit.lg, action: returnToAsk)
            if let error {
                StoreFailure(error)
            }
            packStatus
        }
    }

    private var askFieldRow: some View {
        HStack(spacing: 8) {
            TextField(FieldAskHomeLock.askPlaceholder, text: $query)
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
    }

    private var chipRow: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            spacing: 8
        ) {
            ForEach(FieldAskHomeLock.homeChipTitles, id: \.self) { title in
                MetalButton(title, height: BlackoutDS.Hit.sm) {
                    openChip(title)
                }
            }
        }
    }

    @ViewBuilder
    private var packStatus: some View {
        if packTooNew {
            Text(GuidePackSchema.tooNewCopy)
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Semantic.warn)
        } else if pack == nil {
            Text("GuidePack missing from the app bundle. Ask cannot retrieve.")
                .font(BlackoutDS.bodyFont())
                .foregroundStyle(BlackoutDS.Semantic.warn)
        }
    }

    private func openChip(_ title: String) {
        guard let id = FieldAskHomeLock.homeChipArticleID(title) else { return }
        openTree(id: id)
    }

    private func openTree(id: String) {
        guard let pack, let article = pack.articles.first(where: { $0.id == id }) else {
            query = id.replacingOccurrences(of: "-", with: " ")
            runAsk()
            return
        }
        openArticle(article)
    }

    private func openArticle(_ article: GuideArticle) {
        stopMic()
        activeArticle = article
        browsing = false
        asked = true
        hits = [GuideHit(article: article, score: 1, snippet: article.body)]
        error = nil
    }

    private func returnToAsk() {
        activeArticle = nil
        browsing = false
        hits = []
        asked = false
        error = nil
    }

    private var onDeviceSpeechAvailable: Bool {
        let speech = SFSpeechRecognizer(locale: Locale.current)
        return speech?.supportsOnDeviceRecognition == true
    }

    private func focusInbound(in pack: GuidePackSnapshot) {
        guard let focusArticleID,
              let article = pack.articles.first(where: { $0.id == focusArticleID }) else { return }
        openArticle(article)
    }

    private func runBrowse() {
        retrieveHits()
    }

    private func runAsk() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            hits = []
            asked = true
            error = nil
            applyHits()
            return
        }
        retrieveHits()
    }

    private func retrieveHits() {
        guard let pack else {
            error = packTooNew ? GuidePackSchema.tooNewCopy : "GuidePack missing."
            hits = []
            asked = true
            activeArticle = nil
            browsing = false
            return
        }
        let started = Date()
        hits = GuideSearch.retrieve(query: query, topic: nil, pack: pack, context: context)
        error = nil
        asked = true
        let elapsed = Date().timeIntervalSince(started)
        if elapsed > 2 {
            error = "Retrieve lagged. Showing pack hits anyway."
        }
        applyHits()
    }

    private func applyHits() {
        if FieldAskHomeLock.presentsStepPager(hitCount: hits.count), let first = hits.first {
            activeArticle = first.article
            browsing = false
        } else if FieldAskHomeLock.presentsBrowse(hitCount: hits.count) {
            activeArticle = nil
            browsing = true
        } else {
            activeArticle = nil
            browsing = false
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
