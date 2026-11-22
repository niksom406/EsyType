# EsyType: final quality audit

Date: 2026-11-22 · Version audited: 0.1.0 beta (source in this folder, app installed at `/Applications/EsyType.app`) · Auditor: the same AI agent that built the project, acting as an independent reviewer. Read this with that conflict of interest in mind.

Evidence labels used throughout: **Verified** (run or measured here), **Reported** (by the owner from real use), **Inspected** (read in code or docs, not run), **Not tested**.

## 1. Executive summary

EsyType has a working, well-tested core: local whisper.cpp transcription on the M4, a verified model downloader, hardware-based recommendation, history, settings and clipboard-safe insertion. All automated tests pass, the build has no warnings and the privacy checks pass.

The audit found **one critical bug in the shipped beta**: stopping a dictation could crash the app. The crash report from 15:08 on 2026-11-22 shows `AudioRecorder.stop()` removing the audio tap before stopping the audio engine, so Apple's audio thread called a freed tap. This is almost certainly why the owner's dictation "didn't work". It is **fixed in source and in the installed app**, but the fix is **not yet confirmed on a real dictation**, because only the owner can speak and press keys.

The project is **not production-ready**: Hindi and Marathi quality is unmeasured, Intel Macs are untested on real hardware, there are no UI or app-level automated tests, and the app is neither Developer-ID-signed nor notarised (owner's decision for the beta). It is ready for a **stabilisation phase** focused on confirming real dictation, then language testing.

## 2. Overall project status

| Phase | Status | Evidence |
|---|---|---|
| 0 Research | Done | `research/` (local only) |
| 1 UI foundation | Built | Screenshots; owner has used the app |
| 2 Hardware detection | Done | 15 unit tests (simulated profiles) + real M4 |
| 3 Model manager | Done | 11 tests + real Hugging Face downloads and resume |
| 4 Speech engine | English only | 4 models transcribe `jfk.wav`; Hindi/Marathi not tested |
| 5 Audio and shortcuts | Built, crash fixed today | Owner reported failure; crash report; fix not yet confirmed |
| 6 Insertion | Built | Pasteboard tests; app matrix not done |
| 7 History and settings | Built | Store tests; UI rendered |
| 8 AI refinement | Skipped (owner's decision) | — |
| 9 Testing and optimisation | Done on M4 | Benchmarks in `TESTING.md` |
| 10 Release | GitHub beta prepared, not published | DMG builds; `gh` not logged in |

## 3. Requirements compliance matrix

Source: the original master brief (sections cited). Status per the brief's scale.

| # | Requirement (brief §) | Implementation | Evidence / test | Status | Remaining work |
|---|---|---|---|---|---|
| 1 | Fully local inference, no cloud/paid APIs (§3A) | whisper.cpp in-process; only `ModelStore` uses the network | `privacy-check.sh` (no sockets, network code only in ModelStore) | PASS | — |
| 2 | Offline after model install (§3A) | No network in the dictation path | Inspected; sockets check while idle | PARTIAL | Run a dictation with Wi-Fi off |
| 3 | Detect architecture, Apple Silicon/Intel, chip, RAM, disk, OS (§3B) | `HardwareDetector` | `detectsThisMac` (M4), Rosetta run | PASS | — |
| 4 | Detect available memory, acceleration capabilities (§3B) | Not detected (Metal inferred from arm64) | Inspected | FAIL | Add only if a rule needs it |
| 5 | Recommend model from capabilities; manual choice (§3B, §8) | `Recommender`, Settings ▸ Speech ▸ Model, Models page | 14 table cases | PASS | — |
| 6 | Use measured performance in recommendation (§7, §8) | Recommender accepts benchmarks, app passes none | Inspected | PARTIAL | Store per-Mac benchmark results |
| 7 | Show performance classification (§8) | Not shown | Inspected | FAIL | Add once benchmarks are stored |
| 8 | Storage check incl. temp space, cancel, no duplicates (§3C, §12) | `DiskSpace`, `ModelStore` | 11 ModelStore tests | PASS | — |
| 9 | Checksum + format verification, atomic install, registry, removal with confirmation (§3C, §12) | SHA-256 + exact size, rename, `registry.json`, dialog | Tests + real downloads | PASS | File magic (`ggml`) not checked; SHA covers it |
| 10 | Download only the selected model (§3C) | Download only on button press | Inspected | PASS | — |
| 11 | No background recording; explicit start (§3D) | Mic runs only between start and stop | Inspected | PASS | — |
| 12 | No raw audio stored; no transcripts in logs (§3D) | In-memory audio; logs carry stages only | `privacy-check.sh`; code read | PASS | — |
| 13 | Clear privacy settings (§3D) | Settings ▸ History & Privacy | Rendered | PASS | — |
| 14 | REA investigated and used (§4A) | REA 6.10.1 run against Wispr Flow | `research/REA_INVESTIGATION.md` | PASS | Not re-run in this audit |
| 15 | Ponytail inspected, configured, applied (§4B) | `AGENTS.md` (rules file), plugin installed later | `research/PONYTAIL_SETUP.md`, code style | PASS | — |
| 16 | EsyAI brand research and tokens (§5) | Brand docs, tokens in `Brand.swift` | Re-checked live site: fonts and core colours match | PASS | Official logo/gradient files still needed |
| 17 | Design approval before UI (§5) | Approved 2026-11-22 | Conversation record | PASS | — |
| 18 | Wispr Flow feature matrix (§6) | `research/WISPR_FLOW_FEATURE_MATRIX.md` | Exists | PASS | — |
| 19 | Whisper multilingual via whisper.cpp; Base/Small/Turbo (§7) | b5454 framework, 4 files | Real transcription, all 4 | PASS | — |
| 20 | Test Hindi and Marathi quality (§7) | Not done | — | NOT TESTED | Owner's clips needed |
| 21 | Benchmark Turbo before recommending it (§7) | Benchmarked; never auto-recommended | `TESTING.md` Phase 4/9 | PASS | — |
| 22 | Model registry fields (§7) | `MODEL_REGISTRY.md` | Installed files match bytes + SHA | PASS | Measured RAM for quantised models added; version field = pinned revision |
| 23 | Global shortcut, push-to-talk, toggle (§9A) | Hotkeys + DictationMachine | 7 state tests; owner report | PARTIAL | Confirm after crash fix |
| 24 | Pause/resume where appropriate (§9A) | Not implemented (PRD: not in MVP) | — | NOT STARTED | Decide if wanted |
| 25 | Level feedback, waveform, duration, floating indicator (§9A) | Overlay | Rendered; owner has seen it | PASS | — |
| 26 | Handle shortcut conflicts (§9A) | Shown in the overlay (added in this audit) | Inspected | PARTIAL | Not tested with a real conflict |
| 27 | Language detection, punctuation, long recordings (§9B) | whisper auto-detect; 30-min cap | `longAudio` 30 min, 163/163 | PASS (English) | Other languages |
| 28 | Preserve original transcript if processing fails (§9B) | Cleanup is deterministic; raw text not kept | Inspected | PARTIAL | Keep raw text if Phase 8 is built |
| 29 | Insert into active app, safe fallback (§9C) | `TextInserter` | Pasteboard tests; owner has not confirmed paste yet | PARTIAL | 20-app matrix |
| 30 | History: store, search, copy, delete, clear, retention (§9D) | `HistoryStore`, History page | 3 tests + render | PASS | — |
| 31 | Settings list (§9E) | All present; shortcut presets, not free recording | Rendered | PARTIAL | Free shortcut recorder |
| 32 | Menu bar: recording, status, model, recent, settings, quit (§9F) | No recording status or recent list in the menu | Inspected | PARTIAL | Add status and recent items |
| 33 | Optional local LLM refinement (§9G) | Skipped (owner) | — | NOT STARTED | — |
| 34 | Swift 6, SwiftUI/AppKit, AVAudioEngine, OSLog, SQLite (§10) | As specified; Swift Testing instead of XCTest (no Xcode) | Build | PASS | — |
| 35 | Engine replaceable without UI rewrite (§10) | `WhisperEngine` module; 2 call sites | Inspected | PASS | — |
| 36 | Developer ID signing, notarisation (§14) | Not done (owner's decision for the beta) | — | NOT STARTED | Needs a paid Apple account |
| 37 | Hardened Runtime, entitlements, mic description (§14) | Done; dev builds add `disable-library-validation` | `codesign -d` | PASS | — |
| 38 | DMG, licence notices, attribution (§14) | `make-dmg.sh`, About ▸ Acknowledgements | DMG verified | PASS | — |
| 39 | Application updates, crash recovery (§14) | None | — | NOT STARTED | — |
| 40 | Unit, integration, audio, model, download, hardware, storage tests (§15) | Present | 42 tests pass + 4 opt-in | PASS | — |
| 41 | Shortcut, insertion, permission, UI, recovery tests (§15) | State machine and pasteboard only; no UI tests | — | PARTIAL | Needs Xcode (XCUITest) or a manual protocol |
| 42 | Test Intel, 8/24/32 GB (§15) | Simulated only; Rosetta for x86_64 code | Labelled in `TESTING.md` | NOT TESTED | Real machines |
| 43 | Benchmarks incl. CPU, battery, quality (§15) | Load, latency, RTF, memory, CPU-only, long audio | `TESTING.md` | PARTIAL | Battery, WER |
| 44 | Required docs maintained (§16) | All present | — | PASS | Kept current in this audit |

**Summary (44 rows):** 26 PASS, 10 PARTIAL, 2 FAIL, 2 NOT TESTED, 4 NOT STARTED.

## 4. Documentation and writing review

- **British English** is consistent in the Markdown documents and UI strings. "License" appears only in proper names (SIL Open Font License, `LICENSE` files), which is correct.
- **Fixed (High): `ARCHITECTURE.md` described the Phase 0 proposal, not the code.** It described a `SpeechEngine` protocol, a `Resampler`, folders and scripts (`package-dmg.sh`, `notarize.sh`) that don't exist, FTS5 search, `abort_callback` cancellation, VAD, secure-input detection, a resume-data downloader and "no AppKit in Core". Sections 1–6 were rewritten to match the code. The ADRs are kept as history.
- **Fixed (Medium):** stale status lines in `PRD.md` ("Phase 0 draft", pricing undecided) and `LICENCES.md` ("Phase 0 assessment", VAD "possibly bundled"). `TESTING.md` now says which test layers don't exist.
- **Fixed (Medium): microphone wording.** The macOS permission prompt (`NSMicrophoneUsageDescription`), onboarding and Settings said EsyType listens "only while you hold your shortcut". Hands-free mode records without holding, so the wording was inaccurate. It now says "only while you're dictating".
- **Research accuracy (spot-checked):**
  - The live EsyAI site still loads Barlow 300–600, Instrument Serif and `main.43bb071d.css`, and contains `#050505`, `#0D0D0D`, `#F3F4F6` and `#D1D5DB`, as documented.
  - The logo colours (`#2879AB`, `#9A988F`, `#DBAE7E`) are correctly labelled as estimates sampled from the favicon.
  - All 4 model files on disk match `MODEL_REGISTRY.md` byte counts and SHA-256.
  - REA findings were not re-run, because REA was removed to save disk.
- **Remaining:**
  - Several `TASKS.md` and `TESTING.md` entries are dated historical notes (for example Phase 1 "placeholders"). They're accurate for their date but long.
  - `CLAUDE.md` still says ~20 GB free; about 5.7 GB is free now.

## 5. Code quality findings

- **Strengths:**
  - Small files (largest 271 lines) and clear module boundaries.
  - 0 compiler warnings under Swift 6 strict concurrency.
  - No third-party Swift dependencies.
  - Consistent error types, and `shortcut:` comments on every known limitation.
- **Critical (fixed): crash when stopping a dictation.** `AudioRecorder.tearDown()` called `removeTap` before `engine.stop()` (crash report, EXC_BAD_ACCESS on `com.apple.audio.IOThread.client`, called from `Hotkeys` → `DictationController.handle` → `AudioRecorder.stop`). The order is now reversed, in both places it happened.
- **High (fixed):** a change of input device (including Bluetooth headphones switching to their microphone) ended the recording at once, often with "No speech detected". The recorder now restarts on the new input and keeps the audio it has.
- **High (fixed):** nothing recorded where a dictation stopped, so failures couldn't be diagnosed. Privacy-safe `OSLog` lines were added for recording start, transcription time, outcome, errors and the hold-key listener. They never include the transcript.
- **Medium (fixed):** shortcuts were unregistered and registered again on *every* preference change anywhere in the app. Now only when the shortcut setting changes.
- **Medium (fixed):** shortcut registration failures were only logged. They're now shown in the overlay.
- **Medium (open):** `whisper_full` blocks a Swift shared-pool thread for the length of a decode. That's fine for one dictation at a time.
- **Medium (open):** Esc during transcription drops the result but doesn't stop the decode, because there's no `abort_callback`.
- **Low (open):**
  - The onboarding microphone step shows two buttons that do the same thing.
  - `Hotkeys`' retry loop keeps polling every 2 s while the hold key is set to Off (cheap but unnecessary).
- **C interop:**
  - The whisper context is freed in `deinit`.
  - C strings are only read inside the call.
  - `language` is kept alive with `withCString` for the whole of `whisper_full`.
  - Sample buffers are passed with `withUnsafeBufferPointer`.
  - SQLite statements are finalised in `defer`, and text is bound with `SQLITE_TRANSIENT`.
  - No problems found.

## 6. Architecture review

- The layering is appropriate and not over-built: UI → `DictationController` → (recorder, engine, cleanup, history, inserter). Model management, hardware detection and storage are independent of inference.
- Core logic is in `EsyTypeCore`, unit-tested without UI. The engine is isolated in one module.
- There are no circular dependencies: EsyType → EsyTypeCore and WhisperEngine; WhisperEngine → whisper only.
- **Not separately testable:** `DictationController`, `Hotkeys` and `TextInserter` live in the executable target. Their logic is partly extracted (`DictationMachine`, `PasteboardSnapshot`), but the glue that crashed has no automated test, and couldn't have one without a microphone.
- No new patterns are recommended. A `SpeechEngine` protocol isn't needed with one engine.

## 7. AI and model validation

| Item | Finding | Status |
|---|---|---|
| Source | `huggingface.co/ggerganov/whisper.cpp`, pinned revision `5359861c…` | Verified (real downloads) |
| Format / quantisation | GGML `.bin`, Q8_0 / Q5_0 as listed | Verified (whisper.cpp loads all 4) |
| Size / SHA-256 | Exact, checked on download and against `MODEL_REGISTRY.md` | Verified |
| Runtime | whisper.cpp b5454 XCFramework, SHA-256 `e57f8c48…` checked by SwiftPM | Verified |
| Licence | MIT (repo); OpenAI weights MIT/Apache-2.0 per cards | Inspected (not legal advice) |
| Memory | Measured peak 253 MB–1.13 GB; ~150 MB stays after unload (accepted, ADR-16) | Verified on M4 |
| Languages | 99 listed by whisper.cpp; **English quality measured on one clip only** | Hindi/Marathi Not tested |
| Download safety | Disk check, cancel, resume, retry, duplicate guard, corrupt-file rejection | Verified (tests + real network) |
| Insufficient memory | No pre-load memory check; macOS memory-pressure unload only | Partial |
| Local only | No network in the dictation path | Verified (static + socket check) |

## 8. Security and privacy review

| Risk | Severity | Status |
|---|---|---|
| Audio leaving the Mac | Critical if present | Not present (verified) |
| Transcripts in logs | High if present | Not present. New logs carry stages and timings only (inspected) |
| Raw audio on disk | High if present | Not present (verified: no audio files) |
| History file readable by other users | Medium | `0600`, including WAL/SHM (verified) |
| Model tampering | High | SHA-256 + exact size before install (verified) |
| Clipboard contents | Medium | Restored after paste unless the user copied; dictations marked concealed/transient |
| `disable-library-validation` in non-Developer-ID builds | Medium | Needed because ad-hoc frameworks have no Team ID. Lets any signed library load into EsyType. Removed automatically for Developer ID builds |
| Unsigned, not notarised distribution | Medium | Users must use Open Anyway; permissions reset on each update. Owner's decision for the beta |
| Credentials in source control | High if present | None found. `research/`, `CLAUDE.md`, `AGENTS.md` excluded from git |
| Destructive actions | — | Model removal, Clear History and Clear All ask first |

## 9. macOS compatibility review

- **Minimum macOS 14:** set by the package and needed by `@Observable`. whisper.cpp's framework needs 13.3. **macOS 14 and 15 are not tested.**
- **Apple Silicon:** Metal, tested on the M4 only.
- **Intel:**
  - Builds universal and uses the CPU path (no Metal assumption).
  - Tested only as x86_64 code under Rosetta on the M4. All 4 models transcribed in isolated runs.
  - Under parallel load, Rosetta intermittently crashed inside Apple's audio allocator (`caulk`) while reading the WAV file. That's Apple code; real Intel Macs don't use Rosetta. **Real Intel: not tested.**
- **Permissions:** handled for Microphone, Accessibility and Input Monitoring. They reset after every ad-hoc rebuild, a development-signing limit that the Home page now surfaces.
- **Menu bar:** works. The icon can be hidden by the notch, so opening the app now shows the main window.

## 10. UI and branding review

- **Matches the EsyAI research:**
  - fonts: Barlow, plus Instrument Serif italic for headlines;
  - dark canvas `#050505`, surfaces `#0D0D0D`/`#171717`;
  - light CTA gradient;
  - the bar motif and blue-to-amber level bars.
- **Checked offscreen:** every screen, all 6 overlay states, and the History page with sample data, including Hindi.
- **Fixed in Phase 9:** status text contrast in light mode.
- **Open:**
  - the duplicate Allow button on the microphone step;
  - the provisional app icon (official EsyAI artwork needed);
  - Liquid Glass and the macOS 26 sidebar can't be captured offscreen and have only been seen by the owner;
  - VoiceOver and keyboard use haven't been checked.

## 11. Testing results (this audit)

| Test | Command | Expected | Actual | Result |
|---|---|---|---|---|
| Dependency resolution | `swift package resolve` | whisper zip checksum accepted | exit 0 | PASS |
| Clean debug build | `swift package clean && swift build` | 0 warnings | 0 warnings | PASS |
| All default tests (arm64) | `Scripts/test.sh` | all pass | 42 passed, 4 opt-in skipped | PASS |
| Real transcription, 4 models | part of the above | English text contains the phrase | pass | PASS |
| x86_64 under Rosetta, full suite | `arch -x86_64 swiftpm-testing-helper …` | all pass | SIGILL in Apple `caulk` during `AVAudioFile.read` (parallel run) | FAIL (environment) |
| x86_64 under Rosetta, audio tests alone, twice | same, `--filter` | pass | pass, pass | PASS |
| Release universal build + DMG | `Scripts/make-dmg.sh` | signed, `x86_64 arm64`, DMG verifies | as expected | PASS |
| Privacy checks | `Scripts/privacy-check.sh` | 6/6 | 6/6 | PASS |
| App launch from Applications | `open` + window check | window shown, no crash | 1 window, RSS 108 MB with the main window open | PASS |
| Real dictation after the crash fix | owner | text typed | — | NOT TESTED |
| UI tests, shortcut and permission automation | — | — | no XCUITest without Xcode | NOT TESTED |
| Intel hardware, macOS 14/15, 8/24/32 GB | — | — | no hardware | NOT TESTED |

Earlier opt-in runs (not repeated here): real Hugging Face downloads and resume, benchmarks, 30-minute audio, unload cycles (see `TESTING.md` Phases 4 and 9).

**Correction (2026-11-22, after the audit):** every earlier "no faults in the unified log" result in this project, and the `privacy-check.sh` log test, ran `log show` from zsh, where `log` is a shell built-in, so they checked nothing. Rechecked with `/usr/bin/log` for the last 3 hours of the running app: **no faults**. The errors are macOS framework messages: App Intents can't register an unsigned app (×243), ggml's Metal shader compiler warnings (×35), CoreAudio `-10877` (×4), audio I/O overload (×2), one AppKit layout warning. `privacy-check.sh` now uses `/usr/bin/log`.

## 12. Performance results (measured on M4/16 GB, from `TESTING.md`)

- **Transcription, Small Q8_0 on Metal:** 0.43 s for 3 s of audio, 0.49 s for 11 s. The target was ≤ 1.5 s.
- **Model load:** 0.1–0.8 s.
- **30 minutes of audio:** 47 s.
- **Memory:**
  - App with no window: 48 MB.
  - Main window open: 108 MB (this audit).
  - After the first dictation and unload: about 200 MB (accepted, ADR-16).
- **CPU when idle:** 0.0%.
- **Not measured:**
  - battery and energy impact;
  - launch time;
  - GPU utilisation;
  - UI responsiveness during transcription (inspected only: the decode runs off the main thread).

## 13. Critical issues

1. **Crash when stopping a dictation** (the tap was removed before the engine stopped). **Fixed** and installed, but not yet confirmed by a real dictation.

## 14. High-priority issues

1. Recordings ended on input-device changes (Bluetooth). **Fixed**, not tested on hardware.
2. No diagnostics for failed dictations. **Fixed** with privacy-safe logs.
3. `ARCHITECTURE.md` didn't match the code. **Fixed.**
4. Hindi and Marathi transcription quality unmeasured, although they're the owner's priority languages. **Open.**
5. No automated test covers the app-level dictation path, where the crash was. **Open.**

## 15. Medium-priority issues

1. Microphone wording inaccurate for hands-free mode. **Fixed.**
2. Shortcuts re-registered on every preference change. **Fixed.**
3. Shortcut conflicts not shown to the user. **Fixed.**
4. Stale PRD, LICENCES and TESTING statements. **Fixed.**
5. `whisper_full` blocks a shared-pool thread; there's no `abort_callback`. **Open.**
6. Permissions reset on every ad-hoc build. **Open.** A self-signed identity (supported by `build-app.sh`) or a Developer ID fixes it.
7. `disable-library-validation` in non-Developer-ID builds. **Open, by design** until signing.
8. Menu bar lacks recording status and recent items; there's no pause/resume. **Open.**
9. Intermittent Rosetta crash inside Apple's audio code under parallel tests. **Open** (environment).

## 16. Low-priority issues

1. Duplicate Allow button on the onboarding microphone step.
2. The hold-key retry loop polls while the hold key is Off.
3. `CLAUDE.md` environment notes are out of date (free disk).
4. Long, dated history entries in `TASKS.md`/`TESTING.md`.
5. Provisional app icon.

## 17. Corrections performed in this audit

| Change | Files | Verified by |
|---|---|---|
| Stop the engine before removing the tap (crash fix) | `AudioRecorder.swift` | Build, tests; crash report explains the cause; real dictation pending |
| Continue recording across input-device changes | `AudioRecorder.swift` | Build, tests (no hardware test possible) |
| Privacy-safe diagnostic logging | `DictationController.swift`, `Hotkeys.swift` | Build; code review: no transcript text logged |
| Re-register shortcuts only on change; show conflicts | `Hotkeys.swift`, `DictationController.swift` | Build |
| Accurate microphone wording | `Info.plist`, `OnboardingView.swift`, `SettingsTabs.swift` | Rendered onboarding screen |
| Architecture rewritten to match code | `ARCHITECTURE.md` | Cross-checked file by file |
| Stale statements corrected | `PRD.md`, `LICENCES.md`, `TESTING.md` | Read-through |
| Fixed app rebuilt, DMG rebuilt, installed to Applications | `build/`, `/Applications/EsyType.app` | Signature, launch, window check |

No requirement was changed to improve this report.

## 18. Outstanding work

1. **Owner:** allow the permissions again (new build), then dictate with ⌃⌥Space and Right ⌥. Confirm that it types and doesn't crash.
2. **Owner:** Hindi and Marathi clips with reference text, then measure the word error rate (WER) and choose the Turbo variant.
3. **Owner:** the 20-app paste matrix.
4. Show recording status and recent items in the menu bar.
5. `abort_callback` for Esc during transcription.
6. A stable signing identity (self-signed now, Developer ID before wide release).
7. Real Intel, macOS 14/15, 8 GB and 24/32 GB testing.
8. VoiceOver, keyboard and energy checks.
9. Decide on pause/resume, a free-form shortcut recorder and Phase 8.
10. Publish to GitHub (`gh auth login`), and choose a licence for the source code.

## 19. Unverified assumptions

- That the stop-order fix removes the crash in every case: it matches Apple's documented pattern and the crash stack, but hasn't been run.
- That pasting works in common apps (only the pasteboard logic is tested).
- That x86_64 code behaves the same on a real Intel Mac as under Rosetta.
- That Bluetooth device changes now keep recording.
- That model licences permit commercial use as summarised (not legal advice).
- That the Liquid Glass appearance is correct on screen (offscreen rendering can't show it).

## 20. Recommendation for the next development phase

Don't start new features yet. Run a short **stabilisation phase**:

1. The owner confirms real dictation with this build (permissions, both shortcuts, a few apps).
2. Add menu-bar recording status and a recent-transcripts list, which are missing MVP items.
3. Hindi and Marathi WER with the owner's clips.
4. Set up a stable signing identity so testing doesn't keep resetting permissions.

Then decide between Phase 8 (refinement) and the remaining partial items.

## Scores (out of 100)

| Area | Score | Reasoning |
|---|---|---|
| Requirements compliance | 62 | Core MVP built. Several brief items are partial (menu bar, conflicts, performance class, available memory) and some aren't started (signing, updates, pause/resume, LLM). Priority languages are untested. |
| Documentation quality | 72 | Thorough and honest about evidence. But the architecture document was badly stale until this audit, and the history notes are verbose. |
| Code quality | 70 | Clean, small, warning-free and well-tested core. But a crash-level lifecycle bug shipped in the app layer, which has no automated tests. |
| Architecture | 80 | Simple, appropriate boundaries, no needless abstractions. Small debts: the blocking decode in the shared pool, untestable glue in the executable target. |
| Security | 74 | Strong local-only design, verified downloads, private files, no transcript logging. Weakened by unsigned distribution and library validation turned off in dev builds. |
| Testing | 52 | Good unit and engine tests, real downloads and benchmarks. No UI or app-level tests, and the end-to-end path was never run by an automated test. That's why the crash wasn't caught. |
| User experience | 58 | Polished visuals and good onboarding. But the first real use crashed, permissions reset with every build, and the menu is missing status and recent items. |
| Performance readiness | 76 | Measured and comfortably within the latency target on the M4. Idle memory above the original target (accepted); battery and other hardware not measured. |
| Production readiness | 30 | Not notarised, the crash fix is unconfirmed, priority languages and other hardware untested, no update mechanism. Not ready for public release. |
