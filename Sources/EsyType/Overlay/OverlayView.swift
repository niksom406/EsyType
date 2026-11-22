import SwiftUI

struct OverlayView: View {
    let model: OverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if model.isVisible {
                pill.transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark) // the pill is always the dark brand capsule, over any content
    }

    private var pill: some View {
        HStack(spacing: 12) {
            StatusDot(color: dotColor, pulsing: isRecording && !reduceMotion)
            content
            if model.phase == .handsFree {
                CircleButton(label: "Stop and insert", action: model.onStop) {
                    RoundedRectangle(cornerRadius: 2).fill(.black).frame(width: 9, height: 9)
                }
                .background(.white, in: Circle())
            }
            if let cancelLabel {
                CircleButton(label: cancelLabel, action: model.onCancel) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                }
                .background(.white.opacity(0.12), in: Circle())
            }
        }
        .font(.esy(13, .medium))
        .foregroundStyle(.white)
        .padding(.leading, 16)
        .padding(.trailing, cancelLabel == nil ? 18 : 8)
        .frame(height: 44)
        .esyGlass(in: Capsule(), tint: .black.opacity(0.35))
        .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: model.phase)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("EsyType")
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .listening, .handsFree:
            LevelBars(levels: reduceMotion ? BrandMark.envelope(count: 28) : model.levels.values)
            if let notice = model.notice {
                Text(notice).font(.esy(12, .semibold)).foregroundStyle(Brand.warning)
            } else if model.phase == .handsFree {
                Text("Hands-free").font(.esy(12)).foregroundStyle(.white.opacity(0.7))
            }
            Text(timer).font(.system(size: 13, weight: .medium, design: .monospaced))
                .accessibilityLabel("Recording time \(timer)")
        case .transcribing:
            TranscribingBars(paused: reduceMotion)
            Text("Transcribing…")
        case .inserted:
            Text("Inserted")
        case .copied:
            Text("Copied. Press ⌘V to paste")
        case .error(let message):
            Text(message)
        }
    }

    private var isRecording: Bool { model.phase == .listening || model.phase == .handsFree }

    private var dotColor: Color {
        switch model.phase {
        case .listening, .handsFree: Brand.recording
        case .transcribing: .white
        case .inserted: Brand.success
        case .copied, .error: Brand.warning
        }
    }

    private var cancelLabel: String? {
        switch model.phase {
        case .listening, .handsFree, .transcribing: "Cancel dictation"
        case .copied, .error: "Dismiss"
        case .inserted: nil
        }
    }

    private var timer: String {
        let seconds = Int(model.elapsed)
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

/// Low bars with a highlight sweeping left to right: EsyAI's shimmer, used while transcribing.
private struct TranscribingBars: View {
    let paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { context in
            let sweep = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            LevelBars(levels: (0..<28).map { i in Float(0.18 + 0.4 * max(0, 1 - abs(Double(i) / 27 - sweep) * 5)) },
                      fill: AnyShapeStyle(Color.white.opacity(0.55)))
        }
    }
}

private struct StatusDot: View {
    let color: Color
    let pulsing: Bool
    @State private var dim = false

    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .opacity(pulsing && dim ? 0.4 : 1)
            .animation(pulsing ? .easeInOut(duration: 0.8).repeatForever() : .default, value: dim)
            .onAppear { dim = true }
            .accessibilityHidden(true)
    }
}

private struct CircleButton<Icon: View>: View {
    let label: String
    let action: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        Button(action: action) { icon.frame(width: 28, height: 28).contentShape(Circle()) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .help(label)
    }
}
