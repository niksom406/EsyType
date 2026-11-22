# EsyType: product requirements

Owner: EsyAI · Status: **approved 2026-11-22; updated for the 0.1.0 beta** · 2026-11-22

## 1. Summary

EsyType is a native macOS menu-bar app that turns speech into text in any app. You hold a shortcut, speak, release, and the text appears where your cursor is. Speech recognition runs **entirely on the Mac** with open-weight Whisper models via whisper.cpp. After a one-time model download it works offline. No account, no cloud, no audio leaves the device.

## 2. Target users

- Professionals writing a lot of email, chat and documents who want speed without sending voice to a cloud service.
- Multilingual users (English, Hindi, Marathi and other Whisper languages). Language quality will be stated per language from measurements.
- Privacy-sensitive users (legal, health, finance, education) and anyone in offline or low-connectivity settings.

## 3. Positioning

| | Wispr Flow (reference) | EsyType |
|---|---|---|
| Inference | Cloud ([Docs]: retry needs internet) | On-device |
| Offline | No | Yes, after model install |
| Account | Required | None |
| App tech | Electron, ~610 MB bundle ([Obs]) | Native Swift (target size measured in Phase 9) |
| Price model | Subscription | Free (owner's decision, 2026-11-22) |

## 4. MVP scope (v1.0)

**Must have**

1. Menu-bar app with status, start/stop, paste last transcript, recent items, settings, quit.
2. Global push-to-talk and toggle (hands-free) shortcuts, configurable. Esc cancels.
3. Floating recording overlay: live level bars, timer, cancel, and transcribing/inserted/error states.
4. Local transcription with whisper.cpp: Base, Small and Large-v3 Turbo multilingual; auto-detect or pinned language.
5. Hardware detection and model recommendation with reasons, sizes and disk check. Manual choice.
6. Model download manager: confirm → space check → download with progress/cancel/resume → SHA-256 verify → atomic install → remove with confirmation.
7. Text insertion into the focused app (paste + restore clipboard), with copy-to-clipboard fallback.
8. Deterministic text cleanup: trim, capitalisation, optional filler removal.
9. Local history: search, copy, delete, clear all, retention setting. No audio by default.
10. Onboarding: microphone, Accessibility, optional Input Monitoring, shortcut, model.
11. Settings: shortcuts, speech, models, history/privacy, permissions, launch at login, appearance.
12. Universal binary (arm64 + x86_64), macOS 14+.
13. **Recording and microphone (Stage 1, 2026-11-22):** start/stop sounds, microphone picker, no-speech warning, recording limit (default 20 min).
14. **Personal dictionary (Stage 2, 2026-11-22):** the user's words and phrases, applied as exact whole-word replacements after Whisper, and hinted to Whisper (a nudge, not a guarantee). Per entry: spoken text, replacement, language (or any), category, enabled, description. Search, filters, add, edit, delete, enable/disable, conflict warnings. CSV import (with preview, never silently overwriting), CSV export and a sample template. Stored only on the Mac; never logged.

15. **Snippets and sidebar (Stage 3, 2026-11-22):** say a trigger phrase to type saved text (multi-line, any script). Per snippet: name, trigger, text, category, language, enabled, created and modified dates. Exact whole-phrase triggers, longest first; duplicate triggers refused, ambiguous ones never expand. CSV import (preview, no silent overwrite) and export. The main window's sidebar is grouped: Main (Dashboard, Dictation, History), Personalisation (Personal Dictionary, Snippets, Text Cleanup — "Soon" until Stage 4), System (AI & Models, Settings).

16. **Text Cleanup (Stage 4, 2026-11-22):** fixed rules, each with a switch, on its own sidebar screen with a live preview: filler words, repeated words, repeated phrases (English only), punctuation and spacing, sentence capitals. Links, emails, paths, code names and numbers are never changed; nothing is reworded. Planned but not built: spoken commands ("new line"), numbers as digits, per-app styles.

17. **Dictation controls (Stage 5, 2026-11-22):** three ways to dictate — hold the push-to-talk key, press ⌃⌥Space to start and stop (hands-free/toggle), or double-tap the push-to-talk key to start and stop hands-free. Esc or ✕ cancels, ■ stops. **Undo Last Dictation** (⌃⌘Z or menu) removes the last dictation only if it's still untouched where EsyType typed it, restoring any text it replaced.

18. **Phase 6, Windows parity (2026-11-22):** the main window follows the Windows "Next Generation" design — sidebar Dictation / EsyMeet / Insights, "Your words" (History, Dictionary, Snippets, Style, Scratchpad), Settings; a Dictation home with the week's figures and the last dictation; the pill shows "Typed into ‹app›" with Undo for 60 s; Insights from daily numbers; Scratchpad; onboarding "About you" and "Appearance". EsyMeet (live meeting transcription) is the next phase and is shown as "Soon".

**Not in MVP:** pause/resume, LLM refinement (Phase 8), fuzzy or AI corrections, streaming partials, Core ML encoder, media ducking, meetings, sync, teams.

## 5. Non-functional requirements

| Area | Requirement | Verification |
|---|---|---|
| Privacy | No network traffic during dictation. No transcript in logs. No audio on disk by default. | Network monitor test with Wi-Fi off; log grep test |
| Latency | Target: text inserted ≤ 1.5 s after release for a 10 s utterance on M4/Small. **Target, not a claim.** | Phase 4/9 benchmark |
| Reliability | No lost transcript. If insertion fails, text is in history and on the clipboard. | Recovery tests |
| Memory | Idle before first dictation < 80 MB RSS; after first use ~200 MB is accepted (ggml keeps Metal state, ARCHITECTURE ADR-16, decided 2026-11-22). Model RAM shown to the user is measured. | Instruments / `footprint` |
| Accessibility | VoiceOver, keyboard, Reduce Motion/Transparency, contrast ≥ 4.5:1 | Manual checklist |
| Security | HTTPS-only downloads, SHA-256 pinned, Hardened Runtime, notarised | Release checklist |
| Compatibility | Apple Silicon verified on M4/16 GB. Intel and other RAM tiers labelled "unverified" until tested. | Test matrix |

## 6. Success metrics (local only, no telemetry)

Measured in internal testing, not collected from users: word error rate per language on the fixture set, release-to-insert latency, insertion success rate across a list of 20 common apps.

## 7. Open questions for EsyAI

1. ~~Pricing~~: free (decided 2026-11-22). Still open: a licence for EsyType's own source code.
2. ~~Signing and notarisation~~: not for the beta (decided 2026-11-22). A Developer ID is needed before wide public release.
3. Official brand gradient values and logo master files (the app icon is still provisional).
4. Support and privacy-policy URLs. Bundle identifier in use: `co.uk.esyai.esytype`.
