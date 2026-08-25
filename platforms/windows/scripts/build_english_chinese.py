#!/usr/bin/env python3
"""Build a compact common English to Simplified Chinese lookup table.

The source is ECDICT's CSV database. Only common single words with corpus,
exam-list, Oxford, or Collins metadata are retained. The result is deliberately
small enough to load once inside Rime's Lua runtime.
"""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path


WORD_RE = re.compile(r"[a-z][a-z'-]{0,29}")
POS_RE = re.compile(
    r"^(?:(?:n|v|vi|vt|a|ad|adj|adv|prep|conj|pron|num|art|aux|int|abbr)\.)+\s*",
    re.IGNORECASE,
)
LABEL_RE = re.compile(r"^\[[^]]+\]\s*")
HAN_RE = re.compile(r"[\u3400-\u9fff\uf900-\ufaff]")
SPLIT_RE = re.compile(r"[，,；;。]")
MAX_CHINESE_CHARS = 6


def parse_int(value: str) -> int:
    try:
        return int(value or 0)
    except ValueError:
        return 0


def is_common(row: dict[str, str]) -> bool:
    collins = parse_int(row.get("collins", ""))
    oxford = parse_int(row.get("oxford", ""))
    bnc = parse_int(row.get("bnc", ""))
    frequency = parse_int(row.get("frq", ""))
    tag = (row.get("tag") or "").strip()
    return bool(
        oxford
        or collins
        or tag
        or (bnc and bnc <= 60_000)
        or (frequency and frequency <= 60_000)
    )


def short_chinese(value: str) -> str:
    value = value.replace("\\n", "\n").replace("\r", "\n")
    for raw_line in value.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        line = LABEL_RE.sub("", line)
        line = POS_RE.sub("", line).strip()
        line = re.sub(r"\s*\([^)]*\)", "", line).strip()
        line = SPLIT_RE.split(line, maxsplit=1)[0].strip(" .:：；;,，")
        if not HAN_RE.search(line):
            continue
        line = re.sub(r"\s+", "", line)
        if len(line) > MAX_CHINESE_CHARS:
            line = line[:MAX_CHINESE_CHARS]
        return line
    return ""


def build(source: Path, output: Path) -> int:
    mapping: dict[str, str] = {}
    with source.open("r", encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            word = (row.get("word") or "").strip().lower()
            if word in mapping or not WORD_RE.fullmatch(word) or not is_common(row):
                continue
            chinese = short_chinese(row.get("translation") or "")
            if chinese:
                mapping[word] = chinese

    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("# Common English word | short Simplified Chinese gloss\n")
        handle.write("# Derived from ECDICT. License: MIT.\n")
        handle.write("# Source snapshot downloaded: 2026-08-25\n")
        handle.write("# Source SHA-256: 1a6947e04785db63613a92e14903cdae7954f7e84860b10e68e5c7cbb3f9c3cf\n")
        for word in sorted(mapping):
            handle.write(f"{word}\t{mapping[word]}\n")
    return len(mapping)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Path to ECDICT ecdict.csv")
    parser.add_argument("output", type=Path, help="Output english_chinese.tsv")
    args = parser.parse_args()
    count = build(args.source, args.output)
    print(f"Wrote {count} common English entries to {args.output}")


if __name__ == "__main__":
    main()
