//
//  TextOutput.swift
//  mw
//
//  Delivers recognised text: clipboard, auto-paste, or both.
//  Auto-paste posts a synthetic ⌘V (requires Accessibility / PostEvent access).
//

import AppKit
import Carbon.HIToolbox

enum TextOutput {
    /// What actually happened, so the UI can report the truth.
    enum Result {
        case copied               // placed on the clipboard only
        case pasted               // pasted into the active app
        case needsAccessibility   // wanted to paste but no permission — left on clipboard
    }

    @MainActor
    static func deliver(_ text: String, mode: OutputMode, autoReturn: Bool) -> Result {
        let pasteboard = NSPasteboard.general

        switch mode {
        case .clipboard:
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copied

        case .both:
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            guard Permissions.canPostEvents else {
                Permissions.promptAccessibility()
                return .needsAccessibility   // still on the clipboard
            }
            pasteAfterDelay(restore: nil, pressReturn: autoReturn)
            return .pasted

        case .type:
            guard Permissions.canPostEvents else {
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                Permissions.promptAccessibility()
                return .needsAccessibility
            }
            let saved = snapshot(pasteboard)        // preserve ALL clipboard content
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            pasteAfterDelay(restore: saved, pressReturn: autoReturn)
            return .pasted
        }
    }

    // MARK: Clipboard snapshot / restore (handles images, files, etc.)

    @MainActor
    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    // MARK: Paste

    @MainActor
    private static func pasteAfterDelay(restore saved: [NSPasteboardItem]?, pressReturn: Bool) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            postCommandV()
            if pressReturn {
                try? await Task.sleep(for: .milliseconds(90))
                postReturn()
            }
            if let saved {
                try? await Task.sleep(for: .milliseconds(500))
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                if !saved.isEmpty {
                    pasteboard.writeObjects(saved)
                }
            }
        }
    }

    @MainActor
    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        let tap: CGEventTapLocation = .cgSessionEventTap

        if let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true) {
            down.flags = .maskCommand          // exact flags — ignore any held modifiers
            down.post(tap: tap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) {
            up.flags = .maskCommand
            up.post(tap: tap)
        }
    }

    @MainActor
    private static func postReturn() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_Return)
        let tap: CGEventTapLocation = .cgSessionEventTap

        if let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true) {
            down.post(tap: tap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
            up.post(tap: tap)
        }
    }
}
