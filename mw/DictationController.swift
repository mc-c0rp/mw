//
//  DictationController.swift
//  mw
//
//  Central state machine: hotkey → record (+ parallel model load) → stop →
//  transcribe → deliver text → show result → idle-unload.
//

import AppKit
import Observation

@MainActor
@Observable
final class DictationController {
    static let shared = DictationController()

    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case preparing      // downloading the model before first use
    }

    private(set) var state: State = .idle
    private(set) var isModelLoaded = false

    let settings = AppSettings.shared
    let modelManager = ModelManager.shared

    var isRecording: Bool { state == .recording }
    var menuBarSymbol: String {
        switch state {
        case .idle:         "mic"
        case .recording:    "mic.fill"
        case .transcribing: "waveform"
        case .preparing:    "arrow.down.circle"
        }
    }

    let panel: PanelController
    let waveform: WaveformModel
    let overlay: OverlayModel

    private let hotKey = HotKeyManager()
    private let audio = AudioCaptureEngine()
    private let whisper = WhisperEngine()
    private let fft: FFTProcessor

    private var loadTask: Task<Void, Error>?
    private var vizTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var overlayGeneration = 0   // invalidates stale auto-hide timers

    private init() {
        let barCount = 24
        waveform = WaveformModel(barCount: barCount)
        overlay = OverlayModel()
        fft = FFTProcessor(fftSize: 1024, barCount: barCount, sampleRate: 16_000)
        panel = PanelController(overlay: overlay, waveform: waveform)

        panel.onStop = { [weak self] in self?.toggle() }
    }

    /// Called once from the app delegate after launch.
    func start() {
        hotKey.onPress = {
            Task { @MainActor in DictationController.shared.toggle() }
        }
        hotKey.register(settings.hotKey)
        // Pre-download the model (if missing) and warm it into RAM once present.
        Task { @MainActor in
            if await modelManager.ensureAvailable() { scheduleLoad() }
        }
    }

    func reapplyHotKey() {
        hotKey.register(settings.hotKey)
    }

    /// User switched the model in Settings: drop the loaded one and re-evaluate.
    func modelChanged() {
        loadTask?.cancel()
        loadTask = nil
        isModelLoaded = false
        Task { await whisper.unload() }
        modelManager.selectionChanged()
        Task { @MainActor in
            if await modelManager.ensureAvailable() { scheduleLoad() }
        }
    }

    /// Temporarily drop the global hotkey so its keys reach the recorder.
    func suspendHotKey() {
        hotKey.unregister()
    }

    // MARK: State transitions

    func toggle() {
        switch state {
        case .idle:                     beginRecording()
        case .recording:                endRecording()
        case .transcribing, .preparing: break   // ignore presses while working
        }
    }

    private func beginRecording() {
        guard modelManager.isReady else {
            startModelDownloadFlow()
            return
        }
        overlayGeneration += 1
        state = .recording
        cancelIdleUnload()
        overlay.phase = .recording
        panel.show()

        scheduleLoad()              // record-while-loading: ensure load is in flight

        Task { @MainActor in
            let granted = await Permissions.ensureMicrophone()
            // The user may have stopped/cancelled while we awaited permission.
            guard state == .recording else { return }
            guard granted else {
                state = .idle
                showResult(L.s("No microphone access", "Нет доступа к микрофону", "Fără acces la microfon"), phase: .done)
                return
            }
            do {
                try audio.start()
                startVisualizer()
            } catch {
                state = .idle
                showResult(L.s("Microphone error", "Ошибка микрофона", "Eroare de microfon"), phase: .done)
            }
        }
    }

    private func endRecording() {
        state = .transcribing
        stopVisualizer()
        let samples = audio.stop()

        overlay.phase = .transcribing
        overlay.statusText = L.s("Transcribing…", "Распознаю…", "Transcriere…")

        Task { @MainActor in
            do {
                try await loadTask?.value          // await parallel load if still running
                let text = try await whisper.transcribe(
                    samples: samples,
                    language: settings.language.whisperCode,
                    modelURL: modelManager.modelURL
                )
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    overlay.statusText = L.s("Nothing recognized", "Ничего не распознано", "Nimic recunoscut")
                } else {
                    let result = TextOutput.deliver(trimmed, mode: settings.outputMode, autoReturn: settings.autoReturn)
                    overlay.statusText = statusText(for: result)
                }
            } catch {
                overlay.statusText = L.s("Recognition error", "Ошибка распознавания", "Eroare de recunoaștere")
            }
            overlay.phase = .done
            state = .idle
            scheduleIdleUnload()
            autoHide(after: 1.7)
        }
    }

    /// First-use / model-missing path: show download progress, don't record yet.
    private func startModelDownloadFlow() {
        overlayGeneration += 1
        state = .preparing
        overlay.phase = .preparing
        panel.show()
        Task { @MainActor in
            let ok = await modelManager.ensureAvailable()
            guard state == .preparing else { return }
            state = .idle
            overlay.phase = .done
            overlay.statusText = ok
                ? L.s("Model ready — press again", "Модель готова — нажмите ещё раз", "Model gata — apasă din nou")
                : L.s("Couldn't download the model", "Не удалось скачать модель", "Descărcarea modelului a eșuat")
            autoHide(after: ok ? 2.2 : 3.0)
            if ok { scheduleLoad() }
        }
    }

    private func showResult(_ message: String, phase: OverlayModel.Phase) {
        overlayGeneration += 1
        overlay.phase = phase
        overlay.statusText = message
        panel.show()
        autoHide(after: 1.9)
    }

    private func autoHide(after seconds: Double) {
        let generation = overlayGeneration
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            // Only the latest overlay cycle may hide the panel.
            guard generation == overlayGeneration, state == .idle else { return }
            panel.hide()
        }
    }

    private func statusText(for result: TextOutput.Result) -> String {
        switch result {
        case .copied:
            return L.s("Copied to clipboard", "Скопировано в буфер", "Copiat în clipboard")
        case .pasted:
            return settings.outputMode == .both
                ? L.s("Pasted and copied", "Вставлено и скопировано", "Lipit și copiat")
                : L.s("Pasted", "Вставлено", "Lipit")
        case .needsAccessibility:
            return L.s("Copied · needs Accessibility", "Скопировано · нужен Универсальный доступ", "Copiat · necesită Accesibilitate")
        }
    }

    // MARK: Visualiser

    private func startVisualizer() {
        vizTask?.cancel()
        vizTask = Task { @MainActor in
            while !Task.isCancelled {
                let recent = audio.latestSamples(1024)
                waveform.levels = fft.process(recent)
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func stopVisualizer() {
        vizTask?.cancel()
        vizTask = nil
        waveform.levels = [Float](repeating: 0, count: waveform.levels.count)
    }

    // MARK: Model load / unload

    private func scheduleLoad() {
        guard modelManager.isReady, loadTask == nil else { return }
        let url = modelManager.modelURL
        loadTask = Task {
            try await whisper.load(from: url)
            self.isModelLoaded = true
        }
    }

    private func scheduleIdleUnload() {
        idleTask?.cancel()
        let minutes = settings.idleMinutes
        guard minutes > 0 else { return }
        idleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            guard !Task.isCancelled, state == .idle else { return }
            await whisper.unload()
            isModelLoaded = false
            loadTask = nil
        }
    }

    private func cancelIdleUnload() {
        idleTask?.cancel()
        idleTask = nil
    }
}
