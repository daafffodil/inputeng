# inputeng

[中文](README.md) | [English](README_EN.md)

[![Windows validation](https://github.com/daafffodil/inputeng/actions/workflows/validate.yml/badge.svg)](https://github.com/daafffodil/inputeng/actions/workflows/validate.yml)
[![Latest release](https://img.shields.io/github/v/release/daafffodil/inputeng)](https://github.com/daafffodil/inputeng/releases/latest)
[![Code license: MIT](https://img.shields.io/badge/code%20license-MIT-blue.svg)](LICENSE)

inputeng is a Simplified Chinese input scheme built on Rime. Chinese candidates can display a short English gloss, while direct English input can display a short Chinese gloss. Selecting a candidate commits only the original word; the annotation is never inserted into your document.

![inputeng candidate window](docs/assets/inputeng-preview.png)

> The Windows build has been validated with Weasel and a real librime runtime. macOS now uses the same core features and passes installation/script tests on a macOS GitHub runner; final visual and typing acceptance on a real Mac is still pending.

## Features

- Simplified Chinese full Pinyin with short English candidate annotations.
- Press `F4` to switch directly between full Pinyin and Sogou Double Pinyin.
- Direct English input with short Chinese annotations when the text is not parsed as Pinyin.
- Offline-first dictionaries; AI is not required for normal use.
- A manually composed Chinese phrase is learned locally after its first successful commit.
- Configurable highlight color, Chinese candidate size, and English annotation size.
- Optional DeepSeek fallback for short terms missing from the offline dictionary.

## Download and installation

### Windows

[Download the latest release](https://github.com/daafffodil/inputeng/releases/latest)

1. Download and fully extract `inputeng-windows-v0.6.2.zip`.
2. Double-click `install.cmd`.
3. If Weasel is missing, the installer can download a pinned official build from Rime's GitHub release and verify its SHA-256 checksum.
4. Select **Weasel** in the Windows input method list; the inputeng scheme is enabled inside it.
5. Open **inputeng Settings** from the Start menu to adjust appearance, inspect dictionary information, or configure AI translation.

Starting with v0.6.1, the installer no longer changes Weasel's shared Windows system name or icon by default and never asks the user to sign out just to refresh branding. Seeing “Weasel” in `Win + Space` is expected and does not affect the inputeng scheme, candidate annotations, or settings. Run `uninstall.cmd` to remove the managed inputeng files. The uninstaller does not remove Weasel or learned phrases.

### macOS

The macOS v0.6.2 build requires a recent official Squirrel release. It shares the same optimized Chinese core, native bidirectional offline annotations, full/Sogou Double Pinyin schemas, F4 toggle, first-commit phrase learning, and optional DeepSeek fallback as Windows. Its API key is stored in the macOS Keychain. See the [macOS instructions](platforms/macos-rime/README.md).

## v0.6.2 input-latency optimization

Offline annotations, direct English input, F4 switching, and phrase learning now use native librime components. Only one lightweight Lua filter remains on the per-key path to read the AI cache; Lua no longer loads and searches roughly 59k offline glosses while typing. In an isolated Windows + Weasel 0.17.4 benchmark, median per-key processing fell from about 8.86 ms to 0.32 ms, and p95 fell from about 17.13 ms to 1.19 ms.

## AI translation and API keys

AI translation is optional. **No maintainer API key or shared API key is included in the repository or release archives.**

- Every user supplies their own DeepSeek API key locally.
- Windows uses per-account DPAPI and macOS uses the system Keychain. Plaintext is not written to the project or Rime configuration files.
- Only short terms that are still missing from the offline dictionaries are sent. Application text, previous commits, and full input history are not sent.
- Results are cached locally to avoid duplicate requests.
- Without an API key, Chinese input and offline bilingual annotations continue to work normally.

## Dictionaries

- Chinese core: 173,036 entries. The base is a filtered Simplified Chinese subset of [Rime Ice](https://github.com/iDvel/rime-ice), plus standard character readings.
- Chinese to English: 59,873 short glosses transformed from [CC-CEDICT](https://www.mdbg.net/chinese/dictionary?page=cc-cedict).
- English to Chinese: 58,129 common-word glosses derived from [ECDICT](https://github.com/skywind3000/ECDICT).

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for provenance, modifications, attribution, and licenses. Project code is MIT-licensed; third-party dictionary data remains under its respective license.

## Privacy

inputeng contains no telemetry and does not read the clipboard or the active application's document text. Learned phrases, appearance settings, AI queues, and translation caches stay on the local machine. Missing short terms are sent to DeepSeek only after the user explicitly configures and enables the API integration.

## Build from source

Windows:

```powershell
python platforms/windows/scripts/package.py
python platforms/windows/scripts/test_package.py
```

macOS archive:

```powershell
python platforms/macos-rime/scripts/package.py
```

The full Windows candidate smoke test additionally requires a local loadable librime / Weasel runtime:

```powershell
python platforms/windows/scripts/smoke_rime.py
python platforms/windows/scripts/benchmark_rime.py --max-p95-ms 5
```

## Repository layout

```text
inputeng/
├─ platforms/
│  ├─ windows/          # Weasel schemas, installer, settings UI, and tests
│  └─ macos-rime/       # Experimental Squirrel schema and installer
├─ shared/dictionary/   # Source data for offline bilingual tables
├─ docs/                # Architecture notes and preview image
├─ licenses/            # Full third-party license texts
└─ scripts/             # Public-tree safety checks
```

## Known limitations

- The Windows build is a Weasel extension, not a standalone TSF input method.
- Weasel aligns annotations after the longest Chinese candidate on a page; the current configuration cannot independently attach every gloss at a different horizontal position.
- Rime Lua cannot redraw an already open candidate page without a new input event. An asynchronous AI result therefore appears on the next candidate refresh.
- macOS and Windows now share the same Rime core files and dictionaries. Final real-device validation of macOS installation, candidate visuals, and shortcut behavior is still pending.
- Both builds extend an official Rime frontend rather than implementing an independent system IME. The system input list may therefore keep the upstream Weasel or Squirrel name and icon.

## Contributing

Issues and pull requests are welcome. Before submitting, run the Windows package validation and make sure no API keys, caches, personal frequency data, or other machine-local data are included.
