#!/usr/bin/env python3
"""반복(이음매) 면 질감이 어긋남 없이 이어지는지 보려고 3x3 으로 이어 붙인 미리보기를 만든다(4배 확대).

  python tools/preview_tiles.py 그림.png            → 그림_tiled.png
"""
import os
import sys

# Windows 한국어 환경(cp949)에서 한글·기호 출력 시 UnicodeEncodeError 로 멈추지 않게 한다.
for _s in (sys.stdout, sys.stderr):
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")

from PIL import Image


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = sys.argv[1]
    im = Image.open(src).convert("RGB")
    out = Image.new("RGB", (im.width * 3, im.height * 3))
    for y in range(3):
        for x in range(3):
            out.paste(im, (x * im.width, y * im.height))
    out = out.resize((out.width * 4, out.height * 4), Image.NEAREST)
    dst = os.path.splitext(src)[0] + "_tiled.png"
    out.save(dst)
    print(dst)


if __name__ == "__main__":
    main()
