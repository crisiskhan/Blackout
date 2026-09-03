import Foundation
import FieldCorpus
import OfflineSpeech

public enum FieldSpeech {
    public static func line(_ card: FieldCard, locale: String) -> String {
        locale == "es" ? card.title.es : card.title.en
    }
    public static func speak(_ card: FieldCard, locale: String, engine: OfflineSpeech) {
        engine.speak(line(card, locale: locale), locale: locale)
    }
}
