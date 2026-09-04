import AppIntents

struct ActionButtonSOS: AppIntent {
    static var title: LocalizedStringResource = "CALL SOS"
    static var description = IntentDescription("Offers system Emergency SOS. Does not replace 911.")
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct ActionButtonOK: AppIntent {
    static var title: LocalizedStringResource = "I AM OK"
    func perform() async throws -> some IntentResult { .result() }
}
