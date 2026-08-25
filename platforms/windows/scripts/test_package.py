#!/usr/bin/env python3
"""Static and isolated install/uninstall tests for the Windows package."""

from __future__ import annotations

import hashlib
import http.server
import json
import os
import shutil
import subprocess
import tempfile
import threading
import time
import zipfile
from pathlib import Path

try:
    import yaml
except ImportError as exc:  # pragma: no cover - explicit environment failure
    raise SystemExit("PyYAML is required for package validation") from exc


PLATFORM_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = PLATFORM_ROOT.parents[1]
PACKAGE_ROOT = PLATFORM_ROOT / "package"
DIST_ROOT = PROJECT_ROOT / "dist" / "windows"
VERSION = (PACKAGE_ROOT / "VERSION").read_text(encoding="utf-8").strip()
ARCHIVE = DIST_ROOT / f"inputeng-windows-v{VERSION}.zip"
EXPECTED_DICTIONARY_ENTRIES = 59_872
EXPECTED_CHINESE_TABLES = {
    "cn_dicts/8105.dict.yaml": (8_757, "1f9a42b91dea6982baee2551981780271aeffd78876662b9c9f324e56b37b120"),
    "cn_dicts/base.dict.yaml": (164_199, "f7099c46c1567f2c330865bbe49976a1cfbbfdc10f9c4516d5d54dc0e2d0f235"),
    "cn_dicts/modern.dict.yaml": (79, "30e38a6a374bb5ef1390ca09e9757c282b1e30e5e80f8091d4eaa538f13e0f72"),
}


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_powershell(script: Path, *args: str) -> subprocess.CompletedProcess[str]:
    executable = shutil.which("powershell.exe") or shutil.which("powershell")
    if not executable:
        raise AssertionError("Windows PowerShell was not found")
    command = [
        executable,
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(script),
        *args,
    ]
    result = subprocess.run(command, text=True, encoding="utf-8", errors="replace", capture_output=True)
    if result.returncode:
        raise AssertionError(
            f"PowerShell failed ({result.returncode}): {' '.join(command)}\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
    return result


def validate_dictionary() -> None:
    path = PACKAGE_ROOT / "bilingual_english.tsv"
    lines = path.read_text(encoding="utf-8").splitlines()
    entries = [line for line in lines if line and not line.startswith("#")]
    assert len(entries) == EXPECTED_DICTIONARY_ENTRIES, len(entries)
    mapping = dict(line.split("\t", 1) for line in entries)
    assert mapping.get("翻译")
    assert mapping.get("输入法")
    assert mapping.get("输入") == "input"
    assert mapping.get("翻译") == "translate"
    assert mapping.get("东西") == "thing, stuff"
    assert mapping.get("臀推") == "hip thrust"
    assert mapping.get("麻薯") == "mochi"
    assert mapping.get("臀桥") == "glute bridge"
    assert mapping.get("芋泥") == "taro paste"
    assert "翻譯" not in mapping
    assert "輸入法" not in mapping
    assert max(len(value.encode("utf-8")) for value in mapping.values()) <= 24
    assert all(";" not in value and "(" not in value and ")" not in value for value in mapping.values())
    assert path.stat().st_size < 2_100_000

    overrides = dict(
        line.split("\t", 1)
        for line in (PACKAGE_ROOT / "common_gloss_overrides.tsv").read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#")
    )
    assert overrides == {
        "东西": "thing, stuff",
        "输入": "input",
        "翻译": "translate",
        "臀推": "hip thrust",
        "麻薯": "mochi",
        "臀桥": "glute bridge",
        "芋泥": "taro paste",
    }

    english_entries = [
        line
        for line in (PACKAGE_ROOT / "english_chinese.tsv").read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#")
    ]
    assert len(english_entries) == 58_129
    english_mapping = dict(line.split("\t", 1) for line in english_entries)
    assert english_mapping["translate"] == "翻译"
    assert english_mapping["school"] == "学校"
    assert english_mapping["input"] == "输入"


def rime_dictionary_rows(path: Path) -> list[list[str]]:
    rows: list[list[str]] = []
    body = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip() == "...":
            body = True
            continue
        if body and line and not line.startswith("#"):
            rows.append(line.split("\t"))
    return rows


def validate_chinese_dictionary() -> None:
    upstream = PLATFORM_ROOT / "upstream" / "rime-ice-base.full.dict.yaml"
    assert upstream.exists()
    assert len(rime_dictionary_rows(upstream)) == 543_012
    assert file_hash(upstream) == "4131c5ebd3744e1662231b375636a0d310b51c35f16d2534f7e268c13c72a2c3"

    meta_text = (PACKAGE_ROOT / "input_translate_core.dict.yaml").read_text(encoding="utf-8")
    header = meta_text.split("---", 1)[1].split("...", 1)[0]
    meta = yaml.safe_load(header)
    assert meta["name"] == "input_translate_core"
    assert meta["import_tables"] == ["cn_dicts/8105", "cn_dicts/base", "cn_dicts/modern"]
    assert not (PACKAGE_ROOT / "cn_dicts" / "ext.dict.yaml").exists()
    assert not (PACKAGE_ROOT / "cn_dicts" / "tencent.dict.yaml").exists()
    assert not (PACKAGE_ROOT / "cn_dicts" / "others.dict.yaml").exists()

    all_rows: list[list[str]] = []
    for relative, (expected_rows, expected_hash) in EXPECTED_CHINESE_TABLES.items():
        path = PACKAGE_ROOT / relative
        rows = rime_dictionary_rows(path)
        assert len(rows) == expected_rows, (relative, len(rows))
        assert file_hash(path) == expected_hash, relative
        all_rows.extend(rows)

    words = {row[0] for row in all_rows}
    assert {"输入", "输入法", "翻译", "金枪鱼", "玫粉色", "松弛感", "显眼包", "臀推", "麻薯", "臀桥", "芋泥"}.issubset(words)
    assert {"澍濡", "菽乳", "竖儒", "诱励", "雪鸮", "穴鸮", "雪下", "削下"}.isdisjoint(words)
    base_text = (PACKAGE_ROOT / "cn_dicts" / "base.dict.yaml").read_text(encoding="utf-8")
    assert "inputeng generated common subset" in base_text
    assert "published weight is at least 3000" in base_text
    shuru = [row[0] for row in all_rows if len(row) >= 2 and row[1] == "shu ru"]
    assert shuru == ["输入"], shuru


def validate_yaml_and_lua() -> None:
    schema = yaml.safe_load((PACKAGE_ROOT / "bilingual_pinyin.schema.yaml").read_text(encoding="utf-8"))
    assert schema["schema"]["schema_id"] == "bilingual_pinyin"
    assert schema["engine"]["filters"] == [
        "simplifier",
        "lua_filter@*english_mode_filter",
        "lua_filter@*bilingual_comment",
        "uniquifier",
    ]
    assert schema["engine"]["processors"] == [
        "lua_processor@*schema_toggle_processor",
        "ascii_composer",
        "recognizer",
        "key_binder",
        "speller",
        "punctuator",
        "selector",
        "navigator",
        "lua_processor@*personal_phrase_processor",
        "express_editor",
    ]
    assert schema["engine"]["translators"] == [
        "punct_translator",
        "reverse_lookup_translator",
        "lua_translator@*english_comment_translator",
        "lua_translator@*personal_phrase_translator",
        "script_translator",
    ]
    assert schema["translator"]["dictionary"] == "input_translate_core"
    assert schema["translator"]["user_dict"] == "input_translate_core"
    assert schema["translator"]["enable_sentence"] is True
    assert schema["menu"]["page_size"] == 5
    assert schema["style"]["color_scheme"] == "input_translate_light"
    assert schema["style"]["color_scheme_dark"] == "input_translate_dark"
    assert schema["style"]["font_point"] == 12
    assert schema["style"]["comment_font_point"] == 9
    assert schema["style"]["inline_preedit"] is True
    assert schema["speller"]["delimiter"] == "'"
    assert "xform/ /'/" in schema["translator"]["preedit_format"]
    assert schema["style"]["layout"]["align_type"] == "bottom"
    assert schema["style"]["layout"]["min_width"] == 120
    assert schema["style"]["layout"]["max_width"] == 220
    assert schema["style"]["layout"]["min_height"] == 152
    assert schema["style"]["layout"]["margin_x"] == 8
    assert schema["style"]["layout"]["hilite_spacing"] == 3

    sogou = yaml.safe_load((PACKAGE_ROOT / "bilingual_sogou.schema.yaml").read_text(encoding="utf-8"))
    assert sogou["schema"]["schema_id"] == "bilingual_sogou"
    assert sogou["schema"]["name"] == "inputeng 搜狗双拼"
    assert sogou["translator"]["dictionary"] == "input_translate_core"
    assert sogou["translator"]["prism"] == "bilingual_sogou"
    assert sogou["translator"]["user_dict"] == "input_translate_core_sogou"
    assert sogou["speller"]["delimiter"] == "'"
    assert "xform/ing$/;/" in sogou["speller"]["algebra"]
    assert "lua_translator@*english_comment_translator" not in sogou["engine"]["translators"]
    assert "lua_filter@*bilingual_comment" in sogou["engine"]["filters"]
    assert sogou["engine"]["processors"][0] == "lua_processor@*schema_toggle_processor"
    assert sogou["style"]["inline_preedit"] is True

    windows_lua = PACKAGE_ROOT / "lua" / "bilingual_comment.lua"
    mac_package_builder = (
        PROJECT_ROOT / "platforms" / "macos-rime" / "scripts" / "package.py"
    ).read_text(encoding="utf-8")
    assert 'shutil.copytree(WINDOWS_SOURCE_ROOT / "lua"' in mac_package_builder
    assert 'shutil.copytree(WINDOWS_SOURCE_ROOT / "cn_dicts"' in mac_package_builder
    bilingual_lua = windows_lua.read_text(encoding="utf-8")
    assert "RUNTIME_REFRESH_SECONDS = 1" in bilingual_lua
    assert "MISSING_BATCH_SIZE = 5" in bilingual_lua
    assert "flush_pending_missing(env)" in bilingual_lua
    assert "not file_exists(env.ai_enabled_path)" not in bilingual_lua
    assert "common_gloss_overrides.tsv" in bilingual_lua
    english_lua = (PACKAGE_ROOT / "lua" / "english_comment_translator.lua").read_text(encoding="utf-8")
    assert "english_chinese.tsv" in english_lua
    assert "is_full_pinyin" in english_lua
    assert "has_incomplete_pinyin_tail" in english_lua
    assert "PINYIN_PREFIXES" in english_lua
    assert 'Candidate("english"' in english_lua
    assert 'if not chinese or chinese == "" then\n    return\n  end' in english_lua
    english_filter = (PACKAGE_ROOT / "lua" / "english_mode_filter.lua").read_text(encoding="utf-8")
    assert 'candidate.type == "english"' in english_filter
    processor = (PACKAGE_ROOT / "lua" / "personal_phrase_processor.lua").read_text(encoding="utf-8")
    translator = (PACKAGE_ROOT / "lua" / "personal_phrase_translator.lua").read_text(encoding="utf-8")
    assert "prior_selection_count >= 1" in processor
    assert "append_phrase(env, code, text)" in processor
    assert "input_translate_phrase_pending.tsv" in processor
    assert "input_translate_frequency_events.tsv" not in processor
    assert "input_translate_missing.txt" in processor
    assert "record_commit(env, text)" in processor
    assert "pending_code == code and pending_text == text" not in processor
    assert "input_translate_personal_phrases.tsv" in processor
    assert "candidate.quality = 1000 + index" in translator
    assert "REFRESH_INTERVAL_SECONDS = 1" in translator

    settings = (PACKAGE_ROOT / "helper" / "settings.ps1").read_text(encoding="utf-8")
    assert "input_translate_frequency" not in settings
    assert "hilited_candidate_back_color" in settings
    assert "Apply-FontPoints" in settings
    assert "bilingual_pinyin.custom.yaml" in settings
    assert "bilingual_sogou.custom.yaml" in settings
    assert "deploy-rime.ps1" in settings
    assert "settings-ui.ps1" in settings
    settings_ui = (PACKAGE_ROOT / "helper" / "settings-ui.ps1").read_text(encoding="utf-8")
    assert "PresentationFramework" in settings_ui
    assert "Window.Resources" in settings_ui
    assert "CandidateSlider" not in settings_ui
    assert 'Header="词频"' not in settings_ui
    assert 'Header="词库"' in settings_ui
    assert 'Header="词库与缓存"' not in settings_ui
    assert "中文核心词库" in settings_ui
    assert "离线双语释义" in settings_ui
    assert "筛选依据" in settings_ui
    assert "自学习短语" not in settings_ui
    assert "人工修正" not in settings_ui
    assert "DeepSeek 缓存" not in settings_ui
    assert "待处理：" not in settings_ui
    assert "当前资源状态" not in settings_ui
    assert 'Text="输入方案"' not in settings_ui
    assert "RefreshResourcesButton" not in settings_ui
    assert 'Content="恢复默认"' in settings_ui
    assert "InlineRadio" not in settings_ui
    assert "状态：已启用" in settings_ui
    toggle = (PACKAGE_ROOT / "lua" / "schema_toggle_processor.lua").read_text(encoding="utf-8")
    assert 'key:repr() ~= "F4"' in toggle
    assert 'env.engine:apply_schema(Schema(target))' in toggle
    deploy = (PACKAGE_ROOT / "helper" / "deploy-rime.ps1").read_text(encoding="utf-8")
    assert "RimeDeployWorkspace" in deploy
    assert "RimeDeployConfigFile" in deploy
    brand = (PACKAGE_ROOT / "helper" / "brand-weasel.ps1").read_text(encoding="utf-8")
    assert "{A3F4CDED-B1E9-41EE-9CA6-7B4D0DE6CB0A}" in brand
    assert "0x00000804" in brand
    assert "weasel-profile-backup.json" in brand
    assert "inputeng" in brand
    assert "SendMessageTimeout" in brand
    installer = (PACKAGE_ROOT / "install.ps1").read_text(encoding="utf-8")
    assert "[switch]$InstallWeasel" in installer
    assert "[switch]$AcceptWeaselDownload" in installer
    assert "[switch]$SilentWeaselInstall" in installer
    assert "-NonInteractive -InstallWeasel -AcceptWeaselDownload -SilentWeaselInstall" not in installer
    assert "Windows 输入法列表名称：inputeng；图标：E。" not in installer
    assert "注销当前 Windows 账户并重新登录" in installer
    icon = (PACKAGE_ROOT / "branding" / "inputeng.ico").read_bytes()
    assert icon[:6] == b"\x00\x00\x01\x00\x08\x00", icon[:6]


def validate_archive() -> None:
    assert ARCHIVE.exists()
    with zipfile.ZipFile(ARCHIVE) as archive:
        names = archive.namelist()
        prefix = f"inputeng-windows-v{VERSION}/"
        assert all(name.startswith(prefix) for name in names)
        required = {
            prefix + "install.cmd",
            prefix + "install.ps1",
            prefix + "uninstall.cmd",
            prefix + "uninstall.ps1",
            prefix + "configure-deepseek.cmd",
            prefix + "settings.cmd",
            prefix + "bilingual_pinyin.schema.yaml",
            prefix + "bilingual_sogou.schema.yaml",
            prefix + "input_translate_core.dict.yaml",
            prefix + "cn_dicts/8105.dict.yaml",
            prefix + "cn_dicts/base.dict.yaml",
            prefix + "cn_dicts/modern.dict.yaml",
            prefix + "bilingual_english.tsv",
            prefix + "common_gloss_overrides.tsv",
            prefix + "english_chinese.tsv",
            prefix + "lua/bilingual_comment.lua",
            prefix + "lua/english_comment_translator.lua",
            prefix + "lua/english_mode_filter.lua",
            prefix + "lua/personal_phrase_processor.lua",
            prefix + "lua/personal_phrase_translator.lua",
            prefix + "lua/schema_toggle_processor.lua",
            prefix + "helper/worker.ps1",
            prefix + "helper/start-worker.ps1",
            prefix + "helper/configure-deepseek.ps1",
            prefix + "helper/settings.ps1",
            prefix + "helper/settings-ui.ps1",
            prefix + "helper/deploy-rime.ps1",
            prefix + "helper/brand-weasel.ps1",
            prefix + "branding/inputeng.ico",
            prefix + "README.md",
            prefix + "LICENSE",
            prefix + "THIRD_PARTY_NOTICES.md",
            prefix + "licenses/CC-BY-SA-4.0.txt",
            prefix + "licenses/RIME_ICE_GPL-3.0.txt",
            prefix + "licenses/WANXIANG_CC-BY-4.0.txt",
            prefix + "licenses/ECDICT_MIT.txt",
        }
        assert required.issubset(set(names)), required.difference(names)
        assert not any("upstream/" in name or "base.full" in name for name in names)
        bad = archive.testzip()
        assert bad is None, bad


def test_empty_install_cycle(temp_root: Path) -> None:
    rime = temp_root / "empty" / "Rime"
    state = temp_root / "empty" / "State"
    install = PACKAGE_ROOT / "install.ps1"
    uninstall = PACKAGE_ROOT / "uninstall.ps1"
    args = (
        "-RimeUserDir", str(rime), "-StateRoot", str(state),
        "-SkipWeaselCheck", "-SkipDeploy", "-SkipBackgroundWorker", "-NonInteractive",
    )
    run_powershell(install, *args)
    run_powershell(install, *args)

    assert (rime / "bilingual_pinyin.schema.yaml").exists()
    assert (rime / "bilingual_sogou.schema.yaml").exists()
    assert (rime / "input_translate_core.dict.yaml").exists()
    assert (rime / "cn_dicts" / "8105.dict.yaml").exists()
    assert (rime / "cn_dicts" / "base.dict.yaml").exists()
    assert (rime / "cn_dicts" / "modern.dict.yaml").exists()
    assert (rime / "bilingual_english.tsv").exists()
    assert (rime / "common_gloss_overrides.tsv").exists()
    assert (rime / "english_chinese.tsv").exists()
    assert (rime / "lua" / "bilingual_comment.lua").exists()
    assert (rime / "lua" / "english_comment_translator.lua").exists()
    assert (rime / "lua" / "english_mode_filter.lua").exists()
    assert (rime / "lua" / "personal_phrase_processor.lua").exists()
    assert (rime / "lua" / "personal_phrase_translator.lua").exists()
    assert (rime / "lua" / "schema_toggle_processor.lua").exists()
    default_text = (rime / "default.custom.yaml").read_text(encoding="utf-8")
    weasel_text = (rime / "weasel.custom.yaml").read_text(encoding="utf-8")
    assert default_text.count("# >>> input-translate:schema") == 1
    assert default_text.count("# >>> input-translate:hotkeys") == 1
    assert '"switcher/hotkeys": [Control+grave]' in default_text
    assert weasel_text.count("# >>> input-translate:theme") == 1
    yaml.safe_load(default_text)
    yaml.safe_load(weasel_text)
    manifest = json.loads((state / "install-manifest.json").read_text(encoding="utf-8"))
    assert manifest["version"] == VERSION
    assert manifest["branding"] is None

    run_powershell(uninstall, "-RimeUserDir", str(rime), "-StateRoot", str(state), "-SkipDeploy")
    assert not (rime / "bilingual_pinyin.schema.yaml").exists()
    assert not (rime / "bilingual_sogou.schema.yaml").exists()
    assert not (rime / "input_translate_core.dict.yaml").exists()
    assert not (rime / "cn_dicts" / "8105.dict.yaml").exists()
    assert not (rime / "cn_dicts" / "base.dict.yaml").exists()
    assert not (rime / "cn_dicts" / "modern.dict.yaml").exists()
    assert not (rime / "bilingual_english.tsv").exists()
    assert not (rime / "common_gloss_overrides.tsv").exists()
    assert not (rime / "english_chinese.tsv").exists()
    assert not (rime / "lua" / "bilingual_comment.lua").exists()
    assert not (rime / "lua" / "english_comment_translator.lua").exists()
    assert not (rime / "lua" / "english_mode_filter.lua").exists()
    assert not (rime / "lua" / "personal_phrase_processor.lua").exists()
    assert not (rime / "lua" / "personal_phrase_translator.lua").exists()
    assert not (rime / "lua" / "schema_toggle_processor.lua").exists()
    assert not (rime / "default.custom.yaml").exists()
    assert not (rime / "weasel.custom.yaml").exists()


def test_existing_config_cycle(temp_root: Path) -> None:
    rime = temp_root / "existing" / "Rime"
    state = temp_root / "existing" / "State"
    rime.mkdir(parents=True)
    default_original = 'customization:\n  generator: test\npatch:\n  "menu/page_size": 7\n'
    weasel_original = 'patch:\n  "style/horizontal": true\n'
    (rime / "default.custom.yaml").write_text(default_original, encoding="utf-8", newline="\n")
    (rime / "weasel.custom.yaml").write_text(weasel_original, encoding="utf-8", newline="\n")

    run_powershell(
        PACKAGE_ROOT / "install.ps1",
        "-RimeUserDir", str(rime),
        "-StateRoot", str(state),
        "-SkipWeaselCheck", "-SkipDeploy", "-SkipBackgroundWorker", "-NonInteractive",
    )
    default_installed = (rime / "default.custom.yaml").read_text(encoding="utf-8")
    weasel_installed = (rime / "weasel.custom.yaml").read_text(encoding="utf-8")
    assert '"menu/page_size": 7' in default_installed
    assert '"style/horizontal": true' in weasel_installed
    yaml.safe_load(default_installed)
    yaml.safe_load(weasel_installed)

    run_powershell(
        PACKAGE_ROOT / "uninstall.ps1",
        "-RimeUserDir", str(rime),
        "-StateRoot", str(state),
        "-SkipDeploy",
    )
    assert (rime / "default.custom.yaml").read_text(encoding="utf-8") == default_original
    assert (rime / "weasel.custom.yaml").read_text(encoding="utf-8") == weasel_original


def test_existing_managed_file_backup(temp_root: Path) -> None:
    rime = temp_root / "backup" / "Rime"
    state = temp_root / "backup" / "State"
    rime.mkdir(parents=True)
    original = "# pre-existing user schema\n"
    managed_path = rime / "bilingual_pinyin.schema.yaml"
    managed_path.write_text(original, encoding="utf-8", newline="\n")

    run_powershell(
        PACKAGE_ROOT / "install.ps1",
        "-RimeUserDir", str(rime),
        "-StateRoot", str(state),
        "-SkipWeaselCheck", "-SkipDeploy", "-SkipBackgroundWorker", "-NonInteractive",
    )
    assert managed_path.read_text(encoding="utf-8") != original
    manifest = json.loads((state / "install-manifest.json").read_text(encoding="utf-8"))
    schema_entry = next(item for item in manifest["managedFiles"] if item["relativePath"] == "bilingual_pinyin.schema.yaml")
    assert schema_entry["backupPath"]
    assert Path(schema_entry["backupPath"]).exists()

    run_powershell(
        PACKAGE_ROOT / "uninstall.ps1",
        "-RimeUserDir", str(rime),
        "-StateRoot", str(state),
        "-SkipDeploy",
    )
    assert managed_path.read_text(encoding="utf-8") == original


def test_weasel_settings_rewrite_cycle(temp_root: Path) -> None:
    """Weasel settings rewrites YAML and strips comments; reinstall/uninstall must stay safe."""
    rime = temp_root / "settings-rewrite" / "Rime"
    state = temp_root / "settings-rewrite" / "State"
    rime.mkdir(parents=True)
    (rime / "default.custom.yaml").write_text('patch:\n  "menu/page_size": 7\n', encoding="utf-8", newline="\n")
    (rime / "weasel.custom.yaml").write_text('patch:\n  "style/horizontal": true\n', encoding="utf-8", newline="\n")
    common_args = (
        "-RimeUserDir", str(rime),
        "-StateRoot", str(state),
        "-SkipWeaselCheck", "-SkipDeploy", "-SkipBackgroundWorker", "-NonInteractive",
    )
    run_powershell(PACKAGE_ROOT / "install.ps1", *common_args)

    # Simulate Weasel::SwitcherSettings output after the first deployment UI.
    generated_default = (
        'customization:\n'
        '  generator: "Rime::SwitcherSettings"\n'
        'patch:\n'
        '  schema_list:\n'
        '    - {schema: luna_pinyin}\n'
        '    - {schema: bilingual_pinyin}\n'
        '  "schema_list/@next/schema": bilingual_pinyin\n'
        '  "menu/page_size": 7\n'
    )
    (rime / "default.custom.yaml").write_bytes(generated_default.replace("\n", "\r\n").encode("utf-8"))
    weasel_path = rime / "weasel.custom.yaml"
    generated_weasel = "\n".join(
        line for line in weasel_path.read_text(encoding="utf-8").splitlines()
        if "# >>> input-translate:theme" not in line and "# <<< input-translate:theme" not in line
    ) + "\n"
    weasel_path.write_text(generated_weasel, encoding="utf-8", newline="\n")

    run_powershell(PACKAGE_ROOT / "install.ps1", *common_args)
    default_after_reinstall = (rime / "default.custom.yaml").read_text(encoding="utf-8")
    weasel_after_reinstall = weasel_path.read_text(encoding="utf-8")
    assert default_after_reinstall.count("bilingual_pinyin") == 1
    assert default_after_reinstall.count("bilingual_sogou") == 1
    assert "schema_list/@next/schema" not in default_after_reinstall
    assert weasel_after_reinstall.count('"preset_color_schemes/input_translate_light"') == 1
    assert weasel_after_reinstall.count('"preset_color_schemes/input_translate_dark"') == 1
    assert "hilited_candidate_back_color: 0xec4899ff" in weasel_after_reinstall
    assert "hilited_candidate_back_color: 0xdb2777ff" in weasel_after_reinstall
    assert weasel_after_reinstall.count("hilited_label_color: 0xffffffff") == 2
    yaml.safe_load(default_after_reinstall)
    yaml.safe_load(weasel_after_reinstall)

    # A saved user accent survives reinstall and applies to light and dark themes.
    (state / "settings.json").write_text(
        json.dumps({
            "accentColor": "#2563EB",
            "candidateFontPoint": 13,
            "commentFontPoint": 9,
            "preeditPlacement": "inline",
        }),
        encoding="utf-8",
    )
    run_powershell(PACKAGE_ROOT / "install.ps1", *common_args)
    weasel_after_reinstall = weasel_path.read_text(encoding="utf-8")
    assert weasel_after_reinstall.count("hilited_candidate_back_color: 0x2563ebff") == 2
    assert "hilited_candidate_back_color: 0xec4899ff" not in weasel_after_reinstall
    assert "hilited_candidate_back_color: 0xdb2777ff" not in weasel_after_reinstall
    yaml.safe_load(weasel_after_reinstall)
    schema_style = (rime / "bilingual_pinyin.custom.yaml").read_text(encoding="utf-8")
    assert '"style/font_point": 13' in schema_style
    assert '"style/comment_font_point": 9' in schema_style
    assert '"style/inline_preedit": true' in schema_style
    yaml.safe_load(schema_style)
    double_style = (rime / "bilingual_sogou.custom.yaml").read_text(encoding="utf-8")
    assert '"style/font_point": 13' in double_style
    assert '"style/comment_font_point": 9' in double_style
    assert '"style/inline_preedit": true' in double_style
    yaml.safe_load(double_style)

    # Strip markers again before uninstall to exercise generated-YAML cleanup.
    markerless = "\n".join(
        line for line in weasel_after_reinstall.splitlines()
        if "# >>> input-translate:theme" not in line and "# <<< input-translate:theme" not in line
    ) + "\n"
    weasel_path.write_text(markerless, encoding="utf-8", newline="\n")
    run_powershell(
        PACKAGE_ROOT / "uninstall.ps1",
        "-RimeUserDir", str(rime),
        "-StateRoot", str(state),
        "-SkipDeploy",
    )
    default_after_uninstall = (rime / "default.custom.yaml").read_text(encoding="utf-8")
    weasel_after_uninstall = weasel_path.read_text(encoding="utf-8")
    assert "bilingual_pinyin" not in default_after_uninstall
    assert "bilingual_sogou" not in default_after_uninstall
    assert '"menu/page_size": 7' in default_after_uninstall
    assert "input_translate_" not in weasel_after_uninstall
    assert not (rime / "bilingual_pinyin.custom.yaml").exists()
    assert not (rime / "bilingual_sogou.custom.yaml").exists()
    assert '"style/horizontal": true' in weasel_after_uninstall
    yaml.safe_load(default_after_uninstall)
    yaml.safe_load(weasel_after_uninstall)


def test_settings_appearance(temp_root: Path) -> None:
    root = temp_root / "settings"
    state = root / "State"
    rime = root / "Rime"
    state.mkdir(parents=True)
    rime.mkdir(parents=True)
    (rime / "weasel.custom.yaml").write_text(
        "customization:\n"
        "  modified_time: \"Mon Aug 24 00:00:00 2026\"\n"
        "patch:\n"
        "  # >>> input-translate:theme\n"
        "  \"preset_color_schemes/input_translate_light\":\n"
        "    hilited_candidate_back_color: 0xec4899ff\n"
        "  \"preset_color_schemes/input_translate_dark\":\n"
        "    hilited_candidate_back_color: 0xdb2777ff\n"
        "  # <<< input-translate:theme\n",
        encoding="utf-8",
        newline="\n",
    )

    run_powershell(
        PACKAGE_ROOT / "helper" / "settings.ps1",
        "-StateRoot", str(state),
        "-RimeUserDir", str(rime),
        "-ApplyAccent", "#2563EB", "-SkipDeploy",
    )
    settings = json.loads((state / "settings.json").read_text(encoding="utf-8-sig"))
    assert settings["accentColor"] == "#2563EB"
    weasel = (rime / "weasel.custom.yaml").read_text(encoding="utf-8")
    assert weasel.count("hilited_candidate_back_color: 0x2563ebff") == 2
    yaml.safe_load(weasel)

    run_powershell(
        PACKAGE_ROOT / "helper" / "settings.ps1",
        "-StateRoot", str(state),
        "-RimeUserDir", str(rime),
        "-ApplyCandidateFontPoint", "13",
        "-ApplyCommentFontPoint", "9",
        "-SkipDeploy",
    )
    settings = json.loads((state / "settings.json").read_text(encoding="utf-8-sig"))
    assert settings["accentColor"] == "#2563EB"
    assert settings["candidateFontPoint"] == 13
    assert settings["commentFontPoint"] == 9
    assert settings["preeditPlacement"] == "inline"
    schema_custom = (rime / "bilingual_pinyin.custom.yaml").read_text(encoding="utf-8")
    assert '"style/font_point": 13' in schema_custom
    assert '"style/comment_font_point": 9' in schema_custom
    assert '"style/inline_preedit": true' in schema_custom
    yaml.safe_load(schema_custom)
    double_custom = (rime / "bilingual_sogou.custom.yaml").read_text(encoding="utf-8")
    assert '"style/font_point": 13' in double_custom
    assert '"style/comment_font_point": 9' in double_custom
    assert '"style/inline_preedit": true' in double_custom
    yaml.safe_load(double_custom)

def test_deepseek_worker_with_mock_api(temp_root: Path) -> None:
    state = temp_root / "worker" / "State"
    rime = temp_root / "worker" / "Rime"
    state.mkdir(parents=True)
    rime.mkdir(parents=True)

    received: dict[str, object] = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self) -> None:  # noqa: N802 - stdlib callback name
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length).decode("utf-8"))
            received.update(body)
            translated = {
                "translations": [
                    {"source": "金枪", "english": "golden spear"},
                    {"source": "禁枪", "english": "gun ban"},
                ]
            }
            response = {
                "choices": [
                    {"message": {"content": json.dumps(translated, ensure_ascii=False)}}
                ]
            }
            payload = json.dumps(response, ensure_ascii=False).encode("utf-8")
            self.send_response(200)
            # DeepSeek may omit charset. Windows PowerShell 5.1 must still
            # decode Chinese source strings as UTF-8 rather than Latin-1.
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, _format: str, *_args: object) -> None:
            return

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.handle_request, daemon=True)
    thread.start()

    config = {
        "enabled": True,
        "endpoint": f"http://127.0.0.1:{server.server_port}/chat/completions",
        "model": "deepseek-v4-flash",
    }
    (state / "deepseek-config.json").write_text(json.dumps(config), encoding="utf-8")
    (rime / "input_translate_ai_enabled").write_text("enabled", encoding="utf-8")
    (rime / "input_translate_missing.txt").write_text("金枪\n禁枪\n", encoding="utf-8")

    executable = shutil.which("powershell.exe") or shutil.which("powershell")
    assert executable
    protected = subprocess.run(
        [
            executable,
            "-NoLogo",
            "-NoProfile",
            "-Command",
            "$s=ConvertTo-SecureString 'sk-test-only' -AsPlainText -Force; ConvertFrom-SecureString $s",
        ],
        text=True,
        encoding="ascii",
        capture_output=True,
        check=True,
    ).stdout.strip()
    (state / "deepseek.key.dpapi").write_text(protected, encoding="ascii")
    time.sleep(0.6)

    run_powershell(
        PACKAGE_ROOT / "helper" / "worker.ps1",
        "-StateRoot", str(state),
        "-RimeUserDir", str(rime),
        "-Once",
    )
    thread.join(timeout=3)
    server.server_close()

    worker_log = (state / "worker.log").read_text(encoding="utf-8-sig") if (state / "worker.log").exists() else ""
    assert received, worker_log
    assert received["model"] == "deepseek-v4-flash"
    assert received["thinking"] == {"type": "disabled"}
    user_payload = json.loads(received["messages"][1]["content"])
    assert user_payload["terms"] == ["金枪", "禁枪"]
    cache = (rime / "input_translate_ai_cache.tsv").read_text(encoding="utf-8")
    assert "金枪\tgolden spear" in cache
    assert "禁枪\tgun ban" in cache
    assert (rime / "input_translate_ai_cache.version").exists()


def main() -> None:
    required = [
        PACKAGE_ROOT / "install.ps1",
        PACKAGE_ROOT / "uninstall.ps1",
        PACKAGE_ROOT / "configure-deepseek.cmd",
        PACKAGE_ROOT / "settings.cmd",
        PACKAGE_ROOT / "bilingual_english.tsv",
        PACKAGE_ROOT / "common_gloss_overrides.tsv",
        PACKAGE_ROOT / "english_chinese.tsv",
        PACKAGE_ROOT / "bilingual_pinyin.schema.yaml",
        PACKAGE_ROOT / "bilingual_sogou.schema.yaml",
        PACKAGE_ROOT / "input_translate_core.dict.yaml",
        PACKAGE_ROOT / "cn_dicts" / "8105.dict.yaml",
        PACKAGE_ROOT / "cn_dicts" / "base.dict.yaml",
        PACKAGE_ROOT / "cn_dicts" / "modern.dict.yaml",
        PACKAGE_ROOT / "licenses" / "CC-BY-SA-4.0.txt",
        PACKAGE_ROOT / "licenses" / "RIME_ICE_GPL-3.0.txt",
        PACKAGE_ROOT / "licenses" / "WANXIANG_CC-BY-4.0.txt",
        PACKAGE_ROOT / "licenses" / "ECDICT_MIT.txt",
        PACKAGE_ROOT / "lua" / "bilingual_comment.lua",
        PACKAGE_ROOT / "lua" / "english_comment_translator.lua",
        PACKAGE_ROOT / "lua" / "english_mode_filter.lua",
        PACKAGE_ROOT / "lua" / "personal_phrase_processor.lua",
        PACKAGE_ROOT / "lua" / "personal_phrase_translator.lua",
        PACKAGE_ROOT / "lua" / "schema_toggle_processor.lua",
        PACKAGE_ROOT / "helper" / "worker.ps1",
        PACKAGE_ROOT / "helper" / "start-worker.ps1",
        PACKAGE_ROOT / "helper" / "configure-deepseek.ps1",
        PACKAGE_ROOT / "helper" / "settings.ps1",
        PACKAGE_ROOT / "helper" / "settings-ui.ps1",
        PACKAGE_ROOT / "helper" / "deploy-rime.ps1",
        PACKAGE_ROOT / "helper" / "brand-weasel.ps1",
        PACKAGE_ROOT / "branding" / "inputeng.ico",
    ]
    missing = [str(path) for path in required if not path.exists()]
    assert not missing, missing
    validate_dictionary()
    validate_chinese_dictionary()
    validate_yaml_and_lua()
    validate_archive()
    with tempfile.TemporaryDirectory(prefix="input-translate-test-") as directory:
        temp_root = Path(directory)
        test_empty_install_cycle(temp_root)
        test_existing_config_cycle(temp_root)
        test_existing_managed_file_backup(temp_root)
        test_weasel_settings_rewrite_cycle(temp_root)
        test_settings_appearance(temp_root)
        if os.environ.get("CI", "").casefold() != "true":
            test_deepseek_worker_with_mock_api(temp_root)
        else:
            print("Skipped DPAPI worker test on hosted CI")
    print("Windows package validation passed")


if __name__ == "__main__":
    main()
