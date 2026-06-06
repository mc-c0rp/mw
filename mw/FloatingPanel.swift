//
//  FloatingPanel.swift
//  mw
//
//  A borderless, translucent, always-on-top panel that never becomes key, so
//  the user's previously focused app keeps focus and receives the paste.
//

import AppKit
import SwiftUI

/// Hosting view for the overlay. Transparent areas fall through to the apps
/// behind (via SwiftUI hit-testing + `Color.clear.allowsHitTesting(false)`),
/// while the capsule's controls stay clickable even though the panel never
/// activates the app — `acceptsFirstMouse` delivers the very first click.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Non-activating floating panel for the overlay capsule.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        animationBehavior = .none
    }

    // May become key (so the stop button reliably receives clicks), but never
    // main and — being a non-activating panel — never activates the app, so the
    // user's frontmost app keeps keyboard focus and receives the paste.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the overlay panel: builds it lazily, positions it bottom-centre,
/// and animates show / hide.
@MainActor
final class PanelController {
    let overlay: OverlayModel
    let waveform: WaveformModel

    /// Called when the in-overlay stop button is tapped.
    var onStop: () -> Void = {}

    private var panel: FloatingPanel?
    private let panelSize = NSSize(width: 560, height: 160)

    init(overlay: OverlayModel, waveform: WaveformModel) {
        self.overlay = overlay
        self.waveform = waveform
    }

    func show() {
        ensurePanel()
        reposition()
        panel?.orderFrontRegardless()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            overlay.visible = true
        }
    }

    func hide() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
            overlay.visible = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(480))
            if overlay.visible == false {
                panel?.orderOut(nil)
            }
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let frame = NSRect(origin: .zero, size: panelSize)
        let panel = FloatingPanel(contentRect: frame)

        let root = OverlayRootView(
            overlay: overlay,
            waveform: waveform,
            onStop: { [weak self] in self?.onStop() }
        )
        let hosting = PassthroughHostingView(rootView: root)
        hosting.frame = frame
        hosting.autoresizingMask = [.width, .height]
        // Let clicks on the transparent areas fall through where possible.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear

        panel.contentView = hosting
        self.panel = panel
    }

    private func reposition() {
        guard let panel, let screen = activeScreen() else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - panelSize.width / 2
        let y = visible.minY + 28
        panel.setFrame(NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height),
                       display: false)
    }

    /// The screen the user is actually working on (where the cursor is).
    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}

/// Live `NSVisualEffectView` blur, kept active even when the window isn't key —
/// this is what gives the capsule its reliable frosted-glass look.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active           // stay vibrant even when panel is not key
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}
