import AppKit
import SwiftUI

/// EsyType design tokens, matching the Windows "Next Generation" design (artifact 1LemoizD2hmuqncJKFsBBn, 2026-11-22):
/// the same light and dark palettes, purple accent, Georgia italic for display and the system sans for text.
enum Brand {
    // The waveform / mark gradient, bottom to top: blue → accent → amber.
    static let markBlue = Color(hex: 0x27669A)
    static let markMid = Color(light: 0x5A2FC2, dark: 0xA78BFA)
    static let markAmber = Color(hex: 0xDFA164)
    static let markGradient = LinearGradient(colors: [markAmber, markMid, markBlue], startPoint: .top, endPoint: .bottom)

    // Surfaces (Windows tokens: --win, --side, --panel, --panel-2).
    static let canvas = Color(light: 0xFFFFFF, dark: 0x0B0B0C)
    static let sidebar = Color(light: 0xF7F6FB, dark: 0x0E0E10)
    static let surface = Color(light: 0xFFFFFF, dark: 0x141416)
    static let surfaceRaised = Color(light: 0xF1EFF7, dark: 0x1B1B1F)
    // Lines and text (--line, --line-2, --ink, --ink-3).
    static let hairline = Color(light: 0x15121C, dark: 0xFFFFFF, lightAlpha: 0.11, darkAlpha: 0.10)
    static let hairlineStrong = Color(light: 0x15121C, dark: 0xFFFFFF, lightAlpha: 0.22, darkAlpha: 0.22)
    static let ink = Color(light: 0x15121C, dark: 0xFFFFFF)
    static let inkSecondary = Color(light: 0x15121C, dark: 0xFFFFFF, lightAlpha: 0.74, darkAlpha: 0.76)
    static let inkTertiary = Color(light: 0x15121C, dark: 0xFFFFFF, lightAlpha: 0.56, darkAlpha: 0.54)

    // Accent (--accent, --accent-ink, --accent-soft).
    static let accent = Color(light: 0x6B3FD4, dark: 0x8350E8)
    static let accentInk = Color(light: 0x5A2FC2, dark: 0xA78BFA)
    static let accentSoft = Color(light: 0x6B3FD4, dark: 0x8350E8, lightAlpha: 0.10, darkAlpha: 0.18)

    // Glass (--glass, --glass-strong, --glass-edge, --glass-hi).
    static let glass = Color(light: 0xFFFFFF, dark: 0x16161C, lightAlpha: 0.52, darkAlpha: 0.50)
    static let glassStrong = Color(light: 0xFFFFFF, dark: 0x14141A, lightAlpha: 0.72, darkAlpha: 0.70)
    static let glassEdge = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.78, darkAlpha: 0.14)

    // Activity heatmap shades (--heat-0 … --heat-4).
    static let heat: [Color] = [Color(light: 0xE9E6F2, dark: 0x1D1D22), Color(light: 0xCFC2F3, dark: 0x2F2550),
                                Color(light: 0xA98CE9, dark: 0x4B3488), Color(light: 0x7F56DD, dark: 0x6B45C8),
                                Color(light: 0x5A2FC2, dark: 0xA78BFA)]

    // Meaning (--ok, --warn, --rec). Text-safe contrast in both themes.
    static let recording = Color(light: 0xDC2626, dark: 0xEF4444)
    static let success = Color(light: 0x15803D, dark: 0x4ADE80)
    static let warning = Color(light: 0xA16207, dark: 0xF2B04A)
}

/// System sans for interface text (Windows uses Segoe UI), Georgia italic for display moments, and a monospaced
/// face for keys and timers — as in the Windows design.
extension Font {
    enum BarlowWeight: String { case light = "Light", regular = "Regular", medium = "Medium", semibold = "SemiBold" }

    static func esy(_ size: CGFloat, _ weight: BarlowWeight = .regular, relativeTo style: TextStyle = .body) -> Font {
        let w: Font.Weight = switch weight {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
        return .system(size: size, weight: w)
    }

    static func esyDisplay(_ size: CGFloat, relativeTo style: TextStyle = .largeTitle) -> Font {
        .custom("Georgia-Italic", size: size, relativeTo: style)
    }

    static func esyMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light, opacity: isDark ? darkAlpha : lightAlpha))
        })
    }
}

/// The app-wide appearance setting: Follow Mac (default, like Windows' Follow device), Dark or Light.
enum Appearance: String, CaseIterable, Identifiable {
    case system, dark, light // the Windows order: Follow device, Dark, Light
    static let defaultsKey = "appearance"
    var id: Self { self }
    var title: String { self == .system ? "Follow Mac" : rawValue.capitalized }

    @MainActor static func apply() {
        let value = Appearance(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
        NSApp.appearance = switch value {
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        case .system: nil
        }
    }
}
