import Foundation

/// No on-device ASK model. A 3B GGUF would drain the phone in an emergency.
/// FIELD ASK is the packed book walk. This door stays shut.
public enum FieldAskLlama {
    public static func complete(prompt: String, modelURL: URL) -> String? {
        _ = prompt
        _ = modelURL
        return nil
    }
}
