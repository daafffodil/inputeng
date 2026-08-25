#!/usr/bin/env python3
"""Build Chinese lookup aliases for a Simplified-Chinese input scheme."""

from __future__ import annotations

import argparse
import gzip
import re
from collections import OrderedDict
from pathlib import Path


ENTRY_RE = re.compile(r"^(\S+)\s+(\S+)\s+\[[^]]*]\s+/(.*)/$")
SPACE_RE = re.compile(r"\s+")
SKIP_PREFIXES = (
    "CL:",
    "classifier for ",
    "also pr.",
)
LOW_PRIORITY_PREFIXES = (
    "variant of ",
    "old variant of ",
    "see ",
    "abbr. for ",
    "surname ",
)


def clean_definition(value: str) -> str:
    value = value.replace("\t", " ").replace("\r", " ").replace("\n", " ")
    return SPACE_RE.sub(" ", value).strip(" ;")


def choose_gloss(definitions: list[str], max_senses: int, max_chars: int) -> str:
    cleaned: list[str] = []
    seen: set[str] = set()

    for raw in definitions:
        value = clean_definition(raw)
        if not value or value.startswith(SKIP_PREFIXES):
            continue
        key = value.casefold()
        if key not in seen:
            cleaned.append(value)
            seen.add(key)

    if not cleaned:
        return ""

    preferred = [d for d in cleaned if not d.casefold().startswith(LOW_PRIORITY_PREFIXES)]
    ordered = preferred + [d for d in cleaned if d not in preferred]

    selected: list[str] = []
    for value in ordered:
        proposal = "; ".join(selected + [value])
        if selected and len(proposal) > max_chars:
            break
        selected.append(value)
        if len(selected) >= max_senses or len(proposal) >= max_chars:
            break

    gloss = "; ".join(selected)
    if len(gloss) > max_chars:
        gloss = gloss[: max_chars - 1].rstrip(" ;,.") + "…"
    return gloss


def build(source: Path, output: Path, max_senses: int, max_chars: int) -> tuple[int, dict[str, str]]:
    entries: "OrderedDict[str, list[str]]" = OrderedDict()
    metadata: dict[str, str] = {}
    opener = gzip.open if source.suffix == ".gz" else open

    with opener(source, "rt", encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if line.startswith("#! ") and "=" in line:
                key, value = line[3:].split("=", 1)
                metadata[key] = value
                continue
            if not line or line.startswith("#"):
                continue

            match = ENTRY_RE.match(line)
            if not match:
                continue
            traditional, simplified, definition_blob = match.groups()
            definitions = [part for part in definition_blob.split("/") if part]
            entries.setdefault(simplified, []).extend(definitions)
            # Luna Pinyin candidates may retain a Traditional genuine text even
            # when the simplifier displays Simplified Chinese. Keep this alias
            # only for internal lookup; it does not enable a Traditional scheme.
            if traditional != simplified:
                entries.setdefault(traditional, []).extend(definitions)

    output.parent.mkdir(parents=True, exist_ok=True)
    written = 0
    with output.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("# Chinese lookup aliases | English gloss\n")
        handle.write("# The user-facing input scheme outputs Simplified Chinese only.\n")
        handle.write("# Derived from CC-CEDICT, published by MDBG.\n")
        handle.write("# License: CC BY-SA 4.0 https://creativecommons.org/licenses/by-sa/4.0/\n")
        if metadata.get("date"):
            handle.write(f"# Source date: {metadata['date']}\n")
        for headword in sorted(entries):
            gloss = choose_gloss(entries[headword], max_senses=max_senses, max_chars=max_chars)
            if gloss:
                handle.write(f"{headword}\t{gloss}\n")
                written += 1

    return written, metadata


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="CC-CEDICT .txt or .txt.gz file")
    parser.add_argument("output", type=Path, help="Output bilingual_english.tsv")
    parser.add_argument("--max-senses", type=int, default=2)
    parser.add_argument("--max-chars", type=int, default=64)
    args = parser.parse_args()

    written, metadata = build(args.source, args.output, args.max_senses, args.max_chars)
    print(f"Wrote {written} Simplified/Traditional lookup aliases to {args.output}")
    if metadata:
        print("Source metadata:", metadata)


if __name__ == "__main__":
    main()
