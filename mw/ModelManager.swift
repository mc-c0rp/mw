//
//  ModelManager.swift
//  mw
//
//  Downloads the selected whisper model on demand into Application Support and
//  reports progress. Models are NOT bundled (keeps the app small). Two choices:
//  Large-v3 Turbo (default) and the full Large-v3.
//

import Foundation
import Observation

/// A downloadable whisper model (multilingual large-v3 family: en/ru/ro and more).
nonisolated enum WhisperModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case turbo   // ggml-large-v3-turbo-q5_0
    case full    // ggml-large-v3-q5_0

    var id: String { rawValue }

    var fileName: String {
        switch self {
        case .turbo: "ggml-large-v3-turbo-q5_0.bin"
        case .full:  "ggml-large-v3-q5_0.bin"
        }
    }

    var remoteURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }

    var expectedBytes: Int64 {
        switch self {
        case .turbo: 574_041_195
        case .full:  1_081_140_203
        }
    }

    var displayName: String {
        switch self {
        case .turbo: "Large v3 Turbo"
        case .full:  "Large v3 (полная)"
        }
    }

    var sizeText: String {
        switch self {
        case .turbo: "≈ 574 МБ"
        case .full:  "≈ 1.08 ГБ"
        }
    }

    func fileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("mw", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    var isDownloaded: Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL().path) else { return false }
        return ((attrs[.size] as? Int64) ?? 0) >= expectedBytes - 2_000_000
    }
}

@MainActor
@Observable
final class ModelManager {
    enum State: Equatable {
        case missing
        case downloading(Double)   // 0...1
        case ready
        case failed(String)
    }

    static let shared = ModelManager()

    private(set) var state: State = .missing

    private var session: URLSession?
    private var delegate: DownloadDelegate?
    private var waiters: [CheckedContinuation<Bool, Never>] = []
    private var downloadingModel: WhisperModel?

    private init() { refresh() }

    /// The model the user selected (persisted in AppSettings).
    var selected: WhisperModel { AppSettings.shared.model }
    var modelURL: URL { selected.fileURL() }
    var isReady: Bool { selected.isDownloaded }

    var downloadFraction: Double {
        if case .downloading(let p) = state { return p }
        return isReady ? 1 : 0
    }

    var statusLine: String {
        let name = selected.displayName
        switch state {
        case .missing:
            return L.s("\(name) — not downloaded", "\(name) — не загружена", "\(name) — nedescărcat")
        case .downloading(let p):
            let pct = Int(p * 100)
            return L.s("Downloading \(name)… \(pct)%", "Загрузка \(name)… \(pct)%", "Se descarcă \(name)… \(pct)%")
        case .ready:
            return L.s("\(name) — ready", "\(name) — готова", "\(name) — gata")
        case .failed(let message):
            return L.s("Download error: \(message)", "Ошибка загрузки: \(message)", "Eroare la descărcare: \(message)")
        }
    }

    /// Recompute state for the currently selected model.
    func refresh() {
        if selected.isDownloaded {
            state = .ready
        } else if case .downloading = state, downloadingModel == selected {
            // keep in-flight progress
        } else {
            state = .missing
        }
    }

    /// Called when the user picks a different model: cancel any in-flight download
    /// for the previous model and re-evaluate.
    func selectionChanged() {
        if downloadingModel != nil, downloadingModel != selected {
            cancelDownload()
        }
        refresh()
    }

    private func cancelDownload() {
        session?.invalidateAndCancel()
        session = nil
        delegate = nil
        downloadingModel = nil
        let pending = waiters
        waiters = []
        for continuation in pending { continuation.resume(returning: false) }
    }

    /// Ensures the selected model exists locally, downloading if needed.
    @discardableResult
    func ensureAvailable() async -> Bool {
        let model = selected
        if model.isDownloaded {
            state = .ready
            return true
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            waiters.append(continuation)
            startIfNeeded(model)
        }
    }

    private func startIfNeeded(_ model: WhisperModel) {
        guard session == nil else { return }
        downloadingModel = model
        let target = model.fileURL()
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        state = .downloading(0)

        let delegate = DownloadDelegate(
            target: target,
            expectedBytes: model.expectedBytes,
            onProgress: { progress in Task { @MainActor in self.handleProgress(progress) } },
            onComplete: { result in Task { @MainActor in self.handleComplete(result) } }
        )
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        self.delegate = delegate
        self.session = session
        session.downloadTask(with: model.remoteURL).resume()
    }

    private func handleProgress(_ progress: Double) {
        if case .downloading = state { state = .downloading(progress) }
    }

    private func handleComplete(_ result: Result<Void, Error>) {
        session?.finishTasksAndInvalidate()
        session = nil
        delegate = nil
        let finished = downloadingModel
        downloadingModel = nil

        let success: Bool
        switch result {
        case .success where finished?.isDownloaded == true:
            state = .ready
            success = true
        case .success:
            state = .failed("файл повреждён")
            success = false
        case .failure(let error):
            state = .failed(error.localizedDescription)
            success = false
        }

        let pending = waiters
        waiters = []
        for continuation in pending { continuation.resume(returning: success) }
    }
}

/// URLSession delegate that streams a model to disk and moves it into place.
/// @unchecked Sendable: its state is touched only on the session's serial queue.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let target: URL
    private let expectedBytes: Int64
    private let onProgress: @Sendable (Double) -> Void
    private let onComplete: @Sendable (Result<Void, Error>) -> Void
    private var moveError: Error?

    init(target: URL,
         expectedBytes: Int64,
         onProgress: @escaping @Sendable (Double) -> Void,
         onComplete: @escaping @Sendable (Result<Void, Error>) -> Void) {
        self.target = target
        self.expectedBytes = expectedBytes
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
        onProgress(min(1.0, Double(totalBytesWritten) / Double(total)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.moveItem(at: location, to: target)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            onComplete(.failure(error))
        } else if let moveError {
            onComplete(.failure(moveError))
        } else {
            onComplete(.success(()))
        }
    }
}
