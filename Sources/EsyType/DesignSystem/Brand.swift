import AppKit
import SwiftUI

/// EsyAI design tokens for EsyType. Source and status of each value: research/ESYAI_DESIGN_TOKENS.md.
enum Brand {
    // Brand mark (sampled from the EsyAI favicon; awaiting official values).
    static let markBlue = Color(hex: 0x2879AB)
    static let markMid = Color(hex: 0x9A988F)
    static let markAmber = Color(hex: 0xDBAE7E)
    static let markGradient = LinearGradient(colors: [markBlue, markMid, markAmber], startPoint: .top, endPoint: .bottom)

    // Neutrals: dark values are verified from esyai.co.uk; light values are a derived extension.
    static let canvas = Color(light: 0xFAFAFA, dark: 0x050505)
    static let surface = Color(light: 0xFFFFFF, dark: 0x0D0D0D)
    static let surfaceRaised = Color(light: 0xF2F2F2, dark: 0x171717)
    static let hairline = Color(light: 0xE5E5E5, dark: 0x262626)
    static let hairlineStrong = Color(light: 0xD4D4D4, dark: 0x333333)

    // Meaning, not decoration: system colours adapt to light/dark and Increase Contrast.
    static let recording = Color(nsColor: .systemRed)
    // Used as text: darker in light mode for ≥ 4.5:1 contrast (system green/yellow are 2.1:1 and 1.4:1 on the canvas).
    static let success = Color(light: 0x1E7B34, dark: 0x30D158)
    static let warning = Color(light: 0x8A5A00, dark: 0xFFD60A)

    static let ctaGradient = LinearGradient(colors: [Color(hex: 0xF3F4F6), Color(hex: 0xD1D5DB)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Barlow for interface text, Instrument Serif Italic for display moments only.
extension Font {
    enum BarlowWeight: String { case light = "Light", regular = "Regular", medium = "Medium", semibold = "SemiBold" }

    static func esy(_ size: CGFloat, _ weight: BarlowWeight = .regular, relativeTo style: TextStyle = .body) -> Font {
        .custom("Barlow-\(weight.rawValue)", size: size, relativeTo: style)
    }

    static func esyDisplay(_ size: CGFloat, relativeTo style: TextStyle = .largeTitle) -> Font {
        .custom("InstrumentSerif-Italic", size: size, relativeTo: style)
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

    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
    }
}

/// The app-wide appearance setting. Dark is the brand default.
enum Appearance: String, CaseIterable, Identifiable {
    case system, dark, light // the Windows order: Follow device, Dark, Light
    static let defaultsKey = "appearance"
    var id: Self { self }
    var title: String { self == .system ? "Follow Mac" : rawValue.capitalized }

    @MainActor static func apply() {
        let value = Appearance(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .dark
        NSApp.appearance = switch value {
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        case .system: nil
        }
    }
}
