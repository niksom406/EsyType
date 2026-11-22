import EsyTypeCore
import SwiftUI

struct OnboardingView: View {
    enum Step: Int, CaseIterable { case welcome, microphone, aboutYou, appearance, accessibility, shortcut, yourMac, download, tryIt }

    let permissions: Permissions
    let models: ModelLibrary
    let onFinish: () -> Void
    @State var step = Step.welcome
    @AppStorage(Pref.userName) private var userName = ""
    @AppStorage(Pref.meetingName) private var meetingName = ""
    @AppStorage(Appearance.defaultsKey) private var appearance = Appearance.system
    private let mac = HardwareDetector.current()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule().fill(item.rawValue <= step.rawValue ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: 22, height: 4)
                }
            }
            .padding(.top, 14)
            .accessibilityElement()
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 48)
                .padding(.top, 28)
                .padding(.bottom, 32)
        }
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .microphone:
            StepLayout(title: "First, your microphone.",
                       message: "EsyType listens only while you’re dictating: while you hold your shortcut, or between pressing it to start and stop. Your voice is turned into text on this Mac and is never uploaded.",
                       back: back) {
                PermissionRow(title: "Microphone", detail: "Needed to hear you", granted: permissions.microphone == .allowed,
                              action: { Task { await permissions.requestMicrophone() } }).esyCard()
            } actions: {
                if permissions.microphone == .allowed {
                    Button("Continue", action: next).buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Allow Microphone") { Task { await permissions.requestMicrophone() } }.buttonStyle(PrimaryButtonStyle())
                }
            }
        case .aboutYou:
            StepLayout(title: "What should EsyType call you?",
                       message: "Used to label your lines in meeting transcripts, in place of “You”. It isn’t used to recognise your voice, and it’s stored only on this Mac. You can change it in Settings.",
                       back: back) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Your name", text: $userName, prompt: Text("Your name")).textFieldStyle(.roundedBorder)
                    TextField("Shown in meetings as", text: $meetingName, prompt: Text("Shown in meetings as")).textFieldStyle(.roundedBorder)
                }
                .font(.esy(14)).esyCard()
            } actions: {
                Button("Skip", action: next).buttonStyle(.borderless).font(.esy(13))
                Button("Continue", action: next).buttonStyle(PrimaryButtonStyle())
            }
        case .appearance:
            StepLayout(title: "Light or dark?",
                       message: "Follow Mac switches with your macOS setting. Your choice is kept after a restart, and you can change it in Settings.",
                       back: back) {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .onChange(of: appearance) { Appearance.apply() }
            } actions: {
                Button("Continue", action: next).buttonStyle(PrimaryButtonStyle())
            }
        case .accessibility:
            StepLayout(title: "Let EsyType type for you.",
                       message: "To place text where your cursor is, macOS needs you to switch on EsyType in Privacy & Security ▸ Accessibility. EsyType uses it only to paste your dictation. It doesn’t read or record your screen.",
                       back: back) {
                PermissionRow(title: "Accessibility", detail: "Pastes your text into the app you’re using",
                              granted: permissions.accessibility, action: permissions.requestAccessibility).esyCard()
            } actions: {
                if permissions.accessibility {
                    Button("Continue", action: next).buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Skip, copy to clipboard instead", action: next).buttonStyle(.borderless).font(.esy(13))
                    Button("Open System Settings", action: permissions.requestAccessibility).buttonStyle(PrimaryButtonStyle())
                }
            }
        case .shortcut:
            StepLayout(title: "Your shortcut.",
                       message: "Hold Right ⌥ (Option) to talk and let go to insert. Press ⌃⌥Space to talk hands-free, and press it again to stop. Esc cancels.",
                       back: back) {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Push to talk") { KeyCap("Right ⌥") }
                    LabeledContent("Hands-free") { KeyCap("⌃⌥Space") }
                    Text("Single-key shortcuts like Right ⌥ need Input Monitoring. You can change shortcuts later in Settings.")
                        .font(.esy(12)).foregroundStyle(.secondary)
                }
                .font(.esy(14))
                .esyCard()
            } actions: {
                if !permissions.inputMonitoring {
                    Button("Allow Input Monitoring…", action: permissions.requestInputMonitoring).buttonStyle(GlassButtonStyle())
                }
                Button("Continue", action: next).buttonStyle(PrimaryButtonStyle())
            }
        case .yourMac:
            YourMacStep(mac: mac, models: models, back: back, next: next)
        case .download:
            DownloadStep(model: Recommender.recommend(for: mac).model, models: models, back: back, next: next)
        case .tryIt:
            StepLayout(title: "Try it.", message: "Click in the box, hold Right ⌥ and say something.", back: back) {
                TryItBox()
            } actions: {
                Button("Finish", action: onFinish).buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            BrandMark(bars: 22, barWidth: 4, spacing: 4, height: 96)
            Text("Speak. It’s typed.").font(.esyDisplay(48)).tracking(-1.2).accessibilityAddTraits(.isHeader)
            Text("Private voice typing for every app on your Mac. Your voice is transcribed on this Mac and never leaves it.")
                .font(.esy(15, .light)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            Button("Get started", action: next).buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            Text("About 2 minutes").font(.esy(12)).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func next() { if let s = Step(rawValue: step.rawValue + 1) { step = s } }
    private func back() { if let s = Step(rawValue: step.rawValue - 1) { step = s } }
}

/// Title, explanation, content, then a row of actions. Shared by every step after Welcome.
private struct StepLayout<Content: View, Actions: View>: View {
    let title: String
    let message: String
    let back: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.esyDisplay(36)).tracking(-0.9).accessibilityAddTraits(.isHeader)
            Text(message).font(.esy(14, .light)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            content
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button("Back", action: back).buttonStyle(.borderless).font(.esy(13))
                Spacer()
                actions
            }
        }
    }
}

// MARK: - Preview-only steps

// MARK: - Model steps

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .decimal
    formatter.allowsNonnumericFormatting = false // "0 KB", not "Zero KB"
    return formatter.string(fromByteCount: bytes)
}

private struct YourMacStep: View {
    let mac: HardwareProfile
    let models: ModelLibrary
    let back: () -> Void
    let next: () -> Void

    var body: some View {
        let pick = Recommender.recommend(for: mac)
        StepLayout(title: "Your Mac, your model.",
                   message: "EsyType picks a speech model that runs well on this Mac. You can change it any time.",
                   back: back) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    fact("Chip", mac.chip)
                    fact("Memory", "\(mac.memoryGB) GB")
                    fact("Free disk", formatBytes(mac.freeDiskBytes))
                    fact("macOS", mac.macOSVersion)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recommended: \(pick.model.name) · \(pick.model.quantisation)").font(.esy(17, .semibold))
                    Text(pick.reason).font(.esy(13)).foregroundStyle(.secondary)
                    Text("Download \(formatBytes(pick.model.bytes)) · Uses \(formatBytes(pick.model.bytes)) on disk")
                        .font(.esy(12))
                    ForEach(pick.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "info.circle").font(.esy(12)).foregroundStyle(Brand.warning)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .esyGlass(in: RoundedRectangle(cornerRadius: 12))
                if pick.shortfallBytes > 0, !models.isInstalled(pick.model) {
                    Label("Free \(formatBytes(pick.shortfallBytes)) more to continue. EsyType keeps at least 1 GB spare.",
                          systemImage: "exclamationmark.triangle")
                        .font(.esy(12)).foregroundStyle(Brand.warning)
                }
            }
        } actions: {
            if models.isInstalled(pick.model) {
                Button("Continue", action: next).buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Download \(formatBytes(pick.model.bytes))") {
                    models.download(pick.model)
                    next()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(pick.shortfallBytes > 0)
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.esy(11)).foregroundStyle(.secondary)
            Text(value).font(.esy(14, .medium)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.hairline))
        .accessibilityElement(children: .combine)
    }
}

private struct DownloadStep: View {
    let model: ModelInfo
    let models: ModelLibrary
    let back: () -> Void
    let next: () -> Void

    var body: some View {
        let installed = models.isInstalled(model)
        let progress = models.progress[model.id]
        let error = models.errors[model.id]
        let fraction = installed ? 1 : progress ?? 0
        let status = installed ? "Ready" : progress.map { $0 >= 1 ? "Verifying checksum…" : "Downloading" }
            ?? (error == nil ? "Not downloaded yet" : "Download stopped")
        StepLayout(title: "Getting your model.",
                   message: "This happens once. After that, EsyType works without an internet connection.",
                   back: back) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(model.name) · \(model.quantisation): \(status)").font(.esy(14, .medium))
                ProgressView(value: fraction).tint(Brand.markBlue).accessibilityLabel("Download progress")
                Text("\(formatBytes(Int64(fraction * Double(model.bytes)))) of \(formatBytes(model.bytes))")
                    .font(.esy(12)).foregroundStyle(.secondary).monospacedDigit()
                if let error {
                    Text(error).font(.esy(12)).foregroundStyle(Brand.warning).fixedSize(horizontal: false, vertical: true)
                }
            }
            .esyCard()
        } actions: {
            if progress != nil {
                Button("Cancel") { models.cancel(model) }.buttonStyle(GlassButtonStyle())
            } else if !installed {
                Button(error == nil ? "Download" : "Try again") { models.download(model) }.buttonStyle(GlassButtonStyle())
            }
            Button("Continue", action: next).buttonStyle(PrimaryButtonStyle()).disabled(!installed)
        }
    }
}

private struct TryItBox: View {
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $text)
                .font(.esy(14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 100)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.hairlineStrong))
                .accessibilityLabel("Try it here")
            HStack(spacing: 10) {
                PreviewBadge(text: "Beta")
                Text("Without Accessibility the text is copied: press ⌘V.").font(.esy(12)).foregroundStyle(.secondary)
            }
        }
    }
}
