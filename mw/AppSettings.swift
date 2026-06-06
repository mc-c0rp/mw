//
//  AppSettings.swift
//  mw
//
//  Persisted user preferences (UserDefaults-backed, observable).
//

import Foundation
import Observation

/// What to do with the recognised text.
enum OutputMode: String, CaseIterable, Identifiable, Codable {
    case clipboard
    case type
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clipboard: "Копировать в буфер"
        case .type:      "Печатать на клавиатуре"
        case .both:      "И то, и другое"
        }
    }

    /// Short status shown in the overlay after a successful run.
    var confirmationText: String {
        switch self {
        case .clipboard: "Скопировано в буфер"
        case .type:      "Вставлено"
        case .both:      "Вставлено и скопировано"
        }
    }

    var needsAccessibility: Bool { self != .clipboard }
}

/// Transcription language. `auto` lets Whisper detect per utterance.
enum TranscriptionLanguage: String, CaseIterable, Identifiable, Codable {
    case auto
    case ru
    case ro
    case en

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Авто"
        case .ru:   "Русский"
        case .ro:   "Română"
        case .en:   "English"
        }
    }

    /// Code passed to whisper.cpp (`whisper_full_params.language`).
    var whisperCode: String { rawValue }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var outputMode: OutputMode {
        didSet { defaults.set(outputMode.rawValue, forKey: Keys.outputMode) }
    }

    var language: TranscriptionLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    /// Minutes of inactivity after which the model is unloaded from RAM. `0` = never.
    var idleMinutes: Int {
        didSet { defaults.set(idleMinutes, forKey: Keys.idleMinutes) }
    }

    var hotKey: HotKeyCombo {
        didSet {
            if let data = try? JSONEncoder().encode(hotKey) {
                defaults.set(data, forKey: Keys.hotKey)
            }
        }
    }

    /// Press Return after inserting the text (only with auto-paste/type modes).
    var autoReturn: Bool {
        didSet { defaults.set(autoReturn, forKey: Keys.autoReturn) }
    }

    /// Which whisper model to use (downloaded on demand).
    var model: WhisperModel {
        didSet { defaults.set(model.rawValue, forKey: Keys.model) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let outputMode = "outputMode"
        static let language = "language"
        static let idleMinutes = "idleMinutes"
        static let hotKey = "hotKey"
        static let autoReturn = "autoReturn"
        static let model = "model"
    }

    private init() {
        outputMode = OutputMode(rawValue: defaults.string(forKey: Keys.outputMode) ?? "") ?? .clipboard
        language = TranscriptionLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .auto
        idleMinutes = defaults.object(forKey: Keys.idleMinutes) as? Int ?? 10

        if let data = defaults.data(forKey: Keys.hotKey),
           let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data) {
            hotKey = combo
        } else {
            hotKey = .defaultCombo
        }

        autoReturn = defaults.bool(forKey: Keys.autoReturn)
        model = WhisperModel(rawValue: defaults.string(forKey: Keys.model) ?? "") ?? .turbo
    }
}
