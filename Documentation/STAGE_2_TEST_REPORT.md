# Stage 2 test report: personal dictionary

Date: 2026-11-22, 20:35–20:58.
- Mac: MacBook Air M4, 16 GB, macOS 26.5.2.
- App: `/Applications/EsyType.app` 0.1.0, signed "EsyType Dev". Model: Whisper Small Q8_0 (no new model was downloaded).

Statuses:
- **PASS**: tested on this Mac.
- **PASS (Simulated)**: a unit test with made-up input.
- **NOT TESTED**: no test was done.

Real dictation used macOS `say` through the speakers into the real microphone, as in Stage 1. People were using the Mac
during the run: Claude was full-screen in its own Space and TextEdit's documents were closed once. Steps that needed
on-screen windows were limited by that; see "Not tested".

## How it works

1. **Hints.** Before transcribing, EsyType adds your replacement words to Whisper's prompt, for example
   "Hello, welcome to EsyType. OpenAI, GitHub.".
   - It adds at most 20 words and 200 characters.
   - With auto-detect, it uses "any language" and English entries. With a pinned language, it uses "any" plus that language.
   - Hints make the right spelling **more likely, never certain.**
2. **Replacements.** After Whisper (and filler removal), every active entry for the detected language is applied exactly:
   - **Case:** any capitalisation matches.
   - **Whole words only:** a match must not touch a letter, mark or digit on either side, in any script. "ai" never
     changes inside "said", and "राम" never changes inside "रामायण".
   - **Spacing:** a space in the spoken text matches any spacing ("esy  type", or a line break).
   - **Punctuation and spacing around a match are kept.** Only the matched words change.
   - **Overlaps:** the longer phrase wins ("open ai studio" beats "open ai"), then the earlier entry.
   - **One pass:** a replacement is never matched again, so "type" → "type type" can't loop.
   - **Unicode:** text is normalised first, so a nukta typed two ways still matches.
3. **Conflicts.** Same words and same language but a different replacement: the **earlier entry wins**. The later
   one shows ⚠ in Settings and is ignored. An entry for one language overrides an "any language" entry for that
   language.
4. **No fuzzy matching.** Enter what Whisper actually writes. Hindi transliterations can vary between takes.

## CSV format

```csv
recognised_text,replacement_text,language,category,enabled,description
open ai,OpenAI,en,Brand,true,"The company, not the phrase"
"say ""hi""","Say ""Hi""",,Other,false,
ईज़ी टाइप,EsyType,hi,Brand,true,
```

**Columns**
- **Required:** `recognised_text`, `replacement_text`, `language`, `category`, `enabled`.
- **Optional:** `description`.
- Columns can be in any order.

**Field values**
- **language:** empty or `any` for all languages, otherwise a Whisper code (`en`, `hi`, `mr`, …).
- **enabled:** `true`/`false`, `yes`/`no`, or `1`/`0`. Empty means true.
- **Length:** each text is at most 200 characters.
- **Line breaks:** not allowed in the spoken or replacement text.

**Encoding and limits**
- **Encoding:** UTF-8. Excel's byte-order mark is accepted.
- **Quoting:** standard CSV (RFC 4180). Commas, doubled quotes and line breaks are allowed inside quoted values.
- **Limits:** 2 MB and 10,000 rows.

**Export**
- UTF-8 with a byte-order mark, so Excel shows Devanagari correctly.
- CRLF line endings, and every value quoted.
- A value starting with `= + - @` gets a leading `'`, so spreadsheet apps can't run it as a formula. Import removes the `'` again.

**Import preview** (nothing changes until you press Import)
- **Add:** new words.
- **Existing entries that differ:** applied only if you tick "Replace…". Never silently overwritten.
- **Skipped:** identical to an existing entry, or a repeat in the file.
- **Rejected:** with the line number and the reason, for example "Line 5: “enabled” must be true or false.". This
  also covers a second row in the file with the same words but another replacement.
- **Whole-file problems** show one clear message:
  - not UTF-8
  - empty
  - too large
  - a quote that's never closed
  - missing column names

**Sample template:** Settings ▸ Dictionary ▸ CSV ▸ Save Sample Template… writes 14 example rows (brands, technical terms,
abbreviations, names, Hindi, Marathi). Each is marked "SAMPLE entry". The template is saved to a file you choose and
is never added to your dictionary.

## Unit tests (all PASS (Simulated); 78/78 in the suite)

| Area | Tests |
|---|---|
| Managing entries | add/edit/delete/enable/count; empty, multi-line, bad language and duplicates refused; search and category/language filters; conflicts reported, earlier wins |
| Matching | the brief's example ("I am developing esy type using open ai." → "…EsyType using OpenAI."); case, punctuation, whitespace (incl. non-breaking space and newline); whole words; overlapping phrases, longest first; no repeat application; repeated words with counts; language-specific over "any"; Hindi and Marathi incl. matras and composed/decomposed nukta; empty text, no rules, disabled rules, special characters |
| Hints | auto vs pinned language, punctuated prompt, 20-word cap |
| CSV | valid file with BOM, quotes, commas, multi-line values, Devanagari, line numbers; not UTF-8, empty, missing columns, unclosed quote; bad rows with reasons; export → import keeps every field incl. formula-like values; import plan add/update/skip/reject and update only on request; the sample template imports cleanly |
| Storage | save and load; file mode 0600; a damaged file is kept aside and an empty dictionary is used |

## Real Mac tests

| # | Test | Result | Evidence |
|---|---|---|---|
| R1 | Settings ▸ Dictionary in the real app | PASS | Accessibility read: search, category and language filters, "0 active of 0", CSV menu, Add Word…, the explanation text |
| R2 | Add an entry through the real Add Word sheet | PASS | Fields set and Language → English chosen through Accessibility, **Add** pressed. The list showed "project falcon → Project FALCON-9", "1 active of 1". `dictionary.json` was written with mode `-rw-------`. |
| R3 | Dictate it in TextEdit | PASS | Typed: "Worship **Project FALCON-9** today." Log: "Dictionary replacements: 1". ("Worship" is Whisper mishearing "We shipped".) |
| R4 | Restart EsyType and dictate again | PASS (log) | Log: "Dictionary loaded: 1 entries, 1 active", "Dictionary replacements: 1", "Dictation inserted". TextEdit's document was closed by someone before I could read the text back. |
| R5 | Hindi entry in real dictation | PASS | Dictated "मैं ईज़ी टाइप का परीक्षण कर रहा हूँ।" Whisper wrote "इसी ताइप". That exact spelling → EsyType (hi) was added *to the file while EsyType was stopped*, because its Settings window was on another Space. Then typed: "मैं **EsyType** का परिक्षन कर रहा हूं". |
| R6 | English entry still works with a Hindi entry present | PASS | "Project FALCON-9 works in English too." |
| R7 | Export → import of the real saved dictionary | PASS (no UI) | Same code as the menu, on the real `dictionary.json`: 1 entry exported, parsed back identical. Re-import plan: 0 add, 0 update, 1 skip, 0 reject. File: UTF-8 with BOM, CRLF. |
| R8 | Hints help and cost no punctuation | PASS | 6 `say` clips through Whisper Small: identical punctuation with and without hints. "using open ai" became "OpenI" without hints and "OpenAI" with them. |
| R9 | Settings window title and About tab | PASS (window server) | The window is now 660 pt wide (was 560, which hid About). The title fix couldn't be seen on screen (other Space). |

## Regression

| Feature | Result |
|---|---|
| Built-in EsyType hint | PASS: still the first sentence of the prompt; `promptSpellsTheAppName` passes on all 4 models |
| Recording, sounds, microphone (Stage 1) | PASS: unchanged code; every dictation above logged the MacBook Air Microphone |
| ⌃⌥Space, hold Right ⌥ | PASS. One live hold run produced "Hello to TalkStillWorks." **Not reproduced**: two repeats were spaced normally, and the same clip with and without hints gave identical text. |
| Typing into TextEdit | PASS |
| No new model downloaded | PASS: 4 model files, as before |
| Privacy check | 6/6 PASS. Dictionary logs contain counts only. |
| Crashes | No new crash reports |

## Not tested

- **CSV Import…, Export… and Save Sample Template… through the macOS file dialogs.** The code behind them is
  tested (R7 and unit tests), but the dialogs weren't clicked: EsyType's windows were on another Space.
- The edit sheet for an existing entry, the delete confirmation, the filters and the ⚠ conflict icon, by eye.
- Marathi in real dictation (no Marathi voice on this Mac). Covered by unit tests.

## Remaining limitations

- Matching is exact by design. Different takes can produce different spellings, especially Hindi and Marathi
  transliterations, so one entry may not catch every variant.
- Hints are capped at 20 words. A larger dictionary still gets every replacement, but only the first 20 words
  are hinted.
- In auto-detect, Hindi and Marathi entries aren't hinted. Pin the language in Settings ▸ Speech to hint them.
- Your dictionary now holds two test entries ("project falcon", "इसी ताइप"). Delete them in Settings ▸ Dictionary.
