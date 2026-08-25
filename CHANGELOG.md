# Changelog

## v0.6.1

- Stopped applying Windows TSF name/icon branding during normal installation, avoiding an unnecessary administrator prompt and global changes shared by every Weasel scheme.
- Removed the Windows sign-out/sign-in prompt; seeing the upstream Weasel name or icon in the system input list is now treated as harmless.
- Preserved older branding metadata during upgrades so uninstall can still restore changes made by v0.6.0 or earlier.

## v0.6.0

- Brought macOS to core feature parity with Windows: the same curated Simplified Chinese dictionary, bidirectional offline glosses, full/Sogou Double Pinyin, F4 switching, first-commit phrase learning, and optional DeepSeek fallback.
- Added a macOS Keychain-backed API configuration flow, background LaunchAgent worker, native dialog settings entry, theme/font controls, safe managed-file uninstall, and macOS CI tests.
- Fixed the Windows unattended dependency path with explicit download/install consent switches and pinned hash verification.
- Stopped claiming that Windows TSF branding is immediately visible after registry writes; the installer now warns that sign-out/sign-in may be required and documents the shared Weasel profile boundary.

## v0.5.9

- Renamed the public project and software to **inputeng**.
- Added Chinese and English public documentation and a candidate-window preview.
- Simplified the dictionary settings page to user-facing counts and selection criteria.
- Added a public-tree safety check, CI validation, and complete third-party notices.
- Confirmed that release archives contain no API key; every user configures their own optional DeepSeek key locally.

## v0.5.8

- Reduced the dictionary page from a development diagnostics panel to two user-facing cards.
- Kept only the Chinese core count and basis, plus offline bilingual glossary counts and sources.

## v0.5.7

- Expanded the filtered Chinese base lexicon while retaining explicit exclusions for confirmed low-quality candidates.
- Added controlled modern vocabulary coverage and offline glosses.
