"""등각 바닥 기준 타일(64x32 마름모) 위에 작은 장식만 얹어 변형 타일을 만든다. 생성 0회.

바탕 무늬는 그대로 두고 꽃·풀포기·자갈·이끼·금 같은 작은 점 그림만 찍는다.
장식은 마름모 가장자리에서 떨어진 곳에만 찍어 이웃 타일과의 이음새를 건드리지 않는다.

사용: python tools/art/iso_tile_decor.py
입력: docs/그림_작업/받은그림/바닥_등각/정리/<종류>_1.png
출력: docs/그림_작업/받은그림/바닥_등각/변형/<종류>_1.png(기준) ~ _4.png, 미리보기 _변형_반복.png
"""
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "그림_작업", "받은그림", "바닥_등각")
SRC = os.path.join(ROOT, "정리")
OUT = os.path.join(ROOT, "변형")

# 작은 점 그림. 글자 하나가 픽셀 하나, '.'은 비움. 글자 뜻은 각 종류의 색표에서 정한다.
SPRITES = {
    "flower": [".p.", "pyp", ".p."],
    "flower2": [".w.", "wyw", ".w."],
    "flower_pair": [".p...", "pyp.w", ".p.wy", "....w"],
    "tuft": ["d.d", "dgd", ".d."],
    "tuft2": ["d..d", ".dd.", ".gd."],
    "pebble": [".hh", "sss", ".kk"],
    "pebble2": ["hh.", "ss.", "kk.", "..h", "..k"],
    "sprout": ["g.g", ".g."],
    "crack": ["k...", ".k..", ".kk.", "...k"],
    "moss": [".m.", "mmm", "m.m"],
    "leaf": ["oo", "oO"],
    "scuff": ["kkk.", "..kk"],
    "knot": [".kk.", "kOOk", ".kk."],
    "nail": ["h", "k"],
    "shine": ["w.", ".w"],
}

# 종류별: 색표(글자 -> RGB)와 변형 3장에 쓸 장식 목록(장식 이름, 개수)
KINDS = {
    "grass": {
        "colors": {"p": (236, 140, 170), "w": (245, 242, 230), "y": (250, 214, 90), "d": (58, 110, 52), "g": (96, 156, 70)},
        "variants": [[("flower", 2), ("flower2", 1)], [("tuft", 2), ("tuft2", 1)], [("flower_pair", 1), ("tuft", 1)]],
    },
    "dirt": {
        "colors": {"h": (196, 180, 160), "s": (150, 136, 120), "k": (96, 84, 72), "g": (100, 150, 70)},
        "variants": [[("pebble", 2)], [("sprout", 2), ("pebble2", 1)], [("pebble2", 1), ("pebble", 1)]],
    },
    "road": {
        "colors": {"k": (52, 34, 40), "m": (92, 130, 70), "h": (200, 170, 150), "s": (150, 120, 110)},
        "variants": [[("pebble", 2)], [("moss", 2)], [("pebble2", 1), ("moss", 1)]],
    },
    "paving": {
        "colors": {"k": (120, 104, 100), "m": (110, 150, 80), "o": (214, 140, 60), "O": (170, 96, 40)},
        "variants": [[("moss", 2)], [("crack", 1)], [("leaf", 1), ("moss", 1)]],
    },
    "wood": {
        "colors": {"k": (92, 56, 34), "O": (150, 98, 60), "h": (210, 200, 180)},
        "variants": [[("knot", 1)], [("nail", 3)], [("knot", 1), ("nail", 2)]],
    },
    "tile": {
        "colors": {"k": (190, 180, 168), "w": (255, 255, 250)},
        "variants": [[("scuff", 1)], [("shine", 2)], [("scuff", 1), ("shine", 1)]],
    },
}

MARGIN = 0.72  # 마름모 거리 값이 이보다 작은 곳(가장자리에서 충분히 안쪽)에만 찍는다


def dist(x, y):
    return abs(x - 31.5) / 32 + abs(y - 15.5) / 16


def stamp(img, sprite, colors, rng, taken):
    px = img.load()
    h, w = len(sprite), len(sprite[0])
    for _ in range(200):
        x0 = rng.randint(4, 63 - w - 4)
        y0 = rng.randint(2, 31 - h - 2)
        cells = [(x0 + dx, y0 + dy) for dy in range(h) for dx in range(w) if sprite[dy][dx] != "."]
        if all(dist(x, y) < MARGIN for x, y in cells) and not any(abs(x0 - tx) < 7 and abs(y0 - ty) < 4 for tx, ty in taken):
            for dy in range(h):
                for dx in range(w):
                    ch = sprite[dy][dx]
                    if ch != "." and ch in colors:
                        px[x0 + dx, y0 + dy] = colors[ch] + (255,)
            taken.append((x0, y0))
            return True
    return False


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(21)
    made = {}
    for kind, spec in KINDS.items():
        base = Image.open(os.path.join(SRC, f"{kind}_1.png")).convert("RGBA")
        base.save(os.path.join(OUT, f"{kind}_1.png"))
        tiles = [base]
        for i, deco in enumerate(spec["variants"]):
            t = base.copy()
            taken = []
            for name, count in deco:
                for _ in range(count):
                    stamp(t, SPRITES[name], spec["colors"], rng, taken)
            t.save(os.path.join(OUT, f"{kind}_{i + 2}.png"))
            tiles.append(t)
        made[kind] = tiles

    # 미리보기: 기준 70%, 변형 3장이 10%씩
    N = 7
    W, H = N * 64, N * 32
    sheet = Image.new("RGBA", (3 * (W + 10), 2 * (H + 24)), (40, 36, 32, 255))
    d = ImageDraw.Draw(sheet)
    prng = random.Random(5)
    for idx, (kind, tiles) in enumerate(made.items()):
        ox = (idx % 3) * (W + 10)
        oy = (idx // 3) * (H + 24) + 14
        for i in range(N):
            for j in range(N):
                t = prng.choices(tiles, weights=[7, 1, 1, 1])[0]
                sheet.alpha_composite(t, (ox + W // 2 + (i - j) * 32 - 32, oy + (i + j) * 16))
        d.text((ox + 4, oy - 12), kind, fill=(255, 255, 255))
    sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(os.path.join(ROOT, "_변형_반복.png"))
    print("ok", sum(len(t) for t in made.values()), "tiles")


if __name__ == "__main__":
    main()
