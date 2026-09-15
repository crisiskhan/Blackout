import Foundation
import FieldCorpus
import OfflineSpeech

public enum FieldSpeech {
    public static func line(_ card: FieldCard, locale: String) -> String {
        locale == "es" ? card.title.es : card.title.en
    }

    public static func line(_ card: FieldCard, step: Int, locale: String) -> String {
        guard card.steps.indices.contains(step) else { return line(card, locale: locale) }
        let st = card.steps[step]
        let doLine = (locale == "es" ? st.`do`.es : st.`do`.en)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let child = (locale == "es" ? st.child.es : st.child.en)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if child.isEmpty || child == doLine {
            return doLine
        }
        if doLine.hasSuffix(".") || doLine.hasSuffix("!") || doLine.hasSuffix("?") {
            return doLine + " " + child
        }
        return doLine + ". " + child
    }

    @discardableResult
    public static func speak(_ card: FieldCard, locale: String, engine: SpeechEngine, step: Int? = nil) -> Bool {
        let text: String
        if let step {
            text = line(card, step: step, locale: locale)
        } else {
            text = line(card, locale: locale)
        }
        return engine.speak(text, locale: locale)
    }
}
