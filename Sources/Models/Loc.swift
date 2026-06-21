import SwiftUI
import Combine

/// Bilingual (FR/EN) localization for L'Horizon, per the Atelier i18n spec.
///
/// - FR-first: French is the fallback (Jac is FR-first, Québécois).
/// - Default to the system language on first launch, then honour an in-app
///   override stored under the shared Atelier key `atelier_lang`, so flipping
///   the language in any Atelier native app carries here.
enum Lang: String, CaseIterable, Identifiable {
    case fr, en
    var id: String { rawValue }
    var label: String { self == .fr ? "FR" : "EN" }
}

@MainActor
final class LocManager: ObservableObject {

    static let shared = LocManager()

    /// Shared Atelier key — mirrors the web apps' `atelier:lang` intent.
    nonisolated static let storageKey = "atelier_lang"

    @Published var lang: Lang {
        didSet {
            guard lang != oldValue else { return }
            UserDefaults.standard.set(lang.rawValue, forKey: Self.storageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        if let raw = defaults.string(forKey: Self.storageKey), let saved = Lang(rawValue: raw) {
            lang = saved
        } else {
            lang = Self.systemDefault
        }
    }

    /// System language on first run, FR fallback.
    static var systemDefault: Lang {
        let pref = Locale.preferredLanguages.first?.lowercased() ?? "fr"
        return pref.hasPrefix("en") ? .en : .fr
    }

    func t(_ fr: String, _ en: String) -> String { lang == .fr ? fr : en }

    func toggle() { lang = (lang == .fr) ? .en : .fr }
}

/// Free helper for use anywhere (models, static data, views).
@MainActor
func t(_ fr: String, _ en: String) -> String {
    LocManager.shared.t(fr, en)
}
