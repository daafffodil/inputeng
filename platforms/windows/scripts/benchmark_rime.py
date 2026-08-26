#!/usr/bin/env python3
"""Measure installed inputeng per-key latency through Weasel's librime C API."""

from __future__ import annotations

import argparse
import ctypes as C
import os
import shutil
import statistics
import time
from pathlib import Path


WEASEL_ROOT = Path(r"C:\Program Files\Rime\weasel-0.17.4")
DLL = WEASEL_ROOT / "rime.dll"
SHARED = WEASEL_ROOT / "data"
DEFAULT_SOURCE = Path(os.environ["APPDATA"]) / "Rime"
BENCH_ROOT = Path(os.environ["LOCALAPPDATA"]) / "InputTranslate" / "windows-rime" / "latency-bench"


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


def percentile(values: list[float], quantile: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, round((len(ordered) - 1) * quantile))]


def prepare_isolated_user(source: Path) -> Path:
    target = BENCH_ROOT / "current"
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)
    for item in source.iterdir():
        if item.is_file():
            shutil.copy2(item, target / item.name)
    for name in ("build", "cn_dicts", "lua"):
        item = source / name
        if item.exists():
            shutil.copytree(item, target / name)
    return target


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repeats", type=int, default=40)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--max-p95-ms", type=float)
    args = parser.parse_args()
    if args.repeats < 4:
        raise SystemExit("--repeats must be at least 4")
    if not DLL.exists():
        raise SystemExit(f"Weasel librime not found: {DLL}")

    user = prepare_isolated_user(args.source)
    logs = user / "logs"
    logs.mkdir()
    dll = C.CDLL(str(DLL))
    dll.RimeSetup.argtypes = [C.POINTER(Traits)]
    dll.RimeInitialize.argtypes = [C.POINTER(Traits)]
    dll.RimeCreateSession.restype = C.c_size_t
    dll.RimeSelectSchema.argtypes = [C.c_size_t, C.c_char_p]
    dll.RimeSelectSchema.restype = C.c_int
    dll.RimeProcessKey.argtypes = [C.c_size_t, C.c_int, C.c_int]
    dll.RimeProcessKey.restype = C.c_int
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
    traits.user_data_dir = pointer(str(user))
    traits.distribution_name = pointer("Weasel")
    traits.distribution_code_name = pointer("Weasel")
    traits.distribution_version = pointer("0.17.4")
    traits.app_name = pointer("rime.inputeng_latency_bench")
    traits.min_log_level = 2
    traits.log_dir = pointer(str(logs))

    start = time.perf_counter()
    dll.RimeSetup(C.byref(traits))
    dll.RimeInitialize(C.byref(traits))
    initialize_ms = (time.perf_counter() - start) * 1000

    create_times: list[float] = []
    key_times: list[float] = []
    first_key_times: list[float] = []
    codes = ("shurufaceshi", "zaiyiqi", "meiyouxindedongxi", "gongjianbu")
    try:
        for repeat in range(args.repeats):
            code = codes[repeat % len(codes)]
            start = time.perf_counter()
            session = dll.RimeCreateSession()
            assert session and dll.RimeSelectSchema(session, b"bilingual_pinyin")
            create_times.append((time.perf_counter() - start) * 1000)
            try:
                for position, byte in enumerate(code.encode("ascii")):
                    start = time.perf_counter()
                    assert dll.RimeProcessKey(session, byte, 0)
                    context = Context()
                    context.data_size = C.sizeof(Context) - C.sizeof(C.c_int)
                    assert dll.RimeGetContext(session, C.byref(context))
                    dll.RimeFreeContext(C.byref(context))
                    elapsed = (time.perf_counter() - start) * 1000
                    key_times.append(elapsed)
                    if position == 0:
                        first_key_times.append(elapsed)
            finally:
                dll.RimeDestroySession(session)
    finally:
        dll.RimeFinalize()

    key_p95 = percentile(key_times, 0.95)
    print(f"initialize_ms={initialize_ms:.2f}")
    print(
        "session_create_select "
        f"p50={statistics.median(create_times):.2f} p95={percentile(create_times, 0.95):.2f} "
        f"max={max(create_times):.2f}"
    )
    print(
        "all_key_plus_context "
        f"p50={statistics.median(key_times):.3f} p95={key_p95:.3f} max={max(key_times):.3f}"
    )
    print(
        "first_key_plus_context "
        f"p50={statistics.median(first_key_times):.3f} "
        f"p95={percentile(first_key_times, 0.95):.3f} max={max(first_key_times):.3f}"
    )
    if args.max_p95_ms is not None and key_p95 > args.max_p95_ms:
        raise SystemExit(f"per-key p95 {key_p95:.3f} ms exceeds {args.max_p95_ms:.3f} ms")


if __name__ == "__main__":
    main()
