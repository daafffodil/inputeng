#!/usr/bin/env python3
"""Generate the deterministic inputeng Windows language-profile icon.

The icon intentionally uses only Python's standard library so release builds do
not depend on Pillow or ImageMagick.  Each ICO frame is stored as a PNG image.
"""

from __future__ import annotations

import binascii
import struct
import zlib
from pathlib import Path


PLATFORM_ROOT = Path(__file__).resolve().parents[1]
OUTPUT = PLATFORM_ROOT / "src" / "branding" / "inputeng.ico"
PREVIEW = PLATFORM_ROOT / "src" / "branding" / "inputeng-preview.png"
SIZES = (16, 20, 24, 32, 40, 48, 64, 256)
ACCENT = (236, 72, 153)


def chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF)
    )


def png(width: int, height: int, rgba: bytes) -> bytes:
    rows = b"".join(
        b"\x00" + rgba[y * width * 4 : (y + 1) * width * 4]
        for y in range(height)
    )
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows, 9))
        + chunk(b"IEND", b"")
    )


def inside_rounded_square(x: float, y: float, size: int) -> bool:
    inset = size * 0.06
    radius = size * 0.22
    left, top = inset, inset
    right, bottom = size - inset, size - inset
    if left + radius <= x <= right - radius or top + radius <= y <= bottom - radius:
        return left <= x <= right and top <= y <= bottom
    cx = left + radius if x < left + radius else right - radius
    cy = top + radius if y < top + radius else bottom - radius
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius**2


def inside_e(x: float, y: float, size: int) -> bool:
    left = size * 0.29
    right = size * 0.72
    middle_right = size * 0.65
    top = size * 0.23
    bottom = size * 0.77
    stroke = max(1.0, size * 0.105)
    vertical = left <= x <= left + stroke and top <= y <= bottom
    top_bar = left <= x <= right and top <= y <= top + stroke
    middle_y = size * 0.5 - stroke * 0.5
    middle_bar = left <= x <= middle_right and middle_y <= y <= middle_y + stroke
    bottom_bar = left <= x <= right and bottom - stroke <= y <= bottom
    return vertical or top_bar or middle_bar or bottom_bar


def render(size: int) -> bytes:
    samples = 4
    pixels = bytearray()
    for py in range(size):
        for px in range(size):
            accent_hits = 0
            white_hits = 0
            for sy in range(samples):
                for sx in range(samples):
                    x = px + (sx + 0.5) / samples
                    y = py + (sy + 0.5) / samples
                    if inside_rounded_square(x, y, size):
                        accent_hits += 1
                        if inside_e(x, y, size):
                            white_hits += 1
            total = samples * samples
            alpha = round(255 * accent_hits / total)
            if accent_hits:
                white_mix = white_hits / accent_hits
                red = round(ACCENT[0] * (1 - white_mix) + 255 * white_mix)
                green = round(ACCENT[1] * (1 - white_mix) + 255 * white_mix)
                blue = round(ACCENT[2] * (1 - white_mix) + 255 * white_mix)
            else:
                red = green = blue = 0
            pixels.extend((red, green, blue, alpha))
    return png(size, size, bytes(pixels))


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    frames = [(size, render(size)) for size in SIZES]
    header = struct.pack("<HHH", 0, 1, len(frames))
    offset = 6 + 16 * len(frames)
    entries = []
    payloads = []
    for size, payload in frames:
        dimension = 0 if size == 256 else size
        entries.append(
            struct.pack(
                "<BBBBHHII",
                dimension,
                dimension,
                0,
                0,
                1,
                32,
                len(payload),
                offset,
            )
        )
        payloads.append(payload)
        offset += len(payload)
    OUTPUT.write_bytes(header + b"".join(entries) + b"".join(payloads))
    PREVIEW.write_bytes(frames[-1][1])
    print(OUTPUT)


if __name__ == "__main__":
    main()
