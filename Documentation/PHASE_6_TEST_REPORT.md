# Phase 6 test report: matching the Windows design

Date: 2026-11-22.
- **Source:** the Windows team's "EsyType Next Generation" mockups (Phases 6–11).
- **Mac:** MacBook Air M4, macOS 26.5.2.
- **App:** `/Applications/EsyType.app`, signed "EsyType Dev". No new model.

Statuses: **PASS** (real app on this Mac), **PASS (Simulated)** (unit test), **PASS (render)** (offscreen screenshot), **NOT TESTED**.

## What maps to what

| Windows design | Mac |
|---|---|
| Sidebar: Dictation, EsyMeet, Insights · Your words: History, Dictionary, Snippets, Style, Scratchpad · Settings | Same order and groups. EsyMeet shows "Soon". |
| "Local · Base · 4 threads" under the sidebar | "Local · Small · Metal" (live: model and engine) |
| Dictation: "Hold Ctrl+Space, speak, release." + toggle line | "Hold Right ⌥, speak, release." + "Or press ⌃⌥Space…" (follows your shortcut settings) |
| Week summary: words, minutes saved, dictations → Insights | Same, a button that opens Insights |
| Try it; Last dictation (app · spoken · typed in · Clean · text) | Same; "Clean" shows when Text Cleanup changed something |
| Pill after dictation: "Typed into Word · Undo" for 60 s | "Typed into ‹app› · Undo · ✕" for 60 s |
| Insights: words since, wpm, time saved (40 wpm, how?), meetings; This week by category | Same. Meetings shows "—" until EsyMeet. The typing speed is adjustable. |
| Style, Scratchpad | Style = the Stage 4 cleanup rules; Scratchpad = a page saved on this Mac |
| Onboarding step 3 "About you", step 4 "Appearance" (Follow / Dark / Light) | Same (steps 3 and 4 of 9) |
| Georgia italic, Mica/Acrylic, Ctrl shortcuts | Not copied. The Mac keeps Instrument Serif (the designed font, bundled here) and native macOS materials and shortcuts. |
| EsyMeet (prompt, live transcript, history, Copy for AI) | **Not built.** Next phase. |

## Results

| Test | Result | Evidence |
|---|---|---|
| Sidebar groups and order | PASS | Accessibility: Dictation, EsyMeet (Soon), Insights; heading "Your words"; History…Scratchpad; Settings; "Local · Small · Metal" |
| Dictation home | PASS | Instruction line, week figures, Try it, Last dictation card |
| Pill "Typed into TextEdit · Undo" | PASS | Read during the 60 s window |
| Pill Undo button | PASS | Document returned to "Phase 6 test. " |
| Week figures and Last dictation update | PASS | "17 words this week · 2 dictations"; "TextEdit · 4 s spoken · typed in 0.6 s" |
| Insights | PASS | 17 words since 22 Nov; 115 wpm; time saved; Documents 100% |
| `insights.json` numbers only | PASS | words, ms, counts, category; no text, no app names |
| Scratchpad dictation and save | PASS | "Draft for the scratch pad." in the page and in `scratchpad.txt` (0600) |
| Onboarding About you / Appearance | PASS (render) | `screenshots/phase6/onboarding-*.png` |
| Insights maths and categories | PASS (Simulated) | 4 tests: totals, wpm, time saved (117 s worked example), shares, empty data, never negative, store |
| Regression: push-to-talk + cleanup + dictionary + snippet | PASS | "We need to send Project FALCON-9 Best regards,⏎EsyType Test Signature⏎नमस्ते from the test." |
| Privacy check / crashes | PASS | 6/6; none new |

## Not tested and limitations

- The onboarding steps weren't clicked in the real app (your onboarding is already done). They were checked by render.
- The new VoiceOver label for the Dictation heading wasn't read back: the window opened on another Space.
- An undone dictation still counts in Insights.
- Browsers count as "Other": EsyType doesn't read which website is open.
- EsyMeet is not built.
