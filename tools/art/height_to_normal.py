"""높이 맵(회색조 PNG, 밝을수록 높음) → 법선 맵 PNG (Godot/OpenGL 방식: 초록 = 위쪽, 평평한 곳 = 128,128,255).
도트 느낌을 지키려고 기울기를 몇 단계로 끊는다(--levels). 가장자리는 반대편과 이어서 계산해 이음매 없이 반복되는 질감에 맞다.

    python tools/art/height_to_normal.py art/world3d/wall/brick_h.png            # -> brick_n.png
    python tools/art/height_to_normal.py in.png out.png --strength 1.0 --levels 2

Pillow 만 필요하다(pip install pillow).
"""
import argparse
import math
import sys

# Windows 한국어 환경(cp949)에서 한글·기호 출력 시 UnicodeEncodeError 로 멈추지 않게 한다.
for _s in (sys.stdout, sys.stderr):
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")

from PIL import Image


def convert(height: Image.Image, strength: float = 1.0, levels: int = 2) -> Image.Image:
    h = height.convert("L")
    w, hh = h.size
    px = h.load()
    out = Image.new("RGB", (w, hh))
    op = out.load()

    def level(v: float) -> float:
        # 기울기를 -levels..+levels 의 정수 단계로 끊는다(levels=0 이면 끊지 않음).
        if levels <= 0:
            return v
        return max(-1.0, min(1.0, round(v * levels) / levels))

    for y in range(hh):
        for x in range(w):
            # Sobel (가장자리는 반대편으로 이어짐)
            def s(dx, dy):
                return px[(x + dx) % w, (y + dy) % hh] / 255.0

            gx = (s(1, -1) + 2 * s(1, 0) + s(1, 1)) - (s(-1, -1) + 2 * s(-1, 0) + s(-1, 1))
            gy = (s(-1, 1) + 2 * s(0, 1) + s(1, 1)) - (s(-1, -1) + 2 * s(0, -1) + s(1, -1))
            # Sobel 합은 최대 4 배라서 4로 나눈다. 오른쪽이 높으면 법선은 왼쪽(-x)으로 기운다.
            # 아래쪽이 낮으면(gy<0) 면이 아래를 향하므로 초록(위쪽 +)은 줄어든다.
            nx = level(-gx * strength / 4.0)
            ny = level(gy * strength / 4.0)
            nz = math.sqrt(max(0.0, 1.0 - min(1.0, nx * nx + ny * ny)))
            op[x, y] = (int(round((nx * 0.5 + 0.5) * 255)), int(round((ny * 0.5 + 0.5) * 255)), int(round((nz * 0.5 + 0.5) * 255)))

    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("output", nargs="?")
    ap.add_argument("--strength", type=float, default=1.0)
    ap.add_argument("--levels", type=int, default=2)
    a = ap.parse_args()
    out_path = a.output
    if not out_path:
        base = a.input[:-4] if a.input.lower().endswith(".png") else a.input
        out_path = (base[:-2] if base.endswith("_h") else base) + "_n.png"
    convert(Image.open(a.input), a.strength, a.levels).save(out_path)
    print(out_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
