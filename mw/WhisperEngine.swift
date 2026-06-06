//
//  WhisperEngine.swift
//  mw
//
//  Thin Swift actor around whisper.cpp (Metal-accelerated via the bundled
//  xcframework). Serialises all access to the non-thread-safe whisper_context
//  and supports explicit load / unload for idle memory management.
//

import Foundation
import whisper

enum WhisperError: LocalizedError {
    case modelMissing
    case initFailed
    case transcribeFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .modelMissing:          "Модель не найдена в бандле приложения."
        case .initFailed:            "Не удалось загрузить модель."
        case .transcribeFailed(let code): "Ошибка распознавания (код \(code))."
        }
    }
}

actor WhisperEngine {
    private var context: OpaquePointer?
    private var loadedURL: URL?

    var isLoaded: Bool { context != nil }

    /// Loads the model at `url` into RAM (idempotent per URL). Reloads if a
    /// different model was previously loaded. Runs off the main thread.
    func load(from url: URL) throws {
        if context != nil, loadedURL == url { return }
        if context != nil {
            whisper_free(context)
            context = nil
            loadedURL = nil
        }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw WhisperError.modelMissing
        }

        var params = whisper_context_default_params()
        params.use_gpu = true        // Metal on Apple Silicon
        params.flash_attn = true     // extra speed on M-series

        guard let ctx = whisper_init_from_file_with_params(url.path(percentEncoded: false), params) else {
            throw WhisperError.initFailed
        }
        context = ctx
        loadedURL = url
    }

    /// Frees the model weights and Metal buffers.
    func unload() {
        if let context {
            whisper_free(context)
        }
        context = nil
        loadedURL = nil
    }

    /// Transcribes 16 kHz mono Float32 PCM. `language` is "ru"/"ro"/"en"/"auto".
    func transcribe(samples: [Float], language: String, modelURL: URL) throws -> String {
        try load(from: modelURL)
        guard let context else { throw WhisperError.initFailed }
        guard !samples.isEmpty else { return "" }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true
        params.no_timestamps = true
        params.suppress_blank = true
        params.suppress_nst = true       // suppress non-speech tokens
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))

        let status: Int32 = language.withCString { langPtr in
            params.language = langPtr
            params.detect_language = false      // "auto" in the string triggers detection
            return samples.withUnsafeBufferPointer { buffer in
                whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
            }
        }
        guard status == 0 else { throw WhisperError.transcribeFailed(status) }

        var text = ""
        let segmentCount = whisper_full_n_segments(context)
        for i in 0..<segmentCount {
            if let cString = whisper_full_get_segment_text(context, i) {
                text += String(cString: cString)
            }
        }
        return text
    }
    // No deinit: this engine is a long-lived singleton; memory is reclaimed via
    // unload() (idle timer) or at process exit. Swift 6 forbids touching
    // actor-isolated, non-Sendable state from a nonisolated deinit.
}
