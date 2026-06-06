//
//  FFTProcessor.swift
//  mw
//
//  Turns a window of PCM samples into N normalised bar levels (0...1) for the
//  capsule visualiser, using Accelerate vDSP. Used on the main actor only.
//

import Accelerate
import Foundation

nonisolated final class FFTProcessor {
    let barCount: Int

    private let n: Int
    private let halfN: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private let sampleRate: Float
    private let bandRanges: [(lo: Int, hi: Int)]
    private var smoothed: [Float]

    init(fftSize: Int = 1024, barCount: Int = 24, sampleRate: Float = 16_000) {
        self.n = fftSize
        self.halfN = fftSize / 2
        self.barCount = barCount
        self.sampleRate = sampleRate
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.window = vDSP.window(ofType: Float.self,
                                  usingSequence: .hanningDenormalized,
                                  count: fftSize,
                                  isHalfWindow: false)
        self.smoothed = [Float](repeating: 0, count: barCount)

        // Pre-compute log-spaced frequency bands (80 Hz … 8 kHz) mapped to FFT bins.
        let minHz: Float = 80
        let maxHz: Float = 8_000
        let binHz = sampleRate / Float(fftSize)
        var ranges: [(Int, Int)] = []
        for b in 0..<barCount {
            let f0 = minHz * pow(maxHz / minHz, Float(b) / Float(barCount))
            let f1 = minHz * pow(maxHz / minHz, Float(b + 1) / Float(barCount))
            let lo = max(1, Int(f0 / binHz))
            let hi = min(halfN - 1, max(lo, Int(f1 / binHz)))
            ranges.append((lo, hi))
        }
        self.bandRanges = ranges
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Returns `barCount` smoothed levels in 0...1. Pass the most recent samples;
    /// the last `n` are used (zero-padded if fewer).
    func process(_ samplesIn: [Float]) -> [Float] {
        guard !samplesIn.isEmpty else {
            decay()
            return smoothed
        }

        // Windowed input of length n (use the most recent samples).
        var input = [Float](repeating: 0, count: n)
        let count = min(samplesIn.count, n)
        let start = samplesIn.count - count
        for i in 0..<count { input[i] = samplesIn[start + i] }

        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(input, 1, window, 1, &windowed, 1, vDSP_Length(n))

        var realp = [Float](repeating: 0, count: halfN)
        var imagp = [Float](repeating: 0, count: halfN)
        var magnitudes = [Float](repeating: 0, count: halfN)

        realp.withUnsafeMutableBufferPointer { realBuf in
            imagp.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!,
                                            imagp: imagBuf.baseAddress!)
                windowed.withUnsafeBufferPointer { wptr in
                    wptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { cptr in
                        vDSP_ctoz(cptr, 2, &split, 1, vDSP_Length(halfN))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        var bars = [Float](repeating: 0, count: barCount)
        for b in 0..<barCount {
            let (lo, hi) = bandRanges[b]
            var sum: Float = 0
            for i in lo...hi { sum += magnitudes[i] }
            let avg = sum / Float(hi - lo + 1)
            let db = 10 * log10(avg + 1e-9)
            let level = min(max((db + 60) / 60, 0), 1)

            // Fast attack, slow release for a pleasing capsule motion.
            let prev = smoothed[b]
            let coeff: Float = level > prev ? 0.5 : 0.15
            smoothed[b] = prev + (level - prev) * coeff
            bars[b] = smoothed[b]
        }
        return bars
    }

    /// Gradually relax all bars toward zero (called when there is no audio).
    private func decay() {
        for b in 0..<barCount { smoothed[b] *= 0.6 }
    }
}
