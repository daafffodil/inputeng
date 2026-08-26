#!/usr/bin/env python3
"""Build the deterministic inputeng Windows extension package."""

from __future__ import annotations

import hashlib
import re
import shutil
import zipfile
from pathlib import Path

from build_common_base import build_common_base


PLATFORM_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = PLATFORM_ROOT.parents[1]
SOURCE_ROOT = PLATFORM_ROOT / "src"
PACKAGE_ROOT = PLATFORM_ROOT / "package"
SHARED_DICTIONARY = PROJECT_ROOT / "shared" / "dictionary" / "bilingual_english.tsv"
GLOSS_OVERRIDES = PROJECT_ROOT / "shared" / "dictionary" / "common_gloss_overrides.tsv"
ENGLISH_CHINESE_DICTIONARY = PROJECT_ROOT / "shared" / "dictionary" / "english_chinese.tsv"
PROJECT_LICENSE = PROJECT_ROOT / "LICENSE"
DIST_ROOT = PROJECT_ROOT / "dist" / "windows"
VERSION = (SOURCE_ROOT / "VERSION").read_text(encoding="utf-8").strip()
ARCHIVE_STEM = f"inputeng-windows-v{VERSION}"
MAX_GLOSS_BYTES = 24
ENGLISH_WORD_RE = re.compile(r"[a-z][a-z'-]{2,29}")
ENGLISH_DIRECT_RE = re.compile(r"[a-z]{3,30}")

PINYIN_SYLLABLES = set(
    """
a ai an ang ao e ei en eng er o ou
ba bai ban bang bao bei ben beng bi bian biao bie bin bing bo bu
ca cai can cang cao ce cen ceng cha chai chan chang chao che chen cheng chi chong chou chu chua chuai chuan chuang chui chun chuo ci cong cou cu cuan cui cun cuo
da dai dan dang dao de dei den deng di dia dian diao die ding diu dong dou du duan dui dun duo
fa fan fang fei fen feng fiao fo fou fu
ga gai gan gang gao ge gei gen geng gong gou gu gua guai guan guang gui gun guo
ha hai han hang hao he hei hen heng hm hng hong hou hu hua huai huan huang hui hun huo
ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun
ka kai kan kang kao ke kei ken keng kong kou ku kua kuai kuan kuang kui kun kuo
la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu lo long lou lu luan lun luo lv lve
ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou mu
na nai nan nang nao ne nei nen neng ng ni nian niang niao nie nin ning niu nong nou nu nuan nuo nv nve
pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu
qi qia qian qiang qiao qie qin qing qiong qiu qu quan que qun
ran rang rao re ren reng ri rong rou ru rua ruan rui run ruo
sa sai san sang sao se sen seng sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan shuang shui shun shuo si song sou su suan sui sun suo
ta tai tan tang tao te teng ti tian tiao tie ting tong tou tu tuan tui tun tuo
wa wai wan wang wei wen weng wo wu
xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun
ya yan yang yao ye yi yin ying yo yong you yu yuan yue yun
za zai zan zang zao ze zei zen zeng zha zhai zhan zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo zi zong zou zu zuan zui zun zuo
""".split()
)


def utf8_length(value: str) -> int:
    return len(value.encode("utf-8"))


def truncate_utf8(value: str, max_bytes: int) -> str:
    payload = value.encode("utf-8")[:max_bytes]
    while payload:
        try:
            return payload.decode("utf-8")
        except UnicodeDecodeError:
            payload = payload[:-1]
    return ""


def short_gloss(value: str) -> str:
    """Precompute the same short display value that Lua would normalize."""
    gloss = re.sub(r"\s+", " ", value).strip()
    lowered = gloss.casefold()
    if lowered.startswith("simplified form of chinese characters"):
        gloss = "simplified Chinese"
    elif lowered.startswith("traditional form of chinese characters"):
        gloss = "traditional Chinese"

    previous = None
    while previous != gloss:
        previous = gloss
        gloss = re.sub(r"\s*\([^()]*\)", "", gloss)
    # If the source was already shortened in the middle of a parenthetical,
    # discard that incomplete tail instead of displaying punctuation fragments.
    gloss = gloss.split("(", 1)[0].rstrip()
    gloss = gloss.split(")", 1)[0].rstrip()
    gloss = gloss.split(";", 1)[0]
    gloss = gloss.rstrip()

    if utf8_length(gloss) > MAX_GLOSS_BYTES:
        comma_prefix = gloss.split(",", 1)[0].rstrip()
        if utf8_length(comma_prefix) >= 4:
            gloss = comma_prefix

    if utf8_length(gloss) > MAX_GLOSS_BYTES:
        prefix = truncate_utf8(gloss, MAX_GLOSS_BYTES)
        whole_words = re.sub(r"\s+\S*$", "", prefix)
        gloss = whole_words if utf8_length(whole_words) >= 8 else prefix

    gloss = gloss.rstrip(" ,;:.-")
    # Reference-only CC-CEDICT definitions that still contain Chinese are not
    # useful as an English annotation. Let the optional AI cache fill them.
    if not re.search(r"[A-Za-z]", gloss) or re.search(r"[\u3400-\u9fff\uf900-\ufaff]", gloss):
        return ""
    return gloss


def active_core_words() -> set[str]:
    words: set[str] = set()
    for relative in ("cn_dicts/8105.dict.yaml", "cn_dicts/base.dict.yaml", "cn_dicts/modern.dict.yaml"):
        body = False
        for line in (SOURCE_ROOT / relative).read_text(encoding="utf-8").splitlines():
            if line.strip() == "...":
                body = True
                continue
            if body and line and not line.startswith("#"):
                words.add(line.split("\t", 1)[0])
    return words


def is_full_pinyin(value: str) -> bool:
    """Return True when the whole ASCII word can be segmented as Pinyin."""
    reachable = {0}
    for start in range(len(value)):
        if start not in reachable:
            continue
        for width in range(1, 7):
            finish = start + width
            if finish <= len(value) and value[start:finish] in PINYIN_SYLLABLES:
                reachable.add(finish)
    return len(value) in reachable


def read_tsv_mapping(path: Path) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#"):
            key, value = line.split("\t", 1)
            mapping.setdefault(key, value)
    return mapping


def annotation_code(value: str) -> str:
    # Rime dictionary codes cannot contain literal spaces. The schema's native
    # reverse-lookup formatter restores underscores only for display.
    return re.sub(r"\s+", "_", value.strip())


def write_native_rime_dictionaries(package_root: Path) -> tuple[int, int]:
    """Build exact native annotations and direct-English candidate tables."""
    chinese_to_english = read_tsv_mapping(package_root / "bilingual_english.tsv")
    english_to_chinese = read_tsv_mapping(package_root / "english_chinese.tsv")

    annotations: dict[str, str] = {
        text: annotation_code(gloss)
        for text, gloss in chinese_to_english.items()
        if annotation_code(gloss)
    }
    for word, gloss in english_to_chinese.items():
        if ENGLISH_WORD_RE.fullmatch(word):
            annotations.setdefault(word, annotation_code(gloss))

    annotation_path = package_root / "inputeng_annotations.dict.yaml"
    with annotation_path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(
            "# Rime dictionary\n# encoding: utf-8\n---\n"
            "name: inputeng_annotations\n"
            f'version: "{VERSION}"\n'
            "sort: original\nuse_preset_vocabulary: false\n"
            "columns:\n  - text\n  - code\n...\n"
        )
        for text in sorted(annotations):
            handle.write(f"{text}\t{annotations[text]}\n")

    english_rows = [
        (word, gloss)
        for word, gloss in english_to_chinese.items()
        if ENGLISH_DIRECT_RE.fullmatch(word) and not is_full_pinyin(word)
    ]
    english_path = package_root / "inputeng_english.dict.yaml"
    with english_path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(
            "# Rime dictionary\n# encoding: utf-8\n---\n"
            "name: inputeng_english\n"
            f'version: "{VERSION}"\n'
            "sort: original\nuse_preset_vocabulary: false\n"
            "columns:\n  - text\n  - code\n  - weight\n...\n"
        )
        for word, _ in sorted(english_rows):
            handle.write(f"{word}\t{word}\t100\n")

    return len(annotations), len(english_rows)


def write_runtime_dictionary(output: Path) -> None:
    """Keep only active Simplified candidates and pre-normalize their glosses."""
    core_words = active_core_words()
    overrides: dict[str, str] = {}
    for line in GLOSS_OVERRIDES.read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#"):
            headword, gloss = line.split("\t", 1)
            overrides[headword] = gloss
    rows: list[tuple[str, str]] = []
    seen: set[str] = set()
    source_date = ""
    for line in SHARED_DICTIONARY.read_text(encoding="utf-8").splitlines():
        if line.startswith("# Source date:"):
            source_date = line.split(":", 1)[1].strip()
        if not line or line.startswith("#"):
            continue
        headword, raw = line.split("\t", 1)
        if headword not in core_words:
            continue
        gloss = short_gloss(overrides.get(headword, raw))
        if gloss:
            rows.append((headword, gloss))
            seen.add(headword)

    # The small preferred-gloss table also serves as a controlled offline
    # supplement for confirmed modern terms that CC-CEDICT does not contain.
    for headword, raw in overrides.items():
        if headword in core_words and headword not in seen:
            gloss = short_gloss(raw)
            if gloss:
                rows.append((headword, gloss))

    with output.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("# Active Simplified Chinese candidate | pre-normalized short English gloss\n")
        handle.write("# Filtered from the shared CC-CEDICT extract for input_translate_core.\n")
        handle.write("# License: CC BY-SA 4.0 https://creativecommons.org/licenses/by-sa/4.0/\n")
        if source_date:
            handle.write(f"# Source date: {source_date}\n")
        for headword, gloss in rows:
            handle.write(f"{headword}\t{gloss}\n")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def copy_package() -> None:
    if PACKAGE_ROOT.exists():
        shutil.rmtree(PACKAGE_ROOT)
    shutil.copytree(SOURCE_ROOT, PACKAGE_ROOT)
    write_runtime_dictionary(PACKAGE_ROOT / "bilingual_english.tsv")
    shutil.copy2(GLOSS_OVERRIDES, PACKAGE_ROOT / "common_gloss_overrides.tsv")
    shutil.copy2(ENGLISH_CHINESE_DICTIONARY, PACKAGE_ROOT / "english_chinese.tsv")
    write_native_rime_dictionaries(PACKAGE_ROOT)
    shutil.copy2(PROJECT_LICENSE, PACKAGE_ROOT / "LICENSE")


def write_deterministic_zip(archive_path: Path) -> None:
    if archive_path.exists():
        archive_path.unlink()
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(PACKAGE_ROOT.rglob("*")):
            if not path.is_file():
                continue
            relative = path.relative_to(PACKAGE_ROOT).as_posix()
            info = zipfile.ZipInfo(f"{ARCHIVE_STEM}/{relative}", date_time=(2026, 8, 24, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)


def main() -> None:
    required = [
        SOURCE_ROOT,
        SHARED_DICTIONARY,
        GLOSS_OVERRIDES,
        ENGLISH_CHINESE_DICTIONARY,
        PROJECT_LICENSE,
        PLATFORM_ROOT / "upstream" / "rime-ice-base.full.dict.yaml",
    ]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise SystemExit("Missing build input: " + ", ".join(missing))

    build_common_base()
    copy_package()
    DIST_ROOT.mkdir(parents=True, exist_ok=True)
    archive_path = DIST_ROOT / f"{ARCHIVE_STEM}.zip"
    write_deterministic_zip(archive_path)
    digest = sha256(archive_path)
    hash_path = archive_path.with_suffix(archive_path.suffix + ".sha256")
    hash_path.write_text(f"{digest}  {archive_path.name}\n", encoding="ascii", newline="\n")
    print(f"Package: {archive_path}")
    print(f"SHA-256: {digest}")


if __name__ == "__main__":
    main()
