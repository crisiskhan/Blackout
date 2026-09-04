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
        "net.none": ["en": "NET · NONE", "es": "RED · NINGUNA"],
        "net.physics": ["en": "Airplane: no sockets. Mesh is Bluetooth tens of meters (MPC+BLE). LoRa never required. NET · NONE is local writes only.", "es": "Avión: sin sockets. Mesh es Bluetooth a decenas de metros (MPC+BLE). LoRa nunca es obligatorio. RED · NINGUNA es solo escritura local."],
        "vision.none": ["en": "NO VISION MODEL", "es": "SIN MODELO DE VISIÓN"],
        "chip.rally": ["en": "RALLY", "es": "REUNIR"],
        "chip.down": ["en": "DOWN", "es": "CAÍDO"],
        "scan.qr": ["en": "SCAN QR", "es": "ESCANEAR QR"],
        "net.nolog": ["en": "NO PEERS · LOGGED", "es": "SIN PARES · REGISTRADO"],
    ]

    static func t(_ key: String, _ locale: String) -> String {
        table[key]?[locale] ?? table[key]?["en"] ?? key
    }
}
