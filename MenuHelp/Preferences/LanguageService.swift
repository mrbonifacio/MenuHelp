import AppKit
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case portugueseBrazil
    case english

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .system:
            return String(localized: "Automático (idioma do Mac)")
        case .portugueseBrazil:
            return String(localized: "Português (Brasil)")
        case .english:
            return String(localized: "Inglês")
        }
    }

    fileprivate var appleLanguageCode: String? {
        switch self {
        case .system:
            return nil
        case .portugueseBrazil:
            return "pt-BR"
        case .english:
            return "en"
        }
    }
}

@MainActor
final class LanguageService: ObservableObject {
    static let shared = LanguageService()

    @Published private(set) var selectedLanguage: AppLanguage

    private let defaults = UserDefaults.standard
    private let selectionKey = "menuHelp.appLanguage"

    private init() {
        selectedLanguage = AppLanguage(
            rawValue: defaults.string(forKey: selectionKey) ?? ""
        ) ?? .system
    }

    @discardableResult
    func setLanguage(_ language: AppLanguage) -> Bool {
        guard language != selectedLanguage else { return false }

        selectedLanguage = language
        defaults.set(language.rawValue, forKey: selectionKey)

        if let languageCode = language.appleLanguageCode {
            defaults.set([languageCode], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }

        return true
    }

    func restartApplication() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundleURL.path]

        do {
            try process.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.terminate(nil)
            }
        } catch {
            NSSound.beep()
        }
    }
}
