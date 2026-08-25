#!/usr/bin/env python3
"""Smoke-test the installed schema through Weasel's real librime C API."""

from __future__ import annotations

import ctypes as C
import os
import shutil
from pathlib import Path


WEASEL_ROOT = Path(r"C:\Program Files\Rime\weasel-0.17.4")
DLL = WEASEL_ROOT / "rime.dll"
SHARED = WEASEL_ROOT / "data"
USER_SOURCE = Path(os.environ["APPDATA"]) / "Rime"
LOGS = Path(os.environ["LOCALAPPDATA"]) / "InputTranslate" / "windows-rime" / "smoke-logs"
USER = LOGS.parent / "smoke-user"


class Traits(C.Structure):
    _fields_ = [
        ("data_size", C.c_int), ("shared_data_dir", C.c_void_p), ("user_data_dir", C.c_void_p),
        ("distribution_name", C.c_void_p), ("distribution_code_name", C.c_void_p),
        ("distribution_version", C.c_void_p), ("app_name", C.c_void_p), ("modules", C.c_void_p),
        ("min_log_level", C.c_int), ("log_dir", C.c_void_p), ("prebuilt_data_dir", C.c_void_p),
        ("staging_dir", C.c_void_p),
    ]


class Composition(C.Structure):
    _fields_ = [
        ("length", C.c_int), ("cursor_pos", C.c_int), ("sel_start", C.c_int),
        ("sel_end", C.c_int), ("preedit", C.c_void_p),
    ]


class Candidate(C.Structure):
    _fields_ = [("text", C.c_void_p), ("comment", C.c_void_p), ("reserved", C.c_void_p)]


class Menu(C.Structure):
    _fields_ = [
        ("page_size", C.c_int), ("page_no", C.c_int), ("is_last_page", C.c_int),
        ("highlighted_candidate_index", C.c_int), ("num_candidates", C.c_int),
        ("candidates", C.POINTER(Candidate)), ("select_keys", C.c_void_p),
    ]


class Context(C.Structure):
    _fields_ = [
        ("data_size", C.c_int), ("composition", Composition), ("menu", Menu),
        ("commit_text_preview", C.c_void_p), ("select_labels", C.c_void_p),
    ]


def decode(pointer: int) -> str:
    return C.string_at(pointer).decode("utf-8") if pointer else ""


def main() -> None:
    LOGS.mkdir(parents=True, exist_ok=True)
    # Never attach a second librime process to the user's live LevelDB.  Build
    # an isolated smoke-test user directory from deployed, read-only inputs.
    # This keeps real selection frequencies and learned phrases untouched.
    if USER.exists():
        shutil.rmtree(USER)
    USER.mkdir(parents=True)
    for source in USER_SOURCE.iterdir():
        if source.is_file():
            shutil.copy2(source, USER / source.name)
    for directory in ("build", "cn_dicts", "lua"):
        source = USER_SOURCE / directory
        if source.exists():
            shutil.copytree(source, USER / directory)

    dll = C.CDLL(str(DLL))
    dll.RimeSetup.argtypes = [C.POINTER(Traits)]
    dll.RimeInitialize.argtypes = [C.POINTER(Traits)]
    dll.RimeCreateSession.restype = C.c_size_t
    dll.RimeSelectSchema.argtypes = [C.c_size_t, C.c_char_p]
    dll.RimeSelectSchema.restype = C.c_int
    dll.RimeProcessKey.argtypes = [C.c_size_t, C.c_int, C.c_int]
    dll.RimeProcessKey.restype = C.c_int
    dll.RimeGetCurrentSchema.argtypes = [C.c_size_t, C.c_char_p, C.c_size_t]
    dll.RimeGetCurrentSchema.restype = C.c_int
    dll.RimeGetContext.argtypes = [C.c_size_t, C.POINTER(Context)]
    dll.RimeGetContext.restype = C.c_int
    dll.RimeFreeContext.argtypes = [C.POINTER(Context)]
    dll.RimeDestroySession.argtypes = [C.c_size_t]

    buffers: list[C.Array] = []

    def pointer(value: str):
        buffer = C.create_string_buffer(value.encode("utf-8") + b"\0")
        buffers.append(buffer)
        return C.cast(buffer, C.c_void_p)

    traits = Traits()
    traits.data_size = C.sizeof(Traits) - C.sizeof(C.c_int)
    traits.shared_data_dir = pointer(str(SHARED))
    traits.user_data_dir = pointer(str(USER))
    traits.distribution_name = pointer("Weasel")
    traits.distribution_code_name = pointer("Weasel")
    traits.distribution_version = pointer("0.17.4")
    traits.app_name = pointer("rime.input_translate_smoke")
    traits.min_log_level = 1
    traits.log_dir = pointer(str(LOGS))
    dll.RimeSetup(C.byref(traits))
    dll.RimeInitialize(C.byref(traits))

    def context_for(code: str, schema: bytes = b"bilingual_pinyin") -> tuple[str, list[tuple[str, str]]]:
        session = dll.RimeCreateSession()
        try:
            assert session and dll.RimeSelectSchema(session, schema)
            for byte in code.encode("ascii"):
                assert dll.RimeProcessKey(session, byte, 0)
            context = Context()
            context.data_size = C.sizeof(Context) - C.sizeof(C.c_int)
            assert dll.RimeGetContext(session, C.byref(context))
            try:
                return decode(context.composition.preedit), [
                    (decode(context.menu.candidates[index].text), decode(context.menu.candidates[index].comment))
                    for index in range(context.menu.num_candidates)
                ]
            finally:
                dll.RimeFreeContext(C.byref(context))
        finally:
            if session:
                dll.RimeDestroySession(session)

    def candidates_for(code: str) -> list[tuple[str, str]]:
        return context_for(code)[1]

    def commit_first(code: str) -> None:
        session = dll.RimeCreateSession()
        try:
            assert session and dll.RimeSelectSchema(session, b"bilingual_pinyin")
            for byte in code.encode("ascii"):
                assert dll.RimeProcessKey(session, byte, 0)
            assert dll.RimeProcessKey(session, 32, 0)
        finally:
            if session:
                dll.RimeDestroySession(session)

    def commit_second_then_first(code: str) -> None:
        session = dll.RimeCreateSession()
        try:
            assert session and dll.RimeSelectSchema(session, b"bilingual_pinyin")
            for byte in code.encode("ascii"):
                assert dll.RimeProcessKey(session, byte, 0)
            assert dll.RimeProcessKey(session, ord("2"), 0)
            assert dll.RimeProcessKey(session, 32, 0)
        finally:
            if session:
                dll.RimeDestroySession(session)

    def verify_f4_toggle() -> tuple[str, str]:
        session = dll.RimeCreateSession()
        try:
            assert session and dll.RimeSelectSchema(session, b"bilingual_pinyin")
            schema_id = C.create_string_buffer(128)
            assert dll.RimeProcessKey(session, 0xFFC1, 0)  # XK_F4
            assert dll.RimeGetCurrentSchema(session, schema_id, len(schema_id))
            after_first = schema_id.value.decode("utf-8")
            assert after_first == "bilingual_sogou", after_first
            assert dll.RimeProcessKey(session, 0xFFC1, 0)
            assert dll.RimeGetCurrentSchema(session, schema_id, len(schema_id))
            after_second = schema_id.value.decode("utf-8")
            assert after_second == "bilingual_pinyin", after_second
            return after_first, after_second
        finally:
            if session:
                dll.RimeDestroySession(session)

    try:
        dongxi = candidates_for("dongxi")
        assert ("东西", "thing, stuff") in dongxi, dongxi

        modern = candidates_for("meifense")
        assert any(text == "玫粉色" for text, _ in modern), modern

        english = candidates_for("translate")
        assert english == [("translate", "翻译")], english
        school = candidates_for("school")
        assert school == [("school", "学校")], school

        pinyin = candidates_for("you")
        assert pinyin and pinyin[0][0] != "you", pinyin

        clean = candidates_for("xuexiao")
        texts = [text for text, _ in clean]
        assert texts and texts[0] == "学校", clean
        assert {"雪鸮", "穴鸮", "雪下", "削下"}.isdisjoint(texts), clean

        incomplete = candidates_for("cesh")
        assert incomplete and incomplete[0][0] == "测试", incomplete
        assert all(text != "cesh" for text, _ in incomplete), incomplete

        joined = candidates_for("erqiet")
        assert any(text.startswith("而且") for text, _ in joined), joined
        assert all(text != "erqiet" for text, _ in joined), joined

        sentence = candidates_for("meiyouxindedongxi")
        assert any(text == "没有新的东西" for text, _ in sentence), sentence

        exercise = candidates_for("gongjianbu")
        assert any(text == "弓箭步" for text, _ in exercise), exercise

        hip_thrust = candidates_for("tuntui")
        assert ("臀推", "hip thrust") in hip_thrust, hip_thrust
        mochi = candidates_for("mashu")
        assert ("麻薯", "mochi") in mochi, mochi
        glute_bridge = candidates_for("tunqiao")
        assert ("臀桥", "glute bridge") in glute_bridge, glute_bridge
        taro_paste = candidates_for("yuni")
        assert ("芋泥", "taro paste") in taro_paste, taro_paste

        repeated = candidates_for("dangdangyixia")

        preedit, _ = context_for("zaiyiqi")
        assert preedit == "zai'yi'qi", preedit

        sogou_preedit, sogou = context_for("nihk", b"bilingual_sogou")
        assert any(text == "你好" for text, _ in sogou), (sogou_preedit, sogou)
        assert sogou_preedit == "ni'hao", sogou_preedit

        f4_toggle = verify_f4_toggle()

        # Verify first-use phrase learning, then restore the user's data.
        personal_phrases = USER / "input_translate_personal_phrases.tsv"
        personal_version = USER / "input_translate_personal_phrases.version"
        personal_existed = personal_phrases.exists()
        version_existed = personal_version.exists()
        personal_before = personal_phrases.read_bytes() if personal_existed else b""
        version_before = personal_version.read_bytes() if version_existed else b""
        try:
            commit_second_then_first("dangdangyixia")
            learned = personal_phrases.read_text(encoding="utf-8")
            assert any(line.startswith("dangdangyixia\t") for line in learned.splitlines()), learned
        finally:
            if personal_existed:
                personal_phrases.write_bytes(personal_before)
            elif personal_phrases.exists():
                personal_phrases.unlink()
            if version_existed:
                personal_version.write_bytes(version_before)
            elif personal_version.exists():
                personal_version.unlink()

        print("dongxi=", dongxi)
        print("meifense=", modern)
        print("translate=", english)
        print("school=", school)
        print("you=", pinyin)
        print("xuexiao=", clean)
        print("cesh=", incomplete)
        print("erqiet=", joined)
        print("meiyouxindedongxi=", sentence)
        print("gongjianbu=", exercise)
        print("tuntui=", hip_thrust)
        print("mashu=", mochi)
        print("tunqiao=", glute_bridge)
        print("yuni=", taro_paste)
        print("dangdangyixia=", repeated)
        print("preedit=", preedit)
        print("sogou_nihk=", sogou_preedit, sogou)
        print("f4_toggle=", f4_toggle)
        print("INPUTENG_REAL_RIME_SMOKE_PASSED")
    finally:
        dll.RimeFinalize()


if __name__ == "__main__":
    main()
