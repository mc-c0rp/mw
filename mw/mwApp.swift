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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DictationController.shared.start()
    }
}

private struct MenuContent: View {
    @Bindable var controller: DictationController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(controller.isRecording ? "Остановить запись" : "Начать запись") {
            controller.toggle()
        }
        .keyboardShortcut("r")

        Text(controller.modelManager.statusLine)

        Divider()

        Button("Открыть mw…") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            openWindow(id: WindowID.main)
        }
        .keyboardShortcut(",")

        Button("Выход") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
