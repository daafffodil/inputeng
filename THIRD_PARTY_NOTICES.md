# Third-party notices

## CC-CEDICT

`bilingual_english.tsv` is a transformed extract of **CC-CEDICT**, a community-maintained Chinese-English dictionary published by MDBG.

- Project/download page: <https://www.mdbg.net/chinese/dictionary?page=cc-cedict>
- Editor/project information: <https://cc-cedict.org/wiki/>
- License: [Creative Commons Attribution-ShareAlike 4.0 International](https://creativecommons.org/licenses/by-sa/4.0/)

The transformed dictionary remains available under CC BY-SA 4.0. A copy is
included at `licenses/CC-BY-SA-4.0.txt`.

## Rime Ice Chinese dictionary data

`input_translate_core.dict.yaml` imports the following dictionary tables from
Rime Ice:

- `cn_dicts/8105.dict.yaml`: standard/common Simplified Chinese characters.
- `cn_dicts/base.dict.yaml`: the curated base lexicon.
- `cn_dicts/modern.dict.yaml`: a small manually reviewed supplement whose rows
  are cross-checked against current Rime Ice and Wanxiang source data.

`bilingual_sogou.schema.yaml` also adapts the Sogou double-pinyin algebra and
preedit mapping from Rime Ice's maintained `double_pinyin_sogou.schema.yaml`.

The complete extended, Tencent, and `others` tables are deliberately not
bundled, so they cannot add their long-tail candidates wholesale. The base
source is pinned for reproducibility to commit
`75e6572bebc05b49021e842949ce947882e3e4b2` (2026-08-16 data version).

- Project: <https://github.com/iDvel/rime-ice>
- Exact source: <https://github.com/iDvel/rime-ice/tree/75e6572bebc05b49021e842949ce947882e3e4b2/cn_dicts>
- Upstream credits: <https://github.com/iDvel/rime-ice/blob/75e6572bebc05b49021e842949ce947882e3e4b2/others/docs/Credits.md>
- License: GNU GPL v3 only. A copy is included at `licenses/RIME_ICE_GPL-3.0.txt`.

## Wanxiang dictionary cross-check

The manually reviewed `cn_dicts/modern.dict.yaml` supplement uses Wanxiang's
current dictionary as a second source for spelling and vocabulary validation.

- Project: <https://github.com/amzxyz/rime-wanxiang>
- License: Creative Commons Attribution 4.0 International. A copy is included
  at `licenses/WANXIANG_CC-BY-4.0.txt`.

## ECDICT

`english_chinese.tsv` is a compact common-word extract of ECDICT's free
English to Chinese dictionary database. Only a short Simplified Chinese gloss
is displayed beside an English candidate.

- Project: <https://github.com/skywind3000/ECDICT>
- License: MIT. A copy is included at `licenses/ECDICT_MIT.txt`.

## Weasel / Rime

inputeng does not bundle the Weasel installer. When the optional dependency installer is accepted, `install.ps1` downloads the unmodified installer directly from the official `rime/weasel` GitHub release and verifies its pinned SHA-256 hash.

- Weasel: <https://github.com/rime/weasel> (GPL-3.0)
- librime: <https://github.com/rime/librime> (BSD-3-Clause)
- librime-lua: <https://github.com/hchunhui/librime-lua> (MIT)
