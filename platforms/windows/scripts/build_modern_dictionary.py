#!/usr/bin/env python3
"""Build the small cross-checked modern Chinese supplement."""

from __future__ import annotations

import argparse
import unicodedata
from pathlib import Path


PLATFORM_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = PLATFORM_ROOT.parents[1]
SOURCE_ROOT = PLATFORM_ROOT / "src"
SEED_WORDS = PROJECT_ROOT / "shared" / "dictionary" / "modern_common_words.txt"


def dictionary_rows(path: Path):
    body = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip() == "...":
            body = True
            continue
        if body and line and not line.startswith("#"):
            yield line.split("\t")


def plain_pinyin(value: str) -> str:
    for accented in "üǖǘǚǜ":
        value = value.replace(accented, "v")
    return "".join(
        char
        for char in unicodedata.normalize("NFD", value)
        if unicodedata.category(char) != "Mn"
    ).lower()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rime-ice", type=Path, required=True, help="Rime Ice cn_dicts directory")
    parser.add_argument("--wanxiang-jichu", type=Path, required=True)
    parser.add_argument("--wanxiang-lianxiang", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=SOURCE_ROOT / "cn_dicts" / "modern.dict.yaml")
    args = parser.parse_args()

    rime_words: set[str] = set()
    for name in ("base.dict.yaml", "ext.dict.yaml", "tencent.dict.yaml"):
        rime_words.update(row[0] for row in dictionary_rows(args.rime_ice / name))

    wanxiang: dict[str, str] = {}
    for source in (args.wanxiang_jichu, args.wanxiang_lianxiang):
        for row in dictionary_rows(source):
            if len(row) >= 3:
                wanxiang.setdefault(row[0], row[1])

    core: set[str] = set()
    for relative in ("cn_dicts/8105.dict.yaml", "cn_dicts/base.dict.yaml"):
        core.update(row[0] for row in dictionary_rows(SOURCE_ROOT / relative))

    seeds = [
        line.strip()
        for line in SEED_WORDS.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    ]
    selected = [
        (word, plain_pinyin(wanxiang[word]), 4500)
        for word in seeds
        if word not in core and word in rime_words and word in wanxiang
    ]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("# Rime dictionary\n# encoding: utf-8\n#\n")
        handle.write("# inputeng curated modern Simplified Chinese supplement.\n")
        handle.write("# Every row is absent from the conservative core and cross-checked against\n")
        handle.write("# current Rime Ice and Wanxiang source snapshots. Fixed low weight keeps\n")
        handle.write("# established common words ahead of supplementary modern vocabulary.\n")
        handle.write('---\nname: modern\nversion: "2026.08.25"\nsort: by_weight\n')
        handle.write("columns:\n  - text\n  - code\n  - weight\n...\n")
        for word, pinyin, weight in selected:
            handle.write(f"{word}\t{pinyin}\t{weight}\n")
    print(f"Wrote {len(selected)} cross-checked modern terms to {args.output}")


if __name__ == "__main__":
    main()
