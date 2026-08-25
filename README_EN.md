# inputeng

[中文](README.md) | [English](README_EN.md)

[![Windows validation](https://github.com/daafffodil/inputeng/actions/workflows/validate.yml/badge.svg)](https://github.com/daafffodil/inputeng/actions/workflows/validate.yml)
[![Latest release](https://img.shields.io/github/v/release/daafffodil/inputeng)](https://github.com/daafffodil/inputeng/releases/latest)
[![Code license: MIT](https://img.shields.io/badge/code%20license-MIT-blue.svg)](LICENSE)

inputeng is a Simplified Chinese input scheme built on Rime. Chinese candidates can display a short English gloss, while direct English input can display a short Chinese gloss. Selecting a candidate commits only the original word; the annotation is never inserted into your document.

![inputeng candidate window](docs/assets/inputeng-preview.png)

> The Windows build has been validated with Weasel and a real librime runtime. The macOS build is still an experimental preview awaiting validation on a real Mac.

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

1. Download and fully extract `inputeng-windows-v0.5.9.zip`.
2. Double-click `install.cmd`.
3. If Weasel is missing, the installer can download a pinned official build from Rime's GitHub release and verify its SHA-256 checksum.
4. Select **inputeng** in the Windows input method list.
5. Open **inputeng Settings** from the Start menu to adjust appearance, inspect dictionary information, or configure AI translation.

A Windows sign-out is normally unnecessary. Run `uninstall.cmd` to remove the managed inputeng files. The uninstaller does not remove Weasel or the user's learned phrases.

### Experimental macOS build

The macOS build requires Squirrel with `librime-lua`. It currently provides offline Chinese-to-English annotations only and has not yet been validated on a real Mac. See the [macOS instructions](platforms/macos-rime/README.md).

## AI translation and API keys

AI translation is optional. **No maintainer API key or shared API key is included in the repository or release archives.**

- Every user supplies their own DeepSeek API key locally.
- On Windows, the key is encrypted for the current account with DPAPI. Plaintext is not written to the project or Rime configuration files.
- Only short terms that are still missing from the offline dictionaries are sent. Application text, previous commits, and full input history are not sent.
- Results are cached locally to avoid duplicate requests.
- Without an API key, Chinese input and offline bilingual annotations continue to work normally.

## Dictionaries

- Chinese core: 173,035 entries. The base is a filtered Simplified Chinese subset of [Rime Ice](https://github.com/iDvel/rime-ice), plus standard character readings.
- Chinese to English: 59,872 short glosses transformed from [CC-CEDICT](https://www.mdbg.net/chinese/dictionary?page=cc-cedict).
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
- The macOS build has not yet completed real-device acceptance testing and does not currently claim feature parity with Windows.

## Contributing

Issues and pull requests are welcome. Before submitting, run the Windows package validation and make sure no API keys, caches, personal frequency data, or other machine-local data are included.

