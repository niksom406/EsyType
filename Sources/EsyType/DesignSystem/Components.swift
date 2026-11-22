import SwiftUI

// MARK: - Glass

extension View {
    /// EsyAI "liquid glass": native Liquid Glass on macOS 26, a material with a hairline edge on 14–15,
    /// and an opaque surface when Reduce Transparency is on.
    func esyGlass<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(GlassModifier(shape: shape, tint: tint))
    }

    func esyCard() -> some View {
        padding(18)
            .background(Brand.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.hairline))
    }
}

extension EnvironmentValues {
    /// Draws the macOS 14–15 material instead of Liquid Glass (offscreen snapshots can't capture Liquid Glass).
    var esyGlassFallback: Bool {
        get { self[GlassFallbackKey.self] }
        set { self[GlassFallbackKey.self] = newValue }
    }
}

private struct GlassFallbackKey: EnvironmentKey { static let defaultValue = false }

private struct GlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.esyGlassFallback) private var forceFallback

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Brand.surfaceRaised, in: shape)
                .overlay(shape.stroke(Brand.hairlineStrong, lineWidth: 1))
        } else if #available(macOS 26, *), !forceFallback {
            content.glassEffect(.regular.tint(tint), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(tint ?? .clear, in: shape)
                .overlay(shape.stroke(
                    LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05), .white.opacity(0.2)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
        }
    }
}

// MARK: - Buttons

/// Solid light capsule, the site's "Get Started" style. One per screen, for the main action.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.esy(14, .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 22)
                .frame(minHeight: 36)
                .background(Brand.ctaGradient, in: Capsule())
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
                .contentShape(Capsule())
        }
    }
}

/// Glass capsule for secondary actions.
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.esy(13, .medium))
                .padding(.horizontal, 16)
                .frame(minHeight: 32)
                .esyGlass(in: Capsule())
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
                .contentShape(Capsule())
        }
    }
}

// MARK: - Brand elements

/// Vertical light bars, the EsyAI mark. `levels` are 0...1 heights, oldest first.
/// The gradient spans the whole height, so short bars show the middle of the blue→amber range, like the mark.
struct LevelBars: View {
    var levels: [Float]
    var barWidth: CGFloat = 2
    var spacing: CGFloat = 2
    var height: CGFloat = 28
    var fill: AnyShapeStyle = AnyShapeStyle(Brand.markGradient)

    var body: some View {
        Rectangle()
            .fill(fill)
            .mask {
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(levels.indices, id: \.self) { index in
                        Capsule().frame(width: barWidth, height: max(barWidth + 1, CGFloat(levels[index]) * height))
                    }
                }
            }
            .frame(width: CGFloat(levels.count) * (barWidth + spacing) - spacing, height: height)
            .accessibilityHidden(true)
    }
}

/// The static brand mark: a waveform envelope of bars.
struct BrandMark: View {
    var bars = 18
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 3
    var height: CGFloat = 72

    var body: some View {
        LevelBars(levels: Self.envelope(count: bars), barWidth: barWidth, spacing: spacing, height: height)
    }

    static func envelope(count: Int) -> [Float] {
        (0..<count).map { i in
            let x = Double(i) / Double(max(count - 1, 1))
            return Float(0.2 + 0.8 * sin(x * .pi) * (0.72 + 0.28 * cos(Double(i) * 1.3)))
        }
    }
}

/// A keyboard key, for showing shortcuts.
struct KeyCap: View {
    let label: String

    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.esy(13, .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.hairlineStrong))
    }
}

/// Small uppercase label above a section.
struct Eyebrow: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.esy(11, .light, relativeTo: .caption))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// Marks placeholder content in this preview build so it is never mistaken for real data.
struct PreviewBadge: View {
    var text = "Preview"

    var body: some View {
        Text(text.uppercased())
            .font(.esy(10, .semibold, relativeTo: .caption2))
            .tracking(0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(Brand.warning)
            .overlay(Capsule().stroke(Brand.warning.opacity(0.6)))
            .accessibilityLabel(text == "Preview" ? "Preview, not real data" : text) // "Beta" and "Soon" read as themselves
    }
}
