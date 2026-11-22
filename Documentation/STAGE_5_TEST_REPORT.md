# Stage 5 test report: dictation controls and undo

Date: 2026-11-22, 22:10–22:22.
- Mac: MacBook Air M4, macOS 26.5.2.
- App: `/Applications/EsyType.app`, signed "EsyType Dev".

Real tests:
- **Keys:** system-level keyboard events, the same path as a physical keyboard. Right ⌥ was sent with its device flag.
- **Speech:** macOS `say` through the speakers into the real microphone.
- **Results:** read from the app's log and from TextEdit and Notes through Accessibility.

Statuses: **PASS** (real run), **PASS (Simulated)** (unit test), **NOT TESTED**.

## Activation modes

| Mode | How | Stops |
|---|---|---|
| Push-to-talk | hold Right ⌥ (or Right ⌘; Settings ▸ Shortcuts) | releasing the key |
| Toggle / hands-free (the same mode in EsyType) | press ⌃⌥Space (or ⌃⇧Space / ⌥Space) | ⌃⌥Space again, or ■ in the pill |
| Double-tap → hands-free | tap Right ⌥ twice quickly (each tap < 0.3 s, gap ≤ 0.4 s) | double-tap again, ⌃⌥Space, or ■ |
| Cancel (any mode) | Esc or ✕ | nothing is transcribed |

**Guards against mistakes**
- A single tap never opens the microphone, because recording starts only after 150 ms of holding.
- Right ⌥ used with another key (⌥E) is ignored.
- Only one session runs at a time. Extra presses while recording or transcribing do nothing.
- Taps during transcription aren't remembered.
- Double-tap can be switched off in Settings ▸ Shortcuts.

**Fn/🌐 isn't supported.** macOS gives the Globe key to emoji, Dictation and input sources, and Fn arrives only as a
modifier flag. Supporting it would need raw keyboard (HID) access. Right ⌥ / Right ⌘ are the supported keys.

## Undo Last Dictation (⌃⌘Z, or the menu bar ▸ Undo Last Dictation)

1. **When typing:** EsyType notes, in memory only, the text field, the cursor position, the exact text it typed and
   any selected text it replaced.
2. **On undo:** EsyType checks that you're in the same app, and that the field still has exactly that text at
   exactly that spot. It selects just that text (and checks the selection) and replaces it with what was there
   before. If an app won't accept that, EsyType presses Delete once, and only for that checked selection, and only
   when nothing was replaced. Then it checks the result.
3. **Otherwise** it refuses with a reason in the pill:
   - "Can’t undo: the dictated text was edited or moved"
   - "Go back to the app you dictated into"
   - "Can’t undo in this app"
   - "Nothing to undo"

   It **never sends ⌘Z**, which would undo whatever the app did last, possibly your own typing.

**Limits**
- One level of undo only.
- Typing *before* the dictation in the same field moves it, so undo refuses: safe rather than clever.
- Apps that don't report their text through Accessibility (some web and Electron editors) can't undo.
- Copied (not typed) dictations can't be undone.

## Unit tests (PASS (Simulated); 101/101 in the suite)

- `doubleTapLatchesHandsFreeAndDoubleTapStops`: the tap-1 discard, the latch, the ignored release, the stop.
- `slowTapsOrDoubleTapOffDoNotLatch`
- `repeatedAndMixedShortcutsNeverStartASecondSession`: repeated toggle events, toggle while holding, hold while recording.
- `aDoubleTapAfterTranscribingStartsFresh`
- The existing 7 machine tests: push-to-talk, short tap, modifier use, toggle, cancel, busy, limit end. The Stage 1
  monitor tests cover the duration warnings and the 30-min cap.

Undo needs a real app's text field, so it has no unit test. It's covered by the real tests below.

## Real Mac tests

| # | Test | Result | Evidence |
|---|---|---|---|
| 1 | Push-to-talk | PASS | "Recording started (hold…)" → "Push to talk works." in TextEdit |
| 2 | Toggle (⌃⌥Space ×2) | PASS | "Toggle mode works." |
| 3 | Double-tap Right ⌥ to start, double-tap to stop | PASS | "Recording started (hands-free…)" → "Double-tap hands-free works." |
| 4 | Live pill | PASS | Accessibility read during recording: "Hands-free", "Recording time 0:02", buttons "Stop and insert", "Cancel dictation" |
| 5 | Cancel with Esc | PASS | No "Recorded" line, nothing typed |
| 6 | Microphone interruption | PASS | Default input switched to Teams Audio and back mid-recording; recording continued, the sentence after was typed; default restored |
| 7 | Undo in TextEdit | PASS | The document returned to exactly its previous text |
| 8 | Type after the dictation, then undo | PASS | "Undo test. Remove only this dictation. Typed by hand." → "Undo test.  Typed by hand." (the double space is the typed text's own leading space) |
| 9 | Edit inside the dictation, then undo | PASS (refused) | "…sentXence." stayed; log "Can’t undo: the dictated text was edited or moved" |
| 10 | Notes: dictate, type after, undo | PASS | "…undo test. This line will be undone in nodes. Kept." → "…undo test. Kept." |
| 11 | Shortcut conflict | **Documented limitation** | A second process registered ⌃⌥Space: macOS returned success to it **and** to EsyType (status 0), so no conflict can be detected. The key went to EsyType, the first to register. EsyType reports only clashes macOS refuses. |
| 12 | Stages 1–4 together | PASS | "We need to, we need to send project falcon my test signature." → "We need to send Project FALCON-9 Best regards,⏎EsyType Test Signature⏎नमस्ते from the test." |
| — | Duration warnings, 30-min cap, no truncation | PASS (Stage 1) | Unchanged code; 20 s and 75 s limit runs in `STAGE_1_TEST_REPORT.md` |

**A mistake in my test tool, not the app:** my first undo-after-typing run garbled the typed text ("Y hand.Typed").
My typing tool didn't clear the Control modifier left over from the ⌃⌘Z event, so ⌃B and ⌃Y ran as editing
shortcuts. With the modifiers cleared, rows 8 and 9 pass.

## Reliability

- No private APIs (searched for `dlopen`, `NSClassFromString`, private symbols: none).
- No keyboard polling: the existing event tap is event-driven.
- The microphone is open only while recording, and released on stop, cancel and quit (`shutDown()`).
- Privacy check 6/6; no new crash reports; no new model.

## Not tested

- Double-tap with your own fingers. The timing of real taps varies, so try it.
- Physically unplugging a microphone (no USB or Bluetooth mic attached).
- Quitting during an active transcription. The microphone is released, but whisper.cpp may still be busy
  (see ADR-21).
