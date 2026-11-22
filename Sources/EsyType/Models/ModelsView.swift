import EsyTypeCore
import SwiftUI

/// Main window ▸ Models: download, cancel and remove speech models.
struct ModelsView: View {
    let models: ModelLibrary
    private let recommended = Recommender.recommend(for: HardwareDetector.current()).model
    @State private var removing: ModelInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Speech models").font(.esyDisplay(40)).tracking(-1).accessibilityAddTraits(.isHeader)
            Text("Models run on this Mac. Each is downloaded once from Hugging Face and checked against its published SHA-256 before it’s used.")
                .font(.esy(14, .light)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
            ForEach(ModelCatalog.all) { row($0) }
        }
        .confirmationDialog("Remove \(removing.map { "\($0.name) · \($0.quantisation)" } ?? "")?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            presenting: removing) { model in
            Button("Remove", role: .destructive) { Task { await models.remove(model) } }
        } message: { model in
            Text("This frees \(formatBytes(model.bytes)). You can download it again later.")
        }
    }

    private func row(_ model: ModelInfo) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(model.name) · \(model.quantisation)").font(.esy(15, .semibold))
                    if model == recommended {
                        Text("Recommended").font(.esy(10, .semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Brand.markBlue.opacity(0.25), in: Capsule())
                    }
                }
                Text(formatBytes(model.bytes) + (model.id.hasPrefix("turbo") ? " · Not yet tested on this Mac" : ""))
                    .font(.esy(12)).foregroundStyle(.secondary)
                if let error = models.errors[model.id] {
                    Text(error).font(.esy(12)).foregroundStyle(Brand.warning).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if let fraction = models.progress[model.id] {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: fraction).tint(Brand.markBlue).frame(width: 120)
                        .accessibilityLabel("Downloading \(model.name)")
                    Text(fraction >= 1 ? "Verifying…" : "\(Int(fraction * 100)) %")
                        .font(.esy(11)).foregroundStyle(.secondary).monospacedDigit()
                }
                Button("Cancel") { models.cancel(model) }.buttonStyle(GlassButtonStyle())
            } else if models.isInstalled(model) {
                Label("Installed", systemImage: "checkmark.circle.fill").font(.esy(12, .medium)).foregroundStyle(Brand.success)
                Button("Remove…") { removing = model }.buttonStyle(GlassButtonStyle())
            } else {
                Button("Download") { models.download(model) }.buttonStyle(GlassButtonStyle())
            }
        }
        .esyCard()
    }
}
