# Tasks and roadmap

A task is marked done only with evidence (test output, measurement, or screenshot). Estimates assume one developer with agent assistance and are rough.

## Phase 0: Research and preparation (current)

- [x] Inspect environment: M4 / 16 GB / macOS 26.5.2, Swift 6.3.2 CLT, **no Xcode**, **~0.7–2.5 GB free disk**. Evidence: ARCHITECTURE ADR-1.
- [x] Competitor research at the owner's direction (internal notes, not published).
- [x] Inspect Ponytail and configure it project-scoped (`AGENTS.md` imported by `CLAUDE.md`). Evidence: `research/PONYTAIL_SETUP.md`.
- [x] EsyAI site inspected in a browser, desktop and mobile. Tokens extracted from computed CSS. Evidence: `research/ESYAI_*`, `research/screenshots/esyai/`.
- [x] Wispr Flow public docs reviewed (internal notes, not published).
- [x] whisper.cpp + model facts (exact sizes, SHA-256, XCFramework slices). Evidence: `MODEL_REGISTRY.md`, ADR-3.
- [x] Apple SpeechTranscriber locale check (no hi/mr). Evidence: ADR-3.
- [x] PRD, architecture, roadmap, UI proposal.
- [x] **Your review and approval** of the design and decisions. Approved 2026-11-22 ("Approve, start Phase 1").

## Phase 1: Branding and native UI foundation · done 2026-11-22 (awaiting your hands-on review)

- [x] Free disk space. Evidence: `df -h /` shows 18 GB free.
- [x] `Package.swift` (EsyTypeCore, EsyType, tests), `Scripts/build-app.sh` producing a universal, Hardened Runtime, ad-hoc signed `build/EsyType.app` (3.0 MB). Evidence: `lipo -archs` → `x86_64 arm64`, `codesign --verify --strict` passes. The app launched on the M4 and ran with no faults (65.6 MB RSS, onboarding open).
- [x] Design system: tokens (`Brand.swift`), bundled OFL fonts (Barlow ×4, Instrument Serif ×2), glass modifier (Liquid Glass on 26 / material on 14–15 / opaque for Reduce Transparency), buttons, bars, keycaps. Provisional app icon (`Scripts/make-icon.swift`). Evidence: `Documentation/screenshots/phase1/`.
- [x] Menu bar: template 3-bar icon, native `NSMenu` (dictation items disabled until Phase 5, Preview Recording Overlay, Open, Settings, Welcome Guide, Quit).
- [x] Onboarding: 7 steps. Microphone, Accessibility and Input Monitoring status are **real and live** (polled each second). The model recommendation and download are labelled PREVIEW/Simulated. Evidence: `onboarding-*.png`.
- [x] Settings window (toolbar tabs). Appearance, overlay-hidden-from-screen-sharing and Permissions **work**. Other controls are shown disabled with a PREVIEW note. Main window shell (Home, History and Models placeholders).
- [x] Recording overlay: non-activating `NSPanel`, 6 states, simulated levels through the tested `LevelMeter`, cancel and stop buttons, VoiceOver announcements, Reduce Motion handling, hidden from screen capture by default. Evidence: `overlays.png`.
- [x] Unit tests: `LevelMeter`/`LevelHistory` (3 tests passing via `Scripts/test.sh`).
- [ ] **Your hands-on check** of the running app (see TESTING.md, Phase 1 manual checklist). Liquid Glass and the sidebar can't be captured offscreen.

## Phase 2: Hardware and storage detection · done 2026-11-22 (awaiting your review)

- [x] `HardwareDetector` (`Sources/EsyTypeCore/Hardware.swift`): chip, Apple Silicon, Rosetta, memory, free disk, macOS. Evidence: `detectsThisMac` passes natively (arm64) and as the x86_64 slice under Rosetta. The recommender tests cover simulated 8/16/18/24/32/64 GB, Intel and Rosetta profiles.
- [x] Disk space calculation (`DiskSpace`, the MODEL_REGISTRY.md storage rule) + tests with exact byte boundaries.
- [x] `Recommender` + table-driven tests (14 cases, plus disk fallback, shortfall and warnings). `ModelCatalog` holds the 4 recommendable files; a test checks their bytes and SHA-256 against MODEL_REGISTRY.md.
- [x] Onboarding "Your Mac" step shows real hardware and the real recommendation. Evidence: `Documentation/screenshots/phase2/onboarding-4-yourMac.png` (M4 / 16 GB → Whisper Small Q8_0).
- Skipped on purpose (no rule uses them yet): Metal family, performance-core count, `host_statistics64` available memory. Add when a Phase 4 benchmark rule needs them.

## Phase 3: Model manager · done 2026-11-22 (awaiting your review)

- [x] Catalogue from `MODEL_REGISTRY.md`: the 4 recommendable files with pinned URLs. Evidence: `catalogueMatchesModelRegistry`, `catalogueURLsUseThePinnedRevision`. The f16/Q5_1 files are left out until Phase 4 shows a reason to offer them.
- [x] Downloader (`ModelStore`, ADR-12): progress, cancel, resume (HTTP Range), retry with backoff, duplicate guard, disk check. Evidence: 11 tests in `ModelStoreTests.swift`.
- [x] SHA-256 + exact-size verification, atomic install, `registry.json`, remove with a confirmation dialog. Evidence: tests + `Documentation/screenshots/phase3/`.
- [x] Tests with a local file:// fixture, a stubbed HTTP server (206 resume, transient failures, slow responses) and corrupt/oversized files.
- [x] Onboarding download step and the main window Models page use real downloads. The menu shows the installed model.
- [ ] **Real download from Hugging Face over the network**: not run yet. Needs your OK or your click on Download (Whisper Base is 81.8 MB, Small is 264.5 MB).

## Phase 4: Speech engine · in progress (English done 2026-11-22; Hindi/Marathi need your clips)

- [x] XCFramework integration: SwiftPM `binaryTarget`, b5454, checksum checked by SwiftPM on resolve. `WhisperCppEngine` actor in `Sources/WhisperEngine` (the only module that imports whisper.cpp). Evidence: `transcribesEnglish` passes for all 4 models natively and as x86_64 under Rosetta.
- [x] Real model downloads through `ModelStore` from Hugging Face, including a real-network resume (Turbo Q8 stopped at 74,096,804 bytes, then finished and verified). Evidence: `realDownloadsFromHuggingFace`, `registry.json`.
- [ ] Fixture set: English done (`jfk.wav`, 11 s). **Hindi and Marathi clips with reference text are still needed from you** (or approved public-domain samples).
- [x] Benchmarks on M4 (English, 11 s clip): load, first and warm latency, RTF, peak memory for all 4 models. Evidence: TESTING.md Phase 4 table.
- [ ] WER per language per model: English is 0 errors on one clip for every model (too small to compare). Hindi/Marathi blocked on clips.
- [ ] Decide the Turbo variant: Q5_0 and Q8_0 run at the same speed here (RTF ≈ 0.2) and Q8_0 needs ~320 MB more memory. Choose once Hindi/Marathi WER shows whether Q5_0 loses accuracy.
- Not done on purpose: bundling the engine into EsyType.app (Phase 5, when dictation uses it); saving per-Mac benchmark results for the recommender (Phase 9).

## Phase 5: Audio and shortcuts · built 2026-11-22 (needs your hands-on check)

- [x] `AudioRecorder` (EsyTypeCore): 16 kHz mono in memory only, live levels, 30-minute cap, stops cleanly when the input device changes. Evidence: converter tests at 48 kHz, 44.1 kHz stereo and 16 kHz; silence detection test.
- [x] Shortcuts (`Hotkeys`): ⌃⌥Space (Carbon, no permission), Esc (Carbon, only while dictating), hold Right ⌥ (listen-only event tap, Input Monitoring). Right ⌥ with ⌘/⌃/⇧ or followed by another key is ignored, and the mic only switches on after 150 ms of holding.
- [x] `DictationMachine` + 7 tests: hold, release, short-tap discard, ⌥-as-modifier discard, hands-free toggle, cancel while recording or transcribing, busy rejection, auto-stop keeps audio.
- [x] Overlay driven by the real recorder level, timer, ■ and ✕.
- [x] Whole flow wired (`DictationController`): shortcut → record → Whisper (the recommended model if installed) → **copied to the clipboard** (marked transient/concealed) → "Copied" pill. Typing into the focused app is Phase 6.
- [x] `whisper.framework` embedded in the app; app launches with it loaded. Evidence: `lsof` shows the framework mapped; no faults.
- [ ] **Your hands-on check** (TESTING.md, Phase 5 checklist). I can't press keys or speak in this session.
- Skipped: double-tap Right ⌥ to latch hands-free (⌃⌥Space already does hands-free; add if you want it). Secure-input detection (`IsSecureEventInputEnabled`) and a shortcut recorder are left for Phase 7 Settings.

## Phase 6: Text insertion · built 2026-11-22 (needs your hands-on check and the app matrix)

- [x] `TextInserter`: pastes into the app that was frontmost when recording started, only if it's still frontmost, Accessibility is allowed, something has focus and it isn't a password field. Otherwise the text is copied ("Copied. Press ⌘V").
- [x] Clipboard borrowed and put back: every item and type is snapshotted, restored after 500 ms, and only if the clipboard is still ours. Evidence: `snapshotRestoresEveryItemAndType`, `emptyClipboardStaysEmpty`.
- [x] Layout-aware ⌘V (Dvorak, AZERTY; Devanagari falls back to the ANSI V key). Evidence: `pasteKeyIsVOnThisMacsLayout` on the British layout.
- [x] Paste Last Transcript (menu and ⌃⌘V), kept in memory only, as the safety net when a paste doesn't land.
- [ ] **App compatibility matrix**: TESTING.md has the table. Needs you (this session can't press keys or speak).
- Not done: a per-app "always copy" list and per-app restore delays (add from the matrix results); Chrome/Electron `AXManualAccessibility` (only if the matrix shows those apps fall back to copying).

## Phase 7: History and settings · built 2026-11-22 (needs your hands-on check)

- [x] `HistoryStore` (SQLite, WAL, file 0600): add, search (any script), delete one, delete all, delete older than. Evidence: 3 tests, including Devanagari search, SQL characters and file permissions.
- [x] Every dictation is saved **before** it's pasted, so nothing is lost if the paste lands nowhere. Retention (Forever / 30 / 7 days / Don't keep) is applied on every read and save. Source app is optional.
- [x] History page: search, copy, delete, Clear All with confirmation. Evidence: `Documentation/screenshots/phase7/history.png`.
- [x] `TextCleanup`: removes Whisper markers ([BLANK_AUDIO]) and, optionally, English fillers (um, uh, erm, hmm) without touching words like "umbrella". Evidence: 9 test cases.
- [x] Settings, all working: Open at login, push-to-talk key (Right ⌥ / Right ⌘ / Off), hands-free shortcut (⌃⌥Space / ⌃⇧Space / ⌥Space / Off), model choice, language (Auto + 99 whisper languages), translate to English, filler removal, history retention, source app, Clear History. The greyed-out placeholders are gone.
- [ ] Your hands-on check (TESTING.md, Phase 7).
- Skipped: a free-form shortcut recorder (presets instead), "Insert again" on history rows, a Recent submenu in the menu bar, start/stop sounds, keeping audio recordings (never stored), an About ▸ Acknowledgements screen (Phase 10, with the whisper.cpp licence text).

## Phase 8: Optional local LLM refinement · research spike ~3 days, implement only if reliable

## Phase 9: Testing and optimisation · done on this Mac 2026-11-22 (manual checks still open)

- [x] Latency target (≤ 1.5 s after release for 10 s on M4/Small): **0.50 s** for 11 s, 0.43 s for 3 s (engine time; paste adds ~0.1 s). Evidence: TESTING.md Phase 9.
- [x] 30-minute recording (the app's cap) in one call: 47 s on Small, all 163 repetitions transcribed, peak 969 MB.
- [x] Idle model unload after 10 minutes and on macOS memory pressure; the unload timer restarts on every return to idle (cancel, failure, finish).
- [x] Intel path: CPU only (Metal on Apple Silicon only), all physical cores (19 % faster than whisper's default 4 on CPU; GPU stays at 4, which measured best).
- [x] Load/unload cycles: no leak (+3 MB per cycle after the first).
- [x] Idle memory: 48 MB before the first dictation; ~200 MB after first use (ggml keeps its state). **Accepted by you on 2026-11-22** (ADR-16); an XPC helper stays an option if it becomes a problem.
- [x] Privacy: `Scripts/privacy-check.sh` (no sockets, network code only in ModelStore, no print(), no whisper/ggml log lines, no audio files, history 0600): all pass.
- [x] Idle CPU 0.0 % (top, 6 samples).
- [x] Contrast: light-mode warning and success text failed (1.4:1, 2.1:1); now 5.7:1 and 5.1:1.
- [ ] Manual: VoiceOver, keyboard, Reduce Motion/Transparency, energy impact, Hindi/Marathi WER, the 20-app matrix, a real Intel Mac.

## Phase 10: Release preparation · GitHub beta prepared 2026-11-22, publishing paused by you

- [x] Not notarised, free, GitHub Releases (your decision 2026-11-22). `Scripts/make-dmg.sh` → `build/EsyType-0.1.0.dmg` (6.4 MB, universal, `hdiutil verify` passes).
- [x] README (install with Open Anyway, shortcuts, privacy, build from source), Settings ▸ About ▸ Acknowledgements (whisper.cpp MIT, fonts OFL, Whisper models), copyright and category in Info.plist, "Beta" labels.
- [x] Local git repo, 89 files staged and reviewed (no secrets, models or builds). `research/`, `AGENTS.md`, `CLAUDE.md` are kept out; reverse-engineering details removed from public docs.
- [ ] Publish: log in with `gh auth login`, then first commit (GitHub noreply email), public repo, v0.1.0 pre-release with the DMG.
- [ ] Choose a licence for EsyType's own code (none yet).
- Not done on purpose: notarisation, Developer ID signing, auto-updates.

**Rough total to a signed beta:** about 8–10 weeks of focused work. This is an estimate, not a commitment.

## Stage 1: Recording and microphone · done 2026-11-22 (evidence: `Documentation/STAGE_1_TEST_REPORT.md`)

- [x] Start/stop sounds (system sounds, separate toggles, volume). Start plays once the mic is live. Evidence: log "Microphone live after 191–240 ms" then "Start sound played", 10+ real runs.
- [x] Microphone picker (System default + every input device, refreshed on plug/unplug), fallback when the chosen mic is missing. Evidence: real runs with the built-in mic, Microsoft Teams Audio and a missing UID.
- [x] Default input change mid-recording keeps recording. Evidence: real run, default switched twice.
- [x] No-speech warning (default 5 s, 3/5/10 s, can be off), "no signal" and "mic stopped" told apart; silent recordings are no longer sent to Whisper. Evidence: real runs + 6 unit tests.
- [x] Recording limit: default 20 min (5/10/20/30), warnings at 1 min and a 10 s countdown, everything transcribed. Evidence: real runs at a 20 s and a 75 s limit.
- [x] Settings ▸ Recording tab with a 5-second microphone test. Evidence: `Documentation/screenshots/stage1/settings-recording.png`.
- [ ] **Your checks:** hear the sounds; try Test Microphone; unplug a USB/Bluetooth mic mid-recording; try your iPhone microphone.

## Stage 2: Personal dictionary · done 2026-11-22 (evidence: `Documentation/STAGE_2_TEST_REPORT.md`)

- [x] Core: entries, add/edit/delete/enable, search and filters, duplicates refused, conflicts reported (earlier entry wins). Evidence: 5 unit tests.
- [x] Matching engine: exact, case-insensitive, whole words in any script, phrases, longest first, single pass, NFC. Evidence: 8 unit tests incl. Hindi and Marathi.
- [x] Whisper hints from the dictionary, language-aware, capped. Evidence: unit test + 6-clip probe (punctuation unchanged, "OpenI" → "OpenAI").
- [x] CSV import with preview (add/update/skip/reject, never silent overwrite), export, sample template. Evidence: 5 unit tests + real-file round trip.
- [x] Settings ▸ Dictionary. Evidence: entry added through the real sheet via Accessibility; replacement in real TextEdit dictation (English and Hindi); persisted across a restart.
- [ ] **Your checks:** CSV Import…/Export…/Save Sample Template… through the file dialogs (I couldn't reach them while Claude was full-screen); the edit sheet and filters by eye.


## Stage 3: Snippets and sidebar · done 2026-11-22 (evidence: `Documentation/STAGE_3_TEST_REPORT.md`)

- [x] Shared `PhraseMatcher`, CSV, import plan, list file and file dialogs (dictionary refactored onto them; its 17 tests unchanged and passing).
- [x] Snippet core: library (create, edit, delete, enable, search, categories, dates), engine, CSV with dates, store. Evidence: 12 unit tests.
- [x] Pipeline: dictionary → snippets → insert; history keeps the unexpanded transcript. Evidence: real runs + history check.
- [x] Sidebar: Main / Personalisation / System, every item opens its real page. Evidence: each item selected through Accessibility in the real app.
- [x] Snippets screen: created and edited through the real sheets; multi-line Hindi text typed into TextEdit and Notes; survives a restart.
- [ ] **Your checks:** snippets CSV Import…/Export… through the file dialogs; the screens by eye.

## Stage 4: Text Cleanup · done 2026-11-22 (evidence: `Documentation/STAGE_4_TEST_REPORT.md`)

- [x] Five switchable rules in `TextCleanup` with protected text (links, emails, code, numbers, abbreviations). Evidence: 8 unit-test groups, 97/97 pass.
- [x] Text Cleanup screen in the sidebar (Personalisation): switches with examples, always-on list, live Try it, planned features clearly marked. Evidence: real app via Accessibility; the preview found a bug (" .see") that was then fixed and tested.
- [x] Dictation uses the switches. Evidence: real TextEdit runs with the repeat rules off (repeat kept) and on (removed); Hindi doubling kept; dictionary + snippet still applied.
- [ ] **Your checks:** flip the switches in the screen by hand; dictate with your own fillers ("um", restarts).

## Stage 5: Dictation controls and undo · done 2026-11-22 (evidence: `Documentation/STAGE_5_TEST_REPORT.md`)

- [x] Double-tap push-to-talk key → hands-free, double-tap to stop; setting to turn it off. Evidence: 4 new machine tests; real double-tap run.
- [x] Undo Last Dictation (⌃⌘Z, menu) via verified Accessibility selection. Evidence: real TextEdit (plain, after typing, refused after edit) and Notes.
- [x] Quit during a session releases the mic; "Undone" pill.
- [ ] **Your checks:** double-tap with your own fingers; ⌃⌘Z after dictating in your usual apps.
