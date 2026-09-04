import Foundation
import FieldCorpus
import OfflineSpeech

public enum FieldSpeech {
    public static func line(_ card: FieldCard, locale: String) -> String {
        locale == "es" ? card.title.es : card.title.en
    }
    @discardableResult
    public static func speak(_ card: FieldCard, locale: String, engine: SpeechEngine) -> Bool {
        engine.speak(line(card, locale: locale), locale: locale)
    }
}
