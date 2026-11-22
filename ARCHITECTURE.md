# EsyType architecture

Status: **as built, 0.1.0 beta (2026-11-22)**. This page describes the code as it is. Decisions and how they changed are recorded as ADRs in §7; where an early ADR and this page disagree, this page and the later ADR are current.

## 1. Goals that shape the design

1. Inference is **always local**. The network is used only to download the models the user chooses.
2. The speech engine sits behind **one small module** (`WhisperEngine`), so it can be replaced without touching the UI.
3. It runs on **Apple Silicon and Intel** within measured limits (Intel is built but not yet tested on real hardware).
4. **Minimal dependencies** (Ponytail): whisper.cpp is the only third-party runtime dependency.
5. **Testable core**: logic lives in `EsyTypeCore`, which `Scripts/test.sh` tests without any window.

## 2. System overview

```
                 ┌──────────────────────── EsyType.app (one process, menu-bar agent) ──────────────────────────┐
 shortcut ─────▶ │ Hotkeys ──▶ DictationController (@MainActor) ── rules in DictationMachine (pure, tested)      │
 (Carbon /       │               ├─▶ AudioRecorder (AVAudioEngine → 16 kHz mono Float32, in memory) ─▶ overlay   │
  event tap)     │               ├─▶ WhisperCppEngine (actor) ── whisper.framework (C API, Metal / CPU)           │
                 │               ├─▶ TextCleanup ─▶ HistoryModel ─▶ HistoryStore (SQLite, 0600)                 │
                 │               └─▶ TextInserter (AX focus check → pasteboard + ⌘V → restore; else copy)       │
                 │ ModelLibrary ─▶ ModelStore (URLSession download, SHA-256, atomic install) · Recommender       │
                 │ Permissions · Preferences (UserDefaults) · AppDelegate (status item, menu) · SwiftUI windows   │
                 └────────────────────────────────────────────────────────────────────────────────────────────────┘
```

## 3. Project layout (actual)

```
Package.swift              swift-tools 6.0, macOS 14; whisper pinned by URL + SHA-256 (binaryTarget)
Sources/
  EsyTypeCore/             logic with no windows: AudioRecorder, DictationMachine, Hardware (detector, DiskSpace),
                           HistoryStore, LevelMeter, ModelStore, Pasteboard (snapshot, ⌘V key), Recommender
                           (+ ModelCatalog), TextCleanup. Imports Foundation/AVFoundation/AppKit (pasteboard only).
  WhisperEngine/           WhisperEngine.swift: the ONLY code that imports whisper.cpp
  EsyType/                 the app
    App/                   main.swift, AppDelegate (menu, launch), WindowController, Permissions, Preferences,
                           Snapshots (Debug only)
    Dictation/             DictationController, Hotkeys, TextInserter
    DesignSystem/          Brand (tokens, fonts), Components (glass, buttons, bars, keycaps)
    History/ Models/ Onboarding/ Overlay/ Windows/   SwiftUI screens and the overlay panel
Tests/
  EsyTypeCoreTests/        unit tests (Swift Testing)
  WhisperEngineTests/      engine tests; model tests run only for installed models; benchmarks are opt-in
    Fixtures/jfk.wav       11 s English clip (Hindi/Marathi clips still needed)
Resources/                 Fonts (OFL), Licences, AppIcon.icns
Support/                   Info.plist, EsyType.entitlements
Scripts/                   build-app.sh, make-dmg.sh, test.sh, privacy-check.sh, make-icon.swift
```

**Why a package rather than an `.xcodeproj`:** it builds and tests with the Command Line Tools (no Xcode on the development Mac). Xcode can open `Package.swift` directly later. See ADR-1.

## 4. Key components

### Speech engine boundary

`WhisperCppEngine` (actor) is the only type that touches whisper.cpp: `init(model:useGPU:threads:)`, `transcribe(_:language:translate:) -> Transcript`, `languages`. Only `DictationController` and the language list in Settings use it, and no C types leave the module. There is no `SpeechEngine` protocol: with one engine it would be an abstraction with a single implementation (Ponytail). Swapping engines means replacing this module and the two call sites, not the UI.

- `whisper_full` is a blocking call. It runs on the actor's executor (Swift's shared thread pool) for the length of the decode. Acceptable with one dictation at a time; a dedicated thread is the upgrade if more work runs concurrently.
- GPU: Metal on Apple Silicon (including under Rosetta). Intel: CPU with all physical cores (ADR-16).
- Model loaded on the first dictation (while the user speaks), unloaded after 10 idle minutes or on memory pressure.
- Not implemented: `abort_callback` (Esc during transcription drops the result but the decode finishes), voice-activity detection (VAD).

### AudioRecorder

`AVAudioEngine` input tap, converted by `AVAudioConverter` to 16 kHz mono Float32 (fed in the slice sizes the converter requests, ADR-13) and kept in memory, capped at the user's limit (default 20 minutes, hard cap 30 minutes ≈ 115 MB, ADR-17). Records from the chosen microphone (Core Audio UID) or follows the system default; a fresh `AVAudioEngine` per recording. Publishes a level per tap buffer (~20–25×/s). On an input configuration change it reinstalls the tap on the new input and keeps recording; it stops only when no input is left. **Nothing is written to disk.**

### Hotkeys

- **Hands-free toggle** (⌃⌥Space by default), **Esc** (only while dictating) and **⌃⌘V**: Carbon `RegisterEventHotKey`, no permission needed. If a shortcut can't be registered, the overlay says so.
- **Hold key** (Right ⌥ or Right ⌘): a listen-only `CGEventTap` on `flagsChanged`/`keyDown`, which needs **Input Monitoring**. It retries every 2 s until permission is given.
- Not implemented: `IsSecureEventInputEnabled()` detection, a free-form shortcut recorder (presets instead, ADR-15).

### TextInserter

1. Paste only if the app from recording start is still frontmost, Accessibility is allowed, the app reports a focused element (0.5 s AX timeout) and it isn't a password field. Otherwise copy and show "Copied".
2. Snapshot every pasteboard item and type, write the transcript marked transient + concealed, post ⌘V (layout-aware key) to that app.
3. After 500 ms, restore the snapshot only if the clipboard is still ours (ADR-14).

### Models

- `ModelCatalog`: the four recommendable files from `MODEL_REGISTRY.md` (bytes, SHA-256, pinned URL), checked against the registry by a test.
- `HardwareDetector`: architecture, Rosetta, CPU brand, physical memory, physical cores, free disk, macOS version. Not detected: available memory, Metal family.
- `Recommender`: pure function of the hardware profile and optional benchmarks. The app passes no benchmarks yet, so Turbo is never recommended automatically and Intel always gets Base.
- `ModelStore` (actor): streams to `.partial/<file>.part`, resumes with HTTP Range, retries transient errors, refuses duplicates, checks disk space, verifies exact size + SHA-256, installs by rename, writes `registry.json` (ADR-12).

### HistoryStore

System SQLite, WAL, files `0600`, columns id, created_at, text, language, duration_ms, model_id, app_bundle_id. Search is a substring scan (ADR-15). Retention is applied before every read and after every save.

### Settings

`UserDefaults` (`Preferences.swift` keys, `@AppStorage` in views). Nothing sensitive is stored there.

## 5. Concurrency model (Swift 6 strict, no warnings)

- UI, `DictationController`, `Hotkeys`, `ModelLibrary`, `HistoryModel`: `@MainActor`.
- `WhisperCppEngine`, `ModelStore`, `HistoryStore`: actors.
- Audio tap callback (an AVAudioEngine thread, not the real-time I/O thread): converts each buffer and appends under an `OSAllocatedUnfairLock`. It allocates per buffer, which is acceptable on this thread.
- Carbon and event-tap callbacks arrive on the main run loop and use `MainActor.assumeIsolated`.

## 6. Security and privacy architecture

- Network: only `ModelStore` (HTTPS, pinned Hugging Face revision, SHA-256 verified). No update checks, analytics or telemetry. `Scripts/privacy-check.sh` checks this.
- Logging: stages, timings and error messages only, never transcripts or audio. whisper.cpp's own logging and printing are switched off.
- Audio stays in memory and is released after transcription. History is a local `0600` SQLite file the user can clear.
- Hardened Runtime, non-sandboxed. Entitlements: `com.apple.security.device.audio-input`; builds not signed with a Developer ID also get `com.apple.security.cs.disable-library-validation` (ADR-13). Not notarised (owner's decision, 2026-11-22).

## 7. ADRs

### ADR-1: Build with Swift Package Manager, assemble the .app by script

- **Problem:** Xcode isn't installed, and only ~0.7–2.5 GB of disk is free (Xcode needs tens of GB). XCTest and `actool` aren't in the Command Line Tools. Swift Testing and `notarytool` are (verified).
- **Options:** (a) install Xcode and use an `.xcodeproj`; (b) SwiftPM + build script; (c) Tuist/XcodeGen (extra dependency).
- **Choice:** (b) now, and Xcode can open the package later with no migration.
- **Downsides:** no XCUITest without Xcode (UI tests become manual checklists plus snapshot-free logic tests), no asset catalogue (use `.icns` via `iconutil` and plain PNGs), and a hand-written Info.plist and signing script.
- **Migration:** if UI automation becomes essential, add an Xcode app target that depends on the same package.

### ADR-2: Minimum macOS 14 Sonoma

- whisper.cpp XCFramework minimum is 13.3 (verified via `LC_BUILD_VERSION`). The Observation framework (`@Observable`) and modern SwiftUI need 14. macOS 14 still supports many Intel Macs (2018+).
- Liquid Glass styling is used on macOS 26 with a material fallback on 14–15.

### ADR-3: whisper.cpp via the official prebuilt XCFramework

- Verified the `b5454` (v1.9.5-era) XCFramework: it contains a **`macos-arm64_x86_64`** slice (universal), headers `whisper.h`, `ggml-metal.h`, `ggml-cpu.h`, `ggml-blas.h`, and a GitHub-published SHA-256 `e57f8c48…92393b`.
- **Options:** XCFramework `binaryTarget` (pinned checksum) vs building from source with CMake (not installed) vs WhisperKit (Core ML, Apple Silicon only, no Intel).
- **Choice:** XCFramework, pinned by URL + checksum.
- **As built (Phase 4):** `Package.swift` `binaryTarget(name: "whisper")` with the b5454 URL and SHA-256, so SwiftPM verifies it on every resolve. The macOS slice is a universal dynamic framework (46 MB unzipped, links Metal, Accelerate and CoreML). `WhisperEngine` is the only target that depends on it. The app target doesn't link it until Phase 5, when `Scripts/build-app.sh` must copy `whisper.framework` into `Contents/Frameworks` and add an `@executable_path/../Frameworks` rpath.
- **Downsides:** a binary dependency, and we trust the upstream CI build. Mitigation: pin the version and verify the checksum. Option to build from source for release once Xcode/CMake are available.
- **Not chosen:** Apple `SpeechTranscriber` (macOS 26), because on this Mac it supports 30 locales with **no Hindi or Marathi** (verified). It could be a future optional engine for supported languages.

### ADR-4: SQLite3 (system) for history, not SwiftData

- Full-text search (FTS5), predictable migrations and simple testing. Zero dependencies. About 150 lines.
- SwiftData would avoid SQL but adds actor/`ModelContext` complexity under Swift 6 and has weaker search support.

### ADR-5: Hotkeys via Carbon RegisterEventHotKey + optional listen-only CGEventTap

- Carbon gives press/release for combinations with **no permission**. It's still the documented system-wide hotkey API on macOS.
- Modifier-only holds need an event tap (Input Monitoring). That's opt-in.
- Fn/🌐 and mouse buttons use `IOHIDManager` raw input (also Input Monitoring).
- The shortcut recorder rejects: too many keys, missing modifier (for combinations), left/right duplicates, combinations already registered, overlap between the push-to-talk and toggle shortcuts.
- Rejected: `NSEvent.addGlobalMonitorForEvents` (needs Accessibility, and can't consume events).

### ADR-6: Insert by pasteboard + synthetic ⌘V, with snapshot/restore

- The most compatible method across native, Electron and web apps. Wispr Flow's docs describe the same approach (temporary clipboard use, then restore).
- Additions from that research: post ⌘V to the PID captured when recording started (`CGEventPostToPid`), and keep a small per-app list that goes straight to the clipboard fallback (for example remote-desktop clients).
- Deliberately not adopted: reading surrounding text through `AXTextMarker` and tracking edits after insertion. Local Whisper doesn't need them, and they conflict with EsyType's privacy promise.
- Downsides: needs Accessibility, a brief clipboard change, and some apps block paste. Mitigations are described in §4.

### ADR-7: Developer ID distribution, non-sandboxed, Hardened Runtime

- App Sandbox prevents posting keyboard events and controlling other apps through Accessibility, which the core feature requires. So the Mac App Store is out of scope for MVP.
- Requires an Apple Developer Program membership (paid) for a Developer ID certificate and notarisation.

### ADR-8: No streaming partial results in MVP

- Push-to-talk utterances are short. Batch decoding on release is simpler and more accurate. Live partials can come later with `whisper_full` on sliding windows.

### ADR-10: AppKit app lifecycle with SwiftUI content (Phase 1)

- **Problem:** a menu-bar agent needs a status item, an onboarding window on first launch, a Settings window, and a non-activating floating panel. It must work on macOS 14.
- **Options:** (a) SwiftUI `App` with `MenuBarExtra`, `Window` and `Settings` scenes; (b) an AppKit `NSApplicationDelegate` (`main.swift`) that owns `NSStatusItem`, `NSWindow`/`NSPanel` hosting SwiftUI views.
- **Choice:** (b). It gives deterministic control of what opens at launch on macOS 14 (scene launch behaviour differs across 14/15/26). Opening Settings from an `NSMenu` works without `SettingsLink`. And the status-item icon can be animated later (Phase 5). Every screen is still SwiftUI.
- **Downsides:** a few dozen lines of window management. Settings is an `NSTabViewController` (toolbar style) rather than the SwiftUI `Settings` scene, but it looks the same.
- **Migration:** views are plain SwiftUI, so moving to scenes later only touches `AppDelegate`/`WindowController`.

### ADR-11: Toolchain limits without Xcode (Phase 1 findings)

- Swift Testing works with Command Line Tools, but only with extra search paths: use `Scripts/test.sh` (plain `swift test` fails with "no such module 'Testing'").
- SwiftUI's own macros (`@Entry`, `#Preview`) need Xcode's macro plugins and **don't compile**. Use classic `EnvironmentKey`. The Observation macro (`@Observable`) does work.
- Universal binary: `swift build --arch` is run once per architecture and merged with `lipo` (`Scripts/build-app.sh`).
- Visual checks: this session couldn't capture the screen, so Debug builds include `EsyType --render-snapshots <folder>` (offscreen PNGs). **Liquid Glass and the macOS 26 floating sidebar can't be captured offscreen**, so snapshots use the macOS 14–15 material fallback. Glass on screen still needs a manual look.

### ADR-12: Model downloads stream to a `.part` file and resume with an HTTP Range request (Phase 3)

- **Problem:** downloads must resume after a cancel, a crash or a dropped connection, with retries, a duplicate guard and exact size + SHA-256 checks.
- **Options:** `URLSessionDownloadTask` with resume data (as first planned) vs a data task that appends to `.partial/<file>.part` and sends `Range: bytes=<size>-` vs `URLSession.bytes` (byte-by-byte iteration, too slow for 874 MB).
- **Choice:** the data task (`ModelStore`, `Sources/EsyTypeCore/ModelStore.swift`). Resume works even after the app quits, because the state is just the partial file. A `206` response appends; any other success starts the file over. The finished file is hashed in 1 MB chunks (about a second for 874 MB), checked for exact size, then renamed into `Models/` (same volume, so atomic), and `registry.json` is written atomically.
- **Retries:** up to 3, after 2, 4 and 8 s, only for transient errors (timeouts, lost connection, offline, DNS, HTTP 429/5xx). A short response isn't retried; verification rejects it.
- **Downsides:** a server that ignores Range costs a full re-download (handled correctly, just slower). Partial files from cancelled downloads stay in `.partial/` until the download is resumed or the model is removed.
- **Migration:** none. `ModelStore` is the only code that writes in `Models/`.

### ADR-13: Phase 5 dictation pipeline decisions

- **Clipboard until Phase 6:** the transcript is copied (transient + concealed types) and the pill says "Copied". Pasting into the focused app needs Accessibility and the snapshot/restore logic of ADR-6.
- **Right ⌥ waits 150 ms** before the microphone starts, and is ignored with ⌘/⌃/⇧ or when another key follows. Without this every ⌥E or ⌥← flashed the mic indicator. Cost: speech in the first 150 ms of the hold is not captured.
- **Holds under 0.3 s are discarded** (`DictationMachine.minimumHold`).
- **Audio conversion feeds `AVAudioConverter` in the slice sizes it requests**: it reads at most 4,096 frames per callback and drops the rest of a larger buffer.
- **Model:** the recommended model if installed, else the first installed. Loaded on the first dictation while the user speaks, then kept loaded (`shortcut:` comment; idle unload in Phase 9).
- **Ad-hoc dev builds** get `com.apple.security.cs.disable-library-validation`, because library validation refuses an ad-hoc `whisper.framework` (no Team ID). Builds signed with a real identity (`ESYTYPE_SIGN_IDENTITY`) sign both with one team and don't get this entitlement.
- **Not done:** `abort_callback` (Esc during transcription drops the result but whisper.cpp finishes the current decode), secure-input detection, the double-tap latch.

### ADR-14: Phase 6 insertion decisions

- **When to paste:** the frontmost app is still the one from recording start, Accessibility is allowed, the app reports a focused element (0.5 s AX timeout), and it's not `AXSecureTextField`. Anything else copies instead. The focused element's role isn't checked further, because Chromium and Electron often report generic roles for editable text.
- **Restore after 500 ms** (not 250) because some apps read the clipboard late. Restore only if `changeCount` is still ours.
- **⌘V is posted with `.privateState` and explicit ⌘ flags**, so a modifier the user is still holding (⌃⌥ from the toggle) can't turn it into another shortcut.
- **Last transcript in memory only** (Paste Last Transcript, ⌃⌘V): if a paste lands nowhere, nothing is lost. History on disk comes in Phase 7.
- **The session ends before the paste starts**, so Esc can't interrupt the clipboard restore.
- `EsyTypeCore` now imports AppKit for `PasteboardSnapshot` (testable with a private pasteboard). It still has no windows or views.

### ADR-15: Phase 7 history and settings decisions

- **Search uses `instr(lower(text), lower(?))`, not FTS5.** FTS5's default tokenizer splits Devanagari at vowel signs, and one person's history is small enough to scan (`shortcut:` comment; FTS5 trigram if it ever isn't). Values are always bound, never put into SQL.
- **Columns:** id, created_at, text, language, duration_ms, model_id, app_bundle_id. `raw_text` and `latency_ms` from the plan were left out until something reads them (raw text matters only for Phase 8 refinement).
- **Saved before pasting** (PRD: "No lost transcript").
- **Shortcut presets instead of a recorder:** hold key Right ⌥ / Right ⌘ / Off, toggle ⌃⌥Space / ⌃⇧Space / ⌥Space / Off. A recorder would also need conflict detection and validation (ADR-5); presets cover the need with far less code. Changes apply immediately on any defaults change.
- **Defaults:** history 30 days, source app on, filler removal on (English only), language auto, translate off.

### ADR-16: Phase 9 performance decisions and an open question

- **Unload** after 10 idle minutes and on `DispatchSource` memory-pressure warnings, only when idle. Reload costs 0.1–0.8 s.
- **Backend:** Metal when `hw.optional.arm64` (including under Rosetta), CPU on Intel. Threads: whisper's default 4 with Metal (measured best), all physical cores on CPU (measured 19 % faster).
- **Open: idle memory after first use.** ggml keeps ~80 MB of Metal state and ~70 MB of other allocations for the life of the process, so the app idles at ~200 MB after its first dictation instead of the 80 MB target. Options: (a) accept it and change the target; (b) run whisper in an XPC helper that exits when idle (back to ~48 MB, costs a process launch + model load per first dictation, more code and signing work); (c) wait for upstream ggml to release Metal state. **Decision 2026-11-22 (owner): (a), accept ~200 MB.** Revisit with (b) if users report memory concerns.

### ADR-17: Stage 1 recording decisions (2026-11-22)

- **Problem:** no feedback when the mic was live, no mic choice, no warning when nothing was heard, and a 30-minute recording ended with no warning.
- **Recording limit.** Options: keep 30 min; 20 min like the Wispr-style reference; let the user choose. Measured (Phase 9): 30 min of audio took 47 s to transcribe with Small and peaked at 969 MB. **Choice:** the user chooses 5/10/20/30 min, **default 20**, hard cap 30 (`AudioRecorder.maxSamples`). Warnings at 1 min left and a 10 s countdown (`RecordingMonitor`). At the limit everything recorded is transcribed; nothing is dropped. Downside: a 25-minute monologue now needs a setting change. Migration: none (new default only).
- **Microphone choice.** The Core Audio device UID is stored (`microphoneUID`, "" = system default) and set on the input unit (`kAudioOutputUnitProperty_CurrentDevice`) before the format is read, so each device's own rate and channels are used. A fresh `AVAudioEngine` per recording, because an engine once pinned to a device stops following the default. If the chosen mic is missing at start, or vanishes mid-recording (configuration change), the system default is used and the pill says so. Rejected: an `AVCaptureSession` path (a second audio stack).
- **Sounds.** macOS system sounds (Tink start, Pop stop) via `NSSound`: no bundled or downloaded audio. The start sound plays on the first audio buffer, i.e. once the mic is really live (measured 190–240 ms after the shortcut). The stop sound plays only if a start sound did.
- **No-speech warning and gate.** Speech = at least 0.25 s of chunks at ≥ -45 dBFS, ignoring the first 0.3 s (the start sound). Warned only before any speech, so pauses never warn. Exact-zero audio is reported as "no signal" (muted or virtual device); no audio for 1.5 s as "mic stopped". The same detector now **gates transcription**: a recording with no speech isn't sent to Whisper, because near-silence produced invented text in a real test.
- **Whisper hint.** "Hello, welcome to EsyType." instead of the bare word, which cost full stops on 2 of 5 clips.

### ADR-18: Personal dictionary (Stage 2, 2026-11-22)

- **Problem:** Whisper misspells names, brands and jargon ("EZ type", "Open I"), and no mechanism let the user fix that.
- **Two mechanisms, kept separate.** (1) *Hints*: the replacement words are appended to Whisper's `initial_prompt` as one punctuated sentence ("Hello, welcome to EsyType. OpenAI, GitHub."). At most 20 words / 200 characters (the prompt is limited to ~224 tokens). Auto-detect only knows the language afterwards, so it hints "any language" and English entries; a pinned language hints "any" + that language. Measured: hints left 5/5 clips' punctuation unchanged and turned "OpenI" into "OpenAI". A hint is a nudge, never a guarantee. (2) *Replacements*: exact, deterministic, after `TextCleanup`, for the detected language (English when translating).
- **Matching:** one case-insensitive `NSRegularExpression` per dictation, built from all active rules. Spaces in a phrase match any run of whitespace. A match must not touch a letter, combining mark, digit or underscore on either side (Unicode classes, so Devanagari matras count as part of a word). Text is NFC-normalised first. Rules are ordered longest phrase first, then earlier entry; the regex takes the leftmost match and the first rule that fits there. Single pass: replaced text is never matched again. Options rejected: fuzzy matching (the brief forbids it); a per-word dictionary lookup (breaks multi-word phrases and scripts without spaces).
- **Conflicts:** same words and same language with different replacements: the earlier entry wins, the later one is marked ⚠ and ignored. A language-specific entry overrides an "any language" one for that language (by design, not a conflict). Exact duplicates are refused.
- **Storage:** `~/Library/Application Support/EsyType/dictionary.json`, versioned, written atomically, mode 0600, like the model registry. A damaged file is moved aside as `dictionary.damaged-<time>.json`, never deleted. SQLite was not needed for a list that is always loaded whole.
- **Privacy:** logs show counts only (entries loaded, replacements made). CSV is parsed as data; formula-like values are prefixed with an apostrophe on export (CSV injection) and restored on import.
- **Layers:** `PersonalDictionary`, `DictionaryEngine`, `DictionaryCSV`, `DictionaryStore` in EsyTypeCore (no UI, no Whisper); `DictionaryModel` and `DictionaryTab` in the app; `DictationController` passes the prompt to `WhisperCppEngine` and applies the replacements.
- **Downsides:** exact matching needs the user to enter what Whisper actually writes (which can vary between takes, e.g. Hindi transliterations). Migration: none (new file).

### ADR-19: Snippets and the grouped sidebar (Stage 3, 2026-11-22)

- **Problem:** users repeat the same long texts (signatures, addresses, replies), and personalisation was hidden in Settings.
- **Reuse, not copies.** The Stage 2 matcher moved to `PhraseMatcher` (exact, case-insensitive, whole words in any script, longest phrase first, one pass) and is used by both the dictionary and snippets. CSV parsing/export, the import plan (`ImportPlan<Item>`), the JSON list file (`ListFile<Item>`, atomic, 0600, damaged files set aside) and the macOS file dialogs + import preview (`CSVPanels`, `ImportPreview`) are shared too.
- **Pipeline:** Whisper → `TextCleanup` → dictionary → snippets → insert. Snippets run last, so dictionary rules can fix how Whisper spelled a trigger but never change a snippet's saved text, and a snippet's text never triggers another snippet (one pass).
- **Ambiguity:** a duplicate trigger (same words, same language) is refused when adding or editing. If a file still holds two enabled snippets with one trigger, **neither** expands and both show ⚠ — never the wrong text. (The dictionary instead lets the earlier entry win: a wrong spelling fix is minor, a wrong snippet isn't.) A language-specific snippet overrides an "any language" one for that language.
- **History** keeps the transcript before snippet expansion ("Please add my email signature."), so saved addresses and signatures aren't duplicated into it; Paste Last Transcript pastes what was typed. Logs show counts only.
- **Sidebar:** grouped `List` sections with SF Symbols; arrow keys move the selection; the last page is remembered (`mainWindowSection`). Dictation and AI & Models reuse the existing Settings forms (same preferences, no second store). Settings opens the Settings window and leaves the selection where it was. Text Cleanup shows only what exists (filler removal) with a "Soon" badge. The Dictionary tab left Settings: personalisation lives in the sidebar, Settings keeps configuration.
- **Downsides:** triggers are exact (say it the way Whisper writes it; a dictionary entry can bridge spellings). Snippet triggers aren't hinted to Whisper. Migration: none (new `snippets.json`).

### ADR-20: Text Cleanup rules (Stage 4, 2026-11-22)

- **Problem:** Whisper's output carries hesitations, restarts and spacing slips; the old cleanup was one switch for English fillers plus fixed tidying.
- **One engine, grown in place:** `TextCleanup.clean(_:options:language:)` with `CleanupOptions` (five switches, all on by default; stored under the Phase 7 filler key plus four new keys). Order: Whisper → cleanup → dictionary → snippets → insert.
- **Protection first:** links, emails, paths, `snake_case`, `name()`, `file.ext` (dot attached to a word), numbers like 3.14 and abbreviations (e.g., i.e., etc., Dr.) are swapped for placeholders, so no rule can change them, then restored.
- **Rules:** fillers (um/uh/erm as whole words, not "uh-oh"; "hmm" only when set off; the comma after a filler goes, a sentence's full stop stays). Repeats (1–5 words, immediate, only a comma between): the first copy goes only if the sentence carries on — echoes that end a sentence, triples, numbers and a list of intended doubles (very, had, that, bye…) stay. Punctuation: one space, none before marks (incl. the danda), one after , ; ! ? । before a letter and after . before a capital, " .word" moved back, doubled marks collapsed ("..." "!!" "?!" kept), line breaks kept with at most one blank line. Capitals: first letter of text, sentences and lines, only for all-lowercase words (iPhone, macOS untouched), never lowercasing; "i" → "I" in English.
- **Language:** fillers and repeats run only for English transcripts (Hindi/Marathi reduplication like "धीरे धीरे" is grammar); spacing and capitals run for all.
- **Options rejected:** an LLM or model (brief forbids; nondeterministic); a word-frequency "disfluency" model; aggressive sentence rewriting.
- **Downsides:** rules can miss unusual cases (a restart with a different word, "I think, I believe"), and a deliberate repeat that continues the sentence ("we need to, we need to act") is removed — the user can switch the rule off. Migration: none.

### ADR-21: Dictation controls and safe undo (Stage 5, 2026-11-22)

- **Modes.** Toggle and hands-free are one mode in EsyType (press to start, press or ■ to stop; it runs until stopped, cancelled or the limit). Push-to-talk unchanged. **Double-tap** of the push-to-talk key (each tap < 0.3 s, ≤ 0.4 s between release and press) latches hands-free; a double-tap stops it. Lives in `DictationMachine` (pure, tested); the first tap never opens the mic (150 ms start delay, discarded). Setting: Shortcuts ▸ "Double-tap …" (on by default). Uses the existing listen-only event tap (Input Monitoring) — no new monitoring, no private API.
- **Fn/🌐 not offered:** macOS assigns Globe to emoji/Dictation/input sources, and Fn arrives only as a modifier flag that hardware and settings change; it would need raw HID access. Right ⌥ / Right ⌘ are reliable.
- **Conflicts:** Carbon `RegisterEventHotKey` refuses only system/same-app clashes. Measured: a second process registering ⌃⌥Space got status 0 and so did EsyType; the first registrant receives the key. EsyType reports what macOS refuses and offers other presets.
- **Undo.** Never ⌘Z (it would undo whatever the app did last). Before pasting, `TextInserter` records the focused element, the UTF-16 location of the cursor, the exact typed string (incl. the added leading space) and any selected text it replaces — in memory only. Undo: same app in front → the element's text at that location still equals the typed string → select exactly that range via Accessibility (read back to verify) → set the selection to the replaced text; if the app refuses, a Delete key for that verified selection only (empty replacement only) → verify the final text. Anything else: refuse with a reason. One level, cleared on use or when a dictation is copied instead.
- **Quit:** `shutDown()` stops recording and drops the session, then frees the model.
- **Limits:** text typed *before* the dictation in the same field shifts it, so undo refuses (safe, not smart); apps without Accessibility selection (some web/Electron editors) can't undo; the default recording limit stays 20 min (ADR-17), hard cap 30.

### ADR-9: Optional LLM refinement deferred to Phase 8

- Candidates (to be researched then): llama.cpp with a small instruct model (1–4B, GGUF). This would be a second runtime and a large download, so it's kept out of the MVP. The original transcript is always kept.
