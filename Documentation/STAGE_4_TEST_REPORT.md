# Stage 4 test report: Text Cleanup

Date: 2026-11-22, 21:20–21:36.
- Mac: MacBook Air M4, 16 GB, macOS 26.5.2.
- App: `/Applications/EsyType.app` 0.1.0, signed "EsyType Dev". Model: Whisper Small Q8_0 (no new model; no LLM).

The Stage 4 brief arrived cut off after section 3 (Capitalisation). Testing, documentation and completion follow
the Stage 1–3 pattern.

Statuses:
- **PASS**: tested on this Mac.
- **PASS (Simulated)**: a unit test with made-up input.
- **NOT TESTED**: no test was done.

Real dictation used macOS `say` through the speakers into the real microphone. **People were talking near the Mac**
during this run, and two dictations picked up their speech. Those runs were repeated, and both are noted below.

## How it works

1. **Protect.** Links, emails, file paths, code names (`snake_case`, `name()`, `main.swift`), numbers like 3.14 and
   abbreviations (e.g., i.e., etc., Dr.) are swapped for placeholders. No rule can change them; they're put back
   at the end.
2. **Rules,** each with a switch, all on by default:

| Rule | Does | Never does |
|---|---|---|
| Filler words (English) | removes um, umm, uh, erm, and the comma after them; "hmm" only when set off by punctuation or at a sentence start | touch "uh-oh", "umbrella", "summer"; remove a sentence's full stop; act on Hindi or Marathi |
| Repeated words (English) | "I I think", "the the cat" → one copy | remove "very very", "had had", "bye bye.", "no no no", "4 4 2", or Hindi "धीरे धीरे" |
| Repeated phrases (English, 2–5 words) | "I think, I think we should go" → "I think we should go" | remove an echo that ends the sentence ("never give up, never give up."), or three in a row |
| Punctuation and spacing | one space, no space before marks (incl. "।"), a space after , ; ! ? । before a letter, ". " before a capital, " .see" → ". see", doubled marks → one, ",." → ".", at most one blank line | change "...", "!!", "?!", "3.14", line breaks or paragraphs |
| Capitalise sentences | first letter of the text, of each sentence and line; "i" → "I" (English) | change iPhone, macOS, NASA; lowercase anything; capitalise after "e.g." |

3. **Always on:** removes Whisper's `[BLANK_AUDIO]`-style markers and closes the gaps that removals leave.
4. **Order:** Whisper → **cleanup** → Personal Dictionary → Snippets → typed. Snippet text is typed exactly as saved.

## Text Cleanup screen

The screen is under Sidebar ▸ Personalisation ▸ Text Cleanup (the "Soon" badge is gone). It contains:
- the five switches, each with a before → after example
- the "Always on" list
- **Try it**: type any text, choose English, Hindi or Marathi, and see the result with your current switches
- **"Planned, not available yet"**: spoken commands like "new line", numbers as digits, per-app styles

Settings ▸ Speech now points here instead of having its own filler switch.

## Unit tests (PASS (Simulated); 97/97 in the suite)

| Group | Covers |
|---|---|
| `cleansText` (9 cases, from Phase 7) | markers, fillers on and off, "umbrella"/"hummus" kept, Hindi untouched, the full stop after "umm." kept |
| `fillersOnlyWhereSafe` | "Uh-oh" kept; "I hmm think" kept; ", hmm," removed; Hindi "उम्मीद" untouched |
| `repeatedWordsButNotOnPurpose` | "I I", "the the" fixed; very very / had had / bye bye. / no no no / 4 4 2 / धीरे धीरे kept; switch off |
| `repeatedPhrasesButNotEcho` | the brief's example; "we need to, we need to…"; echo kept; "step by step" kept; switch off |
| `punctuationAndSpacing` | spaces before marks; ",," and ".."; "?." and ",."; "...", "?!", "!!" kept; missing spaces; " .see" (found in the real preview); paragraphs and lines; the danda; switch off |
| `capitalisationKeepsNamesAcronymsAndCode` | sentence starts; iPhone, macOS, iPad, NASA, IBM kept; "i"/"i'm" → "I", "i.e." kept; "e.g." and "etc." don't start sentences; switch off |
| `neverTouchesLinksEmailsCodeOrNumbers` | https link with `_` and `,`; email with a full stop after it; `src/main.swift`, `snake_case_name()`; 3.14, v2.0.1; `example.com.`; `www.` |
| `everythingOffOnlyStripsMarkers` | with every switch off, only markers go |

## Real Mac tests

| # | Test | Result | Evidence |
|---|---|---|---|
| R1 | Text Cleanup in the sidebar opens its screen | PASS | Accessibility: heading "Text Cleanup", the five rules, "Planned, not available yet"; no "Soon" badge |
| R2 | Try it preview | PASS **after a fix** | First run: "…the meeting .see you…" stayed, because ".see" was taken for a file extension. Fixed (protect `word.ext` only when the dot touches a word; move " ." back). Now shows "So I think we should go to the meeting. See you at www.esyai.co.uk, ok?" |
| R3 | Dictate "We need to, we need to finish the the report today." | PASS | Typed "We need to finish the report today." (twice) |
| R4 | Same with the repeat switches **off** | PASS | Typed "We need to, we need to finish the report today.": the repeat really comes from Whisper and the switch controls it. (Whisper wrote "the" once this time.) |
| R5 | "It was very very good, bye bye." | PASS | "It was very very good. Bye bye." |
| R6 | "Um, so I think, I think we should go to the meeting." | PASS (with room speech) | "…So I think we should go to the meeting." The text before it ("I'm in need of your answers.") wasn't spoken by the test; probably room speech or a misheard "Um". |
| R7 | Hindi doubling | PASS | "धीरे धीरे चलो, कभी कभी रुको।" → "दिरे दिरे चलो कभी कभी रुको." Doubles kept ("दिरे" is Whisper mishearing "धीरे"). |
| R8 | Dictionary and snippet after cleanup | PASS | "Project falcon needs my test signature." → "Project FALCON-9 needs Best regards,⏎EsyType Test Signature⏎नमस्ते from the test." |
| — | A run that picked up room speech | repeated | One "rules on" run typed Hindi that wasn't spoken. Repeated twice: both PASS (R3). |

The switches were flipped through the same preference keys the screen's switches write (`defaults write`).
Accessibility doesn't expose the grouped form's switches by name, so clicking them in the real screen is left to you.

## Regression

| Feature | Result |
|---|---|
| Dictionary, snippets, insertion into TextEdit, clipboard restore | PASS (R8) |
| Tests | 97/97 (90 before + 7 new cleanup groups) |
| Privacy check | 6/6 PASS |
| Crashes | none new |
| No new model | PASS |

## Not tested

- Clicking the switches in the real screen (flipped through their preferences instead).
- Your own voice with real hesitations. The test voice says "um" clearly, and Whisper often drops fillers itself anyway.

## Remaining limitations

- **Restarts with different words** ("I think, I believe we should") aren't removed. Only exact repeats are.
- **A deliberate repeat that carries on the sentence** is removed ("we need to, we need to act now"). Switch the
  rule off if you speak that way.
- **"hmm" in the middle of a clause** stays, on purpose: it can be meant.
- **Fillers and repeats are English-only.** Hindi and Marathi hesitations ("मतलब", "वो") are also ordinary words,
  so they aren't removed.
- **Capitals don't follow quotes:** `. "hello` stays lowercase.
