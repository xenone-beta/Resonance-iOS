import SwiftUI

enum ThemeMode: Int, CaseIterable, Identifiable {
    case system, light, dark, amoled
    var id: Int { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .amoled: return "Black (AMOLED)"
        }
    }
}

/// User preferences, stored in UserDefaults.
final class Settings: ObservableObject {
    static let accentSeeds: [UInt32] = [
        0x4F6BD8, 0x16897B, 0x4C9A2A, 0xD9A400, 0xE8742C, 0xD2455A, 0xC2509B, 0x8A5BD1,
    ]
    static let languages: [(tag: String, name: String)] = [("en", "English"), ("ru", "Русский")]

    private let d = UserDefaults.standard

    @Published var themeMode: ThemeMode { didSet { d.set(themeMode.rawValue, forKey: "theme") } }
    @Published var accent: UInt32 { didSet { d.set(Int(accent), forKey: "accent") } }
    @Published var coverColors: Bool { didSet { d.set(coverColors, forKey: "coverColors") } }
    @Published var playerGradient: Bool { didSet { d.set(playerGradient, forKey: "gradient") } }
    @Published var visualizer: Bool { didSet { d.set(visualizer, forKey: "visualizer") } }
    @Published var wavySeek: Bool { didSet { d.set(wavySeek, forKey: "wavySeek") } }
    /// "" follows the system language.
    @Published var language: String { didSet { d.set(language, forKey: "language") } }

    init() {
        let defaults = UserDefaults.standard
        themeMode = ThemeMode(rawValue: defaults.integer(forKey: "theme")) ?? .system
        accent = defaults.object(forKey: "accent") == nil ? Palette.defaultSeed : UInt32(truncatingIfNeeded: defaults.integer(forKey: "accent"))
        coverColors = defaults.object(forKey: "coverColors") as? Bool ?? true
        playerGradient = defaults.object(forKey: "gradient") as? Bool ?? true
        visualizer = defaults.object(forKey: "visualizer") as? Bool ?? true
        wavySeek = defaults.object(forKey: "wavySeek") as? Bool ?? true
        language = defaults.string(forKey: "language") ?? ""
    }

    var locale: Locale { language.isEmpty ? .autoupdatingCurrent : Locale(identifier: language) }

    var colorScheme: ColorScheme? {
        switch themeMode {
        case .system: return nil
        case .light: return .light
        case .dark, .amoled: return .dark
        }
    }
}
