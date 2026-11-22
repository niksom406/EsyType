# EsyType

Private voice typing for macOS, by EsyAI. Hold a key, speak, and your words are typed into the app you're using.
Speech is recognised **on your Mac** with [whisper.cpp](https://github.com/ggml-org/whisper.cpp): no account,
no cloud, no audio leaves your Mac. Free.

> **Beta.** Tested on an Apple Silicon Mac (M4) with macOS 26. Intel Macs and macOS 14–15 should work but
> haven't been tested yet.

## Install

1. Download `EsyType-<version>.dmg` from [Releases](../../releases).
2. Open it and drag **EsyType** into **Applications**.
3. Open EsyType. macOS will say it can't be opened, because EsyType isn't notarised by Apple yet.
   Go to **System Settings ▸ Privacy & Security**, scroll down and click **Open Anyway** next to EsyType.
   You only do this once per version.
4. The welcome guide asks for:
   - **Microphone**: to hear you while you dictate.
   - **Accessibility**: to type the text into your app. Without it, text is copied and you press ⌘V.
   - **Input Monitoring** (optional): only for the hold-to-talk key (Right ⌥).
   - **A speech model**: it recommends one for your Mac (about 80 MB to 875 MB, downloaded once from Hugging Face
     and checked against its published SHA-256).

After installing a new version, macOS may ask for Accessibility and Input Monitoring again (they are tied to the
app's signature, which changes with each unsigned build).

## Use

| | |
|---|---|
| Hold **Right ⌥**, speak, release | Push to talk |
| **⌃⌥Space** | Hands-free: press to start, press again to stop |
| **Esc** | Cancel |
| **⌃⌘V** | Paste the last transcript again |

Change shortcuts, model, language (99 languages, or auto-detect), translation to English, and how long history is
kept in **Settings**. History is stored only on your Mac and can be cleared at any time.

## Privacy

- Audio is processed in memory and never saved.
- The only network use is downloading speech models you choose.
- Transcripts are never written to logs. History is a local file readable only by your user account.
- No analytics, no account.

## Build from source

Needs macOS 14+ and Apple's Command Line Tools (`xcode-select --install`); Xcode isn't required.

```bash
Scripts/build-app.sh        # universal build/EsyType.app
Scripts/test.sh             # unit tests
Scripts/make-dmg.sh         # build/EsyType-<version>.dmg
Scripts/privacy-check.sh    # privacy checks against the running app
```

Design and decisions: [ARCHITECTURE.md](ARCHITECTURE.md). Test results: [TESTING.md](TESTING.md).
Changes: [CHANGELOG.md](CHANGELOG.md).

## Credits

- [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (MIT) and OpenAI Whisper models (MIT).
- Barlow and Instrument Serif fonts (SIL Open Font License 1.1).

Full notices are in the app under **Settings ▸ About ▸ Acknowledgements** and in [LICENCES.md](LICENCES.md).

© 2026 EsyAI. EsyType's own code has no open-source licence yet; the app is free to download and use.
