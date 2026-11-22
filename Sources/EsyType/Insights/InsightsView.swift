import EsyTypeCore
import SwiftUI

/// Insights: your own numbers, worked out on this Mac from daily totals (no text).
struct InsightsView: View {
    let insights: InsightsModel
    @AppStorage(Pref.typingWPM) private var typingWPM = 40.0
    @State private var showWorking = false

    var body: some View {
        let all = insights.log.summary()
        let shares = insights.log.categoryShares()
        VStack(alignment: .leading, spacing: 16) {
            PageTitle("Insights")
            Text("Words, speed and time saved, from numbers kept on this Mac. They stay even when History is off or trimmed.")
                .font(.esy(14, .light)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    tile(all.words.formatted(), "Words dictated", all.since.map { "since \(Self.day($0))" } ?? "none yet")
                    tile("\(all.wordsPerMinute)", "Words per minute", "speaking, not typing")
                }
                GridRow {
                    tile(Self.duration(all.secondsSaved(typingWPM: typingWPM)), "Time saved", "at \(Int(typingWPM)) wpm typing") {
                        Button("How?") { showWorking.toggle() }.buttonStyle(.link).font(.esy(12))
                            .popover(isPresented: $showWorking) { working(all).padding(16).frame(width: 300) }
                    }
                    tile("—", "Meetings transcribed", "comes with EsyMeet")
                }
            }
            Stepper("Your typing speed: \(Int(typingWPM)) words a minute", value: $typingWPM, in: 10...150, step: 5)
                .font(.esy(13))
            VStack(alignment: .leading, spacing: 10) {
                Text("This week").font(.esy(13, .semibold))
                if shares.isEmpty {
                    Text("Dictate into a few apps and the split appears here.").font(.esy(12)).foregroundStyle(.secondary)
                }
                ForEach(shares, id: \.0) { category, share in
                    HStack(spacing: 10) {
                        Text(category.rawValue).font(.esy(13)).frame(width: 110, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(Brand.markGradient).frame(width: max(4, geo.size.width * share))
                        }
                        .frame(height: 8)
                        Text(share.formatted(.percent.precision(.fractionLength(0)))).font(.esy(13, .medium)).frame(width: 44, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .esyCard()
            Text("App categories come from the app’s identifier only. EsyType never reads window titles or document contents for Insights.")
                .font(.esy(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tile(_ value: String, _ label: String, _ note: String) -> some View { tile(value, label, note) { EmptyView() } }

    private func tile(_ value: String, _ label: String, _ note: String, @ViewBuilder extra: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.esyDisplay(36)).tracking(-0.8)
            Text(label).font(.esy(13, .medium))
            HStack(spacing: 6) { Text(note).font(.esy(12)).foregroundStyle(.secondary); extra() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .esyCard()
        .accessibilityElement(children: .combine)
    }

    private func working(_ summary: InsightsSummary) -> some View {
        let typing = Double(summary.words) / typingWPM * 60
        return VStack(alignment: .leading, spacing: 6) {
            Text("How time saved is worked out").font(.esy(13, .semibold))
            Text("Typing \(summary.words) words at \(Int(typingWPM)) wpm: \(Self.duration(typing))")
            Text("minus speaking: \(Self.duration(summary.spokenSeconds))")
            Text("minus waiting for the text: \(Self.duration(summary.processingSeconds))")
            Text("= \(Self.duration(summary.secondsSaved(typingWPM: typingWPM))) saved").font(.esy(13, .semibold))
        }
        .font(.esy(12))
    }

    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
    }

    static func day(_ key: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        return parser.date(from: key).map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? key
    }
}
