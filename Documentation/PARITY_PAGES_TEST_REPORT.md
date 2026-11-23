# Windows parity: Dictionary, Snippets, History, Style, Scratchpad

Date: 2026-11-23.
- Mac: MacBook Air M4, macOS 26.5.2.
- App: `/Applications/EsyType.app`. No new model.

Statuses: **PASS** (real app on this Mac), **PASS (Simulated)** (unit test with made-up input), **PASS (render)** (offscreen screenshot), **NOT TESTED**.

## What the Mac now has (from the Windows screenshots)

| Page | Features |
|---|---|
| Dictionary | Word / Correction; hint switch (off by default, as on Windows); search; enable, edit, delete; Import (CSV or JSON, preview, no silent overwrite); Export CSV / JSON to Downloads; Delete all; built-in product names (29, switchable, your entries win) |
| Snippets | When I say / Insert (0 of 4,000); {date} {time} {day}; Whole dictation or Anywhere (two words or more); search; Import / Export CSV / JSON; Delete all |
| History | Hero with totals; "Not inserted" badge and filter; Copy, **Edit**, Delete; Export CSV / JSON; Delete all; day groups, app chips, search highlight |
| Style | Six styles with the example sentence; Style for other apps; per-app rules (app icons, add from History or open apps); Custom switches and full stop; Clean rules; Try it in all six styles |
| Scratchpad | Several notes, search, new / delete / delete all; editor with word count, Copy all, Export .txt / .md |
| All pages | Hero banner: upright Georgia headline with one italic word, the voice wave, actions, ✕ to hide |

## Results

| Test | Result | Evidence |
|---|---|---|
| Style reproduces the Windows example in every style | PASS (Simulated) | `theWindowsExampleInEveryStyle`: Standard / Professional / Formal / Casual / Concise / Custom exactly as on Windows |
| Style in real dictation | PASS | TextEdit set to Professional (then restored): "Yeah I'm gonna send it tomorrow…" typed "Yes, I'm going to send it tomorrow in order to check. Basically." ×2 |
| Dictionary words, built-in names, hint switch, old entries | PASS (Simulated) | 4 tests |
| Windows CSV and JSON formats | PASS (Simulated) | Dictionary and snippet round trips; `kind,term,replacement` and `trigger,text,mode` import |
| Snippet modes and placeholders | PASS (Simulated) | Whole vs anywhere, the 2-word rule, the 4,000 limit, {day} {date} {time} on a fixed date |
| History upgrade of an old-format file, status, edit, export | PASS (Simulated) | Old row reads as inserted; "not inserted" → inserted; edit; CSV |
| Notes migration | PASS (Simulated) / real | Test migrates text. On this Mac the old `scratchpad.txt` was empty (cleared at 23:17), so there was correctly nothing to migrate. |
| All five pages open in the real app with their heroes | PASS | Accessibility read of each page's headings |
| Layout, both themes | PASS (render) | Sample data only (never your entries) |
| Regression | PASS | 122/122 unit tests |

**One run picked up something else:** the first Style dictation typed "I'll do the best 2-3 things.", probably speech in the room. Repeated twice: both PASS.

## Not tested

- Import of a real Windows export file; the Downloads exports clicked in the app; Edit on a real history row; {date} in a real dictation.
- "Not inserted" on a real dictation since the upgrade.

## Changes to know about

- **Dictionary hints are now off by default**, as on Windows. Switch them on in Dictionary if you want them. The built-in "EsyType" spelling hint is always on.
- **Text Cleanup now lives inside Style** as "Clean, before any style". The settings are the same.
- **History** has a new column (your existing entries show as typed).
- **Scratchpad** now keeps notes in `notes.json`.

Screenshots (sample data): `Documentation/screenshots/parity/` — each page in dark and light.
