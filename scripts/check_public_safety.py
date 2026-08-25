#!/usr/bin/env python3
"""Fail if the public source tree contains secrets or machine-local data."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", "dist", "package", "__pycache__", "licenses", "upstream"}
RUNTIME_NAMES = {
    "input_translate_ai_cache.tsv",
    "input_translate_ai_chinese_cache.tsv",
    "input_translate_missing.txt",
    "input_translate_english_missing.txt",
    "input_translate_personal_phrases.tsv",
    "settings.json",
    "install-manifest.json",
    "weasel-profile-backup.json",
}

# The token prefix is split so this checker does not flag its own source.
SECRET_PATTERNS = {
    "API token": re.compile(r"(?i)\\b" + "sk" + r"-[A-Za-z0-9_-]{12,}\\b"),
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "Windows user path": re.compile(r"(?i)C:\\Users\\(?!Public\\)[^\\\r\n]+\\"),
}


def source_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT)
        if any(part in SKIP_DIRS for part in relative.parts):
            continue
        if relative.match("docs/migration-*.md"):
            continue
        files.append(path)
    return files


def main() -> int:
    findings: list[str] = []
    for path in source_files():
        relative = path.relative_to(ROOT).as_posix()
        if path.name.casefold() in RUNTIME_NAMES or path.name.casefold().startswith("input_translate_frequency"):
            findings.append(f"runtime file: {relative}")
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for line_number, line in enumerate(text.splitlines(), 1):
            for label, pattern in SECRET_PATTERNS.items():
                if pattern.search(line):
                    findings.append(f"{label}: {relative}:{line_number}")

    if findings:
        print("Public-tree safety check failed:")
        print("\n".join(f"- {item}" for item in findings))
        return 1

    print("Public-tree safety check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
