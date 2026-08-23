import AppKit
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func resolvedColorScheme(systemColorScheme: ColorScheme) -> ColorScheme {
        preferredColorScheme ?? systemColorScheme
    }
}

enum ThemeID: String, CaseIterable, Identifiable {
    case systemNative
    case paper
    case graphite
    case midnight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemNative: return "系统原生"
        case .paper: return "纸张"
        case .graphite: return "石墨"
        case .midnight: return "午夜"
        }
    }
}

enum AccentID: String, CaseIterable, Identifiable {
    case blue
    case green
    case purple
    case orange
    case red
    case teal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: return "蓝色"
        case .green: return "绿色"
        case .purple: return "紫色"
        case .orange: return "橙色"
        case .red: return "红色"
        case .teal: return "青色"
        }
    }
}

struct AppearancePreferences: Equatable {
    static let modeDefaultsKey = "appearanceMode"
    static let themeDefaultsKey = "appearanceTheme"
    static let accentDefaultsKey = "appearanceAccent"
    static let standard = AppearancePreferences()

    var mode: AppearanceMode
    var theme: ThemeID
    var accent: AccentID

    init(
        mode: AppearanceMode = .system,
        theme: ThemeID = .systemNative,
        accent: AccentID = .blue
    ) {
        self.mode = mode
        self.theme = theme
        self.accent = accent
    }

    init(defaults: UserDefaults) {
        mode = defaults.string(forKey: Self.modeDefaultsKey)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        theme = defaults.string(forKey: Self.themeDefaultsKey)
            .flatMap(ThemeID.init(rawValue:)) ?? .systemNative
        accent = defaults.string(forKey: Self.accentDefaultsKey)
            .flatMap(AccentID.init(rawValue:)) ?? .blue
    }

    func save(to defaults: UserDefaults) {
        defaults.set(mode.rawValue, forKey: Self.modeDefaultsKey)
        defaults.set(theme.rawValue, forKey: Self.themeDefaultsKey)
        defaults.set(accent.rawValue, forKey: Self.accentDefaultsKey)
    }
}

struct LocalNoteTheme {
    let themeID: ThemeID
    let colorScheme: ColorScheme
    let accentID: AccentID
    let backgroundNSColor: NSColor
    let surfaceNSColor: NSColor
    let primaryTextNSColor: NSColor
    let secondaryTextNSColor: NSColor
    let completedTextNSColor: NSColor
    let separatorNSColor: NSColor
    let accentNSColor: NSColor
    let activityNSColors: [NSColor]

    var background: Color { Color(backgroundNSColor) }
    var surface: Color { Color(surfaceNSColor) }
    var primaryText: Color { Color(primaryTextNSColor) }
    var secondaryText: Color { Color(secondaryTextNSColor) }
    var completedText: Color { Color(completedTextNSColor) }
    var separator: Color { Color(separatorNSColor) }
    var accent: Color { Color(accentNSColor) }

    static func resolve(
        preferences: AppearancePreferences,
        systemColorScheme: ColorScheme
    ) -> LocalNoteTheme {
        let scheme = preferences.mode.resolvedColorScheme(systemColorScheme: systemColorScheme)
        let base = palette(themeID: preferences.theme, colorScheme: scheme)
        let accent = accentColor(preferences.accent, colorScheme: scheme)
        let levels: [CGFloat] = [0.04, 0.18, 0.34, 0.52, 0.72, 0.9]
        let activities = levels.enumerated().map { index, fraction in
            index == 0
                ? blend(base.background, base.primaryText, fraction: fraction)
                : blend(base.background, accent, fraction: fraction)
        }
        return LocalNoteTheme(
            themeID: preferences.theme,
            colorScheme: scheme,
            accentID: preferences.accent,
            backgroundNSColor: base.background,
            surfaceNSColor: base.surface,
            primaryTextNSColor: base.primaryText,
            secondaryTextNSColor: base.secondaryText,
            completedTextNSColor: base.completedText,
            separatorNSColor: base.separator,
            accentNSColor: accent,
            activityNSColors: activities
        )
    }

    func activityColor(level: Int) -> Color {
        Color(activityNSColors[max(0, min(level, activityNSColors.count - 1))])
    }

    func activityTextColor(level: Int) -> Color {
        Color(activityTextNSColor(level: level))
    }

    func activityTextNSColor(level: Int) -> NSColor {
        guard level >= 4 else { return primaryTextNSColor }
        return Self.contrastingTextColor(on: activityNSColors[min(level, 5)])
    }

    static func accentColor(_ accent: AccentID, colorScheme: ColorScheme) -> NSColor {
        let lightHex: UInt32
        let darkHex: UInt32
        switch accent {
        case .blue: lightHex = 0x2878F0; darkHex = 0x5A9BFF
        case .green: lightHex = 0x2F9E59; darkHex = 0x55C878
        case .purple: lightHex = 0x8357E8; darkHex = 0xA984FF
        case .orange: lightHex = 0xE86F18; darkHex = 0xFF984D
        case .red: lightHex = 0xDF3E4C; darkHex = 0xFF6B75
        case .teal: lightHex = 0x159E9C; darkHex = 0x45C7C4
        }
        return rgb(colorScheme == .dark ? darkHex : lightHex)
    }

    static func contrastRatio(_ first: NSColor, _ second: NSColor) -> CGFloat {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private struct BasePalette {
        let background: NSColor
        let surface: NSColor
        let primaryText: NSColor
        let secondaryText: NSColor
        let completedText: NSColor
        let separator: NSColor
    }

    private static func palette(themeID: ThemeID, colorScheme: ColorScheme) -> BasePalette {
        switch (themeID, colorScheme) {
        case (.systemNative, .light):
            return BasePalette(
                background: rgb(0xF1F1F1), surface: rgb(0xFAFAFA),
                primaryText: rgb(0x1D1D1F), secondaryText: rgb(0x6E6E73),
                completedText: rgb(0x77777B), separator: rgb(0xD1D1D1)
            )
        case (.systemNative, .dark):
            return BasePalette(
                background: rgb(0x202124), surface: rgb(0x2B2C2F),
                primaryText: rgb(0xF2F2F2), secondaryText: rgb(0xA6A6AA),
                completedText: rgb(0xA0A0A4), separator: rgb(0x434448)
            )
        case (.paper, .light):
            return BasePalette(
                background: rgb(0xF7F1E6), surface: rgb(0xFDF9F2),
                primaryText: rgb(0x2F2A24), secondaryText: rgb(0x776D60),
                completedText: rgb(0x817669), separator: rgb(0xD8CEBE)
            )
        case (.paper, .dark):
            return BasePalette(
                background: rgb(0x24201B), surface: rgb(0x302A23),
                primaryText: rgb(0xF3E9D9), secondaryText: rgb(0xB7AA98),
                completedText: rgb(0xA89B89), separator: rgb(0x494036)
            )
        case (.graphite, .light):
            return BasePalette(
                background: rgb(0xE9E9E7), surface: rgb(0xF4F4F2),
                primaryText: rgb(0x1F2022), secondaryText: rgb(0x686A6E),
                completedText: rgb(0x74767A), separator: rgb(0xC7C8C9)
            )
        case (.graphite, .dark):
            return BasePalette(
                background: rgb(0x27282A), surface: rgb(0x323335),
                primaryText: rgb(0xF0F0EE), secondaryText: rgb(0xA6A7AA),
                completedText: rgb(0xA0A1A4), separator: rgb(0x494A4D)
            )
        case (.midnight, .light):
            return BasePalette(
                background: rgb(0xEDF2F8), surface: rgb(0xF7FAFD),
                primaryText: rgb(0x162033), secondaryText: rgb(0x667086),
                completedText: rgb(0x747F94), separator: rgb(0xC8D2E0)
            )
        case (.midnight, .dark):
            return BasePalette(
                background: rgb(0x121A28), surface: rgb(0x1A2536),
                primaryText: rgb(0xECF3FF), secondaryText: rgb(0x9EACC1),
                completedText: rgb(0x93A0B4), separator: rgb(0x30405A)
            )
        @unknown default:
            return palette(themeID: .systemNative, colorScheme: .light)
        }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }

    private static func blend(_ background: NSColor, _ foreground: NSColor, fraction: CGFloat) -> NSColor {
        let backgroundComponents = components(background)
        let foregroundComponents = components(foreground)
        let amount = max(0, min(1, fraction))
        return NSColor(
            srgbRed: backgroundComponents.red + (foregroundComponents.red - backgroundComponents.red) * amount,
            green: backgroundComponents.green + (foregroundComponents.green - backgroundComponents.green) * amount,
            blue: backgroundComponents.blue + (foregroundComponents.blue - backgroundComponents.blue) * amount,
            alpha: 1
        )
    }

    private static func contrastingTextColor(on color: NSColor) -> NSColor {
        let black = rgb(0x000000)
        let white = rgb(0xFFFFFF)
        return contrastRatio(black, color) >= contrastRatio(white, color) ? black : white
    }

    private static func relativeLuminance(_ color: NSColor) -> CGFloat {
        let value = components(color)
        func channel(_ component: CGFloat) -> CGFloat {
            component <= 0.03928
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(value.red)
            + 0.7152 * channel(value.green)
            + 0.0722 * channel(value.blue)
    }

    private static func components(_ color: NSColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let converted = color.usingColorSpace(.sRGB) ?? color
        return (converted.redComponent, converted.greenComponent, converted.blueComponent)
    }
}
