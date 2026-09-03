import Foundation

enum L10n {
    static let table: [String: [String: String]] = [
        "sos.call": ["en": "CALL SOS", "es": "LLAMAR SOS"],
        "sos.offer": ["en": "Offers iPhone Emergency SOS. Does not replace 911.", "es": "Ofrece Emergency SOS del iPhone. No reemplaza al 911."],
        "red.plate": ["en": "RED", "es": "ROJO"],
        "red.cancel": ["en": "CANCEL RED", "es": "CANCELAR ROJO"],
        "stop.if": ["en": "STOP-IF", "es": "PARA-SI"],
        "overdue": ["en": "OVERDUE", "es": "VENCIDO"],
        "ok.chip": ["en": "I AM OK", "es": "ESTOY BIEN"],
        "form.up": ["en": "FORM UP", "es": "FORMAR"],
        "lost.kid": ["en": "LOST KID", "es": "NIÑO PERDIDO"],
        "chip.wait": ["en": "WAIT", "es": "ESPERA"],
        "chip.water": ["en": "WATER", "es": "AGUA"],
    ]

    static func t(_ key: String, _ locale: String) -> String {
        table[key]?[locale] ?? table[key]?["en"] ?? key
    }
}
