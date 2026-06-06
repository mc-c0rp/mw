# mw — local, on-device voice dictation for macOS

A native macOS 26 (Tahoe) app that turns speech into text **entirely on your device** (whisper.cpp + Metal). It lives in the menu bar: press a hotkey → a Liquid Glass capsule slides up from the bottom of the screen with a live frequency waveform → speak → press again to transcribe and copy to the clipboard (or type it straight into the focused field). Nothing ever leaves your machine.

> Powered by [Whisper](https://github.com/ggml-org/whisper.cpp) (whisper.cpp + Metal) · Apple Silicon · macOS 26+ · SwiftUI + Liquid Glass

🇷🇺 [Русская версия →](README.ru.md)

## Features

- 🎙 **Global hotkey** (default ⌃⌥Space, rebindable) — works from any app.
- 🌊 **Liquid Glass overlay** at the bottom of the screen with a real FFT frequency visualizer and a stop button; it never steals focus, so the text lands in your active field.
- 🗣 **Multilingual** — ru / ro / en (and more), including English words inside Russian/Romanian speech. Language: Auto or fixed.
- 📋 **Output modes**: clipboard, auto-paste (⌘V) into the active app, or both. Optional "press Return after pasting".
- 🧠 **Two selectable models** (downloaded on first launch):
  - **Large-v3 Turbo** (~574 MB) — fast, lower RAM. Default.
  - **Large-v3 full** (~1.08 GB) — maximum accuracy, slower.
- ⚡️ **Smart model lifecycle**: loaded into memory on launch, unloaded after an idle timeout (configurable, default 10 min); if unloaded, recording starts immediately while the model loads in parallel.
- 🖼 **macOS 26 icons**: a Liquid Glass app icon (adapts to light/dark/tinted appearances) and a monochrome template menu-bar icon.
- 🚀 **Launch at login** (via `SMAppService`).
- 🔄 **Auto-updates** via [Sparkle](https://sparkle-project.org).

## Install

Download the latest **`.dmg`** from the [latest release](https://github.com/mc-c0rp/mw/releases/latest) (e.g. `mw-1.0.0.dmg`), open it, and drag **mw.app** into **Applications**. On first launch the speech model is downloaded automatically.

> Not notarized (no paid Apple Developer account yet): on first run, right‑click the app → **Open** to get past Gatekeeper.

## Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon (M1–M4)
- Xcode 26+ (to build from source)

## Build from source

```bash
git clone https://github.com/mc-c0rp/mw.git
cd mw
./scripts/bootstrap.sh        # fetches whisper.xcframework (Metal-enabled)
open mw.xcodeproj             # ⌘R in Xcode
```

The speech model (~574 MB) is **not stored in the repo** — the app downloads it on first launch into `~/Library/Application Support/mw/Models/`.

## macOS permissions

- **Microphone** — requested on first recording.
- **Accessibility** — only needed for auto-paste / "both" output (synthetic ⌘V). Not required for clipboard-only mode.

The app is not sandboxed (required for CGEvent/Accessibility) and is signed with hardened runtime.

## How it works

| Component | File |
|---|---|
| State & orchestration | `mw/DictationController.swift` |
| whisper.cpp engine (actor, Metal) | `mw/WhisperEngine.swift` |
| Model download / selection | `mw/ModelManager.swift` |
| Mic capture + 16 kHz resampling | `mw/AudioCaptureEngine.swift` |
| FFT bars (Accelerate) | `mw/FFTProcessor.swift` |
| Global hotkey (Carbon) | `mw/HotKeyManager.swift` |
| Floating panel (NSPanel) | `mw/FloatingPanel.swift` |
| Capsule overlay (Liquid Glass) | `mw/OverlayView.swift` |
| Text output (clipboard / ⌘V / Return) | `mw/TextOutput.swift` |
| Tabbed settings window | `mw/SettingsView.swift` |

The engine is [whisper.cpp](https://github.com/ggml-org/whisper.cpp) shipped as a prebuilt Metal XCFramework. Models come from [ggerganov/whisper.cpp on Hugging Face](https://huggingface.co/ggerganov/whisper.cpp).

## Built with

Designed and built with [Claude Opus 4.8](https://claude.com/claude-code) — Anthropic's Claude Code.

## License

[MIT](LICENSE) © 2026 mc-c0rp
