import Foundation

// MARK: - Language

/// Supported UI languages. Adding one = a new case here + a translation
/// table (see `Translations`); call sites never change.
enum Language: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh"

    var id: String { rawValue }

    /// The language's own name, shown un-translated in the picker.
    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }

    /// Primary code from a BCP-47 tag (`zh-Hans-CN` etc.).
    static func match(_ bcp47: String) -> Language? {
        Language(rawValue: String(bcp47.prefix(2)))
    }
}

// MARK: - Translation tables

/// Keyed by the English source text — the key *is* the English copy.
enum Translations {
    /// Language → table. English occupies no slot; keys are English.
    static var tables: [Language: [String: String]] {
        [.chinese: zh]
    }
}

// MARK: - Lookup

/// UI copy: the English text is the lookup key, backed by a translation
/// table instead of `.strings` machinery — SPM has no first-class
/// string-catalog story, and a function call keeps every call site
/// greppable. Not main-actor-bound: error strings produced by nonisolated
/// layers are part of the UI too, and everything read here is thread-safe.
enum L10n {
    /// Test hook: pin the language ("en" / "zh") regardless of everything else.
    nonisolated(unsafe) static var override: String?

    /// The language picked in Settings.
    /// * nil — never chosen, falls back to `defaultLanguage` (Chinese);
    /// * ""  — "Follow System" was chosen explicitly.
    /// nil and "" must stay distinct: the factory default is Chinese, and
    /// following the system is a deliberate user choice.
    static var userPreference: String? {
        get { UserDefaults.standard.string(forKey: "openly.language") }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: "openly.language")
            } else {
                UserDefaults.standard.removeObject(forKey: "openly.language")
            }
        }
    }

    /// Factory default. The app copy is written Chinese-first (the main
    /// window is hardcoded Chinese), so an undecided user gets Chinese —
    /// the system language does not decide for them.
    static let defaultLanguage: Language = .chinese

    /// The language in effect. Resolution order:
    /// override (test pin) > user preference ("" = follow system) > factory default.
    static var current: Language {
        if let override, let pinned = Language.match(override) { return pinned }
        return resolve(preference: userPreference, systemLanguage: detectedSystemLanguage)
    }

    /// Pure resolution: no UserDefaults, no Locale — global state can only
    /// exist once, and tests must not flake against each other.
    static func resolve(preference: String?, systemLanguage: Language) -> Language {
        guard let raw = preference else { return defaultLanguage }
        if let chosen = Language(rawValue: raw) { return chosen }
        return raw.isEmpty ? systemLanguage : defaultLanguage
    }

    /// First recognized system language; factory default otherwise.
    static var detectedSystemLanguage: Language {
        for preferred in Locale.preferredLanguages {
            if let language = Language.match(preferred) { return language }
        }
        return defaultLanguage
    }

    static var isChinese: Bool { current == .chinese }

    /// Table lookup: hit returns the translation; miss (or English) returns
    /// the key itself, so an untranslated string degrades to English —
    /// never to a blank.
    static func text(_ key: String) -> String {
        guard current != .english else { return key }
        return Translations.tables[current]?[key] ?? key
    }

    /// Template lookup with positional fill: `t("Downloading {}%", fraction)`.
    /// Lookup happens before substitution; each language may reword the template.
    static func text(_ template: String, _ args: any CustomStringConvertible...) -> String {
        var translation = text(template)
        for argument in args {
            guard let range = translation.range(of: "{}") else { break }
            translation.replaceSubrange(range, with: argument.description)
        }
        return translation
    }
}

/// Unqualified convenience so call sites read like copy, not like plumbing.
func t(_ key: String) -> String {
    L10n.text(key)
}

func t(_ template: String, _ args: any CustomStringConvertible...) -> String {
    L10n.text(template, args)
}
