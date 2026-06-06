//
//  Permissions.swift
//  mw
//
//  Microphone (TCC) and Accessibility (PostEvent) permission helpers.
//

import AVFoundation
import ApplicationServices
import CoreGraphics

enum Permissions {
    // MARK: Microphone

    static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static var microphoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Returns true if the microphone may be used (prompts on first call).
    static func ensureMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    // MARK: Accessibility (needed only for auto-type / paste)

    /// True if the app may post synthetic keyboard events.
    static var canPostEvents: Bool {
        CGPreflightPostEventAccess()
    }

    @MainActor
    static var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Opens System Settings → Accessibility and asks the user to grant access.
    @MainActor
    static func promptAccessibility() {
        // Key value of kAXTrustedCheckOptionPrompt (imported global var isn't
        // concurrency-safe under Swift 6).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        // Also nudge the CG side (separate prompt on some systems).
        if !CGPreflightPostEventAccess() {
            CGRequestPostEventAccess()
        }
    }
}
