import EsyTypeCore
import SwiftUI

/// Insights, laid out as in the Windows design: four figures, an activity heatmap, this week by day and by kind
/// of app. Everything is worked out on this Mac from daily totals (numbers only, no text).
struct InsightsView: View {
    let insights: InsightsModel
    @AppStorage(Pref.typingWPM) private var typingWPM = 40.0
    @State private var showWorking = false

    private static let weeks = 18
    private var calendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c } // weeks start on Monday

    var body: some View {
        let all = insights.log.summary()
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                PageTitle("Insights")
                Text("Your own numbers, worked out on this Mac. They stay even when History is off or trimmed.")
                    .font(.esy(14)).foregroundStyle(Brand.inkTertiary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { tiles(all) }
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    let views = tileViews(all)
                    GridRow { views[0]; views[1] }
                    GridRow { views[2]; views[3] }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    activity.frame(minWidth: 420)
                    thisWeek.frame(width: 330)
                }
                .fixedSize(horizontal: false, vertical: true) // both cards as tall as the taller one
                VStack(spacing: 12) { activity; thisWeek }
            }
            HStack(spacing: 14) {
                Text("App kinds come from the app’s identifier only. EsyType never reads window titles or what you write for Insights.")
                    .font(.esy(12)).foregroundStyle(Brand.inkTertiary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Stepper("Typing speed \(Int(typingWPM)) wpm", value: $typingWPM, in: 10...150, step: 5)
                    .font(.esy(12)).fixedSize()
            }
        }
    }

    // MARK: Tiles

    @ViewBuilder private func tiles(_ all: InsightsSummary) -> some View {
        ForEach(Array(tileViews(all).enumerated()), id: \.offset) { $0.element }
    }

    private func tileViews(_ all: InsightsSummary) -> [AnyView] {
        [
            AnyView(tile(all.words.formatted(), "Words dictated", all.since.map { "since \(Self.day($0))" } ?? "none yet")),
            AnyView(tile("\(all.wordsPerMinute)", "Words per minute", "speaking, not typing")),
            AnyView(tile(Self.duration(all.secondsSaved(typingWPM: typingWPM)), "Time saved", "at \(Int(typingWPM)) wpm typing") {
                Button("How?") { showWorking.toggle() }.buttonStyle(.plain).font(.esy(12, .semibold)).foregroundStyle(Brand.accentInk)
                    .popover(isPresented: $showWorking) { working(all).padding(16).frame(width: 300) }
            }),
            AnyView(tile("—", "Meetings transcribed", "comes with EsyMeet")),
        ]
    }

    private func tile(_ value: String, _ label: String, _ note: String) -> some View { tile(value, label, note) { EmptyView() } }

    private func tile(_ value: String, _ label: String, _ note: String, @ViewBuilder extra: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.esy(28, .semibold)).monospacedDigit().tracking(-0.3).lineLimit(1).minimumScaleFactor(0.7)
            Text(label.uppercased()).font(.esy(10.5, .semibold)).tracking(1.1).foregroundStyle(Brand.inkTertiary)
            HStack(spacing: 6) { Text(note).font(.esy(12)).foregroundStyle(Brand.inkTertiary); extra() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16).padding(.horizontal, 18)
        .esyGlassCard(cornerRadius: 16, padded: false)
        .accessibilityElement(children: .combine)
    }

    // MARK: Activity heatmap

    private var activity: some View {
        let today = calendar.startOfDay(for: Date())
        let weekday = (calendar.component(.weekday, from: today) + 5) % 7 // Monday 0 … Sunday 6
        let start = calendar.date(byAdding: .day, value: -(weekday + (Self.weeks - 1) * 7), to: today)!
        let days = insights.log.wordsPerDay(count: weekday + 1 + (Self.weeks - 1) * 7, endingOn: today, calendar: calendar)
        let busiest = days.map(\.words).max() ?? 0
        let active = days.filter { $0.words > 0 }.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity").font(.esy(14, .semibold))
                Text("\(active) active \(active == 1 ? "day" : "days") in \(Self.weeks) weeks").font(.esy(12)).foregroundStyle(Brand.inkTertiary)
                Spacer()
                legend
            }
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(["Mon", "", "Wed", "", "Fri", "", ""][row]).font(.esy(10)).foregroundStyle(Brand.inkTertiary)
                            .frame(width: 28, height: 14, alignment: .leading)
                    }
                }
                ForEach(0..<Self.weeks, id: \.self) { week in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { row in
                            let index = week * 7 + row
                            let date = calendar.date(byAdding: .day, value: index, to: start)!
                            if date > today {
                                Color.clear.frame(height: 14)
                            } else {
                                let words = index < days.count ? days[index].words : 0
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Brand.heat[InsightsLog.heatLevel(words: words, busiest: busiest)])
                                    .frame(height: 14)
                                    .help("\(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))): \(words.formatted()) words")
                            }
                        }
                    }
                    .frame(maxWidth: 22)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Activity: \(active) \(active == 1 ? "day" : "days") with dictation in the last \(Self.weeks) weeks; busiest day \(busiest) words")
            Spacer(minLength: 0)
            Rectangle().fill(Brand.hairline).frame(height: 1)
            let best = days.max { $0.words < $1.words }
            HStack(spacing: 0) {
                mini("\(insights.log.streak())", "day streak")
                mini(best.map { $0.words > 0 ? $0.date.formatted(.dateTime.day().month(.abbreviated)) : "—" } ?? "—",
                     "busiest day\(busiest > 0 ? " · \(busiest.formatted()) words" : "")")
                mini(active > 0 ? (days.map(\.words).reduce(0, +) / active).formatted() : "—", "words a day when active")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .esyGlassCard()
    }

    private func mini(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.esy(17, .semibold)).monospacedDigit()
            Text(label).font(.esy(11.5)).foregroundStyle(Brand.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less").font(.esy(10)).foregroundStyle(Brand.inkTertiary)
            ForEach(0..<5, id: \.self) { RoundedRectangle(cornerRadius: 2).fill(Brand.heat[$0]).frame(width: 10, height: 10) }
            Text("More").font(.esy(10)).foregroundStyle(Brand.inkTertiary)
        }
        .accessibilityHidden(true)
    }

    // MARK: This week

    private var thisWeek: some View {
        let today = calendar.startOfDay(for: Date())
        let weekday = (calendar.component(.weekday, from: today) + 5) % 7
        let week = insights.log.wordsPerDay(count: weekday + 1, endingOn: today, calendar: calendar).map(\.words)
            + Array(repeating: -1, count: 6 - weekday) // days still to come
        let busiest = max(1, week.max() ?? 1)
        let shares = insights.log.categoryShares()
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").font(.esy(14, .semibold))
                Spacer()
                Text("\(week.filter { $0 > 0 }.reduce(0, +).formatted()) words").font(.esy(12)).foregroundStyle(Brand.inkTertiary)
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<7, id: \.self) { day in
                    let words = week[day], isToday = day == weekday
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(words < 0 ? Color.clear : isToday ? Brand.accent : Brand.accentSoft)
                            .overlay(RoundedRectangle(cornerRadius: 5)
                                .stroke(words < 0 ? Brand.hairline : Brand.accent.opacity(isToday ? 0 : 0.4),
                                        style: StrokeStyle(lineWidth: 1, dash: words < 0 ? [3] : [])))
                            .frame(height: words <= 0 ? 6 : max(8, 72 * CGFloat(words) / CGFloat(busiest)))
                            .help(words < 0 ? "" : "\(words.formatted()) words")
                        Text(["M", "T", "W", "T", "F", "S", "S"][day]).font(.esy(10.5, isToday ? .semibold : .regular))
                            .foregroundStyle(isToday ? Brand.ink : Brand.inkTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 92, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("This week: " + (0...weekday).map { "\(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][$0]) \(max(0, week[$0])) words" }.joined(separator: ", "))
            Rectangle().fill(Brand.hairline).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                if shares.isEmpty {
                    Text("Dictate into a few apps and the split by kind of app appears here.")
                        .font(.esy(12)).foregroundStyle(Brand.inkTertiary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(shares, id: \.0) { category, share in
                    HStack(spacing: 10) {
                        Text(category.rawValue).font(.esy(13)).frame(width: 104, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Brand.surfaceRaised)
                                Capsule().fill(Brand.accent).frame(width: max(6, geo.size.width * share))
                            }
                        }
                        .frame(height: 8)
                        Text(share.formatted(.percent.precision(.fractionLength(0)))).font(.esy(13)).monospacedDigit()
                            .foregroundStyle(Brand.inkSecondary).frame(width: 40, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .esyGlassCard()
    }

    // MARK: Helpers

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
