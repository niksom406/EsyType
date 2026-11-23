import AppKit
import EsyTypeCore
import SwiftUI

/// Main window ▸ Style: how dictated text is finished in each app, plus the Clean rules that run first.
struct StylePage: View {
    let history: HistoryModel
    @State private var model = StyleModel()
    @State private var sample = StyleEngine.sample
    @State private var newApp = ""
    @State private var newStyle = WritingStyle.professional
    @State private var query = ""
    @AppStorage(Pref.removeFillers) private var fillers = true
    @AppStorage(Pref.cleanRepeatedWords) private var repeatedWords = true
    @AppStorage(Pref.cleanRepeatedPhrases) private var repeatedPhrases = true
    @AppStorage(Pref.cleanPunctuation) private var punctuation = true
    @AppStorage(Pref.cleanCapitalisation) private var capitalisation = true

    private var settings: StyleSettings { model.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle("Style")
            PageHero("style", headline: Text("Write like ") + Text("you").italic() + Text(", in every app."),
                     message: "EsyType finishes your words in the style you set for each app: written-out forms for email, chat-style for messages. It never changes your tone or rewrites sentences.") {
                ForEach([WritingStyle.professional, .casual, .concise], id: \.self) { style in
                    HeroChip(style.title) { model.settings.otherApps = style }
                }
            }
            stylesCard
            appsCard
            customCard
            cleanCard
            tryCard
        }
    }

    // MARK: Styles

    private var stylesCard: some View {
        SectionCard("Styles") {
            Text("Click a style to use it for every app without its own rule. Examples show the same sentence in each style.")
                .font(.esy(13)).foregroundStyle(Brand.inkTertiary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                ForEach(WritingStyle.allCases) { style in
                    StyleCard(style: style, example: example(style, StyleEngine.sample),
                              isDefault: settings.otherApps == style,
                              apps: settings.apps.filter { $0.style == style }.count) {
                        withAnimation(.easeInOut(duration: 0.2)) { model.settings.otherApps = style }
                    }
                }
            }
            HStack(spacing: 10) {
                FieldLabel("Style for other apps")
                Picker("Style for other apps", selection: $model.settings.otherApps) {
                    ForEach(WritingStyle.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
        }
    }

    private func example(_ style: WritingStyle, _ text: String) -> String {
        StyleEngine.apply(text, rules: StyleRules.preset(style, custom: settings.custom), language: "en")
    }

    // MARK: Apps

    private var appsCard: some View {
        let rules = settings.apps.filter { query.isEmpty || name($0.app).localizedStandardContains(query) }
        return SectionCard(title: "Apps", count: settings.apps.count) { EmptyView() } content: {
            SearchField(prompt: "Search apps", text: $query)
            VStack(spacing: 0) {
                ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                    if index > 0 { Rectangle().fill(Brand.hairline).frame(height: 1) }
                    HStack(spacing: 12) {
                        appIcon(rule.app)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name(rule.app)).font(.esy(15, .semibold))
                            if AppInfo.name(rule.app) == nil {
                                Text("Not installed").font(.esy(11.5)).foregroundStyle(Brand.inkTertiary)
                            }
                        }
                        Spacer()
                        Picker("Style for \(name(rule.app))", selection: binding(for: rule.app)) {
                            ForEach(WritingStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        IconAction(symbol: "trash", label: "Remove \(name(rule.app))", danger: true) {
                            model.settings.apps.removeAll { $0.app == rule.app }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
            .background(Brand.surfaceRaised.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.hairline))
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("App")
                    Picker("App", selection: $newApp) {
                        Text("Choose an app…").tag("")
                        ForEach(candidates, id: \.self) { Text(name($0)).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel("Style")
                    Picker("Style", selection: $newStyle) { ForEach(WritingStyle.allCases) { Text($0.title).tag($0) } }
                        .labelsHidden().fixedSize()
                }
                Spacer()
                AccentButton(title: "Add rule", enabled: !newApp.isEmpty) {
                    model.settings.apps.append(AppStyle(app: newApp, style: newStyle))
                    newApp = ""
                }
            }
            Text("Apps are recognised by their identifier only, never by window titles, so a browser has one style for every website. Suggestions come from apps in your History and apps that are open.")
                .font(.esy(12)).foregroundStyle(Brand.inkTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var candidates: [String] {
        let configured = Set(settings.apps.map(\.app))
        let open = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier)
        let used = history.entries.compactMap(\.appBundleID)
        return Array(Set(open + used)).filter { !configured.contains($0) && $0 != Bundle.main.bundleIdentifier }
            .sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
    }

    private func name(_ app: String) -> String { AppInfo.displayName(app) }

    private func appIcon(_ app: String) -> some View {
        Group {
            if let icon = AppInfo.icon(app) { Image(nsImage: icon).resizable() }
            else { Image(systemName: "app.dashed").resizable().foregroundStyle(Brand.inkTertiary) }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }

    private func binding(for app: String) -> Binding<WritingStyle> {
        Binding(get: { settings.style(for: app) }, set: { style in
            if let index = model.settings.apps.firstIndex(where: { $0.app == app }) { model.settings.apps[index].style = style }
        })
    }

    // MARK: Custom, Clean, Try it

    private var customCard: some View {
        SectionCard("Custom style") {
            SwitchRow("Write out spoken forms (“gonna” → “going to”, “yeah” → “yes”)", isOn: $model.settings.custom.spokenForms)
            SwitchRow("Expand contractions with one meaning (“don’t” → “do not”)", isOn: $model.settings.custom.expandContractions)
            SwitchRow("Shorten stock phrases (“in order to” → “to”)", isOn: $model.settings.custom.shortenPhrases)
            SwitchRow("Drop “basically”, “actually”, “literally”, “honestly” when set off by commas", isOn: $model.settings.custom.dropFillerAdverbs)
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("Full stop at the end")
                Picker("Full stop at the end", selection: $model.settings.custom.fullStop) {
                    ForEach([FullStop.asSpoken, .always, .never]) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
        }
        .toggleStyle(.switch)
        .font(.esy(14))
    }

    private var cleanCard: some View {
        SectionCard("Clean, before any style") {
            Text("Clean runs first in every app: it removes noise and fixes layout. Links, emails, code and numbers are never changed.")
                .font(.esy(13)).foregroundStyle(Brand.inkTertiary).fixedSize(horizontal: false, vertical: true)
            rule("Remove filler words", "“um, uh, erm”, and “hmm” on its own → removed. English only.", $fillers)
            rule("Remove repeated words", "“the the cat” → “the cat”. Keeps “very very”, “bye bye.”, numbers. English only.", $repeatedWords)
            rule("Remove repeated phrases", "“I think, I think we should go” → “I think we should go”. Keeps echoes. English only.", $repeatedPhrases)
            rule("Fix punctuation and spacing", "“Hello , world .How” → “Hello, world. How”. Keeps “...”, “?!” and paragraphs.", $punctuation)
            rule("Capitalise sentences", "“hello. how are you” → “Hello. How are you”. Leaves iPhone and NASA alone.", $capitalisation)
        }
    }

    private func rule(_ title: String, _ example: String, _ isOn: Binding<Bool>) -> some View {
        SwitchRow(title, detail: example, isOn: isOn)
    }

    private var tryCard: some View {
        SectionCard("Try it") {
            TextEditor(text: $sample).font(.esy(15)).scrollContentBackground(.hidden).padding(10).frame(height: 80)
                .background(Brand.surfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.hairlineStrong))
                .accessibilityLabel("Sentence to try")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(WritingStyle.allCases) { style in
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel(style.title)
                        Text(example(style, sample)).font(.esy(14)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Brand.surfaceRaised.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

/// One style: name, what it does, the example sentence; accent edge when it's the style for other apps.
private struct StyleCard: View {
    let style: WritingStyle
    let example: String
    let isDefault: Bool
    let apps: Int
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(style.title).font(.esy(19, .semibold))
                    Spacer()
                    if isDefault {
                        Text("Other apps").font(.esy(11, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Brand.accent, in: Capsule())
                    } else if apps > 0 {
                        Text("\(apps) \(apps == 1 ? "app" : "apps")").font(.esy(11, .semibold)).foregroundStyle(Brand.inkSecondary)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Brand.surfaceRaised, in: Capsule())
                    }
                }
                Text(style.summary).font(.esy(13)).foregroundStyle(Brand.inkTertiary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Rectangle().fill(Brand.hairline).frame(height: 1)
                Text(example).font(.esy(14)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .padding(18)
            .background(isDefault ? Brand.accentSoft : (hovering ? Brand.surfaceRaised.opacity(0.7) : Brand.surfaceRaised.opacity(0.4)),
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isDefault ? Brand.accent : Brand.hairline, lineWidth: isDefault ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isDefault ? .isSelected : [])
        .accessibilityHint("Use for apps without their own rule")
    }
}
