//
//  OverlayView.swift
//  mw
//
//  The Liquid-Glass-styled capsule overlay and its visual states.
//

import SwiftUI
import Observation

// MARK: - View models

@MainActor
@Observable
final class OverlayModel {
    enum Phase: Equatable {
        case recording
        case transcribing
        case done
        case preparing      // downloading the model
    }

    var visible = false
    var phase: Phase = .recording
    var statusText: String = ""
}

@MainActor
@Observable
final class WaveformModel {
    var levels: [Float]

    init(barCount: Int) {
        levels = [Float](repeating: 0, count: barCount)
    }
}

// MARK: - Root

struct OverlayRootView: View {
    @Bindable var overlay: OverlayModel
    var waveform: WaveformModel
    var onStop: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear.allowsHitTesting(false)
            if overlay.visible {
                CapsuleContent(overlay: overlay, waveform: waveform, onStop: onStop)
                    .padding(.bottom, 6)
                    .transition(
                        .move(edge: .bottom)
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.9, anchor: .bottom))
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .preferredColorScheme(.dark)
        .tint(.white)
    }
}

// MARK: - Capsule

private struct CapsuleContent: View {
    var overlay: OverlayModel
    var waveform: WaveformModel
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            switch overlay.phase {
            case .recording:
                WaveformView(levels: waveform.levels)
                StopButton(action: onStop)

            case .transcribing:
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text(overlay.statusText)
                    .font(.system(size: 14, weight: .medium))

            case .preparing:
                ProgressView(value: ModelManager.shared.downloadFraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(.white)
                Text(ModelManager.shared.statusLine)
                    .font(.system(size: 14, weight: .medium))

            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(overlay.statusText)
                    .font(.system(size: 14, weight: .medium))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .frame(minHeight: 58)
        .background {
            VisualEffectBackground(material: .hudWindow)
                .overlay(Color.black.opacity(0.38))
        }
        .clipShape(.capsule)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 26, y: 12)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: overlay.phase)
        .fixedSize()
    }
}

// MARK: - Waveform

struct WaveformView: View {
    var levels: [Float]

    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 3
    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 30

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(.white)
                    .frame(width: barWidth, height: height(for: levels[index]))
            }
        }
        .frame(height: maxHeight)
        .animation(.linear(duration: 0.06), value: levels)
    }

    private func height(for level: Float) -> CGFloat {
        let clamped = CGFloat(max(0, min(1, level)))
        return minHeight + (maxHeight - minHeight) * clamped
    }
}

// MARK: - Stop button

struct StopButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 30, height: 30)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.black)
                    .frame(width: 11, height: 11)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help(L.s("Stop and transcribe", "Остановить и распознать", "Oprește și transcrie"))
    }
}
