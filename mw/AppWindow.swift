//
//  AppWindow.swift
//  mw
//
//  AppKit-managed main window (so it can be opened from AppDelegate at launch).
//  While it's open the app behaves like a regular app (Dock icon); on close it
//  goes back to a menu-bar accessory.
//

import AppKit
import SwiftUI

@MainActor
final class AppWindow: NSObject, NSWindowDelegate {
    static let shared = AppWindow()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: MainWindowView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "mw"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        NSApp.setActivationPolicy(.regular)   // Dock icon + real key window
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a pure menu-bar accessory.
        NSApp.setActivationPolicy(.accessory)
    }
}
