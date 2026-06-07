//
//  mwApp.swift
//  mw
//
//  Menu-bar accessory app (no Dock icon by default). The dictation overlay lives
//  in its own floating panel; the main window is AppKit-managed (AppWindow).
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
                .accessibilityLabel(L.s("mw — voice dictation", "mw — диктовка голосом", "mw — dictare vocală"))
        }
    }
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

        // First launch (model not downloaded yet): open the window so the user
        // can see the model downloading. Deferred so SwiftUI scene setup doesn't
        // reset the activation policy afterwards.
        if !DictationController.shared.modelManager.isReady {
            DispatchQueue.main.async {
                AppWindow.shared.show()
            }
        }
    }
}

private struct MenuContent: View {
    @Bindable var controller: DictationController

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
            AppWindow.shared.show()
        }
        .keyboardShortcut(",")

        Button(L.s("Quit", "Выход", "Ieșire")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
