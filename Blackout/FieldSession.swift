import CryptoParty
import FieldAsk
import FieldCorpus
import FieldSpeech
import FieldStepper
import Foundation
import MapLibreMap
import UIKit
import VisionCoreML

enum FieldPlate: String, CaseIterable, Sendable, Hashable {
    case walk, care
}

/// Normalized still crop, UI origin top-left. The well draws this box.
struct VisionCrop: Sendable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

enum FieldWalkStore {
    static let key = "field.walk"

    struct Snapshot: Codable, Equatable {
        var cardID: String
        var index: Int
        var trail: [String]
        var trailTotal: Int
        var trailBook: String
        var plate: String
        var fieldQuery: String
    }

    static func snapshot(of field: FieldSession) -> Snapshot? {
        guard let stepper = field.stepper else { return nil }
        return Snapshot(
            cardID: stepper.card.id,
            index: stepper.index,
            trail: field.trail,
            trailTotal: field.trailTotal,
            trailBook: field.trailBook,
            plate: field.plate.rawValue,
            fieldQuery: field.fieldQuery
        )
    }

    static func save(_ field: FieldSession, defaults: UserDefaults = .standard) {
        guard let snap = snapshot(of: field),
              let data = try? JSONEncoder().encode(snap)
        else {
            defaults.removeObject(forKey: key)
            return
        }
        SealedPersist.put(data, forKey: key, defaults: defaults)
    }

    static func load(defaults: UserDefaults = .standard) -> Snapshot? {
        guard let data = SealedPersist.get(forKey: key, defaults: defaults) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}

struct FieldSession: Sendable {
    var query = ""
    var stepper: StepperState?
    var trail: [String] = []
    var trailTotal = 0
    var trailBook = ""
    var fork: [FieldCard] = []
    var fieldQuery = ""
    var guess: VisionGuess?
    var stillJPEG: Data?
    var visionBusy = false
    var visionCrop: VisionCrop?
    var sayFailed = false
    var askBusy = false
    var askFailed = false
    var askSeq = 0
    var askExpected = ""
    var visionSeq = 0
    var plate: FieldPlate = .walk

    mutating func leaveCard() {
        stepper = nil
        trail = []
        trailTotal = 0
        trailBook = ""
        fork = []
        fieldQuery = ""
        askFailed = false
        askBusy = false
        askSeq += 1
        askExpected = ""
        plate = .walk
    }

    mutating func clearInstrument() {
        query = ""
        guess = nil
        stillJPEG = nil
        visionBusy = false
        visionCrop = nil
        sayFailed = false
        visionSeq += 1
        leaveCard()
    }
}

extension AppRuntime {
    func cancelFieldAsk() {
        field.askSeq += 1
        field.askBusy = false
        field.askExpected = ""
    }

    func beginFieldAsk(
        query: String,
        chapter: [FieldCard],
        locale: String,
        packName: String,
        packId: String?
    ) {
        cancelFieldAsk()
        field.askSeq += 1
        let seq = field.askSeq
        field.askBusy = true
        field.askFailed = false
        field.askExpected = query
        field.fieldQuery = query
        field.sayFailed = false
        Task.detached {
            let card = FieldAsk.answer(
                query: query,
                chapter: chapter,
                locale: locale,
                packName: packName,
                packId: packId
            )
            await MainActor.run {
                self.applyFieldAsk(seq: seq, expected: query, card: card)
            }
        }
    }

    func applyFieldAsk(seq: Int, expected: String, card: FieldCard?) {
        guard seq == field.askSeq else { return }
        field.askBusy = false
        let now = field.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if now.isEmpty || now != expected { return }
        if let card {
            openFieldLive(card)
        } else {
            field.askFailed = true
        }
    }

    func openFieldLive(_ card: FieldCard) {
        field.query = ""
        field.askFailed = false
        field.askBusy = false
        field.trail = []
        field.trailTotal = 1
        field.trailBook = "ASK · LIVE"
        field.plate = .walk
        let wired = FieldTree.decorate(card, query: field.fieldQuery)
        field.stepper = StepperState(card: wired, index: 0, speaking: false, sentToParty: false)
        persistFieldWalk()
        speakFieldStep(wired, step: 0)
    }

    func speakFieldStep(_ card: FieldCard, step: Int) {
        if !FieldSpeech.speak(card, locale: locale, engine: speech, step: step) {
            speechChrome = "SPEECH FAILED"
        } else {
            speechChrome = ""
        }
    }

    func applyFieldVision(image: CGImage?) {
        field.visionSeq += 1
        let seq = field.visionSeq
        guard let image else {
            field.stillJPEG = nil
            field.visionCrop = nil
            field.visionBusy = false
            let next = VisionCoreML.noModelGuess()
            field.guess = next
            speakFieldVision(next)
            return
        }
        field.stillJPEG = UIImage(cgImage: image).jpegData(compressionQuality: 0.82)
        field.guess = nil
        field.visionBusy = true
        if let box = SystemVision.subjectNormalizedBox(from: image) {
            field.visionCrop = VisionCrop(
                x: box.minX, y: box.minY, w: box.width, h: box.height
            )
        } else {
            field.visionCrop = nil
        }
        let book = visionBook()
        let locale = locale
        DispatchQueue.global(qos: .userInitiated).async {
            let observations = SystemVision.observations(from: image)
            let next: VisionGuess
            if let observations, let book {
                next = VisionCoreML.classify(
                    observations: observations.map {
                        VisionObservation(identifier: $0.identifier, confidence: $0.confidence)
                    },
                    book: book,
                    locale: locale
                )
            } else {
                next = VisionCoreML.noModelGuess()
            }
            DispatchQueue.main.async {
                guard seq == self.field.visionSeq else { return }
                self.field.guess = next
                self.field.visionBusy = false
                self.speakFieldVision(next)
            }
        }
    }

    func speakFieldVision(_ g: VisionGuess) {
        let line: String
        if g.noModel {
            line = L10n.t("vision.none", locale)
        } else if g.leaveIt {
            line = "\(g.name). \(L10n.t("vision.leave", locale))"
        } else if InspectField.visionPrepWarns(g.labelId) {
            line = "\(g.name). \(L10n.t("vision.warn", locale))"
        } else {
            line = g.name
        }
        if !speech.speak(line, locale: locale) {
            speechChrome = "SPEECH FAILED"
        } else {
            speechChrome = ""
        }
    }

    func haltFieldListen() {
        if speech.listening {
            speech.endListen()
        }
    }

    func persistFieldWalk() {
        FieldWalkStore.save(field)
    }

    func restoreFieldWalk(in cards: [FieldCard]) {
        guard field.stepper == nil, !field.askBusy else { return }
        guard let snap = FieldWalkStore.load(),
              let card = cards.first(where: { $0.id == snap.cardID }),
              !card.steps.isEmpty
        else { return }
        let index = min(max(0, snap.index), card.steps.count - 1)
        field.fieldQuery = snap.fieldQuery
        field.trail = snap.trail
        field.trailTotal = max(snap.trailTotal, 1)
        field.trailBook = snap.trailBook
        field.plate = FieldPlate(rawValue: snap.plate) ?? .walk
        field.stepper = StepperState(
            card: FieldTree.decorate(card, query: snap.fieldQuery),
            index: index,
            speaking: false,
            sentToParty: false
        )
    }
}
