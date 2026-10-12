#!/usr/bin/env python3
"""2D 스프라이트(건물·소품 그림)에서 법선 맵을 자동으로 만드는 도구(시제품).

  python tools/art/sprite_normal.py <스프라이트.png> [출력폴더] [--alpha 140] [--strength 1.0] [--levels 3]

- 높이 = (가장자리에서 안쪽으로 부드럽게 솟는 모양) × 0.55 + (그림의 밝기, 살짝 흐림) × 0.45.
  가장자리가 둥글게 받는 빛 + 밝게 칠한 윗면이 높게 읽히는 효과를 낸다. 정확한 3D 형상이 아니라 "빛이 들어오는 느낌" 용 근사다.
- 알파가 --alpha 미만인 픽셀(번짐·광채)은 투명으로 잘라 내고, 그림 영역(bbox)만 잘라 저장한다.
- 출력: <이름>_d.png(잘라낸 그림), <이름>_n.png(법선 맵, Godot/OpenGL 방식: 평평 = 128,128,255).
Pillow 만 필요하다.
"""
import argparse
import math
import os
import sys

for _s in (sys.stdout, sys.stderr):
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")

from PIL import Image, ImageFilter


def build(im: Image.Image, alpha_cut: int = 140, strength: float = 1.0, levels: int = 3):
    im = im.convert("RGBA")
    a = im.getchannel("A").point(lambda v: 255 if v >= alpha_cut else 0)
    box = a.getbbox()
    if box is None:
        raise SystemExit("그림 영역이 없음(알파가 모두 %d 미만)" % alpha_cut)
    im = im.crop(box)
    a = a.crop(box)
    r, g, b, _ = im.split()
    diffuse = Image.merge("RGBA", (r, g, b, a))

    # 가장자리 둥글림: 마스크를 흐리게 해서 안쪽일수록 높게(바깥에서 7px 안쪽에서 포화)
    bevel = a.filter(ImageFilter.GaussianBlur(5)).point(lambda v: min(255, int(v * 1.25)))
    # 밝기: 약한 흐림으로 도트 잡음을 줄이고 큰 명암만 남긴다
    lum = im.convert("RGB").convert("L").filter(ImageFilter.GaussianBlur(1.2))
    height = Image.blend(bevel, lum, 0.45)
    w, h = height.size
    hp = height.load()
    mp = a.load()
    normal = Image.new("RGB", (w, h), (128, 128, 255))
    npx = normal.load()

    def lv(v):
        if levels <= 0:
            return v
        return max(-1.0, min(1.0, round(v * levels) / levels))

    def s(x, y):
        return hp[min(max(x, 0), w - 1), min(max(y, 0), h - 1)] / 255.0

    for y in range(h):
        for x in range(w):
            if mp[x, y] == 0:
                continue
            gx = (s(x + 1, y - 1) + 2 * s(x + 1, y) + s(x + 1, y + 1)) - (s(x - 1, y - 1) + 2 * s(x - 1, y) + s(x - 1, y + 1))
            gy = (s(x - 1, y + 1) + 2 * s(x, y + 1) + s(x + 1, y + 1)) - (s(x - 1, y - 1) + 2 * s(x, y - 1) + s(x + 1, y - 1))
            nx = lv(-gx * strength * 2.0 / 4.0)
            ny = lv(gy * strength * 2.0 / 4.0)
            nz = math.sqrt(max(0.0, 1.0 - min(1.0, nx * nx + ny * ny)))
            npx[x, y] = (int(round((nx * 0.5 + 0.5) * 255)), int(round((ny * 0.5 + 0.5) * 255)), int(round((nz * 0.5 + 0.5) * 255)))

    return diffuse, normal


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sprite")
    ap.add_argument("outdir", nargs="?", default=".")
    ap.add_argument("--alpha", type=int, default=140)
    ap.add_argument("--strength", type=float, default=1.0)
    ap.add_argument("--levels", type=int, default=3)
    a = ap.parse_args()
    name = os.path.splitext(os.path.basename(a.sprite))[0]
    diffuse, normal = build(Image.open(a.sprite), a.alpha, a.strength, a.levels)
    os.makedirs(a.outdir, exist_ok=True)
    diffuse.save(os.path.join(a.outdir, name + "_d.png"))
    normal.save(os.path.join(a.outdir, name + "_n.png"))
    print("저장: %s_d.png / %s_n.png (%dx%d)" % (name, name, diffuse.width, diffuse.height))
    return 0


if __name__ == "__main__":
    sys.exit(main())
