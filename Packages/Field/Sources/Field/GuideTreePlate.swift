import BlackoutCore
import DesignSystem
import SwiftUI

/// Medical / lost tree: triage first, then pictograms, care pin, speak, gear, memory, map jobs.
struct GuideTreePlate: View {
    var article: GuideArticle
    var onSendArticle: (String) -> Void
    var onStartMode: (FieldJobMode) -> Void
    var onOpenMapJob: (GuideMapJob) -> Void
    var openExpeditionID: String? = nil
    var onStop: () -> Void = {}

    @State private var triage: GuideTriageChoice?
    @State private var showText = false
    @State private var stepIndex = 0
    @State private var speech = GuideSpeech()
    @State private var memory = OutingMemoryStore.load()
    @State private var gear = OutingGearStore.load()
    @State private var weightDraft = ""
    @State private var allergyDraft = ""

    var body: some View {
        let medical = GuideTriage.isMedicalOrLost(id: article.id, topic: article.topic, tags: article.tags)
        VStack(alignment: .leading, spacing: 10) {
            Text(article.title)
                .font(BlackoutDS.titleFont())
            Text(article.topic)
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.steel)
            if medical, triage == nil {
                triagePlate
            } else {
                treeBody(medical: medical)
            }
        }
        .onAppear {
            OutingMemoryStore.clearIfOutingEnded(openExpeditionID: openExpeditionID)
            memory = OutingMemoryStore.load()
            if memory.outingID.isEmpty {
                memory.outingID = openExpeditionID ?? "session"
            }
            gear = OutingGearStore.load()
        }
    }

    private var triagePlate: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Adult / Kid / Party-split")
                .font(BlackoutDS.titleFont())
            Text("First question. Then the tree. Not a search box.")
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.mid)
            MetalButton("Adult", height: BlackoutDS.Hit.lg) {
                applyTriage(.adult)
            }
            MetalButton("Kid", height: BlackoutDS.Hit.lg) {
                applyTriage(.kid)
            }
            MetalButton("Party-split", height: BlackoutDS.Hit.lg) {
                applyTriage(.partySplit)
            }
        }
    }

    @ViewBuilder
    private func treeBody(medical: Bool) -> some View {
        let steps = resolvedSteps
        if medical, let pin = GuideCarePinParser.parse(article.body).firstLine {
            Text(pin)
                .font(BlackoutDS.titleFont())
                .foregroundStyle(BlackoutDS.Semantic.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
        outingPrompts
        if !steps.isEmpty {
            pictogramFirst(steps: steps)
            speakControls(steps: steps)
        }
        if OutingGearStore.load().isEmpty, medical {
            Text("Gear list empty. Showing improvise steps.")
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.dim)
        }
        mapJobRow
        MetalButton(GuideCardWire.sendLabel, height: BlackoutDS.Hit.sm) {
            onSendArticle(article.id)
        }
        if let mode = FieldJobMode.from(articleID: article.id) {
            MetalButton(mode.title, height: BlackoutDS.Hit.sm) {
                onStartMode(mode)
            }
        }
        if showText || steps.isEmpty {
            GuideMarkdownView(source: article.body)
        } else {
            GhostButton("Show text", height: BlackoutDS.Hit.sm) {
                showText = true
            }
        }
    }

    private var outingPrompts: some View {
        let medical = GuideTriage.isMedicalOrLost(id: article.id, topic: article.topic, tags: article.tags)
        return Group {
            if medical, memory.shouldAskWeight {
                HStack(spacing: 8) {
                    TextField("Weight kg", text: $weightDraft)
                        .keyboardType(.decimalPad)
                        .font(BlackoutDS.bodyFont())
                        .foregroundStyle(BlackoutDS.Silver.bright)
                        .padding(14)
                        .frame(minHeight: BlackoutDS.Hit.sm)
                        .background(BlackoutDS.Surface.sunken)
                    MetalButton("Save", height: BlackoutDS.Hit.sm) {
                        if let kg = Double(weightDraft) {
                            memory.rememberWeight(kg)
                            OutingMemoryStore.save(memory)
                        }
                    }
                }
            }
            if medical, memory.shouldAskAllergy {
                HStack(spacing: 8) {
                    TextField("Allergy this outing", text: $allergyDraft)
                        .font(BlackoutDS.bodyFont())
                        .foregroundStyle(BlackoutDS.Silver.bright)
                        .padding(14)
                        .frame(minHeight: BlackoutDS.Hit.sm)
                        .background(BlackoutDS.Surface.sunken)
                    MetalButton("Save", height: BlackoutDS.Hit.sm) {
                        memory.rememberAllergy(allergyDraft.isEmpty ? "none" : allergyDraft)
                        OutingMemoryStore.save(memory)
                    }
                }
            }
        }
    }

    private func pictogramFirst(steps: [String]) -> some View {
        let pictos = GuidePictogramSteps.symbols(for: steps)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Steps")
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.steel)
            PictogramBar(
                items: pictos.enumerated().map { index, picto in
                    PictogramBar.Item(
                        id: "\(index)",
                        systemName: picto.systemName,
                        on: index == stepIndex,
                        label: picto.spoken,
                        action: {
                            stepIndex = index
                            if let spoken = GuideSpeak.nextStepOnly(steps: steps, index: index) {
                                speech.speakNext(spoken)
                            }
                        }
                    )
                }
            )
        }
    }

    private func speakControls(steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let current = GuideSpeak.nextStepOnly(steps: steps, index: stepIndex) {
                Text(current)
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.mid)
                    .lineSpacing(6)
            }
            HStack(spacing: 8) {
                MetalButton(GuideSpeak.controlNext, height: BlackoutDS.Hit.lg) {
                    if stepIndex + 1 < steps.count {
                        stepIndex += 1
                    }
                    if let spoken = GuideSpeak.nextStepOnly(steps: steps, index: stepIndex) {
                        speech.speakNext(spoken)
                    }
                }
                MetalButton(GuideSpeak.controlStop, height: BlackoutDS.Hit.lg) {
                    speech.stop()
                    onStop()
                }
            }
        }
    }

    private var mapJobRow: some View {
        let jobs = GuideMapJob.jobs(forArticleID: article.id, tags: article.tags, topic: article.topic)
        return Group {
            if !jobs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(jobs) { job in
                        MetalButton(job.title, height: BlackoutDS.Hit.sm) {
                            onOpenMapJob(job)
                        }
                    }
                }
            }
        }
    }

    private var resolvedSteps: [String] {
        let raw = GuideTreeText.doSteps(in: article.body)
        let medical = GuideTriage.isMedicalOrLost(id: article.id, topic: article.topic, tags: article.tags)
        guard medical else { return raw }
        return GuideGearAware.select(steps: raw, gear: gear).steps
    }

    private func applyTriage(_ choice: GuideTriageChoice) {
        triage = choice
        switch GuideTriage.route(choice, treeID: article.id, tags: article.tags) {
        case .adultTree:
            break
        case .partySplit:
            onStartMode(.partySplit)
        case let .kidModes(modes):
            if let first = modes.first {
                onStartMode(first)
            }
        }
    }
}

struct GuideSkillsView: View {
    var pack: GuidePackSnapshot?
    var onOpenMapJob: (GuideMapJob) -> Void

    @State private var selectedArticle: GuideArticle?

    var body: some View {
        FieldSafePlate {
            VStack(alignment: .leading, spacing: 20) {
                if let selectedArticle,
                   let kind = GuideDoAlong.classify(
                    id: selectedArticle.id,
                    tags: selectedArticle.tags,
                    topic: selectedArticle.topic
                   ) {
                    HUDPanel {
                        GuideDoAlongPlate(
                            article: selectedArticle,
                            kind: kind,
                            onOpenMapJob: onOpenMapJob,
                            onStop: { self.selectedArticle = nil }
                        )
                        .id(selectedArticle.id)
                    }
                } else {
                    ScreenHeader("Primitive skills", subtitle: "Timed do-along. Fire, shelter, water. Not a game.")
                    ForEach(doAlongArticles) { article in
                        MetalButton(article.title, height: BlackoutDS.Hit.sm) {
                            selectedArticle = article
                        }
                    }
                    Text(GuideDoAlong.hardStopCopy)
                        .font(BlackoutDS.captionFont())
                        .foregroundStyle(BlackoutDS.Silver.dim)
                }
            }
        }
    }

    private var doAlongArticles: [GuideArticle] {
        let fromPack = pack?.articles.filter {
            GuideDoAlong.classify(id: $0.id, tags: $0.tags, topic: $0.topic) != nil
                && $0.id.hasPrefix("skill-")
        } ?? []
        if !fromPack.isEmpty { return Array(fromPack.prefix(3)) }
        return [
            GuideArticle(
                id: "skill-ferro-fire",
                title: "Throw a spark into a nest, not into the air.",
                topic: "fire",
                tags: ["fire"],
                body: FieldManual.skills.first?.body ?? "Build a small fire. Then walk."
            ),
            GuideArticle(
                id: "skill-debris-hut",
                title: "A small debris roof you can finish.",
                topic: "shelter",
                tags: ["shelter"],
                body: FieldManual.skills.first?.body ?? "Build a small roof. Then walk."
            ),
            GuideArticle(
                id: "skill-boil-water",
                title: "Rolling boil in a pot you can still hold.",
                topic: "water",
                tags: ["water"],
                body: FieldManual.skills.first?.body ?? "Boil. Then walk."
            )
        ]
    }
}

struct GuideDoAlongPlate: View {
    var article: GuideArticle
    var kind: GuideDoAlongKind
    var onOpenMapJob: (GuideMapJob) -> Void
    var onStop: () -> Void = {}

    @State private var stepIndex = 0
    @State private var started: Date?
    @State private var now = Date()
    @State private var speech = GuideSpeech()
    @State private var stopped = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let steps = GuideTreeText.doSteps(in: article.body)
        let elapsed = started.map { now.timeIntervalSince($0) } ?? 0
        let hard = GuideDoAlong.shouldHardStop(elapsed: elapsed, kind: kind)
        VStack(alignment: .leading, spacing: 10) {
            Text(article.title)
                .font(BlackoutDS.titleFont())
            Text(kind.rawValue.capitalized)
                .font(BlackoutDS.captionFont())
                .foregroundStyle(BlackoutDS.Silver.steel)
            if stopped || hard {
                Text(GuideDoAlong.hardStopCopy)
                    .font(BlackoutDS.titleFont())
                    .foregroundStyle(BlackoutDS.Semantic.warn)
                Text("Not a game. Walk.")
                    .font(BlackoutDS.bodyFont())
                    .foregroundStyle(BlackoutDS.Silver.mid)
                MetalButton(GuideSpeak.controlStop, height: BlackoutDS.Hit.lg) {
                    speech.stop()
                    onStop()
                }
            } else {
                if let current = GuideSpeak.nextStepOnly(steps: steps, index: stepIndex) {
                    Text(current)
                        .font(BlackoutDS.bodyFont())
                        .foregroundStyle(BlackoutDS.Silver.mid)
                        .lineSpacing(6)
                }
                HStack(spacing: 8) {
                    MetalButton(started == nil ? "Do along" : GuideSpeak.controlNext, height: BlackoutDS.Hit.lg) {
                        if started == nil {
                            started = Date()
                            if let spoken = GuideSpeak.nextStepOnly(steps: steps, index: 0) {
                                speech.speakNext(spoken)
                            }
                        } else if stepIndex + 1 < steps.count {
                            stepIndex += 1
                            if let spoken = GuideSpeak.nextStepOnly(steps: steps, index: stepIndex) {
                                speech.speakNext(spoken)
                            }
                        } else {
                            stopped = true
                            speech.stop()
                        }
                    }
                    MetalButton(GuideSpeak.controlStop, height: BlackoutDS.Hit.lg) {
                        stopped = true
                        speech.stop()
                        onStop()
                    }
                }
            }
            ForEach(GuideMapJob.jobs(forArticleID: article.id, tags: article.tags, topic: article.topic)) { job in
                MetalButton(job.title, height: BlackoutDS.Hit.sm) {
                    onOpenMapJob(job)
                }
            }
        }
        .onReceive(timer) { date in
            now = date
            if hard {
                speech.stop()
            }
        }
    }
}
