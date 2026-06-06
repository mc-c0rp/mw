//
//  mwApp.swift
//  mw
//
//  Menu-bar accessory app (no Dock icon). The dictation overlay lives in its
//  own floating panel; the main settings window uses tabs.
//

import SwiftUI

@main
struct mwApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = DictationController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .accessibilityLabel("mw — диктовка голосом")
        }

        Window("mw", id: WindowID.main) {
            MainWindowView()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

enum WindowID {
    static let main = "main"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Single instance: a freshly launched copy replaces any older one that's
        // still running, so two instances never run at the same time.
        let current = NSRunningApplication.current
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != current.processIdentifier }
        for app in others { app.terminate() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DictationController.shared.start()
    }
}

private struct MenuContent: View {
    @Bindable var controller: DictationController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(controller.isRecording
               ? L.s("Stop recording", "Остановить запись", "Oprește înregistrarea")
               : L.s("Start recording", "Начать запись", "Începe înregistrarea")) {
            controller.toggle()
        }
        .keyboardShortcut("r")

        Text(controller.modelManager.statusLine)

        Divider()

        Button(L.s("Open mw…", "Открыть mw…", "Deschide mw…")) {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            openWindow(id: WindowID.main)
        }
        .keyboardShortcut(",")

        Button(L.s("Quit", "Выход", "Ieșire")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
