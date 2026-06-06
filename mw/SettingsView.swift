//
//  SettingsView.swift
//  mw
//
//  Main app window — everything organised into tabs. This window can become
//  key, so it uses real Liquid Glass. Strings are localized via L.s(en, ru, ro).
//

import SwiftUI
import AppKit

struct MainWindowView: View {
    var body: some View {
        TabView {
            Tab(L.s("General", "Основное", "General"), systemImage: "slider.horizontal.3") {
                GeneralTab()
            }
            Tab(L.s("Access", "Доступ", "Acces"), systemImage: "lock.shield") {
                PermissionsTab()
            }
            Tab(L.s("About", "О программе", "Despre"), systemImage: "info.circle") {
                AboutTab()
            }
        }
        .frame(width: 540, height: 520)
        .background(BackgroundGradient())
        .preferredColorScheme(.dark)
        .tint(.white)
        .onAppear {
            // While the window is open, behave like a normal app: a Dock icon
            // and a real key window (so it can't get lost and the hotkey
            // recorder receives key events).
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            // Back to a pure menu-bar accessory when the window closes.
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - Tabs

private struct GeneralTab: View {
    @State private var store = AppSettings.shared
    @State private var controller = DictationController.shared
    @State private var launchAtLogin = false

    var body: some View {
        @Bindable var settings = store

        TabScaffold {
            GlassCard {
                SettingsRow(L.s("Text output", "Вывод текста", "Ieșire text")) {
                    Picker("", selection: $settings.outputMode) {
                        ForEach(OutputMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                rowDivider

                SettingsRow(L.s("Speech language", "Язык распознавания", "Limba vorbirii")) {
                    Picker("", selection: $settings.language) {
                        ForEach(TranscriptionLanguage.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                if settings.outputMode != .clipboard {
                    rowDivider
                    SettingsRow(L.s("Return after paste", "Enter после вставки", "Enter după lipire")) {
                        Toggle("", isOn: $settings.autoReturn)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }

            GlassCard {
                SettingsRow(L.s("Recognition model", "Модель распознавания", "Model de recunoaștere")) {
                    Picker("", selection: $settings.model) {
                        ForEach(WhisperModel.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                captionText(L.modelDetail(settings.model))
                rowDivider
                SettingsRow(settings.model.sizeText) {
                    ModelDownloadControl()
                }
            }

            GlassCard {
                SettingsRow(L.s("Hotkey", "Горячая клавиша", "Tastă rapidă")) {
                    HotKeyRecorder(combo: settings.hotKey) { newCombo in
                        settings.hotKey = newCombo
                        controller.reapplyHotKey()
                    }
                }
                captionText(L.s(
                    "Press and set a comfortable combo. The same key starts and stops.",
                    "Нажмите и задайте удобное сочетание. Старт и стоп — одной и той же клавишей.",
                    "Apasă și setează o combinație. Aceeași tastă pornește și oprește."))
            }

            GlassCard {
                SettingsRow(L.s("Unload model from memory", "Выгружать модель из памяти", "Descarcă modelul din memorie")) {
                    Picker("", selection: $settings.idleMinutes) {
                        Text(L.s("Never", "Никогда", "Niciodată")).tag(0)
                        Text(L.s("After 5 min", "Через 5 минут", "După 5 min")).tag(5)
                        Text(L.s("After 10 min", "Через 10 минут", "După 10 min")).tag(10)
                        Text(L.s("After 15 min", "Через 15 минут", "După 15 min")).tag(15)
                        Text(L.s("After 30 min", "Через 30 минут", "După 30 min")).tag(30)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                captionText(L.s(
                    "If unloaded, recording starts instantly while the model loads in parallel.",
                    "Если выгружена — при нажатии хоткея запись стартует сразу, а модель грузится параллельно.",
                    "Dacă e descărcat, înregistrarea pornește imediat, iar modelul se încarcă în paralel."))
            }

            GlassCard {
                SettingsRow(L.s("Interface language", "Язык интерфейса", "Limba interfeței")) {
                    Picker("", selection: $settings.uiLanguage) {
                        ForEach(UILanguage.allCases) { Text(L.languageName($0)).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                rowDivider

                SettingsRow(L.s("Launch at login", "Запуск при входе в систему", "Pornire la autentificare")) {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
        .onAppear { launchAtLogin = LoginItem.isEnabled }
        .onChange(of: launchAtLogin) { _, newValue in
            if !LoginItem.setEnabled(newValue) {
                launchAtLogin = LoginItem.isEnabled   // revert if the system rejected it
            }
        }
        .onChange(of: store.model) { _, _ in
            controller.modelChanged()
        }
    }
}

/// Per-model download status: ready badge, live %, or a download button.
private struct ModelDownloadControl: View {
    @State private var manager = ModelManager.shared

    var body: some View {
        switch manager.state {
        case .ready:
            StatusBadge(ok: true, text: L.s("Downloaded", "Загружена", "Descărcat"))
        case .downloading(let progress):
            Text("\(Int(progress * 100))%")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        case .missing, .failed:
            Button(L.s("Download", "Скачать", "Descarcă")) {
                Task { await manager.ensureAvailable() }
            }
            .buttonStyle(.glass)
        }
    }
}

private struct PermissionsTab: View {
    @State private var micGranted = false
    @State private var axGranted = false

    var body: some View {
        TabScaffold {
            GlassCard {
                SettingsRow(L.s("Microphone", "Микрофон", "Microfon")) {
                    if micGranted {
                        StatusBadge(ok: true, text: L.s("Granted", "Выдан", "Acordat"))
                    } else {
                        Button(L.s("Request", "Запросить", "Solicită")) {
                            Task {
                                _ = await Permissions.ensureMicrophone()
                                refresh()
                            }
                        }
                        .buttonStyle(.glass)
                    }
                }
                captionText(L.s("Needed to record your voice.", "Нужен для записи речи с микрофона.", "Necesar pentru a înregistra vocea."))
            }

            GlassCard {
                SettingsRow(L.s("Accessibility", "Универсальный доступ", "Accesibilitate")) {
                    if axGranted {
                        StatusBadge(ok: true, text: L.s("Granted", "Выдан", "Acordat"))
                    } else {
                        Button(L.s("Open Settings", "Открыть настройки", "Deschide Setări")) {
                            Permissions.promptAccessibility()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refresh() }
                        }
                        .buttonStyle(.glass)
                    }
                }
                captionText(L.s(
                    "Only for auto-paste (⌘V) and typing. Not needed for clipboard-only mode.",
                    "Нужен только для авто-вставки (⌘V) и печати на клавиатуре. Для режима «Копировать в буфер» не требуется.",
                    "Doar pentru auto-lipire (⌘V) și tastare. Nu e necesar pentru modul „doar clipboard”."))
            }

            Spacer(minLength: 0)
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        micGranted = Permissions.microphoneAuthorized
        axGranted = Permissions.accessibilityTrusted
    }
}

private struct AboutTab: View {
    @State private var controller = DictationController.shared

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        TabScaffold {
            GlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 26, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("mw").font(.system(size: 22, weight: .bold))
                        Text(L.s("Local voice dictation", "Локальная диктовка голосом", "Dictare vocală locală"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            GlassCard {
                SettingsRow(L.s("Model", "Модель", "Model")) {
                    Text(controller.modelManager.selected.displayName)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                rowDivider
                SettingsRow(L.s("State", "Состояние", "Stare")) {
                    StatusBadge(ok: controller.isModelLoaded,
                                text: controller.isModelLoaded
                                    ? L.s("In memory", "В памяти", "În memorie")
                                    : L.s("Unloaded", "Выгружена", "Descărcat"))
                }
                rowDivider
                SettingsRow(L.s("Version", "Версия", "Versiune")) {
                    Text(version).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
            }

            captionText(L.s(
                "Recognition runs fully on-device (Metal). Nothing leaves your Mac.",
                "Распознавание выполняется полностью на устройстве (Metal). Ничего не уходит в сеть.",
                "Recunoașterea rulează complet pe dispozitiv (Metal). Nimic nu pleacă de pe Mac."))

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shared building blocks

private struct TabScaffold<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    content
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(BackgroundGradient())
    }
}

private struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            trailing
        }
    }
}

private struct StatusBadge: View {
    let ok: Bool
    let text: String

    var body: some View {
        Label(text, systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(ok ? .green : .orange)
    }
}

private struct BackgroundGradient: View {
    var body: some View {
        LinearGradient(
            colors: [Color(white: 0.09), Color(white: 0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private var rowDivider: some View {
    Divider().opacity(0.14)
}

@ViewBuilder
private func captionText(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
}

// MARK: - Hotkey recorder

struct HotKeyRecorder: View {
    var combo: HotKeyCombo
    var onChange: (HotKeyCombo) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    private let escapeKeyCode: UInt16 = 53   // kVK_Escape

    var body: some View {
        Button {
            recording ? cancel() : start()
        } label: {
            Text(recording ? L.s("Press a combo…", "Нажмите сочетание…", "Apasă o combinație…") : combo.displayString)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(minWidth: 130)
        }
        .buttonStyle(.glass)
        .onDisappear { cancel() }
    }

    private func start() {
        recording = true
        // Drop the global hotkey so its keys reach this local monitor.
        DictationController.shared.suspendHotKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == escapeKeyCode {        // Esc cancels
                cancel()
                return nil
            }
            let mods = HotKeyCombo.carbonModifiers(from: event.modifierFlags)
            let candidate = HotKeyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: mods)
            guard candidate.isValid else { return event }   // need a real combo

            removeMonitor()
            recording = false
            onChange(candidate)                        // persists + registers the new hotkey
            return nil
        }
    }

    /// Stop recording without changing the hotkey; restore the existing one.
    private func cancel() {
        guard recording else { return }
        removeMonitor()
        recording = false
        DictationController.shared.reapplyHotKey()
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
