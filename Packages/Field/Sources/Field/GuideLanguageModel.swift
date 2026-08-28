import Foundation

/// Apple Foundation Models, used only when the system says the on-device model is already available.
/// Never first paint. Never wait on a download. Grounded on retrieved GuidePack text.
enum GuideLanguageModel {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return FoundationModelsBridge.isAvailable
        }
        #endif
        return false
    }

    static func complete(query: String, grounded: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await FoundationModelsBridge.complete(query: query, grounded: grounded)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
private enum FoundationModelsBridge {
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    static func complete(query: String, grounded: String) async -> String? {
        guard SystemLanguageModel.default.availability == .available else { return nil }
        let clipped = String(grounded.prefix(3500))
        let session = LanguageModelSession(instructions: """
        You are a field guide on this device. Answer ONLY from the excerpts. If they do not contain the answer, say you do not know.
        Never declare a plant edible. First aid is not medical advice. Do not invent map data or rescue ETAs.
        EXCERPTS:
        \(clipped)
        """)
        do {
            let response = try await session.respond(to: query)
            return "\(response.content)"
        } catch {
            return nil
        }
    }
}
#endif
