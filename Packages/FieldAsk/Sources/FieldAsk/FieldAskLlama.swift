import Foundation
import llama

public enum FieldAskLlama {
    private static let lock = NSLock()
    private static var backendReady = false
    private static var model: OpaquePointer?
    private static var context: OpaquePointer?
    private static var vocab: OpaquePointer?
    private static var loadedPath: String?

    public static func complete(prompt: String, modelURL: URL) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard ensure(url: modelURL),
              let ctx = context,
              let vocab
        else { return nil }
        llama_memory_clear(llama_get_memory(ctx), true)
        guard var tokens = tokenize(prompt, vocab: vocab), !tokens.isEmpty else { return nil }
        if tokens.count > 2200 { return nil }
        let promptCount = Int32(tokens.count)
        let decodedPrompt = tokens.withUnsafeMutableBufferPointer { buf -> Bool in
            guard let base = buf.baseAddress else { return false }
            let batch = llama_batch_get_one(base, promptCount)
            return llama_decode(ctx, batch) == 0
        }
        guard decodedPrompt else { return nil }
        var chainParams = llama_sampler_chain_default_params()
        guard let sampler = llama_sampler_chain_init(chainParams) else { return nil }
        defer { llama_sampler_free(sampler) }
        guard let greedy = llama_sampler_init_greedy() else { return nil }
        llama_sampler_chain_add(sampler, greedy)
        var out = ""
        for _ in 0..<800 {
            let token = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            out += piece(token, vocab: vocab)
            if out.contains("<|im_end|>") { break }
            var next = token
            let ok = withUnsafeMutablePointer(to: &next) { ptr in
                let batch = llama_batch_get_one(ptr, 1)
                return llama_decode(ctx, batch) == 0
            }
            if !ok { break }
        }
        if let cut = out.range(of: "<|im_end|>") {
            out = String(out[..<cut.lowerBound])
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func ensure(url: URL) -> Bool {
        if loadedPath == url.path, model != nil, context != nil, vocab != nil {
            return true
        }
        release()
        if !backendReady {
            llama_backend_init()
            backendReady = true
        }
        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        #else
        modelParams.n_gpu_layers = 99
        #endif
        guard let loaded = url.path.withCString({ llama_model_load_from_file($0, modelParams) }) else { return false }
        guard let loadedVocab = llama_model_get_vocab(loaded) else {
            llama_model_free(loaded)
            return false
        }
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = 3072
        ctxParams.n_batch = 3072
        ctxParams.n_ubatch = 3072
        ctxParams.n_threads = 2
        ctxParams.n_threads_batch = 2
        guard let ctx = llama_init_from_model(loaded, ctxParams) else {
            llama_model_free(loaded)
            return false
        }
        model = loaded
        context = ctx
        vocab = loadedVocab
        loadedPath = url.path
        return true
    }

    private static func release() {
        if let ctx = context {
            llama_free(ctx)
            context = nil
        }
        if let loaded = model {
            llama_model_free(loaded)
            model = nil
        }
        vocab = nil
        loadedPath = nil
    }

    private static func tokenize(_ text: String, vocab: OpaquePointer) -> [llama_token]? {
        let utf8Count = Int32(text.utf8.count)
        let nMax = utf8Count + 16
        var buf = [llama_token](repeating: 0, count: Int(nMax))
        let n = text.withCString { ptr in
            llama_tokenize(vocab, ptr, utf8Count, &buf, nMax, true, true)
        }
        if n < 0 {
            let need = Int(-n)
            buf = [llama_token](repeating: 0, count: need)
            let n2 = text.withCString { ptr in
                llama_tokenize(vocab, ptr, utf8Count, &buf, Int32(need), true, true)
            }
            guard n2 > 0 else { return nil }
            return Array(buf.prefix(Int(n2)))
        }
        guard n > 0 else { return nil }
        return Array(buf.prefix(Int(n)))
    }

    private static func piece(_ token: llama_token, vocab: OpaquePointer) -> String {
        var buf = [CChar](repeating: 0, count: 128)
        let n = llama_token_to_piece(vocab, token, &buf, 128, 0, true)
        guard n > 0 else { return "" }
        return String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
