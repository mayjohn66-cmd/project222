#!/usr/bin/env python3
"""정면 그림을 아이소메트릭 벽면(2:1 기울기)에 맞게 기울입니다.

문처럼 마름모 타일의 한 변에 서는 오브젝트용입니다. 기본 결과는 52x124이고,
`\\` 방향(왼쪽이 높고 오른쪽이 낮음)입니다. 게임이 회전에 따라 좌우를 뒤집어 `/`로 그립니다.

사용법:
  python tools/iso_shear.py 정면문.png 출력.png [--width 52] [--height 99] [--slope 0.5] [--flip]
  - 입력은 정면에서 본 문(문틀 포함)을 투명 배경으로 만든 그림.
  - 입력을 최근접 방식으로 (width x (height - 기울어 내려가는 높이))로 맞춘 뒤 열마다 아래로 민다.
  - --flip 은 `/` 방향이 필요할 때(시험용).
"""
import argparse
from PIL import Image


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--width", type=int, default=52)
    ap.add_argument("--height", type=int, default=124)
    ap.add_argument("--slope", type=float, default=0.5, help="가로 1칸당 세로 이동(2:1 = 0.5)")
    ap.add_argument("--flip", action="store_true")
    a = ap.parse_args()

    drop = round((a.width - 1) * a.slope)
    body_h = a.height - drop
    img = Image.open(a.src).convert("RGBA")
    # 투명 여백을 잘라 문 영역만 남긴다.
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    img = img.resize((a.width, body_h), Image.NEAREST)
    out = Image.new("RGBA", (a.width, a.height), (0, 0, 0, 0))
    src_px, dst_px = img.load(), out.load()
    for x in range(a.width):
        shift = round(x * a.slope)
        for y in range(body_h):
            p = src_px[x, y]
            if p[3] >= 128:
                dst_px[x, y + shift] = (p[0], p[1], p[2], 255)
    if a.flip:
        out = out.transpose(Image.FLIP_LEFT_RIGHT)
    out.save(a.dst)
    print(f"저장: {a.dst} ({a.width}x{a.height}, 내려가는 높이 {drop}px, 문 본체 {body_h}px)")


if __name__ == "__main__":
    main()
