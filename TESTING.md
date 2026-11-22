# Testing strategy

Framework: **Swift Testing** (`import Testing`), available in the installed Command Line Tools. XCTest and XCUITest need Xcode, which isn't installed (ARCHITECTURE ADR-1). Every result is labelled **Real device**, **Simulated** (mocked hardware values) or **Unverified**.

## Hardware available

| Configuration | Status |
|---|---|
| Apple M4, 16 GB, macOS 26.5.2 (MacBook Air 15", Mac16,13) | **Real device** |
| Apple Silicon 8 GB / 24 GB / 32 GB+ | Unverified: simulated profiles only |
| Intel Macs | Unverified: universal binary builds, runtime untested. Needs a real Intel Mac or a tester. |
| macOS 14 / 15 | Unverified: needs a test machine or VM |

## Test layers

| Layer | What | How |
|---|---|---|
| Unit | Recommender, disk maths, catalogue integrity (sizes/hashes well-formed), checksum verifier, downloader state, history store (insert/search/delete/retention), text cleanup, dictation state machine, resampler | `swift test` |
| Integration | Whisper load/transcribe on fixtures (skipped if the model is absent); download from a local fixture server; SQLite migration | `swift test --filter Integration` |
| Audio pipeline | Converter output rate/format; level computation on synthetic sine/silence; 30-minute buffer cap | Unit + manual mic test |
| Shortcuts | State machine is unit-tested. Real key events are covered by a manual checklist (Carbon events can't be synthesised reliably in tests). | Manual |
| Insertion | Pasteboard snapshot/restore (unit). Per-app insertion matrix (manual, recorded in this file). | Unit + manual |
| Permissions | Status mapping logic (unit). Grant/revoke flows (manual checklist). | Mixed |
| UI | Manual checklist per screen: VoiceOver, keyboard, Reduce Motion, Reduce Transparency, light/dark | Manual (no XCUITest yet) |
| Recovery | Kill during download → resume or clean; corrupt model → rejected; mic unplugged mid-recording → graceful stop; insertion fails → clipboard + history | Integration + manual |
| Privacy | No outbound connections during dictation (Little Snitch-style check or `nettop`); log content scan | Manual + script |

**Status of these layers in 0.1.0:** unit tests exist for every Core module (47 tests). Integration tests for the engine run against installed models. **Not implemented:** UI tests (XCUITest needs Xcode), automated shortcut and permission tests, an SQLite migration test (no migrations yet), the microphone-unplug recovery test (needs hardware). These are covered by the manual checklists below or listed as open in `Documentation/FINAL_QUALITY_AUDIT.md`.

## Benchmarks (Phase 4 / 9)

Per model × language on the real device: model load time (cold/warm), first-result latency, RTF, peak RSS (`footprint`/`/usr/bin/time -l`), CPU %, energy impact (Activity Monitor, approximate), WER/CER against reference transcripts, and 30-minute recording stability.

Rules: no speed or accuracy claim in the UI or marketing without a row in this file.

## Running

- Unit tests: `Scripts/test.sh` (wraps `swift test` with the Command Line Tools paths for Swift Testing).
- App: `Scripts/build-app.sh`, then `open build/EsyType.app`. To see onboarding again: `defaults delete co.uk.esyai.esytype`, or use **Welcome Guide…** in the menu.
- Layout snapshots (Debug only): `swift build && .build/arm64-apple-macosx/debug/EsyType --render-snapshots <folder>`.

## Results

**Correction (2026-11-22, after the audit):** every earlier "no faults in the unified log" result in this project, and the `privacy-check.sh` log test, ran `log show` from zsh, where `log` is a shell built-in, so they checked nothing. Rechecked with `/usr/bin/log` for the last 3 hours of the running app (see `Documentation/FINAL_QUALITY_AUDIT.md`): **no faults**. The errors are macOS framework messages: App Intents can't register an unsigned app (×243), ggml's Metal shader compiler warnings (×35), CoreAudio `-10877` (×4), audio I/O overload (×2), one AppKit layout warning. `privacy-check.sh` now uses `/usr/bin/log`.


### Phase 1 (2026-11-22)

| Check | Result | Label |
|---|---|---|
| `LevelMeter`/`LevelHistory` unit tests (3) | Pass | Real device (M4) |
| `swift build`, debug and release, arm64 + x86_64 | Pass, no warnings | Real device |
| App bundle: `lipo -archs` = `x86_64 arm64`. `codesign --verify --strict` | Pass | Real device |
| App launches, onboarding opens, no faults in unified log, no crash report | Pass. RSS 65.6 MB with onboarding open. | Real device |
| Release binary contains no snapshot/debug code | Pass (`strings` finds none) | Real device |
| Layout of every screen and all 6 overlay states (offscreen, material fallback) | Pass. Images in `Documentation/screenshots/phase1/` | Real device, offscreen render |
| Liquid Glass appearance on macOS 26 | **Not checked**: can't be captured offscreen | Unverified |
| macOS 14/15 material path on a real 14/15 system | Not checked | Unverified |
| Intel (x86_64 slice) runs | Not checked: no Intel Mac | Unverified |

### Phase 2 (2026-11-22)

| Check | Result | Label |
|---|---|---|
| `DiskSpace` reserve and shortfall maths (2 tests, exact byte boundaries) | Pass | Real device (M4) |
| `Recommender` table (14 profiles: 8/16/18/24/32/64 GB Apple Silicon, Intel, benchmark thresholds) | Pass | **Simulated** profiles |
| Disk fallback to a smaller model, exact shortfall when nothing fits, Rosetta/Intel warnings | Pass | Simulated |
| `ModelCatalog` bytes and SHA-256 match `MODEL_REGISTRY.md` | Pass | Real device |
| `HardwareDetector` on this Mac (arm64): Apple Silicon, not translated, memory and disk read | Pass | Real device |
| `HardwareDetector` as x86_64 under Rosetta: translated and Apple Silicon both true | Pass (`arch -x86_64` on the test bundle; `sysctl.proc_translated` = 1) | Real device, Rosetta |
| Intel hardware detection | Not checked: no Intel Mac | Unverified |
| Onboarding shows Apple M4 · 16 GB · Whisper Small Q8_0 | Pass, `Documentation/screenshots/phase2/` | Real device, offscreen render |
| Release app rebuilt (universal, `codesign --verify --strict`), launches with no faults or crash report | Pass. RSS 46 MB | Real device |

Run the x86_64 tests under Rosetta: `swift build --build-tests --arch x86_64 -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks`, then run `swiftpm-testing-helper` with `arch -x86_64` (the arm64 helper can't load an x86_64 bundle).

### Phase 3 (2026-11-22)

| Check | Result | Label |
|---|---|---|
| Download from a file:// fixture: verified, installed, `registry.json` written, `.part` removed, progress reaches 100 % | Pass | Real device (local file) |
| Corrupt file (wrong SHA-256) and oversized file: rejected, deleted, nothing installed | Pass | Real device (local file) |
| Stale partial file + server ignoring Range: starts over and installs correctly | Pass | Real device (local file) |
| Resume: partial file of 120,000 bytes sends `Range: bytes=120000-`, a 206 is appended, result verifies | Pass | **Simulated** HTTP (URLProtocol stub) |
| Retry: 2 dropped connections then success; 3 drops then gives up after 3 attempts | Pass | Simulated HTTP |
| Duplicate guard: a second download or a remove during a download is refused; cancelling releases the guard | Pass | Simulated HTTP |
| Remove deletes only that model's file; the rest of the folder stays | Pass | Real device (temp folder) |
| All 22 tests, run twice | Pass | Real device |
| Models page and download step layouts | Pass, `Documentation/screenshots/phase3/` | Real device, offscreen render |
| Release app rebuilt, launches with no faults; snapshot mode creates no files in Application Support | Pass. RSS 47 MB | Real device |
| Real download from Hugging Face, then verify and install | **Not run**: needs your OK (81.8 MB or more) | Unverified |
| Not-enough-disk refusal inside `ModelStore` | Not unit-tested (the maths is, in `DiskSpace`) | Unverified |

**Phase 3 manual check:** Open EsyType… ▸ Models ▸ Download on Whisper Base. Watch the progress, click Cancel halfway, then Download again: it should carry on from where it stopped, show "Verifying…", then "Installed". Remove… asks first and frees the space.

### Phase 4 (2026-11-22)

Benchmark: `ESYTYPE_BENCH_MODEL=<id> Scripts/test.sh --filter benchmark`, one model per process. Clip: `jfk.wav`, 11.0 s English. Metal GPU on, whisper.cpp default threads (4), greedy decoding. "Warm" is the median of 3 runs after the first. Peak memory is the process's peak physical footprint (`task_vm_info`), which includes the test harness and Metal buffers. Load times are with the file already in the disk cache (just downloaded); a cold load after a reboot is not measured.

| Model | File | Load | First result | Warm | RTF (warm) | Peak memory | English text | Label |
|---|---|---|---|---|---|---|---|---|
| Base Q8_0 | 81.8 MB | 0.11 s | 0.18 s | 0.16 s | 0.015 | 250 MB | Correct | Real device (M4, 16 GB) |
| Small Q8_0 | 264.5 MB | 0.14 s | 0.51 s | 0.49 s | 0.045 | 504 MB | Correct | Real device |
| Turbo Q5_0 | 574.0 MB | 0.27 s | 2.25 s | 2.25 s | 0.205 | 809 MB | Correct | Real device |
| Turbo Q8_0 | 874.2 MB | 0.28 s | 2.18 s | 2.17 s | 0.197 | 1,131 MB | Correct | Real device |

| Check | Result | Label |
|---|---|---|
| Real download of all 4 models from Hugging Face via `ModelStore`, SHA-256 verified, `registry.json` written | Pass, 45 s total | Real device, real network |
| Real-network resume: Turbo Q8_0 cancelled at 74,096,804 bytes, then completed and verified | Pass | Real device, real network |
| `transcribesEnglish` for all 4 models: language detected as `en`, text contains "ask not what your country can do for you" | Pass | Real device |
| Same test, x86_64 build under Rosetta | Pass (11.3 s for all 4) | Real device, Rosetta (not a real Intel Mac) |
| A non-model file is rejected (`cannotLoadModel`) | Pass | Real device |
| whisper.cpp output silenced: no progress, segment text or log lines printed | Set in code (`print_*` = false, `whisper_log_set` no-op) | Real device (no stderr output seen in test runs) |
| Hindi, Marathi accuracy | **Not run: needs clips with reference text** | Unverified |
| Real Intel Mac, CPU-only speed | Not run | Unverified |

### Phase 5 (2026-11-22)

| Check | Result | Label |
|---|---|---|
| `DictationMachine` rules (7 tests) | Pass | Real device |
| Converter: 48 kHz mono, 44.1 kHz stereo, 16 kHz in two chunks → 32,000 ± 16 samples, sine RMS preserved | Pass | Real device (synthetic audio) |
| Bug found and fixed: `AVAudioConverter` takes at most 4,096 frames per request and **silently dropped the rest** of larger tap buffers (7–15 % of audio lost). The input is now fed in slices. | Fixed, covered by the converter test | Real device |
| Silence detection finds 0.5 s of speech inside 10 minutes of hiss | Pass | Real device (synthetic) |
| All 36 tests | Pass | Real device |
| App bundle embeds `whisper.framework` (19 MB app), deep signature valid, launches, framework loaded, no faults, ⌃⌥Space registered | Pass. RSS 48 MB before the first dictation | Real device |
| Ad-hoc build first crashed at launch: library validation refused the ad-hoc framework. Fixed by a dev-only entitlement (ADR-13). | Fixed | Real device |
| Real microphone, shortcuts, overlay levels, transcription in the app | **Not checked: needs you** | Unverified |

**End-to-end on the real app (2026-11-22, reported by the owner):** after re-allowing permissions on the installed 0.1.0 build, hold-to-talk dictation typed into the app. **Real device.** Not yet reported: hands-free, Esc, the 20-app matrix, Hindi/Marathi.

**Phase 5 manual checklist (please run):**

1. Menu bar ▸ Start/Stop Dictation (or ⌃⌥Space): the pill shows "Hands-free" with moving bars and a timer. Say a sentence, press ⌃⌥Space again (or ■). Expect "Copied", then ⌘V pastes your sentence.
2. In Settings ▸ Permissions, allow Input Monitoring, then come back to EsyType. Hold Right ⌥, speak, release: same result.
3. Tap Right ⌥ quickly, and type ⌥E / ⌥←: no pill, no orange microphone dot.
4. Start dictating and press Esc (or ✕): the pill closes and nothing is copied.
5. Start, say nothing for 3 s, stop: "No speech detected".
6. Unplug or switch the microphone (e.g. AirPods) mid-dictation: it stops and transcribes what it had.
7. While "Transcribing…", pressing the shortcut again does nothing.

### Phase 6 (2026-11-22)

| Check | Result | Label |
|---|---|---|
| Clipboard snapshot restores 2 items with 3 types; an empty clipboard stays empty; transcript is marked concealed/transient | Pass | Real device (private pasteboard) |
| ⌘V key found on the British layout | Pass (kVK_ANSI_V) | Real device |
| All 39 tests | Pass | Real device |
| App rebuilt, launches, ⌃⌥Space and ⌃⌘V registered with no conflict, no faults | Pass. RSS 48 MB | Real device |
| Pasting into real apps | **Not checked**: this session isn't allowed to control apps | Unverified |

**App compatibility matrix (please fill in).** For each app: click in a text field, dictate one sentence, and note what happened. "Inserted" = the text appeared and your previous clipboard came back (⌘V afterwards pastes what you had before). "Copied" = the pill said Copied.

| App | Result (Inserted / Copied / Failed) | Clipboard restored? | Notes |
|---|---|---|---|
| TextEdit | | | |
| Notes | | | |
| Mail (compose) | | | |
| Messages | | | |
| Pages | | | |
| Safari (a web text box) | | | |
| Chrome (a web text box) | | | |
| Chrome address bar | | | |
| Slack | | | |
| WhatsApp | | | |
| VS Code (editor) | | | |
| Terminal | | | |
| Microsoft Word | | | |
| Notion | | | |
| Finder (rename a file) | | | |
| Spotlight | | | |
| System Settings search | | | |
| A password field (any) | Should be Copied | | Must never type into it |
| EsyType's own Try it box | | | |
| Switch apps during "Transcribing…" | Should be Copied | | |

### Phase 7 (2026-11-22)

| Check | Result | Label |
|---|---|---|
| `HistoryStore`: newest first, case-insensitive search, Devanagari search, SQL characters (`%`, `'`, `;`) treated as text, limit | Pass | Real device |
| Delete one, delete all, retention (delete older than 30 days) | Pass | Real device |
| History file is 0600 and survives reopening; the app's real `history.sqlite`, `-wal`, `-shm` are all `-rw-------` | Pass | Real device |
| `TextCleanup` (9 cases: markers, fillers on/off, "umbrella"/"hummus" untouched, Hindi untouched) | Pass | Real device |
| whisper.cpp language list (≥ 99, includes hi and mr) | Pass | Real device |
| All 44 tests | Pass | Real device |
| Settings and History layouts | Pass, `Documentation/screenshots/phase7/` | Real device, offscreen render |
| Snapshot mode uses a throwaway history file, never the user's | Pass | Real device |
| Release app rebuilt, launches, no faults | Pass. RSS 48 MB | Real device |
| Open at login, shortcut changes, language/translate in real dictation | **Not checked: needs you** | Unverified |

**Phase 7 manual checklist (please run):**

1. Dictate twice. Open EsyType… ▸ History: both appear, newest first, with the app name. Search finds a word from one of them.
2. Copy and Delete on a row work. Clear All… asks first.
3. Settings ▸ History & Privacy ▸ Keep history: Don't keep history. Dictate: nothing new appears.
4. Settings ▸ Shortcuts: switch hands-free to ⌃⇧Space. ⌃⇧Space now works and ⌃⌥Space doesn't. The Home page shows the new shortcut.
5. Settings ▸ Speech ▸ Language: Hindi. Dictate in Hindi: Devanagari text. Then turn on Translate to English: English text.
6. Settings ▸ General ▸ Open at login: on. Log out and in: EsyType is in the menu bar. (Ad-hoc builds may need re-approving in System Settings ▸ General ▸ Login Items.)

### Phase 9 (2026-11-22)

Benchmarks: `ESYTYPE_BENCH_MODEL=<id> Scripts/test.sh --filter benchmark` (add `ESYTYPE_CPU=1` for CPU only, `ESYTYPE_THREADS=n`). Clip: `jfk.wav` 11 s; "3 s" is its first 3 seconds. Median of 3 warm runs. Memory is the process's physical footprint. Label: **Real device (M4, 16 GB)**.

| Model | Backend | Load | 11 s clip | 3 s clip | RTF | Peak | After unload |
|---|---|---|---|---|---|---|---|
| Base Q8_0 | Metal | 0.11–0.17 s | 0.16 s | 0.13 s | 0.015 | 253 MB | 140 MB |
| Small Q8_0 | Metal | 0.21–0.23 s | 0.49 s | 0.42 s | 0.045 | 505 MB | 158 MB |
| Turbo Q5_0 | Metal | 0.61 s | 2.26 s | 2.22 s | 0.206 | 810 MB | 183 MB |
| Turbo Q8_0 | Metal | 0.78 s | 2.17 s | 2.11 s | 0.197 | 1,132 MB | 204 MB |
| Base Q8_0 | CPU, 4 threads | 0.12 s | 2.25 s | 2.29 s | 0.204 | 260 MB | 69 MB |
| Base Q8_0 | CPU, 10 threads | 0.09 s | 1.82 s | 1.88 s | 0.165 | | |
| Small Q8_0 | CPU, 4 threads | 0.22 s | 10.15 s | 10.46 s | 0.923 | 510 MB | 73 MB |
| Small Q8_0 | Metal, 8 threads | | 0.56 s | 0.46 s | 0.051 | | |

Findings: a 3 s clip costs almost as much as 11 s (whisper always encodes a 30 s window). CPU-only is 5–20× slower than Metal, which supports Base as the Intel default. CPU on an Intel Mac will be slower than CPU on the M4 (unverified).

| Check | Result | Label |
|---|---|---|
| 30 min of audio (163 × jfk.wav) in one call, Small, Metal | 47 s, 163/163 found, peak 969 MB | Real device |
| Load/unload Small 4 times (Metal) | After each unload: 156, 162, 163, 165 MB, no growth beyond ~3 MB/cycle | Real device |
| Same on CPU | 72, 78, 82, 82 MB | Real device |
| `malloc_zone_pressure_relief` after unload | No effect (the memory isn't free memory waiting to be returned) | Real device |
| App idle before any dictation | RSS 48 MB, CPU 0.0 % | Real device |
| App idle after dictation + unload | Expected ~200 MB from the measurements above. **Above the 80 MB target.** | Inferred, not measured in the app |
| `Scripts/privacy-check.sh` against the running app | 6/6 pass | Real device |
| Contrast (WCAG) of status text on the canvas, light / dark | Warning 5.7 / 14.4:1, success 5.1 / 10.1:1 (were 1.4 and 2.1:1 in light mode) | Calculated |
| All 47 tests | Pass | Real device |

**Phase 1 manual checklist (please run on the real app):**

1. First launch shows onboarding. Microphone **Allow** shows the system prompt and the row turns green.
2. Accessibility **Open System Settings** opens the right pane. Switching EsyType on turns the row green within about 1 s. (Ad-hoc builds lose this grant after every rebuild. Since 2026-11-22, local builds are signed with the self-signed "EsyType Dev" certificate, whose designated requirement is `certificate leaf = H"cf30bd40…"`, so grants persist across rebuilds. Unverified until the next rebuild after permissions are allowed.)
3. Menu bar ▸ **Preview Recording Overlay**: the pill appears bottom-centre above the Dock on the screen with the pointer, and doesn't take focus from the app you're typing in. ■ jumps to Transcribing. ✕ closes it.
4. Settings ▸ General ▸ Appearance: Light/Dark/System switches every open window.
5. VoiceOver (⌘F5): onboarding steps read their titles and buttons. The overlay announces "Recording", "Transcribing", "Inserted".
6. Accessibility settings ▸ Display: Reduce Motion (static bars, no pulse) and Reduce Transparency (opaque pill).
7. Keyboard only: Tab moves through onboarding buttons, Return triggers Get started and Finish.

## Real-Mac end-to-end test (2026-11-22)

See `Documentation/REAL_MAC_END_TO_END_TEST_REPORT.md`. Real app, real microphone, synthetic voice (macOS `say` through the speakers), and synthetic HID key events. Results: TextEdit insertion 5/5 in a row, Notes 1/1, Safari 1/1, hold and toggle shortcuts PASS. Two fixed bugs: crash on Quit with a model loaded, and missing space between dictations. Labelled Real device (synthetic voice).

## Stage 1: recording and microphone (2026-11-22)

See `Documentation/STAGE_1_TEST_REPORT.md`. Unit: `RecordingMonitorTests` (6, Simulated levels), `microphoneCheckVerdicts` (Simulated), `recordingSoundsExistOnThisMac` and `listsThisMacsMicrophones` (Real device), `resolvesTheChosenMicrophoneOrFallsBack` (Simulated). 60/60 pass. Real app runs (macOS `say` through the speakers into the real microphone, synthetic HID shortcuts): sounds, warnings, device choice, fallback, default switch, 20 s and 75 s limits, TextEdit and Safari insertion. Not tested: physical unplugging, Bluetooth and USB mics (none attached), iPhone mic, audible check of the sounds.

## Stage 2: personal dictionary (2026-11-22)

See `Documentation/STAGE_2_TEST_REPORT.md`. Unit (Simulated input): 17 dictionary/engine/CSV/store tests, 78/78 total pass. Real device: entry added through the real Settings sheet (Accessibility-driven), English and Hindi replacements in real TextEdit dictation, persistence across a restart, CSV round trip of the real saved dictionary file. Not tested through the UI: CSV import/export file dialogs.


## Stage 3: snippets and sidebar (2026-11-22)

See `Documentation/STAGE_3_TEST_REPORT.md`. Unit (Simulated input): 12 snippet tests; 90/90 total pass. Real device: every sidebar item selected in the real app; a snippet created and edited through the real sheets; its multi-line Hindi text typed into TextEdit and Apple Notes; still expanding after a restart; history keeps the unexpanded sentence. Not tested through the UI: snippet CSV file dialogs.

## Stage 4: Text Cleanup (2026-11-22)

See `Documentation/STAGE_4_TEST_REPORT.md`. Unit (Simulated input): 8 cleanup test groups (each rule, what it must not touch, protected text, all switches off), 97/97 pass. Real device: the Text Cleanup screen and its live preview in the real app; dictation into TextEdit with the repeat rules off and on; Hindi reduplication kept; dictionary and snippets still applied after cleanup.

## Stage 5: dictation controls and undo (2026-11-22)

See `Documentation/STAGE_5_TEST_REPORT.md`. Unit (Simulated events): 4 new `DictationMachine` tests (double-tap start/stop, slow taps, setting off, repeated/mixed shortcuts, taps while transcribing); 101/101 pass. Real device (HID key events, `say` into the mic): push-to-talk, toggle, double-tap; live pill read through Accessibility; Esc; default-input switch mid-recording; undo in TextEdit ×3 and Notes; a real shortcut clash with a second process.
