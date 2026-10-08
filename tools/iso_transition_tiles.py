"""등각 경계 타일(모서리 4개 기준 16장)을 정리한 바닥 타일 두 종으로 합성한다. 생성 0회.

타일 안 픽셀 (x,y) -> 마름모 좌표 (u,v) in [0,1]: 위 꼭짓점 N=(0,0), 오른쪽 E=(1,0), 아래 S=(1,1), 왼쪽 W=(0,1).
값 = 네 모서리 값의 쌍선형 보간 + 주기 1인 물결 잡음. 0.5 이상이면 위쪽 지형(잔디).
잡음이 u,v에 대해 주기 1이라 이웃 타일의 맞닿는 변에서 값이 같다 -> 이음새 없음.
파일명 비트 순서: N E S W (1 = 잔디).
"""
import math, os, random
from PIL import Image, ImageDraw

SRC = r"C:/Users/john9/OneDrive/Documents/project222/docs/그림_작업/받은그림/바닥_등각/정리"
OUT = r"C:/Users/john9/OneDrive/Documents/project222/docs/그림_작업/받은그림/바닥_등각/경계"
os.makedirs(OUT, exist_ok=True)
inside = lambda x, y: abs(x - 31.5) / 32 + abs(y - 15.5) / 16 <= 1


def uv(x, y):
    sx = (x - 31.5) / 32
    sy = (y - 15.5) / 16
    return (sx + sy + 1) / 2, (sy - sx + 1) / 2


def noise(u, v):
    t = 2 * math.pi
    return (0.5 * math.sin(t * (2 * u + v) + 1.3) + 0.35 * math.sin(t * (u - 3 * v) + 0.4)
            + 0.25 * math.sin(t * (4 * u + 2 * v) + 2.1) + 0.2 * math.sin(t * (5 * v - u) + 0.7)) / 1.3


def field(bits, x, y):
    n, e, s, w = bits
    u, v = uv(x, y)
    # bilinear over the (u,v) square: N(0,0) E(1,0) S(1,1) W(0,1)
    val = n * (1 - u) * (1 - v) + e * u * (1 - v) + s * u * v + w * (1 - u) * v
    if 0 < sum(bits) < 4:
        val += 0.22 * noise(u, v)
    return val


def darker(c, f):
    return tuple(int(ch * f) for ch in c[:3]) + (255,)


def make(upper, lower, bits):
    out = Image.new("RGBA", (64, 32), (0, 0, 0, 0))
    up = upper.load(); lo = lower.load(); px = out.load()
    is_up = {}
    for y in range(32):
        for x in range(64):
            if inside(x, y):
                is_up[(x, y)] = field(bits, x, y) >= 0.5
    for (x, y), u in is_up.items():
        if u:
            # grass pixel touching path (looking down/sideways) -> dark fringe
            edge = any(is_up.get((x + dx, y + dy), True) is False for dx, dy in ((0, 1), (1, 0), (-1, 0)))
            px[x, y] = darker(up[x, y], 0.72) if edge else up[x, y]
        else:
            # path pixel right under grass -> soft shadow
            shade = is_up.get((x, y - 1), False) or is_up.get((x, y - 2), False)
            px[x, y] = darker(lo[x, y], 0.85) if shade else lo[x, y]
    return out


PAIRS = [("grass", "dirt"), ("grass", "road"), ("grass", "paving")]
ALL = [tuple((i >> k) & 1 for k in (3, 2, 1, 0)) for i in range(16)]
sets = {}
for upn, lon in PAIRS:
    upper = Image.open(f"{SRC}/{upn}_1.png").convert("RGBA")
    lower = Image.open(f"{SRC}/{lon}_1.png").convert("RGBA")
    d = f"{OUT}/{upn}_{lon}"
    os.makedirs(d, exist_ok=True)
    tiles = {}
    for b in ALL:
        t = make(upper, lower, b)
        t.save(f"{d}/{''.join(map(str, b))}.png")
        tiles[b] = t
    sets[(upn, lon)] = tiles

# 데모: 꼭짓점 격자에 지형을 칠하고 타일을 고른다(구불구불한 길 + 광장)
random.seed(11)
G = 12
demo_imgs = []
for (upn, lon), tiles in sets.items():
    vert = [[1] * (G + 1) for _ in range(G + 1)]
    for i in range(G + 1):  # 대각선으로 지나는 길
        c = int(G / 2 + 2.5 * math.sin(i / 2.2))
        for j in range(c - 1, c + 2):
            if 0 <= j <= G:
                vert[i][j] = 0
    for i in range(2, 5):  # 작은 공터
        for j in range(8, 11):
            vert[i][j] = 0
    W, H = G * 64 + 16, G * 32 + 30
    img = Image.new("RGBA", (W, H), (40, 36, 32, 255))
    for s in range(2 * G - 1):
        for i in range(G):
            j = s - i
            if 0 <= j < G:
                b = (vert[i][j], vert[i + 1][j], vert[i + 1][j + 1], vert[i][j + 1])
                img.alpha_composite(tiles[b], (W // 2 + (i - j) * 32 - 32, 8 + (i + j) * 16))
    ImageDraw.Draw(img).text((6, H - 16), f"{upn} / {lon}", fill=(255, 255, 255))
    demo_imgs.append(img)
sheet = Image.new("RGBA", (demo_imgs[0].width * 3, demo_imgs[0].height), (40, 36, 32, 255))
for k, im in enumerate(demo_imgs):
    sheet.alpha_composite(im, (k * im.width, 0))
sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(f"{OUT}/_경계_데모.png")

# 16장 낱장 시트
st = Image.new("RGBA", (16 * 68, 3 * 40), (40, 36, 32, 255))
for r, tiles in enumerate(sets.values()):
    for c, b in enumerate(ALL):
        st.alpha_composite(tiles[b], (c * 68 + 2, r * 40 + 4))
st.resize((st.width * 2, st.height * 2), Image.NEAREST).save(f"{OUT}/_경계_16장.png")
print("ok")
