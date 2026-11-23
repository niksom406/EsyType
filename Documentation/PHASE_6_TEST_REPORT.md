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
| Georgia italic headings, Segoe UI text, purple accent, light and dark palettes, glass pill | **Matched** (follow-up the same day): Georgia italic, the system sans (the Mac counterpart of Segoe UI), the same colour tokens in both themes, the glass capsule pill. Mica/Acrylic and Ctrl shortcuts become their macOS equivalents. |
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

## Visual design (follow-up)

Rendered in both themes: `screenshots/phase6/dictation-home-light.png`, `dictation-home-dark.png`, `pill-typed-undo-light.png`, `pill-recording-dark.png`. After installing: the real sidebar was read through Accessibility, and a real dictation typed into TextEdit with the pill showing "Typed into TextEdit · Undo". Appearance: Follow Mac / Dark / Light in Settings ▸ General (segmented). Your Mac is set to Dark, the value you chose before; the new default only applies when nothing is chosen.

## Dictation home, glass, window and Dock (second follow-up)

| Check | Result | Evidence |
|---|---|---|
| Dictation home | PASS (render, both themes) | "Welcome back", dark hero with the looping waveform beside the text, numbers card (0 shown as a clear zero), Today list; `dictation-home-light.png`, `-dark.png` |
| Day streak | PASS (Simulated) | `dayStreakCountsConsecutiveDaysUpToToday` |
| Window size | PASS | Opens 1120×740; enlarged to 1253×862 (screen limit); smallest 860×632 |
| Dock | PASS | `lsappinfo`: Foreground with the window open **and** after ⌘W; no `LSUIElement` in the installed Info.plist |
| Glass pill and typing | PASS | Real dictation into TextEdit; pill "Typed into TextEdit · Undo" |
| Window glass | NOT verified on screen | Offscreen renders can't capture behind-window blur; please look at the real window |

## Insights redesign (third follow-up)

As in the Windows design: four tiles (big semibold figure, small-caps label, note), an **Activity** heatmap of the last 18 weeks (Monday-first, 5 purple shades from `--heat-0…4`, hover for a day's words) with current streak, busiest day and average per active day, and **This week** (day bars, today solid purple, days to come dashed) with the split by kind of app. Side by side when wide, stacked when narrow.

| Check | Result | Evidence |
|---|---|---|
| Layout, both themes | PASS (render, sample data) | `screenshots/phase6/insights-light.png`, `insights-dark.png` (throwaway sample days, never your numbers) |
| Real page with your numbers | PASS | Accessibility: 64 words since 22 Nov, 106 wpm, Activity 1 day / busiest 64 words, This week Sunday 64, Documents 73 % |
| Words per day, heat levels, streak | PASS (Simulated) | `wordsPerDayAndHeatLevels`, `dayStreakCountsConsecutiveDaysUpToToday` |

## Animated graphs (fourth follow-up, 2026-11-23)

- **Words per day** chart (Swift Charts, built into macOS): smooth line with a purple fill, dashed average, 7 / 30 / 90-day switch that animates. Monotone smoothing, so the line never goes above or below a real day. Fixed height scale, so the line rises from the bottom.
- **On opening Insights:** figures count up, the chart rises, heatmap squares fade in column by column, week bars grow one after another, category bars fill. With Reduce Motion everything appears at once.
- **Checked:** renders caught mid-animation (0.4 s) and finished (2.2 s) in both themes; real page through Accessibility (chart label "64 words in 30 days", switch → 7 days). The motion itself was not watched on screen.

## Not tested and limitations

- The onboarding steps weren't clicked in the real app (your onboarding is already done). They were checked by render.
- The new VoiceOver label for the Dictation heading wasn't read back: the window opened on another Space.
- An undone dictation still counts in Insights.
- Browsers count as "Other": EsyType doesn't read which website is open.
- EsyMeet is not built.
