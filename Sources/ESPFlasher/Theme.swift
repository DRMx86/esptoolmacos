import SwiftUI

// MARK: - Palette

struct Palette {
    let id: String
    let colorScheme: ColorScheme
    let fontDesign: Font.Design

    let background: Color
    let sidebar: Color
    let panel: Color
    let border: Color
    let text: Color
    let secondaryText: Color
    let accent: Color
    let onAccent: Color
    let danger: Color
    let success: Color
    let terminalBackground: Color
    let terminalText: Color
}

// MARK: - Themes

enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark, hacker

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .hacker: return "Hacker"
        }
    }

    var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .hacker: return "terminal.fill"
        }
    }

    var palette: Palette {
        switch self {
        case .light:
            return Palette(
                id: "light", colorScheme: .light, fontDesign: .default,
                background: Color(hex: 0xF4F5F7),
                sidebar: Color(hex: 0xEBECEF),
                panel: Color(hex: 0xFFFFFF),
                border: Color(hex: 0xDDDFE4),
                text: Color(hex: 0x1C1C1E),
                secondaryText: Color(hex: 0x6B6F76),
                accent: Color(hex: 0x0A7AFF),
                onAccent: .white,
                danger: Color(hex: 0xD92D20),
                success: Color(hex: 0x16A34A),
                terminalBackground: Color(hex: 0xFAFAFB),
                terminalText: Color(hex: 0x1C1C1E)
            )
        case .dark:
            return Palette(
                id: "dark", colorScheme: .dark, fontDesign: .default,
                background: Color(hex: 0x1C1C1E),
                sidebar: Color(hex: 0x161618),
                panel: Color(hex: 0x2A2A2D),
                border: Color(hex: 0x3A3A3E),
                text: Color(hex: 0xF5F5F7),
                secondaryText: Color(hex: 0x9A9AA0),
                accent: Color(hex: 0x3B9CFF),
                onAccent: .white,
                danger: Color(hex: 0xFF6B60),
                success: Color(hex: 0x4ADE80),
                terminalBackground: Color(hex: 0x111113),
                terminalText: Color(hex: 0xD8D8DC)
            )
        case .hacker:
            return Palette(
                id: "hacker", colorScheme: .dark, fontDesign: .monospaced,
                background: Color(hex: 0x000000),
                sidebar: Color(hex: 0x020802),
                panel: Color(hex: 0x050E05),
                border: Color(hex: 0x0F4A1A),
                text: Color(hex: 0x00FF41),
                secondaryText: Color(hex: 0x1FA83A),
                accent: Color(hex: 0x00FF41),
                onAccent: .black,
                danger: Color(hex: 0xFF3B3B),
                success: Color(hex: 0x00FF41),
                terminalBackground: Color(hex: 0x000000),
                terminalText: Color(hex: 0x00FF41)
            )
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}

// MARK: - Store

final class ThemeStore: ObservableObject {
    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: "theme") ?? ""
        theme = AppTheme(rawValue: raw) ?? .dark
    }

    var palette: Palette { theme.palette }
}
