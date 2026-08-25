#!/usr/bin/env python3
"""Create a macOS-friendly ZIP and SHA-256 checksum for the MVP package."""

from __future__ import annotations

import hashlib
import shutil
import zipfile
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
UNIFIED_ROOT = PROJECT_ROOT.parents[1]
SOURCE_ROOT = PROJECT_ROOT / "src"
VERSION = (PROJECT_ROOT / "VERSION").read_text(encoding="utf-8").strip()
PACKAGE_ROOT = PROJECT_ROOT / "package"
DIST_ROOT = UNIFIED_ROOT / "dist" / "macos"
SHARED_DICTIONARY = UNIFIED_ROOT / "shared" / "dictionary" / "bilingual_english.tsv"
GLOSS_OVERRIDES = UNIFIED_ROOT / "shared" / "dictionary" / "common_gloss_overrides.tsv"
ARCHIVE_ROOT = f"inputeng-macos-v{VERSION}"
ARCHIVE_PATH = DIST_ROOT / f"{ARCHIVE_ROOT}.zip"


def add_file(archive: zipfile.ZipFile, source: Path, target: str, executable: bool) -> None:
    info = zipfile.ZipInfo.from_file(source, target)
    info.create_system = 3  # Unix; lets macOS recover executable permission bits.
    mode = 0o755 if executable else 0o644
    info.external_attr = (mode & 0xFFFF) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    archive.writestr(info, source.read_bytes())


def main() -> None:
    if PACKAGE_ROOT.exists():
        shutil.rmtree(PACKAGE_ROOT)
    shutil.copytree(SOURCE_ROOT, PACKAGE_ROOT)
    shutil.copy2(SHARED_DICTIONARY, PACKAGE_ROOT / "bilingual_english.tsv")
    shutil.copy2(GLOSS_OVERRIDES, PACKAGE_ROOT / "common_gloss_overrides.tsv")
    shutil.copy2(UNIFIED_ROOT / "LICENSE", PACKAGE_ROOT / "LICENSE")
    shutil.copy2(UNIFIED_ROOT / "THIRD_PARTY_NOTICES.md", PACKAGE_ROOT / "THIRD_PARTY_NOTICES.md")
    shutil.copytree(UNIFIED_ROOT / "licenses", PACKAGE_ROOT / "licenses")

    DIST_ROOT.mkdir(parents=True, exist_ok=True)
    if ARCHIVE_PATH.exists():
        ARCHIVE_PATH.unlink()

    with zipfile.ZipFile(ARCHIVE_PATH, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for source in sorted(PACKAGE_ROOT.rglob("*")):
            if not source.is_file():
                continue
            relative = source.relative_to(PACKAGE_ROOT).as_posix()
            target = f"{ARCHIVE_ROOT}/{relative}"
            add_file(archive, source, target, source.name in {"install.sh", "uninstall.sh"})

    digest = hashlib.sha256(ARCHIVE_PATH.read_bytes()).hexdigest()
    checksum_path = ARCHIVE_PATH.with_suffix(".zip.sha256")
    checksum_path.write_text(f"{digest}  {ARCHIVE_PATH.name}\n", encoding="ascii")
    print(f"Created {ARCHIVE_PATH}")
    print(f"SHA-256 {digest}")


if __name__ == "__main__":
    main()
