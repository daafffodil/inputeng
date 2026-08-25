#!/usr/bin/env python3
"""Build inputeng's high-frequency subset of the Rime Ice base table."""

from __future__ import annotations

import hashlib
from pathlib import Path


PLATFORM_ROOT = Path(__file__).resolve().parents[1]
UPSTREAM_BASE = PLATFORM_ROOT / "upstream" / "rime-ice-base.full.dict.yaml"
OUTPUT_BASE = PLATFORM_ROOT / "src" / "cn_dicts" / "base.dict.yaml"
MODERN_SUPPLEMENT = PLATFORM_ROOT / "src" / "cn_dicts" / "modern.dict.yaml"
MIN_WEIGHT = 3_000
EXCLUDED_WORDS = {"雪鸮", "穴鸮", "雪下", "削下", "澍濡", "菽乳", "竖儒", "诱励"}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_common_base(source: Path = UPSTREAM_BASE, output: Path = OUTPUT_BASE) -> tuple[int, int]:
    lines = source.read_text(encoding="utf-8").splitlines()
    try:
        body_index = lines.index("...") + 1
    except ValueError as exc:
        raise RuntimeError(f"Dictionary body marker is missing: {source}") from exc

    header = lines[:body_index]
    generated_notice = [
        "#",
        "# inputeng generated common subset.",
        f"# Keeps Rime Ice base rows whose published weight is at least {MIN_WEIGHT}.",
        "# The complete pinned upstream table remains in platforms/windows/upstream/.",
        "# Regenerate with platforms/windows/scripts/build_common_base.py.",
        "#",
    ]
    insert_at = 2 if len(header) >= 2 else len(header)
    header[insert_at:insert_at] = generated_notice

    supplement_words: set[str] = set()
    supplement_body = False
    for line in MODERN_SUPPLEMENT.read_text(encoding="utf-8").splitlines():
        if line.strip() == "...":
            supplement_body = True
            continue
        if supplement_body and line and not line.startswith("#"):
            supplement_words.add(line.split("\t", 1)[0])

    kept: list[str] = []
    total = 0
    for line in lines[body_index:]:
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            raise RuntimeError(f"Malformed dictionary row: {line!r}")
        total += 1
        try:
            weight = int(parts[2])
        except ValueError as exc:
            raise RuntimeError(f"Invalid dictionary weight: {line!r}") from exc
        word = parts[0]
        if weight >= MIN_WEIGHT and word not in EXCLUDED_WORDS and word not in supplement_words:
            kept.append(line)

    words = {line.split("\t", 1)[0] for line in kept}
    required = {"学校", "输入法", "朋友", "翻译", "有时候", "普通话"}
    forbidden = EXCLUDED_WORDS
    if not required.issubset(words):
        raise RuntimeError(f"Common words were unexpectedly removed: {sorted(required - words)}")
    if words.intersection(forbidden):
        raise RuntimeError(f"Rare regression words remain: {sorted(words.intersection(forbidden))}")

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(header + kept) + "\n", encoding="utf-8", newline="\n")
    return total, len(kept)


def main() -> None:
    total, kept = build_common_base()
    print(f"Common base: {kept:,} of {total:,} rows")
    print(f"SHA-256: {sha256(OUTPUT_BASE)}")


if __name__ == "__main__":
    main()
