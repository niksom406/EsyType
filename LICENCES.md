# Licences and third-party notices

Status: updated for the 0.1.0 beta (2026-11-22). **Not legal advice.** Have a solicitor confirm before commercial release.

| Component | Use | Licence | Redistribution | Notes |
|---|---|---|---|---|
| whisper.cpp / ggml (ggml-org) | Runtime, bundled in the app | MIT | Allowed with copyright + licence notice | Pinned XCFramework |
| Whisper model weights (OpenAI) | Downloaded by the user from Hugging Face | MIT (GitHub `openai/whisper`). HF cards: Apache-2.0 for base/small, MIT for large-v3-turbo. | We don't redistribute weights. We link to the official HF repo. Notice included in About. | If we ever mirror weights, include LICENSE/NOTICE |
| GGML conversions (`ggerganov/whisper.cpp` on HF) | Model files | MIT (HF card) | As above | |
| Silero VAD (ggml conversion, `ggml-org/whisper-vad`) | **Not used** in 0.1.0 (candidate, 885 KB) | MIT (HF card) | Allowed with notice | Verify upstream silero-vad licence (MIT) at bundling time |
| Barlow font | UI font, bundled | SIL OFL 1.1 | Allowed. Include OFL text. Can't sell the font by itself. | From Google Fonts |
| Instrument Serif font | Display font, bundled | SIL OFL 1.1 | Same | From Google Fonts |
| Ponytail `AGENTS.md` | Development guidance only (not shipped) | MIT, © 2026 DietrichGebert | Not shipped in the app | Copied verbatim to `AGENTS.md` |
| EsyAI brand assets | Brand | Owned by EsyAI | — | Need master files |

**Bundled font files** (downloaded 2026-11-22 from `github.com/google/fonts`, folders `ofl/barlow` and `ofl/instrumentserif`, with `OFL-Barlow.txt` and `OFL-InstrumentSerif.txt` shipped alongside them in `Resources/Fonts/`):

| File | SHA-256 |
|---|---|
| Barlow-Light.ttf | `20b1375c0c6606701867bf34c7cc97f44087850567a36587d25abb9510b183cc` |
| Barlow-Regular.ttf | `95aa02c7c43096e0dd44d787ba6216864a67157e402adab59b35572e0c1577ea` |
| Barlow-Medium.ttf | `f8906f762cb73dca441da034bc363b2d8e2e68bc10d5c05e58717646c20cc4b4` |
| Barlow-SemiBold.ttf | `86577cb32f8abe3673db53ca0f4221e6856751a4f6730c867e00f720f8bb1fc5` |
| InstrumentSerif-Italic.ttf | `08939b8bdf534afec24ae0ef5e03f948940cd9a8fe08e7fecbad040e62327385` |
| InstrumentSerif-Regular.ttf | `498efd461f6ddfcb7a111bf9a565709d2085d48201d501ead960d93e84ffbb88` |

**whisper.cpp engine (Phase 4):** `whisper-b5454-xcframework.zip` from `github.com/ggml-org/whisper.cpp/releases/tag/b5454`, 65,816,082 bytes, SHA-256 `e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b` (matches GitHub's published digest; SwiftPM checks it on every resolve). MIT. Not bundled in the app yet; it will be in Phase 5, with its licence text in About.

**Test fixture:** `Tests/WhisperEngineTests/Fixtures/jfk.wav` from `whisper.cpp` tag `b5454`, `samples/jfk.wav`, 352,078 bytes, SHA-256 `59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e`. The repository is MIT; the recording is John F. Kennedy's 1961 inaugural address (a US federal government work, public domain). Used for tests only, not shipped.

**App icon:** provisional, drawn by `Scripts/make-icon.swift` from the EsyAI bar motif. To be replaced with artwork made from EsyAI's master logo files.

**Wispr Flow:** no code, assets, sounds, icons or copy are used. "Wispr Flow" is referenced only in internal research documents.

**Apple frameworks** are used under the Xcode/SDK licence. No private APIs (for example MediaRemote) will be used.

The app's About → Acknowledgements screen will list every bundled component with its full licence text.
