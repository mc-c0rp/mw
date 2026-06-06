//
//  AudioCaptureEngine.swift
//  mw
//
//  Microphone capture via AVAudioEngine. Resamples to 16 kHz mono Float32
//  (the format whisper.cpp expects) and accumulates the whole utterance.
//  The tap runs on a real-time thread; all shared state is lock-guarded.
//

@preconcurrency import AVFoundation
import Foundation

/// Feeds a single PCM buffer to AVAudioConverter exactly once. @unchecked
/// Sendable because the converter's input block runs synchronously inline.
private nonisolated final class ConverterFeed: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var fed = false

    init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
        if fed {
            status.pointee = .noDataNow
            return nil
        }
        fed = true
        status.pointee = .haveData
        return buffer
    }
}

enum AudioError: LocalizedError {
    case noInput
    case engineFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInput:              "Микрофон недоступен."
        case .engineFailed(let m):  "Ошибка аудио: \(m)"
        }
    }
}

nonisolated final class AudioCaptureEngine: @unchecked Sendable {
    /// Hard cap on retained audio (seconds) to bound memory on very long takes.
    var maxSeconds = 600

    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var running = false

    init() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    /// Starts capture. Call only after microphone permission has been granted.
    func start() throws {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(16_000 * 60)
        lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioError.noInput
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioError.engineFailed("не удалось создать конвертер")
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioError.engineFailed(error.localizedDescription)
        }
        running = true
    }

    /// Stops capture and returns the full 16 kHz mono buffer.
    @discardableResult
    func stop() -> [Float] {
        if running {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            running = false
        }
        return snapshot()
    }

    /// Thread-safe copy of the most recent `n` samples (for the visualiser).
    func latestSamples(_ n: Int) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        if samples.count <= n { return samples }
        return Array(samples[(samples.count - n)...])
    }

    private func snapshot() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return
        }

        // The input block is @Sendable but the converter invokes it synchronously
        // here; a small box keeps the "fed once" state without a captured-var warning.
        let feed = ConverterFeed(buffer: buffer)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            feed.next(inputStatus)
        }
        guard status != .error, let channel = output.floatChannelData else { return }

        let frames = Int(output.frameLength)
        guard frames > 0 else { return }

        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: frames))
        let maxCount = 16_000 * maxSeconds
        if samples.count > maxCount {
            samples.removeFirst(samples.count - maxCount)
        }
        lock.unlock()
    }

    private func handleConfigurationChange() {
        guard running else { return }
        let input = engine.inputNode

        // Read the new format BEFORE tearing down the tap — during a device
        // switch it can transiently report 0 Hz, and we must not kill capture.
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { return }

        input.removeTap(onBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        if !engine.isRunning {
            try? engine.start()
        }
    }
}
