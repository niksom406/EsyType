import AppKit
import EsyTypeCore
import Carbon.HIToolbox

/// UserDefaults keys for every preference. Nothing sensitive is stored in UserDefaults.
enum Pref {
    static let modelID = "modelID" // "" = the recommended model
    static let language = "language" // "" = auto-detect
    static let translate = "translateToEnglish"
    static let removeFillers = "removeFillers" // Text Cleanup ▸ fillers (key kept from Phase 7)
    static let cleanRepeatedWords = "cleanRepeatedWords"
    static let cleanRepeatedPhrases = "cleanRepeatedPhrases"
    static let cleanPunctuation = "cleanPunctuation"
    static let cleanCapitalisation = "cleanCapitalisation"
    static let historyDays = "historyDays" // 0 = forever, -1 = don't keep history
    static let saveSourceApp = "saveSourceApp"
    static let holdKey = "holdKey"
    static let toggleShortcut = "toggleShortcut"
    static let doubleTap = "doubleTapHandsFree"
    static let typingWPM = "insightsTypingWPM"
    static let dictionaryHints = "dictionaryHints" // off by default, as on Windows (slower, sometimes misplaced words)
    static let builtInNames = "builtInProductNames"
    static let userName = "userName" // About you: labels your lines in meeting transcripts
    static let meetingName = "meetingName"
    static let microphoneUID = "microphoneUID" // "" = system default
    static let startSound = "startSound"
    static let stopSound = "stopSound"
    static let soundVolume = "soundVolume" // 0...1
    static let noSpeechWarning = "noSpeechWarning"
    static let silenceSeconds = "silenceSeconds"
    static let maxRecordingSeconds = "maxRecordingSeconds" // ADR-17: 20 min default, 30 min hard cap

    static var cleanupOptions: CleanupOptions {
        let d = UserDefaults.standard
        return CleanupOptions(fillers: d.bool(forKey: removeFillers), repeatedWords: d.bool(forKey: cleanRepeatedWords),
                              repeatedPhrases: d.bool(forKey: cleanRepeatedPhrases), punctuation: d.bool(forKey: cleanPunctuation),
                              capitalisation: d.bool(forKey: cleanCapitalisation))
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            modelID: "", language: "", translate: false, removeFillers: true,
            cleanRepeatedWords: true, cleanRepeatedPhrases: true, cleanPunctuation: true, cleanCapitalisation: true,
            historyDays: 30, saveSourceApp: true,
            holdKey: HoldKey.rightOption.rawValue, toggleShortcut: ToggleShortcut.controlOptionSpace.rawValue,
            doubleTap: true, typingWPM: 40.0, dictionaryHints: false, builtInNames: true, userName: "", meetingName: "", microphoneUID: "", startSound: true, stopSound: true, soundVolume: 0.5,
            noSpeechWarning: true, silenceSeconds: 5, maxRecordingSeconds: 20 * 60,
        ])
    }
}

/// The key held for push-to-talk. Watched by a listen-only event tap (Input Monitoring).
enum HoldKey: String, CaseIterable, Identifiable {
    case rightOption, rightCommand, off
    var id: Self { self }

    static var current: HoldKey { HoldKey(rawValue: UserDefaults.standard.string(forKey: Pref.holdKey) ?? "") ?? .rightOption }

    var title: String {
        switch self {
        case .rightOption: "Right ⌥ Option"
        case .rightCommand: "Right ⌘ Command"
        case .off: "Off"
        }
    }
    var keyCap: String? { self == .off ? nil : self == .rightOption ? "Right ⌥" : "Right ⌘" }
    var keyCode: Int64 { self == .rightCommand ? Int64(kVK_RightCommand) : Int64(kVK_RightOption) }
    /// NX_DEVICE*KEYMASK bits: this key, and the same key on the left.
    var deviceMask: UInt64 { self == .rightCommand ? 0x10 : 0x40 }
    var leftDeviceMask: UInt64 { self == .rightCommand ? 0x08 : 0x20 }
    var flag: CGEventFlags { self == .rightCommand ? .maskCommand : .maskAlternate }
}

/// The press-to-start, press-to-stop shortcut. A Carbon hot key (no permission needed).
enum ToggleShortcut: String, CaseIterable, Identifiable {
    case controlOptionSpace, controlShiftSpace, optionSpace, off
    var id: Self { self }

    static var current: ToggleShortcut {
        ToggleShortcut(rawValue: UserDefaults.standard.string(forKey: Pref.toggleShortcut) ?? "") ?? .controlOptionSpace
    }

    var title: String {
        switch self {
        case .controlOptionSpace: "⌃⌥Space"
        case .controlShiftSpace: "⌃⇧Space"
        case .optionSpace: "⌥Space"
        case .off: "Off"
        }
    }
    var keyCap: String? { self == .off ? nil : title }
    var carbonModifiers: UInt32 {
        switch self {
        case .controlOptionSpace: UInt32(controlKey | optionKey)
        case .controlShiftSpace: UInt32(controlKey | shiftKey)
        case .optionSpace: UInt32(optionKey)
        case .off: 0
        }
    }
}
