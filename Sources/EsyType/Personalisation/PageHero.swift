import SwiftUI

/// The poster banner at the top of each page: serif headline, one line of text, actions, and the voice wave.
/// Always the dark brand card (like the Dictation page). ✕ hides it; the choice is remembered per page.
struct PageHero<Actions: View>: View {
    let headline: Text
    let message: String
    var glow = Color(hex: 0xDFA164)
    var dismissible = true
    @ViewBuilder let actions: Actions
    @AppStorage private var dismissed: Bool

    init(_ id: String, headline: Text, message: String, glow: Color = Color(hex: 0xDFA164), dismissible: Bool = true,
         @ViewBuilder actions: () -> Actions) {
        self.headline = headline
        self.message = message
        self.glow = glow
        self.dismissible = dismissible
        self.actions = actions()
        _dismissed = AppStorage(wrappedValue: false, "hero.dismissed.\(id)")
    }

    var body: some View {
        if !(dismissible && dismissed) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    // Upright Georgia, so the one emphasised word (.italic()) stands out, like the reference banners.
                    headline.font(.custom("Georgia", size: 34)).tracking(-0.6).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(message).font(.esy(14)).foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    FlowRow(spacing: 8) { actions }.padding(.top, 8)
                }
                .frame(minWidth: 260, idealWidth: 360, maxWidth: 460, alignment: .leading)
                .layoutPriority(1)
                SpeakingWave(bars: 26, barWidth: 4, spacing: 5, height: 140)
                    .frame(minWidth: 120, idealWidth: 160, maxWidth: .infinity)
                    .clipped()
                    .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
            }
            .padding(34)
            .background {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x050507), Color(hex: 0x14102A), Color(hex: 0x2A1A3F)],
                                   startPoint: .leading, endPoint: .trailing)
                    RadialGradient(colors: [glow.opacity(0.28), .clear], center: .init(x: 0.8, y: 0.35),
                                   startRadius: 0, endRadius: 300)
                }
            }
            .overlay(alignment: .topTrailing) {
                if dismissible {
                    Button { withAnimation(.easeOut(duration: 0.25)) { dismissed = true } } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 30).background(.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain).padding(16).accessibilityLabel("Hide this banner")
                }
            }
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08)))
            .environment(\.colorScheme, .dark)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
}

/// The hero's main action: a frosted button.
struct HeroButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }

    var body: some View {
        Button(action: action) {
            Text(title).font(.esy(14, .semibold)).padding(.horizontal, 18).frame(height: 40)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }
}

/// A quieter chip beside the hero's button (an example word, a placeholder, a style).
struct HeroChip: View {
    let title: String
    var action: (() -> Void)?
    init(_ title: String, action: (() -> Void)? = nil) { self.title = title; self.action = action }

    var body: some View {
        let label = Text(title).font(.esy(14)).foregroundStyle(.white.opacity(0.7)).padding(.horizontal, 16).frame(height: 40)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        if let action { Button(action: action) { label }.buttonStyle(.plain) } else { label }
    }
}

/// Lays children out left to right and wraps onto new lines (chips, actions).
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            row = max(row, size.height)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

// MARK: - Shared page parts

/// A page section: glass card with a title row (title, count, actions).
struct SectionCard<Trailing: View, Content: View>: View {
    let title: String
    var count: Int?
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Text(title).font(.esy(17, .semibold))
                if let count {
                    Text("\(count)").font(.esy(12, .semibold)).foregroundStyle(Brand.inkSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 2).background(Brand.surfaceRaised, in: Capsule())
                }
                Spacer(minLength: 8)
                trailing
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .esyGlassCard(cornerRadius: 20, padded: false)
    }
}

extension SectionCard where Trailing == EmptyView {
    init(_ title: String, count: Int? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, count: count, trailing: { EmptyView() }, content: content)
    }
}

/// Capsule buttons for card headers. `danger` is the red outline used for Delete all.
struct PillButton: View {
    let title: String
    var systemImage: String?
    var danger = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { Text(title) } icon: { if let systemImage { Image(systemName: systemImage) } }
                .labelStyle(.titleAndIcon)
                .font(.esy(13, .medium))
                .foregroundStyle(danger ? Brand.recording : Brand.ink)
                .padding(.horizontal, 14).frame(height: 32)
                .background(danger ? Brand.recording.opacity(0.08) : Brand.surfaceRaised, in: Capsule())
                .overlay(Capsule().stroke(danger ? Brand.recording.opacity(0.45) : Brand.hairline))
        }
        .buttonStyle(.plain)
    }
}

/// The accent action (Add, Add snippet).
struct AccentButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.esy(14, .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 20).frame(height: 40)
                .background(enabled ? Brand.accent : Brand.accent.opacity(0.35), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Rounded search field used on every list.
struct SearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Brand.inkTertiary)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.esy(14))
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Brand.inkTertiary).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14).frame(height: 40)
        .background(Brand.surfaceRaised.opacity(0.6), in: Capsule())
        .overlay(Capsule().stroke(Brand.hairlineStrong))
    }
}

/// A labelled input: small capitals label above a rounded field.
struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text.uppercased()).font(.esy(10.5, .semibold)).tracking(1.2).foregroundStyle(Brand.inkTertiary) }
}

struct RoundedField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        TextField(prompt, text: $text).textFieldStyle(.plain).font(.esy(15))
            .padding(.horizontal, 16).frame(height: 44)
            .background(Brand.surfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.hairlineStrong))
    }
}

/// Empty list: icon in a circle, serif title, a line, and one action.
struct EmptyList: View {
    let symbol: String
    let title: String
    let message: String
    let action: String
    let perform: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 22)).frame(width: 60, height: 60)
                .background(Brand.surfaceRaised, in: Circle()).overlay(Circle().stroke(Brand.hairline))
            Text(title).font(.esyDisplay(26))
            Text(message).font(.esy(14)).foregroundStyle(Brand.inkTertiary).multilineTextAlignment(.center)
            Button(action: perform) {
                Text(action).font(.esy(14, .semibold)).foregroundStyle(Brand.canvas)
                    .padding(.horizontal, 20).frame(height: 40).background(Brand.ink, in: Capsule())
            }
            .buttonStyle(.plain).padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
    }
}

/// A short status line under a card (saved to Downloads, imported, errors) with an optional Show in Finder.
struct StatusLine: View {
    let text: String
    var file: URL?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: file == nil ? "info.circle" : "checkmark.circle.fill")
                .foregroundStyle(file == nil ? Brand.inkTertiary : Brand.success)
            Text(text).font(.esy(13)).foregroundStyle(Brand.inkSecondary)
            if let file {
                Button("Show in Finder") { Downloads.reveal(file) }.buttonStyle(.plain).font(.esy(13, .semibold))
                    .foregroundStyle(Brand.accentInk)
            }
        }
        .transition(.opacity)
    }
}

/// A setting row: text on the left, switch on the right edge.
struct SwitchRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.esy(14, .medium)).fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.esy(12)).foregroundStyle(Brand.inkTertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
        .accessibilityElement(children: .combine)
    }
}
