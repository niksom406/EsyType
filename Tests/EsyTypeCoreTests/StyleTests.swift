import EsyTypeCore
import Testing

// Simulated: the Windows Style page's own example, which the Mac must reproduce exactly.
private func styled(_ style: WritingStyle, _ text: String = StyleEngine.sample, custom: StyleRules = StyleRules()) -> String {
    StyleEngine.apply(text, rules: StyleRules.preset(style, custom: custom), language: "en")
}

@Test func theWindowsExampleInEveryStyle() {
    #expect(styled(.standard) == "Yeah I'm gonna send it tomorrow in order to check, basically.")
    #expect(styled(.professional) == "Yes, I'm going to send it tomorrow in order to check, basically.")
    #expect(styled(.formal) == "Yes, I am going to send it tomorrow in order to check, basically.")
    #expect(styled(.casual) == "Yeah I'm gonna send it tomorrow in order to check, basically")
    #expect(styled(.concise) == "Yeah I'm gonna send it tomorrow to check.")
    #expect(styled(.custom) == styled(.standard))
}

@Test func styleRulesAreCarefulWithWords() {
    #expect(styled(.professional, "Gonna call you, yeah.") == "Going to call you, yes.")
    // Mixed apostrophes: each one-meaning contraction expands; "It's" (two meanings) keeps its own apostrophe.
    #expect(styled(.formal, "It's fine, don't worry, I’ll do it") == "It's fine, do not worry, I will do it.")
    #expect(styled(.professional, "The gonnagram stays") == "The gonnagram stays.") // whole words only
    #expect(styled(.casual, "First one. Second one.") == "First one. Second one.") // two sentences keep their stop
    #expect(styled(.concise, "Basically, we ship today.") == "We ship today.")
    #expect(styled(.concise, "We are, honestly, ready.") == "We are, ready.")
    #expect(StyleEngine.apply("ठीक है gonna", rules: StyleRules.preset(.professional, custom: StyleRules()), language: "hi") == "ठीक है gonna")
}

@Test func customFullStopChoices() {
    #expect(styled(.custom, "Done", custom: StyleRules(fullStop: .always)) == "Done.")
    #expect(styled(.custom, "Really?", custom: StyleRules(fullStop: .always)) == "Really?")
    #expect(styled(.custom, "Done.", custom: StyleRules(fullStop: .never)) == "Done")
    #expect(styled(.custom, "Wait...", custom: StyleRules(fullStop: .never)) == "Wait...")
}

@Test func eachAppGetsItsStyle() {
    var settings = StyleSettings()
    #expect(settings.style(for: "com.apple.mail") == .professional)
    #expect(settings.style(for: "com.tinyspeck.slackmacgap") == .casual)
    #expect(settings.style(for: "com.apple.TextEdit") == .standard)
    settings.otherApps = .concise
    #expect(settings.style(for: nil) == .concise)
}
