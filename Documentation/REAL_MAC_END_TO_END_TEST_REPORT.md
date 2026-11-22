# EsyType: real-Mac end-to-end test report

Date: 2026-11-22, 18:58–19:16. Tester: Claude (automated driver) with the owner granting permissions.

## How the tests were run (read this first)

- **The real app** in `/Applications/EsyType.app`, release build. No mocks.
- **Real microphone, synthetic voice.** Each sentence was spoken through the MacBook's **speakers** by macOS
  text-to-speech (`say`, voices Samantha for English and Lekha for Hindi), and EsyType recorded it through the
  **built-in microphone**. No human voice was used. The Mac has no Marathi voice, so the Marathi sentence was read
  by the Hindi voice.
- **Real shortcuts, synthetic key presses.** A small driver posted the shortcut keys as keyboard events at the
  system (HID) level, the same path as a physical keyboard. The owner's own physical Right ⌥ hold is also in the
  app log (18:42–18:43).
- **Real apps.** The driver read back what landed in TextEdit, Notes and Safari through the macOS Accessibility
  API, and checked that the clipboard was restored afterwards. No screenshots: the driver can't capture the
  screen. The read-back text is the evidence.
- Driver sources: the session scratchpad (`e2e/drive.swift`, `fail.swift`, `read.swift`). They aren't part of the repo.

Statuses: **PASS** (tested on this Mac), **FAIL**, **BLOCKED** (prerequisite unavailable), **NOT TESTED**.

## Environment

| Item | Value |
|---|---|
| Mac | MacBook Air, Mac16,13, Apple M4, 16 GB |
| macOS | 26.5.2 |
| Free disk | 5.0 GB |
| Build | 0.1.0 release, universal (arm64 + x86_64), Hardened Runtime |
| Signing | Self-signed "EsyType Dev" certificate (since 18:2x today). Designated requirement `certificate leaf = H"cf30bd40…"`. |
| Running from | Packaged `.app` in `/Applications`, not Xcode (no Xcode installed) |
| Model | Small Q8 (`ggml-small-q8_0.bin`, 264,464,607 bytes, whisper.cpp b5454 on Metal). All 4 models are installed. |
| Language setting | Auto-detect |
| Input | MacBook Air Microphone, 48 kHz, 1 channel, converted to 16 kHz mono |

## Permissions

| Permission | Status | Evidence |
|---|---|---|
| Microphone | Granted | Recordings captured at −22 to −25 dBFS |
| Input Monitoring | Granted (added by the owner with **+**) | Log: "Hold key listener started" |
| Accessibility | Granted after the owner removed the old entry and re-allowed it with EsyType's **Allow…** button | Log: "Dictation inserted" |
| Kept across rebuilds | **PASS** | Both permissions survived 3 rebuilds and reinstalls after the self-signed certificate was introduced |

I didn't change any permission myself.

## Root cause of "it asks me to paste instead of typing"

**Accessibility wasn't allowed for the installed build.** EsyType checks this before it types. When the check
fails, it safely puts the text on the clipboard instead.

The list in System Settings showed EsyType switched on. That entry belonged to an older build: earlier builds
were signed ad hoc, and macOS tied the permission to that exact build. Re-adding the app with **+** kept the old
entry. Removing it and allowing it again through EsyType's own **Allow…** button fixed it.

To make this visible, the app now logs the reason it copies instead of typing, for example
"Copied instead of pasting: Accessibility not allowed". The stable signing certificate stops this from happening
after future rebuilds.

## Speech to text: real microphone

| # | Spoken (reference) | EsyType output | Audio | Transcribe | Notes |
|---|---|---|---|---|---|
| E1 | Hello, this is a real-world test of EsyType. I want to check whether my speech is accurately converted into written text. | Hello, this is a real world test of EZ type, I want to check whether my speech is accurately converted into written text. | 8.9 s | 0.66 s | Name heard as "EZ type". Hyphen lost. Comma instead of a full stop. |
| E2 | Today I am testing voice dictation. Can EsyType recognise my speech, insert the correct punctuation, and preserve the meaning of my sentences? | Today I am testing voice dictation. Can Essy type recognize my speech, insert the correct punctuation, and preserve the meaning of my sentences? | 10.6 s | 0.65 s | Name heard as "Essy type". US spelling "recognize". Punctuation correct. |
| E3–E7 | 5 short sentences (see the workflow section) | 4 of 5 exact | 3–4 s each | ~0.5 s | "favourite colour" became "favorite color" and a comma was lost |
| E8 | Holding the right option key also works. | Holding the right auction key also works. | 3.8 s | 0.49 s | "option" heard as "auction" |
| E9 | 37.8 s passage (110 words) | Every sentence present and in order | 37.8 s | 1.70–1.74 s | "EZ type", "16kHz", lowercase "whisper". No words lost at the end. |
| H1 | नमस्ते, मैं EsyType का परीक्षण कर रहा हूँ। क्या यह मेरी आवाज़ को सही हिंदी टेक्स्ट में बदल सकता है? | नमस्ते, मैं अच्याँटाएक का परिक्षन कर रहा हूं, क्या लिए मेरी आवाज को सही हिंदी तेक्स्त में बडल सकता है? | 8.5 s | 1.12 s | Right script and structure. About 5 of 17 words wrong, or 7 counting nukta and chandrabindu spellings. |
| M1 | नमस्कार, मी EsyType ची चाचणी करत आहे. माझे बोलणे योग्य मराठी मजकुरात रूपांतरित होते का? | नमस्कार, मीतर असिटाएक चीचाचनी करता है, माजी भोलने योगे मरादी मजकुरात रुपान तरिध होते का. | 8.7 s | 1.08 s | Poor: about 4 of 14 words correct. Read by the **Hindi** voice, so not representative of a Marathi speaker. |

**After the "EsyType" vocabulary hint (fix 5, 19:21–19:23):**
- E1 became "Hello, this is a real world test of EsyType. I want to check whether my speech is accurately converted into written text.": the name is right and the full stop is restored.
- E2 was run 4 times. The name was right every time. One run heard "Geist dictation" for "voice dictation"; three repeats were exact.
- H1: Hindi was still about as accurate as before. The Hindi voice pronounces the name differently, so it still wasn't written as EsyType. The language was still detected correctly.

**Accuracy summary:**
- English is very good, apart from the product name, which isn't a dictionary word.
- Hindi is usable but makes errors.
- Marathi is poor in this setup.
- These are single runs with a synthetic voice, not a WER study.

## Insertion into real text boxes (the key test)

| Test | Result | Evidence |
|---|---|---|
| TextEdit: text appears at the cursor | **PASS** | E2 landed at the cursor (start of the document) and "Existing text stays." moved after it. Nothing was deleted. |
| TextEdit: 5 dictations in a row at the end of the document | **PASS** (5/5) | Each typed in 0.60–0.61 s after stopping. Earlier text kept, no duplicates, clipboard restored 5/5. |
| Spacing between dictations | **FAIL → fixed → PASS** | Before: "lazy dog.Please send…". After: " This sentence should have a space before it. And so should this one." |
| Apple Notes (new note) | **PASS** | "Hello, this is a real world test of EZType in Apple Notes." typed in 0.62 s, clipboard restored. The test note is still in your Notes. |
| Safari `<textarea>` | **PASS** | The field read "Browser field: Typing into a browser text field works too." Clipboard restored. |
| Wrong window | **PASS** | Switching from TextEdit to Notes mid-recording copied the text instead of typing it ("you switched apps") |
| Message composition field | NOT TESTED | |
| Hindi and Marathi into TextEdit | **PASS** (insertion) | Devanagari text was typed correctly as received |

## Global shortcuts

| Shortcut | Result |
|---|---|
| ⌃⌥Space start/stop (hands-free), with another app in front | **PASS**: 20+ runs |
| Hold Right ⌥ (push to talk) | **PASS**: synthetic events (E8), plus the owner's physical holds in the log at 18:42 |
| Esc cancels | **PASS**: recording discarded, nothing typed |
| Hold shorter than 0.3 s | **PASS**: discarded |
| Shortcuts after restarting EsyType | **PASS**: listener ready 0.16 s after launch, dictation worked |
| ⌃⌘V paste last transcript | NOT TESTED |
| No interference with normal typing | NOT TESTED systematically. Right ⌥ plus another key cancels by design (unit test). |

## Failure scenarios

| Scenario | Result | Evidence |
|---|---|---|
| Microphone not allowed | PASS (seen earlier today) | Log 15:39:22: "Allow the microphone, then try again." |
| Input Monitoring not allowed | PASS (seen today) | "Hold key waiting for Input Monitoring permission". The Home card asks for it, and ⌃⌥Space still works. |
| Accessibility not allowed | PASS (safe fallback) | The text is copied and the pill says to press ⌘V. The log gives the reason. |
| Silence | PASS | Loudest −50.0 dBFS, so not transcribed. The on-screen message wasn't captured. |
| Very short recording | PASS | Discarded |
| Long recording (37.8 s) | PASS | Fully typed. The 30-minute cap is only covered by the Phase 9 file benchmark (Simulated). |
| Long recording, first attempt | **FAIL, not reproduced** | Once, EsyType copied instead of typing ("no editable text focus") with TextEdit in front. The rerun passed. The app now logs the exact AX error if it happens again. |
| Quit EsyType with a model loaded | **FAIL → fixed → PASS** | 2 crash reports (19:02, 19:09): whisper.cpp's Metal cleanup aborts at exit. Fixed by freeing the model in `applicationWillTerminate`. Two later quits after dictations left no crash report (19:13, 19:21). |
| Killed (SIGTERM) during recording | PASS | Exited, no crash report, microphone released |
| Quit from the menu *during* a transcription | NOT TESTED | It may still hit the exit crash, because the running task holds the model |
| Model missing or failing to load | NOT TESTED on the real app (I won't move your models). Unit test `rejectsAFileThatIsNotAModel` (Simulated). | |
| Not enough disk space | NOT TESTED on the real app. ModelStore unit tests (Simulated). | |
| Internet disconnected | BLOCKED | I won't switch off Wi-Fi. No sockets were open during dictation (see Privacy). |

## Performance (measured unless stated)

| Metric | Value |
|---|---|
| Launch to shortcuts ready | 0.16 s (19:14:26.997 → 19:14:27.159) |
| Model load | Not logged separately. The first dictation after a launch (3 s audio, 0.48 s) was no slower than warm runs. |
| Transcribe 3–4 s / 8–11 s / 38 s of English | 0.47–0.49 s / 0.62–0.66 s / 1.70–1.74 s |
| Transcribe ~8.6 s of Hindi or Marathi | 1.08–1.12 s |
| Stop → text in the field | 0.50–0.62 s (short), 1.86 s (38 s recording); polled every 100 ms |
| Memory with Small loaded | **488–500 MB** footprint. This is above the ~200 MB in ADR-16; it should fall after the 10-minute unload (not re-measured today). |
| CPU when idle | 0.3–0.4 % |
| GPU | Not measured |
| Crashes | 2 on Quit (fixed above). No hangs. |

## Inference is local

- No network sockets were open in 8 samples (`lsof`, every 6 s) taken during the 38 s dictation.
- `Scripts/privacy-check.sh`: 6/6 PASS. It checks for no open sockets and that only ModelStore uses the network
  in the source. Its other checks: no `print()` in app or engine code, nothing from whisper in the system log,
  no audio files, and history file mode 0600.
- Network code exists only in `ModelStore` (model downloads from Hugging Face). There are no transcription APIs.

## Fixes made during this test

1. The reason for copying instead of typing is now logged.
2. A space is added before a dictation when the text before the cursor doesn't end in a space (`TextCleanup.spaced`, unit-tested).
3. Quitting with a model loaded no longer crashes (`DictationController.unloadModel` on terminate).
4. A failed focus query now logs the exact AX error.
5. Whisper gets "EsyType" as a vocabulary hint, so it writes the name correctly. This is checked by
   `promptSpellsTheAppName` on all 4 models with a `say`-generated fixture. Control run: without the hint, all 4
   models fail that test.

Earlier today, from your reports:
- The Dock icon and Edit menu while a window is open.
- The Input Monitoring **Allow…** button now registers the app.
- The self-signed signing certificate.

**Regression:** 50/50 unit tests pass, and the privacy check passes 6/6 after the fixes.

## Acceptance criteria

| # | Criterion | Status |
|---|---|---|
| 1 | App launches | PASS |
| 2 | Microphone captures real sound | PASS (synthetic voice through the speakers into the real mic) |
| 3 | Local model converts it to text | PASS |
| 4 | Global shortcut works | PASS |
| 5 | Text typed directly into TextEdit | PASS (5/5 in a row, plus 6 more runs) |
| 6 | Text typed directly into Notes | PASS (1 run) |
| 7 | Permission and recording failures handled safely | PASS for the scenarios tested. Gaps are listed above. |
| 8 | Workflow succeeds repeatedly | PASS |

**Not yet proven:** a human speaker. The flow is identical, but please dictate a few sentences into TextEdit yourself.
Also not proven: Marathi accuracy with a real Marathi speaker.

## Remaining limitations

- ~~"EsyType" misheard~~ fixed by the vocabulary hint for English. In Hindi, it's still written phonetically.
- US spellings ("recognize", "color") come from Whisper. There's no British-spelling option.
- Hindi accuracy is moderate and Marathi is poor with Small. The larger Turbo model wasn't tried in this run.
- 488–500 MB of memory while the model is loaded.
- One unreproduced "no editable text focus" fallback. It's now logged.
- Quitting during an active transcription hasn't been tested.
