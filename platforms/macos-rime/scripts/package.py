#!/usr/bin/env python3
"""Build the macOS package from the same Rime core used by Windows."""

from __future__ import annotations

import hashlib
import shutil
import zipfile
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
UNIFIED_ROOT = PROJECT_ROOT.parents[1]
SOURCE_ROOT = PROJECT_ROOT / "src"
WINDOWS_SOURCE_ROOT = UNIFIED_ROOT / "platforms" / "windows" / "src"
WINDOWS_SCRIPT_ROOT = UNIFIED_ROOT / "platforms" / "windows" / "scripts"
VERSION = (PROJECT_ROOT / "VERSION").read_text(encoding="utf-8").strip()
PACKAGE_ROOT = PROJECT_ROOT / "package"
DIST_ROOT = UNIFIED_ROOT / "dist" / "macos"
GLOSS_OVERRIDES = UNIFIED_ROOT / "shared" / "dictionary" / "common_gloss_overrides.tsv"
ENGLISH_CHINESE = UNIFIED_ROOT / "shared" / "dictionary" / "english_chinese.tsv"
ARCHIVE_ROOT = f"inputeng-macos-v{VERSION}"
ARCHIVE_PATH = DIST_ROOT / f"{ARCHIVE_ROOT}.zip"


def add_file(archive: zipfile.ZipFile, source: Path, target: str, executable: bool) -> None:
    info = zipfile.ZipInfo(target, date_time=(2026, 8, 26, 0, 0, 0))
    info.create_system = 3  # Unix; lets macOS recover executable permission bits.
    mode = 0o100755 if executable else 0o100644
    info.external_attr = mode << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    archive.writestr(info, source.read_bytes())


def write_macos_schema(source: Path, target: Path) -> None:
    """Keep the shared input engine but drop Weasel-only panel styling."""
    text = source.read_text(encoding="utf-8")
    marker = "\nstyle:\n"
    if marker not in text:
        raise SystemExit(f"Expected a trailing Weasel style section in {source}")
    core = text.split(marker, 1)[0].rstrip()
    target.write_text(
        core
        + "\n\n# Squirrel appearance is managed in squirrel.custom.yaml by the macOS helper.\n",
        encoding="utf-8",
        newline="\n",
    )


def main() -> None:
    if PACKAGE_ROOT.exists():
        shutil.rmtree(PACKAGE_ROOT)
    shutil.copytree(SOURCE_ROOT, PACKAGE_ROOT)

    # Keep the actual Rime schemas, curated Chinese core and Lua behavior byte
    # identical across Weasel and Squirrel. Platform-specific installers and
    # settings helpers remain under their own source trees.
    for name in ("bilingual_pinyin.schema.yaml", "bilingual_sogou.schema.yaml"):
        write_macos_schema(WINDOWS_SOURCE_ROOT / name, PACKAGE_ROOT / name)
    shutil.copy2(
        WINDOWS_SOURCE_ROOT / "input_translate_core.dict.yaml",
        PACKAGE_ROOT / "input_translate_core.dict.yaml",
    )
    shutil.copytree(WINDOWS_SOURCE_ROOT / "cn_dicts", PACKAGE_ROOT / "cn_dicts", dirs_exist_ok=True)
    shutil.copytree(WINDOWS_SOURCE_ROOT / "lua", PACKAGE_ROOT / "lua", dirs_exist_ok=True)

    # Reuse the Windows runtime dictionary builder so both packages expose the
    # exact same active Chinese-to-English table rather than the old full dump.
    import importlib.util
    import sys

    sys.path.insert(0, str(WINDOWS_SCRIPT_ROOT))
    spec = importlib.util.spec_from_file_location(
        "inputeng_windows_package", WINDOWS_SCRIPT_ROOT / "package.py"
    )
    if spec is None or spec.loader is None:
        raise SystemExit("Could not load the shared Windows dictionary builder.")
    windows_package = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(windows_package)
    windows_package.build_common_base()
    windows_package.write_runtime_dictionary(PACKAGE_ROOT / "bilingual_english.tsv")

    shutil.copy2(GLOSS_OVERRIDES, PACKAGE_ROOT / "common_gloss_overrides.tsv")
    shutil.copy2(ENGLISH_CHINESE, PACKAGE_ROOT / "english_chinese.tsv")
    shutil.copy2(PROJECT_ROOT / "VERSION", PACKAGE_ROOT / "VERSION")
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
            executable = source.suffix in {".sh", ".command"}
            add_file(archive, source, target, executable)

    digest = hashlib.sha256(ARCHIVE_PATH.read_bytes()).hexdigest()
    checksum_path = ARCHIVE_PATH.with_suffix(".zip.sha256")
    checksum_path.write_text(f"{digest}  {ARCHIVE_PATH.name}\n", encoding="ascii")
    print(f"Created {ARCHIVE_PATH}")
    print(f"SHA-256 {digest}")


if __name__ == "__main__":
    main()
