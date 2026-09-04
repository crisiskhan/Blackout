import Foundation
import BlackBox
#if canImport(AVFoundation)
import AVFoundation
#endif

public final class SpeechEngine: @unchecked Sendable {
    public private(set) var lastUtterance: String = ""
    public private(set) var lastFailed = false
    private let box: EventLog
    #if canImport(AVFoundation)
    private let synth = AVSpeechSynthesizer()
    #endif

    public init(box: EventLog) { self.box = box }

    @discardableResult
    public func speak(_ text: String, locale: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastFailed = true
            lastUtterance = "SPEECH FAILED"
            box.log("speech", "SPEECH FAILED")
            return false
        }
        #if canImport(AVFoundation)
        let u = AVSpeechUtterance(string: trimmed)
        u.voice = AVSpeechSynthesisVoice(language: locale == "es" ? "es-MX" : "en-US")
        synth.speak(u)
        lastFailed = false
        lastUtterance = "\(locale):\(trimmed)"
        box.log("speech", lastUtterance)
        return true
        #else
        lastFailed = true
        lastUtterance = "SPEECH FAILED"
        box.log("speech", "SPEECH FAILED")
        return false
        #endif
    }
}
