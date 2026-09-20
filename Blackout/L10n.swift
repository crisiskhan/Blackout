import Foundation

enum L10n {
    static let table: [String: [String: String]] = [
        "sos.call": ["en": "CALL SOS", "es": "LLAMAR SOS"],
        "sos.hold": ["en": "Hold to light the mesh", "es": "Mantén para encender la malla"],
        "sos.mesh": ["en": "SOS · MESH", "es": "SOS · MALLA"],
        "red.plate": ["en": "RED", "es": "ROJO"],
        "red.cancel": ["en": "CANCEL RED", "es": "CANCELAR ROJO"],
        "stop.if": ["en": "STOP-IF", "es": "PARA-SI"],
        "overdue": ["en": "OVERDUE", "es": "VENCIDO"],
        "ok.chip": ["en": "I AM OK", "es": "ESTOY BIEN"],
        "form.up": ["en": "FORM UP", "es": "FORMAR"],
        "lost.kid": ["en": "LOST KID", "es": "NIÑO PERDIDO"],
        "chip.here": ["en": "HERE", "es": "AQUÍ"],
        "chip.wait": ["en": "WAIT", "es": "ESPERA"],
        "chip.moving": ["en": "MOVING", "es": "MARCHA"],
        "chip.come": ["en": "COME", "es": "VEN"],
        "chip.rally": ["en": "RALLY", "es": "REUNIR"],
        "chip.down": ["en": "DOWN", "es": "CAÍDO"],
        "chip.hurt": ["en": "HURT", "es": "HERIDO"],
        "chip.water": ["en": "WATER", "es": "AGUA"],
        "chip.lost": ["en": "LOST", "es": "PERDIDO"],
        "chip.found": ["en": "FOUND", "es": "HALLADO"],
        "net.none": ["en": "NET · NONE", "es": "RED · NINGUNA"],
        "vision.none": ["en": "NO VISION MODEL", "es": "SIN MODELO DE VISIÓN"],
        "vision.leave": ["en": "LEAVE IT", "es": "DÉJALO"],
        "scan.qr": ["en": "SCAN QR", "es": "ESCANEAR QR"],
        "net.nolog": ["en": "NO PEERS · LOGGED", "es": "SIN PARES · REGISTRADO"],
        "field.search": ["en": "SEARCH", "es": "BUSCAR"],
        "field.say": ["en": "SAY", "es": "DI"],
        "field.next": ["en": "NEXT", "es": "SIGUIENTE"],
        "field.done": ["en": "DONE", "es": "LISTO"],
        "field.send": ["en": "SEND TO PARTY", "es": "ENVIAR AL GRUPO"],
        "field.type": ["en": "TYPE OR SAY", "es": "ESCRIBE O DI"],
        "field.card": ["en": "CARD", "es": "TARJETA"],
        "field.step": ["en": "STEP", "es": "PASO"],
        "field.of": ["en": "OF", "es": "DE"],
        "field.back": ["en": "BACK", "es": "ATRÁS"],
        "field.care": ["en": "CARE", "es": "CUIDADO"],
        "field.do": ["en": "DO", "es": "HAZ"],
        "field.ask": ["en": "ASK", "es": "PREGUNTA"],
    ]

    static func t(_ key: String, _ locale: String) -> String {
        table[key]?[locale] ?? table[key]?["en"] ?? key
    }
}
