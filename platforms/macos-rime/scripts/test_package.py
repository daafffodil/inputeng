#!/usr/bin/env python3
"""Static, archive and isolated installer tests for the macOS package."""

from __future__ import annotations

import os
import platform
import shutil
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path

import yaml


PLATFORM_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = PLATFORM_ROOT.parents[1]
PACKAGE_ROOT = PLATFORM_ROOT / "package"
WINDOWS_SOURCE = PROJECT_ROOT / "platforms" / "windows" / "src"
VERSION = (PLATFORM_ROOT / "VERSION").read_text(encoding="utf-8").strip()
ARCHIVE = PROJECT_ROOT / "dist" / "macos" / f"inputeng-macos-v{VERSION}.zip"
PREFIX = f"inputeng-macos-v{VERSION}/"


def count_tsv(path: Path) -> int:
    return sum(1 for line in path.read_text(encoding="utf-8").splitlines() if line and not line.startswith("#"))


def validate_core_parity() -> None:
    same_files = [
        "input_translate_core.dict.yaml",
        "inputeng_annotations.schema.yaml",
        "inputeng_english.schema.yaml",
        "cn_dicts/8105.dict.yaml",
        "cn_dicts/base.dict.yaml",
        "cn_dicts/modern.dict.yaml",
        "lua/bilingual_comment.lua",
        "lua/english_comment_translator.lua",
        "lua/english_mode_filter.lua",
        "lua/personal_phrase_processor.lua",
        "lua/personal_phrase_translator.lua",
        "lua/schema_toggle_processor.lua",
    ]
    for relative in same_files:
        assert (PACKAGE_ROOT / relative).read_bytes() == (WINDOWS_SOURCE / relative).read_bytes(), relative

    for schema_name in ("bilingual_pinyin.schema.yaml", "bilingual_sogou.schema.yaml"):
        schema = yaml.safe_load((PACKAGE_ROOT / schema_name).read_text(encoding="utf-8"))
        windows_schema = yaml.safe_load((WINDOWS_SOURCE / schema_name).read_text(encoding="utf-8"))
        windows_schema.pop("style", None)
        assert schema == windows_schema
        assert schema["schema"]["version"] == VERSION
        assert schema["schema"]["name"].startswith("inputeng")
        assert "style" not in schema

    assert count_tsv(PACKAGE_ROOT / "bilingual_english.tsv") == 59873
    assert count_tsv(PACKAGE_ROOT / "english_chinese.tsv") == 58129
    assert count_tsv(PACKAGE_ROOT / "inputeng_annotations.dict.yaml") > 110_000
    assert count_tsv(PACKAGE_ROOT / "inputeng_english.dict.yaml") > 50_000


def validate_scripts() -> None:
    scripts = list(PACKAGE_ROOT.rglob("*.sh")) + list(PACKAGE_ROOT.rglob("*.command"))
    assert scripts
    bash = shutil.which("bash")
    if bash and os.name != "nt":
        for script in scripts:
            subprocess.run([bash, "-n", str(script)], check=True)

    node = shutil.which("node")
    if node:
        subprocess.run([node, "--check", str(PACKAGE_ROOT / "helper" / "worker-json.js")], check=True)

    if platform.system() == "Darwin":
        subprocess.run(
            ["/usr/bin/osascript", "-l", "JavaScript", str(PACKAGE_ROOT / "helper" / "worker-json.js"), "--self-test"],
            check=True,
        )


def validate_archive() -> None:
    assert ARCHIVE.exists()
    required = {
        PREFIX + "install.sh",
        PREFIX + "uninstall.sh",
        PREFIX + "settings.command",
        PREFIX + "configure-deepseek.command",
        PREFIX + "bilingual_pinyin.schema.yaml",
        PREFIX + "bilingual_sogou.schema.yaml",
        PREFIX + "inputeng_annotations.schema.yaml",
        PREFIX + "inputeng_annotations.dict.yaml",
        PREFIX + "inputeng_english.schema.yaml",
        PREFIX + "inputeng_english.dict.yaml",
        PREFIX + "english_chinese.tsv",
        PREFIX + "helper/worker.sh",
        PREFIX + "helper/worker-json.js",
    }
    with zipfile.ZipFile(ARCHIVE) as archive:
        names = set(archive.namelist())
        assert required <= names, sorted(required - names)
        for name in names:
            if name.endswith((".sh", ".command")):
                mode = archive.getinfo(name).external_attr >> 16
                assert mode & stat.S_IXUSR, name


def validate_isolated_install() -> None:
    if platform.system() != "Darwin":
        return
    with tempfile.TemporaryDirectory(prefix="inputeng-macos-test-") as temporary:
        root = Path(temporary)
        rime = root / "Rime"
        state = root / "State"
        agents = root / "LaunchAgents"
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(root),
                "INPUTENG_RIME_DIR": str(rime),
                "INPUTENG_STATE_ROOT": str(state),
                "INPUTENG_LAUNCH_AGENTS_DIR": str(agents),
                "INPUTENG_ALLOW_MISSING_SQUIRREL": "1",
                "INPUTENG_NO_LAUNCH_AGENT": "1",
                "INPUTENG_SKIP_RELOAD": "1",
            }
        )
        subprocess.run(["/bin/bash", str(PACKAGE_ROOT / "install.sh")], env=env, check=True)
        subprocess.run(["/bin/bash", str(PACKAGE_ROOT / "install.sh")], env=env, check=True)
        assert (rime / "bilingual_pinyin.schema.yaml").exists()
        assert (rime / "bilingual_sogou.schema.yaml").exists()
        assert "inputeng:theme" in (rime / "squirrel.custom.yaml").read_text(encoding="utf-8")
        assert "bilingual_sogou" in (rime / "default.custom.yaml").read_text(encoding="utf-8")

        subprocess.run(["/bin/bash", str(PACKAGE_ROOT / "uninstall.sh")], env=env, check=True)
        assert not (rime / "bilingual_pinyin.schema.yaml").exists()
        assert not (rime / "bilingual_sogou.schema.yaml").exists()
        assert "inputeng:theme" not in (rime / "squirrel.custom.yaml").read_text(encoding="utf-8")


def main() -> None:
    validate_core_parity()
    validate_scripts()
    validate_archive()
    validate_isolated_install()
    print("macOS package validation passed.")


if __name__ == "__main__":
    main()
