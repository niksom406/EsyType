import SwiftUI

// MARK: - Glass

extension View {
    /// EsyAI "liquid glass": native Liquid Glass on macOS 26, a material with a hairline edge on 14–15,
    /// and an opaque surface when Reduce Transparency is on.
    func esyGlass<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(GlassModifier(shape: shape, tint: tint))
    }

    /// The Windows card: panel colour, hairline edge, 16 pt corners, 18×20 padding.
    func esyCard() -> some View { esyGlassCard() }
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
                .font(.esy(13, .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 34)
                .background(Brand.accent, in: Capsule())
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
            .font(.esyMono(12, .semibold))
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Brand.hairlineStrong))
    }
}

/// Small uppercase label above a section.
struct Eyebrow: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.esy(10.5, .semibold, relativeTo: .caption))
            .tracking(1.2)
            .foregroundStyle(Brand.inkTertiary)
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

// MARK: - Glass and motion

/// macOS's behind-window blur, the Mac counterpart of Windows' Mica: the desktop shows softly through the window.
struct WindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// A looping waveform in the brand gradient, like a speaking voice. Still when Reduce Motion is on.
struct SpeakingWave: View {
    var bars = 36
    var barWidth: CGFloat = 4
    var spacing: CGFloat = 4
    var height: CGFloat = 120
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in // as many bars as fit, so the wave fills its space at any window size
            let count = max(8, min(bars * 3, Int((geo.size.width + spacing) / (barWidth + spacing))))
            wave(count).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func wave(_ bars: Int) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 1.3 : context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<bars, id: \.self) { i in
                    let x = Double(i) / Double(bars)
                    // Syllable-sized ripples inside slower phrases, fading towards both ends.
                    let phrase = 0.55 + 0.45 * sin(t * 1.1 + x * 5)
                    let syllable = 0.5 + 0.5 * sin(t * 6.3 + x * 19)
                    let envelope = sin(x * .pi)
                    let level = max(0.08, envelope * (0.25 + 0.75 * phrase * syllable))
                    Capsule()
                        .fill(Brand.markGradient)
                        .frame(width: barWidth, height: height * level)
                }
            }
            .frame(height: height)
        }
    }
}

/// The window's background: frosted glass tinted with the theme colour, solid when Reduce Transparency is on.
struct WindowBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Brand.canvas
        } else {
            ZStack { WindowGlass(); Brand.canvas.opacity(0.62) }
        }
    }
}

private struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat
    let padded: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        content
            .padding(.vertical, padded ? 18 : 0).padding(.horizontal, padded ? 20 : 0)
            .background(reduceTransparency ? Brand.surface : Brand.glassStrong, in: shape)
            .overlay(shape.stroke(reduceTransparency ? Brand.hairline : Brand.glassEdge))
            .overlay(shape.stroke(Brand.hairline)) // keeps the edge visible on light glass
            .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }
}

extension View {
    /// A Windows-style glass panel: translucent tint, bright edge, 16 pt corners.
    func esyGlassCard(cornerRadius: CGFloat = 16, padded: Bool = true) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, padded: padded))
    }
}
