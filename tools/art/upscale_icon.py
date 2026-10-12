#!/usr/bin/env python3
"""작은 격자(16/32px)로 만든 픽셀 아이콘을 64x64로 정수 배 확대한다.

Pixel Lab 등에서 32x32(또는 16x16)로 만든 PNG를 받아 최근접 방식으로 정확히
2배(4배) 키워 64x64로 저장한다. 흐려지지 않고 도트가 굵게 유지된다.
반투명(알파)은 0 또는 255로 정리한다.

사용:
  python tools/art/upscale_icon.py 입력.png                # 같은 이름으로 art/items/pixel_v1/ 에 저장
  python tools/art/upscale_icon.py 입력.png -o 출력.png
  python tools/art/upscale_icon.py a.png b.png --out-dir art/items/pixel_v1
Pillow 필요: pip install pillow
"""
import argparse
import os
import sys

from PIL import Image

TARGET = 64


def convert(src: str, dst: str) -> str:
    img = Image.open(src).convert("RGBA")
    w, h = img.size
    if w != h:
        return f"실패: 정사각형이 아님 ({w}x{h})"
    if TARGET % w != 0:
        return f"실패: 크기 {w}가 64의 약수가 아님 (16, 32, 64만 지원)"
    # 반투명 정리: 알파 128 이상이면 불투명
    px = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255) if a >= 128 else (0, 0, 0, 0)
    out = img if w == TARGET else img.resize((TARGET, TARGET), Image.NEAREST)
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    out.save(dst)
    data = out.get_flattened_data() if hasattr(out, "get_flattened_data") else out.getdata()
    colors = len({p for p in data if p[3]})
    return f"완료: {w}x{w} -> 64x64, 색 {colors}개 -> {dst}"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("-o", "--output", help="입력이 1개일 때 출력 파일")
    ap.add_argument("--out-dir", default="art/items/pixel_v1")
    args = ap.parse_args()
    if args.output and len(args.inputs) != 1:
        print("-o는 입력이 1개일 때만 쓸 수 있습니다.")
        return 2
    bad = 0
    for src in args.inputs:
        dst = args.output or os.path.join(args.out_dir, os.path.basename(src))
        msg = convert(src, dst)
        print(f"{os.path.basename(src)}: {msg}")
        bad += msg.startswith("실패")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
