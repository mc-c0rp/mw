//
//  Localization.swift
//  mw
//
//  Lightweight in-app localization with live switching. Every user-facing string
//  is resolved via L.s(en, ru, ro) against the chosen interface language, so the
//  whole UI (and the menu bar / overlay) updates instantly when it changes.
//

import Foundation

enum UILanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case en
    case ru
    case ro

    var id: String { rawValue }
}

@MainActor
enum L {
    /// The active language (`.system` resolved to en/ru/ro).
    static var current: UILanguage { AppSettings.shared.effectiveLanguage }

    /// Pick the variant for the active UI language.
    static func s(_ en: String, _ ru: String, _ ro: String) -> String {
        switch current {
        case .ru: return ru
        case .ro: return ro
        default:  return en
        }
    }

    /// Display name for the language picker.
    static func languageName(_ language: UILanguage) -> String {
        switch language {
        case .system: return s("System", "Системный", "Sistem")
        case .en:     return "English"
        case .ru:     return "Русский"
        case .ro:     return "Română"
        }
    }

    static func modelDetail(_ model: WhisperModel) -> String {
        switch model {
        case .turbo:
            return s("Faster, lower RAM (~0.7–1 GB). Great accuracy for ru/ro/en dictation. Recommended.",
                     "Быстрее, меньше RAM (~0.7–1 ГБ). Отличная точность для диктовки ru/ro/en. Рекомендуется.",
                     "Mai rapid, mai puțină RAM (~0.7–1 GB). Precizie excelentă pentru dictare ru/ro/en. Recomandat.")
        case .full:
            return s("Maximum accuracy (hard speech, accents, code-switching), but slower and more RAM (~1.5–2 GB).",
                     "Максимальная точность (сложная речь, акценты, code-switching), но медленнее и больше RAM (~1.5–2 ГБ).",
                     "Precizie maximă (vorbire dificilă, accente, code-switching), dar mai lent și mai multă RAM (~1.5–2 GB).")
        }
    }
}
