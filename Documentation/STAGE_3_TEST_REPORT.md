# Stage 3 test report: snippets and sidebar

Date: 2026-11-22, 21:00–21:20.
- Mac: MacBook Air M4, 16 GB, macOS 26.5.2.
- App: `/Applications/EsyType.app` 0.1.0, signed "EsyType Dev". Model: Whisper Small Q8_0 (no new model).

Statuses:
- **PASS**: tested on this Mac.
- **PASS (Simulated)**: a unit test with made-up input.
- **NOT TESTED**: no test was done.

Real dictation used macOS `say` through the speakers into the real microphone. The real app's screens were driven
through Accessibility, which selects the same controls a click would.

## How it works

- **Snippet:** name, trigger phrase, text (may span lines), category, language (or any), enabled, created and modified dates.
- **Pipeline:** Whisper → cleanup → personal dictionary → **snippets** → type into the app.
  - The dictionary can fix how Whisper spelled a trigger.
  - It never changes a snippet's saved text.
  - A snippet's text never triggers another snippet.
- **Matching** is the dictionary's, shared:
  - exact phrase, any capitalisation
  - whole words in any script ("my address" doesn't fire inside "my addresses")
  - punctuation around the trigger is kept
  - the longer trigger wins ("my home address" over "my address")
- **Ambiguity:** adding or editing a snippet with a trigger already in use (same language) is refused, naming the
  snippet that has it. If a file still holds two enabled snippets with one trigger, **neither** expands and both
  show ⚠. EsyType never guesses.
- **History** keeps what you said ("Please add my test signature."), not the expanded text. **Paste Last** pastes what was typed.
- **Storage:** `~/Library/Application Support/EsyType/snippets.json`, mode 0600. A damaged file is set aside, never
  deleted. Logs show counts only.

## Snippet CSV format

```csv
name,trigger_phrase,replacement_text,category,language,enabled,created_at,modified_at
Signature,my email signature,"Best regards,
Priya Sharma",Email,,true,2026-11-22T21:14:34.000Z,2026-11-22T21:14:44.000Z
```

- **Columns:**
  - required: `trigger_phrase`, `replacement_text`
  - optional: `name` (defaults to the trigger), `category`, `language` (empty/`any`, or `en`, `hi`, `mr`, …),
    `enabled` (true/false/yes/no/1/0), and the ISO 8601 dates (import time if missing)
- **Format:** UTF-8, standard quoting (commas, `""` and line breaks inside quoted values), formula protection,
  and the 2 MB / 10,000-row limits, all as for the dictionary.
- **Import preview:** add / existing that differ (applied only if ticked) / skipped / rejected with line and reason.

## Sidebar

| Group | Item | Opens | SF Symbol |
|---|---|---|---|
| Main | Dashboard | the former Home: permissions, shortcuts, try-it box, model | `square.grid.2x2` |
| | Dictation | shortcut pickers + Recording & Microphone settings (same preferences as Settings) | `mic` |
| | History | history | `clock.arrow.circlepath` |
| Personalisation | Personal Dictionary | the Stage 2 dictionary (same data as before) | `character.book.closed` |
| | Snippets | the new Snippets screen | `text.badge.plus` |
| | Text Cleanup **Soon** | only what exists today (filler removal, always-on tidying); says more is planned | `textformat` |
| System | AI & Models | model and language settings + model downloads | `cpu` |
| | Settings | opens the Settings window, keeps the current page selected | `gearshape` |

- **Selection:** highlighted natively, moves with the arrow keys, and is remembered across launches. The sidebar
  width adapts (190–260 pt).
- **Settings:** lost its Dictionary tab, because personalisation now lives in the sidebar.

## Unit tests (PASS (Simulated); 90/90 in the suite)

| Area | Tests |
|---|---|
| Managing | create/edit/delete/enable with created and modified dates; empty/multi-line/duplicate triggers refused (case and spacing ignored); name defaults to the trigger; the same trigger in another language allowed; search; category and language filters |
| Expansion | the brief's example with multi-line text and the full stop kept; case; whole words only; longer trigger wins; no recursion (`sig` → `sig sig`, `alpha` → `beta` ↛ `gamma`); ambiguous triggers never expand; disabled and other-language snippets don't expand; Hindi and Marathi; empty text |
| Interaction | the dictionary fixes the trigger ("e mail" → "email"), the snippet then expands, and a dictionary rule for "regards" does **not** change the snippet's "Best regards" |
| CSV | round trip of quotes, commas, newlines, `=` formula text, Devanagari and dates (to the millisecond); preview counts, conflicting rows, bad rows with line numbers (a 3-line value is counted correctly); missing column |
| Storage | persists with id and dates; file mode 0600 |
| Dictionary (Stage 2) | its 17 tests are unchanged and pass on the shared matcher |

## Real Mac tests

| # | Step | Result | Evidence |
|---|---|---|---|
| 1 | Launch; sidebar shows the three groups | PASS | Headings Main / Personalisation / System, 8 items, "Soon" on Text Cleanup |
| 2–4 | Personal Dictionary opens and shows existing entries | PASS | "project falcon → Project FALCON-9", "इसी ताइप → EsyType" |
| 5 | Snippets opens | PASS | "0 active of 0" |
| — | Every other item opens its page | PASS | Dictation (Push to talk, Microphone), History, Text Cleanup, AI & Models (model picker), Dashboard |
| 6–7 | Create "my test signature" with a 3-line text (incl. Hindi) through New Snippet… | PASS | "1 active of 1". `snippets.json` 0600 with the exact text. |
| — | Edit through the Edit sheet | PASS | Name changed. Created kept (21:14:34), modified updated (21:14:44). |
| 8–10 | Dictate "Please add my test signature." in TextEdit | PASS | Typed "Please add Best regards,⏎EsyType Test Signature⏎नमस्ते from the test." in 0.71 s; clipboard restored; log "Snippets expanded: 1" |
| 11 | Same in Apple Notes (new note) | PASS | Note text: "Stage 3 Notes Test. Best regards,⏎EsyType Test Signature⏎नमस्ते from the test." |
| 12–13 | Restart EsyType, dictate again | PASS | "Snippets loaded: 1 snippets, 1 active". Expanded again in TextEdit. |
| — | History keeps the unexpanded text | PASS | Last entries: "After the restart, my test signature.", "Please add my test signature." |

**A mistake in my test, not the app:** my first TextEdit run typed "Please add Email." because, while editing the
snippet, my script had put "Email" into the **Text to type** box instead of Category. The app typed exactly what was
saved. I restored the text through the Edit sheet and the run above passed.

## Regression

| Feature | Result |
|---|---|
| Dictionary (Stage 2) | PASS: loaded 2 entries after restart; 17 unit tests pass on the shared matcher |
| Hold Right ⌥ and ⌃⌥Space | PASS |
| Typing into TextEdit and Notes, clipboard restore | PASS |
| No new model | PASS: 4 model files |
| Privacy check | 6/6 PASS |
| Crashes | none new |
| VoiceOver badge label | fixed: "Beta" now reads "Beta" (was "Preview, not real data") |

## Not tested

- Snippets **CSV Import… / Export…** through the macOS file dialogs. The code behind them is unit-tested, including the round trip.
- Keyboard navigation of the sidebar with real arrow keys (it's the standard macOS list selection).
- The screens by eye (layout and spacing). Accessibility confirms content, not looks.

## Remaining limitations

- Triggers are exact. If Whisper writes a trigger differently ("my test signature" → "my test signiture"), it
  won't fire. Add a dictionary entry that fixes the spelling first.
- Snippet triggers aren't hinted to Whisper (ordinary words that Whisper already knows).
- A trigger at the end of a sentence keeps its full stop after the inserted text ("…from the test."), because
  punctuation around a trigger is preserved by design.
- Test data left behind:
  - the "Test signature" snippet
  - the two dictionary test entries
  - a note in Notes starting "Stage 3 Notes Test". Delete these whenever you like.
