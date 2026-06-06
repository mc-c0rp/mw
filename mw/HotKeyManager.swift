//
//  HotKeyManager.swift
//  mw
//
//  Global system-wide hotkey via Carbon RegisterEventHotKey.
//  Works in the background and needs NO Accessibility/Input-Monitoring permission.
//

import AppKit
import Carbon.HIToolbox

/// A hotkey combination: a virtual key code plus Carbon modifier mask.
struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32          // virtual key code (e.g. kVK_Space)
    var carbonModifiers: UInt32  // controlKey | optionKey | cmdKey | shiftKey

    /// Default: ⌃⌥Space (Ctrl+Option+Space) — almost always free on macOS.
    static let defaultCombo = HotKeyCombo(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(controlKey | optionKey)
    )

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }

    /// Human-readable form, e.g. "⌃⌥Space".
    var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    /// At least one modifier, OR a function key — otherwise the hotkey would
    /// fire on every plain keypress.
    var isValid: Bool {
        if carbonModifiers != 0 { return true }
        return Self.functionKeyCodes.contains(keyCode)
    }

    private static let functionKeyCodes: Set<UInt32> = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
        UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
        UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
    ]

    static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_ANSI_A: return "A"; case kVK_ANSI_B: return "B"; case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"; case kVK_ANSI_E: return "E"; case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"; case kVK_ANSI_H: return "H"; case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"; case kVK_ANSI_K: return "K"; case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"; case kVK_ANSI_N: return "N"; case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"; case kVK_ANSI_Q: return "Q"; case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"; case kVK_ANSI_T: return "T"; case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"; case kVK_ANSI_W: return "W"; case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"; case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"; case kVK_ANSI_1: return "1"; case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"; case kVK_ANSI_4: return "4"; case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"; case kVK_ANSI_7: return "7"; case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_F1: return "F1"; case kVK_F2: return "F2"; case kVK_F3: return "F3"
        case kVK_F4: return "F4"; case kVK_F5: return "F5"; case kVK_F6: return "F6"
        case kVK_F7: return "F7"; case kVK_F8: return "F8"; case kVK_F9: return "F9"
        case kVK_F10: return "F10"; case kVK_F11: return "F11"; case kVK_F12: return "F12"
        default: return "Key \(keyCode)"
        }
    }
}

/// Registers a single global hotkey and invokes `onPress` (off any actor) on each press.
nonisolated final class HotKeyManager {
    /// Called on the main run loop each time the hotkey is pressed.
    var onPress: (@Sendable () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private static let signature: OSType = 0x6D772020 // 'mw  '

    func register(_ combo: HotKeyCombo) {
        unregister()

        // Install the Carbon event handler once per registration.
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onPress?()
                return noErr
            },
            1, &eventType, selfPtr, &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit { unregister() }
}
