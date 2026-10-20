#!/usr/bin/env python3
"""앱 아이콘(1024×1024, 알파 없는 RGB PNG)과 asset catalog를 만든다. 표준 라이브러리만 쓴다.

    python3 ios/scripts/make_app_icon.py

App Store는 알파 채널이 있는 아이콘을 거부하므로(ITMS-90717) 색 형식 2(RGB)로 쓴다.
"""

import json
import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
TOP = (79, 163, 247)  # 하늘색
BOTTOM = (30, 79, 168)  # 짙은 파랑
CLOUD = (255, 255, 255)
DROP = (214, 240, 255)

CATALOG = Path(__file__).resolve().parent.parent / "WeatherBridge" / "Assets.xcassets"


def sd_circle(x, y, cx, cy, r):
    return math.hypot(x - cx, y - cy) - r


def sd_round_rect(x, y, x0, y0, x1, y1, r):
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    qx, qy = abs(x - cx) - hx, abs(y - cy) - hy
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    return outside + min(max(qx, qy), 0.0) - r


def sd_drop(x, y, cx, cy, r, h):
    """아래가 둥글고 위가 뾰족한 물방울 (끝이 둥근 비대칭 캡슐, 끝 반지름 4)."""
    px, py = abs(x - cx), cy - y  # 위쪽이 +
    r2 = 4.0
    b = (r - r2) / h
    a = math.sqrt(1.0 - b * b)
    k = -b * px + a * py
    if k < 0:
        return math.hypot(px, py) - r
    if k > a * h:
        return math.hypot(px, py - h) - r2
    return a * px + b * py - r


def smooth_min(a, b, k=14.0):
    """도형을 이을 때 이음매에 홈이 생기지 않도록 부드럽게 합친다."""
    h = max(k - abs(a - b), 0.0) / k
    return min(a, b) - h * h * k * 0.25


def cloud(x, y):
    # 바닥은 알약 모양, 원들은 그 위에 얹는다(원의 아래쪽이 바닥선보다 위에 있어야 혹이 생기지 않는다)
    d = sd_round_rect(x, y, 250, 470, 870, 610, 70)
    for cx, cy, r in ((400, 450, 130), (580, 390, 175), (730, 470, 120)):
        d = smooth_min(d, sd_circle(x, y, cx, cy, r))
    return d


DROPS = [(400, 790, 42, 105), (560, 850, 42, 105), (720, 790, 42, 105)]
# 위 좌표로 그린 그림을 화면 가운데로 옮기는 양
SHIFT_X, SHIFT_Y = 48, 30


def drops(x, y):
    return min(sd_drop(x, y, cx, cy, r, h) for cx, cy, r, h in DROPS)


def blend(base, color, cover):
    return tuple(round(b + (c - b) * cover) for b, c in zip(base, color))


def coverage(d):
    return min(max(0.5 - d, 0.0), 1.0)


def render():
    rows = []
    for y in range(SIZE):
        t = y / (SIZE - 1)
        bg = tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))
        row = bytearray(b"\x00")  # 필터 없음
        for x in range(SIZE):
            px, py = x + 0.5 + SHIFT_X, y + 0.5 + SHIFT_Y
            c = bg
            cd = coverage(drops(px, py))
            if cd:
                c = blend(c, DROP, cd)
            cc = coverage(cloud(px, py))
            if cc:
                c = blend(c, CLOUD, cc)
            row += bytes(c)
        rows.append(bytes(row))
    return b"".join(rows)


def png(raw):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8비트 RGB
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main():
    info = {"author": "xcode", "version": 1}
    icon_dir = CATALOG / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    (CATALOG / "Contents.json").write_text(json.dumps({"info": info}, indent=2) + "\n")
    (icon_dir / "Contents.json").write_text(
        json.dumps(
            {
                "images": [
                    {"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
                ],
                "info": info,
            },
            indent=2,
        )
        + "\n"
    )
    (icon_dir / "AppIcon.png").write_bytes(png(render()))
    print(f"wrote {icon_dir / 'AppIcon.png'}")


if __name__ == "__main__":
    main()
